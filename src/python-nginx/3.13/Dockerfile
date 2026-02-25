# syntax = docker/dockerfile:1.4
ARG SOURCE_IMAGE
FROM ${SOURCE_IMAGE}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="Lean Python image with Nginx, Gunicorn, and Flask support, based on Debian."

ENV TZ=UTC

# Use the installer to add Python's package manager and venv tool.
# Also ensure net-tools is installed for some legacy networking commands if needed.
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt,sharing=locked\
    --mount=type=bind,from=common,source=v1,target=/tmp/installer \
    bash /tmp/installer/installer.sh \
      --add-dependency "python3-pip" \
      --add-dependency "python3-venv" \
      --add-dependency "net-tools" \
      --exec-after-dependencies "python3 -m venv /opt/venv && chown -R www-data:www-data /opt/venv" \
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
COPY --chown=www-data:www-data container /container
COPY --chown=www-data:www-data src /var/www/html

# Creating a symlink to the global venv, so it is easily accessible when writing commands.
RUN ln -s /opt/venv /var/www/venv

# Ensure we are using the latest pip in the virtual environment before installing dependencies.
# This ensures we have the latest features and security fixes from pip when installing our project dependencies.
RUN gosu www-data pip install --no-cache-dir --upgrade pip
# Install Python dependencies from our requirements.txt into the virtual environment.
RUN gosu www-data pip install --no-cache-dir -r requirements.txt

SHELL ["/bin/bash", "-c"]
EXPOSE 80

ENTRYPOINT ["/container/entrypoint/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
