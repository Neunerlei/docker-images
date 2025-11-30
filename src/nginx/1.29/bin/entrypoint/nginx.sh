#!/bin/bash

echo "[ENTRYPOINT.nginx] Starting Nginx configuration process...";

render_filtered_templates_in_dir "${NGINX_CUSTOM_TEMPLATE_DIR}" "${NGINX_SERVICE_SNIPPET_DIR}" "*.conf"
render_template_all_vars "${NGINX_TEMPLATE_DIR}/nginx.conf" "$NGINX_DIR/nginx.conf"
render_template_all_vars "${NGINX_TEMPLATE_DIR}/mime.custom.types" "$NGINX_DIR/mime.custom.types"

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

  render_template_all_vars "$NGINX_TEMPLATE_DIR/default.https.nginx.conf" "/etc/nginx/sites-available/default"
else
  echo "[ENTRYPOINT.nginx] Configuring for plain HTTP.";
  render_template_all_vars "$NGINX_TEMPLATE_DIR/default.nginx.conf" "/etc/nginx/sites-available/default"
fi

# Enable the default site
ln -sf "/etc/nginx/sites-available/default" "/etc/nginx/sites-enabled/default";

echo "[ENTRYPOINT.nginx] Nginx configuration completed";
