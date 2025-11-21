# syntax = docker/dockerfile:1.2
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="A highly opinonated nginx fileserver or reverse proxy"

ENV DOCKER_PROJECT_PROTOCOL=http
ENV DOCKER_PROJECT_HOST=localhost
ENV DOCKER_PROJECT_PATH=/

RUN mkdir -p /var/www/html/public

WORKDIR /var/www/html

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    apt-get update && apt-get upgrade -y && apt-get install -y \
    bash \
    curl \
    nano \
    gosu \
    && apt-get clean

# Create additional config directories
RUN mkdir -p /etc/app/config.tpl && chmod 755 /etc/app/config.tpl && \
    mkdir -p /etc/nginx/sites-enabled && chmod 755 /etc/nginx/sites-enabled && \
    mkdir -p /etc/nginx/sites-available && chmod 755 /etc/nginx/sites-available && \
    mkdir -p /etc/nginx/snippets/before.d && chmod 755 /etc/nginx/snippets/before.d && \
    mkdir -p /etc/nginx/snippets/after.d && chmod 755 /etc/nginx/snippets/after.d && \
    mkdir -p /etc/nginx/snippets/before.https.d && chmod 755 /etc/nginx/snippets/before.https.d && \
    mkdir -p /etc/nginx/snippets/after.https.d && chmod 755 /etc/nginx/snippets/after.https.d && \
    mkdir -p /etc/nginx/snippets/proxy.d && chmod 755 /etc/nginx/snippets/proxy.d

# Copy configuration tempaltes
COPY --chown=nginx:nginx config/templates /etc/app/config.tpl

# Copy configuration files
COPY --chown=nginx:nginx config/nginx.conf /etc/nginx
COPY --chown=nginx:nginx config/mime.custom.types /etc/nginx

# Ensure ssl folder exists
RUN mkdir -p /etc/ssl/certs && chmod 755 /etc/ssl/certs && chown -R nginx:nginx /etc/ssl/certs

# Copy initial sources
COPY --chown=nginx:nginx ./src /var/www/html/public

# Copy entrypoint (uses the base image extension mechanism)
COPY --chown=nginx:nginx --chmod=+x bin /usr/bin/app
RUN chmod 755 /usr/bin/app/entrypoint.sh && \
    ln -s /usr/bin/app/entrypoint.sh /docker-entrypoint.d/000-entrypoint.sh
