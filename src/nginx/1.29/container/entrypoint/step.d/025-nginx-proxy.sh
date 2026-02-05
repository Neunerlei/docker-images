declare rendered_location_blocks=""

function _process_custom_proxy_snippet_templates() {
    local output_path="${1}"
    local source_path="${3}"

    # If either source_path or output_path is empty, we cannot proceed
    if [[ -z "${source_path}" || -z "${output_path}" ]]; then
        echo "[ENTRYPOINT.proxy] Warning: Missing source or output path for custom proxy snippet template. Skipping." >&2
        return 1
    fi

    # If output_path is not a directory, we cannot proceed
    if [[ ! -d "${output_path}" ]]; then
        echo "[ENTRYPOINT.proxy] Warning: Output path '${output_path}' is not a directory. Skipping." >&2
        return 1
    fi

    # `compgen -A variable` lists all variables. We grep for our pattern.
    for var in $(compgen -A variable | grep '^PROXY_.*_CONTAINER'); do
        # Extract the unique key (e.g., "APP", "BACKEND")
        local KEY=$(echo "${var}" | sed -E 's/PROXY_(.*)_CONTAINER/\1/')
        echo "[ENTRYPOINT.proxy] Found service key: ${KEY}" >&2

        # Dynamically read the variables for this key
        local proxy_path_var="PROXY_${KEY}_PATH"
        local proxy_dest_var="PROXY_${KEY}_DEST"
        local proxy_port_var="PROXY_${KEY}_PORT"
        local proxy_https_port_var="PROXY_${KEY}_HTTPS_PORT"
        local proxy_container_var="PROXY_${KEY}_CONTAINER"
        local proxy_protocol_var="PROXY_${KEY}_PROTOCOL"

        # Determine either port by protocol, or protocol by port
        # If proxy_protocol_var is not set, assume HTTP
        # If proxy_https_port_var is set, assume HTTPS
        local default_protocol="http"
        local PROXY_UPSTREAM_PROTOCOL="${!proxy_protocol_var:-${default_protocol}}"
        local PROXY_LOCATION_PATH="$(join_paths "${DOCKER_SERVICE_ABS_PATH}" "${!proxy_path_var:-/}")"

        # Determine default port based on protocol
        if [ "${PROXY_UPSTREAM_PROTOCOL}" == "https" ]; then
            local PROXY_UPSTREAM_PORT="${!proxy_https_port_var:-443}"
        else
            local PROXY_UPSTREAM_PORT="${!proxy_port_var:-80}"
        fi

        local PROXY_UPSTREAM_HOST="${!proxy_container_var}"
        local PROXY_UPSTREAM_PORT="${!proxy_port_var:-${PROXY_UPSTREAM_PORT}}"
        local PROXY_UPSTREAM_PROTOCOL="${!proxy_protocol_var:-${default_protocol}}"

        echo "   - Location path: ${PROXY_LOCATION_PATH}" >&2
        echo "   - Upstream host: ${PROXY_UPSTREAM_HOST}" >&2
        echo "   - Upstream port: ${PROXY_UPSTREAM_PORT}" >&2
        echo "   - Upstream protocol: ${PROXY_UPSTREAM_PROTOCOL}" >&2

        # Set VIRTUAL_DEST if the variable exists and is not empty
        local PROXY_DEST_VALUE="${!proxy_dest_var}"
        local PROXY_REWRITE_RULE=""
        if [ -n "$PROXY_DEST_VALUE" ]; then
            PROXY_REWRITE_RULE="rewrite ^${PROXY_LOCATION_PATH}(?:/(.*)$|$) ${PROXY_DEST_VALUE}\$1 break;"
            echo "   - Using rewrite rule: ${PROXY_REWRITE_RULE}" >&2
        fi

        local KEY_LOWER=${KEY,,}
        local CURRENT_LOCATION_BLOCK=$(render_template_string "${CONTAINER_TEMPLATES_NGINX_DIR}/proxy.location.nginx.conf")
        rendered_location_blocks="${rendered_location_blocks}"$'\n\n'"${CURRENT_LOCATION_BLOCK}"

        render_filtered_templates_in_dir "${source_path}" "${output_path}" "${KEY_LOWER}*.conf"
    done
}

function _process_root_proxy_template() {
    local output_path="${1}"
    local LOCATION_BLOCKS="$rendered_location_blocks"
    render_template "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/root.proxy.nginx.conf" "${output_path}"
}

if [[ "${CONTAINER_MODE}" == "proxy" ]]; then
    echo "[ENTRYPOINT.proxy] Configuring Nginx in proxy mode..."
    echo "[ENTRYPOINT.proxy] Using project base path: '${DOCKER_SERVICE_ABS_PATH}'"

    process_tpl "nginx-custom-snippets-proxy" _process_custom_proxy_snippet_templates

    # We have to force the processing here, because the nginx step has already processed it once without the location blocks
    allow_reprocessing_tpl "nginx-snippets-root"
    process_tpl "nginx-snippets-root" _process_root_proxy_template

    echo "[ENTRYPOINT.proxy] Nginx configuration completed for proxy mode"
fi
