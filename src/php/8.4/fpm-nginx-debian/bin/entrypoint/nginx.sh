#!/bin/bash
if [ "${CONTAINER_MODE}" == "web" ]; then
  echo "[ENTRYPOINT.nginx] Configuring nginx for web mode";

  render_template 'NGINX_CLIENT_MAX_BODY_SIZE' /etc/app/config.tpl/nginx/service.snippet.tpl.nginx.conf /etc/nginx/snippets/service.nginx.conf

  if [ "${DOCKER_PROJECT_PROTOCOL}" == "https" ]; then
    echo "[ENTRYPOINT.nginx] Configuring for HTTPS.";

    # Ensure our expected certificates are in place
    if [ ! -f $NGINX_CERT_PATH ]; then
      echo "[ENTRYPOINT.nginx] ERROR: SSL Certificate not found at ${NGINX_CERT_PATH}.";
      exit 1;
    fi
    if [ ! -f $NGINX_KEY_PATH ]; then
      echo "[ENTRYPOINT.nginx] ERROR: SSL Key not found at ${NGINX_KEY_PATH}.";
      exit 1;
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
