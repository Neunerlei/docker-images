#!/bin/bash

# Additional user owned directories can be declared via the USER_OWNED_DIRECTORIES
# environment variable (space separated), e.g. for volumes the www-data processes
# need to write into. This deliberately runs HERE — after the custom environment
# files were loaded (step 017) — so the variable may also be set from
# /container/custom/env/*.env, not only from the container environment.
# Split WITHOUT glob expansion: a plain "for d in ${USER_OWNED_DIRECTORIES}"
# word-splits (intended) but also glob-expands every entry (not intended — the
# result is chown-ed recursively as root). "read -ra" splits on IFS whitespace
# and keeps every entry literal; newlines are normalized to spaces first so
# multi-line env files keep working like the documented space-separated format.
declare -a user_owned_dirs_from_env=()
read -r -a user_owned_dirs_from_env <<< "${USER_OWNED_DIRECTORIES//[$'\t'$'\n']/ }"
for user_owned_dir in "${user_owned_dirs_from_env[@]}"; do
    user_owned_directories_registry+=("${user_owned_dir}")
done

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
