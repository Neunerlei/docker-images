#!/bin/bash

echo "[ENTRYPOINT] Image configuration:"

# Additional NGINX settings
# If NGINX_TRY_FILES is empty, assign the default using strong single quotes
if [ -z "$NGINX_TRY_FILES" ]; then
    NGINX_TRY_FILES='$uri @nodeproxy'
fi
export NGINX_TRY_FILES

export NODE_SERVICE_PORT="${NODE_SERVICE_PORT:-"3000"}"
export NODE_WORKER_PROCESS_COUNT="${NODE_WORKER_PROCESS_COUNT:-"1"}"
export NODE_ENV="${NODE_ENV:-${ENVIRONMENT}}"

if [ -z "${CONTAINER_MODE}" ]; then
    # If the NODE_WORKER_COMMAND is set, set the CONTAINER_MODE environment variable to "worker", otherwise set it to "web"
    if [ -n "${NODE_WORKER_COMMAND}" ]; then
        export CONTAINER_MODE="worker"
    else
        export NODE_WEB_COMMAND="${NODE_WEB_COMMAND:-${default_node_web_command}}"
        export CONTAINER_MODE="web"
        feature_registry="${feature_registry} nginx"
    fi
    feature_registry="${feature_registry} supervisor"
fi

if [ "${CONTAINER_MODE}" = "worker" ]; then
    if [ -z "${NODE_WORKER_COMMAND}" ]; then
        # Theoretically, if used correctly, this should never happen, because if the NODE_WORKER_COMMAND is not set,
        # we set the CONTAINER_MODE to web, but we add this check just to be sure (if someone set CONTAINER_MODE to worker manually,
        # but forgot to set the NODE_WORKER_COMMAND, we want to catch this error and exit, instead of running an empty command and
        # exiting with a more cryptic error)
        echo "[ENTRYPOINT] ERROR: NODE_WORKER_COMMAND is not set, but CONTAINER_MODE is 'worker'. Exiting..."
        exit 1
    fi
elif [ "${CONTAINER_MODE}" = "web" ]; then
    if [ -z "${NODE_WEB_COMMAND}" ]; then
        if [ -e "/var/www/html/server.js" ]; then
            export NODE_WEB_COMMAND="node /var/www/html/server.js"
            echo "[ENTRYPOINT] INFO: NODE_WEB_COMMAND is not set, but found /var/www/html/server.js. Setting NODE_WEB_COMMAND to 'node /var/www/html/server.js'"
        else
            echo "[ENTRYPOINT] ERROR: NODE_WEB_COMMAND is not set, but CONTAINER_MODE is 'web'. Exiting..."
            exit 1
        fi
    fi
fi

user_owned_directories_registry+=(
    "/var/www/.npm"
    "/usr/local/lib/node_modules"
)
