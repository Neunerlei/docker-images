#!/bin/bash

if [[ "${feature_registry}" == *"nginx"* ]]; then
  echo "[ENTRYPOINT.nginx] Starting Nginx configuration process...";

  render_filtered_templates_in_dir "${NGINX_CUSTOM_TEMPLATE_DIR}" "${NGINX_SERVICE_SNIPPET_DIR}" "*.conf"
  render_filtered_templates_in_dir "${NGINX_CUSTOM_GLOBAL_TEMPLATE_DIR}" "${NGINX_GLOBAL_SNIPPET_DIR}" "*.conf"
  render_template "${NGINX_TEMPLATE_DIR}/service.root.nginx.conf" "${NGINX_SNIPPET_DIR}/service.root.nginx.conf"
  render_template "${NGINX_TEMPLATE_DIR}/nginx.conf" "${NGINX_DIR}/nginx.conf"
  render_template "${NGINX_TEMPLATE_DIR}/mime.custom.types" "${NGINX_DIR}/mime.custom.types"

  if [ "${DOCKER_SERVICE_PROTOCOL}" == "https" ]; then
    echo "[ENTRYPOINT.nginx] Configuring for HTTPS.";

    # Ensure our expected certificates are in place
    if [ ! -f "${NGINX_CERT_PATH}" ]; then
      echo "[ENTRYPOINT.nginx] ERROR: SSL Certificate not found at ${NGINX_CERT_PATH}.";
    fi
    if [ ! -f "${NGINX_KEY_PATH}" ]; then
      echo "[ENTRYPOINT.nginx] ERROR: SSL Key not found at ${NGINX_KEY_PATH}.";
    fi

    render_template "${NGINX_TEMPLATE_DIR}/default.https.nginx.conf" "${NGINX_SITES_AVAILABLE_DIR}/default"
  else
    echo "[ENTRYPOINT.nginx] Configuring for plain HTTP.";
    render_template "${NGINX_TEMPLATE_DIR}/default.nginx.conf" "${NGINX_SITES_AVAILABLE_DIR}/default"
  fi

  # Enable the default site
  ln -sf "${NGINX_SITES_AVAILABLE_DIR}/default" "${NGINX_SITES_ENABLED_DIR}/default";
fi
