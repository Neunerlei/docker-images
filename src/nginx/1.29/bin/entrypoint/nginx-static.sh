if [[ "$CONTAINER_MODE" == "static" ]]; then
    echo "[ENTRYPOINT.static] Configuring Nginx in static mode..."

    render_template 'NGINX_DOC_ROOT' /etc/app/config.tpl/nginx/service.static.snippet.tpl.nginx.conf /etc/nginx/snippets/service.nginx.conf
fi
