#!/bin/bash

# Clean the active Supervisor config directory on every run.
rm -f /etc/supervisor/conf.d/*.conf

if [ "${CONTAINER_MODE}" == "web" ]; then
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor for web mode";

  # Enable nginx service
  ln -sf /etc/app/config.tpl/supervisor/nginx.service.conf /etc/supervisor/conf.d/zzz-nginx.conf;

  # Enable node service
  render_template 'NODE_WEB_COMMAND' /etc/app/config.tpl/supervisor/node.service.tpl.conf /etc/supervisor/conf.d/zzz-node.conf

  echo "[ENTRYPOINT.supervisor] Supervisor configuration completed for web mode";
else
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor for worker mode";

  render_template 'NODE_WORKER_COMMAND NODE_WORKER_PROCESS_COUNT' /etc/app/config.tpl/worker.service.template.conf /etc/supervisor/conf.d/zzz-node-worker.conf

  echo "[ENTRYPOINT.supervisor] Supervisor configuration completed for worker mode";
fi
