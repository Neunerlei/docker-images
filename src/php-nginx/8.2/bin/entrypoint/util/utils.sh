#!/bin/bash

# The same as render_template but automatically uses all environment variables.
#
# Usage:
#   render_template_all_vars "path/to/template.tpl" "path/to/output.conf" ["ADDITIONAL_VAR1 ADDITIONAL_VAR2"]
#
render_template_all_vars() {
    local template_file="$1"
    local output_file="$2"
    local additional_vars="$3"
    local all_vars
    all_vars="$(get_all_vars)"
    if [ -n "$additional_vars" ]; then
        all_vars="${all_vars} ${additional_vars}"
    fi
    render_template "$all_vars" "$template_file" "$output_file"
}

# Replaces the given list of placeholders in the template file,
# and dumps it into the output file; the placeholders in the template file should look like "${VAR_NAME}".
# The variable names to substitute should be provided as a space-separated string.
# The values are taken from the current environment, with the same name as the variable names.
#
# Usage:
#   render_template 'VAR_NAME ANOTHER_VAR_NAME' "path/to/template.tpl" "path/to/output.conf"
#
render_template() {
    local vars_to_substitute="$1"
    local template_file="$2"
    local output_file="$3"
    local rendered
    rendered=$(render_template_string "$vars_to_substitute" "$template_file")
    echo "$rendered" > "$output_file"
}

# Replaces the given list of placeholders in the template file,
# and returns it into the stdout; the placeholders in the template file should look like "${VAR_NAME}".
# The variable names to substitute should be provided as a space-separated string.
# The values are taken from the current environment, with the same name as the variable names.
#
# Usage:
#   YOUR_VAR=$(render_template_string 'VAR_NAME ANOTHER_VAR_NAME' "path/to/template.tpl")
#
render_template_string() {
    local vars_to_substitute="$1"
    local template_file="$2"
    local line

    if [ ! -f "$template_file" ]; then
        echo "Template file not found: $template_file" >&2
        return 1
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        # If we find a line with [[DEBUG_VARS]], print all variables for debugging and exit immediately
        if [[ "$line" == *'[[DEBUG_VARS]]'* ]]; then
            echo "DEBUG_VARS detected in template: '$template_file'. Current variables that can be substituted:" >&2
            # Iterate the vars to substitute and print their values
            for var_name in $vars_to_substitute; do
                local value="${!var_name}"
                echo "  - \${$var_name} = ${value}" >&2
            done
            exit 1
        fi

        # Only check for variables if the line contains a '${' characters (which marks the start of a variable)
        if [[ "$line" != *'${'* ]]; then
            printf '%s\n' "$line"
            continue
        fi

        for var_name in $vars_to_substitute; do
            # Get the value of the variable using indirect expansion
            local value="${!var_name}"

            # Construct the placeholder string, e.g., "${VAR_NAME}"
            local placeholder="\${${var_name}}"

            # Use Bash's native string replacement.
            # It's safe against special characters in the 'value'.
            line="${line//"$placeholder"/"$value"}"
        done

        # Print the modified line to the output file
        printf '%s\n' "$line"
    done < "$template_file"
}

# Joins multiple path segments into a single normalized path.
# It ensures that there are no duplicate slashes, and that the path starts with a single slash.
# Trailing slashes are removed unless the path is just "/".
# Usage:
#   joined_path=$(join_paths "/path/to" "some//dir/" "/file.txt")
#
join_paths() {
    local path
    path=$( (IFS=/; echo "$*") | tr -s / )
    [[ -n "$path" && "${path:0:1}" != "/" ]] && path="/${path}"
    [[ "${#path}" -gt 1 && "${path: -1}" == "/" ]] && path="${path%/}"
    echo "${path:-/}"
}

# Returns all environment variable names as a space-separated string.
# Usage:
#   render_template "$(get_all_vars)" "path/to/template.tpl" "path/to/output.conf"
#
get_all_vars() {
    local bp='^(BASH_.*|BASH|BASHPID|EPOCHREALTIME|EPOCHSECONDS|FUNCNAME|LINENO|RANDOM|SRANDOM|SECONDS|PIPESTATUS|PWD|OLDPWD|SHLVL|UID|EUID|PPID|GROUPS|SHELLOPTS|BASHOPTS|DIRSTACK|HISTCMD|OPTERR|OPTIND|COMP_.*|_|bp|cep|MACHTYPE)$'
    local cep='^(HOME|PATH|SHELL|TERM|USER|LOGNAME|LANG|LC_.*|PS[1-4]|IFS|OSTYPE|HOSTTYPE|HOSTNAME|EDITOR|PAGER)$'

    compgen -v \
    | grep -E -v "$bp" \
    | grep -E -v "$cep" \
    | sort
}

# Determines the application environment based on the ENVIRONMENT environment variable.
# If ENVIRONMENT is not set, defaults to "production".
# Normalizes common values like "prod" to "production" and "dev" to "development".
# Usage:
#   environment=$(find_environment)
#
find_environment() {
  local environment="${ENVIRONMENT:-production}"
  case "${environment,,}" in
    "prod"|"production")
      echo "production"
      ;;
    "dev"|"development")
      echo "development"
      ;;
    *)
      echo "${environment,,}"
      ;;
  esac
}

# Renders all templates in the given directory to the output directory,
# applying filtering based on filename markers like .prod. and .https.
# The optional third argument is a pattern to match filenames (default is "*").
# Usage:
#   render_filtered_templates_in_dir "path/to/templates" "path/to/output" "[pattern]"
#
render_filtered_templates_in_dir() {
  local template_dir="$1"
  local output_dir="$2"
  local pattern="${3:-"*"}"

  echo "Processing custom snippets from ${template_dir}, matching '${pattern}'..." >&2

  # Clear out old snippets to ensure a clean slate
  rm -f "${output_dir}/${pattern}"

  for template_path in $(find "${template_dir}" -maxdepth 1 -name "${pattern}" | sort); do
    filename=$(basename "$template_path")

    # Check for .prod. marker
    if [[ "$filename" == *".prod."* ]] && [[ "${ENVIRONMENT}" != "production" ]]; then
      echo " - Skipping '${filename}' (requires ENVIRONMENT=production)"
      continue
    fi

    # Check for .dev. marker
    if [[ "$filename" == *".dev."* ]] && [[ "${ENVIRONMENT}" != "development" ]]; then
      echo " - Skipping '${filename}' (requires ENVIRONMENT=development)"
      continue
    fi

    # Check for .https. marker
    if [[ "$filename" == *".https."* ]] && [[ "${DOCKER_SERVICE_PROTOCOL}" != "https" ]]; then
      echo " - Skipping '${filename}' (requires DOCKER_SERVICE_PROTOCOL=https)"
      continue
    fi

    echo " - Rendering '${filename}'"
    render_template_all_vars "${template_path}" "${output_dir}/${filename}"
  done
}
