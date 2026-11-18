#!/usr/bin/env bats
# Tier 3 — resolver-autodetect: the detected resolver is the one from
# /etc/resolv.conf, NOT the 127.0.0.11 fallback.
#
# The golden tier cannot pin this: the resolver value is normalized
# (environment-dependent). This assertion is the regression net for a
# pipeline bug class the golden hid once already: chained tracked defaults
# clobbering a successful detection with the fallback value (the boot
# rendered "resolver 127.0.0.11" while resolv.conf held the real DNS).

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the rendered resolver lists the nameservers from /etc/resolv.conf" {
    # Expected value read from the container itself: every nameserver line
    # (IPv6 bracketed exactly like detect_dns_resolvers renders them),
    # space-joined, with the configured valid= knob.
    local expected
    expected="$(docker exec "${NL_INT_CONTAINER}" bash -c \
        "awk '\$1==\"nameserver\" && \$2 !~ /%/ { ns=\$2; sub(/^[^.]*$/, \"\", dummy); if (ns ~ /:/ && ns !~ /^\[/) ns=\"[\" ns \"]\"; printf \"%s%s\", sep, ns; sep=\" \" }' /etc/resolv.conf")"
    [ -n "${expected}" ] || skip "no readable nameservers in this environment"
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        "nginx -T 2>&1 | grep -F 'resolver ${expected} valid=17s;'"
    [ "${status}" -eq 0 ]
}

@test "NGINX_RESOLVER is exported with the detected value" {
    local expected
    expected="$(docker exec "${NL_INT_CONTAINER}" bash -c \
        "awk '\$1==\"nameserver\" && \$2 !~ /%/ { ns=\$2; if (ns ~ /:/ && ns !~ /^\[/) ns=\"[\" ns \"]\"; printf \"%s%s\", sep, ns; sep=\" \" }' /etc/resolv.conf")"
    [ -n "${expected}" ] || skip "no readable nameservers in this environment"
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${NGINX_RESOLVER}"'
    [ "${output}" == "${expected}" ]
}
