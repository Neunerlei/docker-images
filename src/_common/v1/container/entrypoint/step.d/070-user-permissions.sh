#!/bin/bash

# Set correct ownership on the relevant directories
echo "[ENTRYPOINT.user-permissions] Setting ownership on application directories..."

# Ensure all container bin scripts are executable.
# Scripts that are already executable are skipped, so this also works
# on read-only filesystems (chmod fails there even without a mode change).
if [ -d "${CONTAINER_BIN_DIR}" ]; then
  for bin_script in "${CONTAINER_BIN_DIR}"/*; do
    if [ -f "${bin_script}" ] && [ ! -x "${bin_script}" ]; then
      chmod +x "${bin_script}"
    fi
  done
fi

# Set up ownership of user owned directories (or create them if missing)
for dir in "${user_owned_directories_registry[@]}"; do
  ensure_user_owned_dir "${dir}"
done
