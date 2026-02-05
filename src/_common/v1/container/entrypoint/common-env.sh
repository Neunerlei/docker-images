# Die if entrypoint_dir is not defined
if [[ -z "$entrypoint_dir" ]]; then
    echo "[ENTRYPOINT.common-env] 'entrypoint_dir' is not defined. Cannot proceed." >&2
    exit 1
fi

source "${entrypoint_dir}/util.d/find-environment.sh"
source "${entrypoint_dir}/util.d/join-paths.sh"
export ENVIRONMENT="$(find_environment)"

# Define routing settings
export DOCKER_PROJECT_HOST="${DOCKER_PROJECT_HOST:-localhost}"
export DOCKER_PROJECT_PROTOCOL="${DOCKER_PROJECT_PROTOCOL:-http}"
export DOCKER_PROJECT_PATH="${DOCKER_PROJECT_PATH:-/}"
export DOCKER_SERVICE_PROTOCOL="${DOCKER_SERVICE_PROTOCOL:-${DOCKER_PROJECT_PROTOCOL}}"
export DOCKER_SERVICE_PATH="${DOCKER_SERVICE_PATH:-/}"
export DOCKER_SERVICE_ABS_PATH="$(join_paths "${DOCKER_PROJECT_PATH:-/}" "${DOCKER_SERVICE_PATH}")"

# Define static, well-known directories inside the container
export CONTAINER_DIR="/container"
export CONTAINER_TEMPLATES_DIR="${CONTAINER_DIR}/templates"
export CONTAINER_TEMPLATES_NGINX_DIR="${CONTAINER_TEMPLATES_DIR}/nginx"
export CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR="${CONTAINER_TEMPLATES_NGINX_DIR}/snippets"
export CONTAINER_TEMPLATE_MANIFEST="${CONTAINER_DIR}/template.manifest"
export CONTAINER_ENTRYPOINT_DIR="${CONTAINER_DIR}/entrypoint"
export CONTAINER_ENTRYPOINT_SCRIPT="${CONTAINER_ENTRYPOINT_DIR}/entrypoint.sh"
export CONTAINER_WORK_DIR="${CONTAINER_DIR}/work"
export CONTAINER_VARS_SCRIPT="${CONTAINER_WORK_DIR}/container-vars.sh"
export CONTAINER_CUSTOM_DIR="${CONTAINER_DIR}/custom"
export CONTAINER_CUSTOM_ENTRYPOINT_DIR="${CONTAINER_CUSTOM_DIR}/entrypoint"
export CONTAINER_CUSTOM_SSL_CERTS_DIR="${CONTAINER_CUSTOM_DIR}/certs"
export CONTAINER_CUSTOM_NGINX_DIR="${CONTAINER_CUSTOM_DIR}/nginx"
export NGINX_DIR="/etc/nginx"
export NGINX_SNIPPETS_DIR="${NGINX_DIR}/snippets"
export NGINX_CUSTOM_SNIPPETS_DIR="${NGINX_SNIPPETS_DIR}/custom.d"
export NGINX_CUSTOM_SNIPPETS_GLOBAL_DIR="${NGINX_SNIPPETS_DIR}/global.d"
export NGINX_CUSTOM_SNIPPETS_LOCATION_DIR="${NGINX_SNIPPETS_DIR}/location.d"
export NGINX_SERVE_ROOT="${NGINX_SERVE_ROOT:-"/var/www/html"}"
export NGINX_DOC_ROOT="${NGINX_DOC_ROOT:-"/var/www/html/public"}"
export NGINX_ERROR_ROOT="/var/www/errors"
export SSL_CERTS_DIR="/etc/ssl/certs"
export SUPERVISOR_DIR="/etc/supervisor"

# Define Nginx settings
export NGINX_CLIENT_MAX_BODY_SIZE="${NGINX_CLIENT_MAX_BODY_SIZE:-${MAX_UPLOAD_SIZE:-"100M"}}"
export NGINX_CERT_PATH="${NGINX_CERT_PATH:-"${SSL_CERTS_DIR}/custom/cert.pem"}"
export NGINX_KEY_PATH="${NGINX_KEY_PATH:-"${SSL_CERTS_DIR}/custom/key.pem"}"

# Define Nginx proxy timeouts
calculate_keepalive_timeout() {
  local connect_timeout="${NGINX_PROXY_CONNECT_TIMEOUT:-5s}"
  local read_timeout="${NGINX_PROXY_READ_TIMEOUT:-60s}"
  local send_timeout="${NGINX_PROXY_SEND_TIMEOUT:-60s}"

  # Convert timeouts to seconds
  local connect_seconds=$(echo "$connect_timeout" | sed 's/[^0-9]//g')
  local read_seconds=$(echo "$read_timeout" | sed 's/[^0-9]//g')
  local send_seconds=$(echo "$send_timeout" | sed 's/[^0-9]//g')

  # Calculate the maximum timeout
  local max_timeout=$((connect_seconds + read_seconds + send_seconds))

  echo "${max_timeout}s"
}
export NGINX_PROXY_CONNECT_TIMEOUT="${NGINX_PROXY_CONNECT_TIMEOUT:-5s}"
export NGINX_PROXY_READ_TIMEOUT="${NGINX_PROXY_READ_TIMEOUT:-60s}"
export NGINX_PROXY_SEND_TIMEOUT="${NGINX_PROXY_SEND_TIMEOUT:-60s}"
export NGINX_KEEPALIVE_TIMEOUT="${NGINX_KEEPALIVE_TIMEOUT:-$(calculate_keepalive_timeout)}"
