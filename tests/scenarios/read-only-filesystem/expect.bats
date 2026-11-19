#!/usr/bin/env bats
# Tier 3 — read-only-filesystem: the documented read-only deployment
# (docs/common.md, "Running on a Read-Only Filesystem") boots AND serves on
# every image. The scenario's docker-args apply the documented set: --read-
# only plus tmpfs for the runtime directories and an EMPTY anonymous tmpfs at
# /container/work — the boot must seed the work data from the build-time
# staging area on a fresh mount (the branch's headline feature).
#
# Runs on ALL FOUR images (the runner picks each image from the scenario conf;
# NL_TEST_IMAGE selects the container name + ref per run).

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

@test "the read-only boot brings every supervised program to RUNNING" {
    local statuses
    statuses="$(docker exec "${NL_INT_CONTAINER}" supervisorctl status 2>/dev/null \
        | awk '{print $2}' | LC_ALL=C sort -u)"
    [ "${statuses}" == "RUNNING" ]
}

@test "the read-only container serves the document root with 200" {
    [ "$(nl_int_curl_status "/")" == "200" ]
}

@test "the work directory is writable despite the read-only root filesystem" {
    # /container/work is the documented writable mount (tmpfs here): the boot
    # seeds it, and writes by the services must succeed on it.
    docker exec "${NL_INT_CONTAINER}" sh -c 'echo nl-test > /container/work/.nl-test-write && cat /container/work/.nl-test-write && rm /container/work/.nl-test-write'
}

@test "the root filesystem is really read-only (the fixture is honest)" {
    # Guard against a silently dropped docker-args line: a writable root would
    # make the whole scenario meaningless.
    ! docker exec "${NL_INT_CONTAINER}" sh -c 'touch /nl-test-ro-probe 2>/dev/null'
}
