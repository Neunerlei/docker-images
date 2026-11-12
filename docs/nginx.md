# Documentation for `neunerlei/nginx`

Welcome to the `neunerlei/nginx` image!

This is not just another NGINX container. It's a smart, self-configuring reverse proxy designed to be the central gateway for your multi-service projects. It acts as the "front door," intelligently routing traffic to your backend services based on simple, declarative environment variables.

Think of this image as an "orchestrator-in-a-box" for your project. You define which services live at which paths, and the proxy automatically builds the correct routing configuration for you.

> **Shared behavior:** concepts that apply to all images — the entrypoint, container modes, customization, templating, read-only/Kubernetes operation and more — are documented once in [Shared Concepts](./common.md). This document keeps everything specific to this image.

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

* Route requests to `http://localhost/` to the `frontend-app` on its internal port 3000.
* Route requests to `http://localhost/api/users` to the `backend-app`, sending the request as `/users`.

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, it detects its operating mode and configures NGINX accordingly.

1. **Proxy Mode:** This is the main mode. If the script detects any `PROXY_*_CONTAINER` environment variables, it scans all of them and builds a sophisticated reverse proxy configuration.
2. **Static Mode:** If no `PROXY_*` variables are found, the image gracefully falls back to being a simple web server, serving static files from `/var/www/html/public`. This makes a single instance of the image useful for either being a gateway or a simple file server.

## Configuration via Environment Variables

The proxy is configured almost entirely through declarative environment variables.

| Variable                      | Description                                                                                                                                                                           | Default Value                            |
|-------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------|
| **General**                   |                                                                                                                                                                                       |                                          |
| `PUID`                        | The user ID to run processes as (`www-data`). Useful for matching host file permissions.                                                                                              | `33`                                     |
| `PGID`                        | The group ID to run processes as (`www-data`). Useful for matching host file permissions.                                                                                             | `33`                                     |
| `CONTAINER_MODE`              | Read-only. Automatically set to `proxy` or `static`.                                                                                                                                  | `static`                                 |
| `MAX_UPLOAD_SIZE`             | A convenient variable to set the global `client_max_body_size`. This applies only if in "proxy" mode, as all uploads need to pass through the proxy.                                  | `100M`                                   |
| `USER_OWNED_DIRECTORIES`      | Additional directories (space separated) that should be owned by the `www-data` user, e.g. for mounted volumes the application writes into. They are created when missing.           | (none)                                   |
| `MAX_UPLOAD_SIZE_BYTES`       | Read-only. The byte value of `MAX_UPLOAD_SIZE`, calculated by the entrypoint script.                                                                                                  | (calculated)                             |
| `ENVIRONMENT`                 | Sets the overall environment. `dev`/`development` is non-production; all other values are considered production.                                                                      | `production`                             |
| **Project**                   |                                                                                                                                                                                       |                                          |
| `DOCKER_PROJECT_HOST`         | The public hostname for your application (available for your app).                                                                                                                    | `localhost`                              |
| `DOCKER_PROJECT_PATH`         | The public root path of the entire project.                                                                                                                                           | `/`                                      |
| `DOCKER_PROJECT_PROTOCOL`     | The public protocol. `http` or `https`. Determines NGINX's listening mode.                                                                                                            | `http`                                   |
| `DOCKER_SERVICE_PROTOCOL`     | The protocol your service uses internally. Defaults to `DOCKER_PROJECT_PROTOCOL`.                                                                                                     | (derived)                                |
| `DOCKER_SERVICE_PATH`         | The sub-path for this specific service within the project.                                                                                                                            | `/`                                      |
| `DOCKER_SERVICE_ABS_PATH`     | Read-only. The absolute path for this service (`PROJECT_PATH` + `SERVICE_PATH`).                                                                                                      | (derived)                                |
| **NGINX**                     |                                                                                                                                                                                       |                                          |
| `NGINX_DOC_ROOT`              | The document root NGINX serves static files from.                                                                                                                                     | `/var/www/html/public`                   |
| `NGINX_CLIENT_MAX_BODY_SIZE`  | Sets `client_max_body_size` in NGINX. **Please prefer `MAX_UPLOAD_SIZE`**                                                                                                             | Matches `MAX_UPLOAD_SIZE`                |
| `NGINX_CERT_PATH`             | Path to the SSL certificate (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                   | `/etc/ssl/certs/custom/cert.pem`         |
| `NGINX_KEY_PATH`              | Path to the SSL key (if `DOCKER_SERVICE_PROTOCOL="https"`).                                                                                                                           | `/etc/ssl/certs/custom/key.pem`          |
| `NGINX_PROXY_CONNECT_TIMEOUT` | Sets `proxy_connect_timeout` in NGINX. This value defines the timeout for establishing a connection with a proxied server.                                                            | `5s`                                     |
| `NGINX_PROXY_READ_TIMEOUT`    | Sets `proxy_read_timeout` in NGINX. This value defines the timeout for reading a response from a proxied server.                                                                      | `60s`                                    |
| `NGINX_PROXY_SEND_TIMEOUT`    | Sets `proxy_send_timeout` in NGINX. This value defines the timeout for transmitting a request to a proxied server.                                                                    | `60s`                                    |
| `NGINX_KEEPALIVE_TIMEOUT`     | Sets `keepalive_timeout` in NGINX. This value defines the timeout for keeping connections alive with clients. If omitted, automatically calculated based on the other TIMEOUT values. | (calculated)                             |
| `NGINX_RESOLVER`              | Sets the `resolver` directive in NGINX (DNS servers for dynamic upstream names — a variable in `proxy_pass`). Auto-detected from `/etc/resolv.conf`, see [NGINX DNS Resolution](./common.md#nginx-dns-resolution).                    | Auto-detected, fallback `127.0.0.11`     |
| `NGINX_RESOLVER_VALID_TIMEOUT` | Sets the `valid=` parameter of the `resolver` directive: how long NGINX caches resolved DNS answers.                                                                                                                                  | `30s`                                    |
| `NGINX_RESOLVER_TIMEOUT`      | Sets `resolver_timeout` in NGINX: how long NGINX waits for an answer from a DNS server.                                                                                                                                               | `5s`                                     |
| `NGINX_TRY_FILES`             | (static only) Sets the `try_files` directive in the root location of the nginx server.                                                                                                | `$uri $uri/ /index.html /index.htm =404` |
| `NGINX_BASIC_AUTH`            | Enables basic auth for the **whole server**. Format: `username clear-password`. See [Basic Authentication](#basic-authentication).                                                     | (disabled)                             |
| `NGINX_BASIC_AUTH_1..n`       | Adds additional users to the global basic auth, e.g. `NGINX_BASIC_AUTH_2="user2 pass2"`. Any number of suffixes.                                                                       | (none)                                 |
| `NGINX_BASIC_AUTH_REALM`      | The realm name shown in the browser's login dialog for the global basic auth.                                                                                                          | `Restricted`                           |
| `NGINX_BASIC_AUTH_FILE`       | Read-only. Path to the generated global password file, usable in your own custom snippets. The generated `auth_basic` directives live in the always-present snippet `/etc/nginx/snippets/basicAuth.nginx.conf` (empty when disabled). | (derived)                |

### ENVIRONMENT

`ENVIRONMENT` = `production` (default) | `development`/`dev`; anything not `development`/`dev` counts as production.

See [The ENVIRONMENT Switch](./common.md#the-environment-switch) in the shared documentation.

### MAX_UPLOAD_SIZE and friends

`MAX_UPLOAD_SIZE` (default `100M`) sets all upload limits at once; `MAX_UPLOAD_SIZE_BYTES` is the parsed read-only byte value. Prefer it over the individual overrides.

See [MAX_UPLOAD_SIZE and Friends](./common.md#max_upload_size-and-friends) in the shared documentation for the full explanation.

### Basic Authentication

You can protect your server (or a single proxied service) with HTTP basic auth entirely through environment variables — no `htpasswd` utility or mounted password files needed. The entrypoint hashes the passwords (MD5-based `$apr1$`, as accepted by NGINX) and writes the password file on every boot, so changing a password is just an environment change and a restart.

**Protecting the whole server** (works in `proxy` and `static` mode):

```yaml
environment:
  - NGINX_BASIC_AUTH=admin clear-secret      # the first user: "username clear-password"
  - NGINX_BASIC_AUTH_2=jane another-secret   # additional users: _1, _2, _3, ... any number
  - NGINX_BASIC_AUTH_REALM=My Project        # optional, shown in the login dialog. Default: "Restricted"
```

The **first space** separates username and password — everything after it belongs to the password, so passwords may contain spaces. Numbered variables can be used in any combination (`_2` without `_1` works fine); empty values are ignored.

**Protecting a single proxied service** (only in `proxy` mode): the same scheme with a `PROXY_<KEY>_` prefix, applied only to that service's location:

```yaml
environment:
  - PROXY_API_CONTAINER=backend-app
  - PROXY_API_PATH=/api
  - PROXY_API_BASIC_AUTH=api-user api-secret    # only /api requires credentials
  - PROXY_API_BASIC_AUTH_2=api-user2 api-secret2
  - PROXY_API_BASIC_AUTH_REALM=API Area         # optional, Default: "Restricted"
```

A few details worth knowing:

* If both global and per-service auth are configured, the per-service authentication **replaces** the global one for that location (its users apply, the global users do not).
* Turning auth off again works through the same snippet mechanism: a snippet that declares `auth_basic` — including `auth_basic off;` — **takes ownership** for its context, and the entrypoint then skips its generated directives (NGINX forbids the directive twice in one context). For a single proxy service use `docker/custom/nginx/proxy/<key>.conf`, for the whole server a snippet in `docker/custom/nginx/`.
* The password files are always written, so an owning snippet can point `auth_basic_user_file` at `${NGINX_BASIC_AUTH_DIR}/proxy.<key>.htpasswd` (or `${NGINX_BASIC_AUTH_FILE}`) and keep the env-var managed users.
* The generated `auth_basic` directives are snippets like any other: `/etc/nginx/snippets/basicAuth.nginx.conf` for the server (registered like the built-in snippets, symlinked into the work directory) and `proxy.d/<key>.auth.conf` per service (picked up by the custom-snippet include of the location). Both always exist and are empty when the respective auth is disabled or owned by a custom snippet — do not give your own snippets those names.
* The error pages stay reachable without credentials, so failed logins still show the styled error page instead of a bare NGINX 401.
* A malformed value (e.g. a missing password or a username containing `:`) aborts the container startup with an error message — a typo can never silently disable the protection.
* **Troubleshooting "password mismatch":** the boot log prints every configured user with its password *length*. If logins fail although you entered the password correctly, compare that length with what you expect — some environment file parsers truncate values at characters like `#` or `$` before they reach the container. Verify what actually arrived with `docker exec <container> printenv NGINX_BASIC_AUTH` (or `PROXY_<KEY>_BASIC_AUTH`). Compose YAML lists and `.env` files pass such characters through unchanged, but unquoted values in shell scripts or third-party env UIs may not.

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
| `PROXY_<KEY>_BASIC_AUTH` | **(Optional)** Enables basic auth for **only this service's location**. Format: `username clear-password`. See [Basic Authentication](#basic-authentication). |
| `PROXY_<KEY>_BASIC_AUTH_1..n` | **(Optional)** Adds additional users to this service's basic auth, e.g. `PROXY_API_BASIC_AUTH_2="user2 pass2"`. |
| `PROXY_<KEY>_BASIC_AUTH_REALM` | **(Optional)** The realm name shown in the browser's login dialog for this service. Default is `Restricted`. |

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

| Variable         | Description                         | Default Value          |
|------------------|-------------------------------------|------------------------|
| `NGINX_DOC_ROOT` | The document root for static files. | `/var/www/html/public` |

### **Path Composition: `PROJECT_PATH` + `SERVICE_PATH`**

Public URLs compose from `DOCKER_PROJECT_PATH` + `DOCKER_SERVICE_PATH` into the read-only `DOCKER_SERVICE_ABS_PATH`.

See [Path Composition](./common.md#path-composition) in the shared documentation.

### HTTP vs. HTTPS

NGINX either terminates SSL itself (`DOCKER_PROJECT_PROTOCOL=https`, certificates mounted in `certs/`) — or, recommended for production, an outer gateway terminates TLS and the container speaks plain HTTP internally (`DOCKER_PROJECT_PROTOCOL=https` + `DOCKER_SERVICE_PROTOCOL=http`).

See [HTTP vs. HTTPS](./common.md#http-vs-https) in the shared documentation for both scenarios and the gateway patterns.

### Customizing NGINX with Intelligent Snippets

This image uses a flexible system for extending the base NGINX configuration. You can add any number of custom configuration files, and the container's entrypoint script will intelligently process and include them based on their name and your environment variables.

You can learn more about this powerful feature in [Advanced Customization](#advanced-customization-templating-and-overrides), especially in the [Adding Custom NGINX Snippets](#1-adding-custom-nginx-snippets-marker-aware-templates) section.

## Utility Commands

The following helper commands are available inside every container at runtime.

### `reload-supervisor`

`reload-supervisor` applies changed configs without a container restart.

See [Utility Commands](./common.md#utility-commands) in the shared documentation.

## Advanced Customization: Templating and Overrides

This image uses a powerful templating engine that processes **all internal configuration files** on startup. This allows for deep customization of NGINX, Supervisor, and other components without rebuilding the image.

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
  proxy:
    image: neunerlei/nginx:latest
    volumes:
      # Mount custom directory containing nginx/ subdirectory
      - ./docker/custom:/container/custom
```

**Directory structure:**

```
docker/custom/
└── nginx/
    ├── 01-custom-headers.conf
    ├── 02-rate-limiting.prod.conf
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

##### 1.2 Per-Service Snippets (Proxy Mode Only) `MARKER-AWARE` `TEMPLATES`

If you are using the container as proxy (`CONTAINER_MODE` = `proxy`), this feature allows you to add custom rules *inside* the `location` block of a specific proxied service. This is ideal for things like per-route caching, rate-limiting, or custom headers.

* **How:** Inside your custom directory, create a `nginx/proxy/` sub-directory. Then create a new `.conf` file starting with the **lowercase version of your proxy key**, followed by a `.` and any name you like — the dot is the key boundary, so keys sharing a prefix (e.g. `api` and `api_v2`) do not include each other's snippets. For a service defined with `PROXY_API_CONTAINER`, the filename could be `api.cache.conf`. Your name can include markers like: `api.prod-or-env-staging.https.conf`. Snippets named exactly `api.conf` (without a purpose part) keep working for backward compatibility, but the dotted form is the recommended convention.
* **Result:** All files following that schema will be included within the `location` block for the `API` service (if the marker conditions are met).

**Directory structure:**

```
docker/custom/
└── nginx/
    └── proxy/
        ├── api.cache.conf
        ├── frontend.prod.conf
        └── backend.https.conf
```

**Example:**

```nginx
# docker/custom/nginx/proxy/api.cache.conf
# Custom caching for the API service
proxy_cache_valid 200 10m;
proxy_cache_key "$scheme$request_method$host$request_uri";
```

##### 1.3 Root Location Snippets (Static Mode Only) `MARKER-AWARE` `TEMPLATES`

When running in `static` mode, you can add custom snippets directly to the root location block. This is useful for SPAs that require specific routing rules or custom headers.

**Note:** You cannot override the `try_files` directive from here. Use the `NGINX_TRY_FILES` environment variable instead.

**Directory structure:**

```
docker/custom/
└── nginx/
    └── location/
        ├── 01-custom-headers.conf
        └── 02-custom-rewrites.conf
```

**Example:**

```nginx
# docker/custom/nginx/location/01-custom-headers.conf
add_header X-Frame-Options "SAMEORIGIN";
```

> For basic authentication, prefer the `NGINX_BASIC_AUTH` environment variable — it creates and maintains the password file for you. See [Basic Authentication](#basic-authentication).

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
│       │   ├── proxy/
│       │   │   └── api.cache.conf
│       │   ├── 01-custom-location.conf
│       │   ├── errorPage.html
│       │   └── errorPage.json
│       ├── certs/
│       │   ├── cert.pem
│       │   └── key.pem
│       └── entrypoint/
│           └── 01-setup.sh
└── ... (your application services)
```

```yaml
# docker-compose.yml
services:
  proxy:
    image: neunerlei/nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./docker/custom:/container/custom  # Single mount for all customizations
    environment:
      - ENVIRONMENT=production
      - DOCKER_PROJECT_PROTOCOL=https
      - DOCKER_SERVICE_PROTOCOL=http
      - PROXY_API_CONTAINER=backend-app
      - PROXY_API_PATH=/api
```

### Migration from Legacy Mount Points

Legacy mount points (`/etc/ssl/certs`, `/etc/container/templates/...`) abort the startup with migration instructions.

See [Migration from Legacy Mount Points](./common.md#migration-from-legacy-mount-points) in the shared documentation for the full explanation.

## Default index.html

If you run the image in `static` mode without mounting any files to `/var/www/html/public`, it will serve a default `index.html` page. Simply override this file with your own content by mounting your static files to that path.

## The Shell Environment and the Bash Wrapper

`/bin/bash` (and `/bin/sh`) source `/container/work/container-vars.sh` first, so entrypoint-exported variables are available in `docker exec` sessions. These container values take precedence over variables passed inline or via `docker exec -e`.

See [The Shell Environment and the Bash Wrapper](./common.md#the-shell-environment-and-the-bash-wrapper) in the shared documentation for the full explanation.