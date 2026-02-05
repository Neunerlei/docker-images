#!/bin/bash
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
# Template Manifest
# Key: Template Name (e.g., "nginx-conf")
# Value: The full, tab-separated line from the manifest file.
declare -gA template_manifest
# A set to track which templates have already been processed.
# Key: Template Name
# Value: 1 (if processed)
declare -gA processed_tpl_names
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
# Load the template manifest into memory for fast lookups.
# This avoids costly disk I/O in the process_tpl function.
if [ -f "${CONTAINER_TEMPLATE_MANIFEST}" ]; then
    echo "[ENTRYPOINT] Loading template manifest into memory..."
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue  # Skip empty lines
        IFS=$'\t' read -r type name sources extra <<<"$line"
        if [[ -z "$type" || -z "$name" ]]; then
            echo "[ENTRYPOINT] Warning: Malformed manifest line: $line" >&2
            continue
        fi
        template_manifest["$name"]="$line"
    done <"${CONTAINER_TEMPLATE_MANIFEST}"
fi

# Load utility scripts first
source_files_in_dir_alphabetically "$util_dir"

# Iterate all the steps to configure the container
source_files_in_dir_alphabetically "$step_dir"
