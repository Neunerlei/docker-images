# Legacy PHP images (<= PHP 8.4)

> **DEPRECATION NOTICE**
>
> Everything you read below, is ONLY true for PHP versions **8.4 and below WITHOUT nginx**
> The newer images (from PHP 8.2 onwards) include nginx by default and are described in the [PHP-NGINX documentation](php-nginx.md).

## A brief history

Originally the images would only contain PHP-FPM itself without any web server. This made it necessary to always run a separate web server container (e.g., Nginx or Apache) alongside the PHP-FPM container to serve PHP applications. However, this setup can be cumbersome for simple use cases or development environments.

Also, the PHP images were originally based on Alpine Linux to keep them as small as possible. But over time, it became clear that for production use, stability, security, and compatibility are more important than having the smallest possible image size. Therefore, the images were switched to Debian as the base OS.

We officially deprecated these legacy PHP-FPM-only images with PHP 8.4 and recommend using the newer [PHP-NGINX images](php-nginx.md) instead, which include both PHP and NGINX in a single container for easier setup and use.

## Tags

Here you can find [all available tags](https://docker.neunerlei.eu/neunerlei-php-tags.html) of this image.

## Structure

Each image includes:

- PHP FPM with common extensions (apcu, bcmath, gd, intl, opcache, pdo_mysql, etc.)
- Supervisor for process management
- Config files for PHP, FPM, and Supervisor
- Entrypoint script for customization

### PHP Configuration

- **Common settings** (`php.common.ini`):
    - Timezone: UTC
    - Memory limit: 1024M
    - OPcache enabled with optimized settings
    - APCu enabled for CLI
    - Realpath cache: 4096K, TTL 600

- **Production settings** (`php.prod.ini`):
    - Display errors: Off
    - Error reporting: E_ALL & ~E_DEPRECATED & ~E_STRICT
    - Expose PHP: Off
    - OPcache enabled

### FPM Configuration

- **Pool settings** (`fpm-pool.conf`):
    - Listen: 127.0.0.1:9000
    - User/Group: www-data
    - Process manager: dynamic
    - Max children: 20
    - Start servers: 2
    - Min/Max spare servers: 1/4
    - Status path: /fpm-status

### Supervisor Configuration

- Manages PHP-FPM process
- Logs to stderr
- No daemon mode

## Extending the Entrypoint

Note: This works for all images, here is an example for PHP images:

To customize the container startup in derived images; I always find it a hassle to override the whole entrypoint script just to add a few commands.
Therefore, I added support for an optional local entrypoint script that is executed before the main entrypoint logic.

Example `Dockerfile` for a derived image:

```dockerfile
FROM neunerlei/php:8.4-fpm-debian

# Add custom startup script
COPY my-entrypoint.local.sh /usr/bin/app/entrypoint.local.sh

# Your customizations...
```

Obviously this works with mounted files as well, when you don't want to create a new image.

The `/usr/bin/app/my-entrypoint.local.sh` could look like this:

```bash
#!/bin/bash
# Custom startup commands
echo "Running custom startup commands..."
# e.g., setting environment variables, initializing services, etc.
```

Then mount it:

```bash
docker run -d -p 9000:9000 -v /path/to/my-entrypoint.local.sh:/usr/local/bin/entrypoint.local.sh neunerlei/php:8.4-fpm-debian
```
