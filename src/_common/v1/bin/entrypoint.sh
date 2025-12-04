#!/bin/bash
set -e

echo "[ENTRYPOINT] Starting bootstrapping process...";

declare entrypoint_dir="$(dirname $(realpath "${BASH_SOURCE[0]}"))/entrypoint"
declare step_dir="$entrypoint_dir/step.d"
declare util_dir="$entrypoint_dir/util.d"
declare entrypoint_command="$@"

# If the entrypoint_command is empty, we automatically set the container mode to "build"
# This is useful when building libraries, running unit tests or simply want to initialize a multi-step build.
export CONTAINER_MODE=""
if [ -z "$entrypoint_command" ]; then
  export CONTAINER_MODE="build"
  echo "[ENTRYPOINT] No command specified, setting CONTAINER_MODE to 'build'.";
fi

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
# File Markers
# The keys will be the marker strings (e.g., "prod"), and the values
# will be the names of the condition functions to call for that marker.
# If the function returns true, the marker condition is satisfied.
declare -gA file_marker_condition_registry
# Feature Toggles
# A list of feature names (nginx | supervisor | ...) to dynamically enable / disable
# entrypoint features
declare -g feature_registry

# Load utility scripts first
source_files_in_dir_alphabetically "$util_dir"

# Iterate all the steps to configure the container
source_files_in_dir_alphabetically "$step_dir"
