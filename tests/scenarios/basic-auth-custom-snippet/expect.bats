#!/usr/bin/env bats
# Tier 3 — basic-auth-custom-snippet: a server-level custom snippet declaring
# its own auth_basic takes OWNERSHIP while NGINX_BASIC_AUTH is also set
# (docs/nginx.md ownership rule; 020-nginx.sh).
#
# The scenario's custom snippet renders `auth_basic "Custom Snippet Realm"`
# plus `auth_basic_user_file ${NGINX_BASIC_AUTH_FILE}` — the generated
# (still-written) password file. Live proof of the ownership rule:
#   - the CHALLENGE carries the custom snippet's realm, not the global one;
#   - the GLOBAL credentials from NGINX_BASIC_AUTH work through the snippet's
#     auth_basic_user_file (the generated file is still authoritative);
#   - there is exactly ONE WWW-Authenticate header — if the generated
#     directives had NOT been skipped, nginx would refuse to start at all
#     ("auth_basic directive is duplicate"), which the RUNNING gate in
#     nl_int_boot already proves; the single-header assert pins the response
#     shape explicitly.

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

@test "GET / without credentials answers 401 with the CUSTOM snippet's realm" {
    [ "$(nl_int_curl_status "/")" == "401" ]
    [ "$(nl_int_curl_header "/" "" "WWW-Authenticate")" == 'WWW-Authenticate: Basic realm="Custom Snippet Realm"' ]
}

@test "GET / authenticates with the GLOBAL credentials via the snippet's auth_basic_user_file" {
    # The generated password file was still written (only the directives were
    # skipped) — the snippet points at it through NGINX_BASIC_AUTH_FILE
    [ "$(nl_int_curl_status "/" "global-user:global-password")" == "200" ]
}

@test "the 401 challenge appears exactly once (auth_basic was not duplicated)" {
    local header_count
    header_count="$(docker exec "${NL_INT_CONTAINER}" curl -sS -o /dev/null -D - --max-time 5 \
        "http://127.0.0.1:80/" 2>/dev/null | grep -ci '^WWW-Authenticate:' || true)"
    [ "${header_count}" -eq "1" ]
}

@test "GET / with a wrong password answers 401" {
    [ "$(nl_int_curl_status "/" "global-user:nope")" == "401" ]
}
