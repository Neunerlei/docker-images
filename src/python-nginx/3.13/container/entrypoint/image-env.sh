#!/bin/bash

# Image environment for python-nginx — the file convention that replaced the
# former step.d/015-image-vars.sh. The environment orchestrator
# (step.d/015-environment.sh) sources this file and calls the functions at
# their correct pipeline positions:
#
#   image_env_features()  once, BEFORE the custom env files load (so
#                         mode-*/feat-* markers filter them)
#   image_env_defaults()  after EVERY derive pass (three times — must be
#                         idempotent; every default goes through default_var)
#   image_env_validate()  once, on the final values (not used by this image —
#                         the gunicorn validation lives in step 018-python.sh,
#                         which runs after the orchestrator)

# CONTAINER_MODE and features. Mode and features can NOT be changed from
# custom env files (PYTHON_WORKER_COMMAND in a .env has no effect) — that is
# the documented, unchanged behavior: the env files are marker-filtered
# using the mode, so it has to be known before they load.
image_env_features() {
    # In web mode, we need Nginx and Supervisor
    if [ -z "${CONTAINER_MODE}" ]; then
        if [ -n "${PYTHON_WORKER_COMMAND}" ]; then
            export CONTAINER_MODE="worker"
        else
            export CONTAINER_MODE="web"
            feature_registry="${feature_registry} nginx"
        fi

        # Ensure supervisor is always enabled
        feature_registry="${feature_registry} supervisor"
    fi
}

# Python application, worker and gunicorn defaults. Runs three times; every
# value goes through default_var, so a user-set value survives every pass
# and a still-defaulted value is recomputed when its inputs changed (e.g. a
# .env ENVIRONMENT=development flipping APP_ENV).
image_env_defaults() {
    # Python application settings
    default_var PYTHON_APP_MODULE "server:app"
    default_var PYTHON_WORKER_PROCESS_COUNT "1"
    default_var PYTHON_WORKER_STOP_WAIT_SECS "10"

    # Gunicorn settings
    default_var GUNICORN_WORKERS "4"
    default_var GUNICORN_WORKER_CLASS "sync"
    default_var GUNICORN_LOG_LEVEL "info"

    # Gunicorn longevity settings (defaults match gunicorn's own, so nothing
    # changes unless a consumer opts in). Validation and the stopwaitsecs
    # derivation happen in step 018 — after the custom environment files
    # were loaded, so values from /container/custom/env/*.env are validated
    # and honored too.
    default_var GUNICORN_TIMEOUT "30"
    default_var GUNICORN_GRACEFUL_TIMEOUT "30"
    default_var GUNICORN_MAX_REQUESTS "0"
    default_var GUNICORN_MAX_REQUESTS_JITTER "0"

    # Define the path to the Gunicorn socket (constant, idempotent re-export)
    export GUNICORN_SOCKET="/run/gunicorn.sock"

    # Derive APP_ENV and FLASK_ENV from ENVIRONMENT (inputs first — APP_DEBUG
    # below reads APP_ENV)
    if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
        default_var APP_ENV "dev"
        default_var FLASK_ENV "development"
    else
        default_var APP_ENV "prod"
        default_var FLASK_ENV "production"
    fi

    # Additional NGINX settings (strong single quotes: $uri stays literal)
    default_var NGINX_TRY_FILES '/static/$uri @pythonproxy'

    # Derive APP_DEBUG from ENVIRONMENT / APP_ENV
    if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ] || [ "${APP_ENV}" == "development" ] || [ "${APP_ENV}" == "dev" ]; then
        default_var APP_DEBUG "1"
    else
        default_var APP_DEBUG "0"
    fi
}
