#!/usr/bin/env bats
# Tier 3 — resolver-explicit: the explicit NGINX_RESOLVER list reaches the
# rendered configuration VERBATIM.
#
# The golden (Tier 2) pins the structure — that the directive rendered, the
# knob overrides, the snippet comment — but its resolver-list VALUE is
# normalized ("<NL-TEST-RESOLVER>", see lib/normalize.sed: detected and
# explicit values cannot be told apart there, and multi-address lists are
# normalized as a whole). THIS tier proves the part a normalized golden
# cannot: the exact server LIST this scenario configures ("127.0.0.11
# 8.8.8.8") lands in the rendered resolver directive, in order, with the
# non-default valid= knob — read straight from the live container's config
# (nginx -T).

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

@test "the rendered config contains the full explicit resolver list with the configured knob" {
    # nginx -T dumps the fully resolved configuration (snippets included);
    # the resolver snippet is rendered into the http context. Reading the
    # LIVE config is the observable the normalization in the golden tier
    # intentionally hides. The dump goes to stderr — grep both streams.
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "resolver 127.0.0.11 8.8.8.8 valid=17s;"'
    [ "${status}" -eq 0 ]
    [ "${output}" == "resolver 127.0.0.11 8.8.8.8 valid=17s;" ]
}

@test "the resolver_timeout override rendered as configured" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "resolver_timeout 9s;"'
    [ "${status}" -eq 0 ]
}
