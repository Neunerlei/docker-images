#!/bin/bash

_process_ssl_cert_templates() {
    local output_path="$1"
    # First check if there is a directory $CONTAINER_CUSTOM_SSL_CERTS_DIR that contains cert.pem and key.pem
    # If so, we copy them to the work directory
    # If not, we must create self-signed certificates and place them there and show a warning
    if [ -d "${CONTAINER_CUSTOM_SSL_CERTS_DIR}" ] && [ -f "${CONTAINER_CUSTOM_SSL_CERTS_DIR}/cert.pem" ] && [ -f "${CONTAINER_CUSTOM_SSL_CERTS_DIR}/key.pem" ]; then
        echo "[ENTRYPOINT.nginx] Found custom SSL certificates in ${CONTAINER_CUSTOM_SSL_CERTS_DIR}, copying to work directory."
        cp "${CONTAINER_CUSTOM_SSL_CERTS_DIR}/cert.pem" "${output_path}/cert.pem"
        cp "${CONTAINER_CUSTOM_SSL_CERTS_DIR}/key.pem" "${output_path}/key.pem"
    else
        echo "[ENTRYPOINT.nginx] WARNING: No custom SSL certificates found in ${CONTAINER_CUSTOM_SSL_CERTS_DIR}. Generating self-signed certificates."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${output_path}/key.pem" \
            -out "${output_path}/cert.pem" \
            -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com"
    fi
}

_process_nginx_default_ssl_conf() {
    local output_path="$1"
    render_template "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/default.https.nginx.conf" "${output_path}"
}

_process_nginx_default_http_conf() {
    local output_path="$1"
    render_template "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/default.nginx.conf" "${output_path}"
}

_render_nginx_error() {
    local ERROR_CODE="$1"
    local ERROR_TITLE="$2"
    local ERROR_DESCRIPTION="$3"
    local output_path="$4"

    local htmlTplName="errorPage.html"
    local jsonTplName="errorPage.json"

    # Look into the custom tpl directory first
    local htmlTplPath="${CONTAINER_CUSTOM_NGINX_DIR}/${htmlTplName}"
    local jsonTplPath="${CONTAINER_CUSTOM_NGINX_DIR}/${jsonTplName}"

    if [ ! -f "${htmlTplPath}" ]; then
        htmlTplPath="${CONTAINER_TEMPLATES_DIR}/nginx/${htmlTplName}"
    fi
    if [ ! -f "${jsonTplPath}" ]; then
        jsonTplPath="${CONTAINER_TEMPLATES_DIR}/nginx/${jsonTplName}"
    fi

    render_template "${htmlTplPath}" "${output_path}/${ERROR_CODE}.html"
    render_template "${jsonTplPath}" "${output_path}/${ERROR_CODE}.json"
}

_process_nginx_error_pages() {
    echo "[ENTRYPOINT.nginx] Rendering custom Nginx error pages"
    _render_nginx_error "400" "400 Bad Request" "The server could not understand the request due to invalid syntax." "$1"
    _render_nginx_error "401" "401 Unauthorized" "The request requires user authentication." "$1"
    _render_nginx_error "403" "403 Forbidden" "You do not have permission to access the requested resource." "$1"
    _render_nginx_error "404" "404 Not Found" "The requested resource could not be found on this server." "$1"
    _render_nginx_error "500" "500 Internal Server Error" "The server encountered an internal error and was unable to complete your request." "$1"
    _render_nginx_error "502" "502 Bad Gateway" "The server received an invalid response from the upstream server." "$1"
    _render_nginx_error "503" "503 Service Unavailable" "The server is currently unable to handle the request due to maintenance." "$1"
    _render_nginx_error "504" "504 Gateway Timeout" "The server did not receive a timely response from the upstream server." "$1"
}

if [[ "${feature_registry}" == *"nginx"* ]]; then
    echo "[ENTRYPOINT.nginx] Starting Nginx configuration process..."

    process_tpl "nginx-conf"
    process_tpl "nginx-mime-types"
    process_tpl "nginx-snippets-root"
    process_tpl "nginx-snippets-resolver"
    process_tpl "nginx-custom-snippets"
    process_tpl "nginx-custom-snippets-global"
    process_tpl "nginx-error-pages" _process_nginx_error_pages
    process_tpl "nginx-snippets-errors"

    if [ "${DOCKER_SERVICE_PROTOCOL}" == "https" ]; then
        echo "[ENTRYPOINT.nginx] Configuring for HTTPS."
        process_tpl "ssl" _process_ssl_cert_templates
        process_tpl "nginx-snippets-global-default" _process_nginx_default_ssl_conf
    else
        echo "[ENTRYPOINT.nginx] Configuring for plain HTTP."
        process_tpl "nginx-snippets-global-default" _process_nginx_default_http_conf
    fi
fi
