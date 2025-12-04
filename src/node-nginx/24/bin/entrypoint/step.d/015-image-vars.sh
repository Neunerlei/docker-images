#!/bin/bash

echo "[ENTRYPOINT] Image configuration:";

# Check for default web entry script
declare default_node_web_command=""
declare default_web_entrypoint_script="/var/www/html/server.js"
if [ -f "${default_web_entrypoint_script}" ]; then
  default_node_web_command="node ${default_web_entrypoint_script}"
fi

export NODE_SERVICE_PORT="${NODE_SERVICE_PORT:-"3000"}"
export NODE_WORKER_PROCESS_COUNT="${NODE_WORKER_PROCESS_COUNT:-"1"}"
export NODE_ENV="${NODE_ENV:-${ENVIRONMENT}}"

if [ -z "${CONTAINER_MODE}" ] ; then
  # If the NODE_WORKER_COMMAND is set, set the CONTAINER_MODE environment variable to "worker", otherwise set it to "web"
  if [ -n "${NODE_WORKER_COMMAND}" ]; then
    export CONTAINER_MODE="worker"
  else
    # If in web mode, we require the NODE_WEB_COMMAND to be set, otherwise exit with an error
    if [ -z "${NODE_WEB_COMMAND}" ] && [ -e "${default_node_web_command}" ] ; then
      echo "[ENTRYPOINT] ERROR: NODE_WEB_COMMAND is not set, but CONTAINER_MODE is 'web'. Exiting...";
      exit 1
    fi

    export NODE_WEB_COMMAND="${NODE_WEB_COMMAND:-${default_node_web_command}}"
    export CONTAINER_MODE="web"
    feature_registry="${feature_registry} nginx"
  fi
  feature_registry="${feature_registry} supervisor"
fi

user_owned_directories_registry+=(
  "/var/www/.npm"
)
