# Legacy PHP images (<= PHP 8.4)

Originally the images would only contain PHP-FPM itself without any web server. This made it necessary to always run a separate web server container (e.g., Nginx or Apache) alongside the PHP-FPM container to serve PHP applications. However, this setup can be cumbersome for simple use cases or development environments.

Starting in [PHP 8.5](current.md), the images have been updated to include a built-in web server (using PHP's built-in server capabilities) alongside PHP-FPM. This allows you to run PHP applications directly within the container without needing a separate web server container. To get the same features for the PHP 8.4 image, you can now use the `fpm-nginx-debian` variant, which includes Nginx pre-configured to work with PHP-FPM, starting from PHP 8.5 this will be the default behavior for all images.

Also, starting with PHP 8.4, the base image switches from Alpine to Debian for better compatibility and stability. Debian will be the only base image for newer PHP versions. As an intermediate step, the PHP 8.4 images still offer an Alpine variant (`fpm-alpine`), together with a migration version of the Debian-based image (`fpm-debian`) and the new standard nginx variant (`fpm-nginx-debian`).

> Everything you read below, is ONLY true for PHP versions **8.4 and below WITHOUT nginx**
> For the `8.4-fpm-nginx-debian` image, as well as all images `>= 8.5`, please refer to the [current PHP documentation](current.md).

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
