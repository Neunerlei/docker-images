#!/bin/bash
set -e

echo "[ENTRYPOINT] Starting bootstrapping process...";

# Configurable default values
DEFAULT_MAX_UPLOAD_SIZE="100M"
DEFAULT_NGINX_CERT_PATH="/etc/ssl/certs/cert.pem"
DEFAULT_NGINX_KEY_PATH="/etc/ssl/certs/key.pem"

# Determine effective max upload size
MAX_UPLOAD_SIZE_EFFECTIVE="${MAX_UPLOAD_SIZE:-$DEFAULT_MAX_UPLOAD_SIZE}"

# Load environment variables
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-$MAX_UPLOAD_SIZE_EFFECTIVE}"
export NGINX_CERT_PATH="${NGINX_CERT_PATH:-$DEFAULT_NGINX_CERT_PATH}"
export NGINX_KEY_PATH="${NGINX_KEY_PATH:-$DEFAULT_NGINX_KEY_PATH}"

# If there are any PROXY_*_CONTAINER environment variables, set the container mode to "proxy"
if env | grep -q '^PROXY_.*_CONTAINER='; then
  export CONTAINER_MODE="proxy"
else
  export CONTAINER_MODE="static" # Static file server mode is the default if no proxy containers are defined
fi

# Configure services
echo "[ENTRYPOINT] Configuring services in mode: ${CONTAINER_MODE}...";

ENTRYPOINT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/entrypoint"
source "${ENTRYPOINT_DIR}/util/render-template.sh"
source "${ENTRYPOINT_DIR}/nginx.sh"
source "${ENTRYPOINT_DIR}/nginx-proxy.sh"
source "${ENTRYPOINT_DIR}/nginx-static.sh"
source "${ENTRYPOINT_DIR}/custom.sh"

echo "[ENTRYPOINT] Bootstrapping completed!";

# No exec here, as this script uses the base images extension mechanism at /docker-entrypoint.d/ (See Dockerfile)
