#!/bin/bash

# The same as render_template_string_with but automatically uses all environment variables.
# Usage:
#   YOUR_VAR=$(render_template_string "path/to/template.tpl")
#
render_template_string() {
    local template_file="$1"
    render_template_string_with "$(get_all_vars)" "$template_file"
}
