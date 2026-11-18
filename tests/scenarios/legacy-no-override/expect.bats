#!/usr/bin/env bats
# Tier 3 — legacy-no-override: a boot without downstream overrides warns
# about nothing.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "no deprecation warning for either absorbed step file" {
    run docker logs "${NL_INT_CONTAINER}" 2>&1
    [ "${status}" -eq 0 ]
    if printf '%s\n' "${output}" | grep -qF "WARNING: A custom 'step.d/"; then
        fail "a deprecation warning appeared although no override is shipped"
    fi
}

@test "the environment orchestrator ran" {
    run docker logs "${NL_INT_CONTAINER}" 2>&1
    printf '%s\n' "${output}" | grep -qF "[ENTRYPOINT.environment] Environment pipeline completed."
}
