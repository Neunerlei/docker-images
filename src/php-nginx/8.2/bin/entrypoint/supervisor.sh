#!/bin/bash

# Clean the active Supervisor config directory on every run.
rm -f /etc/supervisor/conf.d/*.conf

render_template_all_vars "$SUPERVISOR_TEMPLATE_DIR/supervisord.conf" "/etc/supervisor/supervisord.conf"

if [ "${CONTAINER_MODE}" == "web" ]; then
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor for web mode";

  render_template_all_vars "$SUPERVISOR_TEMPLATE_DIR/nginx.service.conf" "$SUPERVISOR_CONFIG_DIR/zzz-nginx.conf"
  render_template_all_vars "$SUPERVISOR_TEMPLATE_DIR/php-fpm.service.conf" "$SUPERVISOR_CONFIG_DIR/zzz-php-fpm.conf"

  echo "[ENTRYPOINT.supervisor] Supervisor configuration completed for web mode";
else
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor for worker mode";

  render_template_all_vars "$SUPERVISOR_TEMPLATE_DIR/worker.service.conf" "$SUPERVISOR_CONFIG_DIR/zzz-php-worker.conf"

  echo "[ENTRYPOINT.supervisor] Supervisor configuration completed for worker mode";
fi
