#!/usr/bin/env bats
# Tier 3 — init-build-env-double-run: the marker written BETWEEN two
# build-mode runs is present in the BOOTED derived scenario image.
#
# The Dockerfile (built ON TOP of the image under test, see scenario.conf)
# already proves the build-time half: the final `RUN test -f` fails the
# scenario build when the sync-back between the two init-build-env runs
# regresses. THIS tier boots the derived image — the entrypoint resets the
# work data from the staging area on every boot — and asserts the live half:
# the marker must exist in the running container, i.e. it survived BOTH
# build-mode runs AND the boot reset.

load '../../lib/integration-helpers'

setup() {
    # bats runs each test in its own process — reload the boot state written
    # by setup_file (container name, etc.)
    nl_int_load_state
}

setup_file() {
    nl_int_boot
}

teardown_file() {
    nl_int_teardown
}

@test "the file written between the two init-build-env runs is present in the booted scenario image" {
    # double-run-marker: written by a plain `RUN touch` BETWEEN the first
    # (plain) and the second (--allow-boot) init-build-env run. Only the
    # sync-back of the first run makes it reach the staging area the boot
    # restores from — a regression removes exactly this file.
    run docker exec "${NL_INT_CONTAINER}" test -f /container/work/data/double-run-marker
    [ "${status}" -eq 0 ]
}

@test "the booted scenario image still carries the build-time proof file's content" {
    # The marker is not just an empty file claim: read its identity back.
    # (touch creates it empty — assert the path IS a regular empty file inside
    # the work data, not a dangling pointer into a stale layer path. GNU stat
    # prints "regular empty file" as the %F of a zero-byte regular file.)
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'stat -c "%F %s" /container/work/data/double-run-marker'
    [ "${status}" -eq 0 ]
    [[ "${output}" == "regular empty file 0"* ]]
}

@test "the boot is not refused: the supervisor is up with the php-fpm programs" {
    # The second init-build-env ran with --allow-boot, which removes the
    # build-mode marker an earlier plain run wrote. If that removal
    # regressed, the boot would refuse (exit 1) and this container would
    # never have reached the RUNNING gate in nl_int_boot — but the refusal
    # contract itself is pinned by init-build-env-refuses-boot; here we pin
    # the positive: fpm + nginx actually supervise.
    run docker exec "${NL_INT_CONTAINER}" supervisorctl status
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"php-fpm"*"RUNNING"* ]]
    [[ "${output}" == *"nginx"*"RUNNING"* ]]
}
