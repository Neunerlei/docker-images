# Documentation for `neunerlei/nginx-proxy`

Welcome to the `neunerlei/nginx` image!

This is not just another NGINX container. It's a smart, self-configuring reverse proxy designed to be the central gateway for your multi-service projects. It acts as the "front door," intelligently routing traffic to your backend services based on simple, declarative environment variables.

Think of this image as an "orchestrator-in-a-box" for your project. You define which services live at which paths, and the proxy automatically builds the correct routing configuration for you.

## Quick Start

The quickest way to get started is with a `docker-compose.yml` file. This example sets up the proxy to route traffic to two backend services: a frontend application at `/` and a backend API at `/api`.

```yaml
# docker-compose.yml
version: '3.8'

services:
  # 1. The Smart Proxy Service
  proxy:
    image: neunerlei/nginx-proxy:latest
    ports:
      - "80:80"   # Expose standard HTTP port
    environment:
      # --- Define the services to proxy to ---

      # Main frontend app on the root path
      - PROXY_FRONTEND_CONTAINER=node-app
      - PROXY_FRONTEND_PATH=/
      - PROXY_FRONTEND_PORT=8000

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

| Variable                     | Description                                                                                                                                                                                          | Default Value               |
|------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------|
| **General**                  |                                                                                                                                                                                                      |                             |
| `CONTAINER_MODE`             | Read-only. Automatically set to `proxy` or `static`.                                                                                                                                                 | `static`                    |
| `MAX_UPLOAD_SIZE`            | A convenient variable to set the global `client_max_body_size`.                                                                                                                                      | `100M`                      |
| **PROJECT**                  |                                                                                                                                                                                                      |                             |
| `DOCKER_PROJECT_HOST`        | The hostname for your project (used for logging and headers).                                                                                                                                        | `localhost`                 |
| `DOCKER_PROJECT_PROTOCOL`    | Set to `https` to enable SSL mode.                                                                                                                                                                   | `http`                      |
| `DOCKER_PROJECT_PATH`        | A global path prefix for the entire project. If set to `/my-project`, all service paths will be prefixed with it. This allows you to host the entire application stack under a common sub-directory. | `/`                         |
| **NGINX**                    |                                                                                                                                                                                                      |                             |
| `NGINX_CLIENT_MAX_BODY_SIZE` | Overrides `client_max_body_size`.                                                                                                                                                                    | Matches `MAX_UPLOAD_SIZE`   |
| `NGINX_KEY_PATH`             | Path to the SSL key file (only used if `DOCKER_PROJECT_PROTOCOL="https"`).                                                                                                                           | `/etc/nginx/certs/key.pem`  |
| `NGINX_CERT_PATH`            | Path to the SSL certificate file (only used if `DOCKER_PROJECT_PROTOCOL="https"`).                                                                                                                   | `/etc/nginx/certs/cert.pem` |

### Proxy Service Configuration

For each service you want to proxy, you define a group of variables with a unique key (e.g., `FRONTEND`, `BACKEND`, `API_V2`).

| Variable Pattern        | Description                                                                                                                                                                  |
|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `PROXY_<KEY>_CONTAINER` | **(Required)** The hostname of the backend service (usually the Docker Compose service name).                                                                                |
| `PROXY_<KEY>_PATH`      | The path for this service, **relative to `DOCKER_PROJECT_PATH`**. For example, if `DOCKER_PROJECT_PATH` is `/app` and this is `/api`, the final location will be `/app/api`. |
| `PROXY_<KEY>_PORT`      | The internal port the backend service is listening on. Default is `80`.                                                                                                      |
| `PROXY_<KEY>_DEST`      | **(Optional)** Rewrites the request path. For example, `PROXY_BACKEND_PATH=/api` and `PROXY_BACKEND_DEST=/` will route `/api/users` to `/users` on the backend container.    |

## Proxy Mode In-Depth

In `proxy` mode, the entrypoint generates a unique `location` block for each service key it finds.

### HTTP vs. HTTPS

The image supports a convenient way to run SSL locally using tools like `mkcert`.

* **By default (`DOCKER_PROJECT_PROTOCOL="http"`):** NGINX is configured to listen for plain HTTP on port 80.
* **When `DOCKER_PROJECT_PROTOCOL="https"`:** NGINX is configured to listen on port 443 with SSL, using certificates it expects to find at the paths defined by `NGINX_CERT_PATH` and `NGINX_KEY_PATH`. It also sets up an automatic redirect from HTTP (port 80) to HTTPS. You can mount your certificates to this path. This setup is also suitable for production if you provide valid certificates.

### Customizing NGINX with Snippets

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
       image: neunerlei/nginx-proxy:latest
       environment:
         - PROXY_API_CONTAINER=my-api-service
         - PROXY_API_PATH=/api
       volumes:
         # Mount the custom snippet, using the key "API"
         - ./my-api-header.conf:/etc/nginx/snippets/proxy.d/API-headers.conf
   ```

The `X-API-Version` header will now only be added to requests sent to the `/api` backend.

#### SSL Customization

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

## Advanced Customization

Similar to the PHP images, you can hook into the startup process using a custom local script.

* `/usr/bin/app/entrypoint.local.sh`: This script is executed just before the main NGINX process starts. It's a general-purpose hook for any custom setup commands you might need.
