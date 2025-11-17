#!/bin/bash
set -e

echo "[ENTRYPOINT] Starting Node.js bootstrapping process...";

# Configurable default values
DEFAULT_NGINX_DOC_ROOT="/var/www/html/public"
DEFAULT_NGINX_CERT_PATH="/etc/ssl/certs/cert.pem"
DEFAULT_NGINX_KEY_PATH="/etc/ssl/certs/key.pem"
DEFAULT_MAX_UPLOAD_SIZE="100M"
DEFAULT_NODE_SERVICE_PORT="3000"
DEFAULT_NODE_WORKER_PROCESS_COUNT="1"
DEFAULT_NODE_WEB_COMMAND=""

# Check for default web entry script
DEFAULT_WEB_ENTRY_SCRIPT="/var/www/html/server.js"
if [ -f "${DEFAULT_WEB_ENTRY_SCRIPT}" ]; then
  DEFAULT_NODE_WEB_COMMAND="node ${DEFAULT_WEB_ENTRY_SCRIPT}"
fi

# Determine effective max upload size
MAX_UPLOAD_SIZE_EFFECTIVE="${MAX_UPLOAD_SIZE:-$DEFAULT_MAX_UPLOAD_SIZE}"

# Load environment variables
export NGINX_DOC_ROOT="${NGINX_DOC_ROOT:-$DEFAULT_NGINX_DOC_ROOT}"
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-$MAX_UPLOAD_SIZE_EFFECTIVE}"
export NGINX_CERT_PATH="${NGINX_CERT_PATH:-$DEFAULT_NGINX_CERT_PATH}"
export NGINX_KEY_PATH="${NGINX_KEY_PATH:-$DEFAULT_NGINX_KEY_PATH}"
export NODE_SERVICE_PORT="${NODE_SERVICE_PORT:-$DEFAULT_NODE_SERVICE_PORT}"
export NODE_WEB_COMMAND="${NODE_WEB_COMMAND:-$DEFAULT_NODE_WEB_COMMAND}"
export NODE_WORKER_PROCESS_COUNT="${NODE_WORKER_PROCESS_COUNT:-$DEFAULT_NODE_WORKER_PROCESS_COUNT}"

# Inherit the NODE_ENV environment variable from APP_ENV if the latter is set, the former is not set
if [ -z "${NODE_ENV}" ] && [ -n "${APP_ENV}" ]; then
  if [ "${APP_ENV}" == "prod" ] || [ "${APP_ENV}" == "production" ]; then
    export NODE_ENV="production"
  elif [ "${APP_ENV}" == "development" ] || [ "${APP_ENV}" == "dev" ]; then
    export NODE_ENV="development"
  else
    export NODE_ENV="${APP_ENV}"
  fi
fi

# If the NODE_WORKER_COMMAND is set, set the CONTAINER_MODE environment variable to "worker", otherwise set it to "web"
if [ -n "${NODE_WORKER_COMMAND}" ]; then
  export CONTAINER_MODE="worker"
  echo "[ENTRYPOINT] Detected NODE_WORKER_COMMAND, executing: ${NODE_WORKER_COMMAND}";
else
  # If in web mode, we require the NODE_WEB_COMMAND to be set, otherwise exit with an error
  if [ -z "${NODE_WEB_COMMAND}" ]; then
    echo "[ENTRYPOINT] ERROR: NODE_WEB_COMMAND is not set, but CONTAINER_MODE is 'web'. Exiting...";
    exit 1
  else
    export NODE_WEB_COMMAND
    echo "[ENTRYPOINT] Detected NODE_WEB_COMMAND, executing: ${NODE_WEB_COMMAND}";
  fi
  export CONTAINER_MODE="web"
fi

# Configure services
echo "[ENTRYPOINT] Configuring services in mode: ${CONTAINER_MODE}...";

ENTRYPOINT_DIR="$(dirname $(realpath "${BASH_SOURCE[0]}"))/entrypoint"
source "${ENTRYPOINT_DIR}/util/render-template.sh"
source "${ENTRYPOINT_DIR}/user-setup.sh"
source "${ENTRYPOINT_DIR}/nginx.sh"
source "${ENTRYPOINT_DIR}/supervisor.sh"
source "${ENTRYPOINT_DIR}/custom.sh"

echo "[ENTRYPOINT] Bootstrapping completed, starting command...";
exec "$@"
