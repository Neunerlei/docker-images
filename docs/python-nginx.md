# Python Images - with NGINX

Welcome to the `python-nginx` images!

These images are designed as self-contained, high-performance services. The philosophy is to provide a complete, production-ready Python application runtime that includes a pre-configured NGINX web server as a reverse proxy and **Gunicorn** as the WSGI application server.

Think of this image as a "service-in-a-box." You put your code in, configure it with environment variables, and it just works—whether in local development or behind a production load balancer.

> **Shared behavior:** concepts that apply to all images — the entrypoint, container modes, customization, templating, read-only/Kubernetes operation and more — are documented once in [Shared Concepts](./common.md). This document keeps everything specific to this image.

## Tags

Here you can find [all available tags](https://docker.neunerlei.eu/neunerlei-python-nginx-tags.html) of this image.

## Quick Start

The quickest way to get started is with a `docker-compose.yml` file. This example runs your application in "web" mode, mounts your code, and exposes it on port 8080.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/python-nginx:latest # Or your desired version
    ports:
      - "8080:80"
    volumes:
      - ./your-python-project:/var/www/html
    environment:
      # In development, this shows a helpful page with env vars
      - ENVIRONMENT=dev
      # Optional: Set a larger upload size for NGINX
      - MAX_UPLOAD_SIZE=250M
```

Place your Python project in the `./your-python-project` directory, ensure your WSGI application callable lives at `/var/www/html/server.py` and is named `app` (or adjust `PYTHON_APP_MODULE`), and run `docker-compose up`. You can now access your application at `http://localhost:8080`.

> **Important:** The image uses a Python virtual environment located at `/opt/venv` (symlinked to `/var/www/venv` for convenience). All dependencies are installed into this venv, and the `PATH` is pre-configured so that `python` and `pip` resolve to the venv's binaries automatically.

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, this script reads your environment variables to decide how to configure itself. It operates in one of two primary modes:

1. **Web Mode (Default):** This is the standard mode. The script starts and configures both NGINX (as a reverse proxy) and **Gunicorn** (as the WSGI application server) to serve traffic over HTTP. NGINX proxies requests to Gunicorn via a Unix socket.
2. **Worker Mode:** Activated by setting the `PYTHON_WORKER_COMMAND` variable. In this mode, NGINX is disabled, and Supervisor is configured to run your specified command instead. This is perfect for running queue workers, schedulers, or other long-running background tasks.

## Configuration via Environment Variables

This image is configured almost entirely through environment variables. This allows you to use the same image for different purposes (web vs. worker, dev vs. prod) without rebuilding it.

| Variable                      | Description                                                                                                                                                                           | Default Value                        |
|:------------------------------|:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:-------------------------------------|
| **General**                   |                                                                                                                                                                                       |                                      |
| `PUID`                        | The user ID to run processes as (`www-data`). Useful for matching host file permissions.                                                                                              | `33`                                 |
| `PGID`                        | The group ID to run processes as (`www-data`). Useful for matching host file permissions.                                                                                             | `33`                                 |
| `CONTAINER_MODE`              | Read-only. Automatically set to `web`, `worker` or `build`.                                                                                                                           | `web`                                |
| `MAX_UPLOAD_SIZE`             | A convenient variable to set NGINX's `client_max_body_size`.                                                                                                                          | `100M`                               |
| `USER_OWNED_DIRECTORIES`      | Additional directories (space separated) that should be owned by the `www-data` user, e.g. for mounted volumes the application writes into. They are created when missing.             | (none)                               |
| `MAX_UPLOAD_SIZE_BYTES`       | Read-only. The byte value of `MAX_UPLOAD_SIZE`, calculated by the entrypoint script.                                                                                                  | (calculated)                         |
| `ENVIRONMENT`                 | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production.                                                                      | `production`                         |
| `APP_ENV`                     | The application environment flag. Derived from `ENVIRONMENT` if not explicitly set.                                                                                                   | (derived)                            |
| `FLASK_ENV`                   | The Flask environment variable. Derived from `ENVIRONMENT` if not explicitly set.                                                                                                     | (derived)                            |
| `APP_DEBUG`                   | Debug flag for the application. Derived from `ENVIRONMENT` / `APP_ENV` if not explicitly set.                                                                                         | (derived: `1` in dev, `0` otherwise) |
| **Project**                   |                                                                                                                                                                                       |                                      |
| `DOCKER_PROJECT_HOST`         | The public hostname for your application (available for your app).                                                                                                                    | `localhost`                          |
| `DOCKER_PROJECT_PATH`         | The public root path of the entire project.                                                                                                                                           | `/`                                  |
| `DOCKER_PROJECT_PROTOCOL`     | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                                                                                            | `http`                               |
| `DOCKER_SERVICE_PROTOCOL`     | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                                                                                     | (derived)                            |
| `DOCKER_SERVICE_PATH`         | The sub-path for this specific service within the project.                                                                                                                            | `/`                                  |
| `DOCKER_SERVICE_ABS_PATH`     | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                                                                                      | (derived)                            |
| **NGINX**                     |                                                                                                                                                                                       |                                      |
| `NGINX_DOC_ROOT`              | The document root NGINX serves static files from.                                                                                                                                     | `/var/www/html/public`               |
| `NGINX_CLIENT_MAX_BODY_SIZE`  | Sets `client_max_body_size` in NGINX. **Please prefer `MAX_UPLOAD_SIZE`**                                                                                                             | Matches `MAX_UPLOAD_SIZE`            |
| `NGINX_CERT_PATH`             | Path to the SSL certificate (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                   | `/etc/ssl/certs/custom/cert.pem`     |
| `NGINX_KEY_PATH`              | Path to the SSL key (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                           | `/etc/ssl/certs/custom/key.pem`      |
| `NGINX_PROXY_CONNECT_TIMEOUT` | Sets `proxy_connect_timeout` in NGINX. This value defines the timeout for establishing a connection with a proxied server.                                                            | `5s`                                 |
| `NGINX_PROXY_READ_TIMEOUT`    | Sets `proxy_read_timeout` in NGINX. This value defines the timeout for reading a response from a proxied server.                                                                      | `60s`                                |
| `NGINX_PROXY_SEND_TIMEOUT`    | Sets `proxy_send_timeout` in NGINX. This value defines the timeout for transmitting a request to a proxied server.                                                                    | `60s`                                |
| `NGINX_KEEPALIVE_TIMEOUT`     | Sets `keepalive_timeout` in NGINX. This value defines the timeout for keeping connections alive with clients. If omitted, automatically calculated based on the other TIMEOUT values. | (calculated)                         |
| `NGINX_TRY_FILES`             | Sets the `try_files` directive in the root location of the nginx server.                                                                                                              | `/static/$uri @pythonproxy`          |
| `NGINX_BASIC_AUTH`            | Enables basic auth for the **whole server**. Format: `username clear-password`; additional users via `NGINX_BASIC_AUTH_1..n` (e.g. `NGINX_BASIC_AUTH_2="user2 pass2"`), login dialog realm via `NGINX_BASIC_AUTH_REALM` (default `Restricted`). | (disabled) |
| **Gunicorn (Web Mode)**       |                                                                                                                                                                                       |                                      |
| `PYTHON_APP_MODULE`           | The WSGI application module in `module:callable` format. This tells Gunicorn where to find your application.                                                                          | `server:app`                         |
| `GUNICORN_WORKERS`            | The number of Gunicorn worker processes.                                                                                                                                              | `4`                                  |
| `GUNICORN_WORKER_CLASS`       | The type of Gunicorn worker processes (e.g., `sync`, `gevent`, `uvicorn.workers.UvicornWorker`).                                                                                      | `sync`                               |
| `GUNICORN_LOG_LEVEL`          | The Gunicorn log level (e.g., `debug`, `info`, `warning`, `error`, `critical`).                                                                                                       | `info`                               |
| `GUNICORN_SOCKET`             | Read-only. The path to the Unix socket Gunicorn binds to and NGINX proxies to.                                                                                                        | `/run/gunicorn.sock`                 |
| **Python Worker Mode**        |                                                                                                                                                                                       |                                      |
| `PYTHON_WORKER_COMMAND`       | The command to execute in worker mode. **Setting this enables worker mode.**                                                                                                          |                                      |
| `PYTHON_WORKER_PROCESS_COUNT` | The number of worker processes to run (`numprocs` in Supervisor).                                                                                                                     | `1`                                  |
| `PYTHON_WORKER_STOP_WAIT_SECS`| The number of seconds Supervisor waits for the worker process to stop gracefully before sending SIGKILL (`stopwaitsecs` in Supervisor).                                               | `10`                                 |

### ENVIRONMENT, `APP_ENV`, and `FLASK_ENV` Derivation

The `ENVIRONMENT` variable is a high-level switch for the container's operational mode. It is shared across all images in this ecosystem and influences NGINX configurations, logging verbosity, and other entrypoint behaviors.

- **Possible Values:** `production` (or `prod`) and `development` (or `dev`).
- **Default:** `production`.
- **Rule:** Any value other than `development` or `dev` is treated as a production environment.

**`APP_ENV` and `FLASK_ENV` Derivation Logic:**

To align with standard Python/Flask practices, the `APP_ENV` and `FLASK_ENV` variables are automatically derived from `ENVIRONMENT`. You generally do not need to set them yourself.

1. If `ENVIRONMENT` is set to `production` or `prod`, `APP_ENV` defaults to `prod` and `FLASK_ENV` defaults to `production`.
2. If `ENVIRONMENT` is set to `development` or `dev`, `APP_ENV` defaults to `dev` and `FLASK_ENV` defaults to `development`.
3. If you set `APP_ENV` explicitly, **your value will always take precedence**. This allows you to run in a `production` container `ENVIRONMENT` (with optimized NGINX settings) while having `APP_ENV` set to `staging`, for example.

Additionally, `APP_DEBUG` is automatically derived:

- It is set to `1` when `ENVIRONMENT` or `APP_ENV` is `development` or `dev`.
- It is set to `0` otherwise.
- You can override it by setting `APP_DEBUG` explicitly.

### Path Composition: `PROJECT_PATH` + `SERVICE_PATH`

Public URLs compose from `DOCKER_PROJECT_PATH` + `DOCKER_SERVICE_PATH` into the read-only `DOCKER_SERVICE_ABS_PATH`.

See [Path Composition](./common.md#path-composition) in the shared documentation.

### PYTHON_WORKER_STOP_WAIT_SECS  and Docker Stop Timeout

Graceful shutdown: `*_WORKER_STOP_WAIT_SECS` defines how long the worker may finish after SIGTERM — raise Docker's `stop_grace_period` above it, or the timeout never takes effect.

See [Worker Mode](./common.md#worker-mode) in the shared documentation.

### MAX_UPLOAD_SIZE and friends

`MAX_UPLOAD_SIZE` (default `100M`) sets all upload limits at once; `MAX_UPLOAD_SIZE_BYTES` is the parsed read-only byte value. Prefer it over the individual overrides.

See [MAX_UPLOAD_SIZE and Friends](./common.md#max_upload_size-and-friends) in the shared documentation for the full explanation.

## Web Mode In-Depth

In `web` mode, the entrypoint script configures NGINX and Gunicorn to serve your application. NGINX acts as the front-facing server, handling static files and proxying dynamic requests to Gunicorn over a **Unix socket** (`/run/gunicorn.sock`).

### HTTP vs. HTTPS

Direct HTTPS (`DOCKER_PROJECT_PROTOCOL=https` with mounted certificates) or, recommended, TLS terminated at an outer gateway (`DOCKER_SERVICE_PROTOCOL=http`).

See [HTTP vs. HTTPS](./common.md#http-vs-https) in the shared documentation for the full explanation.

### Customizing NGINX with Intelligent Snippets

This image uses a flexible system for extending the base NGINX configuration. You can add any number of custom configuration files, and the container's entrypoint script will intelligently process and include them based on their name and your environment variables.

You can learn more about this powerful feature in [Advanced Customization](#advanced-customization-templating-and-overrides), especially in the [Adding Custom NGINX Snippets](#1-adding-custom-nginx-snippets-marker-aware-templates) section.

## Worker Mode In-Depth

If you provide the `PYTHON_WORKER_COMMAND` environment variable, the image switches to worker mode. This is the idiomatic way to run background tasks using the exact same Python environment as your web application.

**Example 1: Running a background processing script**

```yaml
services:
  my-app-worker:
    image: neunerlei/python-nginx:latest
    volumes:
      - ./your-python-project:/var/www/html
    environment:
      # This enables worker mode and defines the command
      - PYTHON_WORKER_COMMAND=python /var/www/html/queue_worker.py
      # Optional: run 4 worker processes
      - PYTHON_WORKER_PROCESS_COUNT=4
```

**Example 2: Running a "cron" task**

For simple scheduled tasks without a full cron daemon, you can use a loop managed by Supervisor.

```yaml
services:
  my-app-scheduler:
    image: neunerlei/python-nginx:latest
    volumes:
      - ./your-python-project:/var/www/html
    environment:
      # This simple loop will be managed and kept alive by Supervisor
      - PYTHON_WORKER_COMMAND=while true; do python /var/www/html/my_task.py; sleep 300; done
```

> **Note:** Because the venv's `python` and `pip` are on the `PATH`, you can reference them directly in your worker commands without specifying the full `/opt/venv/bin/python` path.

### Automatic Container Restart on Fatal Failures

All services run under Supervisor; a process reaching `FATAL` exits the whole container so a dead worker never hides inside a healthy-looking container.

See [Supervisor and Fatal Failures](./common.md#supervisor-and-fatal-failures) in the shared documentation for the full explanation.

## Build Mode at a Glance

Invoking the entrypoint in a Dockerfile `RUN` without a command sets `CONTAINER_MODE=build`: full environment setup, services skipped — later `RUN` steps see exactly the production variables.

See [Build Mode](./common.md#build-mode) in the shared documentation for the full explanation.

## Utility Commands

The following helper commands are available inside every container at runtime.

### `reload-supervisor`

`reload-supervisor` applies changed configs without a container restart.

See [Utility Commands](./common.md#utility-commands) in the shared documentation.

## Advanced Customization: Templating and Overrides

This image uses a powerful templating engine that processes **all internal configuration files** on startup. This allows for deep customization of NGINX, Supervisor, Gunicorn, and other components without rebuilding the image.

### The `/container/custom` Directory

**All customization happens through a single mount point: `/container/custom`** — snippets, certificates, env files, hooks and image-specific runtime config together. Read-only mounts (e.g. Kubernetes config maps) are fully supported.

See [The /container/custom Directory](./common.md#the-custom-directory) for the structure and the config map example, and [Running on a Read-Only Filesystem](./common.md#running-on-a-read-only-filesystem) for read-only deployments.

### How Templating Works

Every config file — built-in and custom — is rendered with `${VAR}` substitution from the exported environment. `[[DEBUG_VARS]]` prints all substitutable variables.

See [Templating](./common.md#templating) in the shared documentation for the full explanation.

### Filename Markers: Declarative Conditional Logic

`.prod.`, `.dev.`, `.env-*`, `.mode-*` and `.https` filename suffixes decide declaratively when a file loads; `-or-` builds OR clauses.

See [Filename Markers](./common.md#filename-markers) in the shared documentation for the full explanation.

### Customization Methods

There are multiple ways to customize the container's behavior and configuration. Here are the primary methods:

#### 1. Adding Custom NGINX Snippets `MARKER-AWARE` `TEMPLATES`

This is the standard, additive approach for extending NGINX. It's perfect for adding headers, redirects, or custom `location` blocks.

* **How it works:** Place your custom `.conf` files in `./docker/custom/nginx/` and mount it to `/container/custom`.
* **Result:** These files are treated as snippets. After variable substitution, they are copied to `/etc/nginx/snippets/custom.d/` and included by the main server block.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/python-nginx:latest
    volumes:
      # Mount custom directory containing nginx/ subdirectory
      - ./docker/custom:/container/custom
```

**Directory structure:**

```
docker/custom/
└── nginx/
    ├── 01-custom-headers.conf
    ├── 02-api-proxy.prod.conf
    └── 03-websockets.https.conf
```

Your custom snippets can add headers, redirects, or even new `location` blocks and can look like this:

```nginx
# docker/custom/nginx/01-custom-headers.conf
location ^~ ${DOCKER_SERVICE_ABS_PATH}custom/ {
    root ${NGINX_DOC_ROOT};
    index index.html index.htm;
}
```

##### 1.1 Global NGINX Snippets (http) `MARKER-AWARE` `TEMPLATES`

These snippets are included in the main `http` block and are perfect for adding global rules, headers, or `map` blocks.

* **How:** Inside your custom directory, create a `nginx/global/` sub-directory.
* **Result:** The files are processed and included globally in the `http` block.

**Directory structure:**

```
docker/custom/
└── nginx/
    └── global/
        ├── 01-rate-limiting.conf
        └── 02-gzip-settings.prod.conf
```

##### 1.2 Root Location Snippets `MARKER-AWARE` `TEMPLATES`

These snippets are included in the `location /` block, allowing you to add authentication, custom headers, or internal rewrites specific to the root path.

**Note:** You cannot override the `try_files` directive from here. Use the `NGINX_TRY_FILES` environment variable instead.

**Directory structure:**

```
docker/custom/
└── nginx/
    └── location/
        ├── 01-auth-basic-off.prod.conf
        └── 02-custom-rewrites.conf
```

**Example:**

```nginx
# docker/custom/nginx/location/01-auth-basic-off.prod.conf
# Make this location public again when NGINX_BASIC_AUTH is enabled
auth_basic off;
```

> For simple "protect everything with a username and password" cases, prefer the `NGINX_BASIC_AUTH` environment variable over hand-written snippets — it creates and maintains the password file for you.

#### Shared Customization Methods

The remaining customization methods are shared between all images and are documented once in the shared documentation:

- [SSL Certificates](./common.md#ssl-certificates) — mount `cert.pem` + `key.pem` in `certs/`
- [Custom Error Pages](./common.md#custom-error-pages) — `errorPage.html` / `errorPage.json` in `nginx/`
- [Environment Files](./common.md#environment-files) — `*.env` / `*.env.sh` in `env/`, loaded before any service configuration
- [Entrypoint Hooks](./common.md#entrypoint-hooks) — `.sh` scripts in `entrypoint/`, run just before the services launch
- [Overriding Core Templates](./common.md#overriding-core-templates-advanced) — replace a default template wholesale (advanced)

### Complete Example

Here's a complete example showing all customization types:

```
project/
├── docker-compose.yml
├── docker/
│   └── custom/
│       ├── env/
│       │   └── 10-routing.env
│       ├── nginx/
│       │   ├── global/
│       │   │   └── 01-cors.conf
│       │   ├── 01-api-routes.conf
│       │   ├── errorPage.html
│       │   └── errorPage.json
│       ├── certs/
│       │   ├── cert.pem
│       │   └── key.pem
│       └── entrypoint/
│           └── 01-migrations.mode-build.sh
└── src/
    └── ... (your application code)
```

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/python-nginx:latest
    volumes:
      - ./src:/var/www/html
      - ./docker/custom:/container/custom  # Single mount for all customizations
    environment:
      - ENVIRONMENT=production
      - DOCKER_PROJECT_PROTOCOL=https
      - DOCKER_SERVICE_PROTOCOL=http
```

### Migration from Legacy Mount Points

Legacy mount points (`/etc/ssl/certs`, `/etc/container/templates/...`) abort the startup with migration instructions.

See [Migration from Legacy Mount Points](./common.md#migration-from-legacy-mount-points) in the shared documentation for the full explanation.

## Default Application (`server.py`)

To get you started quickly, the image includes a simple Flask application at `/var/www/html/server.py`. This file provides a WSGI callable named `app` that Gunicorn serves by default. It displays a welcome message and, if `APP_ENV` is not `prod`, a list of environment variables.

The default `requirements.txt` includes **gunicorn** and **flask**. You can replace both files with your own application code by mounting your project into `/var/www/html`.

NGINX is configured to serve static files from `/var/www/html/static/` first (via the `try_files` directive), and if a file is not found, it proxies the request to Gunicorn. If your WSGI application module is not `server:app`, set the `PYTHON_APP_MODULE` environment variable to point to the correct `module:callable` (e.g., `myapp.wsgi:application`).

### Installing Custom Dependencies

When building your own image on top of this one, add your `requirements.txt` and install it into the virtual environment:

```dockerfile
FROM neunerlei/python-nginx:latest

COPY --chown=www-data:www-data ./requirements.txt /var/www/html/requirements.txt
RUN pip install --no-cache-dir -r /var/www/html/requirements.txt

COPY --chown=www-data:www-data ./src /var/www/html
```

`pip` always runs as `www-data` (the venv belongs to it), so the install needs no `gosu`.

The venv's `pip` and `python` are already on the `PATH`, so you can use them directly. A convenience symlink at `/var/www/venv` points to the venv at `/opt/venv`.

## The Shell Environment and the Bash Wrapper

`/bin/bash` (and `/bin/sh`) source `/container/work/container-vars.sh` first, so entrypoint-exported variables are available in `docker exec` sessions. These container values take precedence over variables passed inline or via `docker exec -e`.

`python` and `pip` are env-wrapped the same way (`_python`/`_pip` for the originals), so the container values take precedence over inline overrides like `FLASK_ENV=testing python …` here too. `pip` additionally always runs as `www-data`, since the virtual environment belongs to that user.

See [The Shell Environment and the Bash Wrapper](./common.md#the-shell-environment-and-the-bash-wrapper) in the shared documentation for the full explanation.

## Build-Time Execution with Multi-Stage Builds

Beyond running as a web or worker service, this image includes a powerful **"Build Mode"** designed to be used inside your `Dockerfile` during a `docker build` process.

This feature allows you to leverage the container's fully configured environment—including all its environment variables, helper scripts, and logic—to perform build tasks like compiling assets, running database migrations, or running unit tests.

### How It Works

The entrypoint runs in build mode when invoked without a command; the resulting variables are exported for the following `RUN` steps.

See [Build Mode](./common.md#build-mode) in the shared documentation for the full explanation.

### Use Case: Creating an Optimized Production Image

This is the most common use case. In a multi-stage Docker build, you can use one stage to build your application and a final, clean stage to run it.

Here is a typical `Dockerfile` for a Python application:

```dockerfile
# Start from your application's base image
FROM neunerlei/python-nginx:latest AS builder

# Pass in build-time arguments (e.g., from your CI/CD system)
ARG DOCKER_PROJECT_PROTOCOL
ARG DOCKER_PROJECT_HOST

# Set them as environment variables so the entrypoint can read them
ENV DOCKER_PROJECT_PROTOCOL=${DOCKER_PROJECT_PROTOCOL}
ENV DOCKER_PROJECT_HOST=${DOCKER_PROJECT_HOST}

# Copy your application source code
COPY --chown=www-data:www-data ./requirements.txt ./requirements.txt
COPY --chown=www-data:www-data ./src ./src

# === Build-Time Execution ===
# 1. Run the entrypoint to set up the environment.
RUN /container/entrypoint/entrypoint.sh

# 2. Install dependencies and run build commands.
#    They now have access to all container variables.
RUN pip install --no-cache-dir -r requirements.txt
RUN python -m pytest tests/

# --- Final Production Stage ---
FROM neunerlei/python-nginx:latest

WORKDIR /var/www/html

# Copy only the necessary artifacts from the builder stage.
COPY --from=builder /var/www/html ./
COPY --from=builder /opt/venv /opt/venv

# The final image now contains your app with all dependencies installed
# but not test fixtures or build-time-only packages,
# making it smaller and more secure.
# The standard CMD and ENTRYPOINT will take over from here.
```

By using this pattern, you ensure that the environment variables and paths used during your build process are identical to those that will be used in production, eliminating a common source of bugs. You can also use filename markers like `my-script.mode-build.sh` in your custom entrypoint hooks to run scripts exclusively during the build phase.
