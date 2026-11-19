#!/usr/bin/env bats
# Tier 1 — legacy.d/2026-11-12-exact-command-arguments.sh
#
# Target: legacy_apply_single_string_command_fallback, the compatibility layer
# reproducing main's word splitting of a command passed as ONE string argument.
# It operates on the global `entrypoint_command` array — which is exactly why
# these tests call the function directly with stderr redirection instead of
# bats' `run` (a subshell would swallow the mutation, and the mutation IS the
# observable).
#
# Contract under test:
#   - exactly one non-executable argument containing whitespace → split like a
#     shell would (ALL whitespace, newlines included) + deprecation warning;
#   - embedded quotes stay LITERAL (the old quote handling is NOT reproduced);
#   - multi-argument commands and single executables pass through untouched.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "legacy.d/2026-11-12-exact-command-arguments.sh"
    STDERR_FILE="${NL_UNIT_SANDBOX}/stderr"
}

teardown() {
    nl_unit_teardown
}

@test "splits a single-string command with double spaces into argv plus deprecation warnings" {
    entrypoint_command=('echo a  b')
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 3 ]
    [ "${entrypoint_command[0]}" == "echo" ]
    [ "${entrypoint_command[1]}" == "a" ]
    [ "${entrypoint_command[2]}" == "b" ]

    grep -q 'Warning: the command was passed as a single string' "${STDERR_FILE}"
    grep -q 'Warning: this is deprecated and will fail in a future release' "${STDERR_FILE}"
    grep -q 'migration/2026-11-12-exact-command-arguments.md' "${STDERR_FILE}"
}

@test "splits a single-string command across newlines entirely" {
    # read -r -d '' consumes the WHOLE string — the old bug (everything after
    # the first newline silently dropped) must stay fixed: two lines → three args.
    entrypoint_command=$'echo a\nb'
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 3 ]
    [ "${entrypoint_command[0]}" == "echo" ]
    [ "${entrypoint_command[1]}" == "a" ]
    [ "${entrypoint_command[2]}" == "b" ]
}

@test "keeps embedded quotes literal — the old quote handling is deliberately NOT reproduced" {
    # Documented old behavior: quotes in the string survive as characters.
    # This is also why the argv fix is compatible: `sh -c` payloads that were
    # quoted lose their meaning here, exactly like on main.
    entrypoint_command=('sh -c "echo hi"')
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 4 ]
    [ "${entrypoint_command[0]}" == "sh" ]
    [ "${entrypoint_command[1]}" == "-c" ]
    [ "${entrypoint_command[2]}" == '"echo' ]
    [ "${entrypoint_command[3]}" == 'hi"' ]
}

@test "passes a properly split multi-argument command through untouched" {
    entrypoint_command=("npm" "run" "dev")
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 3 ]
    [ "${entrypoint_command[0]}" == "npm" ]
    [ "${entrypoint_command[1]}" == "run" ]
    [ "${entrypoint_command[2]}" == "dev" ]
    # No fallback may fire, no deprecation noise on stderr
    [ ! -s "${STDERR_FILE}" ]
}

@test "passes a properly passed sh -c command through untouched (the argv-fix control)" {
    # THE regression case of the branch: on main this three-argument command
    # was joined and re-split, destroying the -c payload (silent no-op). The
    # fallback must never touch exact argv.
    entrypoint_command=("sh" "-c" 'echo "$X"')
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 3 ]
    [ "${entrypoint_command[2]}" == 'echo "$X"' ]
    [ ! -s "${STDERR_FILE}" ]
}

@test "passes a single executable name through untouched" {
    entrypoint_command=("nginx")
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 1 ]
    [ "${entrypoint_command[0]}" == "nginx" ]
    [ ! -s "${STDERR_FILE}" ]
}

@test "does not split when the single string IS a resolvable command (no whitespace case)" {
    # A single argument without whitespace is either an executable or an error
    # — either way it is not this fallback's business. /nl-test/bats/bin/bats
    # is resolvable only by path here, which the executable check would accept;
    # a bare name must stay untouched because no splitting is defined for it.
    entrypoint_command=("supervisord")
    nl_unit_capture_stderr "${STDERR_FILE}" legacy_apply_single_string_command_fallback

    [ "${#entrypoint_command[@]}" -eq 1 ]
    [ "${entrypoint_command[0]}" == "supervisord" ]
    [ ! -s "${STDERR_FILE}" ]
}
