#!/bin/bash

# Ensures a directory exists and is owned by the www-data user, so processes
# running as www-data can work inside it. Creates missing directories and
# chowns recursively when the ownership does not match yet. Directories that
# are already correct are left untouched — which also works on read-only
# filesystems, where mkdir/chown would fail even as a no-op.
#
# Usage:
#   ensure_user_owned_dir "/path/to/dir"
#
ensure_user_owned_dir() {
    local dir_path="$1"

    if [ ! -d "${dir_path}" ]; then
        echo "[UTIL.user-owned-dir] Creating missing directory: ${dir_path}"
        mkdir -p "${dir_path}"
    fi

    if [ "$(stat -c '%U' "${dir_path}")" != "www-data" ]; then
        echo "[UTIL.user-owned-dir] Setting ownership of ${dir_path} to user 'www-data'"
        chown -R www-data:www-data "${dir_path}"
    fi
}
