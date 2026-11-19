#!/bin/bash

# Loads project-specific environment variables from /container/custom/env/
# (pointed to by $CONTAINER_CUSTOM_ENV_DIR). Extracted from the former
# step.d/017-custom-env.sh so the environment orchestrator
# (step.d/015-environment.sh) can run the two file-type passes at their
# correct positions in the boot sequence — and so a legacy 017 override can
# replace both passes in one place.
#
# Two file types are supported inside the custom env directory:
#
#   *.env      Plain key=value files (no shell logic). All variables are automatically
#              exported into the environment. Useful for static derived values:
#
#                APP_URL=${APP_PROTOCOL}://${APP_HOST}
#                VITE_REVERB_HOST=${APP_HOST}
#
#   *.env.sh   Full shell scripts for dynamic lookups, conditionals, or anything
#              that requires real logic. Variables must be exported explicitly:
#
#                export CACHE_TTL=$(redis-cli get cache_ttl || echo "3600")
#
# Files are sourced in alphabetical order. Both types honour the same naming
# convention so you can control load order with numeric prefixes if needed:
#   10-routing.env, 20-services.env.sh, ...
#
# Usage:
#   load_custom_env_files "*.env"      # plain pass (set -a auto-export)
#   load_custom_env_files "*.env.sh"   # dynamic pass (explicit export required)

_load_custom_env_file() {
    local file="$1"
    echo "[ENTRYPOINT.custom-env] Loading: $file"
    # set -a / set +a automatically exports every variable assignment in the sourced file,
    # so plain KEY=VALUE lines don't need an explicit 'export'.
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

# Loads every custom env file matching the glob. Both loader variants go
# through for_each_filtered_file_in_dir so the marker DSL works here too —
# e.g. '10-routing.prod.env' is only loaded in production.
load_custom_env_files() {
    local glob="${1:?glob required}"
    case "${glob}" in
        "*.env.sh")
            for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENV_DIR}" _load_custom_env_sh_file "*.env.sh"
            ;;
        *)
            for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENV_DIR}" _load_custom_env_file "*.env"
            ;;
    esac
}
