#!/usr/bin/env bats
# Tier 3 — registry-installer-user-dirs: the installer-registered user-owned
# directories are REPAIRED to www-data by step 070 — the scenario image broke
# the ownership at build time, so only the registry-driven repair (the
# installer's entries surviving the registry move into step 070) can pass.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the venv directory (and a child) is repaired to www-data" {
    if [ "${NL_TEST_IMAGE}" != "python-nginx" ]; then skip "python-nginx only"; fi
    run docker exec "${NL_INT_CONTAINER}" bash -c 'stat -c "%U:%G" /opt/venv /opt/venv/bin'
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -qx 'www-data:www-data'
    [ "$(printf '%s\n' "${output}" | grep -c 'www-data:www-data')" == "2" ]
}

@test "the global node_modules directory (and a child) is repaired to www-data" {
    if [ "${NL_TEST_IMAGE}" != "node-nginx" ]; then skip "node-nginx only"; fi
    run docker exec "${NL_INT_CONTAINER}" bash -c 'stat -c "%U:%G" /usr/local/lib/node_modules /usr/local/lib/node_modules/pnpm'
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -qx 'www-data:www-data'
    [ "$(printf '%s\n' "${output}" | grep -c 'www-data:www-data')" == "2" ]
}
