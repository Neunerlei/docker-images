#!/usr/bin/env bats
# Tier 3 — env-file-explicit-precedence: the explicit body size wins, the
# input still feeds the byte form.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "client_max_body_size renders the explicit 50M, not the derived 500M" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "client_max_body_size 50M;"'
    [ "${status}" -eq 0 ]
}

@test "MAX_UPLOAD_SIZE_BYTES still derives from the 500M input" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${MAX_UPLOAD_SIZE_BYTES}"'
    [ "${output}" == "524288000" ]
}
