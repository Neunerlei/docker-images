#!/bin/bash

# Image environment for nginx — the file convention that replaced the former
# step.d/015-image-vars.sh. The environment orchestrator
# (step.d/015-environment.sh) sources this file and calls the functions at
# their correct pipeline positions:
#
#   image_env_features()  once, BEFORE the custom env files load (so
#                         mode-*/feat-* markers filter them)
#   image_env_defaults()  after EVERY derive pass (three times — must be
#                         idempotent; every default goes through default_var)
#   image_env_validate()  once, on the final values (not used by this image)

# CONTAINER_MODE and features.
image_env_features() {
    # IMPORTANT: We ignore the "BUILD" container mode, and always set the mode based on the presence of proxy containers.
    # There is no build-time configuration for nginx images, so the build mode is not applicable here.
    # A mode set by anything else (e.g. a LEGACY 015 override, which runs before
    # this) IS respected — hence the explicit -z / build check instead of the
    # unconditional assignment the old step used.
    if [ -z "${CONTAINER_MODE}" ] || [ "${CONTAINER_MODE}" == "build" ]; then
        # If there are any PROXY_*_CONTAINER environment variables, set the container mode to "proxy"
        if env | grep -q '^PROXY_.*_CONTAINER='; then
            export CONTAINER_MODE="proxy"
        else
            export CONTAINER_MODE="static" # Static file server mode is the default if no proxy containers are defined
        fi
    fi

    # Always enable supervisor and nginx features
    feature_registry="${feature_registry} supervisor nginx"
}

# Runtime defaults. Runs three times; every value goes through default_var,
# so a user-set value survives every pass.
image_env_defaults() {
    # Additional NGINX settings (strong single quotes: $uri stays literal)
    default_var NGINX_TRY_FILES '$uri $uri/ /index.html /index.htm =404'

    # Constant (idempotent re-export)
    export NGINX_CUSTOM_SNIPPETS_PROXY_DIR="${NGINX_SNIPPETS_DIR}/proxy.d"
}
