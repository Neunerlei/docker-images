#!/bin/bash

set -e

# =============================================================================
# Container Image Installer
# =============================================================================
#
# A build-time setup script that provisions the container with dependencies,
# configuration templates, and executable wrappers. It is designed to run
# exactly once during `docker build`, invoked from within a Dockerfile's
# RUN instruction with the common layer bind-mounted:
#
#   RUN --mount=type=bind,from=common,source=v1,target=/tmp/installer \
#       bash /tmp/installer/installer.sh [FLAGS...]
#
# The installer performs the following tasks, in order:
#
#   1. Parses all flags (both built-in defaults and caller-provided overrides)
#   2. Generates a template manifest for the entrypoint's runtime templating
#   3. Copies the common container scaffolding into /container/
#   4. Installs system packages via apt
#   5. Executes post-dependency commands (--exec-after-dependencies)
#   6. Generates executable wrappers (--env-wrap, --www-data-wrap)
#
# -----------------------------------------------------------------------------
# FLAGS
# -----------------------------------------------------------------------------
#
# --add-dependency PACKAGE
#
#     Registers a system package to be installed via apt. Duplicates are
#     silently ignored. The installer ships with a set of default packages
#     (bash, nginx, curl, ca-certificates, openssl, openssh-client, git,
#     nano, supervisor, gosu, zip, unzip, 7zip) that are always installed
#     unless explicitly removed.
#
#     Example:
#       --add-dependency "python3-pip"
#       --add-dependency "python3-venv"
#
#
# --remove-dependency PACKAGE
#
#     Removes a package from the installation list. This allows child images
#     to exclude default packages they don't need. If the package is not in
#     the list, a warning is printed and execution continues.
#
#     Example:
#       --remove-dependency "nano"
#
#
# --env-wrap PATH
#
#     Wraps an executable so that the container's runtime environment
#     variables are available when the binary is invoked — even from
#     "docker exec" sessions that bypass the entrypoint.
#
#     The original binary is moved to PATH_orig, and a shell wrapper is
#     generated at the original PATH. The wrapper sources the variable
#     file written by the entrypoint (/container/work/container-vars.sh)
#     before exec-ing the original binary.
#
#     /bin/bash is wrapped by default. Its wrapper uses a special shebang
#     (#!/bin/bash_orig) to avoid infinite recursion. /bin/sh is symlinked
#     to the wrapped /bin/bash.
#
#     Example:
#       --env-wrap "/opt/venv/bin/python"
#       --env-wrap "/opt/venv/bin/pip"
#
#
# --www-data-wrap PATH
#
#     Wraps an executable so that it always runs as the www-data user via
#     gosu. Can be combined with --env-wrap on the same binary; a single
#     unified wrapper is generated that handles both concerns.
#
#     Example:
#       --www-data-wrap "/usr/bin/composer"
#
#
# --exec-after-dependencies COMMAND
#
#     Registers a shell command to run after all apt packages have been
#     installed. Commands are executed in registration order via bash -c.
#     Useful for setup steps that depend on installed packages (e.g.,
#     creating a Python virtual environment after python3-venv is available).
#
#     Example:
#       --exec-after-dependencies "python3 -m venv /opt/venv"
#       --exec-after-dependencies "chown -R www-data:www-data /opt/venv"
#
#
# --tpl NAME [SUB-FLAGS...]
#
#     Registers a named template with the runtime templating system. At
#     container startup, the entrypoint processes registered templates by
#     substituting ${VAR_NAME} placeholders with environment variable values
#     and writing the result to the configured target location.
#
#     Templates are identified by NAME, which is used both as a key in the
#     manifest and as the working directory name under /container/work/NAME.
#     The target path is symlinked to the work path, so changes are reflected
#     automatically after the entrypoint renders the template.
#
#     Sub-flags (parsed until the next --tpl or top-level flag):
#
#       --source FILE
#           Path to a single template source file. Can be specified multiple
#           times for layered rendering (later sources can override earlier
#           ones). Mutually exclusive with --source-dir.
#
#       --source-dir DIR
#           Path to a directory of template source files. Can be specified
#           multiple times. Files are processed using the filename marker
#           system (e.g., .prod., .dev., .https.). Mutually exclusive
#           with --source.
#
#       --target FILE
#           The final destination path for a single-file template. Exactly
#           one of --target or --target-dir is required.
#
#       --target-dir DIR
#           The final destination directory for a directory-type template.
#           Exactly one of --target or --target-dir is required.
#
#       --pattern GLOB
#           Filename glob pattern for directory-type templates.
#           Default: "*"
#
#     If neither --source nor --source-dir is provided, the template is
#     a "callback" type (cb_file or cb_dir). These have no default
#     rendering behavior and require a callback function to be passed
#     to process_tpl at runtime.
#
#     Examples:
#
#       # Single file template
#       --tpl "nginx-conf" \
#         --source "/container/templates/nginx/nginx.conf" \
#         --target "/etc/nginx/nginx.conf"
#
#       # Directory of templates with filename filtering
#       --tpl "supervisor-config" \
#         --source-dir "/container/templates/supervisor/conf.d" \
#         --target-dir "/etc/supervisor/conf.d" \
#         --pattern "*.conf"
#
#       # Callback template (rendered by custom logic at runtime)
#       --tpl "nginx-error-pages" \
#         --target-dir "/var/www/errors"
#
# =============================================================================

declare current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
declare entrypoint_dir="${current_dir}/container/entrypoint"

# Load the common environment variables
source "${entrypoint_dir}/common-env.sh"

# A list of dependencies to install using apt
declare dependencies_to_install=()

# Arrays to collect script paths that need to be wrapped for various reasons.
declare -A scripts_wrap_env=()
declare -A scripts_wrap_www_data=()

# Array to collect commands to run after dependencies are installed ---
declare -a commands_to_exec_after_deps=()

# These flags will be prepended to the command-line arguments
# to ensure that certain default templates are always registered.
declare -a default_flags=(
    # Default dependencies
    "--add-dependency" "bash"
    "--add-dependency" "nginx"
    "--add-dependency" "curl"
    "--add-dependency" "ca-certificates"
    "--add-dependency" "openssl"
    "--add-dependency" "openssh-client"
    "--add-dependency" "git"
    "--add-dependency" "nano"
    "--add-dependency" "supervisor"
    "--add-dependency" "gosu"
    "--add-dependency" "zip"
    "--add-dependency" "unzip"
    "--add-dependency" "7zip"
    # NGINX
    "--tpl" "nginx-conf"
    "--source" "${CONTAINER_TEMPLATES_NGINX_DIR}/nginx.conf"
    "--target" "${NGINX_DIR}/nginx.conf"
    "--tpl" "nginx-mime-types"
    "--source" "${CONTAINER_TEMPLATES_NGINX_DIR}/mime.custom.types"
    "--target" "${NGINX_DIR}/mime.custom.types"
    "--tpl" "nginx-error-pages"
    "--target-dir" "${NGINX_ERROR_ROOT}"
    "--tpl" "nginx-snippets-root"
    "--source" "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/root.nginx.conf"
    "--target" "${NGINX_SNIPPETS_DIR}/root.nginx.conf"
    "--tpl" "nginx-snippets-errors"
    "--source" "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/errors.nginx.conf"
    "--target" "${NGINX_SNIPPETS_DIR}/errors.nginx.conf"
    "--tpl" "nginx-snippets-resolver"
    "--source" "${CONTAINER_TEMPLATES_NGINX_SNIPPETS_DIR}/resolver.nginx.conf"
    "--target" "${NGINX_SNIPPETS_DIR}/resolver.nginx.conf"
    "--tpl" "nginx-snippets-global-default"
    "--target" "${NGINX_SNIPPETS_DIR}/default.nginx.conf"
    "--tpl" "nginx-custom-snippets"
    "--source-dir" "${CONTAINER_CUSTOM_DIR}/nginx"
    "--target-dir" "${NGINX_CUSTOM_SNIPPETS_DIR}"
    "--pattern" "*.conf"
    "--tpl" "nginx-custom-snippets-global"
    "--source-dir" "${CONTAINER_CUSTOM_NGINX_DIR}/global"
    "--target-dir" "${NGINX_CUSTOM_SNIPPETS_GLOBAL_DIR}"
    "--pattern" "*.conf"
    "--tpl" "nginx-custom-snippets-location"
    "--source-dir" "${CONTAINER_CUSTOM_NGINX_DIR}/location"
    "--target-dir" "${NGINX_CUSTOM_SNIPPETS_LOCATION_DIR}"
    # SSL Certificates
    "--tpl" "ssl"
    "--target-dir" "${SSL_CERTS_DIR}/custom"
    # Supervisor
    "--tpl" "supervisor-conf"
    "--source" "${CONTAINER_TEMPLATES_DIR}/supervisor/supervisord.conf"
    "--target" "${SUPERVISOR_DIR}/supervisord.conf"
    "--tpl" "supervisor-config"
    "--source-dir" "${CONTAINER_TEMPLATES_DIR}/supervisor/conf.d"
    "--target-dir" "${SUPERVISOR_DIR}/conf.d"
    "--pattern" "*.conf"
    # Default script wrappers
    "--env-wrap" "/bin/bash"
)

# Prepend the default registrations to the command-line arguments.
# This allows the same loop to process both defaults and user-provided flags,
# with user flags naturally overriding defaults if they share the same name.
set -- "${default_flags[@]}" "$@"

# -----------------------------------------------------------------
# Argument Parsing & Template Collection
# -----------------------------------------------------------------
echo "[INSTALLER] Parsing template registrations..."

# Collected template registrations. Each entry is a tab-separated string:
#   type \t name \t sources_str \t extra
declare -a tpl_registrations=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --tpl)
        if [[ -z "$2" ]]; then
            echo "[INSTALLER] Error: --tpl flag requires a name." >&2
            exit 1
        fi
        tpl_name="$2"
        shift 2

        declare -a tpl_sources=()
        declare -a tpl_source_dirs=()
        tpl_target=""
        tpl_target_dir=""
        tpl_pattern="*"

        while [[ "$#" -gt 0 ]]; do
            flag_name="$1"
            flag_value="$2"
            case $flag_name in
            --source)
                tpl_sources+=("$flag_value")
                shift 2
                ;;
            --source-dir)
                tpl_source_dirs+=("$flag_value")
                shift 2
                ;;
            --target)
                tpl_target="$flag_value"
                shift 2
                ;;
            --target-dir)
                tpl_target_dir="$flag_value"
                shift 2
                ;;
            --pattern)
                tpl_pattern="$flag_value"
                shift 2
                ;;
            *) # This is not a sub-flag. Break the inner loop to return to the main parser.
                break ;;
            esac

            # If any of these is given, but has an empty value, it's an error
            if [[ -z "$flag_value" ]]; then
                echo "[INSTALLER] Error: ${flag_name} flag for --tpl ${tpl_name} requires a non-empty value." >&2
                exit 1
            fi
        done

        # --- Validation ---
        if ((${#tpl_sources[@]} > 0 && ${#tpl_source_dirs[@]} > 0)); then
            echo "[INSTALLER] Error: --source and --source-dir are mutually exclusive within a single --tpl block." >&2
            exit 1
        fi
        if { [[ -n "$tpl_target" && -n "$tpl_target_dir" ]] || [[ -z "$tpl_target$tpl_target_dir" ]]; }; then
            echo "[INSTALLER] Error: Must provide exactly one of --target or --target-dir for --tpl ${tpl_name}." >&2
            exit 1
        fi

        # --- Determine Type, Serialize Sources ---
        tpl_type=""
        final_target_path=""
        sources_str=""
        extra="$tpl_pattern"

        if ((${#tpl_source_dirs[@]} > 0)); then
            tpl_type="dir"
            final_target_path="$tpl_target_dir"
            printf -v sources_str '%s|' "${tpl_source_dirs[@]}"
            sources_str="${sources_str%?}"
        elif ((${#tpl_sources[@]} > 0)); then
            tpl_type="file"
            final_target_path="$tpl_target"
            extra=""
            printf -v sources_str '%s|' "${tpl_sources[@]}"
            sources_str="${sources_str%?}"
        elif [[ -n "$tpl_target_dir" ]]; then
            tpl_type="cb_dir"
            final_target_path="$tpl_target_dir"
            sources_str="_"
        else
            tpl_type="cb_file"
            final_target_path="$tpl_target"
            sources_str="_"
            extra=""
        fi

        # Collect the registration for later registry script generation.
        # Fields are separated by ASCII unit separator (0x1F) to avoid conflicts with
        # both | (used inside sources_str) and \t (ambiguous with empty extra field).
        tpl_registrations+=("${tpl_type}"$'\x1F'"${tpl_name}"$'\x1F'"${sources_str}"$'\x1F'"${extra}"$'\x1F'"${final_target_path}")

        # --- Create dummy work entry and symlink ---
        # The work directory entry serves as the symlink target. Subsequent build
        # steps (e.g., installing PHP extensions) may write files into the target
        # path, which now resolves through the symlink into CONTAINER_WORK_DIR.
        # The clean-state snapshot is taken on first boot by the entrypoint, so
        # all files written during the build are captured correctly.
        work_path="${CONTAINER_WORK_DIR}/${tpl_name}"
        if [[ "$tpl_type" == "file" || "$tpl_type" == "cb_file" ]]; then
            echo "[INSTALLER] Creating dummy file at work path: ${work_path}"
            mkdir -p "$(dirname "$work_path")"
            touch "$work_path"
        else
            echo "[INSTALLER] Creating dummy directory at work path: ${work_path}"
            mkdir -p "$work_path"
        fi

        # Create the symlink from the target location to the work directory.
        # If the target already exists we must preserve its content by moving
        # it into the work path before replacing the target with a symlink.
        echo "[INSTALLER] Creating symlink: ${final_target_path} -> ${work_path}"
        mkdir -p "$(dirname "$final_target_path")"
        if [[ -d "$final_target_path" ]]; then
            mkdir -p "$work_path"
            shopt -s dotglob
            mv "${final_target_path}/"* "$work_path/" 2>/dev/null || true
            shopt -u dotglob
        elif [[ -f "$final_target_path" ]]; then
            mv "$final_target_path" "$work_path"
        fi
        rm -rf "$final_target_path"
        ln -s "$work_path" "$final_target_path"

        ;;
    --add-dependency)
        if [[ ! " ${dependencies_to_install[@]} " =~ " ${2} " ]]; then
            dependencies_to_install+=("${2}")
        else
            echo "[INSTALLER] Warning: Dependency '${2}' is already in the list, skipping addition."
        fi
        shift 2
        ;;
    --remove-dependency)
        if [[ " ${dependencies_to_install[@]} " =~ " ${2} " ]]; then
            dependencies_to_install=("${dependencies_to_install[@]/$2/}")
        else
            echo "[INSTALLER] Warning: Dependency '${2}' not found in the list, cannot remove."
        fi
        shift 2
        ;;
    --env-wrap)
        scripts_wrap_env["$2"]=1
        shift 2
        ;;
    --www-data-wrap)
        scripts_wrap_www_data["$2"]=1
        shift 2
        ;;
    --exec-after-dependencies)
        commands_to_exec_after_deps+=("$2")
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done

# -----------------------------------------------------------------
# Generate installer-registry.sh
# -----------------------------------------------------------------
# Instead of writing a text manifest that has to be parsed back at runtime,
# we generate a self-contained shell script that populates the in-memory
# registries when sourced. It contains:
#   1. template_registry assignments (the associative array used by process_tpl)
#   2. container_custom_dir_child_registry extensions for dir-type custom sources
echo "[INSTALLER] Generating installer registry script at ${CONTAINER_INSTALLER_REGISTRY_SCRIPT}..."
mkdir -p "$(dirname "$CONTAINER_INSTALLER_REGISTRY_SCRIPT")"

cat > "$CONTAINER_INSTALLER_REGISTRY_SCRIPT" <<'REGISTRY_HEADER'
#!/bin/bash
# ==========================================================================
# AUTO-GENERATED by installer.sh — DO NOT EDIT
# ==========================================================================
# This script is sourced at container startup by the entrypoint. It
# populates the template_registry associative array and extends the
# container_custom_dir_child_registry with entries discovered from
# dir-type template registrations.
# ==========================================================================

REGISTRY_HEADER

{
    echo "# --- 1. Populate template_registry ---"
    for reg in "${tpl_registrations[@]}"; do
        IFS=$'\x1F' read -r _type _name _sources _extra _target <<<"$reg"
        # Build the registry value: tab-separated (type, name, sources, extra) as expected by process_tpl
        _reg_value="$(printf '%s\t%s\t%s\t%s' "$_type" "$_name" "$_sources" "$_extra")"
        # Escape single quotes in values (defensive; paths normally don't contain them)
        _name_esc="${_name//\'/\'\\\'\'}"
        _value_esc="${_reg_value//\'/\'\\\'\'}"
        echo "template_registry['${_name_esc}']='${_value_esc}'"
    done

    echo ""
    echo "# --- 2. Extend container_custom_dir_child_registry ---"
    for reg in "${tpl_registrations[@]}"; do
        IFS=$'\x1F' read -r _type _name _sources _extra _target <<<"$reg"
        if [[ "$_type" == "dir" ]]; then
            IFS='|' read -r -a _source_paths <<<"$_sources"
            for _source_path in "${_source_paths[@]}"; do
                if [[ "$_source_path" == "${CONTAINER_CUSTOM_DIR}"* ]]; then
                    echo "container_custom_dir_child_registry['${_source_path}']=1"
                fi
            done
        fi
    done
} >> "$CONTAINER_INSTALLER_REGISTRY_SCRIPT"

echo "[INSTALLER] Installer registry script generated successfully."


# -----------------------------------------------------------------
# Copy container directory
# -----------------------------------------------------------------
echo "[INSTALLER] Copying common container files"

cp -R "${current_dir}/container/." "${CONTAINER_DIR}/"
chmod +x "${CONTAINER_ENTRYPOINT_SCRIPT}"

# -----------------------------------------------------------------
# Ensure home permissions for www-data
# -----------------------------------------------------------------
echo "[INSTALLER] Ensuring home directory permissions for www-data user"
# If www-data user does not exist, die
if ! id -u www-data >/dev/null 2>&1; then
    echo "[INSTALLER] Error: www-data user does not exist in the container. Cannot set home directory permissions." >&2
    exit 1
fi
if [ ! -d "/var/www" ]; then
    mkdir -p "/var/www"
fi
chown -R www-data:www-data "/var/www"
if [ ! -d "/var/www/html" ]; then
    mkdir -p "/var/www/html"
fi
chown -R www-data:www-data "/var/www/html"

# -----------------------------------------------------------------
# Install common dependencies
# -----------------------------------------------------------------
echo "[INSTALLER] Installing common dependencies"

apt update
if [ $? -ne 0 ]; then
    echo "[INSTALLER] apt update failed!"
    exit 1
fi

apt upgrade -y
if [ $? -ne 0 ]; then
    echo "[INSTALLER.install-common-deps] apt upgrade failed!"
    exit 1
fi

echo "[INSTALLER] Installing packages: ${dependencies_to_install[*]}"

apt install -y "${dependencies_to_install[@]}"
if [ $? -ne 0 ]; then
    echo "[INSTALLER] apt install failed!"
    exit 1
fi

# In some root images, the /var/www/html directory might already contain files (e.g. index.html), which can cause permission issues and are not needed in our setup, so we clean it up to be safe
# Also, some dependencies we install (e.g. nginx) might also add files to this directory, which we do not need and can cause issues, so we clean it up again after installing dependencies to be safe
echo "[INSTALLER] Cleaning up the html directory"
rm -rf /var/www/html/*

# -----------------------------------------------------------------
# Execute post-dependency commands
# -----------------------------------------------------------------
if [[ ${#commands_to_exec_after_deps[@]} -gt 0 ]]; then
    echo "[INSTALLER] Executing post-dependency commands..."
    for cmd in "${commands_to_exec_after_deps[@]}"; do
        echo "  -> Running: ${cmd}"
        # Use 'bash -c' to properly handle commands with spaces, pipes, etc.
        bash -c "${cmd}"
        if [ $? -ne 0 ]; then
            echo "[INSTALLER] Error: Command failed: '${cmd}'" >&2
            exit 1
        fi
    done
fi

# -----------------------------------------------------------------
# Script Wrappers
# -----------------------------------------------------------------
echo "[INSTALLER] Processing script wrappers..."

declare -A scripts_to_wrap=()
for path in "${!scripts_wrap_env[@]}"; do scripts_to_wrap["$path"]=1; done
for path in "${!scripts_wrap_www_data[@]}"; do scripts_to_wrap["$path"]=1; done

if [[ ${#scripts_to_wrap[@]} -gt 0 ]]; then
    echo "[INSTALLER] Wrapping scripts: ${!scripts_to_wrap[*]}"
    for script_path in "${!scripts_to_wrap[@]}"; do
        if [ ! -f "${script_path}" ]; then
            echo "[INSTALLER] Warning: Cannot wrap non-existent script '${script_path}'. Skipping." >&2
            continue
        fi

        declare script_path_orig="${script_path%/*}/_${script_path##*/}"

        mv "${script_path}" "${script_path_orig}"

        # Build and write the wrapper
        cat <<WRAPPER >"${script_path}"
#!/bin/_bash
# ==========================================================================
# AUTO-GENERATED WRAPPER — DO NOT EDIT
# ==========================================================================
# This file was generated by the container installer script at build time.
# The original executable has been moved to:
#   ${script_path_orig}
#
$(if [[ -n "${scripts_wrap_env[$script_path]}" ]]; then
    echo "# This wrapper is responsible for sourcing the container's environment variables before executing the original binary."
    echo "# This ensures that any variables exported during the entrypoint boot sequence are available, even in contexts that bypass"
    echo "# the entrypoint (e.g., docker exec)."
    echo "#"
    echo "# The variable file is written by the entrypoint at:"
    echo "#   ${CONTAINER_VARS_SCRIPT}"
fi
if [[ -n "${scripts_wrap_www_data[$script_path]}" ]]; then
    if [[ -n "${scripts_wrap_env[$script_path]}" ]]; then
        echo "# Additionally, this wrapper enforces that the command always runs as the www-data user via gosu,"
        echo "# unless the current user is already www-data."
    else
        echo "# This wrapper is responsible for enforcing that the command always runs as the www-data user via gosu,"
        echo "# unless the current user is already www-data."
    fi
fi)
#
# For details, see: installer.sh in the image source repository.
# ==========================================================================
$(if [[ -n "${scripts_wrap_env[$script_path]}" ]]; then
            echo "[ -f \"${CONTAINER_VARS_SCRIPT}\" ] && . \"${CONTAINER_VARS_SCRIPT}\""
        fi)
$(if [[ -n "${scripts_wrap_www_data[$script_path]}" ]]; then
            echo "if [ \"\$(id -u)\" -eq \"\$(id -u www-data)\" ]; then"
            echo "  exec ${script_path_orig} \"\$@\""
            echo "else"
            echo "  gosu www-data ${script_path_orig} \"\$@\""
            echo "fi"
        else
            echo "exec ${script_path_orig} \"\$@\""
        fi)
WRAPPER
        chmod +x "${script_path}"
    done
fi

# Ensure /bin/sh always resolves through our wrapped bash
rm -f /bin/sh
ln -s /bin/bash /bin/sh
