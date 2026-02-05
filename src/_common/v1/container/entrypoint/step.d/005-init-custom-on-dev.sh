#!/bin/bash

# This script runs in development mode to create a skeleton of all available
# custom source directories, making it easier for developers to discover
# where to place their custom templates and scripts.

if [[ "${ENVIRONMENT}" == "development" ]]; then
  echo "[ENTRYPOINT.dev-setup] Initializing custom directory skeleton for development..."

  # The custom directory must be mounted for this to be useful.
  if [[ ! -d "${CONTAINER_CUSTOM_DIR}" ]]; then
    echo "[ENTRYPOINT.dev-setup] Custom directory not found at '${CONTAINER_CUSTOM_DIR}', skipping skeleton creation."
    return
  fi

  # Use an associative array to prevent trying to create the same directory multiple times.
  declare -A custom_dirs_to_create

  # Built in directories to always ensure exist
  custom_dirs_to_create["${CONTAINER_CUSTOM_ENTRYPOINT_DIR}"]=1

  # Loop through our in-memory manifest to find all relevant source directories.
  for line in "${template_manifest[@]}"; do
    IFS=$'\t' read -r type _ sources_str _ <<< "$line"

    # We only care about registrations that have source directories.
    if [[ "$type" != "dir" ]]; then
      continue
    fi

    declare -a source_paths=()
    IFS='|' read -r -a source_paths <<< "$sources_str"

    for source_path in "${source_paths[@]}"; do
      # Check if the source path is within our main custom directory.
      if [[ "$source_path" == "${CONTAINER_CUSTOM_DIR}"* ]]; then
        # Add the path to our list of directories to create.
        # The key-based nature of the associative array handles duplicates automatically.
        custom_dirs_to_create["$source_path"]=1
      fi
    done
  done

  # Now, create any directories that don't already exist.
  if (( ${#custom_dirs_to_create[@]} > 0 )); then
    echo "[ENTRYPOINT.dev-setup] Ensuring custom directories exist:"
    for dir in "${!custom_dirs_to_create[@]}"; do
      if [[ ! -d "$dir" ]]; then
        echo "  -> Creating missing custom directory: ${dir}"
        mkdir -p "$dir"
      fi
    done
  else
    echo "[ENTRYPOINT.dev-setup] No custom source directories found in manifest."
  fi
fi
