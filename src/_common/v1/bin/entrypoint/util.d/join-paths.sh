#!/bin/bash

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
