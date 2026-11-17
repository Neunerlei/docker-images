# syntax = docker/dockerfile:1.14
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean PHP FPM image with an nginx server based on debian"

ENV TZ=UTC
# Make the utility commands in /container/bin callable by name from fresh
# shells (docker exec, Dockerfile RUN steps in builder stages). The entrypoint
# prepends the directory at runtime, but that only reaches its own processes.
ENV PATH="/container/bin:$PATH"

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
      --env-wrap "/usr/local/bin/php" \
      --user-owned-dir "/usr/local/etc/php/conf.d" \
      --user-owned-dir "/usr/local/etc/php-fpm.d" \
      --add-dependency "libxml2-dev" \
      --add-dependency "tzdata" \
      --add-dependency "libicu-dev" \
      --add-dependency "libedit-dev" \
      --add-dependency "libzip-dev" \
      --add-dependency "libwebp-dev" \
      --add-dependency "webp" \
      --remove-dependency "7zip" \
      --tpl "php-ini" \
        --source-dir "/container/templates/php" \
        --source-dir "/container/custom/php" \
        --target-dir "/usr/local/etc/php/conf.d" \
        --pattern "*.ini" \
      --tpl "php-fpm" \
        --source-dir "/container/templates/php/fpm" \
        --source-dir "/container/custom/php/fpm" \
        --target-dir "/usr/local/etc/php-fpm.d" \
        --pattern "*.conf"

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

RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=mlocati/php-extension-installer:latest,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    install-php-extensions \
        apcu \
        bcmath \
        bz2 \
        exif \
        gd \
        intl \
        opcache \
        pdo_mysql \
        xmlrpc \
        zip


# Remove default fpm pool config (This causes issues, because we want to listen to a socket, not port 9000)
RUN rm -rf /usr/local/etc/php-fpm.d/zz-docker.conf

EXPOSE 80

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
