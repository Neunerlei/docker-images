#!/usr/bin/env bats
# Tier 3 — basic-auth-global: the documented global basic auth behavior
# (docs/nginx.md, "Basic Authentication") against a LIVE container.
#
# The golden (Tier 2) pins the rendered directives and WHICH users exist; the
# hashes there are normalized because they are salted. THIS tier proves the
# part a normalized golden cannot: the generated hashes actually WORK — 401
# without credentials, 200 with the right ones, 401 for a wrong password, and
# the realm text from NGINX_BASIC_AUTH_REALM reaching the challenge header.

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

@test "GET / without credentials answers 401 with the configured realm" {
    [ "$(nl_int_curl_status "/")" == "401" ]
    [ "$(nl_int_curl_header "/" "" "WWW-Authenticate")" == 'WWW-Authenticate: Basic realm="NL Test Realm"' ]
}

@test "GET / with the correct first-user credentials answers 200" {
    # testuser/test-password from the scenario env — the proof that the apr1
    # hash in the golden-normalized password file really matches this password
    [ "$(nl_int_curl_status "/" "testuser:test-password")" == "200" ]
}

@test "GET / with the correct second-user credentials answers 200 (multi-user collection)" {
    # NGINX_BASIC_AUTH_1 was collected into the same password file
    [ "$(nl_int_curl_status "/" "seconduser:other-password")" == "200" ]
}

@test "GET / with a wrong password answers 401" {
    [ "$(nl_int_curl_status "/" "testuser:totally-wrong")" == "401" ]
}

@test "GET / with an unknown user answers 401" {
    [ "$(nl_int_curl_status "/" "nobody:nope")" == "401" ]
}
