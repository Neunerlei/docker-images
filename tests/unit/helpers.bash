#!/usr/bin/env bash
# Unit-test helpers for Tier 1, loaded by every tests/unit/*.bats via bats'
# `load`. This file runs INSIDE the image under test (run.sh mounts it at
# /nl-test/unit) and its whole job is to bridge the isolation of a unit test
# with the reality of the entrypoint code:
#
#   - the tests source the REAL files from /container/entrypoint/{util,legacy}.d
#     — never copies, so a drift between tests and shipped code is impossible;
#   - the functions under test read their paths from well-known environment
#     variables (CONTAINER_*); each test points them at a fresh sandbox under
#     /tmp so no test ever mutates the image's real state, and teardown removes
#     the sandbox again (bats gives every @test its own shell — the file-scope
#     state below is re-created per test, the filesystem is the only shared
#     thing between tests, hence the strict cleanup).

# The real implementation inside the image under test — the unit under test is
# the shipped file, not a checkout copy.
# bats evaluates this helper file several times per run inside one shell, and
# a plain `readonly` fires on every load ("UNIT_ENTRYPOINT_DIR: readonly
# variable" noise all over the TAP stream). The guard makes it a
# single-assignment constant: set once, then only read.
if [ -z "${UNIT_ENTRYPOINT_DIR:-}" ]; then
    readonly UNIT_ENTRYPOINT_DIR="/container/entrypoint"
fi

# The helpers use the bats ≥ 1.5 `run` flags API (`run --separate-stderr` for
# stderr assertions); the pinned release (1.11.0) guarantees it — declaring the
# minimum silences the per-use BW02 warning.
bats_require_minimum_version 1.5.0

# Per-test sandbox (set by nl_unit_sandbox, removed by nl_unit_teardown).
NL_UNIT_SANDBOX=""

# Source one of the REAL implementation files by its directory + file name.
# Usage: nl_unit_source util.d/basic-auth.sh
function nl_unit_source() {
    local relative="${1:?implementation file required}"
    # shellcheck source=/dev/null  # sourced from the image, not this repo
    source "${UNIT_ENTRYPOINT_DIR}/${relative}"
}

# Create a fresh per-test sandbox under /tmp and remember it for teardown.
# Prints the path; the global NL_UNIT_SANDBOX is what the tests use.
function nl_unit_sandbox() {
    NL_UNIT_SANDBOX="$(mktemp -d /tmp/nl-unit-sandbox-XXXXXX)"
    printf '%s\n' "${NL_UNIT_SANDBOX}"
}

# Remove the sandbox of the current test. Called from every file's teardown;
# safe when a test failed before creating one.
function nl_unit_teardown() {
    if [ -n "${NL_UNIT_SANDBOX}" ] && [ -d "${NL_UNIT_SANDBOX}" ]; then
        chmod -R u+w "${NL_UNIT_SANDBOX}" 2>/dev/null || true
        rm -rf "${NL_UNIT_SANDBOX}"
    fi
    NL_UNIT_SANDBOX=""
}

# Capture a function's stderr into a file inside the sandbox WITHOUT running it
# through bats' `run`: `run` executes in a subshell, which would swallow the
# global mutations of the legacy fallbacks (they rewrite the global
# entrypoint_command array — capturing that mutation IS the assertion).
# Usage: nl_unit_run_stderr <stderr-file> <command...>
function nl_unit_capture_stderr() {
    local stderr_file="${1:?stderr file required}"
    shift
    "$@" 2> "${stderr_file}"
}
