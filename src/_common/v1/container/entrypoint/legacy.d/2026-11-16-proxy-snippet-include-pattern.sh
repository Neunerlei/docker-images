# LEGACY LAYER — proxy snippet include pattern ("<key>*.conf" → "<key>.<name>.conf")
# Migration guide: docs/migration/2026-11-16-proxy-snippet-include-pattern.md
# Compatibility layer until: 2027-11-16
#
# When this layer expires: delete this file and its call site in
# nginx/1.29/container/entrypoint/step.d/025-nginx-proxy.sh (search for
# "legacy_warn_on_legacy_proxy_snippet_names"), then note the removal in the
# migration guide. See docs/contributing.md, "Legacy compatibility layers
# (legacy.d)".
#
# The include pattern for per-proxy custom snippets changed from
# "<key>*.conf" to "<key>.<name>.conf": the dot after the key is the key
# boundary, so keys sharing a prefix (e.g. "api" and "api_v2") no longer
# include each other's snippets, and a file named exactly "<key>.conf" keeps
# working. Files the old pattern still matched but the new one does not (e.g.
# "api-cors.conf", "apicache.conf") are not included anymore — previously they
# would have been dropped SILENTLY: no error, no config, just a missing
# snippet. This layer warns loudly for every such file while the proxy
# locations are rendered, naming the file and the scheme it must be renamed
# to. Files that belong to ANOTHER configured key whose name shares the
# prefix (e.g. "api_v2.prefix.conf" when scanning for key "api") are skipped:
# they are included by their own key's new pattern and are not dropped.
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before the steps run.

# Detects custom proxy snippet files that matched the OLD include pattern
# ("<key>*.conf") but are not matched by the current one ("<key>.<name>.conf")
# and warns about each of them with a stable, greppable wording.
# Call site: nginx/1.29/container/entrypoint/step.d/025-nginx-proxy.sh,
# _render_proxy_location_for_key, after the service's snippets were rendered.
# Arguments:
#   $1 — the service key, lower case (the "<key>" of the include patterns)
#   $2 — the directory the service's custom snippets are rendered from
function legacy_warn_on_legacy_proxy_snippet_names() {
    local KEY_LOWER="${1}"
    local source_path="${2}"
    local legacy_snippet other_key
    while IFS= read -r -d '' legacy_snippet; do
        case "${legacy_snippet}" in
            "${source_path}"/${KEY_LOWER}.*conf) continue ;;
            "${source_path}"/${KEY_LOWER}.conf*) continue ;;
        esac
        # A file may belong to ANOTHER configured key whose name shares this
        # key's prefix: "api_v2.prefix.conf" matches the old "api*.conf"
        # finder pattern, but it IS included — by the new "api_v2.*conf"
        # pattern of its own key. It is not a dropped snippet and must not be
        # flagged here. The configured key set is re-derived from the
        # PROXY_<KEY>_CONTAINER variables, exactly like the caller enumerates
        # the services.
        for other_key in $(compgen -A variable | grep '^PROXY_.*_CONTAINER' | sed -E 's/PROXY_(.*)_CONTAINER/\1/' | tr '[:upper:]' '[:lower:]'); do
            if [ "${other_key}" != "${KEY_LOWER}" ]; then
                case "${legacy_snippet}" in
                    "${source_path}"/${other_key}.*conf) continue 2 ;;
                esac
            fi
        done
        echo "[ENTRYPOINT.proxy] WARNING: Custom proxy snippet '$(basename "${legacy_snippet}")' for service '${KEY_LOWER}' is NOT included anymore: the include pattern changed from '<key>*.conf' to '<key>.<name>.conf' (dot required after the key; a file named exactly '<key>.conf' still works). Rename the snippet or it will be silently ignored." >&2
        echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-16-proxy-snippet-include-pattern.md" >&2
    done < <(find "${source_path}" -maxdepth 1 -name "${KEY_LOWER}*.conf" -print0 | sort -z)
}
