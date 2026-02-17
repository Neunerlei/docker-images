# Gunicorn configuration file

# The socket to bind to.
bind = "unix:${GUNICORN_SOCKET}"

# The number of worker processes.
workers = "${GUNICORN_WORKERS}"

# The type of worker processes.
worker_class = "${GUNICORN_WORKER_CLASS}"

# The log level.
loglevel = "${GUNICORN_LOG_LEVEL}"

# The user and group to run as.
user = "www-data"
group = "www-data"

# The application to run.
# This variable will be provided by the entrypoint.
# We can't use ${...} syntax here as this is a Python file, not a simple text template.
# The entrypoint will need to render this dynamically.
wsgi_app = "${PYTHON_APP_MODULE}"
