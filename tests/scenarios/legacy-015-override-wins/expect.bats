#!/usr/bin/env bats
# Tier 3 — legacy-015-override-wins: the deprecation warning, the override's
# precedence (mode + values), and the exactly-once execution.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the deprecation warning names the file and the migration guide" {
    run docker logs "${NL_INT_CONTAINER}" 2>&1
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -qF "WARNING: A custom 'step.d/015-image-vars.sh' was found"
    printf '%s\n' "${output}" | grep -qF "docs/migration/2026-11-17-environment-pipeline.md"
}

@test "the override ran exactly once (the step loop skipped the file)" {
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF '[LEGACY-015-OVERRIDE] running'"
    [ "${output}" == "1" ]
}

@test "the override's worker mode won" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${CONTAINER_MODE}"'
    [ "${output}" == "worker" ]
    # process_name includes %(process_num)02d, so supervisorctl reports the
    # program as a group ("app-worker:app-worker_00") — match on the group.
    run docker exec "${NL_INT_CONTAINER}" supervisorctl status app-worker:
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -q 'RUNNING'
}

@test "the override's PHP_MEMORY_LIMIT survived the base defaults" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${PHP_MEMORY_LIMIT}"'
    [ "${output}" == "256M" ]
}
