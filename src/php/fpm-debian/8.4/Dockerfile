# syntax = docker/dockerfile:1.2
ARG SOURCE_IMAGE_TAG=latest
FROM php:${SOURCE_IMAGE_TAG}

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

COPY config/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY config/php.common.ini /usr/local/etc/php/conf.d/zzz.app.common.ini
COPY config/php.prod.ini /usr/local/etc/php/conf.d/zzz.app.prod.ini
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY --chown=www-data:www-data --chmod=+x bin /usr/bin/app
RUN chmod 755 /usr/bin/app/entrypoint.sh

RUN mkdir -p /run/supervisord && chmod 777 /run/supervisord

# Legacy support, we had a typo in the filename before
# @todo remove this in php 8.5
RUN mkdir -p /user/bin/app && \
    ln -s /usr/bin/app/entrypoint.sh /user/bin/app/entrypoint.sh

ENTRYPOINT ["/usr/bin/app/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
