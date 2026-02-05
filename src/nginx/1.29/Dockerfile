# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="A highly opinonated nginx fileserver or reverse proxy"

ENV TZ=UTC

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
        --remove-dependency "nginx" \
        --tpl "nginx-custom-snippets-proxy" \
        --source-dir "/container/custom/nginx/proxy" \
        --target-dir "/etc/nginx/snippets/proxy.d"

# Load image specific files
COPY --chown=www-data:www-data container /container
COPY --chown=www-data:www-data src /var/www/html

SHELL ["/bin/bash", "-c"]
WORKDIR /var/www/html

# Remove the "nginx" user, so we do not create conflicts with www-data
RUN userdel -r nginx || true

EXPOSE 80

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
