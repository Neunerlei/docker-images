#!/bin/bash
if [ "${CONTAINER_MODE}" == "web" ]; then
  echo "[ENTRYPOINT.nginx] Configuring nginx for web mode";

  render_template 'NGINX_CLIENT_MAX_BODY_SIZE NGINX_DOC_ROOT NODE_SERVICE_PORT' /etc/app/config.tpl/nginx/service.snippet.tpl.nginx.conf /etc/nginx/snippets/service.nginx.conf
  render_template_dir 'DOCKER_PROJECT_HOST DOCKER_PROJECT_PROTOCOL DOCKER_PROJECT_PATH DOCKER_SERVICE_PROTOCOL DOCKER_SERVICE_PATH DOCKER_SERVICE_ABS_PATH NGINX_DOC_ROOT' \
    /etc/nginx/snippets/before.d \
    /etc/nginx/snippets/after.d \
    /etc/nginx/snippets/before.https.d \
    /etc/nginx/snippets/after.https.d

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

    render_template 'NGINX_CERT_PATH NGINX_KEY_PATH' /etc/app/config.tpl/nginx/default.https.tpl.nginx.conf /etc/nginx/sites-available/default
  else
    echo "[ENTRYPOINT.nginx] Configuring for plain HTTP.";
    cat /etc/app/config.tpl/nginx/default.tpl.nginx.conf > /etc/nginx/sites-available/default
  fi

  # Enable the default site
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default;

  echo "[ENTRYPOINT.nginx] Nginx configuration completed";
fi
