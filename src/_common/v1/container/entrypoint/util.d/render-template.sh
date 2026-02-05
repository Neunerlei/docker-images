#!/bin/bash

# The same as render_template_with but automatically uses all environment variables.
#
# Usage:
#   render_template "path/to/template.tpl" "path/to/output.conf"
#
render_template() {
    local template_file="$1"
    local output_file="$2"
    render_template_with "$(get_all_vars)" "$template_file" "$output_file"
}
