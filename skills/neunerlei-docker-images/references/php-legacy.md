# `neunerlei/php` — Legacy PHP Images (≤ 8.4, FPM-only)

> **DEPRECATED.** True only for PHP ≤ 8.4 WITHOUT nginx. Newer images (PHP ≥ 8.2) bundle NGINX — see [php-nginx.md](php-nginx.md). Use those instead.

## Background

Originally PHP-FPM only, no web server — a separate Nginx/Apache container was always required. Based on Alpine first, later switched to Debian (stability/security/compatibility over size). Deprecated with PHP 8.4.

## Tags

Repository `neunerlei/php`, two variants:
- `fpm-alpine`: `https://docker.neunerlei.eu/neunerlei-php-fpm-alpine-tags.html`
- `fpm-debian`: `https://docker.neunerlei.eu/neunerlei-php-fpm-debian-tags.html`

## What's inside

- PHP-FPM with common extensions (apcu, bcmath, gd, intl, opcache, pdo_mysql, …)
- Supervisor managing the FPM process (no daemon mode, logs to stderr)
- `php.common.ini`: timezone UTC, memory limit 1024M, OPcache optimized, APCu enabled for CLI, realpath cache 4096K / TTL 600
- `php.prod.ini`: display errors off, error reporting `E_ALL & ~E_DEPRECATED & ~E_STRICT`, expose PHP off
- `fpm-pool.conf`: listen `127.0.0.1:9000`, user/group www-data, dynamic pm (max children 20, start 2, spare 1–4), status path `/fpm-status`

## Legacy entrypoint extension

Pre-dates `/container/custom`. Derived images/mounts can add an optional script executed before the main entrypoint logic:

```dockerfile
FROM neunerlei/php:8.4-fpm-debian
COPY my-entrypoint.local.sh /usr/local/bin/entrypoint.local.sh
```

or mount it:

```bash
docker run -d -p 9000:9000 \
  -v /path/to/my-entrypoint.local.sh:/usr/local/bin/entrypoint.local.sh \
  neunerlei/php:8.4-fpm-debian
```

```bash
#!/bin/bash
echo "Running custom startup commands..."
# set env vars, initialize services, ...
```

Do NOT use this pattern on current images — use `/container/custom/entrypoint/` hooks there.
