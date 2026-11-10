#!/bin/_bash
set -e

echo "[ENTRYPOINT] Starting bootstrapping process..."

declare entrypoint_dir="$(dirname $(realpath "${BASH_SOURCE[0]}"))"
declare step_dir="$entrypoint_dir/step.d"
declare util_dir="$entrypoint_dir/util.d"
declare entrypoint_command="$@"

# If the entrypoint_command is empty, we automatically set the container mode to "build"
# This is useful when building libraries, running unit tests or simply want to initialize a multi-step build.
export CONTAINER_MODE=""
if [ -z "$entrypoint_command" ]; then
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
    "/var/www" # This is important because this is the home directory for the www-data user, and we want to ensure it has the correct ownership and permissions.
    "${NGINX_DOC_ROOT}"
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
    echo "[ENTRYPOINT] Running in NORMAL mode, executing entrypoint command: $entrypoint_command"
    exec $entrypoint_command
fi
