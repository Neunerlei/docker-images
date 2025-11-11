#!/bin/bash
if [ "${CONTAINER_MODE}" == "web" ]; then
  echo "[ENTRYPOINT.nginx] Configuring nginx for web mode";

  VARS_TO_SUBSTITUTE='$NGINX_CLIENT_MAX_BODY_SIZE'
  envsubst "$VARS_TO_SUBSTITUTE" < /etc/app/config.tpl/nginx/service.snippet.tpl.nginx.conf > /etc/nginx/snippets/service.nginx.conf

  if [ "${DOCKER_PROJECT_INSTALLED}" == "true" ]; then
    echo "[ENTRYPOINT.nginx] Project is installed. Configuring for HTTPS. WARNING: THIS IS NOT A PRODUCTION-READY SSL CONFIGURATION -> DEVELOPMENT USE ONLY!";

    # Ensure our expected self-signed certificates are in place
    if [ ! -f /var/www/certs/cert.pem ] || [ ! -f /var/www/certs/key.pem ]; then
      echo "[ENTRYPOINT.nginx] ERROR: Self-signed certificates not found in /var/www/certs/. Expected cert.pem and key.pem files.";
      exit 1;
    fi

    cat /etc/app/config.tpl/nginx/default.https.tpl.nginx.conf > /etc/nginx/sites-available/default
  else
    echo "[ENTRYPOINT.nginx] Project is not installed. Configuring for plain HTTP.";
    cat /etc/app/config.tpl/nginx/default.tpl.nginx.conf > /etc/nginx/sites-available/default
  fi

  # Enable the default site
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default;

  echo "[ENTRYPOINT.nginx] Nginx configuration completed";
fi
