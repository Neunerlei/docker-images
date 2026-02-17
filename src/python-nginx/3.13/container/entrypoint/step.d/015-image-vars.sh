#!/bin/bash

echo "[ENTRYPOINT] Python image configuration settings initialization started.";

# Python application settings
export PYTHON_APP_MODULE="${PYTHON_APP_MODULE:-'server:app'}"
export PYTHON_WORKER_PROCESS_COUNT="${PYTHON_WORKER_PROCESS_COUNT:-"1"}"

# Gunicorn settings
export GUNICORN_WORKERS="${GUNICORN_WORKERS:-4}"
export GUNICORN_WORKER_CLASS="${GUNICORN_WORKER_CLASS:-sync}"
export GUNICORN_LOG_LEVEL="${GUNICORN_LOG_LEVEL:-info}"

# Define the path to the Gunicorn socket
export GUNICORN_SOCKET="/run/gunicorn.sock"

# Derive APP_ENV and FLASK_ENV from ENVIRONMENT if not explicitly set.
if [ -z "${APP_ENV}" ]; then
  if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
    export APP_ENV="dev"
    export FLASK_ENV="development"
  else
    export APP_ENV="prod"
    export FLASK_ENV="production"
  fi
fi

# Additional NGINX settings
# If NGINX_TRY_FILES is empty, assign the default using strong single quotes
if [ -z "$NGINX_TRY_FILES" ]; then
    NGINX_TRY_FILES='/static/$uri @pythonproxy'
fi
export NGINX_TRY_FILES

# Derive APP_DEBUG from ENVIRONMENT if not explicitly set.
if [ -z "${APP_DEBUG}" ]; then
  if [ "${ENVIRONMENT:-}" == "development" ] || [ "${ENVIRONMENT:-}" == "dev" ]; then
    export APP_DEBUG="1"
  elif [ "${APP_ENV}" == "development" ] || [ "${APP_ENV}" == "dev" ]; then
    export APP_DEBUG="1"
  else
    export APP_DEBUG="0"
  fi
fi

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
