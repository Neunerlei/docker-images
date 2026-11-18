#!/usr/bin/env bats
# Tier 3 — env-sh-upload-size: a .env.sh input reaches the derived values via
# the third derive pass.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "client_max_body_size renders the 300M set by the .env.sh file" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "client_max_body_size 300M;"'
    [ "${status}" -eq 0 ]
}

@test "MAX_UPLOAD_SIZE_BYTES derives from the .env.sh value" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${MAX_UPLOAD_SIZE_BYTES}"'
    [ "${output}" == "314572800" ]
}
