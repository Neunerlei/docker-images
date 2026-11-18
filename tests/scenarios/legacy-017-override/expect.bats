#!/usr/bin/env bats
# Tier 3 — legacy-017-override: the override replaced both env-file loads —
# each file loaded exactly once — and warned.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the deprecation warning names the file and the migration guide" {
    run docker logs "${NL_INT_CONTAINER}" 2>&1
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -qF "WARNING: A custom 'step.d/017-custom-env.sh' was found"
    printf '%s\n' "${output}" | grep -qF "docs/migration/2026-11-17-environment-pipeline.md"
}

@test "the env file loaded exactly once" {
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF 'Loading: /container/custom/env/10-only.env'"
    [ "${output}" == "1" ]
}

@test "the .env.sh file loaded exactly once too (the override replaced BOTH loads)" {
    # The override is the old 017 body — it owns the *.env AND the *.env.sh
    # pass. If the orchestrator's own .env.sh load ran as well, this file
    # would load twice.
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF 'Loading: /container/custom/env/20-dynamic.env.sh'"
    [ "${output}" == "1" ]
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${LEGACY_017_ENVSH_LOADED}"'
    [ "${output}" == "yes" ]
}

@test "each env-file pass was processed exactly once (no double loading)" {
    # for_each_filtered_file_in_dir announces every pass it runs. The
    # override runs one *.env pass and one *.env.sh pass; a second, base
    # load would announce the same pattern again.
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF \"matching '*.env'...\""
    [ "${output}" == "1" ]
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF \"matching '*.env.sh'...\""
    [ "${output}" == "1" ]
}

@test "the override ran exactly once" {
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF '[LEGACY-017-OVERRIDE] running'"
    [ "${output}" == "1" ]
}

@test "the env file's variable is exported" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${LEGACY_017_ENV_LOADED}"'
    [ "${output}" == "yes" ]
}
