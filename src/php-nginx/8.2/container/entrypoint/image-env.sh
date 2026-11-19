#!/bin/bash

# Image environment for php-nginx — the file convention that replaced the
# former step.d/015-image-vars.sh. The environment orchestrator
# (step.d/015-environment.sh) sources this file and calls the functions at
# their correct pipeline positions:
#
#   image_env_features()  once, BEFORE the custom env files load (so
#                         mode-*/feat-* markers filter them)
#   image_env_defaults()  after EVERY derive pass (three times — must be
#                         idempotent; every default goes through default_var)
#   image_env_validate()  once, on the final values (not used by this image)

# CONTAINER_MODE and features. Mode and features can NOT be changed from
# custom env files (PHP_WORKER_COMMAND in a .env has no effect) — that is
# the documented, unchanged behavior: the env files are marker-filtered
# using the mode, so it has to be known before they load.
image_env_features() {
    if [ -z "${CONTAINER_MODE}" ] ; then
        # If the PHP_WORKER_COMMAND is set, set the CONTAINER_MODE environment variable to "worker", otherwise set it to "web"
        if [ -n "${PHP_WORKER_COMMAND}" ]; then
            export CONTAINER_MODE="worker"
        else
            export CONTAINER_MODE="web"
            feature_registry="${feature_registry} nginx"
        fi

        # Ensure supervisor is always enabled
        feature_registry="${feature_registry} supervisor"
    fi
}

# PHP, FPM and app defaults. Runs three times; every value goes through
# default_var, so a user-set value survives every pass and a still-defaulted
# value is recomputed when its inputs changed (e.g. a .env
# MAX_UPLOAD_SIZE=500M flipping PHP_UPLOAD_MAX_FILESIZE, or a .env
# ENVIRONMENT=development flipping APP_ENV/APP_DEBUG).
image_env_defaults() {
    default_var PHP_TIMEZONE "${TZ}" # TZ is by default UTC
    default_var PHP_UPLOAD_MAX_FILESIZE "${MAX_UPLOAD_SIZE}"
    default_var PHP_POST_MAX_SIZE "${MAX_UPLOAD_SIZE}"
    default_var PHP_MEMORY_LIMIT "1024M"

    # Set default production settings, can be overridden by environment variables
    # If PHP_PROD_DEBUG is set to "true", enable more verbose error reporting for production.
    # The local default_prod_* values are recomputed on EVERY pass (PHP_PROD_DEBUG
    # may come from a custom env file), and the tracked defaults follow along.
    local default_prod_display_errors="Off"
    local default_prod_display_startup_errors="Off"
    local default_prod_error_reporting="E_ALL & ~E_DEPRECATED & ~E_STRICT"
    local default_prod_opcache_validate_timestamps="0"
    if [ "${PHP_PROD_DEBUG:-"false"}" == "true" ]; then
        default_prod_display_errors="On"
        default_prod_display_startup_errors="On"
        default_prod_error_reporting="E_ALL & ~E_DEPRECATED"
        default_prod_opcache_validate_timestamps="1"
    fi
    default_var PHP_PROD_DISPLAY_ERRORS "${default_prod_display_errors}"
    default_var PHP_PROD_DISPLAY_STARTUP_ERRORS "${default_prod_display_startup_errors}"
    default_var PHP_PROD_ERROR_REPORTING "${default_prod_error_reporting}"
    default_var PHP_PROD_OPCACHE_VALIDATE_TIMESTAMPS "${default_prod_opcache_validate_timestamps}"

    default_var PHP_WORKER_PROCESS_COUNT "1"
    default_var PHP_WORKER_STOP_WAIT_SECS "10"
    default_var PHP_FPM_MAX_CHILDREN "20"
    default_var PHP_FPM_START_SERVERS "2"
    default_var PHP_FPM_MIN_SPARE_SERVERS "1"
    default_var PHP_FPM_MAX_SPARE_SERVERS "4"
    default_var PHP_FPM_MAX_REQUESTS "500"

    # Constants (idempotent re-exports)
    export PHP_CONFIG_DIR="/usr/local/etc/php/conf.d"
    export PHP_FPM_CONFIG_DIR="/usr/local/etc/php-fpm.d"

    # Additional NGINX settings (strong single quotes: $uri stays literal)
    default_var NGINX_TRY_FILES '$uri $uri/ /index.php$is_args$args'

    # Derive APP_ENV from ENVIRONMENT (inputs first — APP_DEBUG below reads it)
    if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
        default_var APP_ENV "dev"
    else
        default_var APP_ENV "prod"
    fi

    # Derive APP_DEBUG from ENVIRONMENT and PHP_PROD_DEBUG
    if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
        default_var APP_DEBUG "1"
    elif { [ "${ENVIRONMENT:-}" == "production" ] || [ "${ENVIRONMENT:-}" == "prod" ]; } && [ "${PHP_PROD_DEBUG:-}" == "true" ]; then
        default_var APP_DEBUG "1"
    elif [ "${APP_ENV}" == "development" ] || [ "${APP_ENV}" == "dev" ]; then
        default_var APP_DEBUG "1"
    else
        default_var APP_DEBUG "0"
    fi
}
