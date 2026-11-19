# LEGACY LAYER — centralized container directory (mount paths)
# Migration guide: docs/migration/2026-02-05-migrate-to-centralized-container-dir.md
# Compatibility layer until: 2027-02-05
#
# When this layer expires: delete this file and its call site in
# entrypoint.sh (search for "legacy_fail_on_legacy_mount_paths"), then note
# the removal in the migration guide. See docs/contributing.md, "Legacy
# compatibility layers (legacy.d)".
#
# Before all customization was centralized into /container/custom, consumers
# mounted the old paths directly (/etc/ssl/certs, /etc/container/templates/…).
# Those mounts would silently no longer be read, so the boot aborts loudly with
# migration instructions instead.
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before any state is changed.

# Checks for legacy mount points and aborts the boot if any are found.
# Call site: entrypoint.sh, right after the build mode marker check.
function legacy_fail_on_legacy_mount_paths() {
    function legacy_is_mounted() {
        local path="$1"
        findmnt -T "$path" --noheadings --output SOURCE | grep -q "^/"
    }

    local -A legacy_mount_map=(
        ["/etc/ssl/certs"]="${CONTAINER_CUSTOM_DIR}/certs"
        ["/etc/container/templates/nginx/custom/global"]="${CONTAINER_CUSTOM_DIR}/nginx/global"
        ["/etc/container/templates/nginx/custom"]="${CONTAINER_CUSTOM_DIR}/nginx"
        ["/etc/container/templates/php/custom"]="${CONTAINER_CUSTOM_DIR}/php"
        ["/usr/bin/container/custom"]="${CONTAINER_CUSTOM_DIR}/entrypoint"
    )

    local -a detected_legacy_mounts=()

    local legacy_path
    for legacy_path in "${!legacy_mount_map[@]}"; do
        if legacy_is_mounted "$legacy_path"; then
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
        echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-02-05-migrate-to-centralized-container-dir.md"
        exit 1
    fi
}
