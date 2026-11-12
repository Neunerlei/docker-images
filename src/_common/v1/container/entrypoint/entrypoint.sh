#!/bin/_bash
set -e

echo "[ENTRYPOINT] Starting bootstrapping process..."

declare entrypoint_dir="$(dirname $(realpath "${BASH_SOURCE[0]}"))"
declare step_dir="$entrypoint_dir/step.d"
declare util_dir="$entrypoint_dir/util.d"
declare -a entrypoint_command=("$@")

# If the entrypoint_command is empty, we automatically set the container mode to "build"
# This is useful when building libraries, running unit tests or simply want to initialize a multi-step build.
export CONTAINER_MODE=""
if [ ${#entrypoint_command[@]} -eq 0 ]; then
    export CONTAINER_MODE="build"
    echo "[ENTRYPOINT] No command specified, setting CONTAINER_MODE to 'build'."
fi

echo "[ENTRYPOINT] Setting common environment variables..."

source "${entrypoint_dir}/common-env.sh"

# Sources all .sh files in the given directory in alphabetical order
#
# Usage:
#   source_files_in_dir_alphabetically "/path/to/directory"
function source_files_in_dir_alphabetically() {
    local dir_path="$1"
    if [ -d "$dir_path" ]; then
        while IFS= read -r -d '' file; do
            source "$file"
        done < <(find "$dir_path" -maxdepth 1 -name "*.sh" -print0 | sort -z)
    fi
}

# Registries for feature promotion
# Template Registry
# Key: Template Name (e.g., "nginx-conf")
# Value: The full, tab-separated registration line (type, name, sources, extra).
declare -gA template_registry
# A set to track which templates have already been processed.
# Key: Template Name
# Value: 1 (if processed)
declare -gA processed_tpl_registry
# File Markers
# The keys will be the marker strings (e.g., "prod"), and the values
# will be the names of the condition functions to call for that marker.
# If the function returns true, the marker condition is satisfied.
declare -gA file_marker_condition_registry
# Feature Toggles
# A list of feature names (nginx | supervisor | ...) to dynamically enable / disable
# entrypoint features
declare -g feature_registry
# User directories
# A list of directory paths that should be owned by the www-data user inside the container
declare -g -a user_owned_directories_registry=(
    "/run"
    "/var/lib/nginx"
    "/var/log/nginx"
    "${CONTAINER_DIR}"
    "${NGINX_SERVE_ROOT}"
    "/var/www" # This is the home directory of the www-data user by distribution default. It remains the application tree parent — the writable service home lives in the work directory (CONTAINER_WWW_DATA_HOME_DIR).
    "${NGINX_DOC_ROOT}"
    "${CONTAINER_WWW_DATA_HOME_DIR}"
)
# Additional user owned directories can be declared for the running container via the
# USER_OWNED_DIRECTORIES environment variable (space separated), e.g. for volumes that
# the www-data processes need to write into
for user_owned_dir in ${USER_OWNED_DIRECTORIES}; do
    user_owned_directories_registry+=("${user_owned_dir}")
done
# Custom directory children
# The set of sub-directories that should exist inside CONTAINER_CUSTOM_DIR.
# Used by 005-init-custom-on-dev.sh to create the skeleton on first startup in development.
# Keys are the full paths; values are always 1.
# Image-specific step files can extend this registry by adding entries, just like feature_registry.
declare -gA container_custom_dir_child_registry=(
    ["${CONTAINER_CUSTOM_ENV_DIR}"]=1
    ["${CONTAINER_CUSTOM_ENTRYPOINT_DIR}"]=1
)

# --- Work data bootstrap -----------------------------------------------
# The staging area holds the pristine build-time state of the work data: during
# the build, work/data is a symlink to it, so everything written into the work
# data — by the installer, later build steps or child images — is captured
# there. On every boot, the work data is reset to exactly that state: the
# build-time symlink (or a stale runtime copy from a previous boot) is replaced
# by a real directory, and the entrypoint steps re-generate everything they
# need. A work directory mounted empty (tmpfs, Kubernetes emptyDir) is seeded
# the same way — the staging area lives outside the work directory, so a mount
# can not shadow it.
if [ ! -d "${CONTAINER_WORK_DIR}" ]; then
    echo "[ENTRYPOINT] Work directory is missing — creating it..."
    mkdir -p "${CONTAINER_WORK_DIR}"
fi

# --- Service user home bootstrap -----------------------------------------
# The www-data home lives in the work directory, so it is writable on every
# deployment — including read-only filesystems, where /container/work is the
# documented writable mount (tmpfs or emptyDir start empty, so the home must
# be created here). It has to exist before the entrypoint steps run: step 030
# (git) already writes to $HOME of the www-data user via gosu. The chown is
# conditional, matching ensure_user_owned_dir: already-correct setups — and
# environments where chown is not permitted — are left untouched.
if [ ! -d "${CONTAINER_WWW_DATA_HOME_DIR}" ]; then
    echo "[ENTRYPOINT] Creating www-data home directory: ${CONTAINER_WWW_DATA_HOME_DIR}"
    mkdir -p "${CONTAINER_WWW_DATA_HOME_DIR}"
fi
if [ "$(stat -c '%U' "${CONTAINER_WWW_DATA_HOME_DIR}")" != "www-data" ]; then
    # Recursive, like ensure_user_owned_dir: on a named volume at /container/work
    # the CONTENTS can keep a stale uid (e.g. PUID removed after a previous boot
    # reset /etc/passwd to uid 33) while step 070 would see the — by then fixed —
    # top-level owner and skip its repair. Conditional, so boots where the
    # ownership already matches remain a no-op.
    chown -R www-data:www-data "${CONTAINER_WWW_DATA_HOME_DIR}"
fi

# --- Legacy dotfile bridge -------------------------------------------------
# Historically the www-data home was /var/www, so consumers may have baked or
# mounted dotfiles there (.npmrc, .ssh, .gitconfig, .composer, ...). After the
# home moved, those files would silently stop being read. Bridge them: every
# dot-entry in /var/www that does not exist in the new home yet is symlinked.
# Note: writes through a bridged entry (e.g. into ~/.ssh/) land back in
# /var/www, which is unwritable on read-only systems — the bridge does not
# change that, it only keeps the files readable where they were before.
shopt -s nullglob
# First sweep the home for leftover bridge links from earlier boots whose
# source in /var/www has disappeared (e.g. a mount was removed while the home
# lives on a named volume) — dangling links must not accumulate forever.
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
for legacy_entry in /var/www/.[!.]* /var/www/..?*; do
    bridge_target="${CONTAINER_WWW_DATA_HOME_DIR}/${legacy_entry##*/}"
    if [ ! -e "${bridge_target}" ] && [ ! -L "${bridge_target}" ]; then
        echo "[ENTRYPOINT] Warning: bridging legacy '${legacy_entry}' into the www-data home. Deprecated — move it to '${CONTAINER_WWW_DATA_HOME_DIR}'." >&2
        echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-12-www-data-home-directory.md" >&2
        ln -s "${legacy_entry}" "${bridge_target}"
    fi
done
shopt -u nullglob

echo "[ENTRYPOINT] Resetting work data from the staging area..."
rm -rf "${CONTAINER_WORK_DATA_DIR}"
if [ -d "${CONTAINER_WORK_STAGING_DIR}" ]; then
    cp -a "${CONTAINER_WORK_STAGING_DIR}" "${CONTAINER_WORK_DATA_DIR}"
else
    # The staging area is created by the installer during the image build and is as
    # much part of the image as the entrypoint itself — a healthy image can not boot
    # without it. Continuing with an empty work data directory would only die a few
    # steps later with a far less helpful "Output directory does not exist" error.
    echo "[ENTRYPOINT] Error: the work data staging area is missing at '${CONTAINER_WORK_STAGING_DIR}'. It is created by the installer during the image build — the image appears to be broken or was modified after the build. Aborting." >&2
    exit 1
fi

# Source the installer registry script to populate the in-memory registries
# (template_registry, container_custom_dir_child_registry).
if [ -f "${CONTAINER_INSTALLER_REGISTRY_SCRIPT}" ]; then
    echo "[ENTRYPOINT] Sourcing installer registry..."
    source "${CONTAINER_INSTALLER_REGISTRY_SCRIPT}"
fi

# Load utility scripts first
source_files_in_dir_alphabetically "$util_dir"

# Iterate all the steps to configure the container
source_files_in_dir_alphabetically "$step_dir"

# If running in BUILD mode, export all variables for the next command,
# but remove the "CONTAINER_VARS_SCRIPT" script, so it does not pollute the next run.
if [ "$CONTAINER_MODE" == "build" ]; then
    echo "[ENTRYPOINT] Running in BUILD mode, exporting variables for the next command..."
    export -p > "${CONTAINER_VARS_SCRIPT}"
    rm -f "${CONTAINER_VARS_SCRIPT}"
else
    echo "[ENTRYPOINT] Running in NORMAL mode, executing entrypoint command: $(printf '%q ' "${entrypoint_command[@]}")"
    exec "${entrypoint_command[@]}"
fi
