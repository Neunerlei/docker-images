#!/bin/bash

echo "[ENTRYPOINT.export-custom-vars] Checking for new or changed environment variables...";

# Re-run the pattern registration before the change detection: custom
# entrypoint scripts (step 080) run AFTER step 050 and can export new
# credential variables — those must be excluded here as well, not just the
# ones that already existed at 050 (the function deduplicates, so the second
# call is idempotent).
register_basic_auth_credential_vars

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
    # Same exclusion as step 050: entrypoint-only basic auth credential
    # variables (entrypoint_only_vars_registry) never reach the
    # container-vars.sh snapshot (or the log), no matter when the variable
    # appeared or changed during the boot
    for registered_var in "${entrypoint_only_vars_registry[@]}"; do
      if [[ "${var_name}" == "${registered_var}" ]]; then
        echo " - Not exporting variable: ${var_name} (clear-text basic auth credentials — used only to generate the password files during boot; intentionally not exported to later RUN steps or exec shells)"
        continue 2
      fi
    done
    echo " - Exporting variable: ${var_name}=\"$(mask_var "${var_name}" "${var_value}")\""
    printf "export %s=%q\n" "$var_name" "$var_value" >> "${CONTAINER_VARS_SCRIPT}"
  done
fi
