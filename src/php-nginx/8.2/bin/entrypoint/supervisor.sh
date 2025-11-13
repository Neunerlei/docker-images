#!/bin/bash

# Clean the active Supervisor config directory on every run.
rm -f /etc/supervisor/conf.d/*.conf

if [ "${CONTAINER_MODE}" == "web" ]; then
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor for web mode";

  # Enable nginx and php-fpm services
  ln -sf /etc/app/config.tpl/supervisor/nginx.service.conf /etc/supervisor/conf.d/zzz-nginx.conf;
  ln -sf /etc/app/config.tpl/supervisor/php-fpm.service.conf /etc/supervisor/conf.d/zzz-php-fpm.conf;

  echo "[ENTRYPOINT.supervisor] Supervisor configuration completed for web mode";
else
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor for worker mode";

  render_template 'PHP_WORKER_COMMAND PHP_WORKER_PROCESS_COUNT' /etc/app/config.tpl/worker.service.template.conf /etc/supervisor/conf.d/zzz-php-worker.conf

  echo "[ENTRYPOINT.supervisor] Supervisor configuration completed for worker mode";
fi
