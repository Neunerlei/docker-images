declare rendered_location_blocks=""

# Configures the per-service basic auth (PROXY_${KEY}_BASIC_AUTH, _1..n, _REALM) for one
# proxy service key: writes the password file and the generated snippet
# "${NGINX_CUSTOM_SNIPPETS_PROXY_DIR}/${KEY_LOWER}.auth.conf", which is picked up by the
# custom-snippet include of the location template.
#
# Sets the plain global "proxy_basic_auth_source" for the caller, telling it where this
# location's "auth_basic" comes from:
#   "generated" — the directives below were written into the generated snippet
#   "snippet"   — a custom snippet owns the authentication for this location
#   "none"      — no authentication is configured for this location
#
# NGINX does not allow the "auth_basic" directive twice in the same context. If one of
# the service's custom snippets declares its own "auth_basic" (checked against the
# already rendered snippet files), that snippet takes ownership of the authentication —
# the generated snippet then stays disabled, but the password file is still written so
# the snippet may reference it via "${NGINX_BASIC_AUTH_DIR}/proxy.${KEY_LOWER}.htpasswd".
function _configure_proxy_basic_auth() {
    local KEY="${1}"
    local KEY_LOWER="${2}"
    local auth_snippet="${NGINX_CUSTOM_SNIPPETS_PROXY_DIR}/${KEY_LOWER}.auth.conf"

    # Where this location's "auth_basic" comes from (read by the caller after
    # this function returns, e.g. for the Authorization header stripping)
    proxy_basic_auth_source="none"

    # The snippet must always exist, so it starts with the "not configured" variant
    printf '# basic auth is not configured\n' > "${auth_snippet}"

    mapfile -t credentials < <(collect_basic_auth_credentials "PROXY_${KEY}_BASIC_AUTH")
    if [[ ${#credentials[@]} -eq 0 ]]; then
        return 0
    fi

    local auth_file="${NGINX_BASIC_AUTH_DIR}/proxy.${KEY_LOWER}.htpasswd"
    if ! write_basic_auth_file "${auth_file}" "${credentials[@]}"; then
        echo "[ENTRYPOINT.proxy] Error: Invalid PROXY_${KEY}_BASIC_AUTH / PROXY_${KEY}_BASIC_AUTH_<n> value. Aborting." >&2
        exit 1
    fi

    # Skip our own generated snippet when looking for a snippet that takes
    # ownership (see snippet_manages_basic_auth): any "auth_basic" directive —
    # enabled or "off" — at one of the snippets' top level (the location
    # context the generated directives land in) takes ownership. A directive
    # NESTED in a sub-location (e.g. a health-check opt-out) must not disable
    # this service's generated auth. The "<key>.*conf" pattern is the same the
    # include below uses — the dot after the key is the key boundary, the
    # "conf" ending keeps unrelated files out, and snippets named exactly
    # "<key>.conf" keep working. find runs with -H: the snippets directory is
    # a SYMLINK into the work data, and without -H the default -P mode would
    # not descend into the symlinked root at all — the scan would silently see
    # zero candidates and every custom snippet would lose the ownership vote.
    while IFS= read -r -d '' candidate; do
        if [ "${candidate}" == "${auth_snippet}" ]; then
            continue
        fi
        if snippet_manages_basic_auth "${candidate}"; then
            echo "   - Custom snippet declares its own 'auth_basic' — skipping the generated directives, password file kept at ${auth_file}" >&2
            proxy_basic_auth_source="snippet"
            return 0
        fi
    done < <(find -H "${NGINX_CUSTOM_SNIPPETS_PROXY_DIR}" -maxdepth 1 -name "${KEY_LOWER}.*conf" -print0 | sort -z)

    local proxy_basic_auth_realm_var="PROXY_${KEY}_BASIC_AUTH_REALM"
    local auth_directives
    if ! auth_directives="$(build_basic_auth_directives "${!proxy_basic_auth_realm_var:-Restricted}" "${auth_file}")"; then
        echo "[ENTRYPOINT.proxy] Error: Invalid PROXY_${KEY}_BASIC_AUTH_REALM value. Aborting." >&2
        exit 1
    fi
    printf '%s\n' "${auth_directives}" > "${auth_snippet}"

    proxy_basic_auth_source="generated"

    echo "   - Basic auth enabled for ${#credentials[@]} user(s)" >&2
}

# Renders the location block for a single proxy service key, collects it in
# rendered_location_blocks and renders the service's custom snippets.
function _render_proxy_location_for_key() {
    local KEY="${1}"
    local KEY_LOWER="${2}"
    local source_path="${3}"
    local output_path="${4}"

    # Dynamically read the variables for this key
    local proxy_path_var="PROXY_${KEY}_PATH"
    local proxy_dest_var="PROXY_${KEY}_DEST"
    local proxy_port_var="PROXY_${KEY}_PORT"
    local proxy_https_port_var="PROXY_${KEY}_HTTPS_PORT"
    local proxy_container_var="PROXY_${KEY}_CONTAINER"
    local proxy_protocol_var="PROXY_${KEY}_PROTOCOL"

    # If proxy_protocol_var is not set, assume HTTP
    local PROXY_UPSTREAM_PROTOCOL="${!proxy_protocol_var:-http}"
    local PROXY_LOCATION_PATH="$(join_paths "${DOCKER_SERVICE_ABS_PATH}" "${!proxy_path_var:-/}")"

    # An explicit PROXY_<KEY>_PORT always wins; otherwise the port defaults by
    # protocol (PROXY_<KEY>_HTTPS_PORT or 443 for https, 80 for http)
    local PROXY_UPSTREAM_PORT
    if [ -n "${!proxy_port_var}" ]; then
        PROXY_UPSTREAM_PORT="${!proxy_port_var}"
    elif [ "${PROXY_UPSTREAM_PROTOCOL}" == "https" ]; then
        PROXY_UPSTREAM_PORT="${!proxy_https_port_var:-443}"
    else
        PROXY_UPSTREAM_PORT="80"
    fi

    local PROXY_UPSTREAM_HOST="${!proxy_container_var}"

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

    # Render the custom snippets for this service first, so _configure_proxy_basic_auth
    # can detect whether one of them declares its own "auth_basic". The pattern matches
    # "<key>.<anything>conf" — the dot after the key is the key boundary (keys sharing
    # a prefix do not match each other's files), the "conf" ending keeps unrelated
    # files out, and snippets named exactly "<key>.conf" keep working
    render_filtered_templates_in_dir "${source_path}" "${output_path}" "${KEY_LOWER}.*conf"

    # Legacy compatibility layer (expires 2027-11-16): files matching only the
    # OLD include pattern ("<key>*.conf" — e.g. "api-cors.conf", or another
    # key's "api_v2.rewrite.conf" overlapping this key's prefix) are bridged
    # back into this location: the layer renders them as
    # "<key>.legacy.<name>.conf" so the include glob above picks them up
    # again, exactly like before the pattern change, and warns for each of
    # them. LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME=true disables the
    # bridge and aborts the boot instead. Runs before
    # _configure_proxy_basic_auth so the auth ownership scan sees the bridge
    # renders.
    legacy_restore_legacy_proxy_snippet_includes "${KEY_LOWER}" "${source_path}" "${output_path}"

    _configure_proxy_basic_auth "${KEY}" "${KEY_LOWER}"

    # Strip the client's Authorization header toward the upstream whenever this
    # location is protected by GENERATED basic auth: the client authenticated
    # against THIS server, so the credentials it sent are this image's own
    # basic-auth credentials (global or per-proxy generated) — forwarding them
    # would leak them to the upstream, where they have no business. A custom
    # snippet that manages auth for this location decides for itself and stays
    # untouched ("snippet"); with "none", the strip only applies when the
    # GLOBAL generated auth is active — the server-level directives from
    # basicAuth.nginx.conf protect this location, too (a server snippet having
    # taken ownership would have reduced that file to a comment). Requests to
    # the image's own app runtime are untouched entirely: the directive only
    # ever exists inside proxy location blocks.
    PROXY_AUTHORIZATION_HEADER_DIRECTIVE=""
    if [ "${proxy_basic_auth_source}" == "generated" ] \
        || { [ "${proxy_basic_auth_source}" == "none" ] && snippet_manages_basic_auth "${NGINX_SNIPPETS_DIR}/basicAuth.nginx.conf"; }; then
        PROXY_AUTHORIZATION_HEADER_DIRECTIVE='proxy_set_header Authorization "";'
    fi

    local CURRENT_LOCATION_BLOCK=$(render_template_string "${CONTAINER_TEMPLATES_NGINX_DIR}/proxy.location.nginx.conf")
    rendered_location_blocks="${rendered_location_blocks}"$'\n\n'"${CURRENT_LOCATION_BLOCK}"
}

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

        _render_proxy_location_for_key "${KEY}" "${KEY,,}" "${source_path}" "${output_path}"
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
