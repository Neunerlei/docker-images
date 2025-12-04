#!/bin/bash

# Set correct ownership on the relevant directories
echo "[ENTRYPOINT.user-permissions] Setting ownership on application directories..."

# Always add the well known paths here
user_owned_directories_registry+=(
  "${CONTAINER_VARS_SCRIPT}"
  "${CONTAINER_CERTS_DIR}"
  "${NGINX_SERVE_ROOT}"
  "${NGINX_DOC_ROOT}"
)

for dir in "${user_owned_directories_registry[@]}"; do
  if [ ! -d "${dir}" ] && [ ! -f "${dir}" ]; then
    echo "[ENTRYPOINT.user-permissions] Creating missing path: ${dir}"
    mkdir -p "${dir}"
  fi

  # Ignore if the directory is already owned by the correct user
  current_owner=$(stat -c '%U' "${dir}")
  if [ "${current_owner}" == "www-data" ]; then
    echo "[ENTRYPOINT.user-permissions] Path ${dir} is already owned by 'www-data', skipping..."
    continue
  fi

  echo "[ENTRYPOINT.user-permissions] Setting ownership of ${dir} to user 'www-data'"
  chown -R "www-data:www-data" "${dir}"
done
