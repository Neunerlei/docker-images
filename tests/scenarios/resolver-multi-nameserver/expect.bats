#!/usr/bin/env bats
# Tier 3 — resolver-multi-nameserver: BOTH pinned --dns nameservers must be
# collected, in order, into the rendered resolver directive.
#
# The golden cannot make this assertion itself: the resolver rules in
# lib/normalize.sed normalize the whole ADDRESS LIST by context (they cannot
# distinguish one server from two — that is the price of machine-independent
# goldens). The docker-args pin the addresses to RFC 5737 TEST-NET values, so
# HERE — where the assertion runs on the live container — the raw values ARE
# deterministic and can be asserted verbatim. This is the regression detector
# for the multi-nameserver collection: a parser that drops the second
# nameserver (e.g. the old no-trailing-newline read bug) reds this test while
# every golden stays green.

load '../../lib/integration-helpers'

setup() {
    nl_int_load_state
}

setup_file() {
    nl_int_boot
}

teardown_file() {
    nl_int_teardown
}

@test "resolv.conf carries both pinned nameservers (scenario setup is intact)" {
    local resolv
    resolv="$(docker exec "${NL_INT_CONTAINER}" cat /etc/resolv.conf 2>/dev/null)"
    [[ "${resolv}" == *"nameserver 192.0.2.10"* ]]
    [[ "${resolv}" == *"nameserver 192.0.2.11"* ]]
}

@test "the rendered resolver directive contains the full space-separated list in order" {
    local directive
    directive="$(docker exec "${NL_INT_CONTAINER}" nginx -T 2>/dev/null \
        | grep -E '^resolver .* valid=' | head -n1)"
    [ "${directive}" == "resolver 192.0.2.10 192.0.2.11 valid=30s;" ]
}

@test "the exported NGINX_RESOLVER value holds both servers" {
    # The snapshot is root-owned 600 — read it as root via docker exec
    # (default user), which is exactly the context later RUN steps get.
    local snapshot_line
    snapshot_line="$(docker exec "${NL_INT_CONTAINER}" bash -c \
        'grep "^export NGINX_RESOLVER=" /container/work/container-vars.sh')"
    [ "${snapshot_line}" == "export NGINX_RESOLVER=192.0.2.10\ 192.0.2.11" ]
}
