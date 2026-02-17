#!/bin/bash

set -e

# The generic installer script that sets up common dependencies and directories
# It should run in the Dockerfile right after the base image is set up

declare current_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
declare entrypoint_dir="${current_dir}/container/entrypoint"

# Load the common environment variables
source "${entrypoint_dir}/common-env.sh"

# A list of dependencies to install using apt
declare dependencies_to_install=()

# Array to collect executables that need the environment wrapper.
declare -a scripts_to_wrap=()

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
)

# Prepend the default registrations to the command-line arguments.
# This allows the same loop to process both defaults and user-provided flags,
# with user flags naturally overriding defaults if they share the same name.
set -- "${default_flags[@]}" "$@"

# -----------------------------------------------------------------
# Argument Parsing & Manifest Generation
# -----------------------------------------------------------------
echo "[INSTALLER] Parsing template registrations and creating manifest..."
mkdir -p "$(dirname "$CONTAINER_TEMPLATE_MANIFEST")" && : >"$CONTAINER_TEMPLATE_MANIFEST"

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --tpl)
        if [[ -z "$2" ]]; then
            echo "[INSTALLER] Error: --tpl flag requires a name." >&2
            exit 1
        fi
        tpl_name="$2"
        shift 2

        # --- THIS IS THE KEY CHANGE: Use local arrays to collect sources ---
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

        # --- Determine Type, Serialize Sources, and Write Manifest ---
        tpl_type=""
        final_target_path=""
        sources_str=""
        extra="$tpl_pattern"

        if ((${#tpl_source_dirs[@]} > 0)); then
            tpl_type="dir"
            final_target_path="$tpl_target_dir"
            # Serialize the array into a |-separated string
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

        # Write to manifest
        printf "%s\t%s\t%s\t%s\n" "$tpl_type" "$tpl_name" "$sources_str" "$extra" >>"$CONTAINER_TEMPLATE_MANIFEST"

        # --- Create Dummy Files/Dirs and Symlinks ---
        work_path="${CONTAINER_WORK_DIR}/${tpl_name}"
        if [[ "$tpl_type" == "file" || "$tpl_type" == "cb_file" ]]; then
            echo "[INSTALLER] Creating dummy file at work path: ${work_path}"
            mkdir -p "$(dirname "$work_path")"
            touch "$work_path"
        else
            echo "[INSTALLER] Creating dummy directory at work path: ${work_path}"
            mkdir -p "$work_path"
        fi

        # Create the symlink
        echo "[INSTALLER] Creating symlink: ${final_target_path} -> ${work_path}"
        mkdir -p "$(dirname "$final_target_path")"

        # CRITICAL: If $final_target_path is a directory, we can not simply remove it
        # we must first move its content to the work_path, so that existing files are still there after linking
        # If $final_target_path is a file, we again must move it to the work_path (replacing our dummy file),
        # so that existing content is preserved until the entrypoint replaces it with the rendered template
        if [[ -d "$final_target_path" ]]; then
            # Move existing content into the work_path
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
        scripts_to_wrap+=("$2")
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

echo "[INSTALLER] Manifest created successfully at ${CONTAINER_TEMPLATE_MANIFEST}"

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
# Install bash wrapper
# -----------------------------------------------------------------
echo "[INSTALLER] Installing bash wrapper"

# IMPORTANT: This is black magic!
# Because we create environment variables in our entrypoint.sh they do not automatically
# become available in the default shell (which seems to be always "sh"), an neither in bash
# if you run a command like docker exec container_name npm run...
# Therefore I wrap bash with a custom script, that always loads our generated env variables
# And symlink sh into bash to work in both cases out of the box.

mv /bin/bash /bin/_bash
cat <<EOF >/bin/bash
#!/bin/_bash
[ -f "${CONTAINER_VARS_SCRIPT}" ] && . "${CONTAINER_VARS_SCRIPT}"
exec /bin/_bash "\$@"
EOF
chmod +x /bin/bash
rm -f /bin/sh
ln -s /bin/bash /bin/sh

# -----------------------------------------------------------------
# Additional bash wrappers
# -----------------------------------------------------------------
if [[ ${#scripts_to_wrap[@]} -gt 0 ]]; then
    echo "[INSTALLER] Applying wrappers to: ${scripts_to_wrap[*]}"
    for script_path in "${scripts_to_wrap[@]}"; do
        if [ -f "${script_path}" ]; then
            # Move the original executable
            mv "${script_path}" "${script_path}_orig"
            # Create the new wrapper script that invokes the original via our wrapped bash
            echo -e "#!/bin/bash\nexec ${script_path}_orig \"\$@\"" >"${script_path}"
            chmod +x "${script_path}"
        else
            echo "[INSTALLER] Warning: Cannot wrap non-existent script '${script_path}'. Skipping." >&2
        fi
    done
fi
