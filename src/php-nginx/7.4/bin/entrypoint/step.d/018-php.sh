#!/bin/bash
echo "[ENTRYPOINT.php] Configuring PHP";

render_filtered_templates_in_dir "${PHP_TEMPLATE_DIR}" "${PHP_CONFIG_DIR}" "*.ini"
render_filtered_templates_in_dir "${PHP_CUSTOM_TEMPLATE_DIR}" "${PHP_CONFIG_DIR}" "*.ini"
render_filtered_templates_in_dir "${PHP_TEMPLATE_DIR}" "${PHP_FPM_CONFIG_DIR}" "*.conf"
render_filtered_templates_in_dir "${PHP_CUSTOM_TEMPLATE_DIR}" "${PHP_FPM_CONFIG_DIR}" "*.conf"

echo "[ENTRYPOINT.php] PHP configuration completed";
