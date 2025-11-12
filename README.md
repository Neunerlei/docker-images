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

## Nginx 

A minimal NGINX image based on Debian, highly opinionated to be used as a simple web server or reverse proxy,
based on the [official NGINX image](https://hub.docker.com/_/nginx).
Available on Docker Hub: [neunerlei/nginx](https://hub.docker.com/r/neunerlei/nginx). 
Please refer to the [NGINX documentation](docs/nginx/current.md) for details.

> **Versions**: Actively maintained are the three latest NGINX versions on dockerhub.

## Build Process

Use the `bin/build.sh` script to build images:

```bash
./bin/build.sh php 8.4 fpm-debian
```

Parameters:
- `IMAGE_NAME`: e.g., `php`
- `VERSION`: e.g., `8.4`
- `TYPE`: e.g., `fpm-debian` (the type is optional)

To build and push:

```bash
./bin/build.sh php 8.5 fpm-debian --push
```

The script navigates to `src/${IMAGE_NAME}/${VERSION}/${TYPE}`, builds the Docker image with tag `neunerlei/${IMAGE_NAME}:${VERSION}-${TYPE}`, and pushes if `--push` is specified. If the `TYPE` is omitted, it assumes, that the directory is `src/${IMAGE_NAME}/${VERSION}/`.

### Automatic version tagging

We use `bin/discover-and-build.sh` to build images that rely on a specific base image, that will be updated frequently.
This is for example the case for node and nginx based images. The Idea is to query the docker hub api for the latest tags of the base image and automatically build the n latest versions based on that. 

The system has an automatic "cascading fallback" mechanism for our local source files. This is a powerful pattern. You define a "base" configuration (e.g., for version 1.27) and it is used for all subsequent versions (1.28, 1.29, etc.) until you encounter a breaking change. At that point, you create a new directory for the new version (e.g., 1.29) and it becomes the new base for future versions.

## License

There is no license for these images. The licenses for the base images and included software apply; obviously.
Use, modify and distribute at your own risk and leisure. I do not take any responsibility for any damage caused by using these images. However! If you have any questions or problems, feel free to open an issue or contact me directly.
