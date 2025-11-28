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
      - PROXY_FRONTEND_CONTAINER=node-app
      - PROXY_FRONTEND_PATH=/
      - PROXY_FRONTEND_PORT=8000
      - PROXY_FRONTEND_PROTOCOL=https # By default, this is http, but you can set it to https if you want

      # PHP backend on a sub-path, rewrite url to its root
      - PROXY_BACKEND_CONTAINER=php-app
      - PROXY_BACKEND_PATH=/api
      - PROXY_BACKEND_DEST=/ # Route /api to the root of the php-app

  # 2. Your Application Services
  node-app:
    image: node:24-alpine
    # ... your node app service definition ...

  php-app:
    image: neunerlei/php:8.5-fpm-nginx-debian
    # ... your php app service definition ...
```

Run `docker-compose up`, and the proxy will automatically:

* Route requests to `http://localhost/` to the `node-app` on its internal port 8000.
* Route requests to `http://localhost/api/users` to the `php-app`, sending the request as `/users`.

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, it automatically detects its operating mode and configures NGINX accordingly.

1. **Proxy Mode:** This is the main mode. If the script detects any `PROXY_*_CONTAINER` environment variables, it scans all of them and builds a sophisticated reverse proxy configuration.
2. **Static Mode:** If no `PROXY_*` variables are found, the image gracefully falls back to being a simple web server, serving static files from `/var/www/html/public`. This makes it useful for simple landing pages or maintenance modes.

## Configuration via Environment Variables

The proxy is configured almost entirely through declarative environment variables.

| Variable                     | Description                                                                                                                                                                                          | Default Value                       |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------|
| **General**                  |                                                                                                                                                                                                      |                                     |
| `CONTAINER_MODE`             | Read-only. Automatically set to `proxy` or `static`.                                                                                                                                                 | `static`                            |
| `MAX_UPLOAD_SIZE`            | A convenient variable to set the global `client_max_body_size`. This applies only if in "proxy" mode, as all uploads need to pass through the proxy.                                                 | `100M`                              |
| **Project**                  |                                                                                                                                                                                                      |                                     |
| `DOCKER_PROJECT_HOST`        | The hostname for your project (used for logging and headers).                                                                                                                                        | `localhost`                         |
| `DOCKER_PROJECT_PATH`        | A global path prefix for the entire project. If set to `/my-project`, all service paths will be prefixed with it. This allows you to host the entire application stack under a common sub-directory. | `/`                                 |
| `DOCKER_PROJECT_PROTOCOL`    | Can be `http` or `https`. Determines if NGINX should listen for HTTP or HTTPS.                                                                                                                       | `http`                              |
| `DOCKER_SERVICE_PROTOCOL`    | When running behind a proxy, your service might run on a different protocol than the public one. If omitted, it defaults to the value of `DOCKER_PROJECT_PROTOCOL`.                                  | (matches `DOCKER_PROJECT_PROTOCOL`) |
| `DOCKER_SERVICE_PATH`        | When running behind a proxy, the `DOCKER_PROJECT_PATH` is expected to be the public path of the proxy. Your service might run on a "sub-path" of that path. If omitted, it defaults to `/`.          | `/`                                 |
| `DOCKER_SERVICE_ABS_PATH`    | This combines `DOCKER_PROJECT_PATH` and `DOCKER_SERVICE_PATH` into an absolute path.                                                                                                                 | (derived value)                     |
| **NGINX**                    |                                                                                                                                                                                                      |                                     |
| `NGINX_CLIENT_MAX_BODY_SIZE` | Overrides `client_max_body_size`.                                                                                                                                                                    | Matches `MAX_UPLOAD_SIZE`           |
| `NGINX_DOC_ROOT`             | The document root NGINX serves static files from.                                                                                                                                                    | `/var/www/html/public`              |
| `NGINX_KEY_PATH`             | Path to the SSL key file (only used if `DOCKER_PROJECT_PROTOCOL="https"`).                                                                                                                           | `/etc/ssl/key.pem`                  |
| `NGINX_CERT_PATH`            | Path to the SSL certificate file (only used if `DOCKER_PROJECT_PROTOCOL="https"`).                                                                                                                   | `/etc/ssl/cert.pem`                 |

## Proxy Mode In-Depth

In `proxy` mode, the entrypoint generates a unique `location` block for each service key it finds.

### Proxy Service Configuration Variables

For each service you want to proxy, you define a group of variables with a unique key (e.g., `FRONTEND`, `BACKEND`, `API_V2`).

| Variable Pattern        | Description                                                                                                                                                                  |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `PROXY_<KEY>_CONTAINER` | **(Required)** The hostname of the backend service (usually the Docker Compose service name).                                                                                |
| `PROXY_<KEY>_PATH`      | The path for this service, **relative to `DOCKER_PROJECT_PATH`**. For example, if `DOCKER_PROJECT_PATH` is `/app` and this is `/api`, the final location will be `/app/api`. |
| `PROXY_<KEY>_PORT`      | **(Optional)** The internal port the backend service is listening on. Default is `80`.                                                                                       |
| `PROXY_<KEY>_DEST`      | **(Optional)** Rewrites the request path. For example, `PROXY_BACKEND_PATH=/api` and `PROXY_BACKEND_DEST=/` will route `/api/users` to `/users` on the backend container.    |
| `PROXY_<KEY>_PROTOCOL`  | **(Optional)** The protocol for this service. Default is `http`.                                                                                                             |
### **Project Base Path in Proxy Mode**

You can serve the entire proxied application from a sub-directory using `DOCKER_PROJECT_PATH`.

*   **Public URL goal:** `https://example.com/my-project/` should go to the `frontend` container, and `https://example.com/my-project/api/` to the `backend`.
*   **Configuration:**
    ```yaml
    environment:
      - DOCKER_PROJECT_PATH=/my-project
      - PROXY_FRONTEND_CONTAINER=frontend
      - PROXY_FRONTEND_PATH=/
      - PROXY_API_CONTAINER=backend
      - PROXY_API_PATH=/api
    ```
*   **Result:** The proxy automatically combines the project path and the service path for routing.

## **Static Mode In-Depth**

If no `PROXY_*` variables are found, the image runs as a high-performance web server for static files. This is perfect for serving a SPA (Single-Page Application), documentation, or a simple maintenance page.

### **Static Mode Configuration Variables**

In this mode, the image behaves like one of your application services (`node-nginx`, `php-nginx`) and can be placed behind another proxy.

| Variable                  | Description                                                                    | Default Value          |
|---------------------------|--------------------------------------------------------------------------------|------------------------|
| `NGINX_DOC_ROOT`          | The document root for static files.                                            | `/var/www/html/public` |
| `DOCKER_PROJECT_PATH`     | The base path for the entire project this service belongs to.                  | `/`                    |
| `DOCKER_SERVICE_PATH`     | The unique sub-path for this static server.                                    | `/`                    |
| `DOCKER_SERVICE_ABS_PATH` | Read-only. The derived absolute path (`PROJECT_PATH` + `SERVICE_PATH`).        | (derived value)        |
| `DOCKER_SERVICE_PROTOCOL` | The protocol this service uses internally (usually `http`).                    | (matches `PROJECT`)    |

### **Path Composition: `PROJECT_PATH` + `SERVICE_PATH`**

When running this image in `static` mode as part of a larger project, you need a way to manage its URL path. This image handles this by composing the final public URL path from two separate variables.

A reverse proxy sits between your users and your services, directing traffic to the right place based on the URL path.

*   `DOCKER_PROJECT_PATH`: The **base path** for the entire group of related services. If your whole application is served from `https://example.com/myapp/`, then this value would be `/myapp/`.
*   `DOCKER_SERVICE_PATH`: The unique **sub-path** for a specific service within that project. For an API service, this might be `/api/`.
*   `DOCKER_SERVICE_ABS_PATH`: This read-only variable is automatically created by combining the two: `DOCKER_PROJECT_PATH` + `DOCKER_SERVICE_PATH`. Your application can use this to reliably generate correct absolute URLs.

Your reverse proxy uses `DOCKER_SERVICE_PATH` for routing, while your application uses `DOCKER_SERVICE_ABS_PATH` for its internal logic.

---

#### Scenario 1: A Single App on a Domain Root

Your app runs at the root of a domain. This is the simplest case.

*   **Public URL:** `https://my-app.com/`
*   **Environment:**
    *   `DOCKER_PROJECT_PATH: /`
    *   `DOCKER_SERVICE_PATH: /` (or unset, as it defaults to `/`)
*   **Resulting Path:**
    *   `DOCKER_SERVICE_ABS_PATH` will be `/`.

---

#### Scenario 2: Frontend and Backend on the Same Domain

You have a frontend service at the root and a backend API service under `/api/`. A reverse proxy routes traffic.

*   **Public URLs:**
    *   Frontend: `https://my-app.com/`
    *   Backend: `https://my-app.com/api/`

**Frontend Service Configuration:**
*   `DOCKER_PROJECT_PATH: /`
*   `DOCKER_SERVICE_PATH: /`
*   **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/`.

**Backend Service Configuration:**
*   `DOCKER_PROJECT_PATH: /`
*   `DOCKER_SERVICE_PATH: /api/`
*   **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/api/`. The backend can now correctly generate links like `/api/users/123`.

---

#### Scenario 3: An Entire Project Deployed on a Sub-Path

Your entire project, including a frontend and backend, must live under a specific path on a shared server.

*   **Public URLs:**
    *   Frontend: `https://shared.server.com/project-alpha/`
    *   Backend: `https://shared.server.com/project-alpha/api/`

**Frontend Service Configuration:**
*   `DOCKER_PROJECT_PATH: /project-alpha/`
*   `DOCKER_SERVICE_PATH: /`
*   **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/project-alpha/`.

**Backend Service Configuration:**
*   `DOCKER_PROJECT_PATH: /project-alpha/`
*   `DOCKER_SERVICE_PATH: /api/`
*   **Resulting Path:** `DOCKER_SERVICE_ABS_PATH` is `/project-alpha/api/`.

## Customizing NGINX with Snippets

This image is designed to be extensible. The NGINX configuration includes several "hook" directories for placing custom `.conf` files.

* `/etc/nginx/snippets/before.d/`: Included at the beginning of the `server` block. Good for `map` directives or other server-level settings.
* `/etc/nginx/snippets/after.d/`: Included at the end of the `server` block. Good for general `location` blocks (e.g., for `/robots.txt`).
* `/etc/nginx/snippets/proxy.d/${KEY}-*.conf`: A location-specific hook! Files placed here will be included *inside* the `location` block for that specific service. This is perfect for adding custom headers or caching rules for a single backend.

**Example: Adding a custom header to a single backend**

1. Create a file, e.g., `my-api-header.conf`:
   ```nginx
   # my-api-header.conf
   add_header X-API-Version "2.1" always;
   ```
2. Mount this file into the `proxy.d` directory in your `docker-compose.yml`, naming it with the service key:
   ```yaml
   services:
     proxy:
       image: neunerlei/nginx:latest
       environment:
         - PROXY_API_CONTAINER=my-api-service
         - PROXY_API_PATH=/api
       volumes:
         # Mount the custom snippet, using the key "API"
         - ./my-api-header.conf:/etc/nginx/snippets/proxy.d/API-headers.conf
   ```

The `X-API-Version` header will now only be added to requests sent to the `/api` backend.


## HTTP vs. HTTPS

The image supports a convenient way to run SSL locally using tools like `mkcert`.

* **By default (`DOCKER_PROJECT_PROTOCOL="http"`):** NGINX is configured to listen for plain HTTP on port 80.
* **When `DOCKER_PROJECT_PROTOCOL="https"`:** NGINX is configured to listen on port 443 with SSL, using certificates it expects to find at the paths defined by `NGINX_CERT_PATH` and `NGINX_KEY_PATH`. It also sets up an automatic redirect from HTTP (port 80) to HTTPS. You can mount your certificates to this path. This setup is also suitable for production if you provide valid certificates.

### SSL Customization

When the container is configured to run in HTTPS mode, it expects to find the SSL certificate and key at `/var/www/certs/cert.pem` and `/var/www/certs/key.pem`. You can mount your own certificates to this path. Additionally, to the config options described above, you have additional hooks that only apply when HTTPS is enabled:

* `/etc/nginx/snippets/before.https.d/`
* `/etc/nginx/snippets/after.https.d/`

Any `.conf` files placed in these directories will be included in the SSL server block, allowing you to customize SSL settings further.
In general, the SSL configuration is included AFTER the main server configuration, so you can override settings as needed. The `before.https`

The order of the hooks is as follows:

1. `/etc/nginx/snippets/before.d/`
2. Set up the main service + locations
3. `/etc/nginx/snippets/before.https.d/`
4. SSL-specific settings, like certificates and hardening
5. `/etc/nginx/snippets/after.https.d/`
6. `/etc/nginx/snippets/after.d/`

#### Variables in nginx.conf

To avoid configuration duplication in your nginx snippets, you can use the following variables that are replaced at runtime:

- `DOCKER_PROJECT_HOST`
- `DOCKER_PROJECT_PROTOCOL`
- `DOCKER_PROJECT_PATH`
- `DOCKER_SERVICE_PROTOCOL`
- `DOCKER_SERVICE_PATH`
- `DOCKER_SERVICE_ABS_PATH`
- `NGINX_DOC_ROOT`

They will be replaced with their respective values when the nginx configuration is generated.
Use them like this:

```nginx
location ^~ ${DOCKER_SERVICE_ABS_PATH}custom/ {
    root ${NGINX_DOC_ROOT};
    index index.html index.htm;
}
```

The replacement will happen in all files that are placed **directly** (not in subdirectories) in:

- `/etc/nginx/snippets/before.d/`
- `/etc/nginx/snippets/after.d/`
- `/etc/nginx/snippets/before.https.d/`
- `/etc/nginx/snippets/after.https.d/`
- `/etc/nginx/snippets/proxy.d/`

## Advanced Customization

Similar to the PHP images, you can hook into the startup process using a custom local script.

* `/usr/bin/app/entrypoint.local.sh`: This script is executed just before the main NGINX process starts. It's a general-purpose hook for any custom setup commands you might need.
