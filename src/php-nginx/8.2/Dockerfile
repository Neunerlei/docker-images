# syntax = docker/dockerfile:1.2
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image with an nginx server based on debian"

ENV TZ=UTC
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

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
    gosu \
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
RUN mkdir -p "$CONTAINER_TEMPLATE_DIR" && chmod 755 "$CONTAINER_TEMPLATE_DIR" && \
    mkdir -p /etc/nginx/sites-enabled && chmod 755 /etc/nginx/sites-enabled && \
    mkdir -p /etc/nginx/sites-available && chmod 755 /etc/nginx/sites-available && \
    mkdir -p /etc/nginx/snippets/service.d && chmod 755 /etc/nginx/snippets/service.d && \
    mkdir -p /etc/nginx/snippets/global.d && chmod 755 /etc/nginx/snippets/global.d && \
    mkdir -p /etc/ssl/certs && chmod 755 /etc/ssl/certs && \
    mkdir -p /var/www/html/public && chmod 755 /var/www/html/public && \
    mkdir -p /var/www/errors && chmod 755 /var/www/errors

WORKDIR /var/www/html

# Copy configuration tempaltes
COPY --chown=www-data:www-data templates "$CONTAINER_TEMPLATE_DIR"

# Remove default fpm pool config (This causes issues, because we want to listen to a socket, not port 9000)
RUN rm -rf /usr/local/etc/php-fpm.d/zz-docker.conf

# Copy initial sources
COPY --chown=www-data:www-data ./src /var/www/html

# Copy entrypoint
COPY --chown=www-data:www-data --chmod=+x bin "$CONTAINER_BIN_DIR"
RUN chmod 755 "$CONTAINER_BIN_DIR/entrypoint.sh"

EXPOSE 80

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/usr/bin/container/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
