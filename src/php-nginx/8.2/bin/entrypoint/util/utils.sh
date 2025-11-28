#!/bin/bash

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

# Replaces the given list of placeholders in all files found in the specified directories.
# The placeholders in the files should look like "${VAR_NAME}".
# The variable names to substitute should be provided as a space-separated string.
# The values are taken from the current environment, with the same name as the variable names.
# Files are modified in-place.
#
# Usage:
#   render_template_dir 'VAR_NAME ANOTHER_VAR_NAME' /path/to/dir1 /path/to/dir2
#
render_template_dir() {
    local vars_to_substitute="$1"
    shift  # Remove first argument, remaining are directory paths

    local dir file temp_file

    for dir in "$@"; do
        if [ ! -d "$dir" ]; then
            echo "Directory not found: $dir" >&2
            continue
        fi

        for file in "$dir"/*; do
            [ ! -f "$file" ] && continue

            temp_file=$(mktemp) || {
                echo "Failed to create temp file for: $file" >&2
                continue
            }

            if render_template_string "$vars_to_substitute" "$file" > "$temp_file"; then
                mv "$temp_file" "$file"
            else
                echo "Failed to render template: $file" >&2
                rm -f "$temp_file"
            fi
        done
    done
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
