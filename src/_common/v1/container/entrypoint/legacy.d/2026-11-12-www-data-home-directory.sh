# LEGACY LAYER — www-data home directory (dotfile bridge)
# Migration guide: docs/migration/2026-11-12-www-data-home-directory.md
# Compatibility layer until: 2027-11-12
#
# When this layer expires: delete this file and its call site in
# entrypoint.sh (search for "legacy_bridge_var_www_dotfiles"), then note the
# removal in the migration guide. See docs/contributing.md, "Legacy
# compatibility layers (legacy.d)".
#
# Historically the www-data home was /var/www, so consumers may have baked or
# mounted dotfiles there (.npmrc, .ssh, .gitconfig, .composer, ...). After the
# home moved to /container/work/www-data-home, those files would silently
# stop being read. The bridge symlinks every dot-entry in /var/www that does
# not exist in the new home yet. Note: writes through a bridged entry (e.g.
# into ~/.ssh/) land back in /var/www, which is unwritable on read-only
# systems — the bridge does not change that, it only keeps the files readable
# where they were before.
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before any state is changed.

# Bridges legacy dotfiles from /var/www into the www-data home and removes
# stale bridge links whose source has disappeared.
# Call site: entrypoint.sh, after the service user home bootstrap.
function legacy_bridge_var_www_dotfiles() {
    shopt -s nullglob
    # First sweep the home for leftover bridge links from earlier boots whose
    # source in /var/www has disappeared (e.g. a mount was removed while the
    # home lives on a named volume) — dangling links must not accumulate.
    local existing_home_entry existing_home_target
    for existing_home_entry in "${CONTAINER_WWW_DATA_HOME_DIR}"/.[!.]* "${CONTAINER_WWW_DATA_HOME_DIR}"/..?*; do
        if [ -L "${existing_home_entry}" ]; then
            existing_home_target="$(readlink "${existing_home_entry}")"
            case "${existing_home_target}" in
                /var/www/*)
                    if [ ! -e "${existing_home_entry}" ]; then
                        echo "[ENTRYPOINT] Removing stale bridge link '${existing_home_entry}' (target '${existing_home_target}' is gone)."
                        rm -f "${existing_home_entry}"
                    fi
                    ;;
            esac
        fi
    done
    local legacy_entry bridge_target
    for legacy_entry in /var/www/.[!.]* /var/www/..?*; do
        bridge_target="${CONTAINER_WWW_DATA_HOME_DIR}/${legacy_entry##*/}"
        if [ ! -e "${bridge_target}" ] && [ ! -L "${bridge_target}" ]; then
            echo "[ENTRYPOINT] Warning: bridging legacy '${legacy_entry}' into the www-data home. Deprecated — move it to '${CONTAINER_WWW_DATA_HOME_DIR}'." >&2
            echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-12-www-data-home-directory.md" >&2
            ln -s "${legacy_entry}" "${bridge_target}"
        fi
    done
    shopt -u nullglob
}
