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

| Variable                          | Description                                                                                                         | Default Value             |
|-----------------------------------|---------------------------------------------------------------------------------------------------------------------|---------------------------|
| **General**                       |                                                                                                                     |                           |
| `PUID`                            | The user ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                                 | `33`                      |
| `PGID`                            | The group ID to run PHP-FPM and NGINX as. Useful for matching host file permissions.                                | `33`                      |
| `CONTAINER_MODE`                  | Read-only. Automatically set to `web` or `worker`.                                                                  | `web`                     |
| `MAX_UPLOAD_SIZE`                 | A convenient variable to set NGINX, `upload_max_filesize`, and `post_max_size` all at once.                         | `100M`                    |
| `APP_ENV`                         | Usage optional, can be used by your application to determine the environment. Suggested: `prod`, `dev`, `stage`     | `prod`                    |
| **Project**                       |                                                                                                                     |                           |
| `DOCKER_PROJECT_HOST`        | The hostname for your application (not actively used by the image but available for your app).                                                                                              | `localhost`                         |
| `DOCKER_PROJECT_PATH`        | The web root (not actively used by the image but available for your app).                                                                                                                   | `/`                                 |
| `DOCKER_PROJECT_PROTOCOL`    | Can be `http` or `https`. Determines if NGINX should listen for HTTP or HTTPS.                                                                                                              | `http`                              |
| `DOCKER_SERVICE_PROTOCOL`    | When running behind a proxy, your service might run on a different protocol than the public one. If omitted, it defaults to the value of `DOCKER_PROJECT_PROTOCOL`.                         | (matches `DOCKER_PROJECT_PROTOCOL`) |
| `DOCKER_SERVICE_PATH`        | When running behind a proxy, the `DOCKER_PROJECT_PATH` is expected to be the public path of the proxy. Your service might run on a "sub-path" of that path. If omitted, it defaults to `/`. | `/`                                 |
| `DOCKER_SERVICE_ABS_PATH`    | This combines `DOCKER_PROJECT_PATH` and `DOCKER_SERVICE_PATH` into an absolute path.                                                                                                        | (derived value)                     |
| **NGINX**                         |                                                                                                                     |                           |
| `NGINX_DOC_ROOT`                  | The document root NGINX should use.                                                                                 | `/var/www/html/public`    |
| `NGINX_CLIENT_MAX_BODY_SIZE`      | Overrides `client_max_body_size` in NGINX.                                                                          | Matches `MAX_UPLOAD_SIZE` |
| `NGINX_CERT_PATH`            | Path to the SSL certificate file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                                                                                                               | `/etc/ssl/certs/cert.pem`           |
| `NGINX_KEY_PATH`             | Path to the SSL key file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                                                                                                                       | `/etc/ssl/certs/key.pem`            |
| **PHP**                           |                                                                                                                     |                           |
| `PHP_UPLOAD_MAX_FILESIZE`         | Overrides PHP's `upload_max_filesize` directly.                                                                     | Matches `MAX_UPLOAD_SIZE` |
| `PHP_POST_MAX_SIZE`               | Overrides PHP's `post_max_size` directly.                                                                           | Matches `MAX_UPLOAD_SIZE` |
| `PHP_MEMORY_LIMIT`                | Overrides PHP's `memory_limit`.                                                                                     | `1024M`                   |
| `PHP_TIMEZONE`                    | Sets the default timezone for `date()` functions.                                                                   | `UTC`                     |
| `PHP_PROD_DISPLAY_ERRORS`         | Overrides `display_errors` in `php.prod.ini`.                                                                       | `Off`                     |
| `PHP_PROD_DISPLAY_STARTUP_ERRORS` | Overrides `display_startup_errors` in `php.prod.ini`.                                                               | `Off`                     |
| **PHP Worker Mode**               |                                                                                                                     |                           |
| `PHP_WORKER_COMMAND`              | The command to execute in worker mode. **Setting this enables worker mode.**                                        | (unset)                   |
| `PHP_WORKER_PROCESS_COUNT`        | The number of worker processes to run (`numprocs` in Supervisor).                                                   | `1`                       |
| **PHP-FPM**                       |                                                                                                                     |                           |
| `PHP_FPM_MAX_CHILDREN`            | `pm.max_children`                                                                                                   | `20`                      |
| `PHP_FPM_START_SERVERS`           | `pm.start_servers`                                                                                                  | `2`                       |
| `PHP_FPM_MIN_SPARE_SERVERS`       | `pm.min_spare_servers`                                                                                              | `1`                       |
| `PHP_FPM_MAX_SPARE_SERVERS`       | `pm.max_spare_servers`                                                                                              | `4`                       |
| `PHP_FPM_MAX_REQUESTS`            | `pm.max_requests`                                                                                                   | `500`                     |

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

### Customizing NGINX with Snippets

This image is designed to be extensible without being modified. The NGINX configuration includes several "hook" directories:

* `/etc/nginx/snippets/before.d/`
* `/etc/nginx/snippets/after.d/`

Any `.conf` file you mount into these directories will be included in the `server` block. `before.d` is included before the primary `location` block and proxy configuration, while `after.d` is included at the very end of the `server` block.

**Example: Adding a custom security header**

1. Create a file, e.g., `my-headers.conf`:
   ```nginx
   # my-headers.conf
   add_header X-Content-Type-Options "nosniff";
   ```
2. Mount this file into the `before.d` directory in your `docker-compose.yml`:
   ```yaml
   services:
     app:
       image: neunerlei/php-nginx:latest
       volumes:
         - ./your-code:/var/www/html
         # Mount the custom snippet
         - ./my-headers.conf:/etc/nginx/snippets/before.d/headers.conf
   ```

NGINX will now automatically include this header in its responses.

> When you are building your own derived images, you can also COPY files into these directories.

#### SSL Customization

When running in HTTPS mode, two additional hook directories are available that only apply to the SSL `server` block:

* `/etc/nginx/snippets/before.https.d/`
* `/etc/nginx/snippets/after.https.d/`

Any `.conf` files placed in these directories will be included in the SSL server block, allowing you to customize SSL settings further.
In general, the SSL configuration is included AFTER the main server configuration, so you can override settings as needed. The `before.https`
and `after.https` hooks are included before and after the SSL-specific settings, respectively.

The order of the hooks is as follows:

1. `/etc/nginx/snippets/before.d/`
2. The main service configuration (root, proxy pass, etc.).
3. `/etc/nginx/snippets/before.https.d/`
4. SSL-specific settings (`ssl_certificate`, hardening options).
5. `/etc/nginx/snippets/after.https.d/`
6. `/etc/nginx/snippets/after.d/`

> Feel free to name your certificate and key files anything you like; just make sure to adjust either the mount paths or `NGINX_KEY_PATH` and `NGINX_CERT_PATH` environment variables accordingly.
>
> For backward compatibility, if the specified certificate or key files are not found, it will also look at `/var/www/certs/cert.pem` and `/var/www/certs/key.pem` locations respectively; however a warning will be logged.

#### Variables in nginx.conf

To avoid configuration duplication in your nginx snippets, you can use the following variables that are replaced at runtime:

- DOCKER_PROJECT_HOST
- DOCKER_PROJECT_PROTOCOL
- DOCKER_PROJECT_PATH
- DOCKER_SERVICE_PROTOCOL
- DOCKER_SERVICE_PATH
- DOCKER_SERVICE_ABS_PATH
- NGINX_DOC_ROOT

They will be replaced with their respective values when the nginx configuration is generated.
Use them like this:

```nginx
location ^~ ${DOCKER_SERVICE_ABS_PATH}custom/ {
    root ${NGINX_DOC_ROOT};
    index index.html index.htm;
}
```

The replacement will happen in all files that are placed **directly** (not in subdirectories) in:

- /etc/nginx/snippets/before.d/
- /etc/nginx/snippets/after.d/
- /etc/nginx/snippets/before.https.d/
- /etc/nginx/snippets/after.https.d/

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

## Advanced Customization

The entrypoint provides two script hooks for advanced customization.

* `/usr/bin/app/entrypoint.user-setup.sh`: This script is executed early in the startup process. It's the ideal place to put the run-time user mapping logic for local development to solve UID/GID file permission issues. **IMPORTANT** This script is ONLY executed if the `PUID` and `PGID` environment variables are set to values different from the defaults. If you want to modify permissions unconditionally, use the `entrypoint.local.sh` hook instead.
* `/usr/bin/app/entrypoint.local.sh`: This script is executed just before the main command. It's a general-purpose hook for any other custom setup commands you might need.

### Default Script (index.php)

To get you started quickly, the image includes a simple default `index.php` file located at `/var/www/html/public/index.php`. This file displays a welcome message and some basic PHP configuration information. You can replace this file with your own application code by mounting your project into `/var/www/html`.
