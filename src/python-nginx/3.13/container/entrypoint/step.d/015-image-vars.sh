#!/bin/bash

echo "[ENTRYPOINT] Python image configuration settings initialization started.";

# Python application settings
export PYTHON_APP_MODULE="${PYTHON_APP_MODULE:-'server:app'}"
export PYTHON_WORKER_PROCESS_COUNT="${PYTHON_WORKER_PROCESS_COUNT:-"1"}"
export PYTHON_WORKER_STOP_WAIT_SECS="${PYTHON_WORKER_STOP_WAIT_SECS:-"10"}"

# Gunicorn settings
export GUNICORN_WORKERS="${GUNICORN_WORKERS:-4}"
export GUNICORN_WORKER_CLASS="${GUNICORN_WORKER_CLASS:-sync}"
export GUNICORN_LOG_LEVEL="${GUNICORN_LOG_LEVEL:-info}"

# Gunicorn longevity settings (defaults match gunicorn's own, so nothing
# changes unless a consumer opts in)
export GUNICORN_TIMEOUT="${GUNICORN_TIMEOUT:-30}"
export GUNICORN_GRACEFUL_TIMEOUT="${GUNICORN_GRACEFUL_TIMEOUT:-30}"
export GUNICORN_MAX_REQUESTS="${GUNICORN_MAX_REQUESTS:-0}"
export GUNICORN_MAX_REQUESTS_JITTER="${GUNICORN_MAX_REQUESTS_JITTER:-0}"

# All five values below feed bash arithmetic or supervisor verbatim. Bash
# arithmetic is dangerously lenient — leading zeros like "08" are parsed as
# octal ("value too great for base" aborts the boot mid-run with a confusing
# message) — so validate the numeric gunicorn settings up front and fail with
# a clear error instead. The pattern rejects leading zeros on purpose.
for _gunicorn_numeric_var in GUNICORN_TIMEOUT GUNICORN_GRACEFUL_TIMEOUT GUNICORN_MAX_REQUESTS GUNICORN_MAX_REQUESTS_JITTER; do
    _value="${!_gunicorn_numeric_var}"
    if ! [[ "${_value}" =~ ^(0|[1-9][0-9]*)$ ]]; then
        echo "[ENTRYPOINT] Error: ${_gunicorn_numeric_var} must be a plain integer without leading zeros (seconds / requests), got: '${_value}'." >&2
        exit 1
    fi
done
unset _gunicorn_numeric_var _value

# How long supervisor waits for gunicorn to shut down before SIGKILL.
# Default: the graceful timeout plus a margin, so the workers get the full
# graceful window (supervisor's own default of 10s would cut it short).
export GUNICORN_STOP_WAIT_SECS="${GUNICORN_STOP_WAIT_SECS:-$((GUNICORN_GRACEFUL_TIMEOUT + 10))}"
if ! [[ "${GUNICORN_STOP_WAIT_SECS}" =~ ^(0|[1-9][0-9]*)$ ]]; then
    echo "[ENTRYPOINT] Error: GUNICORN_STOP_WAIT_SECS must be a plain integer without leading zeros (seconds), got: '${GUNICORN_STOP_WAIT_SECS}'." >&2
    exit 1
fi

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
