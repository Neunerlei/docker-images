#!/bin/bash

# A downstream image's copy of the OLD 017-custom-env.sh (pre-2026-11-17
# shape) — the file used to own BOTH custom env file loads.

_load_custom_env_file() {
    local file="$1"
    echo "[ENTRYPOINT.custom-env] Loading: $file"
    set -a
    # shellcheck source=/dev/null
    source "$file" || {
        echo "[ENTRYPOINT.custom-env] Error: '$file' failed with exit code $?" >&2
        exit 1
    }
    set +a
}

_load_custom_env_sh_file() {
    local file="$1"
    echo "[ENTRYPOINT.custom-env] Loading: $file"
    # shellcheck source=/dev/null
    source "$file" || {
        echo "[ENTRYPOINT.custom-env] Error: '$file' failed with exit code $?" >&2
        exit 1
    }
}

echo "[LEGACY-017-OVERRIDE] running"

for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENV_DIR}" _load_custom_env_file "*.env"
for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENV_DIR}" _load_custom_env_sh_file "*.env.sh"
