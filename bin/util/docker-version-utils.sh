_extract () {
    echo -n "$2" | awk -v f="$1" 'BEGIN {RS=","; FS="=\"|\"$";} ($1 == f) { print $2; }'
}

_get_all_tags() {
    local image_namespace="$1"
    local image_name="$2"
    local next_uri="https://index.docker.io/v2/${image_namespace}/${image_name}/tags/list"

    local auth
    auth=$(curl --silent -I "$next_uri" | sed -n 's/^Www-Authenticate: Bearer //pI' | tr -d '\r')
    local auth_header_arg=""
    if [ -n "$auth" ]; then
        local realm=$(_extract realm "$auth")
        local service=$(_extract service "$auth")
        local scope=$(_extract scope "$auth")
        local token
        token=$(curl --silent --get --data-urlencode "service=$service" --data-urlencode "scope=$scope" "$realm" | jq  -r '.token')
        auth_header_arg="--header \"Authorization: Bearer $token\""
    fi

    # --- Pagination Loop ---
    # This loop will continue as long as `next_uri` is not empty
    # See the docs: https://distribution.github.io/distribution/spec/api/#tags-paginated
    while [ -n "$next_uri" ]; do
        # Use a temporary variable to capture both the body and headers
        local response
        response=$(eval "curl -s -i $auth_header_arg \"$next_uri\"")

        # Extract the body (everything after the first empty line)
        # and then get the tags from the JSON.
        echo "$response" | sed '1,/^\r$/d' | jq -r '.tags[]'

        # Extract the 'Link' header from the headers part of the response.
        # It looks like: Link: </v2/.../tags/list?...>; rel="next"
        local link_header
        link_header=$(echo "$response" | grep -i '^Link:' | tr -d '\r')

        if echo "$link_header" | grep -q 'rel="next"'; then
            # Extract the URL part from the Link header
            next_uri="https://index.docker.io$(echo "$link_header" | sed -n 's/.*<\([^>]*\)>.*/\1/p')"
        else
            next_uri=""
        fi
    done
}

# Helper function to find the latest n versions of a docker image
# Usage get_latest_versions "namespace" "imagename" "num_versions" ["alpine"|"slim"|""] [2]
# Parameters:
#   namespace: The namespace of the image (e.g. library for official images)
#   imagename: The name of the image (e.g. nginx)
#   num_versions: The number of latest versions to return
#   filter: (optional) A string to filter the tags by variant (e.g. "alpine" to get only alpine variants)
#   precision: (optional) Number of version segments to consider (e.g., 2 for major.minor), default is 3 (major.minor.patch)
get_latest_versions() {
  local image_namespace="$1"
  local image_name="$2"
  local num_versions="$3"
  local filter="$4"
  local precision="${5:-3}"

  _get_all_tags "$image_namespace" "$image_name" | {

    # 2. Build the rest of the filtering pipeline.
    # We start with `cat` to accept the piped input from the helper.
    local versions_cmd="cat"

    if [ -n "$filter" ]; then
      versions_cmd+=" | grep -- '-$filter$' | sed 's/-$filter$//'"
    fi

    local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
    if [ "$precision" -eq 2 ]; then
      version_pattern='^[0-9]+\.[0-9]+$'
    elif [ "$precision" -eq 1 ]; then
      version_pattern='^[0-9]+$'
    fi

    versions_cmd+=" | grep -E '${version_pattern}' | sort -V | tail -n \"${num_versions}\""

    eval "$versions_cmd"
  }
}

# Helper function to check if the given tag is in the list of latest versions
# Usage is_latest_tag "version" "latest_versions" (The output of get_latest_versions)
is_latest_version() {
  local version="$1"
  local latest_versions="$2"
  local latest_version=$(echo "$latest_versions" | tail -n 1)
  if [ "$version" = "$latest_version" ]; then
    return 0
  else
    return 1
  fi
}
