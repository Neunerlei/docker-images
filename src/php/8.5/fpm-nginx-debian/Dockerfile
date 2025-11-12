# syntax = docker/dockerfile:1.2
FROM php:8.5-rc-fpm-bookworm AS app_php

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image with an nginx server based on debian"

ENV APP_ENV=prod

WORKDIR /var/www/html

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    apt-get update && apt-get upgrade -y && apt-get install -y \
    bash \
    curl \
    nginx \
    ca-certificates \
    openssl \
    openssh-client \
    git \
    nano \
    libxml2-dev \
    tzdata \
    libicu-dev \
    openntpd \
    libedit-dev \
    libzip-dev \
    supervisor \
    libwebp-dev \
    gettext \
    && apt-get clean

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

# Create additional config directories
RUN mkdir -p /etc/app/config.tpl && chmod 755 /etc/app/config.tpl && \
    mkdir -p /etc/nginx/snippets/before.d && chmod 755 /etc/nginx/snippets/before.d && \
    mkdir -p /etc/nginx/snippets/after.d && chmod 755 /etc/nginx/snippets/after.d

# Copy configuration tempaltes
COPY --chown=www-data:www-data config/templates /etc/app/config.tpl

# Copy configuration files
COPY --chown=www-data:www-data config/nginx.conf /etc/nginx
COPY --chown=www-data:www-data config/supervisord.conf /etc/supervisor

# Remove default fpm pool config (This causes issues, because we want to listen to a socket, not port 9000)
RUN rm -rf /usr/local/etc/php-fpm.d/zz-docker.conf

# Make sure files/folders needed by the processes are accessable when they run under the nobody user
RUN chown -R www-data:www-data /var/www/html /run /var/lib/nginx /var/log/nginx

# Copy initial soruces
COPY --chown=www-data:www-data ./src /var/www/html

# Copy entrypoint
COPY --chown=www-data:www-data --chmod=+x bin /usr/bin/app
RUN chmod 755 /usr/bin/app/entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/bin/app/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
