# Check if all external environment variables are set
declare required_vars=( "CONTAINER_TEMPLATE_DIR" "CONTAINER_BIN_DIR")
for var_name in "${required_vars[@]}"; do
  if [ -z "${!var_name}" ]; then
    echo "[ENTRYPOINT] ERROR: Required environment variable '${var_name}' is not set."
    exit 1
  fi
done

export ENVIRONMENT="$(find_environment)"
export CONTAINER_VARS_SCRIPT="/etc/container-vars.sh"
export CONTAINER_CERTS_DIR="/etc/ssl/certs"
export NGINX_DIR="/etc/nginx"
export NGINX_DOC_ROOT="${NGINX_DOC_ROOT:-"/var/www/html/public"}"
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
export NGINX_CERT_PATH="${NGINX_CERT_PATH:-"${CONTAINER_CERTS_DIR}/cert.pem"}"
export NGINX_KEY_PATH="${NGINX_KEY_PATH:-"${CONTAINER_CERTS_DIR}/key.pem"}"
export NGINX_ERRORS_DIR="${NGINX_ERRORS_DIR:-"/var/www/errors"}"
export NGINX_SITES_ENABLED_DIR="${NGINX_DIR}/sites-enabled"
export NGINX_SITES_AVAILABLE_DIR="${NGINX_DIR}/sites-available"
export NGINX_SNIPPET_DIR="${NGINX_DIR}/snippets"
export NGINX_SERVICE_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/service.d"
export NGINX_GLOBAL_SNIPPET_DIR="${NGINX_SNIPPET_DIR}/global.d"
export NGINX_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/nginx"
export NGINX_CUSTOM_TEMPLATE_DIR="${NGINX_TEMPLATE_DIR}/custom"
export NGINX_CUSTOM_GLOBAL_TEMPLATE_DIR="${NGINX_CUSTOM_TEMPLATE_DIR}/global"
export DOCKER_PROJECT_HOST="${DOCKER_PROJECT_HOST:-localhost}"
export DOCKER_PROJECT_PROTOCOL="${DOCKER_PROJECT_PROTOCOL:-http}"
export DOCKER_PROJECT_PATH="${DOCKER_PROJECT_PATH:-/}"
export DOCKER_SERVICE_PROTOCOL="${DOCKER_SERVICE_PROTOCOL:-${DOCKER_PROJECT_PROTOCOL}}"
export DOCKER_SERVICE_PATH="${DOCKER_SERVICE_PATH:-/}"
export DOCKER_SERVICE_ABS_PATH="$(join_paths "${DOCKER_PROJECT_PATH:-/}" "${DOCKER_SERVICE_PATH}")"
export SUPERVISOR_TEMPLATE_DIR="${CONTAINER_TEMPLATE_DIR}/supervisor"
export SUPERVISOR_CONFIG_TEMPLATE_DIR="${SUPERVISOR_TEMPLATE_DIR}/conf.d"
export SUPERVISOR_DIR="/etc/supervisor"
export SUPERVISOR_CONFIG_DIR="${SUPERVISOR_DIR}/conf.d"
