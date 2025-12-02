#!/bin/bash

# The same as render_template_with but automatically uses all environment variables.
#
# Usage:
#   render_template "path/to/template.tpl" "path/to/output.conf" ["ADDITIONAL_VAR1 ADDITIONAL_VAR2"]
#
render_template() {
    local template_file="$1"
    local output_file="$2"
    local additional_vars="$3"
    render_template_with "$(get_all_vars)" "$template_file" "$output_file"
}

# Replaces the given list of placeholders in the template file,
# and dumps it into the output file; the placeholders in the template file should look like "${VAR_NAME}".
# The variable names to substitute should be provided as a space-separated string.
# The values are taken from the current environment, with the same name as the variable names.
#
# Usage:
#   render_template_with 'VAR_NAME ANOTHER_VAR_NAME' "path/to/template.tpl" "path/to/output.conf"
#
render_template_with() {
    local vars_to_substitute="$1"
    local template_file="$2"
    local output_file="$3"
    echo "$(render_template_string_with "$vars_to_substitute" "$template_file")" > "$output_file"
}

# The same as render_template_string_with but automatically uses all environment variables.

# Usage:
#   YOUR_VAR=$(render_template_string "path/to/template.tpl")
#
render_template_string() {
    local template_file="$1"
    render_template_string_with "$(get_all_vars)" "$template_file"
}

# Replaces the given list of placeholders in the template file,
# and returns it into the stdout; the placeholders in the template file should look like "${VAR_NAME}".
# The variable names to substitute should be provided as a space-separated string.
# The values are taken from the current environment, with the same name as the variable names.
#
# Usage:
#   YOUR_VAR=$(render_template_string_with 'VAR_NAME ANOTHER_VAR_NAME' "path/to/template.tpl")
#
render_template_string_with() {
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

# Iterates over files in the given directory, filtering them based on filename markers
# like .prod., .dev., and .https., and calls the provided callback function for each file that passes the filters.
# The optional third argument is a pattern to match filenames (default is "*").
# The optional fourth argument is additional arguments to pass to the callback function.
# Usage:
#   for_each_filtered_file_in_dir "path/to/dir" "callback_function" "[pattern]" "[additional_args]"
#
for_each_filtered_file_in_dir() {
  local read_dir="$1"
  local callback="$2"
  local pattern="${3:-"*"}"
  local additional_args="$4"

  if [[ -z "$callback" ]]; then
    echo "No callback function provided to for_each_filtered_file_in_dir" >&2
    return 1
  fi

  echo "Processing files from ${read_dir}, matching '${pattern}'..." >&2

  for file_path in $(find "${read_dir}" -maxdepth 1 -name "${pattern}" | sort); do
    filename=$(basename "$file_path")

    # Check for .prod. marker
    if [[ "$filename" == *".prod."* ]] && [[ "${ENVIRONMENT}" != "production" ]]; then
      echo " - Skipping '${filename}' (requires ENVIRONMENT=production)" >&2
      continue
    fi

    # Check for .dev. marker
    if [[ "$filename" == *".dev."* ]] && [[ "${ENVIRONMENT}" != "development" ]]; then
      echo " - Skipping '${filename}' (requires ENVIRONMENT=development)" >&2
      continue
    fi

    # Check for .https. marker
    if [[ "$filename" == *".https."* ]] && [[ "${DOCKER_SERVICE_PROTOCOL}" != "https" ]]; then
      echo " - Skipping '${filename}' (requires DOCKER_SERVICE_PROTOCOL=https)" >&2
      continue
    fi

    echo " - Processing '${filename}'"  >&2
    # Call the provided callback function with the file path
    "$callback" "$file_path" $additional_args
  done
}

# Callback function to render a template file to the output path.
# @INTERNAL - Not intended for direct use.
# Usage:
#   _render_template_callback "path/to/template.tpl" "path/to/output.conf"
_render_template_callback() {
  local template_path="$1"
  local output_path="$2"
  local filename
  filename=$(basename "$template_path")
  echo " - Rendering '$filename' to '$output_path'" >&2
  render_template "${template_path}" "${output_path}/$filename"
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

  for_each_filtered_file_in_dir "$template_dir" _render_template_callback "$pattern" "$output_dir"
}
