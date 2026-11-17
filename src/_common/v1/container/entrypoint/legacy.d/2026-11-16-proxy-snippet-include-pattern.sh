# LEGACY LAYER — proxy snippet include pattern ("<key>*.conf" → "<key>.<name>.conf")
# Migration guide: docs/migration/2026-11-16-proxy-snippet-include-pattern.md
# Compatibility layer until: 2027-11-16
#
# When this layer expires: delete this file and its call site in
# nginx/1.29/container/entrypoint/step.d/025-nginx-proxy.sh (search for
# "legacy_restore_legacy_proxy_snippet_includes"), then note the removal in
# the migration guide. The LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME
# variable dies with this layer — after its removal a set variable is simply
# unread. See docs/contributing.md, "Legacy compatibility layers (legacy.d)".
#
# The include pattern for per-proxy custom snippets changed from
# "<key>*.conf" to "<key>.<name>.conf": the dot after the key is the key
# boundary, so keys sharing a prefix (e.g. "api" and "api_v2") no longer
# include each other's snippets, and a file named exactly "<key>.conf" keeps
# working. Per the legacy-layer contract this layer RESTORES the original
# behavior, it does not just warn about its loss: every file the OLD pattern
# matched is included again during the transition — rendered under the bridge
# name "<key>.legacy.<name>.conf", which the current "<key>.*conf" include
# glob picks up. That deliberately includes the old pattern's flaws: a file
# like "api_v2.rewrite.conf" matches the old "api*.conf" glob, so while both
# keys are configured it is included in BOTH locations again (that prefix
# overlap is the bug this migration fixes; it disappears for good when this
# layer expires, or immediately in strict mode).
#
# Modes:
#   default (variable unset / not "true")
#       For each configured key, every file matching "<key>*.conf" that the
#       current pattern does not already include is rendered as
#       "<key>.legacy.<name>.conf" into the key's rendered snippets output
#       directory, and a warning names the file and the renaming scheme. The
#       render goes through for_each_filtered_file_in_dir, so the marker DSL
#       keeps applying to the ORIGINAL filename ("api-cors.prod.conf" still
#       only loads in production) — and a marker-excluded file warns not.
#   LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME=true (strict mode)
#       The bridge render is disabled, and finding ANY file matching the old
#       glob that the current pattern does not include aborts the boot
#       (exit 1) with an error per file — the opt-in guarantee that a
#       configuration renders identically after this layer expires. Strict
#       mode scans raw file NAMES, marker-agnostic on purpose: it asserts the
#       directory is free of legacy names for this key (CI), not that the
#       files happen to be active in the current environment.
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before the steps run.

# Renders one legacy-named proxy snippet under its bridge name.
# Callback for for_each_filtered_file_in_dir (called once per file matching
# the old "<key>*.conf" finder pattern that also passes the marker DSL).
# Call site: legacy_restore_legacy_proxy_snippet_includes below.
# Arguments:
#   $1 — the snippet's source file path
#   $2 — the rendered snippets output directory (the include glob's dir)
#   $3 — the service key, lower case (the "<key>" of the include patterns)
function legacy_render_legacy_proxy_snippet() {
    local source_file="${1}"
    local output_path="${2}"
    local key_lower="${3}"
    local filename
    filename="$(basename "${source_file}")"

    # The current pattern already includes this file ("<key>.<name>.conf"
    # and the exact "<key>.conf" both match "<key>.*conf") — nothing legacy
    # about it, the normal render above already handled it.
    case "${filename}" in
        "${key_lower}".*conf) return 0 ;;
    esac

    echo "[ENTRYPOINT.proxy] WARNING: Custom proxy snippet '${filename}' for service '${key_lower}' matches only the LEGACY include pattern '<key>*.conf' (current pattern: '<key>.<name>.conf'). It keeps working — rendered as '${key_lower}.legacy.${filename}' — but only until 2027-11-16, afterwards it will be silently ignored. Rename the snippet (or give this key its own copy if you relied on the prefix overlap)." >&2
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-16-proxy-snippet-include-pattern.md" >&2
    render_template "${source_file}" "${output_path}/${key_lower}.legacy.${filename}"
}

# Restores the pre-2026-11-16 include behavior for one service key — or, in
# strict mode, refuses to boot on legacy-named files instead.
# Call site: nginx/1.29/container/entrypoint/step.d/025-nginx-proxy.sh,
# _render_proxy_location_for_key, after the service's snippets were rendered
# and before _configure_proxy_basic_auth (the auth ownership scan must see
# the bridge renders, so a legacy snippet declaring its own "auth_basic"
# takes over the location exactly like before the pattern change).
# Arguments:
#   $1 — the service key, lower case (the "<key>" of the include patterns)
#   $2 — the directory the service's custom snippets are rendered from
#   $3 — the rendered snippets output directory (the include glob's dir)
function legacy_restore_legacy_proxy_snippet_includes() {
    local key_lower="${1}"
    local source_path="${2}"
    local output_path="${3}"

    if [ "${LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME:-}" == "true" ]; then
        local legacy_snippet found_legacy=0
        while IFS= read -r -d '' legacy_snippet; do
            case "$(basename "${legacy_snippet}")" in
                "${key_lower}".*conf) continue ;;
            esac
            echo "[ENTRYPOINT.proxy] Error: Custom proxy snippet '$(basename "${legacy_snippet}")' for service '${key_lower}' matches the LEGACY include pattern '<key>*.conf' (current pattern: '<key>.<name>.conf'), and LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME=true is set: the legacy include bridge is disabled, aborting so the snippet cannot rely on it. Rename the snippet." >&2
            echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-16-proxy-snippet-include-pattern.md" >&2
            found_legacy=1
        done < <(find "${source_path}" -maxdepth 1 -name "${key_lower}*.conf" -print0 | sort -z)
        if [ "${found_legacy}" == "1" ]; then
            exit 1
        fi
        return 0
    fi

    # The old pattern as finder pattern; the callback skips files the current
    # pattern already includes, so nothing is rendered (or included) twice.
    # The marker DSL applies to the original filenames — see the header.
    for_each_filtered_file_in_dir "${source_path}" legacy_render_legacy_proxy_snippet "${key_lower}*.conf" "${output_path} ${key_lower}"
}
