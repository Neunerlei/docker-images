# PHP Images (>= 8.4)

Welcome to the new generation of `neunerlei/php-nginx` images!

Starting with PHP 8.4, these images are designed as self-contained, high-performance services. The philosophy has shifted from providing only PHP-FPM to providing a complete, production-ready PHP application runtime that includes a pre-configured NGINX web server.

Think of this image as a "service-in-a-box". You put your code in, configure it with environment variables, and it just works—whether in local development or behind a production reverse proxy.

For older PHP versions (<= 8.4) without NGINX, please refer to the [legacy PHP documentation](legacy.md).

## Quick Start

The quickest way to get started is with a `docker-compose.yml` file. This example runs your application in "web" mode, mounts your code, and exposes it on port 8080.

```yaml
# docker-compose.yml
version: '3.8'

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
| **PROJECT**                       |                                                                                                                     |                           |
| `DOCKER_PROJECT_HOST`             | The hostname your application (for the application URL generation, etc.).                                           | `localhost`               |
| `DOCKER_PROJECT_PATH`             | The web root when accessing the pages. For example, if your app is at `http://example.com/app`, set this to `/app`. | `/`                       |
| `DOCKER_PROJECT_PROTOCOL`         | Can be either `http` or `https`, to determine how nginx should listen for connections.                              | `"false"`                 |
| **NGINX**                         |                                                                                                                     |                           |
| `NGINX_CLIENT_MAX_BODY_SIZE`      | Overrides `client_max_body_size` in NGINX.                                                                          | Matches `MAX_UPLOAD_SIZE` |
| `NGINX_KEY_PATH`                  | Path to the SSL key file (only used if `DOCKER_PROJECT_PROTOCOL="https"`).                                          | `/var/www/certs/key.pem`  |
| `NGINX_CERT_PATH`                 | Path to the SSL certificate file (only used if `DOCKER_PROJECT_PROTOCOL="https"`).                                  | `/var/www/certs/cert.pem` |
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

## Web Mode In-Depth

In the default `web` mode, the entrypoint script dynamically generates the NGINX configuration.

### HTTP vs. HTTPS

The image supports a convenient way to run SSL locally using tools like `mkcert`.

* **By default (`DOCKER_PROJECT_PROTOCOL="https"` op missing `DOCKER_PROJECT_PROTOCOL`):** NGINX is configured to listen for plain HTTP on port 80.
* **When `DOCKER_PROJECT_PROTOCOL="http"`:** NGINX is configured to listen on port 443 with SSL, using certificates it expects to find at `/var/www/certs/cert.pem` and `/var/www/certs/key.pem`. It also sets up an automatic redirect from HTTP (port 80) to HTTPS. You can mount your certificates to this path. You can use this setup in local development to simulate HTTPS; but the general setup is also suitable for production if you provide valid certificates. You can learn more about customizing SSL in the next section.

### Customizing NGINX with Snippets

This image is designed to be extensible without being modified. The NGINX configuration includes two "hook" directories:

* `/etc/nginx/snippets/before.d/`
* `/etc/nginx/snippets/after.d/`

Any `.conf` file you place in these directories will be included at the beginning or end of the main server logic, respectively. This is the perfect way to add custom headers, caching rules, or other specific directives. `before.d` is included before the main location blocks, while `after.d` is included at the end of the server block.

**Example: Adding a custom security header**

1. Create a file, e.g., `my-headers.conf`:
   ```nginx
   # my-headers.conf
   add_header X-My-Custom-Header "Hello from my project!";
   ```
2. Mount this file into the `before.d` directory in your `docker-compose.yml`:
   ```yaml
   services:
     app:
       image: neunerlei/php-nginx:8.5
       volumes:
         - ./your-code:/var/www/html
         # Mount the custom snippet
         - ./my-headers.conf:/etc/nginx/snippets/before.d/headers.conf
   ```

NGINX will now automatically include this header in its responses.

> When you are building your own derived images, you can also COPY files into these directories.

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
