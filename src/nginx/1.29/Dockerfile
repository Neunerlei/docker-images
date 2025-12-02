# syntax = docker/dockerfile:1.2
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="A highly opinonated nginx fileserver or reverse proxy"

ENV TZ=UTC
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    apt-get update && apt-get upgrade -y && apt-get install -y \
    bash \
    curl \
    nano \
    gosu \
    && apt-get clean

# Create additional config directories
RUN mkdir -p "$CONTAINER_TEMPLATE_DIR" && chmod 755 "$CONTAINER_TEMPLATE_DIR" && \
    mkdir -p /etc/nginx/sites-enabled && chmod 755 /etc/nginx/sites-enabled && \
    mkdir -p /etc/nginx/sites-available && chmod 755 /etc/nginx/sites-available && \
    mkdir -p /etc/nginx/snippets/service.d && chmod 755 /etc/nginx/snippets/service.d && \
    mkdir -p /etc/nginx/snippets/global.d && chmod 755 /etc/nginx/snippets/global.d && \
    mkdir -p /etc/nginx/snippets/proxy.d && chmod 755 /etc/nginx/snippets/proxy.d && \
    mkdir -p /etc/ssl/certs && chmod 755 /etc/ssl/certs && \
    mkdir -p /var/www/html/public && chmod 755 /var/www/html/public && \
    mkdir -p /var/www/errors && chmod 755 /var/www/errors

WORKDIR /var/www/html

# Remove the "nginx" user, so we do not create conflicts with www-data
RUN userdel -r nginx || true

# Copy configuration tempaltes
COPY --chown=www-data:www-data templates "$CONTAINER_TEMPLATE_DIR"

# Copy initial sources
COPY --chown=www-data:www-data ./src /var/www/html/public

# Copy entrypoint (uses the base image extension mechanism)
COPY --chown=www-data:www-data --chmod=+x bin "$CONTAINER_BIN_DIR"
RUN chmod 755 "$CONTAINER_BIN_DIR/entrypoint.sh" && \
    ln -s "$CONTAINER_BIN_DIR/entrypoint.sh" "/docker-entrypoint.d/000-entrypoint.sh"

EXPOSE 80

SHELL ["/bin/bash", "-c"]
