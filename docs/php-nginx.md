# PHP Images - with nginx (>= 8.2)

Welcome to the new generation of `neunerlei/php-nginx` images!

Starting with PHP 8.2, these images are designed as self-contained, high-performance services. The philosophy has shifted from providing only PHP-FPM to providing a complete, production-ready PHP application runtime that includes a pre-configured NGINX web server.

Think of this image as a "service-in-a-box". You put your code in, configure it with environment variables, and it just works—whether in local development or behind a production reverse proxy.

> **Shared behavior:** concepts that apply to all images — the entrypoint, container modes, customization, templating, read-only/Kubernetes operation and more — are documented once in [Shared Concepts](./common.md). This document keeps everything specific to this image.

For older PHP versions (<= 8.1) without NGINX, please refer to the [legacy PHP documentation](php.md).

## Tags

Here you can find [all available tags](https://docker.neunerlei.eu/neunerlei-php-nginx-tags.html) of this image.

## Quick Start

The quickest way to get started is with a `docker-compose.yml` file. This example runs your application in "web" mode, mounts your code, and exposes it on port 8080.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/php-nginx:latest # Or your desired version
    ports:
      - "8080:80"
    volumes:
      - ./your-php-project:/var/www/html
    environment:
      # Optional: Set a higher memory limit
      - PHP_MEMORY_LIMIT=2G
      # Optional: Set a larger upload size
      - MAX_UPLOAD_SIZE=250M
```

Place your PHP project (with a `public/index.php`) in the `./your-php-project` directory and run `docker-compose up`. You can now access your application at `http://localhost:8080`.

## Installed extensions

The image comes with a wide range of commonly used PHP extensions pre-installed and ready to use.
Additional, to those already in the [official PHP images](https://hub.docker.com/_/php#default-extensions), the following extensions are included:

`apcu`, `bcmath`, `bz2`, `ctype`, `curl`, `exif`, `gd`, `iconv`, `intl`, `mbstring`, `mysqli`, `opcache`, `opcache`, `pcntl`, `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `pgsql`, `redis`, `xmlrpc`, `zip`

> DEPRECATION NOTE: **xmlrpc** is included for legacy reasons, but considered DEPRECATED in this image. I will remove it in the next release that has a breaking change.
> After that you can still use it by installing it manually in your image with: `RUN docker-php-ext-install xmlrpc`.

## Composer

Composer is pre-installed globally in the image, so you can run `composer` commands directly in your container without needing to install it yourself.

> Composer is configured to ALWAYS run as `www-data` user, so you do not need to worry about permissions when running composer commands.
> If you want to use composer as a different user, execute `_composer` instead, which is the original composer binary without the user switch.

Unrelated to the user switch above: `php` is **env-wrapped** (it still runs as the invoking user). The `php` command sources the container variables first, so CLI scripts see the same environment as the entrypoint — execute `_php` for the original binary. The container values take precedence over inline overrides like `APP_ENV=testing php …`; see [The Shell Environment and the Bash Wrapper](./common.md#the-shell-environment-and-the-bash-wrapper).

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, this script reads your environment variables to decide how to configure itself. It operates in one of two primary modes:

1. **Web Mode (Default):** This is the standard mode. The script starts and configures both NGINX and PHP-FPM to serve your application over HTTP.
2. **Worker Mode:** Activated by setting the `PHP_WORKER_COMMAND` variable. In this mode, NGINX and PHP-FPM are disabled, and Supervisor is configured to run your specified command instead. This is perfect for running queue workers, schedulers, or other long-running background tasks.

## Configuration via Environment Variables

This image is configured almost entirely through environment variables. This allows you to use the same image for different purposes (web vs. worker, dev vs. prod) without rebuilding it.

| Variable                               | Description                                                                                                                                                                           | Default Value                        |
|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------|
| **General**                            |                                                                                                                                                                                       |                                      |
| `PUID`                                 | The user ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                                                                                                   | `33`                                 |
| `PGID`                                 | The group ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                                                                                                  | `33`                                 |
| `CONTAINER_MODE`                       | Read-only. Automatically set to `web`, `worker`, or `build`.                                                                                                                          | `web`                                |
| `MAX_UPLOAD_SIZE`                      | A convenient variable to set NGINX, `upload_max_filesize`, and `post_max_size` all at once.                                                                                           | `100M`                               |
| `USER_OWNED_DIRECTORIES`               | Additional directories (space separated) that should be owned by the `www-data` user, e.g. for mounted volumes the application writes into. They are created when missing.           | (none)                               |
| `MAX_UPLOAD_SIZE_BYTES`                | Read-only. The byte value of `MAX_UPLOAD_SIZE`, calculated by the entrypoint script.                                                                                                  | (calculated)                         |
| `ENVIRONMENT`                          | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production.                                                                      | `production`                         |
| `APP_ENV`                              | The semi-standard PHP framework environment variable. Defaults to the value of `ENVIRONMENT`.                                                                                         | (derived)                            |
| `APP_DEBUG`                            | Defaults to `1` if `ENVIRONMENT` is `development`, or `PHP_PROD_DEBUG` is set to true, otherwise `0`                                                                                  | (derived)                            |
| **Project**                            |                                                                                                                                                                                       |                                      |
| `DOCKER_PROJECT_HOST`                  | The public hostname for your application (available for your app).                                                                                                                    | `localhost`                          |
| `DOCKER_PROJECT_PATH`                  | The public root path of the entire project.                                                                                                                                           | `/`                                  |
| `DOCKER_PROJECT_PROTOCOL`              | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                                                                                            | `http`                               |
| `DOCKER_SERVICE_PROTOCOL`              | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                                                                                     | (derived)                            |
| `DOCKER_SERVICE_PATH`                  | The sub-path for this specific service within the project.                                                                                                                            | `/`                                  |
| `DOCKER_SERVICE_ABS_PATH`              | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                                                                                      | (derived)                            |
| **NGINX**                              |                                                                                                                                                                                       |                                      |
| `NGINX_DOC_ROOT`                       | The document root NGINX should use.                                                                                                                                                   | `/var/www/html/public`               |
| `NGINX_CLIENT_MAX_BODY_SIZE`           | Overrides `client_max_body_size` in NGINX. **Please prefer `MAX_UPLOAD_SIZE`**                                                                                                        | Matches `MAX_UPLOAD_SIZE`            |
| `NGINX_CERT_PATH`                      | Path to the SSL certificate file (used if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                         | `/etc/ssl/certs/custom/cert.pem`     |
| `NGINX_KEY_PATH`                       | Path to the SSL key file (used if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                 | `/etc/ssl/certs/custom/key.pem`      |
| `NGINX_PROXY_CONNECT_TIMEOUT`          | Sets `fastcgi_connect_timeout` in NGINX. This defines how long NGINX will wait when trying to connect to PHP-FPM.                                                                     | `5s`                                 |
| `NGINX_PROXY_READ_TIMEOUT`             | Sets `fastcgi_send_timeout` in NGINX. This value defines the timeout for reading a response from a proxied server.                                                                    | `60s`                                |
| `NGINX_PROXY_SEND_TIMEOUT`             | Sets `fastcgi_read_timeout` in NGINX. This value defines the timeout for transmitting a request to a proxied server.                                                                  | `60s`                                |
| `NGINX_KEEPALIVE_TIMEOUT`              | Sets `keepalive_timeout` in NGINX. This value defines the timeout for keeping connections alive with clients. If omitted, automatically calculated based on the other TIMEOUT values. | (calculated)                         |
| `NGINX_RESOLVER`                       | Sets the `resolver` directive in NGINX (DNS servers for dynamic upstream names — a variable in `proxy_pass`). Auto-detected from `/etc/resolv.conf`, see [NGINX DNS Resolution](./common.md#nginx-dns-resolution).                              | Auto-detected, fallback `127.0.0.11` |
| `NGINX_RESOLVER_VALID_TIMEOUT`         | Sets the `valid=` parameter of the `resolver` directive: how long NGINX caches resolved DNS answers.                                                                                                                                            | `30s`                                |
| `NGINX_RESOLVER_TIMEOUT`               | Sets `resolver_timeout` in NGINX: how long NGINX waits for an answer from a DNS server.                                                                                                                                                         | `5s`                                 |
| `NGINX_TRY_FILES`                      | Sets the `try_files` directive in the root location of the nginx server.                                                                                                              | `$uri $uri/ /index.php$is_args$args` |
| `NGINX_BASIC_AUTH`                      | Enables basic auth for the **whole server**. Format: `username clear-password`; additional users via `NGINX_BASIC_AUTH_1..n` (e.g. `NGINX_BASIC_AUTH_2="user2 pass2"`), login dialog realm via `NGINX_BASIC_AUTH_REALM` (default `Restricted`). | (disabled)              |
| **PHP**                                |                                                                                                                                                                                       |                                      |
| `PHP_UPLOAD_MAX_FILESIZE`              | Overrides PHP's `upload_max_filesize` directly. **Please prefer `MAX_UPLOAD_SIZE`**                                                                                                   | Matches `MAX_UPLOAD_SIZE`            |
| `PHP_POST_MAX_SIZE`                    | Overrides PHP's `post_max_size` directly. **Please prefer `MAX_UPLOAD_SIZE`**                                                                                                         | Matches `MAX_UPLOAD_SIZE`            |
| `PHP_MEMORY_LIMIT`                     | Overrides PHP's `memory_limit`.                                                                                                                                                       | `1024M`                              |
| `PHP_TIMEZONE`                         | Sets the default timezone for `date()` functions.                                                                                                                                     | `UTC`                                |
| `PHP_PROD_DISPLAY_ERRORS`              | Overrides `display_errors` in production mode.                                                                                                                                        | `Off`                                |
| `PHP_PROD_DISPLAY_STARTUP_ERRORS`      | Overrides `display_startup_errors` in production mode.                                                                                                                                | `Off`                                |
| `PHP_PROD_ERROR_REPORTING`             | Overrides `error_reporting` in production mode.                                                                                                                                       | `E_ALL & ~E_DEPRECATED & ~E_STRICT`  |
| `PHP_PROD_OPCACHE_VALIDATE_TIMESTAMPS` | Overrides `opcache.validate_timestamps` in production mode.                                                                                                                           | `0`                                  |
| `PHP_PROD_DEBUG`                       | When set to `true`, allows you to override the `PHP_PROD_*` variables with more lax settings suitable for debugging in a "production" environment.                                    | `false`                              |
| **PHP Worker Mode**                    |                                                                                                                                                                                       |                                      |
| `PHP_WORKER_COMMAND`                   | The command to execute in worker mode. **Setting this enables worker mode.**                                                                                                          | (unset)                              |
| `PHP_WORKER_PROCESS_COUNT`             | The number of worker processes to run (`numprocs` in Supervisor).                                                                                                                     | `1`                                  |
| `PHP_WORKER_STOP_WAIT_SECS`            | The number of seconds Supervisor waits for the worker process to stop gracefully before sending SIGKILL (`stopwaitsecs` in Supervisor).                                               | `10`                                 |
| **PHP-FPM**                            |                                                                                                                                                                                       |                                      |
| `PHP_FPM_MAX_CHILDREN`                 | `pm.max_children`                                                                                                                                                                     | `20`                                 |
| `PHP_FPM_START_SERVERS`                | `pm.start_servers`                                                                                                                                                                    | `2`                                  |
| `PHP_FPM_MIN_SPARE_SERVERS`            | `pm.min_spare_servers`                                                                                                                                                                | `1`                                  |
| `PHP_FPM_MAX_SPARE_SERVERS`            | `pm.max_spare_servers`                                                                                                                                                                | `4`                                  |
| `PHP_FPM_MAX_REQUESTS`                 | `pm.max_requests`                                                                                                                                                                     | `500`                                |

### ENVIRONMENT, `APP_ENV` and `APP_DEBUG` Derivation

The `ENVIRONMENT` variable is a high-level switch for the container's operational mode. It is shared across all images in this ecosystem and influences NGINX configurations, logging verbosity, and other entrypoint behaviors.

- **Possible Values:** `production` (or `prod`) and `development` (or `dev`).
- **Default:** `production`.
- **Rule:** Any value other than `development` or `dev` is treated as a production environment.

**`APP_ENV` Derivation Logic:**

To align with standard frameworks (Symfony, Laravel, CakePHP...), the `APP_ENV` variable is automatically derived from `ENVIRONMENT`. You generally do not need to set it yourself.

- If `ENVIRONMENT` is set to `development` or `dev`, `APP_ENV` defaults to `dev`.
- Otherwise, `APP_ENV` defaults to `prod`.
- If you set `APP_ENV` explicitly, **your value will always take precedence**. This allows you to run in a `production` container `ENVIRONMENT` (with optimized NGINX settings) while having `APP_ENV` set to `staging`, for example.

**`APP_DEBUG` Derivation Logic:**

Similarly, `APP_DEBUG` is derived from `ENVIRONMENT` and `PHP_PROD_DEBUG`.

- If `ENVIRONMENT` is `development` or `dev`, `APP_DEBUG` defaults to `1` (true).
- If `ENVIRONMENT` is `production` or `prod` and `PHP_PROD_DEBUG` is set to `true`, `APP_DEBUG` defaults to `1` (true).
- If `APP_ENV` is manually set to `development` or `dev`, `APP_DEBUG` defaults to `1` (true).
- If none of the above conditions are met, `APP_DEBUG` defaults to `0` (false).
- If you set `APP_DEBUG` explicitly, **your value will always take precedence**.

### A word on `PHP_PROD_DEBUG`

The `PHP_PROD_DEBUG` variable is a special override for production environments. By default, the [x.php.prod.ini](../src/php-nginx/8.2/container/templates/php/x.php.prod.ini) configuration is optimized for security and performance, which means error display is turned off and opcache is locked down. While good for security and performance, this can make debugging difficult.
For this reason, if you set `PHP_PROD_DEBUG=true`, the entrypoint script will relax several of these settings to make debugging easier, while still keeping the overall production optimizations in place. This is especially useful when you need to troubleshoot issues in a production-like environment without fully switching to a development setup.

When you enable it, it modifies the php.ini:

- `display_errors=On` -> Allows errors to be displayed.
- `display_startup_errors=On` -> Allows startup errors to be displayed.
- `error_reporting=E_ALL & ~E_DEPRECATED` -> Reports all errors except deprecated warnings.
- `opcache.validate_timestamps=1` -> Enables opcache to check for updated scripts (meaning you don't have to restart the server for code changes to take effect).

The changes will be reflected in the corresponding `PHP_PROD_*` environment variables.

### Path Composition: `PROJECT_PATH` + `SERVICE_PATH`

Public URLs compose from `DOCKER_PROJECT_PATH` + `DOCKER_SERVICE_PATH` into the read-only `DOCKER_SERVICE_ABS_PATH`.

See [Path Composition](./common.md#path-composition) in the shared documentation.

### MAX_UPLOAD_SIZE and friends

`MAX_UPLOAD_SIZE` (default `100M`) sets all upload limits at once; `MAX_UPLOAD_SIZE_BYTES` is the parsed read-only byte value. Prefer it over the individual overrides.

See [MAX_UPLOAD_SIZE and Friends](./common.md#max_upload_size-and-friends) in the shared documentation for the full explanation.

### PHP_WORKER_STOP_WAIT_SECS and Docker Stop Timeout

Graceful shutdown: `*_WORKER_STOP_WAIT_SECS` defines how long the worker may finish after SIGTERM — raise Docker's `stop_grace_period` above it, or the timeout never takes effect.

See [Worker Mode](./common.md#worker-mode) in the shared documentation.

## Web Mode In-Depth

In `web` mode, the entrypoint script configures NGINX to serve your application.

### HTTP vs. HTTPS

Direct HTTPS (`DOCKER_PROJECT_PROTOCOL=https` with mounted certificates) or, recommended, TLS terminated at an outer gateway (`DOCKER_SERVICE_PROTOCOL=http`).

See [HTTP vs. HTTPS](./common.md#http-vs-https) in the shared documentation for the full explanation.

### Customizing NGINX with Intelligent Snippets

This image uses a flexible system for extending the base NGINX configuration. You can add any number of custom configuration files, and the container's entrypoint script will intelligently process and include them based on their name and your environment variables.

You can learn more about this powerful feature in [Advanced Customization](#advanced-customization-templating-and-overrides), especially in the [Adding Custom NGINX Snippets](#1-adding-custom-nginx-snippets-marker-aware-templates) section.

## Worker Mode In-Depth

If you provide the `PHP_WORKER_COMMAND` environment variable, the image switches to worker mode. This is the idiomatic way to run background tasks using the exact same PHP environment as your web application.

**Example 1: Running a Laravel Queue Worker**

```yaml
services:
  my-app-worker:
    image: neunerlei/php-nginx:8.5
    volumes:
      - ./your-laravel-project:/var/www/html
    environment:
      # This enables worker mode and defines the command
      - PHP_WORKER_COMMAND=php /var/www/html/artisan queue:work --tries=3
      # Optional: run 4 worker processes
      - PHP_WORKER_PROCESS_COUNT=4
```

**Example 2: Running a "cron" task**

For simple scheduled tasks without a full cron daemon, you can use a loop managed by Supervisor.

```yaml
services:
  my-app-scheduler:
    image: neunerlei/php-nginx:8.5
    volumes:
      - ./your-project:/var/www/html
    environment:
      # This simple loop will be managed and kept alive by Supervisor
      - PHP_WORKER_COMMAND=while true; do php /var/www/html/my_task.php; sleep 300; done
```

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

This image uses a powerful templating engine that processes **all internal configuration files** on startup. This allows for deep customization of NGINX, Supervisor, PHP, and other components without rebuilding the image.

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
    image: neunerlei/php-nginx:latest
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

These snippets are included in the `location /` block, allowing you to add
authentication, custom headers, or internal rewrites specific to the root path.

**Note:** You cannot override the `try_files` directive from here. Use the
`NGINX_TRY_FILES` environment variable instead.

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

#### 2. Adding Custom php.ini and php-fpm.conf Snippets `MARKER-AWARE` `TEMPLATES`

You can extend the PHP configuration by adding custom snippets for `php.ini` and `php-fpm.conf`.

* **How:** Place files ending with `.ini` in `./docker/custom/php/` for `php.ini` snippets, or `.conf` files in `./docker/custom/php/fpm/` for `php-fpm.conf` snippets.

**Directory structure:**

```
docker/custom/
└── php/
    ├── z-custom-settings.ini
    ├── z-opcache-tuning.prod.ini
    └── fpm/
        └── z-custom-pool.conf
```

> **Naming Convention:** The default FPM pool configuration is loaded as `www.conf`. The default php.ini configurations are loaded as `x.php.ini` and `x.php.prod.ini` (production only). Prefix your custom files with `z-` to ensure they load last and can override defaults.

**Example `z-custom-settings.ini`:**

```ini
; Custom PHP settings
max_execution_time = ${PHP_MAX_EXECUTION_TIME}
default_socket_timeout = 300
```

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
│       ├── php/
│       │   ├── z-custom.ini
│       │   └── fpm/
│       │       └── z-pool-custom.conf
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
    image: neunerlei/php-nginx:latest
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

## Default Script (index.php)

To get you started quickly, the image includes a simple default `index.php` file located at `/var/www/html/public/index.php`. This file displays a welcome message and some basic PHP configuration information. In development mode (`ENVIRONMENT=development`), it also shows full `phpinfo()` output. You can replace this file with your own application code by mounting your project into `/var/www/html`.

## The Shell Environment and the Bash Wrapper

`/bin/bash` (and `/bin/sh`) source `/container/work/container-vars.sh` first, so entrypoint-exported variables are available in `docker exec` sessions. These container values take precedence over variables passed inline or via `docker exec -e`.

See [The Shell Environment and the Bash Wrapper](./common.md#the-shell-environment-and-the-bash-wrapper) in the shared documentation for the full explanation.

## Build-Time Execution with Multi-Stage Builds

Beyond running as a web or worker service, this image includes a powerful **"Build Mode"** designed to be used inside your `Dockerfile` during a `docker build` process.

This feature allows you to leverage the container's fully configured environment—including all its environment variables, helper scripts, and logic—to perform build tasks like compiling frontend assets, running database migrations, or running unit tests.

### How It Works

The entrypoint runs in build mode when invoked without a command; the resulting variables are exported for the following `RUN` steps.

See [Build Mode](./common.md#build-mode) in the shared documentation for the full explanation.

### Use Case: Creating an Optimized Production Image

This is the most common use case. In a multi-stage Docker build, you can use one stage to build your application and a final, clean stage to run it.

Here is a typical `Dockerfile` for running unit tests during the build process:

```dockerfile
# Start from your application's base image
FROM neunerlei/php-nginx:latest AS test

# Pass in build-time arguments (e.g., from your CI/CD system)
ARG DOCKER_PROJECT_PROTOCOL
ARG DOCKER_PROJECT_HOST

# Set them as environment variables so the entrypoint can read them
ENV DOCKER_PROJECT_PROTOCOL=${DOCKER_PROJECT_PROTOCOL}
ENV DOCKER_PROJECT_HOST=${DOCKER_PROJECT_HOST}

# Copy your application source code
COPY --chown=www-data:www-data ./composer*.json ./
COPY --chown=www-data:www-data ./src ./src

# === Build-Time Execution ===
# 1. Run the entrypoint to set up the environment.
RUN /container/entrypoint/entrypoint.sh

# 2. Run your build commands. They now have access to all container variables.
RUN composer install --no-dev --optimize-autoloader
RUN ./vendor/bin/phpunit
```

Then, to execute your unit-tests start the build with:

```bash
docker build --build-arg DOCKER_PROJECT_PROTOCOL=https --build-arg DOCKER_PROJECT_HOST=my-app.com -t my-app-test .
```

By using this pattern, you ensure that the environment variables and paths used during your build process are identical to those that will be used in production, eliminating a common source of bugs. You can also use filename markers like `my-script.mode-build.sh` in your custom entrypoint hooks to run scripts exclusively during the build phase.
