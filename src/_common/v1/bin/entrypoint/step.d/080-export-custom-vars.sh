#!/bin/bash

echo "[ENTRYPOINT.export-custom-vars] Checking for new or changed environment variables...";

declare changed_vars=()
for var_name in $(get_all_vars); do
  var_value="${!var_name}"
  if [[ ! -v exported_vars_map["$var_name"] ]] || [[ "$var_value" != "${exported_vars_map["$var_name"]}" ]]; then
    changed_vars+=("$var_name")
  fi
done

# If there are any changes, export the new or changed variables
if [ ${#changed_vars[@]} -gt 0 ]; then
  echo "[ENTRYPOINT.export-custom-vars] Detected changes in environment variables, exporting new/changed variables:";
  for var_name in "${changed_vars[@]}"; do
    var_value="${!var_name}"
    echo " - Exporting variable: ${var_name}=\"${var_value}\""
    echo "export ${var_name}=\"${var_value}\"" >> "${CONTAINER_VARS_SCRIPT}"
  done
fi
