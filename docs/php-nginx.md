# PHP Images - with nginx (>= 8.2)

Welcome to the new generation of `neunerlei/php-nginx` images!

Starting with PHP 8.2, these images are designed as self-contained, high-performance services. The philosophy has shifted from providing only PHP-FPM to providing a complete, production-ready PHP application runtime that includes a pre-configured NGINX web server.

Think of this image as a "service-in-a-box". You put your code in, configure it with environment variables, and it just works—whether in local development or behind a production reverse proxy.

For older PHP versions (<= 8.4) without NGINX, please refer to the [legacy PHP documentation](php.md).

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

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, this script reads your environment variables to decide how to configure itself. It operates in one of two primary modes:

1. **Web Mode (Default):** This is the standard mode. The script starts and configures both NGINX and PHP-FPM to serve your application over HTTP.
2. **Worker Mode:** Activated by setting the `PHP_WORKER_COMMAND` variable. In this mode, NGINX and PHP-FPM are disabled, and Supervisor is configured to run your specified command instead. This is perfect for running queue workers, schedulers, or other long-running background tasks.

## Configuration via Environment Variables

This image is configured almost entirely through environment variables. This allows you to use the same image for different purposes (web vs. worker, dev vs. prod) without rebuilding it.

| Variable                               | Description                                                                                                      | Default Value                                                                                                                                      |
|----------------------------------------|------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| **General**                            |                                                                                                                  |                                                                                                                                                    |
| `PUID`                                 | The user ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                              | `33`                                                                                                                                               |
| `PGID`                                 | The group ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                             | `33`                                                                                                                                               |
| `CONTAINER_MODE`                       | Read-only. Automatically set to `web` or `worker`.                                                               | `web`                                                                                                                                              |
| `MAX_UPLOAD_SIZE`                      | A convenient variable to set NGINX, `upload_max_filesize`, and `post_max_size` all at once.                      | `100M`                                                                                                                                             |
| `ENVIRONMENT`                          | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production. | `production`                                                                                                                                       |
| `APP_ENV`                              | The semi-standard PHP framework environment variable. Defaults to the value of `ENVIRONMENT`.                    | (derived)                                                                                                                                          |
| `APP_DEBUG`                            | Defaults to `1`, if `ENVIRONMENT` is `development`, or `PHP_PROD_DEBUG` is set to true, otherwise `0`            | (derived)                                                                                                                                          |                                                                                                                                                     |
| **Project**                            |                                                                                                                  |                                                                                                                                                    |
| `DOCKER_PROJECT_HOST`                  | The public hostname for your application (available for your app).                                               | `localhost`                                                                                                                                        |
| `DOCKER_PROJECT_PATH`                  | The public root path of the entire project.                                                                      | `/`                                                                                                                                                |
| `DOCKER_PROJECT_PROTOCOL`              | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                       | `http`                                                                                                                                             |
| `DOCKER_SERVICE_PROTOCOL`              | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                | (derived)                                                                                                                                          |
| `DOCKER_SERVICE_PATH`                  | The sub-path for this specific service within the project.                                                       | `/`                                                                                                                                                |
| `DOCKER_SERVICE_ABS_PATH`              | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                 | (derived)                                                                                                                                          |
| **NGINX**                              |                                                                                                                  |                                                                                                                                                    |
| `NGINX_DOC_ROOT`                       | The document root NGINX should use.                                                                              | `/var/www/html/public`                                                                                                                             |
| `NGINX_CLIENT_MAX_BODY_SIZE`           | Overrides `client_max_body_size` in NGINX.                                                                       | Matches `MAX_UPLOAD_SIZE`                                                                                                                          |
| `NGINX_CERT_PATH`                      | Path to the SSL certificate file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                                    | `/etc/ssl/certs/cert.pem`                                                                                                                          |
| `NGINX_KEY_PATH`                       | Path to the SSL key file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                                            | `/etc/ssl/certs/key.pem`                                                                                                                           |
| **PHP**                                |                                                                                                                  |                                                                                                                                                    |
| `PHP_UPLOAD_MAX_FILESIZE`              | Overrides PHP's `upload_max_filesize` directly.                                                                  | Matches `MAX_UPLOAD_SIZE`                                                                                                                          |
| `PHP_POST_MAX_SIZE`                    | Overrides PHP's `post_max_size` directly.                                                                        | Matches `MAX_UPLOAD_SIZE`                                                                                                                          |
| `PHP_MEMORY_LIMIT`                     | Overrides PHP's `memory_limit`.                                                                                  | `1024M`                                                                                                                                            |
| `PHP_TIMEZONE`                         | Sets the default timezone for `date()` functions.                                                                | `UTC`                                                                                                                                              |
| `PHP_PROD_DISPLAY_ERRORS`              | Overrides `display_errors` in `php.prod.ini`.                                                                    | `Off`                                                                                                                                              |
| `PHP_PROD_DISPLAY_STARTUP_ERRORS`      | Overrides `display_startup_errors` in `php.prod.ini`.                                                            | `Off`                                                                                                                                              |
| `PHP_PROD_ERROR_REPORTING`             | `E_ALL & ~E_DEPRECATED & ~E_STRICT`                                                                              | Overrides `error_reporting` in `php.prod.ini`.                                                                                                     |
| `PHP_PROD_OPCACHE_VALIDATE_TIMESTAMPS` | `0`                                                                                                              | Overrides `opcache.validate_timestamps` in `php.prod.ini`.                                                                                         |
| `PHP_PROD_DEBUG`                       | `false`                                                                                                          | When set to `true`, allows you to override the `PHP_PROD_*` variables with more lax settings suitable for debugging in a "production" environment. |
| **PHP Worker Mode**                    |                                                                                                                  |                                                                                                                                                    |
| `PHP_WORKER_COMMAND`                   | The command to execute in worker mode. **Setting this enables worker mode.**                                     | (unset)                                                                                                                                            |
| `PHP_WORKER_PROCESS_COUNT`             | The number of worker processes to run (`numprocs` in Supervisor).                                                | `1`                                                                                                                                                |
| **PHP-FPM**                            |                                                                                                                  |                                                                                                                                                    |
| `PHP_FPM_MAX_CHILDREN`                 | `pm.max_children`                                                                                                | `20`                                                                                                                                               |
| `PHP_FPM_START_SERVERS`                | `pm.start_servers`                                                                                               | `2`                                                                                                                                                |
| `PHP_FPM_MIN_SPARE_SERVERS`            | `pm.min_spare_servers`                                                                                           | `1`                                                                                                                                                |
| `PHP_FPM_MAX_SPARE_SERVERS`            | `pm.max_spare_servers`                                                                                           | `4`                                                                                                                                                |
| `PHP_FPM_MAX_REQUESTS`                 | `pm.max_requests`                                                                                                | `500`                                                                                                                                              |
| **Advanced/Internal**                  |                                                                                                                  |                                                                                                                                                    |
| `CONTAINER_TEMPLATE_DIR`               | The path to the container's internal template files.                                                             | `/etc/container/templates`                                                                                                                         |
| `CONTAINER_BIN_DIR`                    | The path to the container's internal binary and script files.                                                    | `/usr/bin/container`                                                                                                                               |

### ENVIRONMENT, `APP_ENV` and `APP_DEBUG` Derivation

The `ENVIRONMENT` variable is a high-level switch for the container's operational mode. It is shared across all images in this ecosystem and influences NGINX configurations, logging verbosity, and other entrypoint behaviors.

- **Possible Values:** `production` (or `prod`) and `development` (or `dev`).
- **Default:** `production`.
- **Rule:** Any value other than `development` or `dev` is treated as a production environment.

**`APP_ENV` Derivation Logic:**

To align with standard Framework (Symfony, Laravel, CakePhp...), the `APP_ENV` variable is automatically derived from `ENVIRONMENT`. You generally do not need to set it yourself.

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

The `PHP_PROD_DEBUG` variable is a special override for production environments. By default, the [x.php.prod.ini](../src/php-nginx/8.2/templates/php/x.php.prod.ini) configuration is optimized for security and performance, which means error display is turned off and opcache is locked down. While good for security and performance, this can make debugging difficult.
For this reason, if you set `PHP_PROD_DEBUG=true`, the entrypoint script will relax several of these settings to make debugging easier, while still keeping the overall production optimizations in place. This is especially useful when you need to troubleshoot issues in a production-like environment without fully switching to a development setup.

When you enable it, it modifies the php.ini:

- `display_errors=On` -> Allows errors to be displayed.
- `display_startup_errors=On` -> Allows startup errors to be displayed.
- `error_reporting=E_ALL & ~E_DEPRECATED` -> Reports all errors except deprecated warnings.
- `opcache.validate_timestamps=1` -> Enables opcache to check for updated scripts (meaning you don't have to restart the server for code changes to take effect).

The changes will be reflected in the corresponding `PHP_PROD_*` environment variables.

### Path Composition: `PROJECT_PATH` + `SERVICE_PATH`

When running multiple services behind a single reverse proxy, you need a way to manage URL paths. This image handles this by composing the final public URL path from two separate variables. A reverse proxy sits between your users and your services, directing traffic to the right place based on the URL path.

* `DOCKER_PROJECT_PATH`: The **base path** for the entire group of related services. If your whole application is served from `https://example.com/myapp/`, then this value would be `/myapp/`.
* `DOCKER_SERVICE_PATH`: The unique **sub-path** for a specific service within that project. For an API service, this might be `/api/`.
* `DOCKER_SERVICE_ABS_PATH`: This read-only variable is automatically created by combining the two: `DOCKER_PROJECT_PATH` + `DOCKER_SERVICE_PATH`. Your application can use this to reliably generate correct absolute URLs.

Your reverse proxy uses `DOCKER_SERVICE_PATH` for routing, while your application uses `DOCKER_SERVICE_ABS_PATH` for its internal logic.

---

#### Scenario 1: A Single App on a Domain Root

Your app runs at the root of a domain. This is the simplest case.

* **Public URL:** `https://my-app.com/`
* **Environment:**
    * `DOCKER_PROJECT_PATH: /`
    * `DOCKER_SERVICE_PATH: /` (or unset, as it defaults to `/`)
* **Resulting Path:**
    * `DOCKER_SERVICE_ABS_PATH` will be `/`.

---

#### Scenario 2: Frontend and Backend on the Same Domain

You have a frontend service at the root and a backend API service under `/api/`. A reverse proxy routes traffic.

* **Public URLs:**
    * Frontend: `https://my-app.com/`
    * Backend: `https://my-app.com/api/`

**Frontend Service Configuration:**

* `DOCKER_PROJECT_PATH: /`
* `DOCKER_SERVICE_PATH: /`
* **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/`.

**Backend Service Configuration:**

* `DOCKER_PROJECT_PATH: /`
* `DOCKER_SERVICE_PATH: /api/`
* **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/api/`. The backend can now correctly generate links like `/api/users/123`.

---

#### Scenario 3: An Entire Project Deployed on a Sub-Path

Your entire project, including a frontend and backend, must live under a specific path on a shared server.

* **Public URLs:**
    * Frontend: `https://shared.server.com/project-alpha/`
    * Backend: `https://shared.server.com/project-alpha/api/`

**Frontend Service Configuration:**

* `DOCKER_PROJECT_PATH: /project-alpha/`
* `DOCKER_SERVICE_PATH: /`
* **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/project-alpha/`.

**Backend Service Configuration:**

* `DOCKER_PROJECT_PATH: /project-alpha/`
* `DOCKER_SERVICE_PATH: /api/`
* **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/project-alpha/api/`.

## Web Mode In-Depth

In `web` mode, the entrypoint script configures NGINX to serve your application. By default, it operates over plain HTTP, but enabling SSL for HTTPS is controlled via a single environment variable. This process is known as **SSL Termination**, where NGINX handles the performance-intensive work of encrypting and decrypting traffic, freeing your application to communicate over plain HTTP internally.

**Controlling the Protocol:**

The `DOCKER_PROJECT_PROTOCOL` and `DOCKER_SERVICE_PROTOCOL` variables work together to manage this.

- `DOCKER_PROJECT_PROTOCOL`: Defines how the **end-user** connects to your service from the outside world. Set this to `"https"` if your service is exposed via HTTPS.
- `DOCKER_SERVICE_PROTOCOL`: Defines how the **reverse proxy talks to your application container**. If you are terminating SSL at an outer proxy, you should set this to `"http"`. It defaults to the value of `DOCKER_PROJECT_PROTOCOL`.

**Common Scenarios:**

1. **Direct HTTPS Exposure:**
    - **Goal:** This container handles SSL directly.
    - **Config:** `DOCKER_PROJECT_PROTOCOL="https"` (and leave `DOCKER_SERVICE_PROTOCOL` unset).
    - **Result:** NGINX listens on port 443 with SSL, using certificates from `NGINX_CERT_PATH` and `NGINX_KEY_PATH`, and redirects HTTP traffic to HTTPS. You must mount your certificates into the container.

2. **SSL Termination at an External Gateway (Recommended for Production):**
    - **Goal:** A different proxy (like Traefik, Caddy, or another `nginx` instance) handles SSL, and forwards plain HTTP traffic to this container.
    - **Config:** `DOCKER_PROJECT_PROTOCOL="httpss"` (so your app can generate correct public URLs) and `DOCKER_SERVICE_PROTOCOL="http"`.
    - **Result:** NGINX inside this container listens for plain HTTP on port 80. Your application remains simple and unaware of SSL, while still understanding that the public-facing connection is secure.

> **Production Note:** For automated certificate management (e.g., via Let's Encrypt), using a dedicated reverse proxy gateway like [linuxserver/swag](https://docs.linuxserver.io/images/docker-swag) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) in front of this container is a highly recommended pattern. This centralizes SSL management and simplifies your application containers.

### Example: A Secure Application with SSL Termination

You're running a single application that must be accessed securely over HTTPS. Your reverse proxy will handle the security.

* **Public URL:** `https://my-secure-app.com/`
* **Request Flow:**
    1. User's browser connects to `https://my-secure-app.com/`.
    2. The reverse proxy receives the HTTPS request on port 443 and terminates the TLS connection.
    3. The proxy forwards a plain HTTP request to the internal `app` service (e.g., `http://app`).

* **Configuration for the `app` service:**
  ```yaml
  environment:
    # --- Public-Facing Configuration ---
    DOCKER_PROJECT_HOST: 'my-secure-app.com'
    DOCKER_PROJECT_PROTOCOL: 'https' # The user connects via HTTPS

    # --- Service-Specific Configuration ---
    DOCKER_SERVICE_PROTOCOL: 'http'  # But the proxy talks to us via plain HTTP
  ```

* **Result:**
    * Your main proxy listens for `https` traffic.
    * Your `app` service only needs to run a standard `http` server on its internal port.
    * The automatically derived `DOCKER_SERVICE_ABS_PATH` is `/`, and your application code can still be made aware that the public connection is secure by checking the `X-Forwarded-Proto` header, which proxies typically add.

If you were to omit `DOCKER_SERVICE_PROTOCOL`, it would default to the value of `DOCKER_PROJECT_PROTOCOL` (`https` in this case), and your internal service would be expected to handle HTTPS traffic directly. By setting it explicitly to `http`, you enable the SSL Termination pattern.

### Customizing NGINX with Intelligent Snippets

This image uses a flexible system for extending the base NGINX configuration. You can add any number of custom configuration files, and the container's entrypoint script will intelligently process and include them based on their name and your environment variables.

You can learn more about this powerful feature in [Advanced Customization](#advanced-customization-templating-and-overrides), especially in the [Adding Custom NGINX Snippets](#1-adding-custom-nginx-snippets-marker-aware) section.

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

## Build Mode at a Glance

Automatically activated when no command is provided. This mode sets up the full container environment for multi-stage builds, dependency installation, testing, or compilation without starting any services.

Learn more about it in the [Build Mode Documentation](#build-time-execution-with-multi-stage-builds)

## Advanced Customization: Templating and Overrides

This image uses a powerful templating engine that processes **all internal configuration files** on startup. This allows for deep customization of NGINX, Supervisor, and other components.

### How Templating Works

Every configuration file inside `/etc/container/templates/` is treated as a template. The entrypoint script will read these files, substitute placeholders with their corresponding environment variable values, and write the final config to its destination.

You can use any of the environment variables listed above as placeholders in your custom files, using the syntax `${VAR_NAME}`.

> Whenever you see `TEMPLATES` in the headlines below, it means that you can use variables in the files.

#### The `[[DEBUG_VARS]]` Helper

To see exactly which variables are available for a template, you can add the special string `[[DEBUG_VARS]]` anywhere in a `.conf` file you are customizing. When the container starts, the template engine will detect this, print a list of all available variables and their current values to the console, and then exit. This is an invaluable tool for debugging your configurations.

Example output:

```
DEBUG_VARS detected in template: '/etc/container/templates/nginx/custom/my_debug.conf'. Current variables that can be substituted:
  - ${CONTAINER_MODE} = web
  - ${ENVIRONMENT} = production
  - ${NGINX_DOC_ROOT} = /var/www/html/public
  ...
```

### Filename Markers: Declarative Conditional Logic

To control *when* your custom snippets and scripts are loaded, you can embed special markers in their filenames. This creates a powerful and readable declarative system for managing configuration.

The system understands two operators: `.` (for AND) and `-or-` (for OR).

> Whenever you see `MARKER-AWARE` in the headlines below, it means that these rules apply.

**Logic Rules:**

1. A filename is broken into groups by the `.` delimiter. For a file to be loaded, **every** logical group must be satisfied.
2. Each group is broken into clauses by the `-or-` delimiter. For a group to be satisfied, **at least one** of its clauses must be true.

**Available Markers:**

| Marker Pattern | Example Filename          | Condition for Loading                                                                                                                                                                                                                                          |
|:---------------|:--------------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `env-*`        | `config.env-staging.conf` | The value of `$ENVIRONMENT` must match the part after `env-` (in this case, "staging"). This allows you to define custom environments beyond `prod` and `dev`. The aliases `env-prod` (for `production`) and `env-dev` (for `development`) are also supported. |
| `mode-*`       | `script.mode-worker.sh`   | The value of `$CONTAINER_MODE` must match the part after `mode-` (e.g., "worker", "web", or "build").                                                                                                                                                          |
| `prod`         | `config.prod.conf`        | A short form of `env-prod` when `ENVIRONMENT` is `production`.                                                                                                                                                                                                 |
| `dev`          | `config.dev.conf`         | A short form of `env-dev` when `ENVIRONMENT` is `development`.                                                                                                                                                                                                 |
| `https`        | `ssl-settings.https.conf` | The `$DOCKER_SERVICE_PROTOCOL` must be `https`.                                                                                                                                                                                                                |

**Examples:**

- **`01-headers.conf`**
    - **Logic:** No markers.
    - **Result:** Always loaded.

- **`10-security.prod.conf`** equivalent to `10-security.env-prod.conf`
    - **Logic:** `prod`
    - **Result:** Loaded only when `ENVIRONMENT` is `production`.

- **`20-hsts.prod.https.conf`**
    - **Logic:** `prod` AND `https`
    - **Result:** Loaded only in a `production` environment with `https` enabled.

- **`30-analytics.prod-or-env-staging.conf`** equivalent to `30-analytics.env-prod-or-env-staging.conf`
    - **Logic:** `env-prod` OR `env-staging`
    - **Result:** Loaded if `$ENVIRONMENT` is `production` or `staging`.

### Customization Methods

There are multiple ways to customize the container's behavior and configuration. Here are the primary methods:

#### 1. Adding Custom NGINX Snippets `MARKER-AWARE` `TEMPLATES`

This is the standard, additive approach for extending NGINX. It's perfect for adding headers, redirects, or custom `location` blocks.

* **How it works:** Place your custom `.conf` files in a local directory and mount it to `/etc/container/templates/nginx/custom/`.
* **Result:** These files are treated as snippets. After variable substitution, they are copied to `/etc/nginx/snippets/service.d/` and included by the main server block.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/php-nginx:latest
    volumes:
      # Mount your custom snippets into the 'custom' directory
      - ./my-nginx-snippets:/etc/container/templates/nginx/custom
```

Your custom snippets can add headers, redirects, or even new `location` blocks and can look like this:

```nginx
location ^~ ${DOCKER_SERVICE_ABS_PATH}custom/ {
    root ${NGINX_DOC_ROOT};
    index index.html index.htm;
}
```

##### 1.1 Server Snippets (server) `MARKER-AWARE` `TEMPLATES`

These snippets are included in the main `server` block and are perfect for adding global rules, headers, or `map` blocks.

* **How:** Mount a directory containing your `.conf` files to `/etc/container/templates/nginx/custom/`.
* **Result:** The files are processed and included globally.

##### 1.2 Global Snippets (http) `MARKER-AWARE` `TEMPLATES`

These snippets are included in the main `http` block and are perfect for adding global rules, headers, or `map` blocks.

* **How:** Inside your custom templates directory, create a `global` sub-directory.
* **Result:** The files are processed and included globally in the `http` block.

#### 2. Adding Custom php.ini and php-fpm.conf Snippets `MARKER-AWARE` `TEMPLATES`

You can also extend the PHP configuration by adding custom snippets for `php.ini` and `php-fpm.conf`.
Just copy or mount them to: `/etc/container/templates/php/custom/`. File ending with `.ini` will be treated as `php.ini` snippets, and `.conf` files as `php-fpm.conf` snippets.

> The default fpm-pool configuration is loaded as "www.conf"
> The default php.ini configuration is loaded as "x.php.common.ini" and "x.php.prod.ini" depending on the environment.
> So make sure your file names do not conflict with the defaults, and reflect the naming scheme (e.g. by prefixing with z- to load them last).

#### 3. Overriding Core Templates (Advanced) `TEMPLATES`

For maximum control, you can completely replace any of the container's default template files. This is an "all-or-nothing" approach best used for fundamentally changing a core component.

* **How:** Identify the default template (e.g., `/etc/container/templates/nginx/nginx.conf`). In your project, create your version and mount it to the *exact same path* inside the container.
* **Result:** Your mounted file will completely replace the image's default. The entrypoint will then process *your* template instead.

> **Note:** Filename markers do **not** apply when directly overriding a core template file.

##### 3.1. Custom error pages `TEMPLATES`

The `/etc/container/templates/nginx/service.errors.nginx.conf` file is responsible for handling error pages in the nginx configuration. By default, it supports custom error pages for HTTP status codes 400, 401, 403, 404, 500, 502, 503, and 504; both as HTML and JSON responses.

You can customize these error pages by overriding the default templates at: `/etc/container/templates/nginx/errorPage.html` or `/etc/container/templates/nginx/errorPage.json`.
Note, that these files are templates, so you can use any environment variables defined in the container within these files, additionally you have access to: `ERROR_CODE`, `ERROR_TITLE` and `ERROR_DESCRIPTION`, which will be replaced with the actual error code, title and description when the error page is rendered.

#### 4. Custom Entrypoint Hooks

Additionally to service snippets, the image supports custom entrypoint hooks that allow you to run your own scripts when the container starts. The scripts will be executed, just before the main command (`supervisord`) is started.

* **How it works:** Place your custom `.sh` files in a local directory and mount it to `/usr/bin/container/custom`.
* **Result:** These files are treated as executable scripts and run during the container's startup process.

> Custom entrypoint scripts use the same filename marker system described above, allowing you to conditionally execute scripts based on environment, mode, or protocol. All environment variables are automatically available in your scripts. Unlike templates, there's no `[[DEBUG_VARS]]` helper since scripts are executed directly, but you can use commands like `printenv | sort` to see all available variables.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/node-nginx:latest
    volumes:
      # Mount your custom entrypoint scripts into the 'custom' directory
      - ./my-entrypoint-scripts:/usr/bin/container/custom
```

## Default Script (index.php)

To get you started quickly, the image includes a simple default `index.php` file located at `/var/www/html/public/index.php`. This file displays a welcome message and some basic PHP configuration information. You can replace this file with your own application code by mounting your project into `/var/www/html`.

## The Shell Environment and the Bash Wrapper

A common challenge in Docker is that environment variables set during an entrypoint's execution are not automatically available to subsequent `docker exec` sessions or different shell environments. This image solves this problem with a "bash wrapper."

During the build process, the original `/bin/bash` is moved to `/bin/_bash`, and a new `/bin/bash` script is put in its place. This wrapper does one simple thing: before executing the real bash, it sources the file at `/etc/container-vars.sh`, which is generated by the entrypoint and contains all exported variables. The `/bin/sh` shell is also symlinked to this wrapper.

> The PHP CLI has a similar mechanism. The `/usr/local/bin/php` binary is moved to `/usr/local/bin/_php`, and a wrapper script is placed at `/usr/local/bin/php` that uses the above bash wrapper to execute PHP with the correct environment.

**Implications for You:**

- **Seamless `exec`:** Variables like `DOCKER_SERVICE_ABS_PATH` will be available in `docker exec my-container env` or `docker exec my-container bash`.
- **Other Shells (e.g., `zsh`):** If you install and use a different shell, it will **not** inherit these variables automatically. To get the same behavior, you would need to configure your `~/.zshrc` (or equivalent) to source `/etc/container-vars.sh` upon startup.

## Build-Time Execution with Multi-Stage Builds

Beyond running as a web or worker service, this image includes a powerful **"Build Mode"** designed to be used inside your `Dockerfile` during a `docker build` process.

This feature allows you to leverage the container's fully configured environment—including all its environment variables, helper scripts, and logic—to perform build tasks like compiling frontend assets, running database migrations, or running unit tests.

### How It Works

Build Mode is activated automatically:

> When you execute the entrypoint script (`/usr/bin/container/entrypoint.sh`) inside a `Dockerfile` `RUN` instruction **without** providing any command, the framework detects this and sets `CONTAINER_MODE="build"`.

It then proceeds to run all the normal setup steps, making variables like `DOCKER_SERVICE_ABS_PATH` available to subsequent `RUN` commands. Crucially, it skips the final `exec` step, allowing the Docker build to continue.

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
RUN /usr/bin/container/entrypoint.sh

# 2. Run your build commands. They now have access to all container variables.
RUN composer install --no-dev --optimize-autoloader
RUN ./vendor/bin/phpunit
```

Then, to execute your unit-tests start the build with:

```bash
docker build --build-arg DOCKER_PROJECT_PROTOCOL=https --build-arg DOCKER_PROJECT_HOST=my-app.com -t my-app-test .
```

By using this pattern, you ensure that the environment variables and paths used during your build process are identical to those that will be used in production, eliminating a common source of bugs. You can also use filename markers like `my-script.mode-build.sh` in your custom entrypoint hooks to run scripts exclusively during the build phase.
