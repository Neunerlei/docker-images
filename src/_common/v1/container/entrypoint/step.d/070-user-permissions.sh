#!/bin/bash

# Set correct ownership on the relevant directories
echo "[ENTRYPOINT.user-permissions] Setting ownership on application directories..."

set_owner_and_group() {
  local path="$1"
  local expected_owner="${2:-www-data}"
  local expected_group="${3:-www-data}"

  # Ignore if the path is already owned by the correct user
  current_owner=$(stat -c '%U' "${path}")
  if [ "${current_owner}" == "${expected_owner}" ]; then
    echo "[ENTRYPOINT.user-permissions] ${path} is already owned by '${expected_owner}', skipping..."
    return
  fi

  echo "[ENTRYPOINT.user-permissions] Setting ownership of ${path} to user '${expected_owner}' and group '${expected_group}'"
  chown -R "${expected_owner}:${expected_group}" "${path}"
}

# Set up ownership of user owned directories (or create them if missing)
for dir in "${user_owned_directories_registry[@]}"; do
  if [ ! -d "${dir}" ]; then
    echo "[ENTRYPOINT.user-permissions] Creating missing directory: ${dir}"
    mkdir -p "${dir}"
  fi
  set_owner_and_group "${dir}" "www-data" "www-data"
done
