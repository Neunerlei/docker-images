#!/bin/bash
set -e

echo "[ENTRYPOINT] Starting Node.js bootstrapping process...";

ENTRYPOINT_DIR="$(dirname $(realpath "${BASH_SOURCE[0]}"))/entrypoint"
source "${ENTRYPOINT_DIR}/util/utils.sh"

# Check for default web entry script
DEFAULT_NODE_WEB_COMMAND=""
DEFAULT_WEB_ENTRY_SCRIPT="/var/www/html/server.js"
if [ -f "${DEFAULT_WEB_ENTRY_SCRIPT}" ]; then
  DEFAULT_NODE_WEB_COMMAND="node ${DEFAULT_WEB_ENTRY_SCRIPT}"
fi

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
export NODE_SERVICE_PORT="${NODE_SERVICE_PORT:-"3000"}"
echo "   - NODE_SERVICE_PORT=${NODE_SERVICE_PORT}";
export NODE_WORKER_PROCESS_COUNT="${NODE_WORKER_PROCESS_COUNT:-"1"}"
echo "   - NODE_WORKER_PROCESS_COUNT=${NODE_WORKER_PROCESS_COUNT}";
export NODE_ENV="${NODE_ENV:-${ENVIRONMENT}}"
echo "   - NODE_ENV=${NODE_ENV}";
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

# If the NODE_WORKER_COMMAND is set, set the CONTAINER_MODE environment variable to "worker", otherwise set it to "web"
if [ -n "${NODE_WORKER_COMMAND}" ]; then
  export CONTAINER_MODE="worker"
  echo "   - NODE_WORKER_COMMAND=${NODE_WORKER_COMMAND}";
  echo "   - CONTAINER_MODE=${CONTAINER_MODE}";
else
  # If in web mode, we require the NODE_WEB_COMMAND to be set, otherwise exit with an error
  if [ -z "${NODE_WEB_COMMAND}" ] && [ -e "${DEFAULT_NODE_WEB_COMMAND}" ] ; then
    echo "[ENTRYPOINT] ERROR: NODE_WEB_COMMAND is not set, but CONTAINER_MODE is 'web'. Exiting...";
    exit 1
  fi

  export NODE_WEB_COMMAND="${NODE_WEB_COMMAND:-$DEFAULT_NODE_WEB_COMMAND}"
  echo "   - NODE_WEB_COMMAND=${NODE_WEB_COMMAND}";
  export CONTAINER_MODE="web"
  echo "   - CONTAINER_MODE=${CONTAINER_MODE}";
fi

# Setting directories for later use
export NGINX_DIR="/etc/nginx"
export NGINX_SNIPPET_DIR="$NGINX_DIR/snippets"
export NGINX_SERVICE_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/service.d"
export NGINX_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/nginx"
export NGINX_CUSTOM_TEMPLATE_DIR="${NGINX_TEMPLATE_DIR}/custom"
export SUPERVISOR_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/supervisor"
export SUPERVISOR_CONFIG_DIR="/etc/supervisor/conf.d"

# Configure services
echo "[ENTRYPOINT] Configuring services...";

source "${ENTRYPOINT_DIR}/user-setup.sh"
source "${ENTRYPOINT_DIR}/nginx.sh"
source "${ENTRYPOINT_DIR}/supervisor.sh"
source "${ENTRYPOINT_DIR}/custom.sh"

echo "[ENTRYPOINT] Bootstrapping completed, starting command \"$@\"...";
exec "$@"
