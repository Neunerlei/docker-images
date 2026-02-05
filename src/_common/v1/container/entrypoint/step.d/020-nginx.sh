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

if [[ "${feature_registry}" == *"nginx"* ]]; then
    echo "[ENTRYPOINT.nginx] Starting Nginx configuration process..."

    process_tpl "nginx-conf"
    process_tpl "nginx-mime-types"
    process_tpl "nginx-snippets-root"
    process_tpl "nginx-custom-snippets"
    process_tpl "nginx-custom-snippets-global"

    if [ "${DOCKER_SERVICE_PROTOCOL}" == "https" ]; then
        echo "[ENTRYPOINT.nginx] Configuring for HTTPS."
        process_tpl "ssl" _process_ssl_cert_templates
        process_tpl "nginx-snippets-global-default" _process_nginx_default_ssl_conf
    else
        echo "[ENTRYPOINT.nginx] Configuring for plain HTTP."
        process_tpl "nginx-snippets-global-default" _process_nginx_default_http_conf
    fi
fi
