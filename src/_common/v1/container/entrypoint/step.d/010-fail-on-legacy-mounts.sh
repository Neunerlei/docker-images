#!/bin/bash

# This script checks for legacy mount points and stops the container if any are found.
# I need to do this, because I moved all configuration into the /container/custom directory,
# to allow the container to be more flexible and work well with read-only filesystems.
# However, some users might still mount old paths like /etc/ssl/certs directly

# Check if a given path is a mounted filesystem
_is_mounted() {
    local path="$1"
    findmnt -T "$path" --noheadings --output SOURCE | grep -q "^/"
}

declare -A legacy_mount_map=(
    ["/etc/ssl/certs"]="${CONTAINER_CUSTOM_DIR}/certs"
    ["/etc/container/templates/nginx/custom/global"]="${CONTAINER_CUSTOM_DIR}/nginx/global"
    ["/etc/container/templates/nginx/custom"]="${CONTAINER_CUSTOM_DIR}/nginx"
    ["/etc/container/templates/php/custom"]="${CONTAINER_CUSTOM_DIR}/php"
    ["/usr/bin/container/custom"]="${CONTAINER_CUSTOM_DIR}/entrypoint"
)

declare -a detected_legacy_mounts=()

for legacy_path in "${!legacy_mount_map[@]}"; do
    if _is_mounted "$legacy_path"; then
        detected_legacy_mounts+=("$legacy_path")
    fi
done

if [[ ${#detected_legacy_mounts[@]} -gt 0 ]]; then
    echo "❌ [ERROR] Detected legacy mount paths. These are no longer supported."
    echo ""
    echo "Please update your docker-compose.yml:"
    echo ""
    echo "  volumes:"
    echo "    # ❌ OLD (remove these):"
    for path in "${detected_legacy_mounts[@]}"; do
        echo "    # - ./docker/...:${path}"
    done
    echo ""
    echo "    # ✅ NEW (use this instead):"
    echo "    - ./docker:/container/custom"
    echo ""
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/migrate-to-centralized-container-dir.md"
    exit 1
fi
