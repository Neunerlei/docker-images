#!/usr/bin/env bats
# Tier 3 — basic-auth-health-location: a nested `auth_basic off;` inside a
# custom snippet is a LOCAL opt-out, not an ownership signal (020-nginx.sh).
#
# The golden (Tier 2) pins the rendered config: the generated global auth
# directives are still in the basicAuth include (not reduced to a comment).
# THIS tier proves the behavior a rendered config cannot: the root stays
# protected (401, credentials still work) while the nested location is open
# (200 without credentials) — the health-check property.

load '../../lib/integration-helpers'

setup() {
    # bats runs each test in its own process — reload the boot state written
    # by setup_file (container name, etc.)
    nl_int_load_state
}

setup_file() {
    nl_int_boot
}

teardown_file() {
    nl_int_teardown
}

@test "GET / without credentials answers 401 (global auth still rendered)" {
    [ "$(nl_int_curl_status "/")" == "401" ]
    [ "$(nl_int_curl_header "/" "" "WWW-Authenticate")" == 'WWW-Authenticate: Basic realm="NL Test Realm"' ]
}

@test "GET / with a wrong password answers 401" {
    [ "$(nl_int_curl_status "/" "testuser:totally-wrong")" == "401" ]
}

@test "GET / with the global credentials answers 200 (generated auth include still active)" {
    [ "$(nl_int_curl_status "/" "testuser:test-password")" == "200" ]
}

@test "GET /health answers 200 WITHOUT credentials (nested auth_basic off)" {
    # The health-check contract: orchestrator probes cannot send credentials,
    # so the opt-out must answer them as-is.
    [ "$(nl_int_curl_status "/health")" == "200" ]
}

@test "GET /health ignores credentials as well (no challenge to leak)" {
    # Wrong credentials must not make a difference in an auth-off location —
    # nginx never challenges there.
    [ "$(nl_int_curl_status "/health" "testuser:totally-wrong")" == "200" ]
}
