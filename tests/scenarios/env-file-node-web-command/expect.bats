#!/usr/bin/env bats
# Tier 3 — env-file-node-web-command: the container boots in web mode with a
# command that exists only in the .env file, and runs it.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the env-file web command runs as the node-server program" {
    run docker exec "${NL_INT_CONTAINER}" supervisorctl status node-server
    [ "${status}" -eq 0 ]
    printf '%s\n' "${output}" | grep -q 'RUNNING'
}

@test "NODE_WEB_COMMAND is exported with the env-file value" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${NODE_WEB_COMMAND}"'
    [ "${output}" == "node -e 'setInterval(function () {}, 60000)'" ]
}

@test "no boot failure: the validate check accepted the env-file command" {
    # The pre-reordering pipeline aborted exactly here ("NODE_WEB_COMMAND is
    # not set, but CONTAINER_MODE is 'web'") — reaching the RUNNING state
    # above already proves it; this pins the absence of the old abort line
    # in the boot log.
    if docker logs "${NL_INT_CONTAINER}" 2>&1 | grep -qF "NODE_WEB_COMMAND is not set, but CONTAINER_MODE is 'web'"; then
        fail "the old web-command abort fired although the env file provided a command"
    fi
}
