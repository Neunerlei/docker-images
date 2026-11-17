#!/usr/bin/env bats
# Tier 1 — legacy.d/2026-11-16-proxy-snippet-include-pattern.sh
#
# Target: legacy_warn_on_legacy_proxy_snippet_names — the include-pattern
# migration warning. The proxy-mode-multi scenario covers the quiet side of
# this layer's contract (both prefix-sharing keys configured → NO warning in
# the goldens); THIS file pins the warning path itself, self-contained:
# which legacy-named files warn, which are skipped because the CURRENT
# pattern still includes them, and which are skipped because ANOTHER
# configured key with a shared prefix owns them.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "legacy.d/2026-11-16-proxy-snippet-include-pattern.sh"
}

teardown() {
    nl_unit_teardown
}

# Create snippet files in the sandbox "rendered snippets" dir. Arguments are
# file names; content is irrelevant (the finder only looks at names).
snippet_dir_with() {
    local dir="${NL_UNIT_SANDBOX}/snippets"
    mkdir -p "${dir}"
    local name
    for name in "$@"; do
        printf '# snippet\n' > "${dir}/${name}"
    done
    printf '%s\n' "${dir}"
}

@test "legacy_warn_on_legacy_proxy_snippet_names stays silent for files the current pattern includes" {
    local dir
    dir="$(snippet_dir_with "api.auth.conf" "api.conf" "api.confbackup")"
    # "api.auth.conf": the NEW "<key>.<name>.conf" pattern includes it.
    # "api.conf": the exact legacy name, still included by both patterns.
    # "api.confbackup": matches "<key>.conf*" — a deliberate grandfather
    # shape (see the layer's case patterns), not a dropped snippet.
    run --separate-stderr legacy_warn_on_legacy_proxy_snippet_names "api" "${dir}"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
    [ -z "${stderr}" ]
}

@test "legacy_warn_on_legacy_proxy_snippet_names warns for files only the OLD pattern matched" {
    local dir
    dir="$(snippet_dir_with "api-cors.conf" "apicache.conf")"
    # "api-cors.conf" / "apicache.conf": matched the old "<key>*.conf" glob,
    # are NOT matched by "<key>.<name>.conf" (dot required) — previously they
    # would have been dropped silently, so the layer warns loudly instead.
    run --separate-stderr legacy_warn_on_legacy_proxy_snippet_names "api" "${dir}"
    [ "${status}" -eq 0 ]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'api-cors.conf' for service 'api' is NOT included anymore"* ]]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'apicache.conf' for service 'api' is NOT included anymore"* ]]
    # The warning names the fix (migration guide):
    [[ "${stderr}" == *"Migration guide:"* ]]
}

@test "legacy_warn_on_legacy_proxy_snippet_names skips files owned by another configured key with a shared prefix" {
    local dir
    dir="$(snippet_dir_with "api_v2.prefix.conf" "api-cors.conf")"
    # With api_v2 CONFIGURED (PROXY_API_V2_CONTAINER), "api_v2.prefix.conf"
    # is included by its own key's new pattern — scanning for key "api" must
    # not flag it. "api-cors.conf" is owned by nobody and still warns.
    PROXY_API_CONTAINER="api-backend:80"
    PROXY_API_V2_CONTAINER="api-v2-backend:80"
    run --separate-stderr legacy_warn_on_legacy_proxy_snippet_names "api" "${dir}"
    [ "${status}" -eq 0 ]
    [[ "${stderr}" != *"api_v2.prefix.conf"* ]]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'api-cors.conf'"* ]]
}

@test "legacy_warn_on_legacy_proxy_snippet_names warns for a shared-prefix file when that other key is NOT configured" {
    local dir
    dir="$(snippet_dir_with "api_v2.prefix.conf")"
    # No PROXY_API_V2_CONTAINER: nothing includes "api_v2.prefix.conf" — the
    # skip must depend on the configured key set, not on the name shape.
    PROXY_API_CONTAINER="api-backend:80"
    run --separate-stderr legacy_warn_on_legacy_proxy_snippet_names "api" "${dir}"
    [ "${status}" -eq 0 ]
    [[ "${stderr}" == *"WARNING: Custom proxy snippet 'api_v2.prefix.conf' for service 'api' is NOT included anymore"* ]]
}
