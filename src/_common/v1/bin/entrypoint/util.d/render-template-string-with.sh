#!/bin/bash

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
