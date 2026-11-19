#!/usr/bin/env bats
# Tier 3 — basic-auth-malformed: a malformed NGINX_BASIC_AUTH value aborts the
# boot (docs/nginx.md: "a typo can never silently disable the protection").
#
# STATIC scenario: the boot exits 1 in step 020 before any command runs — the
# observable is the exit code plus the abort message in the boot log. The
# golden (Tier 2) pins the exact log bytes; this tier pins the CONTRACT (exit
# 1 + the named message) so a regression stays loud even if the log formatting
# drifts.

load '../../lib/integration-helpers'

setup() {
    # bats runs each test in its own process — reload the static-boot state
    # written by setup_file (exit code, stream dir)
    nl_int_load_state
}

setup_file() {
    # Attached run; the container removes itself (--rm). The command under it
    # is irrelevant — the abort happens before any command could run.
    nl_int_run_static true
}

teardown_file() {
    nl_int_static_teardown
}

@test "the boot exits 1 on the malformed NGINX_BASIC_AUTH value" {
    [ "${NL_INT_STATIC_EXIT}" -eq 1 ]
}

@test "the boot log names the invalid basic auth value and aborts" {
    grep -q "Invalid NGINX_BASIC_AUTH" "${NL_INT_STATIC_DIR}/stderr"
    grep -q "Aborting" "${NL_INT_STATIC_DIR}/stderr"
}

@test "the validation error comes from the writer, with the format reminder" {
    # The util-level message must teach the fix ("username clear-password"),
    # not just fail — and it must be the util that caught it (the writer's
    # validation, which the step-level abort wraps).
    grep -q "Malformed basic auth credential" "${NL_INT_STATIC_DIR}/stderr"
    grep -q "Expected format: 'username clear-password'" "${NL_INT_STATIC_DIR}/stderr"
}
