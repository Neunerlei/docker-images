#!/bin/bash

echo "[ENTRYPOINT.export-vars] Propagating known variables to default shell config";

rm -rf "${CONTAINER_VARS_SCRIPT}"
touch "${CONTAINER_VARS_SCRIPT}"

declare -g -A exported_vars_map=()

for var_name in $(get_all_vars); do
  var_value="${!var_name}"
  exported_vars_map["$var_name"]="${var_value}"
  echo " - Exporting variable: ${var_name}=\"$(mask_var "${var_name}" "${var_value}")\""
  echo "export ${var_name}=\"${var_value}\"" >> "${CONTAINER_VARS_SCRIPT}"
done
