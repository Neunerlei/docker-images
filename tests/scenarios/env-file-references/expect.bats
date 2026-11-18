#!/usr/bin/env bats
# Tier 3 — env-file-references: ${VAR} references in a .env expand against the
# pass-1 values (the load-time environment), byte-for-byte the same values the
# pre-reordering pipeline produced — while the final derived values reflect
# the .env input from the next pass on.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "a DOCKER_SERVICE_ABS_PATH reference resolved to the pass-1 value" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${APP_BASE}"'
    [ "${output}" == "/" ]
}

@test "a NODE_SERVICE_PORT reference resolved to the pass-1 default" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${APP_PORT}"'
    [ "${output}" == "3000" ]
}

@test "a MAX_UPLOAD_SIZE_BYTES reference resolved to the pass-1 default" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${UPLOAD_BYTES}"'
    [ "${output}" == "104857600" ]
}

@test "a NODE_ENV reference resolved to the pass-1 environment" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${RUNTIME_ENV}"'
    [ "${output}" == "production" ]
}

@test "the final DOCKER_SERVICE_ABS_PATH reflects the .env input (next pass)" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${DOCKER_SERVICE_ABS_PATH}"'
    [ "${output}" == "/proj-alpha" ]
}
