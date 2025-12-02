# Documentation for `neunerlei/nginx`

Welcome to the `neunerlei/nginx` image!

This is not just another NGINX container. It's a smart, self-configuring reverse proxy designed to be the central gateway for your multi-service projects. It acts as the "front door," intelligently routing traffic to your backend services based on simple, declarative environment variables.

Think of this image as an "orchestrator-in-a-box" for your project. You define which services live at which paths, and the proxy automatically builds the correct routing configuration for you.

## Tags

Here you can find [all available tags](https://docker.neunerlei.eu/neunerlei-nginx-tags.html) of this image.

## Quick Start

The quickest way to get started is with a `docker-compose.yml` file. This example sets up the proxy to route traffic to two backend services: a frontend application at `/` and a backend API at `/api`.

```yaml
# docker-compose.yml
services:
  # 1. The Smart Proxy Service
  proxy:
    image: neunerlei/nginx:latest
    ports:
      - "80:80"   # Expose standard HTTP port
    environment:
      # --- Define the services to proxy to ---

      # Main frontend app on the root path
      - PROXY_FRONTEND_CONTAINER=frontend-app
      - PROXY_FRONTEND_PATH=/
      - PROXY_FRONTEND_PORT=3000

      # Backend API on a sub-path, rewrite url to its root
      - PROXY_API_CONTAINER=backend-app
      - PROXY_API_PATH=/api
      - PROXY_API_DEST=/ # Route /api/* to /* on the backend-app

  # 2. Your Application Services
  frontend-app:
  # ... your frontend service definition, listening on port 3000 ...

  backend-app:
  # ... your backend service definition, listening on port 80 ...
```

Run `docker-compose up`, and the proxy will automatically:

* Route requests to `http://localhost:8080/` to the `frontend-app` on its internal port 3000.
* Route requests to `http://localhost:8080/api/users` to the `backend-app`, sending the request as `/users`.

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, it detects its operating mode and configures NGINX accordingly.

1. **Proxy Mode:** This is the main mode. If the script detects any `PROXY_*_CONTAINER` environment variables, it scans all of them and builds a sophisticated reverse proxy configuration.
2. **Static Mode:** If no `PROXY_*` variables are found, the image gracefully falls back to being a simple web server, serving static files from `/var/www/html/public`. This makes a single instance of the image useful for either being a gateway or a simple file server.

## Configuration via Environment Variables

The proxy is configured almost entirely through declarative environment variables.

| Variable                     | Description                                                                                                                                          | Default Value              |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------|
| **General**                  |                                                                                                                                                      |                            |
| `PUID`                       | The user ID to run processes as (`www-data`). Useful for matching host file permissions.                                                             | `33`                       |
| `PGID`                       | The group ID to run processes as (`www-data`). Useful for matching host file permissions.                                                            | `33`                       |
| `CONTAINER_MODE`             | Read-only. Automatically set to `proxy` or `static`.                                                                                                 | `static`                   |
| `MAX_UPLOAD_SIZE`            | A convenient variable to set the global `client_max_body_size`. This applies only if in "proxy" mode, as all uploads need to pass through the proxy. | `100M`                     |
| `ENVIRONMENT`                | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production.                                     | `production`               |
| **Project**                  |                                                                                                                                                      |                            |
| `DOCKER_PROJECT_HOST`        | The public hostname for your application (available for your app).                                                                                   | `localhost`                |
| `DOCKER_PROJECT_PATH`        | The public root path of the entire project.                                                                                                          | `/`                        |
| `DOCKER_PROJECT_PROTOCOL`    | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                                                           | `http`                     |
| `DOCKER_SERVICE_PROTOCOL`    | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                                                    | (derived)                  |
| `DOCKER_SERVICE_PATH`        | The sub-path for this specific service within the project.                                                                                           | `/`                        |
| `DOCKER_SERVICE_ABS_PATH`    | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                                                     | (derived)                  |
| **NGINX**                    |                                                                                                                                                      |                            |
| `NGINX_DOC_ROOT`             | The document root NGINX serves static files from.                                                                                                    | `/var/www/html/public`     |
| `NGINX_CLIENT_MAX_BODY_SIZE` | Sets `client_max_body_size` in NGINX.                                                                                                                | Matches `MAX_UPLOAD_SIZE`  |
| `NGINX_CERT_PATH`            | Path to the SSL certificate (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                  | `/etc/ssl/certs/cert.pem`  |
| `NGINX_KEY_PATH`             | Path to the SSL key (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                          | `/etc/ssl/certs/key.pem`   |
| **Advanced/Internal**        |                                                                                                                                                      |                            |
| `CONTAINER_TEMPLATE_DIR`     | The path to the container's internal template files.                                                                                                 | `/etc/container/templates` |
| `CONTAINER_BIN_DIR`          | The path to the container's internal binary and script files.                                                                                        | `/usr/bin/container`       |

### ENVIRONMENT

The `ENVIRONMENT` variable is shared between all my base images and is used to define the overall environment your application is running in. It can be set to either `development` (or `dev`) or `production` (or `prod`); the values in brackets will be expanded to their full forms automatically. This variable is primarily used to load the correct NGINX configuration, but it also influences other behaviors in the entrypoint script. If any other value is provided, it will be used as-is.

> Please note tho, that every value other than `development` or `dev` is considered production.

## Proxy Mode In-Depth

In `proxy` mode, the entrypoint generates a unique `location` block for each service key it finds.

### Proxy Service Configuration Variables

For each service you want to proxy, you define a group of variables with a unique key (e.g., `FRONTEND`, `BACKEND`, `API_V2`).

| Variable Pattern         | Description                                                                                           |
|--------------------------|-------------------------------------------------------------------------------------------------------|
| `PROXY_<KEY>_CONTAINER`  | **(Required)** The hostname of the backend service (usually the Docker Compose service name).         |
| `PROXY_<KEY>_PATH`       | The public path for this service. Default is `/`.                                                     |
| `PROXY_<KEY>_DEST`       | **(Optional)** Rewrites the request path. `_PATH=/api` and `_DEST=/` routes `/api/users` to `/users`. |
| `PROXY_<KEY>_PROTOCOL`   | **(Optional)** The protocol to communicate with the backend (`http` or `https`). Default is `http`.   |
| `PROXY_<KEY>_PORT`       | **(Optional)** The internal port the backend listens on (for HTTP). Default is `80`.                  |
| `PROXY_<KEY>_HTTPS_PORT` | **(Optional)** The internal port the backend listens on (for HTTPS). Default is `443`.                |

### **Project Base Path in Proxy Mode**

You can serve the entire proxied application from a sub-directory using `DOCKER_PROJECT_PATH`.

* **Public URL goal:** `https://example.com/my-project/` should go to the `frontend` container, and `https://example.com/my-project/api/` to the `backend`.
* **Configuration:**
  ```yaml
  environment:
    - DOCKER_PROJECT_PATH=/my-project
    - PROXY_FRONTEND_CONTAINER=frontend
    - PROXY_FRONTEND_PATH=/
    - PROXY_API_CONTAINER=backend
    - PROXY_API_PATH=/api
  ```
* **Result:** The proxy automatically combines the project path and the service path for routing.

## **Static Mode In-Depth**

If no `PROXY_*` variables are found, the image runs as a high-performance web server for static files. This is perfect for serving a SPA (Single-Page Application), documentation, or a simple maintenance page.

### **Static Mode Configuration Variables**

In this mode, the image behaves like one of your application services (`node-nginx`, `php-nginx`) and can be placed behind another proxy.

| Variable                  | Description                                                             | Default Value          |
|---------------------------|-------------------------------------------------------------------------|------------------------|
| `NGINX_DOC_ROOT`          | The document root for static files.                                     | `/var/www/html/public` |
| `DOCKER_PROJECT_PATH`     | The base path for the entire project this service belongs to.           | `/`                    |
| `DOCKER_SERVICE_PATH`     | The unique sub-path for this static server.                             | `/`                    |
| `DOCKER_SERVICE_ABS_PATH` | Read-only. The derived absolute path (`PROJECT_PATH` + `SERVICE_PATH`). | (derived value)        |
| `DOCKER_SERVICE_PROTOCOL` | The protocol this service uses internally (usually `http`).             | (matches `PROJECT`)    |

### **Path Composition: `PROJECT_PATH` + `SERVICE_PATH`**

When running this image in `static` mode as part of a larger project, you need a way to manage its URL path. This image handles this by composing the final public URL path from two separate variables.

A reverse proxy sits between your users and your services, directing traffic to the right place based on the URL path.

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

#### Filename Markers for Conditional Loading

For greater flexibility, you can use special markers in your custom configuration filenames to control when they are loaded. The entrypoint script recognizes these markers and includes or excludes files based on the current environment. Whenever you see `MARKER-AWARE` in the options below, it means that these rules apply.

* `.prod.` : Loaded only if `ENVIRONMENT` is `production`.
* `.dev.` : Loaded only if `ENVIRONMENT` is `development`.
* `.https.` : Loaded only if `DOCKER_SERVICE_PROTOCOL` is `https`.

**Examples:**

* `01-security-headers.prod.conf`: Adds security headers, but only in production.
* `10-hsts.https.prod.conf`: Adds HSTS rules, but only when the service is running HTTPS in production.
* `20-redirects.conf`: A general-purpose file that is always loaded.

### Customization Methods

There are multiple ways to customize the container's behavior and configuration. Here are the primary methods:

#### 1. Adding Custom NGINX Snippets `MARKER-AWARE`

This is the standard, additive approach for extending NGINX.

**Directory Structure Example:**

```
my-nginx-configs/
├── 01-global-headers.conf              # Global snippet, always loaded
├── 99-security.prod.conf               # Global snippet, only for production
└── proxy/
    └── api/
        ├── 01-rate-limiting.conf       # Per-service snippet for 'api', always loaded
        └── 02-caching.prod.conf        # Per-service snippet for 'api', only for production
```

**Compose File:**

```yaml
services:
  proxy:
    image: neunerlei/nginx:latest
    volumes:
      - ./my-nginx-configs:/etc/container/templates/nginx/custom
    environment:
      - ENVIRONMENT=production
      - PROXY_API_CONTAINER=backend-app
      # ...
```

##### a) Server Snippets (server) `MARKER-AWARE`

These snippets are included in the main `server` block and are perfect for adding global rules, headers, or `map` blocks.

* **How:** Mount a directory containing your `.conf` files to `/etc/container/templates/nginx/custom/`.
* **Result:** The files are processed and included globally.

##### b) Per-Service Snippets (location) `MARKER-AWARE`

This powerful feature allows you to add custom rules *inside* the `location` block of a specific proxied service. This is ideal for things like per-route caching, rate-limiting, or custom headers.

* **How:** Inside your custom templates directory, create a `proxy` sub-directory, and then another directory named after the **lowercase version of your proxy key**.
    * For a service defined with `PROXY_API_CONTAINER`, the path would be `/etc/container/templates/nginx/custom/proxy/api/`.
* **Result:** Any `.conf` files in this directory will be included only within the `location` block for the `API` service.

##### c) Global Snippets (http) `MARKER-AWARE`

These snippets are included in the main `http` block and are perfect for adding global rules, headers, or `map` blocks.

* **How:** Inside your custom templates directory, create a `global` sub-directory.
* **Result:** The files are processed and included globally in the `http` block.

#### 2. Overriding Core Templates (Advanced)

For maximum control, you can completely replace any of the container's default template files. This is best used when snippets aren't enough to change a fundamental behavior.

* **How:** Identify the default template (e.g., `/etc/container/templates/nginx/nginx.conf`). In your project, create your version and mount it to the *exact same path* inside the container.
* **Result:** Your mounted file will completely replace the image's default. The entrypoint will then process *your* template instead.

> **Note:** Filename markers do **not** apply when directly overriding a core template file.

#### 3. Custom error pages

The `/etc/container/templates/nginx/service.errors.nginx.conf` file is responsible for handling error pages in the nginx configuration. By default, it supports custom error pages for HTTP status codes 400, 401, 403, 404, 500, 502, 503, and 504; both as HTML and JSON responses.

You can customize these error pages by overriding the default templates at: `/etc/container/templates/nginx/errorPage.html` or `/etc/container/templates/nginx/errorPage.json`.
Note, that these files are templates, so you can use any environment variables defined in the container within these files, additionally you have access to: `ERROR_CODE`, `ERROR_TITLE` and `ERROR_DESCRIPTION`, which will be replaced with the actual error code, title and description when the error page is rendered.

#### 4. Custom Entrypoint Hooks `MARKER-AWARE`

Additionally to service snippets, the image supports custom entrypoint hooks that allow you to run your own scripts when the container starts. The scripts will be executed, just before the main command (`supervisord`) is started.

* **How it works:** Place your custom `.sh` files in a local directory and mount it to `/usr/bin/container/custom`.
* **Result:** These files are treated as executable scripts and run during the container's startup process.

> You can use all environment variables in your scripts as well; but there is no `[[DEBUG_VARS]]` helper for scripts, as they are executed as normal shell scripts.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/node-nginx:latest
    volumes:
      # Mount your custom entrypoint scripts into the 'custom' directory
      - ./my-entrypoint-scripts:/usr/bin/container/custom
```

## Default index.html

If you run the image in `static` mode without mounting any files to `/var/www/html/public`, it will serve a default `index.html` page. Simply override this file with your own content by mounting your static files to that path.
