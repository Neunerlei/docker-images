# Node.js Images - with NGINX

Welcome to the `node-nginx` images!

These images are designed as self-contained, high-performance services. The philosophy is to provide a complete, production-ready Node.js application runtime that includes a pre-configured NGINX web server as a reverse proxy.

Think of this image as a "service-in-a-box." You put your code in, configure it with environment variables, and it just works—whether in local development or behind a production load balancer.

## Tags

Here you can find [all available tags](https://docker.neunerlei.eu/neunerlei-node-nginx-tags.html) of this image.

## Quick Start

The quickest way to get started is with a `docker-compose.yml` file. This example runs your application in "web" mode, mounts your code, and exposes it on port 8080.

```yaml
# docker-compose.yml
services:
  app:
    image: neunerlei/node-nginx:latest # Or your desired version
    ports:
      - "8080:80"
    volumes:
      - ./your-node-project:/var/www/html
    environment:
      # In development, this shows a helpful page with env vars
      - APP_ENV=dev
      # Optional: Set a larger upload size for NGINX
      - MAX_UPLOAD_SIZE=250M
```

Place your Node.js project in the `./your-node-project` directory, ensure your main server file is at `/var/www/html/server.js` (or adjust `NODE_WEB_COMMAND`), and run `docker-compose up`. You can now access your application at `http://localhost:8080`.

## Core Concepts: The Smart Entrypoint

The "brain" of this image is its entrypoint script. When the container starts, this script reads your environment variables to decide how to configure itself. It operates in one of two primary modes:

1. **Web Mode (Default):** This is the standard mode. The script starts and configures both NGINX (as a reverse proxy) and your Node.js application to serve traffic over HTTP.
2. **Worker Mode:** Activated by setting the `NODE_WORKER_COMMAND` variable. In this mode, NGINX is disabled, and Supervisor is configured to run your specified command instead. This is perfect for running queue workers, schedulers, or other long-running background tasks.

## Configuration via Environment Variables

This image is configured almost entirely through environment variables. This allows you to use the same image for different purposes (web vs. worker, dev vs. prod) without rebuilding it.

| Variable                     | Description                                                                                    | Default Value                  |
|:-----------------------------|:-----------------------------------------------------------------------------------------------|:-------------------------------|
| **General**                  |                                                                                                |                                |
| `PUID`                       | The user ID to run processes as (`www-data`). Useful for matching host file permissions.       | `33`                           |
| `PGID`                       | The group ID to run processes as (`www-data`). Useful for matching host file permissions.      | `33`                           |
| `CONTAINER_MODE`             | Read-only. Automatically set to `web` or `worker`.                                             | `web`                          |
| `MAX_UPLOAD_SIZE`            | A convenient variable to set NGINX's `client_max_body_size`.                                   | `100M`                         |
| `APP_ENV`                    | Can be `dev` or `prod`. Used to set `NODE_ENV` if `NODE_ENV` is not already set.               | `prod`                         |
| `NODE_ENV`                   | The standard Node.js environment variable. Takes precedence over `APP_ENV`.                    | (derived from `APP_ENV`)       |
| **Project**                  |                                                                                                |                                |
| `DOCKER_PROJECT_HOST`        | The hostname for your application (not actively used by the image but available for your app). | `localhost`                    |
| `DOCKER_PROJECT_PATH`        | The web root (not actively used by the image but available for your app).                      | `/`                            |
| `DOCKER_PROJECT_PROTOCOL`    | Can be `http` or `https`. Determines if NGINX should listen for HTTP or HTTPS.                 | `http`                         |
| **NGINX**                    |                                                                                                |                                |
| `NGINX_DOC_ROOT`             | The document root NGINX serves static files from.                                              | `/var/www/html/public`         |
| `NGINX_CLIENT_MAX_BODY_SIZE` | Overrides `client_max_body_size` in NGINX.                                                     | Matches `MAX_UPLOAD_SIZE`      |
| `NGINX_CERT_PATH`            | Path to the SSL certificate file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                  | `/etc/ssl/certs/key.pem`       |
| `NGINX_KEY_PATH`             | Path to the SSL key file (used if `DOCKER_PROJECT_PROTOCOL="https"`).                          | `/etc/ssl/certs/cert.pem`      |
| **Node.js Web Mode**         |                                                                                                |                                |
| `NODE_WEB_COMMAND`           | The command to start your web server application.                                              | `node /var/www/html/server.js` |
| `NODE_SERVICE_PORT`          | The port your Node.js application listens on internally for NGINX to proxy to.                 | `3000`                         |
| **Node.js Worker Mode**      |                                                                                                |                                |
| `NODE_WORKER_COMMAND`        | The command to execute in worker mode. **Setting this enables worker mode.**                   |                                |
| `NODE_WORKER_PROCESS_COUNT`  | The number of worker processes to run (`numprocs` in Supervisor).                              | `1`                            |

### A Note on `NODE_ENV`

The entrypoint script includes a small convenience for setting `NODE_ENV`. If `NODE_ENV` is not set, it will be derived from `APP_ENV`:

* If `APP_ENV` is `prod` or `production`, `NODE_ENV` becomes `production`.
* If `APP_ENV` is `dev` or `development`, `NODE_ENV` becomes `development`.
* Otherwise, `NODE_ENV` is set to the value of `APP_ENV`.

If you set `NODE_ENV` directly, its value will always be respected.

## Web Mode In-Depth

In the default `web` mode, the entrypoint script dynamically generates the NGINX configuration to act as a reverse proxy for your Node.js application.

### HTTP vs. HTTPS

The image supports a simple way to enable SSL. This is fundamental for modern web applications and NGINX handles this process, known as SSL Termination, very efficiently [docs.nginx.com](https://docs.nginx.com/nginx/admin-guide/security-controls/terminating-ssl-http/).

* **By default (`DOCKER_PROJECT_PROTOCOL="http"`):** NGINX listens for plain HTTP on port 80.
* **When `DOCKER_PROJECT_PROTOCOL="https"`:** NGINX is configured to listen on port 443 with SSL, using certificates it expects to find at the paths specified by `NGINX_CERT_PATH` and `NGINX_KEY_PATH`. It also sets up an automatic redirect from HTTP (port 80) to HTTPS. You must mount your certificates to these paths.

This setup is great for local development with tools like `mkcert` or for production if you provide valid certificates.

> For a more automated approach to SSL, especially in production with Let's Encrypt certificates, you might consider a dedicated reverse proxy gateway like [linuxserver.io/swag](https://docs.linuxserver.io/images/docker-swag/) in front of this container (running in plain HTTP mode). Another good alternative is [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) with the [acme-companion](https://github.com/nginx-proxy/acme-companion).
> This allows you to centralize SSL management and offload that responsibility from your application containers.

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
           image: your-repo/node-nginx:latest
           volumes:
               - ./your-node-project:/var/www/html
               # Mount the custom snippet
               - ./my-headers.conf:/etc/nginx/snippets/before.d/headers.conf
   ```

NGINX will now automatically include this header in its responses.

> When you are building your own derived images, you can also `COPY` files into these directories.

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

## Worker Mode In-Depth

If you provide the `NODE_WORKER_COMMAND` environment variable, the image switches to worker mode. This is the idiomatic way to run background tasks using the exact same Node.js environment as your web application.

**Example 1: Running a background processing script**

```yaml
services:
  my-app-worker:
    image: neunerlei/node-nginx:latest
    volumes:
      - ./your-node-project:/var/www/html
    environment:
      # This enables worker mode and defines the command
      - NODE_WORKER_COMMAND=node /var/www/html/dist/queue-worker.js
      # Optional: run 4 worker processes
      - NODE_WORKER_PROCESS_COUNT=4
```

**Example 2: Running a "cron" task**

For simple scheduled tasks without a full cron daemon, you can use a loop managed by Supervisor.

```yaml
services:
  my-app-scheduler:
    image: neunerlei/node-nginx:latest
    volumes:
      - ./your-node-project:/var/www/html
    environment:
      # This simple loop will be managed and kept alive by Supervisor
      - NODE_WORKER_COMMAND=while true; do node /var/www/html/my_task.js; sleep 300; done
```

## Advanced Customization

The entrypoint provides two script hooks for advanced customization.

* `/usr/bin/app/entrypoint.user-setup.sh`: This script is executed early in the startup process if `PUID` or `PGID` are set. It's the ideal place to handle run-time user mapping for local development to solve file permission issues.
* `/usr/bin/app/entrypoint.local.sh`: This script is executed just before the main command (`supervisord`). It's a general-purpose hook for any other custom setup commands you might need.

### Default Script (`server.js`)

To get you started quickly, the image includes a simple `server.js` file at `/var/www/html/server.js`. This file starts a basic web server that displays a welcome message and, if `NODE_ENV` is `development`, a list of environment variables.

You can replace this file with your own application code by mounting your project into `/var/www/html`. NGINX is configured to serve static files from `/var/www/html/public` first, and if a file is not found, it will proxy the request to your Node.js application.
