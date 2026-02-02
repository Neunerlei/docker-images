#!/bin/bash

set -e

# The generic installer script that sets up common dependencies and directories
# It should run in the Dockerfile right after the base image is set up
# -----------------------------------------------------------------
# Configuration:
# - You can define the INSTALLER_EXTRA_DEPENDENCIES environment variable
#   to add extra dependencies to install via apt (separated by spaces)
# - You can define the INSTALLER_REMOVE_DEPENDENCIES environment variable
#   to remove dependencies from the default list (separated by spaces)
# -----------------------------------------------------------------

declare current_directory="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
declare entrypoint_directory="${current_directory}/bin/entrypoint"

# Load the common environment variables
source "${entrypoint_directory}/common-env.sh"

# A list of dependencies to install using apt
declare dependencies_to_install=(
  "bash"
  "nginx"
  "curl"
  "ca-certificates"
  "openssl"
  "openssh-client"
  "git"
  "nano"
  "supervisor"
  "gosu"
  "zip"
  "unzip"
  "7zip"
)

# If there is a global variable called INSTALLER_EXTRA_DEPENDENCIES, append its contents to the dependencies list, ensure there are no duplicates
if [ -n "${INSTALLER_EXTRA_DEPENDENCIES}" ]; then
  for extra_dep in ${INSTALLER_EXTRA_DEPENDENCIES}; do
    if [[ ! " ${dependencies_to_install[@]} " =~ " ${extra_dep} " ]]; then
      dependencies_to_install+=("${extra_dep}")
    fi
  done
fi

# If there is a global variable called INSTALLER_REMOVE_DEPENDENCIES, remove its contents from the dependencies list
if [ -n "${INSTALLER_REMOVE_DEPENDENCIES}" ]; then
  for remove_dep in ${INSTALLER_REMOVE_DEPENDENCIES}; do
    dependencies_to_install=("${dependencies_to_install[@]/$remove_dep}")
  done
fi

# A list of directories to create inside the container
declare directories_to_create=(
  "${CONTAINER_TEMPLATE_DIR}"
  "${CONTAINER_BIN_DIR}"
  "${NGINX_SITES_ENABLED_DIR}"
  "${NGINX_SITES_AVAILABLE_DIR}"
  "${NGINX_SERVICE_SNIPPET_DIR}"
  "${NGINX_GLOBAL_SNIPPET_DIR}"
  "${NGINX_DOC_ROOT}"
  "${NGINX_ERRORS_DIR}"
  "${CONTAINER_CERTS_DIR}"
)

# -----------------------------------------------------------------
# Create common directories
# -----------------------------------------------------------------
echo "[INSTALLER] Creating common directories";

for dir_path in "${directories_to_create[@]}"; do
  mkdir -p "$dir_path"
  chmod 755 "$dir_path"
done

# -----------------------------------------------------------------
# Install common dependencies
# -----------------------------------------------------------------
echo "[INSTALLER] Installing common dependencies";

apt update
if [ $? -ne 0 ]; then
  echo "[INSTALLER] apt update failed!"
  exit 1
fi

apt upgrade -y
if [ $? -ne 0 ]; then
  echo "[INSTALLER.install-common-deps] apt upgrade failed!"
  exit 1
fi

echo "[INSTALLER] Installing packages: ${dependencies_to_install[*]}";
apt install -y "${dependencies_to_install[@]}"
if [ $? -ne 0 ]; then
  echo "[INSTALLER] apt install failed!"
  exit 1
fi

# -----------------------------------------------------------------
# Install bash wrapper
# -----------------------------------------------------------------
echo "[INSTALLER] Installing bash wrapper";

# IMPORTANT: This is black magic!
# Because we create environment variables in our entrypoint.sh they do not automatically
# become available in the default shell (which seems to be always "sh"), an neither in bash
# if you run a command like docker exec container_name npm run...
# Therefore I wrap bash with a custom script, that always loads our generated env variables
# And symlink sh into bash to work in both cases out of the box.

mv /bin/bash /bin/_bash
cat << EOF > /bin/bash
#!/bin/_bash
[ -f "${CONTAINER_VARS_SCRIPT}" ] && . "${CONTAINER_VARS_SCRIPT}"
exec /bin/_bash "\$@"
EOF
chmod +x /bin/bash
rm -f /bin/sh
ln -s /bin/bash /bin/sh
