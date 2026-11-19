# Die if entrypoint_dir is not defined
if [[ -z "$entrypoint_dir" ]]; then
    echo "[ENTRYPOINT.common-env] 'entrypoint_dir' is not defined. Cannot proceed." >&2
    exit 1
fi

source "${entrypoint_dir}/util.d/find-environment.sh"
source "${entrypoint_dir}/util.d/join-paths.sh"
source "${entrypoint_dir}/util.d/default-var.sh"

# The ENVIRONMENT normalization is the ONE user-input derivation that runs at
# source time: step 005 (custom dir scaffolding) reads it before the
# environment orchestrator (step.d/015-environment.sh) runs. derive_common_env
# repeats it as its first line, so a value from a custom env file is
# normalized too — a .env with ENVIRONMENT=dev really selects .dev. markers.
export ENVIRONMENT="$(find_environment)"

# This file is sourced by the entrypoint (before every step) AND by the
# installer during the image build. At source time it must only export
# CONSTANTS — expressions with no user input — and define functions. Every
# value derived from a user-settable variable lives in derive_common_env()
# below, which the environment orchestrator calls once per environment-file
# pass (see step.d/015-environment.sh). The installer gets the constants and
# never calls the function.

# Define static, well-known directories inside the container
export CONTAINER_DIR="/container"
export CONTAINER_BIN_DIR="${CONTAINER_DIR}/bin"
export PATH="${CONTAINER_BIN_DIR}:${PATH}"
export CONTAINER_TEMPLATES_DIR="${CONTAINER_DIR}/templates"
export CONTAINER_TEMPLATES_NGINX_DIR="${CONTAINER_TEMPLATES_DIR}/nginx"
export CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR="${CONTAINER_TEMPLATES_NGINX_DIR}/snippets"
export CONTAINER_INSTALLER_REGISTRY_SCRIPT="${CONTAINER_DIR}/installer-registry.sh"
export CONTAINER_ENTRYPOINT_DIR="${CONTAINER_DIR}/entrypoint"
export CONTAINER_ENTRYPOINT_SCRIPT="${CONTAINER_ENTRYPOINT_DIR}/entrypoint.sh"
export CONTAINER_WORK_DIR="${CONTAINER_DIR}/work"
# All template/entrypoint work data lives in this sub-directory of the work directory
export CONTAINER_WORK_DATA_DIR="${CONTAINER_WORK_DIR}/data"
# The home directory of the www-data service user. It deliberately lives in the
# work directory: that is the one location guaranteed to be writable on every
# deployment — including read-only filesystems, where /container/work is the
# documented writable mount. Unlike work/data it is NOT reset on boot, so
# caches and dotfiles survive container restarts. Read-only constant: the path
# is baked into the image at build time (passwd entry, supervisor configs),
# so overriding it at runtime would strand that baked state.
export CONTAINER_WWW_DATA_HOME_DIR="${CONTAINER_WORK_DIR}/www-data-home"
# Pristine build-time state of the work data. During the image build, work/data
# is a symlink to this directory, so everything written "into the work data" —
# by the installer, later build steps or child images — lands here. Every boot
# resets the real work data from it (see entrypoint.sh). Lives OUTSIDE the work
# directory so that a mount over the work directory can not shadow it.
export CONTAINER_WORK_STAGING_DIR="${CONTAINER_DIR}/work-data-staging"
# Marker file written by every build-mode run (see entrypoint.sh). Like the
# staging area it lives in the image layer — deliberately NOT inside the work
# directory: a work-dir mount (tmpfs, emptyDir, named volume) would hide a
# marker placed there, and everything in work/data is deleted by the boot
# reset anyway. Its presence at boot means the image ran build mode during
# its build and must not be booted as a final image.
export CONTAINER_BUILD_MODE_MARKER="${CONTAINER_DIR}/build-mode.marker"
export CONTAINER_VARS_SCRIPT="${CONTAINER_WORK_DIR}/container-vars.sh"
export CONTAINER_CUSTOM_DIR="${CONTAINER_DIR}/custom"
export CONTAINER_CUSTOM_ENV_DIR="${CONTAINER_CUSTOM_DIR}/env"
export CONTAINER_CUSTOM_ENTRYPOINT_DIR="${CONTAINER_CUSTOM_DIR}/entrypoint"
export CONTAINER_CUSTOM_SSL_CERTS_DIR="${CONTAINER_CUSTOM_DIR}/certs"
export CONTAINER_CUSTOM_NGINX_DIR="${CONTAINER_CUSTOM_DIR}/nginx"
export NGINX_DIR="/etc/nginx"
export NGINX_SNIPPETS_DIR="${NGINX_DIR}/snippets"
# Basic auth password files are generated at runtime, so they must live in the
# work directory — the only guaranteed-writable location on a read-only filesystem
export NGINX_BASIC_AUTH_DIR="${CONTAINER_WORK_DIR}/nginx-basic-auth"
export NGINX_CUSTOM_SNIPPETS_DIR="${NGINX_SNIPPETS_DIR}/custom.d"
export NGINX_CUSTOM_SNIPPETS_GLOBAL_DIR="${NGINX_SNIPPETS_DIR}/global.d"
export NGINX_CUSTOM_SNIPPETS_LOCATION_DIR="${NGINX_SNIPPETS_DIR}/location.d"
export NGINX_ERROR_ROOT="/var/www/errors"
export SSL_CERTS_DIR="/etc/ssl/certs"
export SUPERVISOR_DIR="/etc/supervisor"

# Calculate max upload size defaults
parse_filesize_string_to_bytes() {
    local size="${1^^}"  # uppercase the whole input (requires bash 4+)
    local number="${size//[^0-9]/}"
    local unit="${size//[0-9]/}"

    case "$unit" in
        K)  echo $((number * 1024)) ;;
        M)  echo $((number * 1024 * 1024)) ;;
        G)  echo $((number * 1024 * 1024 * 1024)) ;;
        "")  echo "$number" ;;
        *)
            echo "Unsupported unit: '$unit'" >&2
            return 1
            ;;
    esac
}

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

# Define the Nginx DNS resolvers. Nginx only consults them for dynamic upstream
# names (a variable in proxy_pass, "server ... resolve", ...) which it resolves
# on every request — for those it never reads /etc/resolv.conf on its own.
# The servers are therefore detected from /etc/resolv.conf on every boot, so
# the same image works everywhere: Docker's embedded DNS (127.0.0.11) on
# user-defined networks, the cluster DNS in Kubernetes, Podman's runtime DNS,
# the host resolvers with host networking, ...
detect_dns_resolvers() {
    local key nameserver found=""

    # Without a readable resolv.conf we return nothing and let the caller
    # fall back to the Docker default below
    [ -r /etc/resolv.conf ] || return 0

    # The "|| [ -n ... ]" keeps the LAST line when /etc/resolv.conf lacks a
    # trailing newline: plain "read" loses it (read reports EOF failure after
    # the data was already assigned), silently dropping the final nameserver
    # and falling back to the Docker default instead
    while read -r key nameserver _ || [ -n "${key}" ]; do
        [[ "${key}" == "nameserver" ]] || continue
        [ -n "${nameserver}" ] || continue
        # Scoped IPv6 addresses (fe80::1%eth0) are not valid Nginx resolvers
        case "${nameserver}" in *%*) continue ;; esac
        # Nginx expects IPv6 resolver addresses in square brackets
        case "${nameserver}" in *:*) nameserver="[${nameserver}]" ;; esac
        found="${found}${found:+ }${nameserver}"
    done < /etc/resolv.conf

    printf '%s' "${found}"
}

# Derives every environment value that depends on user input.
#
# The environment orchestrator (step.d/015-environment.sh) calls this once
# per pass: before the custom env files load (so the rest of the pipeline and
# ${VAR} references inside the env files see sane values), after the static
# *.env pass and after the dynamic *.env.sh pass — so values provided in
# /container/custom/env/ reach these derivations instead of being computed
# from the defaults forever.
#
# Inputs are defaulted BEFORE anything derived from them (routing block
# before ABS_PATH, proxy timeouts before keepalive, upload size before the
# nginx body size). Values computed unconditionally (MAX_UPLOAD_SIZE_BYTES,
# DOCKER_SERVICE_ABS_PATH — both documented read-only) are simply recomputed
# on every pass. Everything else goes through default_var, which recomputes
# a default that is still in place and never touches a user-set value.
derive_common_env() {
    export ENVIRONMENT="$(find_environment)"

    # Define routing settings
    default_var DOCKER_PROJECT_HOST "localhost"
    default_var DOCKER_PROJECT_PROTOCOL "http"
    default_var DOCKER_PROJECT_PATH "/"
    default_var DOCKER_SERVICE_PROTOCOL "${DOCKER_PROJECT_PROTOCOL}"
    default_var DOCKER_SERVICE_PATH "/"
    export DOCKER_SERVICE_ABS_PATH="$(join_paths "${DOCKER_PROJECT_PATH:-/}" "${DOCKER_SERVICE_PATH}")"

    # Document roots (overridable, and consumed by the user-owned directories
    # registry in step 070 — which runs after this, so a custom env file's
    # serve root really gets its ownership fixed)
    default_var NGINX_SERVE_ROOT "/var/www/html"
    default_var NGINX_DOC_ROOT "/var/www/html/public"

    # Calculate max upload size
    default_var MAX_UPLOAD_SIZE "100M"
    if ! MAX_UPLOAD_SIZE_BYTES="$(parse_filesize_string_to_bytes "${MAX_UPLOAD_SIZE}")" || [ -z "${MAX_UPLOAD_SIZE_BYTES}" ]; then
        echo "[ENTRYPOINT] Warning: Failed to parse MAX_UPLOAD_SIZE '${MAX_UPLOAD_SIZE}'. Defaulting to 104857600 bytes (100M)." >&2
        MAX_UPLOAD_SIZE_BYTES=104857600
    fi
    export MAX_UPLOAD_SIZE_BYTES

    # Define Nginx settings
    default_var NGINX_CLIENT_MAX_BODY_SIZE "${MAX_UPLOAD_SIZE}"
    default_var NGINX_CERT_PATH "${SSL_CERTS_DIR}/custom/cert.pem"
    default_var NGINX_KEY_PATH "${SSL_CERTS_DIR}/custom/key.pem"

    # Define Nginx proxy timeouts
    default_var NGINX_PROXY_CONNECT_TIMEOUT "5s"
    default_var NGINX_PROXY_READ_TIMEOUT "60s"
    default_var NGINX_PROXY_SEND_TIMEOUT "60s"
    default_var NGINX_KEEPALIVE_TIMEOUT "$(calculate_keepalive_timeout)"

    # Define the Nginx DNS resolvers (detected from /etc/resolv.conf, with
    # the embedded Docker DNS as fallback for containers without a readable
    # resolv.conf). Deliberately NOT two chained default_var calls: the
    # second would see the value the first just recorded as "still the
    # default" and clobber a successful detection with the fallback. The
    # fallback is resolved BEFORE the one tracked default_var.
    local detected_dns_resolvers
    detected_dns_resolvers="$(detect_dns_resolvers)"
    default_var NGINX_RESOLVER "${detected_dns_resolvers:-127.0.0.11}"
    default_var NGINX_RESOLVER_VALID_TIMEOUT "30s"
    default_var NGINX_RESOLVER_TIMEOUT "5s"
}
