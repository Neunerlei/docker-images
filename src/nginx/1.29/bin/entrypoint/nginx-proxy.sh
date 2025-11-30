if [[ "$CONTAINER_MODE" == "proxy" ]]; then
    echo "[ENTRYPOINT.proxy] Configuring Nginx in proxy mode..."
    echo "[ENTRYPOINT.proxy] Using project base path: '${DOCKER_SERVICE_ABS_PATH}'"

    LOCATION_BLOCKS=""
    # `compgen -A variable` lists all variables. We grep for our pattern.
    for var in $(compgen -A variable | grep '^PROXY_.*_CONTAINER'); do
        # Extract the unique key (e.g., "APP", "BACKEND")
        KEY=$(echo "$var" | sed -E 's/PROXY_(.*)_CONTAINER/\1/')
        echo "[ENTRYPOINT.proxy] Found service key: ${KEY}"

        # Dynamically read the variables for this key
        # Using `declare` and indirection is a robust way to do this.
        declare PROXY_PATH_VAR="PROXY_${KEY}_PATH"
        declare PROXY_DEST_VAR="PROXY_${KEY}_DEST"
        declare PROXY_PORT_VAR="PROXY_${KEY}_PORT"
        declare PROXY_HTTPS_PORT_VAR="PROXY_${KEY}_HTTPS_PORT"
        declare PROXY_CONTAINER_VAR="PROXY_${KEY}_CONTAINER"
        declare PROXY_PROTOCOL_VAR="PROXY_${KEY}_PROTOCOL"
        declare PROXY_LOCATION_PATH="$(join_paths "${DOCKER_SERVICE_ABS_PATH}" "${!PROXY_PATH_VAR:-/}")"

        # Determine either port by protocol, or protocol by port
        # If PROXY_PROTOCOL_VAR is not set, assume HTTP
        # If PROXY_HTTPS_PORT_VAR is set, assume HTTPS
        DEFAULT_PROTOCOL="http"
        declare PROXY_UPSTREAM_PROTOCOL="${!PROXY_PROTOCOL_VAR:-$DEFAULT_PROTOCOL}"

        # Determine default port based on protocol
        if [ "${PROXY_UPSTREAM_PROTOCOL}" == "https" ]; then
            declare PROXY_UPSTREAM_PORT="${!PROXY_HTTPS_PORT_VAR:-443}"
        else
            declare PROXY_UPSTREAM_PORT="${!PROXY_PORT_VAR:-80}"
        fi

        declare PROXY_UPSTREAM_HOST="${!PROXY_CONTAINER_VAR}"
        declare PROXY_UPSTREAM_PORT="${!PROXY_PORT_VAR:-${PROXY_UPSTREAM_PORT}}"
        declare PROXY_UPSTREAM_PROTOCOL="${!PROXY_PROTOCOL_VAR:-$DEFAULT_PROTOCOL}"

        echo "   - Location path: ${PROXY_LOCATION_PATH}"
        echo "   - Upstream host: ${PROXY_UPSTREAM_HOST}"
        echo "   - Upstream port: ${PROXY_UPSTREAM_PORT}"
        echo "   - Upstream protocol: ${PROXY_UPSTREAM_PROTOCOL}"

        # Set VIRTUAL_DEST if the variable exists and is not empty
        PROXY_DEST_VALUE="${!PROXY_DEST_VAR}"
        if [ -n "$PROXY_DEST_VALUE" ]; then
            declare PROXY_REWRITE_RULE="rewrite ^${PROXY_LOCATION_PATH}(.*)$ ${PROXY_DEST_VALUE}\$1 break;"
            echo "   - Using rewrite rule: ${PROXY_REWRITE_RULE}"
        else
            declare PROXY_REWRITE_RULE=""
        fi

        declare KEY_LOWER=${KEY,,}
        CURRENT_LOCATION_BLOCK=$(render_template_string "$(get_all_vars)" "$NGINX_TEMPLATE_DIR/proxy.location.nginx.conf")
        LOCATION_BLOCKS="${LOCATION_BLOCKS}${CURRENT_LOCATION_BLOCK}"

        declare LOCATION_SNIPPET_DIR="${NGINX_PROXY_SNIPPET_DIR}/${KEY_LOWER}"
        mkdir -p "${LOCATION_SNIPPET_DIR}"
        declare LOCATION_TEMPLATE_DIR="${NGINX_CUSTOM_PROXY_TEMPLATE_DIR}/${KEY_LOWER}"
        if [ -d "${LOCATION_TEMPLATE_DIR}" ]; then
          render_filtered_templates_in_dir "${LOCATION_TEMPLATE_DIR}" "${LOCATION_SNIPPET_DIR}" "*.conf"
        fi
    done

    render_template_all_vars "${NGINX_TEMPLATE_DIR}/service.root.proxy.nginx.conf" "${NGINX_SNIPPET_DIR}/service.root.nginx.conf" "LOCATION_BLOCKS"

cat "${NGINX_SNIPPET_DIR}/service.root.nginx.conf"
    echo "[ENTRYPOINT.proxy] Nginx configuration completed for proxy mode";
fi
