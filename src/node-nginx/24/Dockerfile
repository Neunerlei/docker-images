# syntax = docker/dockerfile:1.2
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Node.js image with an nginx server based on debian"

ENV TZ=UTC
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

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
    supervisor \
    gosu \
    && apt-get clean

# Remove the "node" user, so we do not create conflicts with www-data
RUN userdel -r node || true

# Create additional config directories
RUN mkdir -p "$CONTAINER_TEMPLATE_DIR" && chmod 755 "$CONTAINER_TEMPLATE_DIR" && \
    mkdir -p /etc/nginx/snippets/service.d && chmod 755 /etc/nginx/snippets/service.d

# Copy configuration tempaltes
COPY --chown=www-data:www-data templates "$CONTAINER_TEMPLATE_DIR"

# Make sure files/folders needed by the processes are accessable when they run under the nobody user
RUN chown -R www-data:www-data /var/www/html /run /var/lib/nginx /var/log/nginx

# Copy initial sources
COPY --chown=www-data:www-data ./src /var/www/html

# Copy entrypoint
COPY --chown=www-data:www-data --chmod=+x bin "$CONTAINER_BIN_DIR"
RUN chmod 755 "$CONTAINER_BIN_DIR/entrypoint.sh"

EXPOSE 80

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/usr/bin/container/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
