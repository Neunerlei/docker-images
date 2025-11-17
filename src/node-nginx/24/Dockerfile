# syntax = docker/dockerfile:1.2
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Node.js image with an nginx server based on debian"

ENV APP_ENV=prod
ENV TZ=UTC
ENV DOCKER_PROJECT_PROTOCOL=http
ENV DOCKER_PROJECT_HOST=localhost
ENV DOCKER_PROJECT_PATH=/

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
    tzdata \
    openntpd \
    libedit-dev \
    libzip-dev \
    supervisor \
    gosu \
    && apt-get clean

# Remove the "node" user, so we do not create conflicts with www-data
RUN userdel -r node || true

# Create additional config directories
RUN mkdir -p /etc/app/config.tpl && chmod 755 /etc/app/config.tpl && \
    mkdir -p /etc/nginx/snippets/before.d && chmod 755 /etc/nginx/snippets/before.d && \
    mkdir -p /etc/nginx/snippets/after.d && chmod 755 /etc/nginx/snippets/after.d && \
    mkdir -p /etc/nginx/snippets/before.https.d && chmod 755 /etc/nginx/snippets/before.https.d && \
    mkdir -p /etc/nginx/snippets/after.https.d && chmod 755 /etc/nginx/snippets/after.https.d

# Copy configuration tempaltes
COPY --chown=www-data:www-data config/templates /etc/app/config.tpl

# Copy configuration files
COPY --chown=www-data:www-data config/nginx.conf /etc/nginx
COPY --chown=www-data:www-data config/supervisord.conf /etc/supervisor

# Copy initial soruces
COPY --chown=www-data:www-data ./src /var/www/html

# Copy entrypoint
COPY --chown=www-data:www-data --chmod=+x bin /usr/bin/app
RUN chmod 755 /usr/bin/app/entrypoint.sh

EXPOSE 80

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/usr/bin/app/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
