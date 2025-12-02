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

| Variable                          | Description                                                                                                      | Default Value              |
|-----------------------------------|------------------------------------------------------------------------------------------------------------------|----------------------------|
| **General**                       |                                                                                                                  |                            |
| `PUID`                            | The user ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                              | `33`                       |
| `PGID`                            | The group ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                             | `33`                       |
| `CONTAINER_MODE`                  | Read-only. Automatically set to `web` or `worker`.                                                               | `web`                      |
| `MAX_UPLOAD_SIZE`                 | A convenient variable to set NGINX, `upload_max_filesize`, and `post_max_size` all at once.                      | `100M`                     |
| `ENVIRONMENT`                     | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production. | `production`               |
| `APP_ENV`                         | The semi-standard PHP framework environment variable.   Defaults to the value of `ENVIRONMENT`.                  | (derived)                  |
| **Project**                       |                                                                                                                  |                            |
| `DOCKER_PROJECT_HOST`             | The public hostname for your application (available for your app).                                               | `localhost`                |
| `DOCKER_PROJECT_PATH`             | The public root path of the entire project.                                                                      | `/`                        |
| `DOCKER_PROJECT_PROTOCOL`         | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                       | `http`                     |
| `DOCKER_SERVICE_PROTOCOL`         | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                | (derived)                  |
| `DOCKER_SERVICE_PATH`             | The sub-path for this specific service within the project.                                                       | `/`                        |
| `DOCKER_SERVICE_ABS_PATH`         | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                 | (derived)                  |
| **NGINX**                         |                                                                                                                  |                            |
| `NGINX_DOC_ROOT`                  | The document root NGINX should use.                                                                              | `/var/www/html/public`     |
| `NGINX_CLIENT_MAX_BODY_SIZE`      | Overrides `client_max_body_size` in NGINX.                                                                       | Matches `MAX_UPLOAD_SIZE`  |
| `NGINX_CERT_PATH`                 | Path to the SSL certificate file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                                    | `/etc/ssl/certs/cert.pem`  |
| `NGINX_KEY_PATH`                  | Path to the SSL key file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                                            | `/etc/ssl/certs/key.pem`   |
| **PHP**                           |                                                                                                                  |                            |
| `PHP_UPLOAD_MAX_FILESIZE`         | Overrides PHP's `upload_max_filesize` directly.                                                                  | Matches `MAX_UPLOAD_SIZE`  |
| `PHP_POST_MAX_SIZE`               | Overrides PHP's `post_max_size` directly.                                                                        | Matches `MAX_UPLOAD_SIZE`  |
| `PHP_MEMORY_LIMIT`                | Overrides PHP's `memory_limit`.                                                                                  | `1024M`                    |
| `PHP_TIMEZONE`                    | Sets the default timezone for `date()` functions.                                                                | `UTC`                      |
| `PHP_PROD_DISPLAY_ERRORS`         | Overrides `display_errors` in `php.prod.ini`.                                                                    | `Off`                      |
| `PHP_PROD_DISPLAY_STARTUP_ERRORS` | Overrides `display_startup_errors` in `php.prod.ini`.                                                            | `Off`                      |
| **PHP Worker Mode**               |                                                                                                                  |                            |
| `PHP_WORKER_COMMAND`              | The command to execute in worker mode. **Setting this enables worker mode.**                                     | (unset)                    |
| `PHP_WORKER_PROCESS_COUNT`        | The number of worker processes to run (`numprocs` in Supervisor).                                                | `1`                        |
| **PHP-FPM**                       |                                                                                                                  |                            |
| `PHP_FPM_MAX_CHILDREN`            | `pm.max_children`                                                                                                | `20`                       |
| `PHP_FPM_START_SERVERS`           | `pm.start_servers`                                                                                               | `2`                        |
| `PHP_FPM_MIN_SPARE_SERVERS`       | `pm.min_spare_servers`                                                                                           | `1`                        |
| `PHP_FPM_MAX_SPARE_SERVERS`       | `pm.max_spare_servers`                                                                                           | `4`                        |
| `PHP_FPM_MAX_REQUESTS`            | `pm.max_requests`                                                                                                | `500`                      |
| **Advanced/Internal**             |                                                                                                                  |                            |
| `CONTAINER_TEMPLATE_DIR`          | The path to the container's internal template files.                                                             | `/etc/container/templates` |
| `CONTAINER_BIN_DIR`               | The path to the container's internal binary and script files.                                                    | `/usr/bin/container`       |

### ENVIRONMENT

The `ENVIRONMENT` variable is shared between all my base images and is used to define the overall environment your application is running in. It can be set to either `development` (or `dev`) or `production` (or `prod`); the values in brackets will be expanded to their full forms automatically. This variable is primarily used to load the correct NGINX configuration, but it also influences other behaviors in the entrypoint script. If any other value is provided, it will be used as-is.

> Please note tho, that every value other than `development` or `dev` is considered production.

#### `APP_ENV` Derivation

If you do not explicitly set `APP_ENV`, it will be derived from `ENVIRONMENT` as follows:

* If `ENVIRONMENT` is `prod` or `production`, `APP_ENV` becomes `production`.
* If `ENVIRONMENT` is `dev` or `development`, `APP_ENV` becomes `development`.
* Otherwise, `APP_ENV` is set to the value of `ENVIRONMENT`.

If you set `APP_ENV` directly, its value will always be respected.

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

In the default `web` mode, the entrypoint script dynamically generates the NGINX configuration to act as a reverse proxy for your PHP application.

### HTTP vs. HTTPS

The image supports a simple way to enable SSL. This is fundamental for modern web applications and NGINX handles this process, known as SSL Termination, very efficiently [docs.nginx.com](https://docs.nginx.com/nginx/admin-guide/security-controls/terminating-ssl-http/).

* **By default (`DOCKER_PROJECT_PROTOCOL="http"`):** NGINX listens for plain HTTP on port 80.
* **When `DOCKER_PROJECT_PROTOCOL="https"`:** NGINX is configured to listen on port 443 with SSL, using certificates it expects to find at the paths specified by `NGINX_CERT_PATH` and `NGINX_KEY_PATH`. It also sets up an automatic redirect from HTTP (port 80) to HTTPS. You must mount your certificates to these paths.

This setup is great for local development with tools like `mkcert` or for production if you provide valid certificates.

> For a more automated approach to SSL, especially in production with Let's Encrypt certificates, you might consider a dedicated reverse proxy gateway like [linuxserver.io/swag](https://docs.linuxserver.io/images/docker-swag/) in front of this container (running in plain HTTP mode). Another good alternative is [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) with the [acme-companion](https://github.com/nginx-proxy/acme-companion).
> This allows you to centralize SSL management and offload that responsibility from your application containers.

#### SSL Termination using a proxy

When your service is running behind a reverse proxy [e.g. neunerlei/nginx](nginx.md), you might want to terminate the SSL connection at the proxy level. In this setup, your reverse proxy is exposed to the internet and handles all the complex and CPU-intensive work of HTTPS encryption and decryption. Once it receives a secure request, it "terminates" the SSL and forwards a plain, unencrypted HTTP request to the appropriate internal service.

This is beneficial because:

* **Centralized Security:** You only need to manage TLS certificates in one place (the proxy), not in every single application container.
* **Simplicity:** Your application containers don't need to be configured for HTTPS, simplifying their setup and code.

----

##### Example: A Secure Application with SSL Termination

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

You can learn more about this powerful feature in [Advanced Customization](#advanced-customization-templating-and-overrides), especially in the [Adding Custom NGINX Snippets](#1-adding-custom-nginx-snippets-recommended-for-most-cases) section.

In a nutshell:

* Place your custom NGINX `.conf` files in a local directory.
* Mount that directory to `/etc/container/templates/nginx/custom/` in the container.
* The entrypoint will process these files, substituting any environment variable placeholders, and include them in the main NGINX configuration.

Your custom snippets can add headers, redirects, or even new `location` blocks and can look like this:

```nginx
location ^~ ${DOCKER_SERVICE_ABS_PATH}custom/ {
    root ${NGINX_DOC_ROOT};
    index index.html index.htm;
}
```

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

**Example 2: Running a Generic "Cron" Task every 5 minutes**

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

## Advanced Customization: Templating and Overrides

This image uses a powerful templating engine that processes **all internal configuration files** on startup. This allows for deep customization of NGINX, Supervisor, and other components.

### How Templating Works

Every configuration file inside `/etc/container/templates/` is treated as a template. The entrypoint script will read these files, substitute placeholders with their corresponding environment variable values, and write the final config to its destination.

You can use any of the environment variables listed above as placeholders in your custom files, using the syntax `${VAR_NAME}`.

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

### Customization Methods

There are four primary ways to customize the container's configuration:

#### 1. Adding Custom NGINX Snippets (Recommended for most cases)

This is the standard, additive approach for extending NGINX. It's perfect for adding headers, redirects, or custom `location` blocks.

* **How it works:** Place your custom `.conf` files in a local directory and mount it to `/etc/container/templates/nginx/custom/`.
* **Result:** These files are treated as snippets. After variable substitution, they are copied to `/etc/nginx/snippets/service.d/` and included by the main server block.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/node-nginx:latest
    volumes:
      # Mount your custom snippets into the 'custom' directory
      - ./my-nginx-snippets:/etc/container/templates/nginx/custom
```

**Filename Markers for Conditional Loading:**
Snippets in this directory support special filename markers to be loaded conditionally:

* `.prod.` : The snippet is loaded only if `ENVIRONMENT` is `production`.
* `.dev.` : The snippet is loaded only if `ENVIRONMENT` is `development`.
* `.https.` : The snippet is loaded only if `DOCKER_SERVICE_PROTOCOL` is `https`.

**Examples:**

* `01-security-headers.prod.conf`: Adds security headers, but only in production.
* `10-hsts.https.prod.conf`: Adds HSTS rules, but only when the service is running HTTPS in production.
* `20-redirects.conf`: A general-purpose file that is always loaded.

#### 2. Adding Custom php.ini and php-fpm.conf Snippets

You can also extend the PHP configuration by adding custom snippets for `php.ini` and `php-fpm.conf`.
This procedure follows the same pattern as NGINX snippets, except instead of you putting your files in the `nginx/custom/` directory, you place them in: `/etc/container/templates/php/custom/`. `.ini` files will be treated as `php.ini` snippets, and `.conf` files as `php-fpm.conf` snippets.

> The default fpm-pool configuration is loaded as "www.conf"
> The default php.ini configuration is loaded as "x.php.common.ini" and "x.php.prod.ini" depending on the environment.
> So make sure your file names do not conflict with the defaults, and reflect the naming scheme (e.g. by prefixing with z- to load them last).

#### 3. Overriding Core Templates (Advanced)

For maximum control, you can completely replace any of the container's default template files. This is an "all-or-nothing" approach best used for fundamentally changing a core component.

* **How it works:** Identify the default template you wish to replace (e.g., `/etc/container/templates/nginx/service.root.nginx.conf`). In your project, create a file with your desired content and mount it to the *

#### 4. Custom Entrypoint Hooks

Additionally to service snippets, the image supports custom entrypoint hooks that allow you to run your own scripts when the container starts. The scripts will be executed, just before the main command (`supervisord`) is started.

* **How it works:** Place your custom `.sh` files in a local directory and mount it to `/usr/bin/container/custom`.
* **Result:** These files are treated as executable scripts and run during the container's startup process.

> Both, the sorting rules and the conditional filename markers described in the "Adding Custom NGINX Snippets" section also apply to these scripts. You can use all environment variables in your scripts as well; but there is no `[[DEBUG_VARS]]` helper for scripts, as they are executed as normal shell scripts.

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
