#!/bin/bash

if [[ "${feature_registry}" == *"nginx"* ]]; then

    echo "[ENTRYPOINT.nginx-error-pages] Rendering custom Nginx error pages"

    _render_error() {
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
        _render_error "400" "400 Bad Request" "The server could not understand the request due to invalid syntax." "$1"
        _render_error "401" "401 Unauthorized" "The request requires user authentication." "$1"
        _render_error "403" "403 Forbidden" "You do not have permission to access the requested resource." "$1"
        _render_error "404" "404 Not Found" "The requested resource could not be found on this server." "$1"
        _render_error "500" "500 Internal Server Error" "The server encountered an internal error and was unable to complete your request." "$1"
        _render_error "502" "502 Bad Gateway" "The server received an invalid response from the upstream server." "$1"
        _render_error "503" "503 Service Unavailable" "The server is currently unable to handle the request due to maintenance." "$1"
        _render_error "504" "504 Gateway Timeout" "The server did not receive a timely response from the upstream server." "$1"
    }

    process_tpl "nginx-error-pages" _process_nginx_error_pages
    process_tpl "nginx-snippets-errors"
fi
