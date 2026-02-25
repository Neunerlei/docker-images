# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Node.js image with an nginx server based on debian"

ENV TZ=UTC

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
    --exec-after-dependencies "npm install -g pnpm" \
    --www-data-wrap "/usr/local/bin/npm" \
    --www-data-wrap "/usr/local/bin/pnpm"

# Load image specific files
COPY --chown=www-data:www-data container /container
COPY --chown=www-data:www-data src /var/www/html

SHELL ["/bin/bash", "-c"]
WORKDIR /var/www/html

RUN mkdir -p /var/www/.npm && chmod 755 /var/www/.npm \
    && chown www-data:www-data /var/www/.npm \
    && mkdir -p /usr/local/lib/node_modules \
    && chown -R www-data:www-data /usr/local/lib/node_modules

# Remove the "node" user, so we do not create conflicts with www-data
RUN userdel -r node || true

EXPOSE 80

USER root

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
