# syntax = docker/dockerfile:1.14
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Node.js image with an nginx server based on debian"

ENV TZ=UTC
# Make the utility commands in /container/bin callable by name from fresh
# shells (docker exec, Dockerfile RUN steps in builder stages). The entrypoint
# prepends the directory at runtime, but that only reaches its own processes.
ENV PATH="/container/bin:$PATH"

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
    --exec-after-dependencies "npm install -g pnpm" \
    --env-wrap "/usr/local/bin/node" \
    --user-owned-dir "/usr/local/lib/node_modules" \
    --www-data-wrap "/usr/local/bin/npm" \
    --www-data-wrap "/usr/local/bin/pnpm"

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

# Prepare the global node_modules directory so www-data can install global
# packages. The npm cache no longer needs a dedicated directory: npm writes
# it into the www-data home (/container/work/www-data-home) on demand.
RUN mkdir -p /usr/local/lib/node_modules \
    && chown -R www-data:www-data /usr/local/lib/node_modules

# Remove the "node" user, so we do not create conflicts with www-data
RUN userdel -r node || true

EXPOSE 80

USER root

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
