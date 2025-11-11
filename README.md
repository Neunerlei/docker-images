# Docker Images

A collection of Docker images; optimized for production use with common extensions and configurations.

## Important Notice

These images are in general for my private/professional projects. I try to keep them updated and secure and promise not to include any breaking changes without notice. However, I cannot guarantee the same level of support and stability as official images. Use at your own risk. All images are automatically build via GitHub Actions on Sunday and Wednesday to ensure they are up-to-date.

## PHP

The images are organized under `src/php/` by PHP version and type, they are available on Docker Hub: [neunerlei/php](https://hub.docker.com/r/neunerlei/php)

### Newer Versions (>= PHP 8.5)
From PHP 8.5 onwards, I only provide a debian based image including nginx. Please refer to the [current PHP documentation](docs/php/current.md) for details.

> Currently, PHP 8.5 is not yet released, so we work with the RC versions for now.
> 
> **Versions**: 8.5
> 
> **Types**:
> - `fpm-debian`: Based on Debian (NO NGINX) (ONLY for 8.5, to ease the transition)
> - `fpm-nginx-debian`: Based on Debian with NGINX included


### Legacy PHP images (<= PHP 8.4)

Older PHP versions (<= PHP 8.4) do not include NGINX by default. Please refer to the [legacy PHP documentation](docs/php/legacy.md) for details.

> **Versions**: 7.4, 8.1, 8.2, 8.3, 8.4
> 
> **Types**:
> - `fpm-alpine`: Based on Alpine Linux (for versions <= 8.4)
> - `fpm-debian`: Based on Debian (NO NGINX) (ONLY for 8.4, to ease the transition)
> - `fpm-nginx-debian`: Based on Debian with NGINX (introduced in 8.4, will be the default for future versions)

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
./bin/build.sh php 8.5 fpm-debian --push
```

The script navigates to `src/${IMAGE_NAME}/${VERSION}/${TYPE}`, builds the Docker image with tag `neunerlei/${IMAGE_NAME}:${VERSION}-${TYPE}`, and pushes if `--push` is specified.

## Usage Example

To run a container:

```bash
docker run -d -p 9000:9000 neunerlei/php:8.5-fpm-nginx-debian
```

Mount your application code to `/var/www/html` and configure your web server to proxy to `127.0.0.1:9000`.

## License

There is no license for these images. The licenses for the base images and included software apply; obviously.
Use, modify and distribute at your own risk and leisure. I do not take any responsibility for any damage caused by using these images. However! If you have any questions or problems, feel free to open an issue or contact me directly.
