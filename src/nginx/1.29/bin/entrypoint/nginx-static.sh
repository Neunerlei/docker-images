if [[ "$CONTAINER_MODE" == "static" ]]; then
    echo "[ENTRYPOINT.static] Configuring Nginx in static mode..."

    render_template "${NGINX_TEMPLATE_DIR}/service.root.static.nginx.conf" "${NGINX_SNIPPET_DIR}/service.root.nginx.conf"
fi
