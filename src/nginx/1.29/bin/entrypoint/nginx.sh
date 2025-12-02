#!/bin/bash

echo "[ENTRYPOINT.nginx] Starting Nginx configuration process...";

render_filtered_templates_in_dir "${NGINX_CUSTOM_TEMPLATE_DIR}" "${NGINX_SERVICE_SNIPPET_DIR}" "*.conf"
render_filtered_templates_in_dir "${NGINX_CUSTOM_GLOBAL_TEMPLATE_DIR}" "${NGINX_GLOBAL_SNIPPET_DIR}" "*.conf"
render_template "${NGINX_TEMPLATE_DIR}/nginx.conf" "$NGINX_DIR/nginx.conf"
render_template "${NGINX_TEMPLATE_DIR}/mime.custom.types" "$NGINX_DIR/mime.custom.types"

if [ "${DOCKER_SERVICE_PROTOCOL}" == "https" ]; then
  echo "[ENTRYPOINT.nginx] Configuring for HTTPS.";

    LEGACY_NGINX_CERT_PATH="/var/www/certs/cert.pem"
    LEGACY_NGINX_KEY_PATH="/var/www/certs/key.pem"

    # Ensure our expected certificates are in place
    if [ ! -f "$NGINX_CERT_PATH" ]; then
      if [ -f "$LEGACY_NGINX_CERT_PATH" ]; then
        echo "[ENTRYPOINT.nginx] WARNING: Using legacy SSL Certificate path at ${LEGACY_NGINX_CERT_PATH}. Please update your configuration to use NGINX_CERT_PATH environment variable.";
        export NGINX_CERT_PATH="$LEGACY_NGINX_CERT_PATH"
      else
        echo "[ENTRYPOINT.nginx] ERROR: SSL Certificate not found at ${NGINX_CERT_PATH}.";
        exit 1;
      fi
    fi
    if [ ! -f "$NGINX_KEY_PATH" ]; then
      if [ -f "$LEGACY_NGINX_KEY_PATH" ]; then
        echo "[ENTRYPOINT.nginx] WARNING: Using legacy SSL Key path at ${LEGACY_NGINX_KEY_PATH}. Please update your configuration to use NGINX_KEY_PATH environment variable.";
        export NGINX_KEY_PATH="$LEGACY_NGINX_KEY_PATH"
      else
        echo "[ENTRYPOINT.nginx] ERROR: SSL Key not found at ${NGINX_KEY_PATH}.";
        exit 1;
      fi
    fi

  render_template "$NGINX_TEMPLATE_DIR/default.https.nginx.conf" "$NGINX_DIR/sites-available/default"
else
  echo "[ENTRYPOINT.nginx] Configuring for plain HTTP.";
  render_template "$NGINX_TEMPLATE_DIR/default.nginx.conf" "$NGINX_DIR/sites-available/default"
fi

# Enable the default site
ln -sf "$NGINX_DIR/sites-available/default" "$NGINX_DIR/sites-enabled/default";

# Render standard error pages
echo "[ENTRYPOINT.nginx] Rendering standard error pages to '/var/www/errors/'";
_render_error() {
  local ERROR_CODE="$1"
  local ERROR_TITLE="$2"
  local ERROR_DESCRIPTION="$3"
  render_template "${NGINX_TEMPLATE_DIR}/errorPage.html" "/var/www/errors/${ERROR_CODE}.html"
  render_template "${NGINX_TEMPLATE_DIR}/errorPage.json" "/var/www/errors/${ERROR_CODE}.json"
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

echo "[ENTRYPOINT.nginx] Nginx configuration completed";
