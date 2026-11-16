#!/usr/bin/env bats
# Tier 3 — basic-auth-per-proxy: global auth PLUS a per-proxy override on the
# /api service (docs/nginx.md, "Protecting a single proxied service").
#
# The documented replacement semantics, asserted against the LIVE responses:
#   /       keeps the global auth (users + "Global Realm")
#   /api/   uses ONLY the per-proxy auth (users + "API Area") — the global
#           users must NOT work there
#
# The proxy upstreams are deliberately nonexistent (.invalid): a request that
# PASSES authentication therefore deterministically fails at the upstream with
# 502 — which is exactly the proof that auth was accepted (401 would mean the
# opposite). 401 = rejected, 502 = authenticated and proxied.

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

@test "GET / without credentials answers 401 with the GLOBAL realm" {
    [ "$(nl_int_curl_status "/")" == "401" ]
    [ "$(nl_int_curl_header "/" "" "WWW-Authenticate")" == 'WWW-Authenticate: Basic realm="Global Realm"' ]
}

@test "GET /api/ without credentials answers 401 with the PER-PROXY realm" {
    [ "$(nl_int_curl_status "/api/")" == "401" ]
    [ "$(nl_int_curl_header "/api/" "" "WWW-Authenticate")" == 'WWW-Authenticate: Basic realm="API Area"' ]
}

@test "GET /api/ rejects the global credentials — the per-proxy auth replaces the global one" {
    # The documented replacement rule: global users do not apply to the
    # overridden location
    [ "$(nl_int_curl_status "/api/" "global-user:global-password")" == "401" ]
}

@test "GET /api/ accepts the per-proxy credentials (auth passes, upstream .invalid fails 502)" {
    [ "$(nl_int_curl_status "/api/" "api-user:api-password")" == "502" ]
}

@test "GET / accepts the global credentials (auth passes, upstream .invalid fails 502)" {
    [ "$(nl_int_curl_status "/" "global-user:global-password")" == "502" ]
}

@test "GET /api/ with a wrong per-proxy password answers 401" {
    [ "$(nl_int_curl_status "/api/" "api-user:wrong")" == "401" ]
}
