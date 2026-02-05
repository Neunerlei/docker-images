#!/bin/bash

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

  # Fail if output_file is not provided
  if [ -z "$output_file" ]; then
      echo "Output file path is required" >&2
      exit 1
  fi

  # Fail if the directory of the output file does not exist
  local output_dir
  output_dir=$(dirname "$output_file")
  if [ ! -d "$output_dir" ]; then
      echo "Output directory does not exist: $output_dir for $output_file" >&2
      exit 1
  fi

  echo "$(render_template_string_with "$vars_to_substitute" "$template_file")" > "$output_file"
}
