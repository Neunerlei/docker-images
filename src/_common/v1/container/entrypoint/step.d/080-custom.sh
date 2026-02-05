#!/bin/bash

_execute_custom_entrypoint() {
    local script="$1"
    if [[ ! -r "$script" ]]; then
        echo "[ENTRYPOINT.custom] Warning: Cannot read '$script', skipping." >&2
        return 1
    fi
    echo "[ENTRYPOINT.custom] Executing: $script"
    source "$script" || {
        echo "[ENTRYPOINT.custom] Error: Script failed with exit code $?" >&2
        exit 1  # Fail the container if custom script fails
    }
}

for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENTRYPOINT_DIR}" _execute_custom_entrypoint "*.sh"
