#!/usr/bin/env bats
# Tier 3 — env-file-upload-size: a MAX_UPLOAD_SIZE from /container/custom/env
# reaches every derived upload variable (client_max_body_size, the byte form,
# the PHP ini limits). The derived values live in rendered config files and
# the exported environment — all readable inside the live container.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "nginx renders client_max_body_size 500M" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "client_max_body_size 500M;"'
    [ "${status}" -eq 0 ]
}

@test "MAX_UPLOAD_SIZE_BYTES is the exact 500M byte value" {
    # bash is env-wrapped: the exec shell sources container-vars.sh, so the
    # exported snapshot IS the observable.
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${MAX_UPLOAD_SIZE_BYTES}"'
    [ "${output}" == "524288000" ]
}

@test "php: upload_max_filesize and post_max_size follow in the rendered ini" {
    if [ "${NL_TEST_IMAGE}" != "php-nginx" ]; then skip "php-nginx only"; fi
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'grep -hE "^(upload_max_filesize|post_max_size)" /usr/local/etc/php/conf.d/*.ini'
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -qx 'upload_max_filesize = 500M'
    printf '%s\n' "${output}" | grep -qx 'post_max_size = 500M'
}
