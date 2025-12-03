# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Node.js image with an nginx server based on debian"

ENV TZ=UTC
ENV CONTAINER_TEMPLATE_DIR=/etc/container/templates
ENV CONTAINER_BIN_DIR=/usr/bin/container

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1/installer,target=/tmp/scripts \
    bash /tmp/scripts/install-common-deps.sh && \
    bash /tmp/scripts/install-bash-wrapper.sh && \
    bash /tmp/scripts/install-common-dirs.sh

SHELL ["/bin/bash", "-c"]
WORKDIR /var/www/html

RUN mkdir -p /var/www/.npm && chmod 755 /var/www/.npm

# Remove the "node" user, so we do not create conflicts with www-data
RUN userdel -r node || true

# Load common files
RUN --mount=type=bind,from=common,source=v1,target=/tmp/common \
    cp -r /tmp/common/templates/* "$CONTAINER_TEMPLATE_DIR/" && \
    cp -r /tmp/common/bin/* "$CONTAINER_BIN_DIR/" && \
    find "$CONTAINER_BIN_DIR" -type f -name "*.sh" -exec chmod +x {} \; || true

# Load image files
COPY --chown=www-data:www-data templates/ "$CONTAINER_TEMPLATE_DIR/"
COPY --chown=www-data:www-data --chmod=+x bin/ "$CONTAINER_BIN_DIR/"
COPY --chown=www-data:www-data src /var/www/html

EXPOSE 80

ENTRYPOINT ["/usr/bin/container/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
