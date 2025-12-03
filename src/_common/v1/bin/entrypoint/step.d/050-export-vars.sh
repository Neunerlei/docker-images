#!/bin/bash

echo "[ENTRYPOINT.export-vars] Propagating known variables to default shell config";

rm -rf "${CONTAINER_VARS_SCRIPT}"
touch "${CONTAINER_VARS_SCRIPT}"

for var_name in $(get_all_vars); do
  # Ignore vars starting with lowercase letters or underscore
  if [[ ! "$var_name" =~ ^[A-Z] ]]; then
    continue
  fi
  var_value="${!var_name}"
  echo " - Exporting variable: ${var_name}=\"${var_value}\""
  echo "export ${var_name}=\"${var_value}\"" >> "${CONTAINER_VARS_SCRIPT}"
done
