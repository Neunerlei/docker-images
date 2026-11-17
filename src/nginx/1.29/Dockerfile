# syntax = docker/dockerfile:1.14
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="A highly opinonated nginx fileserver or reverse proxy"

ENV TZ=UTC
# Make the utility commands in /container/bin callable by name from fresh
# shells (docker exec, Dockerfile RUN steps in builder stages). The entrypoint
# prepends the directory at runtime, but that only reaches its own processes.
ENV PATH="/container/bin:$PATH"

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
        --remove-dependency "nginx" \
        --tpl "nginx-custom-snippets-proxy" \
        --source-dir "/container/custom/nginx/proxy" \
        --target-dir "/etc/nginx/snippets/proxy.d"

# Load image specific files.
# --chmod makes the copied modes independent of the checkout umask: COPY
# otherwise preserves the build context's modes verbatim, so a umask-002
# tree would bake 664/775 into the image where the umask-022 registry builds
# bake 644/755. u=rwX,go=rX fixes that: capital X sets the execute bit only
# on directories and on files that already carry it, and git preserves the
# executable bit across checkouts regardless of umask — so the result is
# stable (directories 755, files 644, executable files 755) and matches the
# umask-022 builds. The common layer needs no equivalent: installer.sh
# copies it inside a RUN step, which always runs with the daemon's fixed
# umask. Symbolic --chmod needs Dockerfile frontend 1.14+ (the syntax pin
# above): older frontends accept the flag and silently ignore it.
COPY --chown=www-data:www-data --chmod=u=rwX,go=rX container /container
COPY --chown=www-data:www-data --chmod=u=rwX,go=rX src /var/www/html

SHELL ["/bin/bash", "-c"]
WORKDIR /var/www/html

# Remove the "nginx" user, so we do not create conflicts with www-data
RUN userdel -r nginx || true

EXPOSE 80

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
