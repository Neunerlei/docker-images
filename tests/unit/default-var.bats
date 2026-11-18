#!/usr/bin/env bats
# Tier 1 — util.d/default-var.sh
#
# Target: default_var — the tracked-default helper behind the environment
# pipeline's "derive twice" model (step.d/015-environment.sh). The helper is
# what makes recomputing defaults after every env-file pass safe:
#   - an empty variable gets the default;
#   - a user-set value is never touched (and never recorded);
#   - a value the helper itself set last time is recomputed (inputs changed);
#   - a value equal to an EARLIER default but modified since is user-owned.
#
# The contract in one line: default_var only ever overwrites a value it
# cannot distinguish from its own last assignment.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "util.d/default-var.sh"
}

teardown() {
    nl_unit_teardown
}

@test "sets and exports the value when the variable is empty" {
    unset TESTVAR 2>/dev/null || true
    default_var TESTVAR "fallback"
    [ "${TESTVAR}" == "fallback" ]
    export | grep -q 'declare -x TESTVAR="fallback"'
}

@test "keeps a value the user set before any default_var call" {
    export TESTVAR="user-value"
    default_var TESTVAR "fallback"
    [ "${TESTVAR}" == "user-value" ]
}

@test "recomputes a value the helper set itself when the default changes" {
    default_var TESTVAR "pass-one-default"   # empty -> set + record
    default_var TESTVAR "pass-two-default"   # still the recorded value -> recompute
    [ "${TESTVAR}" == "pass-two-default" ]
}

@test "leaves a value equal to an earlier default but changed since" {
    default_var TESTVAR "a"    # pass 1: helper sets "a"
    default_var TESTVAR "b"    # pass 2: recomputed, registry now "b"
    export TESTVAR="a"         # user sets the EARLIER default value by hand
    default_var TESTVAR "c"    # pass 3: "a" != recorded "b" -> user value
    [ "${TESTVAR}" == "a" ]
}

@test "keeps a user value that was set between two passes" {
    default_var TESTVAR "docker-default"
    export TESTVAR="from-env-file"           # what a custom env file pass does
    default_var TESTVAR "docker-default"     # the next derive pass
    [ "${TESTVAR}" == "from-env-file" ]
}

@test "a user value equal to the current default counts as not set (documented caveat)" {
    default_var TESTVAR "same-value"
    export TESTVAR="same-value"              # indistinguishable from the default
    default_var TESTVAR "changed-default"
    [ "${TESTVAR}" == "changed-default" ]
}

@test "supports empty-string defaults and recovers from them" {
    unset TESTVAR 2>/dev/null || true
    default_var TESTVAR ""                   # e.g. PHP_TIMEZONE with TZ unset
    [ -z "${TESTVAR}" ]
    export TZ="Europe/Berlin"
    default_var TESTVAR "${TZ}"              # still empty -> set for real
    [ "${TESTVAR}" == "Europe/Berlin" ]
    unset TZ
}

@test "records values only for variables it actually set" {
    export KEEP_ME="user"
    export RECOMPUTED=""
    default_var KEEP_ME "unused-default"
    default_var RECOMPUTED "helper-default"
    # KEEP_ME was user-set: never recorded. RECOMPUTED was helper-set: recorded.
    [ -z "${_default_var_registry[KEEP_ME]:-}" ]
    [ "${_default_var_registry[RECOMPUTED]}" == "helper-default" ]
    # The registry itself is not exported (get_all_vars also filters the
    # underscore prefix — both properties pinned here).
    ! export | grep -q '_default_var_registry'
}

@test "the registry is invisible to get_all_vars" {
    # The naming contract from util.d/get-all-vars.sh: lowercase and
    # underscore-prefixed names are filtered — the registry must not leak
    # into the template variable set or the container-vars.sh snapshot.
    # (`run` + status assert, NOT a bare `! grep`: a command's return value
    # inverted with `!` is exempt from errexit, so a bare mid-test `! grep`
    # could never fail this test — the same trap legacy-mount-guard.bats
    # documents.)
    nl_unit_source "util.d/get-all-vars.sh"
    default_var SOMEVAR "x"
    # The list goes into its own variable: every `run` overwrites
    # bats' $output, so feeding a later run from "${output}" would grep
    # the PREVIOUS run's (empty) result.
    local var_list
    var_list="$(get_all_vars)"
    run grep -qx '_default_var_registry' <<< "${var_list}"
    [ "${status}" -ne 0 ]
    run grep -qx 'SOMEVAR' <<< "${var_list}"
    [ "${status}" -eq 0 ]
}
