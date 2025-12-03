#!/bin/bash

echo "[ENTRYPOINT] Image configuration:";

export PHP_TIMEZONE="${PHP_TIMEZONE:-${TZ}}" # TZ is by default UTC
export PHP_UPLOAD_MAX_FILESIZE="${PHP_UPLOAD_MAX_FILESIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
export PHP_POST_MAX_SIZE="${PHP_POST_MAX_SIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
export PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-"1024M"}"
export PHP_PROD_DISPLAY_ERRORS="${PHP_PROD_DISPLAY_ERRORS:-"Off"}"
export PHP_PROD_DISPLAY_STARTUP_ERRORS="${PHP_PROD_DISPLAY_STARTUP_ERRORS:-"Off"}"
export PHP_WORKER_PROCESS_COUNT="${PHP_WORKER_PROCESS_COUNT:-"1"}"
export PHP_FPM_MAX_CHILDREN="${PHP_FPM_MAX_CHILDREN:-"20"}"
export PHP_FPM_START_SERVERS="${PHP_FPM_START_SERVERS:-"2"}"
export PHP_FPM_MIN_SPARE_SERVERS="${PHP_FPM_MIN_SPARE_SERVERS:-"1"}"
export PHP_FPM_MAX_SPARE_SERVERS="${PHP_FPM_MAX_SPARE_SERVERS:-"4"}"
export PHP_FPM_MAX_REQUESTS="${PHP_FPM_MAX_REQUESTS:-"500"}"
export APP_ENV="${APP_ENV:-${ENVIRONMENT}}"
export PHP_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/php"
export PHP_CUSTOM_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/php/custom"
export PHP_CONFIG_DIR="/usr/local/etc/php/conf.d"
export PHP_FPM_CONFIG_DIR="/usr/local/etc/php-fpm.d"

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
