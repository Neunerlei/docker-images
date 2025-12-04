#!/bin/bash

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

  if [[ -z "${callback}" ]]; then
    echo "No callback function provided to for_each_filtered_file_in_dir" >&2
    return 1
  fi

  if [[ ${#file_marker_condition_registry[@]} -eq 0 ]]; then
    echo "Warning: file_marker_condition_registry map is empty. No filtering will be applied." >&2
  fi

  # Build a single regex pattern from all registry keys.
  # This is a highly efficient way to quickly discard non-matching groups.
  local all_markers_regex
  all_markers_regex="($(IFS=\|; echo "${!file_marker_condition_registry[*]}"))"
  # This converts 'env-*|https' into a regex like '(env-.*|https)'
  all_markers_regex="${all_markers_regex//\*/.*}"

  echo "Processing files from ${read_dir}, matching '${pattern}'..." >&2

  while IFS= read -r -d '' file_path; do
    local filename
    filename=$(basename "${file_path}")
    local all_and_groups_satisfied=true

    # We only need to parse the filename if it potentially contains markers.
    if [[ "$filename" == *.* ]]; then
      # Split the filename by '.' to get the top-level AND groups.
      # Example: 'file.prod.https-or-dev.sh' -> ('file', 'prod', 'https-or-dev', 'sh')
      local and_groups
      IFS='.' read -ra and_groups <<<"$filename"

      for group in "${and_groups[@]}"; do
        # Use the fast regex pre-filter.
        if ! [[ "$group" =~ $all_markers_regex ]]; then
          continue
        fi

        # Split the group into its OR clauses.
        # Example: 'https-or-dev' -> ('https', 'dev')
        # Example: 'prod' -> ('prod')
        # Replace the '-or-' string with a newline character.
        # This correctly prepares the group for splitting.
        local group_with_newlines="${group//-or-/$'\n'}"

        # Now read the newline-separated clauses into an array.
        local or_clauses
        mapfile -t or_clauses <<< "${group_with_newlines}"

        local is_or_group_satisfied=false

        for clause in "${or_clauses[@]}"; do
          if [[ -z "${clause}" ]]; then continue; fi

          for registered_marker in "${!file_marker_condition_registry[@]}"; do
            # Use Bash's glob matching:
            # - If registered_marker is 'https', it matches if clause is 'https'.
            # - If registered_marker is 'env-*', it matches if clause is 'env-prod', 'env-staging', etc.
            if [[ "${clause}" == ${registered_marker} ]]; then
              local condition_func="${file_marker_condition_registry["${registered_marker}"]}"
              local arg=""

              # If it was a wildcard match, extract the argument.
              if [[ "${registered_marker}" == *"*"* ]]; then
                local prefix="${registered_marker%\*}"
                # Get the suffix (e.g., 'prod')
                arg="${clause#$prefix}"
              fi

              # Call the function (with or without an argument)
              if "$condition_func" "${arg}"; then
                is_or_group_satisfied=true
              fi
              break # Found a matching handler, no need to check other markers for this clause.
            fi
          done

          if "$is_or_group_satisfied"; then
            break # The OR group is satisfied, move to the next AND group.
          fi
        done

        if ! "$is_or_group_satisfied"; then
          echo " - Skipping '${filename}': condition group '${group}' was not satisfied." >&2
          all_and_groups_satisfied=false
          break
        fi
      done
    fi

    # Final check: if all logical groups were satisfied, process the file.
    if ! "$all_and_groups_satisfied"; then
      continue
    fi
    "$callback" "${file_path}" $additional_args

  done < <(find "${read_dir}" -maxdepth 1 -name "${pattern}" -print0 | sort -z)
}
