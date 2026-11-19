#!/usr/bin/env bats
# Tier 3 — env-file-upload-size-proxy: an env-file MAX_UPLOAD_SIZE reaches the
# client_max_body_size of a proxy location on the nginx image.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "proxy mode is active and the body size rendered 500M" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${CONTAINER_MODE}"'
    [ "${output}" == "proxy" ]
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "client_max_body_size 500M;"'
    [ "${status}" -eq 0 ]
}

@test "MAX_UPLOAD_SIZE_BYTES is the exact 500M byte value" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${MAX_UPLOAD_SIZE_BYTES}"'
    [ "${output}" == "524288000" ]
}
