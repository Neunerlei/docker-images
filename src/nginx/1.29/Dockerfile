ARG SOURCE_IMAGE_TAG=latest
FROM nginx:${SOURCE_IMAGE_TAG}

LABEL org.opencontainers.image.authors="Martin Neundorfer <code@neunerlei.eu>"
LABEL org.opencontainers.image.description="A highly opinonated nginx fileserver or reverse proxy"

ENV DOCKER_PROJECT_PROTOCOL=http
ENV DOCKER_PROJECT_HOST=localhost
ENV DOCKER_PROJECT_PATH=/

RUN mkdir -p /var/www/html/public

WORKDIR /var/www/html

# Create additional config directories
RUN mkdir -p /etc/app/config.tpl && chmod 755 /etc/app/config.tpl && \
    mkdir -p /etc/nginx/snippets/before.d && chmod 755 /etc/nginx/snippets/before.d && \
    mkdir -p /etc/nginx/snippets/after.d && chmod 755 /etc/nginx/snippets/after.d && \
    mkdir -p /etc/nginx/snippets/before.https.d && chmod 755 /etc/nginx/snippets/before.https.d && \
    mkdir -p /etc/nginx/snippets/after.https.d && chmod 755 /etc/nginx/snippets/after.https.d && \
    mkdir -p /etc/nginx/snippets/proxy.d && chmod 755 /etc/nginx/snippets/proxy.d

# Copy configuration tempaltes
COPY --chown=nginx:nginx config/templates /etc/app/config.tpl

# Copy initial soruces
COPY --chown=nginx:nginx ./src /var/www/html/public

# Copy entrypoint (uses the base image extension mechanism)
COPY --chown=nginx:nginx --chmod=+x bin /usr/bin/app
RUN chmod 755 /usr/bin/app/entrypoint.sh && \
    ln -s /usr/bin/app/entrypoint.sh /docker-entrypoint.d/000-entrypoint.sh
