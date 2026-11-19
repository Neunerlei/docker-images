#!/bin/bash

echo "[ENTRYPOINT.export-vars] Propagating known variables to default shell config";

# Register the basic auth credential variables by NAME PATTERN, before any
# exporting happens (see util.d/basic-auth.sh for the full why: usage-based
# registration cannot see variables the current mode never reads — in worker
# mode nothing ever collects NGINX_BASIC_AUTH, and PROXY_<KEY>_BASIC_AUTH is
# only collected in proxy mode for configured services — while a shared env
# file between the web and the worker container of one stack makes such
# cross-mode leakage realistic). 090 and 100 run after this step, so the
# registry is complete for all three consumers.
register_basic_auth_credential_vars

# The snapshot is sourced by later RUN steps and docker exec shells via the
# bash wrapper. Deliberately created WITHOUT a restrictive mode (it ends up
# 644): the entrypoint-only secrets are kept out of the file by the registry
# below, and a root-only file would break "docker exec -u www-data" shells —
# they could not source it and would lose ALL variables (fatal in sh mode,
# where no bash wrapper re-derives them).
rm -rf "${CONTAINER_VARS_SCRIPT}"
touch "${CONTAINER_VARS_SCRIPT}"

declare -g -A exported_vars_map=()

for var_name in $(get_all_vars); do
  var_value="${!var_name}"
  # Entrypoint-only variables (entrypoint_only_vars_registry, see
  # entrypoint.sh) hold the clear-text basic auth credentials — they only
  # exist to generate the htpasswd files during boot — and have no legitimate
  # use in later RUN steps or exec shells, so they are deliberately kept out
  # of the snapshot (the nginx config references the generated files, never
  # these variables)
  for registered_var in "${entrypoint_only_vars_registry[@]}"; do
    if [[ "${var_name}" == "${registered_var}" ]]; then
      echo " - Not exporting variable: ${var_name} (clear-text basic auth credentials — used only to generate the password files during boot; intentionally not exported to later RUN steps or exec shells)"
      continue 2
    fi
  done
  exported_vars_map["$var_name"]="${var_value}"
  echo " - Exporting variable: ${var_name}=\"$(mask_var "${var_name}" "${var_value}")\""
  printf "export %s=%q\n" "$var_name" "$var_value" >> "${CONTAINER_VARS_SCRIPT}"
done
