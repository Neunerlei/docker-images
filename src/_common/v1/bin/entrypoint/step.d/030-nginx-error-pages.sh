#!/bin/bash

if [[ "${feature_registry}" == *"nginx"* ]]; then

  echo "[ENTRYPOINT.nginx-error-pages] Rendering custom Nginx error pages";

  _render_error() {
    local ERROR_CODE="$1"
    local ERROR_TITLE="$2"
    local ERROR_DESCRIPTION="$3"
    render_template "${NGINX_TEMPLATE_DIR}/errorPage.html" "${NGINX_ERRORS_DIR}/${ERROR_CODE}.html"
    render_template "${NGINX_TEMPLATE_DIR}/errorPage.json" "${NGINX_ERRORS_DIR}/${ERROR_CODE}.json"
  }

  _render_error "400" "400 Bad Request" "The server could not understand the request due to invalid syntax."
  _render_error "401" "401 Unauthorized" "The request requires user authentication."
  _render_error "403" "403 Forbidden" "You do not have permission to access the requested resource."
  _render_error "404" "404 Not Found" "The requested resource could not be found on this server."
  _render_error "500" "500 Internal Server Error" "The server encountered an internal error and was unable to complete your request."
  _render_error "502" "502 Bad Gateway" "The server received an invalid response from the upstream server."
  _render_error "503" "503 Service Unavailable" "The server is currently unable to handle the request due to maintenance."
  _render_error "504" "504 Gateway Timeout" "The server did not receive a timely response from the upstream server."

  render_template "${NGINX_TEMPLATE_DIR}/service.errors.nginx.conf" "${NGINX_SNIPPET_DIR}/service.errors.nginx.conf"
fi
