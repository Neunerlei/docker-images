if [[ "$CONTAINER_MODE" == "proxy" ]]; then
    echo "[ENTRYPOINT.proxy] Configuring Nginx in proxy mode..."

    # Read the global project path, ensuring it's not just "/" and cleaning trailing slashes
    PROJECT_BASE_PATH=$(echo "${DOCKER_PROJECT_PATH:-/}" | sed 's:/*$::')
    if [ "$PROJECT_BASE_PATH" == "/" ]; then
        PROJECT_BASE_PATH=""
    else
      echo "[ENTRYPOINT.proxy] Using project base path: '${PROJECT_BASE_PATH}'"
    fi

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
        declare PROXY_CONTAINER_VAR="PROXY_${KEY}_CONTAINER"

        # Get the relative path for this service
        RELATIVE_SERVICE_PATH="${!PROXY_PATH_VAR:-/}"
        # Combine the global project path and the relative service path
        export PROXY_LOCATION_PATH="${PROJECT_BASE_PATH}${RELATIVE_SERVICE_PATH}"
        # Clean up any double slashes that might result, except for regex paths starting with ~
        if [[ ! "$PROXY_LOCATION_PATH" =~ ^\~ ]]; then
          PROXY_LOCATION_PATH=$(echo "$PROXY_LOCATION_PATH" | sed 's://:/:g')
        fi

        export PROXY_UPSTREAM_HOST="${!PROXY_CONTAINER_VAR}"
        export PROXY_UPSTREAM_PORT="${!PROXY_PORT_VAR:-80}"

        echo "   - Location path: ${PROXY_LOCATION_PATH}"
        echo "   - Upstream host: ${PROXY_UPSTREAM_HOST}"
        echo "   - Upstream port: ${PROXY_UPSTREAM_PORT}"

        # Set VIRTUAL_DEST if the variable exists and is not empty
        PROXY_DEST_VALUE="${!PROXY_DEST_VAR}"
        if [ -n "$PROXY_DEST_VALUE" ]; then
            export PROXY_REWRITE_RULE="rewrite ^${PROXY_LOCATION_PATH}(.*)$ ${PROXY_DEST_VALUE}\$1 break;"
            echo "   - Using rewrite rule: ${PROXY_REWRITE_RULE}"
        else
            export PROXY_REWRITE_RULE=""
        fi

        CURRENT_LOCATION_BLOCK=$(render_template_string 'KEY PROXY_LOCATION_PATH PROXY_UPSTREAM_HOST PROXY_UPSTREAM_PORT PROXY_REWRITE_RULE' /etc/app/config.tpl/nginx/proxy.location.tpl.nginx.conf)
        LOCATION_BLOCKS="${LOCATION_BLOCKS}${CURRENT_LOCATION_BLOCK}"
    done

    render_template 'LOCATION_BLOCKS NGINX_CLIENT_MAX_BODY_SIZE' /etc/app/config.tpl/nginx/service.proxy.snippet.tpl.nginx.conf /etc/nginx/snippets/service.nginx.conf

    echo "[ENTRYPOINT.proxy] Nginx configuration completed for proxy mode";
fi
