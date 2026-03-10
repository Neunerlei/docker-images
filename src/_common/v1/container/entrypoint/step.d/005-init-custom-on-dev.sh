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

  # container_custom_dir_child_registry is populated in entrypoint.sh from the static
  # built-in entries (env/, entrypoint/) and from dir-type template manifest entries.
  # Image-specific step files can extend it further before this script runs.
  if (( ${#container_custom_dir_child_registry[@]} > 0 )); then
    echo "[ENTRYPOINT.dev-setup] Ensuring custom directories exist:"
    for dir in "${!container_custom_dir_child_registry[@]}"; do
      if [[ ! -d "$dir" ]]; then
        echo "  -> Creating missing custom directory: ${dir}"
        mkdir -p "$dir"
      fi
    done
  else
    echo "[ENTRYPOINT.dev-setup] No custom source directories found in registry."
  fi
fi
