# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image with an nginx server based on debian"

ENV TZ=UTC
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    INSTALLER_EXTRA_DEPENDENCIES="libxml2-dev tzdata libicu-dev libedit-dev libzip-dev libwebp-dev" \
    bash /tmp/installer/installer.sh

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

# Load common files
RUN --mount=type=bind,from=common,source=v1,target=/tmp/common \
    cp -r /tmp/common/templates/* "$CONTAINER_TEMPLATE_DIR/" && \
    cp -r /tmp/common/bin/* "$CONTAINER_BIN_DIR/" && \
    find "$CONTAINER_BIN_DIR" -type f -name "*.sh" -exec chmod +x {} \; || true

# Load image files
COPY --chown=www-data:www-data templates/ "$CONTAINER_TEMPLATE_DIR/"
COPY --chown=www-data:www-data --chmod=+x bin/ "$CONTAINER_BIN_DIR/"
COPY --chown=www-data:www-data src /var/www/html

# Remove default fpm pool config (This causes issues, because we want to listen to a socket, not port 9000)
RUN rm -rf /usr/local/etc/php-fpm.d/zz-docker.conf

EXPOSE 80

ENTRYPOINT ["/usr/bin/container/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
