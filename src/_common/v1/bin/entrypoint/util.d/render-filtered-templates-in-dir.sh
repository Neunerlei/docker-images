#!/bin/bash

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
