# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="A highly opinonated nginx fileserver or reverse proxy"

ENV TZ=UTC
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh --no-nginx

SHELL ["/bin/bash", "-c"]
WORKDIR /var/www/html

# Remove the "nginx" user, so we do not create conflicts with www-data
RUN userdel -r nginx || true

# Load common files
RUN --mount=type=bind,from=common,source=v1,target=/tmp/common \
    cp -r /tmp/common/templates/* "${CONTAINER_TEMPLATE_DIR}/" && \
    cp -r /tmp/common/bin/* "${CONTAINER_BIN_DIR}/" && \
    find "${CONTAINER_BIN_DIR}" -type f -name "*.sh" -exec chmod +x {} \; || true

# Load image files
COPY --chown=www-data:www-data templates/ "${CONTAINER_TEMPLATE_DIR}/"
COPY --chown=www-data:www-data --chmod=+x bin/ "${CONTAINER_BIN_DIR}/"
COPY --chown=www-data:www-data src /var/www/html/public

EXPOSE 80

# Link our custom entrypoint into the container entrypoint
RUN chmod 755 "${CONTAINER_BIN_DIR}/entrypoint.sh" && \
    ln -s "${CONTAINER_BIN_DIR}/entrypoint.sh" "/docker-entrypoint.d/000-entrypoint.sh"
