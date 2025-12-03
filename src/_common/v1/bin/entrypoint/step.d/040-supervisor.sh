#!/bin/bash

if [[ "${feature_registry}" == *"supervisor"* ]]; then
  echo "[ENTRYPOINT.supervisor] Configuring Supervisor...";

  render_template "${SUPERVISOR_TEMPLATE_DIR}/supervisord.conf" "${SUPERVISOR_DIR}/supervisord.conf"

  rm -rf "${SUPERVISOR_CONFIG_DIR}/*.conf"

  render_filtered_templates_in_dir "${SUPERVISOR_CONFIG_TEMPLATE_DIR}" "${SUPERVISOR_CONFIG_DIR}" "*.conf"
fi
