function _process_root_static_template() {
    local output_path="${1}"
    render_template "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/root.static.nginx.conf" "${output_path}"
}

if [[ "${CONTAINER_MODE}" == "static" ]]; then
    echo "[ENTRYPOINT.static] Configuring Nginx in static mode..."

    # We have to force the processing here, because the nginx step has already processed it
    allow_reprocessing_tpl "nginx-snippets-root"
    process_tpl "nginx-snippets-root" _process_root_static_template
fi
