#!/bin/bash

echo "[ENTRYPOINT] Image configuration:";

declare NGINX_PROXY_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/proxy.d"
user_owned_directories_registry+=(
  "${NGINX_PROXY_SNIPPET_DIR}"
)
export NGINX_CUSTOM_PROXY_TEMPLATE_DIR="${NGINX_CUSTOM_TEMPLATE_DIR}/proxy"

# IMPORTANT: We ignore the "BUILD" container mode, and always set the mode based on the presence of proxy containers.
# There is no build-time configuration for nginx images, so the build mode is not applicable here.
# If there are any PROXY_*_CONTAINER environment variables, set the container mode to "proxy"
if env | grep -q '^PROXY_.*_CONTAINER='; then
  export CONTAINER_MODE="proxy"
else
  export CONTAINER_MODE="static" # Static file server mode is the default if no proxy containers are defined
fi

# Always enable supervisor and nginx features
feature_registry="${feature_registry} supervisor nginx"
