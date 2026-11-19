#!/bin/bash
echo "[ENTRYPOINT.python] Configuring Python (Gunicorn)";

# Validate the numeric gunicorn settings and derive the supervisor stop wait.
# This deliberately runs HERE — after the custom environment files were loaded
# (step 017) — so values set in /container/custom/env/*.env are validated and
# honored by the derivation too, not only values from the container environment.
#
# Bash arithmetic is dangerously lenient — leading zeros like "08" are parsed
# as octal ("value too great for base" aborts the boot mid-run with a confusing
# message) — so validate up front and fail with a clear error instead. The
# pattern rejects leading zeros on purpose.
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

process_tpl "gunicorn-conf"

echo "[ENTRYPOINT.python] Python (Gunicorn) configuration completed";
