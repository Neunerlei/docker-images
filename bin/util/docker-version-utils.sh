# Helper function to find the latest n versions of a docker image
# Usage get_latest_versions "imagename" "num_versions" ["alpine"|"slim"|""] # the third parameter is optional and used to filter for specific variants
get_latest_versions() {
  local image_name="$1"
  local num_versions="$2"

  local versions_cmd="curl -s \"https://hub.docker.com/v2/repositories/library/${image_name}/tags/?page_size=100\" | jq -r '.results[].name'"

  if [ -n "$3" ]; then
    # If a filter is provided, use it.
    versions_cmd+=" | grep -- '-$3$' | sed 's/-$3$//'"
  fi

  versions_cmd+=" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n \"${num_versions}\""

  eval "$versions_cmd"
}

# Helper function to check if the given tag is in the list of latest versions
# Usage is_latest_tag "version" "latest_versions" (The output of get_latest_versions)
is_latest_version() {
  local version="$1"
  local latest_versions="$3"
  if echo "$latest_versions" | grep -q "^${version}$"; then
    return 0  # true
  else
    return 1  # false
  fi
}
