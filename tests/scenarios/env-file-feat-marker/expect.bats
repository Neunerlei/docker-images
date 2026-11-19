#!/usr/bin/env bats
# Tier 3 — env-file-feat-marker: the feat-supervisor-marked env file loaded.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the feat-supervisor-marked env file loaded" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${FEAT_MARKER_LOADED}"'
    [ "${output}" == "yes" ]
}

@test "a feat-marker the image does NOT have keeps the env file unloaded" {
    # The negative case: feat-doesnotexist matches no feature in the
    # registry, so the file must NOT load (run + status assert — the value
    # read is the observable, an unset variable prints nothing).
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'if [ -n "${FEAT_NEGATIVE_NOT_LOADED:-}" ]; then printf "%s" "${FEAT_NEGATIVE_NOT_LOADED}"; fi'
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
    run bash -c "docker logs ${NL_INT_CONTAINER} 2>&1 | grep -cF 'Loading: /container/custom/env/20-missing.feat-doesnotexist.env'"
    [ "${output}" == "0" ]
}
