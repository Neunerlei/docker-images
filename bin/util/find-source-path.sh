# Helper function for Semver-aware directory selection
# Returns an empty string if no suitable directory is found
# Usage: find_dockerfile_path "./nginx" "1.29.1"
find_source_path() {
    local source_base_dir="$1"
    local target_version="$2"
    local best_match_dir=""

    # Get a descending, version-sorted list of available config directories (e.g., 1.29, 1.27)
    local available_dirs=$(find "$source_base_dir" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -Vr)

    for dir_version in $available_dirs; do
        # Use dpkg for robust semver comparison. 'ge' means "greater or equal".
        if dpkg --compare-versions "$target_version" "ge" "$dir_version"; then
            best_match_dir="$dir_version"
            # Since the list is sorted descending, the first match is the best one.
            break
        fi
    done

    echo "$best_match_dir"
}
