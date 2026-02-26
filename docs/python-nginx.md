# Python Images - with NGINX

Welcome to the `python-nginx` images!

These images are designed as self-contained, high-performance services. The philosophy is to provide a complete, production-ready Python application runtime that includes a pre-configured NGINX web server as a reverse proxy and **Gunicorn** as the WSGI application server.

Think of this image as a "service-in-a-box." You put your code in, configure it with environment variables, and it just works—whether in local development or behind a production load balancer.

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

1.  **Web Mode (Default):** This is the standard mode. The script starts and configures both NGINX (as a reverse proxy) and **Gunicorn** (as the WSGI application server) to serve traffic over HTTP. NGINX proxies requests to Gunicorn via a Unix socket.
2.  **Worker Mode:** Activated by setting the `PYTHON_WORKER_COMMAND` variable. In this mode, NGINX is disabled, and Supervisor is configured to run your specified command instead. This is perfect for running queue workers, schedulers, or other long-running background tasks.

## Configuration via Environment Variables

This image is configured almost entirely through environment variables. This allows you to use the same image for different purposes (web vs. worker, dev vs. prod) without rebuilding it.

| Variable                      | Description                                                                                                                                                                           | Default Value                          |
|:------------------------------|:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:---------------------------------------|
| **General**                   |                                                                                                                                                                                       |                                        |
| `PUID`                        | The user ID to run processes as (`www-data`). Useful for matching host file permissions.                                                                                              | `33`                                   |
| `PGID`                        | The group ID to run processes as (`www-data`). Useful for matching host file permissions.                                                                                             | `33`                                   |
| `CONTAINER_MODE`              | Read-only. Automatically set to `web`, `worker` or `build`.                                                                                                                           | `web`                                  |
| `MAX_UPLOAD_SIZE`             | A convenient variable to set NGINX's `client_max_body_size`.                                                                                                                          | `100M`                                 |
| `ENVIRONMENT`                 | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production.                                                                      | `production`                           |
| `APP_ENV`                     | The application environment flag. Derived from `ENVIRONMENT` if not explicitly set.                                                                                                   | (derived)                              |
| `FLASK_ENV`                   | The Flask environment variable. Derived from `ENVIRONMENT` if not explicitly set.                                                                                                     | (derived)                              |
| `APP_DEBUG`                   | Debug flag for the application. Derived from `ENVIRONMENT` / `APP_ENV` if not explicitly set.                                                                                         | (derived: `1` in dev, `0` otherwise)   |
| **Project**                   |                                                                                                                                                                                       |                                        |
| `DOCKER_PROJECT_HOST`         | The public hostname for your application (available for your app).                                                                                                                    | `localhost`                            |
| `DOCKER_PROJECT_PATH`         | The public root path of the entire project.                                                                                                                                           | `/`                                    |
| `DOCKER_PROJECT_PROTOCOL`     | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                                                                                            | `http`                                 |
| `DOCKER_SERVICE_PROTOCOL`     | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                                                                                     | (derived)                              |
| `DOCKER_SERVICE_PATH`         | The sub-path for this specific service within the project.                                                                                                                            | `/`                                    |
| `DOCKER_SERVICE_ABS_PATH`     | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                                                                                      | (derived)                              |
| **NGINX**                     |                                                                                                                                                                                       |                                        |
| `NGINX_DOC_ROOT`              | The document root NGINX serves static files from.                                                                                                                                     | `/var/www/html/public`                 |
| `NGINX_CLIENT_MAX_BODY_SIZE`  | Sets `client_max_body_size` in NGINX.                                                                                                                                                 | Matches `MAX_UPLOAD_SIZE`              |
| `NGINX_CERT_PATH`             | Path to the SSL certificate (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                   | `/etc/ssl/certs/custom/cert.pem`       |
| `NGINX_KEY_PATH`              | Path to the SSL key (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                           | `/etc/ssl/certs/custom/key.pem`        |
| `NGINX_PROXY_CONNECT_TIMEOUT` | Sets `proxy_connect_timeout` in NGINX. This value defines the timeout for establishing a connection with a proxied server.                                                            | `5s`                                   |
| `NGINX_PROXY_READ_TIMEOUT`    | Sets `proxy_read_timeout` in NGINX. This value defines the timeout for reading a response from a proxied server.                                                                      | `60s`                                  |
| `NGINX_PROXY_SEND_TIMEOUT`    | Sets `proxy_send_timeout` in NGINX. This value defines the timeout for transmitting a request to a proxied server.                                                                    | `60s`                                  |
| `NGINX_KEEPALIVE_TIMEOUT`     | Sets `keepalive_timeout` in NGINX. This value defines the timeout for keeping connections alive with clients. If omitted, automatically calculated based on the other TIMEOUT values.  | (calculated)                           |
| `NGINX_TRY_FILES`             | Sets the `try_files` directive in the root location of the nginx server.                                                                                                              | `/static/$uri @pythonproxy`            |
| **Gunicorn (Web Mode)**       |                                                                                                                                                                                       |                                        |
| `PYTHON_APP_MODULE`           | The WSGI application module in `module:callable` format. This tells Gunicorn where to find your application.                                                                          | `server:app`                           |
| `GUNICORN_WORKERS`            | The number of Gunicorn worker processes.                                                                                                                                              | `4`                                    |
| `GUNICORN_WORKER_CLASS`       | The type of Gunicorn worker processes (e.g., `sync`, `gevent`, `uvicorn.workers.UvicornWorker`).                                                                                      | `sync`                                 |
| `GUNICORN_LOG_LEVEL`          | The Gunicorn log level (e.g., `debug`, `info`, `warning`, `error`, `critical`).                                                                                                       | `info`                                 |
| `GUNICORN_SOCKET`             | Read-only. The path to the Unix socket Gunicorn binds to and NGINX proxies to.                                                                                                        | `/run/gunicorn.sock`                   |
| **Python Worker Mode**        |                                                                                                                                                                                       |                                        |
| `PYTHON_WORKER_COMMAND`       | The command to execute in worker mode. **Setting this enables worker mode.**                                                                                                          |                                        |
| `PYTHON_WORKER_PROCESS_COUNT` | The number of worker processes to run (`numprocs` in Supervisor).                                                                                                                     | `1`                                    |

### ENVIRONMENT, `APP_ENV`, and `FLASK_ENV` Derivation

The `ENVIRONMENT` variable is a high-level switch for the container's operational mode. It is shared across all images in this ecosystem and influences NGINX configurations, logging verbosity, and other entrypoint behaviors.

-   **Possible Values:** `production` (or `prod`) and `development` (or `dev`).
-   **Default:** `production`.
-   **Rule:** Any value other than `development` or `dev` is treated as a production environment.

**`APP_ENV` and `FLASK_ENV` Derivation Logic:**

To align with standard Python/Flask practices, the `APP_ENV` and `FLASK_ENV` variables are automatically derived from `ENVIRONMENT`. You generally do not need to set them yourself.

1.  If `ENVIRONMENT` is set to `production` or `prod`, `APP_ENV` defaults to `prod` and `FLASK_ENV` defaults to `production`.
2.  If `ENVIRONMENT` is set to `development` or `dev`, `APP_ENV` defaults to `dev` and `FLASK_ENV` defaults to `development`.
3.  If you set `APP_ENV` explicitly, **your value will always take precedence**. This allows you to run in a `production` container `ENVIRONMENT` (with optimized NGINX settings) while having `APP_ENV` set to `staging`, for example.

Additionally, `APP_DEBUG` is automatically derived:

-   It is set to `1` when `ENVIRONMENT` or `APP_ENV` is `development` or `dev`.
-   It is set to `0` otherwise.
-   You can override it by setting `APP_DEBUG` explicitly.

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

In `web` mode, the entrypoint script configures NGINX and Gunicorn to serve your application. NGINX acts as the front-facing server, handling static files and proxying dynamic requests to Gunicorn over a **Unix socket** (`/run/gunicorn.sock`). By default, it operates over plain HTTP, but enabling SSL for HTTPS is controlled via a single environment variable.

**How NGINX and Gunicorn Work Together:**

1.  A request arrives at NGINX on port 80 (or 443 for HTTPS).
2.  NGINX first attempts to serve the request as a static file from the `/var/www/html/static/` directory (controlled by `NGINX_TRY_FILES`).
3.  If no static file matches, NGINX proxies the request to Gunicorn via the Unix socket at `/run/gunicorn.sock`.
4.  Gunicorn passes the request to your Flask (or other WSGI) application and returns the response through NGINX to the client.

This process is known as **SSL Termination** when HTTPS is enabled, where NGINX handles the performance-intensive work of encrypting and decrypting traffic, freeing your application to communicate over plain HTTP internally.

**Controlling the Protocol:**

The `DOCKER_PROJECT_PROTOCOL` and `DOCKER_SERVICE_PROTOCOL` variables work together to manage this.

- `DOCKER_PROJECT_PROTOCOL`: Defines how the **end-user** connects to your service from the outside world. Set this to `"https"` if your service is exposed via HTTPS.
- `DOCKER_SERVICE_PROTOCOL`: Defines how the **reverse proxy talks to your application container**. If you are terminating SSL at an outer proxy, you should set this to `"http"`. It defaults to the value of `DOCKER_PROJECT_PROTOCOL`.

**Common Scenarios:**

1. **Direct HTTPS Exposure:**
    - **Goal:** This container handles SSL directly.
    - **Config:** `DOCKER_PROJECT_PROTOCOL="https"` (and leave `DOCKER_SERVICE_PROTOCOL` unset).
    - **Result:** NGINX listens on port 443 with SSL, using certificates from `NGINX_CERT_PATH` and `NGINX_KEY_PATH`, and redirects HTTP traffic to HTTPS. You must mount your certificates into the container at `/container/custom/certs/`.

2. **SSL Termination at an External Gateway (Recommended for Production):**
    - **Goal:** A different proxy (like Traefik, Caddy, or another `nginx` instance) handles SSL, and forwards plain HTTP traffic to this container.
    - **Config:** `DOCKER_PROJECT_PROTOCOL="https"` (so your app can generate correct public URLs) and `DOCKER_SERVICE_PROTOCOL="http"`.
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

## Build Mode at a Glance

Automatically activated when no command is provided. This mode sets up the full container environment for multi-stage builds, dependency installation, testing, or compilation without starting any services.

Learn more about it in the [Build Mode Documentation](#build-time-execution-with-multi-stage-builds)

## Advanced Customization: Templating and Overrides

This image uses a powerful templating engine that processes **all internal configuration files** on startup. This allows for deep customization of NGINX, Supervisor, Gunicorn, and other components without rebuilding the image.

### The `/container/custom` Directory

**All customization happens through a single mount point: `/container/custom`**

This centralized approach simplifies volume management and provides a clear structure for organizing your custom configurations, scripts, and certificates.

```yaml
services:
  app:
    image: neunerlei/python-nginx:latest
    volumes:
      # Single mount for all customizations
      - ./docker/custom:/container/custom
```

**Structure:**

```
docker/custom/
├── nginx/              # Custom NGINX snippets (server-level)
│   ├── global/         # Custom NGINX snippets (http-level)
│   ├── location/       # Custom NGINX snippets (root-location-level "/")
│   └── errorPage.html  # Optional: Custom error page template
├── certs/              # SSL certificates (cert.pem, key.pem)
└── entrypoint/         # Custom startup scripts
```

> **Development Mode Bonus:** When running with `ENVIRONMENT=development`, the container will automatically create this directory structure for you if `/container/custom` is mounted. This provides a clear guide for what you can customize.

### How Templating Works

Every configuration file (both built-in templates in `/container/templates/` and your custom files in `/container/custom/`) is treated as a template. The entrypoint script reads these files, substitutes placeholders with their corresponding environment variable values, and writes the final config to its destination.

You can use any of the environment variables listed above as placeholders in your custom files, using the syntax `${VAR_NAME}`.

> Whenever you see `TEMPLATES` in the headlines below, it means that you can use variables in the files.

#### The `[[DEBUG_VARS]]` Helper

To see exactly which variables are available for a template, you can add the special string `[[DEBUG_VARS]]` anywhere in a `.conf` file you are customizing. When the container starts, the template engine will detect this, print a list of all available variables and their current values to the console, and then exit. This is an invaluable tool for debugging your configurations.

Example output:

```
DEBUG_VARS detected in template: '/container/custom/nginx/my_debug.conf'. Current variables that can be substituted:
  - ${CONTAINER_MODE} = web
  - ${ENVIRONMENT} = production
  - ${NGINX_DOC_ROOT} = /var/www/html/public
  - ${GUNICORN_WORKERS} = 4
  - ${PYTHON_APP_MODULE} = server:app
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

*   **How:** Inside your custom directory, create a `nginx/global/` sub-directory.
*   **Result:** The files are processed and included globally in the `http` block.

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
        ├── 01-basic-auth.prod.conf
        └── 02-custom-rewrites.conf
```

**Example:**

```nginx
# docker/custom/nginx/location/01-basic-auth.prod.conf
auth_basic "Restricted";
auth_basic_user_file /etc/nginx/.htpasswd;
```

#### 2. Custom SSL Certificates `TEMPLATES`

For HTTPS support, provide your SSL certificate and private key:

* **How:** Place `cert.pem` and `key.pem` in `./docker/custom/certs/`.
* **Result:** When `DOCKER_SERVICE_PROTOCOL="https"`, NGINX will use these certificates.

**Directory structure:**

```
docker/custom/
└── certs/
    ├── cert.pem
    └── key.pem
```

> **Warning:** If no custom certificates are found and HTTPS is enabled, the container will generate self-signed certificates and display a warning. This is only suitable for development.

#### 3. Custom Error Pages `TEMPLATES`

Customize the error pages shown for HTTP status codes (400, 401, 403, 404, 500, 502, 503, 504).

* **How:** Place `errorPage.html` and/or `errorPage.json` in `./docker/custom/nginx/`.
* **Result:** These templates will be used to generate all error pages. They support variable substitution including `${ERROR_CODE}`, `${ERROR_TITLE}`, and `${ERROR_DESCRIPTION}`.

**Example `errorPage.html`:**

```html
<!DOCTYPE html>
<html>
<head><title>${ERROR_TITLE}</title></head>
<body>
<h1>${ERROR_CODE}</h1>
<p>${ERROR_DESCRIPTION}</p>
<p>Environment: ${ENVIRONMENT}</p>
</body>
</html>
```

#### 4. Custom Entrypoint Hooks `MARKER-AWARE`

Run your own scripts when the container starts, just before the main command (`supervisord`) is executed.

* **How:** Place `.sh` files in `./docker/custom/entrypoint/`.
* **Result:** These scripts are executed during the container's startup process. All environment variables are automatically available.

**Directory structure:**

```
docker/custom/
└── entrypoint/
    ├── 01-run-migrations.mode-build.sh
    ├── 02-clear-cache.mode-web.sh
    └── 03-warm-cache.prod.sh
```

> **Note:** Unlike templates, entrypoint scripts are executed directly. You can use commands like `printenv | sort` to see all available variables, but the `[[DEBUG_VARS]]` helper is not available in shell scripts.

**Example script:**

```bash
#!/bin/bash
# 02-clear-cache.mode-web.sh
echo "Clearing application cache for web mode..."
python /var/www/html/scripts/clear_cache.py
```

#### 5. Overriding Core Templates (Advanced) `TEMPLATES`

For maximum control, you can completely replace any of the container's default template files. This is an "all-or-nothing" approach best used for fundamentally changing a core component.

*   **How:** Identify the default template (e.g., `/container/templates/nginx/nginx.conf` or `/container/templates/python/gunicorn.conf.py`). In your project, create your version and mount it to the *exact same path* inside the container.
* **Result:** Your mounted file will completely replace the image's default. The entrypoint will then process *your* template instead.

> **Note:** Filename markers do **not** apply when directly overriding a core template file.

### Complete Example

Here's a complete example showing all customization types:

```
project/
├── docker-compose.yml
├── docker/
│   └── custom/
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

> **Breaking Change:** All customization paths have been centralized to `/container/custom`.

If you're upgrading from an older version that used individual mount points like `/etc/ssl/certs`, `/etc/container/templates/nginx/custom`, etc., your container will **fail to start** and display a clear error message with migration instructions.

**Old structure (no longer supported):**

```yaml
volumes:
  - ./docker/certs:/etc/ssl/certs
  - ./docker/nginx:/etc/container/templates/nginx/custom
  - ./docker/entrypoint:/usr/bin/container/custom
```

**New structure:**

```yaml
volumes:
  - ./docker/custom:/container/custom
```

See the [Migration Guide](https://github.com/Neunerlei/docker-images/blob/main/docs/migration/migrate-to-centralized-container-dir.md) for detailed instructions.

## Default Application (`server.py`)

To get you started quickly, the image includes a simple Flask application at `/var/www/html/server.py`. This file provides a WSGI callable named `app` that Gunicorn serves by default. It displays a welcome message and, if `APP_ENV` is not `prod`, a list of environment variables.

The default `requirements.txt` includes **gunicorn** and **flask**. You can replace both files with your own application code by mounting your project into `/var/www/html`.

NGINX is configured to serve static files from `/var/www/html/static/` first (via the `try_files` directive), and if a file is not found, it proxies the request to Gunicorn. If your WSGI application module is not `server:app`, set the `PYTHON_APP_MODULE` environment variable to point to the correct `module:callable` (e.g., `myapp.wsgi:application`).

### Installing Custom Dependencies

When building your own image on top of this one, add your `requirements.txt` and install it into the virtual environment:

```dockerfile
FROM neunerlei/python-nginx:latest

COPY --chown=www-data:www-data ./requirements.txt /var/www/html/requirements.txt
RUN gosu www-data pip install --no-cache-dir -r /var/www/html/requirements.txt

COPY --chown=www-data:www-data ./src /var/www/html
```

The venv's `pip` and `python` are already on the `PATH`, so you can use them directly. A convenience symlink at `/var/www/venv` points to the venv at `/opt/venv`.

## The Shell Environment and the Bash Wrapper

A common challenge in Docker is that environment variables set during an entrypoint's execution are not automatically available to subsequent `docker exec` sessions or different shell environments. This image solves this problem with a "bash wrapper."

During the build process, the original `/bin/bash` is moved to `/bin/_bash`, and a new `/bin/bash` script is put in its place. This wrapper does one simple thing: before executing the real bash, it sources the file at `/container/work/container-vars.sh`, which is generated by the entrypoint and contains all exported variables. The `/bin/sh` shell is also symlinked to this wrapper.

Additionally, the venv's `python` and `pip` executables are wrapped in a similar fashion, ensuring they always have access to the container's environment variables.

**Implications for You:**

-   **Seamless `exec`:** Variables like `DOCKER_SERVICE_ABS_PATH`, `PYTHON_APP_MODULE`, and `GUNICORN_WORKERS` will be available in `docker exec my-container env` or `docker exec my-container bash`.
-   **Other Shells (e.g., `zsh`):** If you install and use a different shell, it will **not** inherit these variables automatically. To get the same behavior, you would need to configure your `~/.zshrc` (or equivalent) to source `/container/work/container-vars.sh` upon startup.

## Build-Time Execution with Multi-Stage Builds

Beyond running as a web or worker service, this image includes a powerful **"Build Mode"** designed to be used inside your `Dockerfile` during a `docker build` process.

This feature allows you to leverage the container's fully configured environment—including all its environment variables, helper scripts, and logic—to perform build tasks like compiling assets, running database migrations, or running unit tests.

### How It Works

Build Mode is activated automatically:

> When you execute the entrypoint script (`/container/entrypoint/entrypoint.sh`) inside a `Dockerfile` `RUN` instruction **without** providing any command, the framework detects this and sets `CONTAINER_MODE="build"`.

It then proceeds to run all the normal setup steps, making variables like `DOCKER_SERVICE_ABS_PATH` available to subsequent `RUN` commands. Crucially, it skips the final `exec` step, allowing the Docker build to continue.

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
RUN gosu www-data pip install --no-cache-dir -r requirements.txt
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
