# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image with an nginx server based on debian"

ENV TZ=UTC

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
      --env-wrap "/usr/local/bin/php" \
      --add-dependency "libxml2-dev" \
      --add-dependency "tzdata" \
      --add-dependency "libicu-dev" \
      --add-dependency "libedit-dev" \
      --add-dependency "libzip-dev" \
      --add-dependency "libwebp-dev" \
      --add-dependency "webp" \
      --tpl "php-ini" \
        --source-dir "/container/templates/php" \
        --source-dir "/container/custom/php" \
        --target-dir "/usr/local/etc/php/conf.d" \
        --pattern "*.ini" \
      --tpl "php-fpm" \
        --source-dir "/container/templates/php/fpm" \
        --source-dir "/container/custom/php/fpm" \
        --target-dir "/usr/local/etc/php-fpm.d" \
        --pattern "*.conf"

# Load image specific files
COPY --chown=www-data:www-data container /container
COPY --chown=www-data:www-data src /var/www/html

SHELL ["/bin/bash", "-c"]
WORKDIR /var/www/html

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=mlocati/php-extension-installer:latest,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    install-php-extensions \
        apcu \
        bcmath \
        bz2 \
        exif \
        gd \
        intl \
        opcache \
        pdo_mysql \
        xmlrpc \
        zip


# Remove default fpm pool config (This causes issues, because we want to listen to a socket, not port 9000)
RUN rm -rf /usr/local/etc/php-fpm.d/zz-docker.conf

EXPOSE 80

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
