# `neunerlei/php-nginx` — PHP-FPM + NGINX (PHP ≥ 8.2)

**TOC:** [Extensions](#extensions) · [Composer](#composer) · [Modes](#modes) · [Variables](#variables-image-specific) · [Env derivation](#environment-app_env--app_debug) · [Customization](#image-specific-customization-containercustom) · [Defaults](#defaults)

PHP application runtime: NGINX + PHP-FPM in one container, Supervisor-managed. For PHP ≤ 8.1 or FPM-only setups see [php-legacy.md](php-legacy.md).

```yaml
services:
  app:
    image: neunerlei/php-nginx:latest
    ports: ["8080:80"]
    volumes:
      - ./your-php-project:/var/www/html   # project with public/index.php
    environment:
      - PHP_MEMORY_LIMIT=2G
      - MAX_UPLOAD_SIZE=250M
```

## Extensions

Beyond the official PHP image: `apcu`, `bcmath`, `bz2`, `ctype`, `curl`, `exif`, `gd`, `iconv`, `intl`, `mbstring`, `mysqli`, `opcache`, `pcntl`, `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `pgsql`, `redis`, `zip`, and `xmlrpc`.

> `xmlrpc` is deprecated and will be removed in the next breaking release. Reinstall manually in derived images: `RUN docker-php-ext-install xmlrpc`.

## Composer

Pre-installed globally. ALWAYS runs as `www-data` — no permission worries. Run as another user via `_composer` (original binary).

## Modes

- **web** (default): NGINX + PHP-FPM serve the app.
- **worker**: set `PHP_WORKER_COMMAND` → NGINX + FPM off, Supervisor runs your command.
- **build**: entrypoint in a Dockerfile `RUN` without a command.

```yaml
my-app-worker:
  image: neunerlei/php-nginx:8.5
  volumes: [./your-laravel-project:/var/www/html]
  restart: unless-stopped
  environment:
    - PHP_WORKER_COMMAND=php /var/www/html/artisan queue:work --tries=3
    - PHP_WORKER_PROCESS_COUNT=4
# "cron": PHP_WORKER_COMMAND=while true; do php my_task.php; sleep 300; done
```

## Variables (image-specific)

| Variable | Default | Purpose |
|---|---|---|
| `APP_ENV` | derived from `ENVIRONMENT` | Framework env (Symfony/Laravel/CakePHP); explicit wins. |
| `APP_DEBUG` | derived | `1` in dev, or prod with `PHP_PROD_DEBUG=true`; explicit wins. |
| `PHP_MEMORY_LIMIT` | `1024M` | PHP `memory_limit`. |
| `PHP_TIMEZONE` | `UTC` (via `TZ`) | `date()` default timezone. |
| `PHP_UPLOAD_MAX_FILESIZE` / `PHP_POST_MAX_SIZE` | = `MAX_UPLOAD_SIZE` | Prefer `MAX_UPLOAD_SIZE` — it sets body size + both PHP limits at once. |
| `PHP_PROD_DISPLAY_ERRORS` | `Off` | Prod `display_errors`. |
| `PHP_PROD_DISPLAY_STARTUP_ERRORS` | `Off` | Prod `display_startup_errors`. |
| `PHP_PROD_ERROR_REPORTING` | `E_ALL & ~E_DEPRECATED & ~E_STRICT` | Prod `error_reporting`. |
| `PHP_PROD_OPCACHE_VALIDATE_TIMESTAMPS` | `0` | Prod opcache revalidation; `0` = code changes need a restart. |
| `PHP_PROD_DEBUG` | `false` | `true` relaxes all `PHP_PROD_*` for debugging (see below). |
| `PHP_WORKER_COMMAND` | (unset) | **Setting this enables worker mode.** |
| `PHP_WORKER_PROCESS_COUNT` | `1` | Supervisor `numprocs`. |
| `PHP_WORKER_STOP_WAIT_SECS` | `10` | Supervisor `stopwaitsecs`; needs `stop_grace_period` above it. |
| `PHP_FPM_MAX_CHILDREN` | `20` | `pm.max_children`. |
| `PHP_FPM_START_SERVERS` | `2` | `pm.start_servers`. |
| `PHP_FPM_MIN_SPARE_SERVERS` | `1` | `pm.min_spare_servers`. |
| `PHP_FPM_MAX_SPARE_SERVERS` | `4` | `pm.max_spare_servers`. |
| `PHP_FPM_MAX_REQUESTS` | `500` | `pm.max_requests`. |
| `NGINX_TRY_FILES` | `$uri $uri/ /index.php$is_args$args` | Root-location routing into `index.php`. |

NGINX timeout vars map to FastCGI: `NGINX_PROXY_CONNECT_TIMEOUT` → `fastcgi_connect_timeout`, `NGINX_PROXY_READ_TIMEOUT` → `fastcgi_send_timeout`, `NGINX_PROXY_SEND_TIMEOUT` → `fastcgi_read_timeout`.

## ENVIRONMENT, `APP_ENV` & `APP_DEBUG`

- `APP_ENV`: `dev` when `ENVIRONMENT` is dev, else `prod`. Explicit wins → `ENVIRONMENT=production` + `APP_ENV=staging` is valid.
- `APP_DEBUG`: `1` if `ENVIRONMENT` dev; or prod **and** `PHP_PROD_DEBUG=true`; or `APP_ENV` dev. Else `0`. Explicit wins.

**`PHP_PROD_DEBUG=true`** keeps prod optimizations but relaxes debugging: `display_errors=On`, `display_startup_errors=On`, `error_reporting=E_ALL & ~E_DEPRECATED`, `opcache.validate_timestamps=1` (no restart needed for code changes). Reflected in the `PHP_PROD_*` vars.

## Image-specific customization (`/container/custom`)

Shared dirs plus:

| Dir | Loaded as | Notes |
|---|---|---|
| `php/*.ini` | `php.ini` snippets | Prefix `z-` to load after defaults (`x.php.ini`, `x.php.prod.ini`) and override them. |
| `php/fpm/*.conf` | FPM pool snippets | Defaults load as `www.conf`; prefix `z-`. |
| `nginx/` | Server block | → `/etc/nginx/snippets/service.d/`. |
| `nginx/global/` | `http` block | |
| `nginx/location/` | Root `location /` block | Cannot override `try_files` (use `NGINX_TRY_FILES`). |

```ini
; php/z-custom-settings.ini — full template syntax available
max_execution_time = ${PHP_MAX_EXECUTION_TIME}
default_socket_timeout = 300
```

## Defaults

- `index.php` at `/var/www/html/public/index.php`: welcome page; full `phpinfo()` in dev. Replace by mounting your project.
- PHP CLI wrapped like bash (`/usr/local/bin/php` → wrapper, `_php` = original) so `docker exec ... php` sees entrypoint vars.

## Build mode

```dockerfile
FROM neunerlei/php-nginx:latest AS test
ARG DOCKER_PROJECT_HOST
ENV DOCKER_PROJECT_HOST=${DOCKER_PROJECT_HOST}
COPY --chown=www-data:www-data ./composer*.json ./
COPY --chown=www-data:www-data ./src ./src
RUN /container/entrypoint/entrypoint.sh
RUN composer install --no-dev --optimize-autoloader
RUN ./vendor/bin/phpunit
```
