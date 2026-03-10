#!/bin/bash

# Loads project-specific environment variables from /container/custom/env/ before
# any service configuration (nginx, supervisor, etc.) runs.
#
# This is the canonical place to declare variables that need to be derived from
# other variables or computed dynamically — things that would otherwise end up
# scattered across custom entrypoint scripts, Dockerfiles, or compose files.
#
# Two file types are supported inside /container/custom/env/:
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
# The CONTAINER_CUSTOM_ENV_DIR variable points to this directory and is
# already exported in the environment by the time this step runs.

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

# Plain .env files first (static derived values), then .env.sh files (dynamic logic).
# Both passes go through for_each_filtered_file_in_dir so the marker DSL works here
# too — e.g. '10-routing.prod.env' is only loaded in production.
for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENV_DIR}" _load_custom_env_file "*.env"
for_each_filtered_file_in_dir "${CONTAINER_CUSTOM_ENV_DIR}" _load_custom_env_sh_file "*.env.sh"
