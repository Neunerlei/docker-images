# syntax = docker/dockerfile:1.2
FROM php:8.4-fpm-bookworm AS app_php

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image based on debian"

ENV APP_ENV=prod

WORKDIR /var/www/html

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    apt-get update && apt-get upgrade -y && apt-get install -y \
    bash \
    curl \
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
    # Install fcgi for healthcheck
    libfcgi-bin \
    && apt-get clean

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=mlocati/php-extension-installer:1.5,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
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

COPY config/fpm-pool.conf /usr/local/etc/php-fpm.d/www.conf
COPY config/php.common.ini /usr/local/etc/php/conf.d/zzz.app.common.ini
COPY config/php.prod.ini /usr/local/etc/php/conf.d/zzz.app.prod.ini

COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY --chown=1000:1000 bin /user/bin/app
RUN find /user/bin/app -type f -iname "*.sh" -exec chmod +x {} \;

CMD ["/user/bin/app/boot.sh"]
