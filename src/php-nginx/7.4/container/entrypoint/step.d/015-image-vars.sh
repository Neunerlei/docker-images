#!/bin/bash

echo "[ENTRYPOINT] Image configuration settings initialization started.";

# Set default production settings, can be overridden by environment variables
# If PHP_PROD_DEBUG is set to "true", enable more verbose error reporting for production
declare default_prod_display_errors="Off"
declare default_prod_display_startup_errors="Off"
declare default_prod_error_reporting="E_ALL & ~E_DEPRECATED & ~E_STRICT"
declare default_prod_opcache_validate_timestamps="0"
if [ "${PHP_PROD_DEBUG:-"false"}" == "true" ]; then
  default_prod_display_errors="On"
  default_prod_display_startup_errors="On"
  default_prod_error_reporting="E_ALL & ~E_DEPRECATED"
  default_prod_opcache_validate_timestamps="1"
fi

export PHP_TIMEZONE="${PHP_TIMEZONE:-${TZ}}" # TZ is by default UTC
export PHP_UPLOAD_MAX_FILESIZE="${PHP_UPLOAD_MAX_FILESIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
export PHP_POST_MAX_SIZE="${PHP_POST_MAX_SIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
export PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-"1024M"}"
export PHP_PROD_DISPLAY_ERRORS="${PHP_PROD_DISPLAY_ERRORS:-"${default_prod_display_errors}"}"
export PHP_PROD_DISPLAY_STARTUP_ERRORS="${PHP_PROD_DISPLAY_STARTUP_ERRORS:-"${default_prod_display_startup_errors}"}"
export PHP_PROD_ERROR_REPORTING="${PHP_PROD_ERROR_REPORTING:-"${default_prod_error_reporting}"}"
export PHP_PROD_OPCACHE_VALIDATE_TIMESTAMPS="${PHP_PROD_OPCACHE_VALIDATE_TIMESTAMPS:-"${default_prod_opcache_validate_timestamps}"}"
export PHP_WORKER_PROCESS_COUNT="${PHP_WORKER_PROCESS_COUNT:-"1"}"
export PHP_FPM_MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-"20"}"
export PHP_FPM_START_SERVERS="${PHP_FPM_START_SERVERS:-"2"}"
export PHP_FPM_MIN_SPARE_SERVERS="${PHP_FPM_MIN_SPARE_SERVERS:-"1"}"
export PHP_FPM_MAX_SPARE_SERVERS="${PHP_FPM_MAX_SPARE_SERVERS:-"4"}"
export PHP_FPM_MAX_REQUESTS="${PHP_FPM_MAX_REQUESTS:-"500"}"
export PHP_CONFIG_DIR="/usr/local/etc/php/conf.d"
export PHP_FPM_CONFIG_DIR="/usr/local/etc/php-fpm.d"

# Additional NGINX settings
# If NGINX_TRY_FILES is empty, assign the default using strong single quotes
if [ -z "$NGINX_TRY_FILES" ]; then
    NGINX_TRY_FILES='$uri $uri/ /index.php$is_args$args'
fi
export NGINX_TRY_FILES

# Derive APP_ENV from ENV if not explicitly set
if [ -z "${APP_ENV}" ]; then
  if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
    export APP_ENV="dev"
  else
    export APP_ENV="prod"
  fi
fi

# Derive APP_DEBUG from ENVIRONMENT and PHP_PROD_DEBUG if not explicitly set
if [ -z "${APP_DEBUG}" ]; then
  if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
    export APP_DEBUG="1"
  elif { [ "${ENVIRONMENT:-}" == "production" ] || [ "${ENVIRONMENT:-}" == "prod" ]; } && [ "${PHP_PROD_DEBUG:-}" == "true" ]; then
    export APP_DEBUG="1"
  elif [ "${APP_ENV}" == "development" ] || [ "${APP_ENV}" == "dev" ]; then
    export APP_DEBUG="1"
  else
    export APP_DEBUG="0"
  fi
fi

# Allow access to www-data
user_owned_directories_registry+=(
  "${PHP_CONFIG_DIR}"
  "${PHP_FPM_CONFIG_DIR}"
)

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
