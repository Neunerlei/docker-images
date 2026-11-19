#!/bin/bash

# Image environment for node-nginx — the file convention that replaced the
# former step.d/015-image-vars.sh. The environment orchestrator
# (step.d/015-environment.sh) sources this file and calls the functions at
# their correct pipeline positions:
#
#   image_env_features()  once, BEFORE the custom env files load (so
#                         mode-*/feat-* markers filter them)
#   image_env_defaults()  after EVERY derive pass (three times — must be
#                         idempotent; every default goes through default_var)
#   image_env_validate()  once, on the final values

# CONTAINER_MODE and features. Mode and features can NOT be changed from
# custom env files (NODE_WORKER_COMMAND in a .env has no effect) — that is
# the documented, unchanged behavior: the env files are marker-filtered
# using the mode, so it has to be known before they load.
image_env_features() {
    if [ -z "${CONTAINER_MODE}" ]; then
        # If the NODE_WORKER_COMMAND is set, set the CONTAINER_MODE environment variable to "worker", otherwise set it to "web"
        if [ -n "${NODE_WORKER_COMMAND}" ]; then
            export CONTAINER_MODE="worker"
        else
            export CONTAINER_MODE="web"
            feature_registry="${feature_registry} nginx"
        fi
        feature_registry="${feature_registry} supervisor"
    fi
}

# Runtime defaults. Runs three times; every value goes through default_var,
# so a user-set value survives every pass and a still-defaulted value is
# recomputed when its inputs changed (e.g. a .env ENVIRONMENT=development
# flipping NODE_ENV).
image_env_defaults() {
    # Additional NGINX settings (strong single quotes: $uri stays literal)
    default_var NGINX_TRY_FILES '$uri @nodeproxy'

    default_var NODE_SERVICE_PORT "3000"
    default_var NODE_WORKER_PROCESS_COUNT "1"
    default_var NODE_WORKER_STOP_WAIT_SECS "10"
    default_var NODE_ENV "${ENVIRONMENT}"

    # The server.js probe: if NODE_WEB_COMMAND is still empty, the mode is
    # web and the default app entrypoint exists, use it. Web-mode-only on
    # purpose — the old check never ran in worker or build mode either.
    # Tracked through default_var like every default, so a NODE_WEB_COMMAND
    # from a custom env file wins on the next pass — which is exactly why
    # this moved out of the old mode checks into the defaults: the old check
    # ran before the env files were loaded. The [ -z ] guard also makes the
    # log below fire only on the first pass.
    if [ "${CONTAINER_MODE}" = "web" ] && [ -z "${NODE_WEB_COMMAND}" ] && [ -e "/var/www/html/server.js" ]; then
        default_var NODE_WEB_COMMAND "node /var/www/html/server.js"
        echo "[ENTRYPOINT] INFO: NODE_WEB_COMMAND is not set, but found /var/www/html/server.js. Setting NODE_WEB_COMMAND to 'node /var/www/html/server.js'"
    fi
}

# Checks that only make sense on the FINAL values — running them here (after
# all env files loaded) is what makes a NODE_WEB_COMMAND from a custom env
# file actually work in web mode.
image_env_validate() {
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
            # Neither the environment, nor the env files, nor the server.js
            # probe provided a command — there is nothing to run in web mode.
            echo "[ENTRYPOINT] ERROR: NODE_WEB_COMMAND is not set, but CONTAINER_MODE is 'web'. Exiting..."
            exit 1
        fi
        echo "[ENTRYPOINT] INFO: CONTAINER_MODE is 'web' and NODE_WEB_COMMAND is set to '${NODE_WEB_COMMAND}'"
    fi
}
