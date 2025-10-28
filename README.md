# Docker Images

A collection of Docker images; optimized for production use with common extensions and configurations.

## Important Notice

These images are in general for my private/professional projects. I try to keep them updated and secure and promise not to include any breaking 
changes without notice. However, I cannot guarantee the same level of support and stability as official images. Use at your own risk.
All images are automatically build via GitHub Actions on Sunday and Wednesday to ensure they are up-to-date.

## PHP

The images are organized under `src/php/` by PHP version and type:

- **Versions**: 7.4, 8.1, 8.2, 8.3, 8.4, 8.5 _(This is currently 8.5-rc, will be stable when PHP 8.5 is officially released)_
- **Types**:
  - `fpm-alpine`: Based on Alpine Linux (for versions < 8.4)
  - `fpm-debian`: Based on Debian (introduced in 8.4, will be the default for future versions)

Each image includes:
- PHP FPM with common extensions (apcu, bcmath, gd, intl, opcache, pdo_mysql, etc.)
- Supervisor for process management
- Config files for PHP, FPM, and Supervisor
- Entrypoint script for customization

The images are available on Docker Hub: [neunerlei/php](https://hub.docker.com/r/neunerlei/php)

### PHP 8.4 and Future Versions

Starting with PHP 8.4, the base image switches from Alpine to Debian for better compatibility and stability. Debian will be the only base image for newer PHP versions.

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

## Build Process

Use the `bin/build.sh` script to build images:

```bash
./bin/build.sh php 8.4 fpm-debian
```

Parameters:
- `IMAGE_NAME`: e.g., `php`
- `VERSION`: e.g., `8.4`
- `TYPE`: e.g., `fpm-debian`

To build and push:

```bash
./bin/build.sh php 8.4 fpm-debian --push
```

The script navigates to `src/${IMAGE_NAME}/${VERSION}/${TYPE}`, builds the Docker image with tag `neunerlei/${IMAGE_NAME}:${VERSION}-${TYPE}`, and pushes if `--push` is specified.

## Usage Example

To run a container:

```bash
docker run -d -p 9000:9000 neunerlei/php:8.4-fpm-debian
```

Mount your application code to `/var/www/html` and configure your web server to proxy to `127.0.0.1:9000`.

## Extending the Entrypoint

Note: This works for all images, here is an example for PHP images: 

To customize the container startup in derived images; I always find it a hassle to override the whole entrypoint script just to add a few commands.
Therefore, I added support for an optional local entrypoint script that is executed before the main entrypoint logic.

Example `Dockerfile` for a derived image:

```dockerfile
FROM neunerlei/php:8.4-fpm-debian

# Add custom startup script
COPY my-entrypoint.local.sh /usr/local/bin/entrypoint.local.sh

# Your customizations...
```

Obviously this works with mounted files as well, when you don't want to create a new image.

The `my-entrypoint.local.sh` could look like this:

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

## License

There is no license for these images. The licenses for the base images and included software apply; obviously.
Use, modify and distribute at your own risk and leisure. I do not take any responsibility for any damage caused by using these images.
However! If you have any questions or problems, feel free to open an issue or contact me directly.
