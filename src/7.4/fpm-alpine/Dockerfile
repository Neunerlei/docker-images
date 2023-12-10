# syntax = docker/dockerfile:1.2
FROM php:7.4-fpm-alpine AS app_php

# set maintainer and description
LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image based on alpine"

ENV APP_ENV=prod

WORKDIR /var/www/html

RUN --mount=type=cache,id=apk-cache,target=/var/cache/apk rm -rf /etc/apk/cache && ln -s /var/cache/apk /etc/apk/cache && \
    apk update && apk upgrade && apk add \
	bash \
    curl \
    ca-certificates \
    openssl \
    openssh \
    git \
    nano \
    libxml2-dev \
    tzdata \
    icu-dev \
    openntpd \
    libedit-dev \
    libzip-dev \
    supervisor

# Install fcgi for healthcheck
RUN --mount=type=cache,id=apk-cache,target=/var/cache/apk rm -rf /etc/apk/cache && ln -s /var/cache/apk /etc/apk/cache && \
    apk update && apk upgrade && apk add \
	  fcgi

# Install php extensions
RUN --mount=type=cache,id=apk-cache,target=/var/cache/apk \
    --mount=type=bind,from=mlocati/php-extension-installer:1.5,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
		rm -rf /etc/apk/cache && ln -s /var/cache/apk /etc/apk/cache && \
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

# Configure PHP-FPM
COPY config/fpm-pool.conf /usr/local/etc/php-fpm.d/www.conf
COPY config/php.common.ini /usr/local/etc/php/conf.d/zzz.app.common.ini
COPY config/php.prod.ini /usr/local/etc/php/conf.d/zzz.app.prod.ini

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy additional boot script files
COPY --chown=1000:1000 bin /user/bin/app
RUN find /user/bin/app -type f -iname "*.sh" -exec chmod +x {} \;

# Let supervisord start nginx & php-fpm
CMD ["/user/bin/app/boot.sh"]

# Configure a healthcheck to validate that everything is up & running
HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1:80/fpm-ping
