# syntax = docker/dockerfile:1.14
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Python image with Nginx, Gunicorn, and Flask support, based on Debian."

ENV TZ=UTC
# Make the utility commands in /container/bin callable by name from fresh
# shells (docker exec, Dockerfile RUN steps in builder stages). The entrypoint
# prepends the directory at runtime, but that only reaches its own processes.
ENV PATH="/container/bin:$PATH"

# Use the installer to add Python's package manager and venv tool.
# Also ensure net-tools is installed for some legacy networking commands if needed.
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
      --user-owned-dir "/var/www/html/public" \
      --add-dependency "python3-pip" \
      --add-dependency "python3-venv" \
      --add-dependency "net-tools" \
      --exec-after-dependencies "python3 -m venv /opt/venv" \
      --user-owned-dir "/opt/venv" \
      --env-wrap "/opt/venv/bin/python" \
      --env-wrap "/opt/venv/bin/pip" \
      --www-data-wrap "/opt/venv/bin/pip" \
      --tpl "gunicorn-conf" \
        --source "/container/templates/python/gunicorn.conf.py" \
        --target "/etc/gunicorn.conf.py"

# Set up the application directory and a virtual environment.
# This isolates our Python packages from the system's Python.
WORKDIR /var/www/html

# Make the venv's Python the default for subsequent commands.
ENV PATH="/opt/venv/bin:$PATH"

# Copy image-specific files (these are new files we will create).
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

# Creating a symlink to the global venv, so it is easily accessible when writing commands.
RUN ln -s /opt/venv /var/www/venv

# Ensure we are using the latest pip in the virtual environment before installing dependencies.
# This ensures we have the latest features and security fixes from pip when installing our project dependencies.
RUN pip install --no-cache-dir --upgrade pip
# Install Python dependencies from our requirements.txt into the virtual environment.
RUN pip install --no-cache-dir -r requirements.txt

SHELL ["/bin/bash", "-c"]
EXPOSE 80

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
