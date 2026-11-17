#!/usr/bin/env bats
# Tier 3 — worker-mode: the credential variables of a shared .env never reach
# the exec'd process tree (docs/common.md, "The credentials never leave the
# entrypoint").
#
# Worker mode is the leak case that motivated the name-pattern credential
# registry: a shared env file between the web and the worker container of one
# stack delivers NGINX_BASIC_AUTH / PROXY_<KEY>_BASIC_AUTH to a container
# whose mode NEVER reads them (no nginx feature runs here, and PROXY_GHOST_*
# has no matching PROXY_GHOST_CONTAINER service). Usage-based registration
# would see nothing to register; the pattern-based registration (steps 050 +
# 090) must keep the credentials out of the snapshot AND the environment.
#
# The golden (Tier 2) pins the snapshot's visible side (credentials absent
# from vars.sh, _REALM present, the "Not exporting variable" boot-log lines);
# THIS tier pins the live absence in PID 1's kernel environment.

load '../../lib/integration-helpers'

setup() {
    nl_int_load_state
}

setup_file() {
    nl_int_boot
}

teardown_file() {
    nl_int_teardown
}

# The leak contract is image-independent (the registry lives in the shared
# entrypoint), so one image pins it and the others skip — the same convention
# as basic-auth-global's php-only health-location tests.
image_is_php() { [ "${NL_TEST_IMAGE}" == "php-nginx" ]; }

@test "PID 1 (supervisord) boots without the shared-.env credentials (php-nginx)" {
    # PID 1 IS the entrypoint's final exec: step 100 unsets every registered
    # credential name right before it. Read from /proc/1/environ — the
    # kernel's view of what PID 1 actually received. This is the regression
    # pin for the worker-mode leak: without the pattern registration nothing
    # in worker mode ever READS these variables, the registry would stay
    # empty, and the credentials would flow straight into this environment.
    image_is_php || skip "asserted on one image; the registry is shared entrypoint code"
    run --separate-stderr docker exec "${NL_INT_CONTAINER}" bash -s <<'SCAN'
tr '\0' '\n' < /proc/1/environ | grep -E '^(NGINX_BASIC_AUTH(_[0-9]+)?|PROXY_[A-Za-z0-9_]+_BASIC_AUTH(_[0-9]+)?)=' && exit 1
exit 0
SCAN
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "the env file actually reached the container: _REALM is in PID 1's environment (php-nginx)" {
    # Positive control for the absence test above: the same env file delivers
    # NGINX_BASIC_AUTH_REALM, which is no credential and stays in the
    # environment on purpose. Without this control a broken env delivery
    # would make the absence tests pass vacuously.
    image_is_php || skip "asserted on one image"
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        "tr '\0' '\n' < /proc/1/environ | grep -c '^NGINX_BASIC_AUTH_REALM='"
    [ "${output}" -ge 1 ]
}

@test "no process in the container carries a credential — the worker included (php-nginx)" {
    # The worker command (`gosu www-data php …`) inherits supervisord's
    # environment; scanning every /proc/<pid>/environ keeps the assertion
    # independent of the process tree shape.
    image_is_php || skip "asserted on one image; the registry is shared entrypoint code"
    run --separate-stderr docker exec "${NL_INT_CONTAINER}" bash -s <<'SCAN'
for p in /proc/[0-9]*; do
    tr '\0' '\n' < "${p}/environ" 2>/dev/null
done | grep -E '^(NGINX_BASIC_AUTH(_[0-9]+)?|PROXY_[A-Za-z0-9_]+_BASIC_AUTH(_[0-9]+)?)=' && exit 1
exit 0
SCAN
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}
