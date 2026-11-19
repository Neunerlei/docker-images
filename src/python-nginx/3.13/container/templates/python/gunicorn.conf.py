# Gunicorn configuration file

# The socket to bind to.
bind = "unix:${GUNICORN_SOCKET}"

# The number of worker processes.
workers = "${GUNICORN_WORKERS}"

# The type of worker processes.
worker_class = "${GUNICORN_WORKER_CLASS}"

# The log level.
loglevel = "${GUNICORN_LOG_LEVEL}"

# The number of seconds a worker may handle a request before it is killed.
# NOTE: NGINX sits in front of gunicorn and applies its own
# proxy_read_timeout (NGINX_PROXY_READ_TIMEOUT, default 60s) — raise both
# together, or nginx will answer 504 before this timeout is ever reached.
timeout = "${GUNICORN_TIMEOUT}"

# The number of seconds to wait for workers during a graceful shutdown
# before they are force-killed. Supervisor must allow at least this long
# (GUNICORN_STOP_WAIT_SECS) or it SIGKILLs the workers first.
graceful_timeout = "${GUNICORN_GRACEFUL_TIMEOUT}"

# Restart workers after the given number of requests (0 = never) to mitigate
# memory leaks. Jitter spreads the restarts so not all workers recycle at once.
max_requests = "${GUNICORN_MAX_REQUESTS}"
max_requests_jitter = "${GUNICORN_MAX_REQUESTS_JITTER}"

# The user and group to run as.
user = "www-data"
group = "www-data"

# The application to run.
# This variable will be provided by the entrypoint.
# We can't use ${...} syntax here as this is a Python file, not a simple text template.
# The entrypoint will need to render this dynamically.
wsgi_app = "${PYTHON_APP_MODULE}"
