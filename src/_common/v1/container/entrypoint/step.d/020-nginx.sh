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

    # Ensure the generated or copied certificates are owned by www-data
    chown -R www-data:www-data "${output_path}"
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

# Configures global NGINX basic authentication from environment variables:
#   NGINX_BASIC_AUTH="username clear-password"      the first user
#   NGINX_BASIC_AUTH_1, NGINX_BASIC_AUTH_2, ...     additional users
#   NGINX_BASIC_AUTH_REALM                          optional realm shown in the login dialog
#
# When at least one user is configured, the password file is written to
# ${NGINX_BASIC_AUTH_DIR}/default.htpasswd and the "auth_basic" directives are written
# to the "nginx-snippets-basic-auth" template target (${NGINX_SNIPPETS_DIR}/basicAuth.nginx.conf,
# symlinked into the work directory) — an include file the server templates always
# include (an empty include is valid NGINX). The authentication then applies to the
# whole server; a custom snippet can still take ownership with its own "auth_basic"
# directive (see below), or opt out with "auth_basic off;".
#
# The password files of the per-proxy authentication (PROXY_<KEY>_BASIC_AUTH, handled
# in the nginx image) live in ${NGINX_BASIC_AUTH_DIR}, so it is reset here on every
# boot — this step always runs before the proxy configuration.
_configure_nginx_basic_auth() {
    # Start from a clean slate, so users or proxies that were removed from the
    # environment since the last boot do not leave their password files behind
    rm -rf "${NGINX_BASIC_AUTH_DIR}"
    mkdir -p "${NGINX_BASIC_AUTH_DIR}"

    # The include file must always exist, so it starts with the "not configured" variant
    printf '# basic auth is not configured\n' > "${NGINX_SNIPPETS_DIR}/basicAuth.nginx.conf"

    local -a credentials=()
    mapfile -t credentials < <(collect_basic_auth_credentials "NGINX_BASIC_AUTH")

    if [[ ${#credentials[@]} -eq 0 ]]; then
        return 0
    fi

    echo "[ENTRYPOINT.nginx] Configuring global basic auth for ${#credentials[@]} user(s)..."

    local auth_file="${NGINX_BASIC_AUTH_DIR}/default.htpasswd"
    if ! write_basic_auth_file "${auth_file}" "${credentials[@]}"; then
        echo "[ENTRYPOINT.nginx] Error: Invalid NGINX_BASIC_AUTH / NGINX_BASIC_AUTH_<n> value. Aborting." >&2
        exit 1
    fi

    local auth_directives
    if ! auth_directives="$(build_basic_auth_directives "${NGINX_BASIC_AUTH_REALM:-Restricted}" "${auth_file}")"; then
        echo "[ENTRYPOINT.nginx] Error: Invalid NGINX_BASIC_AUTH_REALM value. Aborting." >&2
        exit 1
    fi
    printf '%s\n' "${auth_directives}" > "${NGINX_SNIPPETS_DIR}/basicAuth.nginx.conf"

    # NGINX_BASIC_AUTH_FILE is deliberately a plain shell variable (not "local", not
    # exported): it must stay visible to the template rendering (which reads it via
    # get_all_vars) without polluting the environment
    NGINX_BASIC_AUTH_FILE="${auth_file}"
}

if [[ "${feature_registry}" == *"nginx"* ]]; then
    echo "[ENTRYPOINT.nginx] Starting Nginx configuration process..."

    # Basic auth first: it resets the password file directory and prepares the
    # auth_basic include file consumed by the server templates
    NGINX_BASIC_AUTH_FILE=""
    _configure_nginx_basic_auth

    process_tpl "nginx-conf"
    process_tpl "nginx-mime-types"
    process_tpl "nginx-snippets-root"
    process_tpl "nginx-snippets-resolver"
    process_tpl "nginx-custom-snippets"
    process_tpl "nginx-custom-snippets-global"
    process_tpl "nginx-custom-snippets-location"
    process_tpl "nginx-error-pages" _process_nginx_error_pages
    process_tpl "nginx-snippets-errors"

    # NGINX does not allow "auth_basic" twice in the same context. If a custom
    # server-level snippet declares its own, it takes ownership of the
    # authentication and we empty the generated include file instead.
    # (The generated password file is still written, so the snippet may
    # reference it via ${NGINX_BASIC_AUTH_FILE}.)
    if grep -qsE '^\s*auth_basic' "${NGINX_SNIPPETS_DIR}/basicAuth.nginx.conf" && grep -qsE '^\s*auth_basic' "${NGINX_CUSTOM_SNIPPETS_DIR}"/*.conf; then
        echo "[ENTRYPOINT.nginx] A custom server snippet declares its own 'auth_basic' — skipping the generated NGINX_BASIC_AUTH directives."
        printf '# basic auth is managed by a custom server snippet\n' > "${NGINX_SNIPPETS_DIR}/basicAuth.nginx.conf"
    fi

    if [ "${DOCKER_SERVICE_PROTOCOL}" == "https" ]; then
        echo "[ENTRYPOINT.nginx] Configuring for HTTPS."
        process_tpl "ssl" _process_ssl_cert_templates
        process_tpl "nginx-snippets-global-default" _process_nginx_default_ssl_conf
    else
        echo "[ENTRYPOINT.nginx] Configuring for plain HTTP."
        process_tpl "nginx-snippets-global-default" _process_nginx_default_http_conf
    fi
fi
