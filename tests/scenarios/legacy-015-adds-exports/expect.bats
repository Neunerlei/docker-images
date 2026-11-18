#!/usr/bin/env bats
# Tier 3 — legacy-015-adds-exports: the base feature/mode logic and defaults
# still ran, and the override's addition is present.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the override's export is present" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${MY_LEGACY_EXTRA}"'
    [ "${output}" == "added-by-override" ]
}

@test "the deprecation warning names the file and the migration guide" {
    run docker logs "${NL_INT_CONTAINER}" 2>&1
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -qF "WARNING: A custom 'step.d/015-image-vars.sh' was found"
    printf '%s\n' "${output}" | grep -qF "docs/migration/2026-11-17-environment-pipeline.md"
}

@test "the base mode logic still ran (web, not unset)" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${CONTAINER_MODE}"'
    [ "${output}" == "web" ]
}

@test "the base defaults still applied" {
    # NODE_ENV derives from ENVIRONMENT in the BASE image_env_defaults —
    # the override never set it.
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${NODE_ENV}"'
    [ "${output}" == "production" ]
}

@test "the override ran exactly once" {
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF '[LEGACY-015-ADDS] running'"
    [ "${output}" == "1" ]
}
