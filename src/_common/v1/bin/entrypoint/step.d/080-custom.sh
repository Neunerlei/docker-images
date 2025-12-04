#!/bin/bash

_execute_custom_entrypoint() {
  echo "[ENTRYPOINT.custom] Executing custom entrypoint script '$1'";
  source "$1";
}

for_each_filtered_file_in_dir "${CONTAINER_BIN_DIR}/custom" _execute_custom_entrypoint "*.sh"
