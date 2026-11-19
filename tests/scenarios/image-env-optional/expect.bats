#!/usr/bin/env bats
# Tier 3 — image-env-optional: the entrypoint completes (exit 0) with no
# image-env.sh present, without warnings.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_run_static /bin/true; }
teardown_file() { nl_int_static_teardown; }

@test "the entrypoint completed and exec'd the command (exit 0)" {
    [ "${NL_INT_STATIC_EXIT}" == "0" ]
}

@test "no deprecation warning and no error surfaced" {
    local stream
    for stream in stdout stderr; do
        if grep -qE "(WARNING: A custom 'step\.d/|Error)" "${NL_INT_STATIC_DIR}/${stream}" 2>/dev/null; then
            fail "unexpected warning/error in ${stream}"
        fi
    done
}
