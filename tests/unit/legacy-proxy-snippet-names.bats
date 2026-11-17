#!/usr/bin/env bats
# Tier 1 — legacy.d/2026-11-16-proxy-snippet-include-pattern.sh
#
# Target: legacy_restore_legacy_proxy_snippet_includes — the include-pattern
# migration bridge. The proxy-mode-multi scenario covers the golden side of
# this layer's contract (the bridged leak file IS part of the recorded
# config); THIS file pins the bridge itself, self-contained: which files the
# bridge renders under their "<key>.legacy.<name>.conf" name, which the
# current pattern already includes (never bridged), how the marker DSL keeps
# applying to legacy names, and how LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME
# turns legacy names into a boot abort.

load helpers

# The marker registry must exist before the conditions file registers its
# markers — the entrypoint.sh contract, replicated here (see
# file-marker-dsl.bats). The render chain is sourced for real as well: the
# bridge renders through the production render_template, and the assertions
# check the rendered files on disk, not a stub.
declare -gA file_marker_condition_registry
declare -g feature_registry=""

nl_unit_source "util.d/file-marker-conditions.sh"
nl_unit_source "util.d/for-each-filtered-file-in-dir.sh"
nl_unit_source "util.d/get-all-vars.sh"
nl_unit_source "util.d/render-template-string-with.sh"
nl_unit_source "util.d/render-template-with.sh"
nl_unit_source "util.d/render-template.sh"
nl_unit_source "legacy.d/2026-11-16-proxy-snippet-include-pattern.sh"

setup() {
    nl_unit_sandbox
    mkdir -p "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
}

teardown() {
    nl_unit_teardown
}

# Create snippet files in the sandbox source dir. Arguments are "name:body"
# pairs; a body of "-" writes the default marker line.
snippet_dir_with() {
    local name body
    for name in "$@"; do
        body="${name#*:}"
        [ "${body}" == "${name}" ] && body="# snippet"
        printf '%s\n' "${body}" > "${NL_UNIT_SANDBOX}/snippets/${name}"
    done
}

@test "bridge stays silent and renders nothing for files the current pattern includes" {
    snippet_dir_with "api.auth.conf" "api.conf" "api.confbackup"
    # "api.auth.conf": the NEW "<key>.<name>.conf" pattern includes it.
    # "api.conf": the exact legacy name — matches "<key>.*conf", included.
    # "api.confbackup": matches no include pattern at all (old or new) —
    # not the bridge's business either.
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ -z "$(printf '%s' "${stderr}" | grep WARNING)" ]
    [ -z "$(ls "${NL_UNIT_SANDBOX}/rendered")" ]
}

@test "bridge renders old-pattern-only files under their legacy name and warns" {
    snippet_dir_with "api-cors.conf:add_header X-Bridge cors;" "apicache.conf:add_header X-Bridge cache;"
    # "api-cors.conf" / "apicache.conf": matched the old "<key>*.conf" glob,
    # are NOT matched by "<key>.<name>.conf" (dot required) — the bridge
    # renders them as "<key>.legacy.<name>.conf" so the CURRENT include glob
    # picks them up again, restoring the pre-migration behavior.
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ -f "${NL_UNIT_SANDBOX}/rendered/api.legacy.api-cors.conf" ]
    grep -q "add_header X-Bridge cors;" "${NL_UNIT_SANDBOX}/rendered/api.legacy.api-cors.conf"
    [ -f "${NL_UNIT_SANDBOX}/rendered/api.legacy.apicache.conf" ]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'api-cors.conf' for service 'api' matches only the LEGACY include pattern"* ]]
    [[ "${stderr}" == *"rendered as 'api.legacy.api-cors.conf'"* ]]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'apicache.conf' for service 'api' matches only the LEGACY include pattern"* ]]
    # The warning names the fix (migration guide):
    [[ "${stderr}" == *"Migration guide:"* ]]
}

@test "bridge restores the prefix overlap: another configured key's file is bridged too" {
    snippet_dir_with "api_v2.prefix.conf"
    # With api_v2 CONFIGURED (PROXY_API_V2_CONTAINER), "api_v2.prefix.conf"
    # is included by its own key's new pattern — but it ALSO matches the old
    # "api*.conf" glob, so pre-migration behavior included it in the "api"
    # location as well. The bridge deliberately restores that overlap (the
    # flaw disappears only when the layer expires or in strict mode).
    PROXY_API_CONTAINER="api-backend:80"
    PROXY_API_V2_CONTAINER="api-v2-backend:80"
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ -f "${NL_UNIT_SANDBOX}/rendered/api.legacy.api_v2.prefix.conf" ]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'api_v2.prefix.conf' for service 'api' matches only the LEGACY include pattern"* ]]
}

@test "bridge applies the marker DSL to legacy names" {
    snippet_dir_with "api-cors.prod.conf"
    # The bridge renders through for_each_filtered_file_in_dir: markers are
    # evaluated on the ORIGINAL filename. Not in production -> not rendered,
    # not warned; in production -> rendered and warned.
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ ! -f "${NL_UNIT_SANDBOX}/rendered/api.legacy.api-cors.prod.conf" ]
    [ -z "$(printf '%s' "${stderr}" | grep WARNING)" ]

    ENVIRONMENT="production"
    export ENVIRONMENT
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ -f "${NL_UNIT_SANDBOX}/rendered/api.legacy.api-cors.prod.conf" ]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'api-cors.prod.conf' for service 'api'"* ]]
}

@test "strict mode aborts the boot on a legacy-named file and renders nothing" {
    snippet_dir_with "api-cors.conf" "api.cache.conf"
    LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME="true"
    # "api-cors.conf" matches the old glob only -> abort. The check is
    # marker-agnostic (raw names), so no ENVIRONMENT is needed.
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 1 ]
    [[ "${stderr}" == *"Error: Custom proxy snippet 'api-cors.conf' for service 'api' matches the LEGACY include pattern"* ]]
    [[ "${stderr}" == *"LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME=true is set"* ]]
    [[ "${stderr}" == *"Migration guide:"* ]]
    # The file the current pattern includes ("api.cache.conf") is NOT an error:
    [[ "${stderr}" != *"api.cache.conf"* ]]
    [ -z "$(ls "${NL_UNIT_SANDBOX}/rendered")" ]
}

@test "strict mode stays silent when every name matches the current pattern" {
    snippet_dir_with "api.cache.conf" "api.conf"
    LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME="true"
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ -z "$(printf '%s' "${stderr}" | grep -E 'Error|WARNING')" ]
}

@test "strict mode only triggers on the exact value true" {
    snippet_dir_with "api-cors.conf"
    LEGACY_20261116_FORCE_EXPLICIT_SNIPPET_NAME="1"
    # Anything but "true" keeps the default bridging behavior.
    run --separate-stderr legacy_restore_legacy_proxy_snippet_includes "api" "${NL_UNIT_SANDBOX}/snippets" "${NL_UNIT_SANDBOX}/rendered"
    [ "${status}" -eq 0 ]
    [ -f "${NL_UNIT_SANDBOX}/rendered/api.legacy.api-cors.conf" ]
    [[ "${stderr}" == *"WARNING"* ]]
}
