#!/usr/bin/env bats
# Tier 3 — env-file-environment-dev: an env-file ENVIRONMENT=dev is normalized
# by the second derive pass and reaches the APP_ENV family, NODE_ENV, the
# .dev. snippet selection and the .dev.-marked .env.sh files.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "python: APP_ENV / FLASK_ENV / APP_DEBUG follow the env-file dev switch" {
    if [ "${NL_TEST_IMAGE}" != "python-nginx" ]; then skip "python-nginx only"; fi
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s/%s/%s" "${APP_ENV}" "${FLASK_ENV}" "${APP_DEBUG}"'
    [ "${output}" == "dev/development/1" ]
}

@test "php: APP_ENV / APP_DEBUG follow the env-file dev switch" {
    if [ "${NL_TEST_IMAGE}" != "php-nginx" ]; then skip "php-nginx only"; fi
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s/%s" "${APP_ENV}" "${APP_DEBUG}"'
    [ "${output}" == "dev/1" ]
}

@test "node: NODE_ENV follows the env-file dev switch" {
    if [ "${NL_TEST_IMAGE}" != "node-nginx" ]; then skip "node-nginx only"; fi
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${NODE_ENV}"'
    [ "${output}" == "development" ]
}

@test "a .dev.-marked custom snippet is selected and rendered" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -F "# dev-marker-dev-active"'
    [ "${status}" -eq 0 ]
}

@test "a .dev.-marked .env.sh file is selected (post-.env marker filtering)" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${ENVSH_DEV_MARKER}"'
    [ "${output}" == "yes" ]
}

@test "ENVIRONMENT itself is normalized to development" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${ENVIRONMENT}"'
    [ "${output}" == "development" ]
}
