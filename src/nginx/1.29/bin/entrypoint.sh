#!/bin/bash
set -e

echo "[ENTRYPOINT] Starting bootstrapping process...";

ENTRYPOINT_DIR="$(dirname $(realpath "${BASH_SOURCE[0]}"))/entrypoint"
source "${ENTRYPOINT_DIR}/util/utils.sh"

# Load environment variables
echo "[ENTRYPOINT] Effective configuration:";

export ENVIRONMENT="$(find_environment)"
echo "   - ENVIRONMENT=${ENVIRONMENT}";
export NGINX_DOC_ROOT="${NGINX_DOC_ROOT:-"/var/www/html/public"}"
echo "   - NGINX_DOC_ROOT=${NGINX_DOC_ROOT}";
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
echo "   - NGINX_CLIENT_MAX_BODY_SIZE=${NGINX_CLIENT_MAX_BODY_SIZE}";
export NGINX_CERT_PATH="${NGINX_CERT_PATH:-"/etc/ssl/certs/cert.pem"}"
echo "   - NGINX_CERT_PATH=${NGINX_CERT_PATH}";
export NGINX_KEY_PATH="${NGINX_KEY_PATH:-"/etc/ssl/certs/key.pem"}"
echo "   - NGINX_KEY_PATH=${NGINX_KEY_PATH}";
export DOCKER_PROJECT_HOST="${DOCKER_PROJECT_HOST:-localhost}"
echo "   - DOCKER_PROJECT_HOST=${DOCKER_PROJECT_HOST}";
export DOCKER_PROJECT_PROTOCOL="${DOCKER_PROJECT_PROTOCOL:-http}"
echo "   - DOCKER_PROJECT_PROTOCOL=${DOCKER_PROJECT_PROTOCOL}";
export DOCKER_PROJECT_PATH="${DOCKER_PROJECT_PATH:-/}"
echo "   - DOCKER_PROJECT_PATH=${DOCKER_PROJECT_PATH}";
export DOCKER_SERVICE_PROTOCOL="${DOCKER_SERVICE_PROTOCOL:-${DOCKER_PROJECT_PROTOCOL}}"
echo "   - DOCKER_SERVICE_PROTOCOL=${DOCKER_SERVICE_PROTOCOL}";
export DOCKER_SERVICE_PATH="${DOCKER_SERVICE_PATH:-/}"
echo "   - DOCKER_SERVICE_PATH=${DOCKER_SERVICE_PATH}";
export DOCKER_SERVICE_ABS_PATH="$(join_paths "${DOCKER_PROJECT_PATH:-/}" "${DOCKER_SERVICE_PATH}")"
echo "   - DOCKER_SERVICE_ABS_PATH=${DOCKER_SERVICE_ABS_PATH}";

# If there are any PROXY_*_CONTAINER environment variables, set the container mode to "proxy"
if env | grep -q '^PROXY_.*_CONTAINER='; then
  export CONTAINER_MODE="proxy"
else
  export CONTAINER_MODE="static" # Static file server mode is the default if no proxy containers are defined
fi
echo "   - CONTAINER_MODE=${CONTAINER_MODE}";

# Setting directories for later use
export NGINX_DIR="/etc/nginx"
export NGINX_SNIPPET_DIR="$NGINX_DIR/snippets"
export NGINX_SERVICE_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/service.d"
export NGINX_GLOBAL_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/global.d"
export NGINX_PROXY_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/proxy.d"
export NGINX_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/nginx"
export NGINX_CUSTOM_TEMPLATE_DIR="${NGINX_TEMPLATE_DIR}/custom"
export NGINX_CUSTOM_PROXY_TEMPLATE_DIR="${NGINX_CUSTOM_TEMPLATE_DIR}/proxy"
export NGINX_CUSTOM_GLOBAL_TEMPLATE_DIR="${NGINX_CUSTOM_TEMPLATE_DIR}/global"

# Configure services
echo "[ENTRYPOINT] Configuring services...";

source "${ENTRYPOINT_DIR}/user-setup.sh"
source "${ENTRYPOINT_DIR}/nginx.sh"
source "${ENTRYPOINT_DIR}/nginx-proxy.sh"
source "${ENTRYPOINT_DIR}/nginx-static.sh"
source "${ENTRYPOINT_DIR}/custom.sh"

echo "[ENTRYPOINT] Bootstrapping completed!";

# No exec here, as this script uses the base images extension mechanism at /docker-entrypoint.d/ (See Dockerfile)
