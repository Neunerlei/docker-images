#!/bin/bash

# Checks if the given path sits on a read-only mount (e.g. a Kubernetes config map
# volume). Returns 0 (true) if it does.
#
# Usage:
#   if _path_is_on_read_only_mount "/container/custom"; then ...
#
_path_is_on_read_only_mount() {
    local dir_path="$1"
    # findmnt resolves the deepest mount covering the path; if the path itself does
    # not exist (yet), check the closest existing parent instead
    while [ ! -e "${dir_path}" ] && [ "${dir_path}" != "/" ]; do
        dir_path="$(dirname "${dir_path}")"
    done
    findmnt -no OPTIONS --target "${dir_path}" 2>/dev/null | grep -qw ro
}

# Ensures a directory exists and is owned by the www-data user, so processes
# running as www-data can work inside it. Creates missing directories and
# chowns recursively when the ownership does not match yet.
#
# Directories that are already correct are left untouched — which also works on
# read-only filesystems, where mkdir/chown would fail even as a no-op.
#
# Read-only mounts (e.g. Kubernetes config map volumes injected into /container/custom)
# are a deliberate setup: the files only need to stay world-readable, so a failed
# mkdir/chown there only produces a warning instead of aborting the boot.
#
# Usage:
#   ensure_user_owned_dir "/path/to/dir"
#
ensure_user_owned_dir() {
    local dir_path="$1"

    if [ ! -d "${dir_path}" ]; then
        echo "[UTIL.user-owned-dir] Creating missing directory: ${dir_path}"
        if ! mkdir -p "${dir_path}" 2>/dev/null; then
            if _path_is_on_read_only_mount "${dir_path}"; then
                echo "[UTIL.user-owned-dir] Warning: '${dir_path}' could not be created (read-only mount) — continuing." >&2
                return 0
            fi
            echo "[UTIL.user-owned-dir] Error: Failed to create directory '${dir_path}'." >&2
            return 1
        fi
    fi

    if [ "$(stat -c '%U' "${dir_path}")" != "www-data" ]; then
        echo "[UTIL.user-owned-dir] Setting ownership of ${dir_path} to user 'www-data'"
        if ! chown -R www-data:www-data "${dir_path}" 2>/dev/null; then
            if _path_is_on_read_only_mount "${dir_path}"; then
                echo "[UTIL.user-owned-dir] Warning: ownership of '${dir_path}' could not be changed (read-only mount) — continuing, the world-readable files remain usable." >&2
                return 0
            fi
            echo "[UTIL.user-owned-dir] Error: Failed to set ownership of '${dir_path}'." >&2
            return 1
        fi
    fi
}
