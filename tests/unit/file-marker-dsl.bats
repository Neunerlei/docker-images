#!/usr/bin/env bats
# Tier 1 — util.d/file-marker-conditions.sh + util.d/for-each-filtered-file-in-dir.sh
#
# Target: the filename-marker DSL — the framework's central configuration
# mechanism (contributing.md, "Metadata-Driven Configuration"):
#   `.` separates AND groups, `-or-` separates OR clauses within a group,
#   groups without any known marker are neutral (ignored).
#
# The conditions file registers into the SAME global registry the entrypoint
# uses, so the tests declare the registry first and then source the real
# files — exactly the entrypoint's own source order (entrypoint.sh declares,
# util.d fills).
#
# NOTE on patterns: for_each_filtered_file_in_dir feeds `find -maxdepth 1
# -name <pattern>` — with pattern "*" the STARTING DIRECTORY ITSELF matches
# and reaches the callback. Production callers therefore always pass a
# concrete pattern ("*.conf", "*.env", ...), and so does nl_dsl_run here.

load helpers

# The registry must exist before the conditions file registers its markers —
# this is the entrypoint.sh contract, replicated here. File scope runs once
# per test (bats re-executes this file in a fresh shell for every @test), so
# every test starts with the real registry and the real condition functions.
declare -gA file_marker_condition_registry
declare -g feature_registry=""

nl_unit_source "util.d/file-marker-conditions.sh"
nl_unit_source "util.d/for-each-filtered-file-in-dir.sh"

setup() {
    nl_unit_sandbox
    # The callback appends every processed path here; for_each_... runs in the
    # test's own shell (never via bats `run`), so the mutation is observable.
    NL_DSL_RESULTS=()
    NL_DSL_ARGS=()
    NL_DSL_RUN_SEQ=0
}

teardown() {
    nl_unit_teardown
}

function nl_dsl_collect() {
    NL_DSL_RESULTS+=("$1")
    NL_DSL_ARGS+=("$2 ${3:-}")
}

# Shorthand: create files in the sandbox and run the DSL over them. Every call
# gets a FRESH subdirectory (run-N) — a second call in the same directory would
# re-process the earlier files and pollute the result counting.
# Usage: nl_dsl_run <dir> <pattern> <file1> <file2>...
function nl_dsl_run() {
    local dir="$1" pattern="$2"
    shift 2
    local file
    NL_DSL_RUN_SEQ=$((NL_DSL_RUN_SEQ + 1))
    local run_dir="${dir}/run-${NL_DSL_RUN_SEQ}"
    mkdir -p "${run_dir}"
    for file in "$@"; do
        printf '# %s\n' "${file}" > "${run_dir}/${file}"
    done
    for_each_filtered_file_in_dir "${run_dir}" nl_dsl_collect "${pattern}"
}

@test "prod marker matches ENVIRONMENT=production only" {
    export ENVIRONMENT="production"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod.conf svc.dev.conf
    # Only the prod file processed; the dev file's group is not satisfied
    [ "${NL_DSL_RESULTS[0]##*/}" == "svc.prod.conf" ]
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
}

@test "dev marker matches ENVIRONMENT=development" {
    export ENVIRONMENT="development"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod.conf svc.dev.conf svc.plain.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 2 ]
    [ "${NL_DSL_RESULTS[0]##*/}" == "svc.dev.conf" ]
    [ "${NL_DSL_RESULTS[1]##*/}" == "svc.plain.conf" ]
}

@test "env-* wildcard matches any ENVIRONMENT value (env-staging)" {
    export ENVIRONMENT="staging"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.env-staging.conf svc.env-prod.conf svc.prod.conf
    # env-staging: the wildcard passes "staging" to the condition, ENVIRONMENT matches
    # env-prod: the condition maps "prod" to production, but ENVIRONMENT is staging
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
    [ "${NL_DSL_RESULTS[0]##*/}" == "svc.env-staging.conf" ]
}

@test "env-prod is satisfied by ENVIRONMENT=production through the wildcard alias" {
    export ENVIRONMENT="production"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.env-prod.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
}

@test "-or- group is satisfied when at least one clause matches (prod-or-env-staging)" {
    export ENVIRONMENT="staging"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod-or-env-staging.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]

    export ENVIRONMENT="production"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod-or-env-staging.conf
    [ "${NL_DSL_RESULTS[1]##*/}" == "svc.prod-or-env-staging.conf" ]

    # Neither clause holds → the file is skipped
    export ENVIRONMENT="development"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod-or-env-staging.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 2 ]
}

@test "https marker matches DOCKER_SERVICE_PROTOCOL=https only" {
    export ENVIRONMENT="production"
    export DOCKER_SERVICE_PROTOCOL="https"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.https.conf svc.plain.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 2 ]
    [ "${NL_DSL_RESULTS[0]##*/}" == "svc.https.conf" ]

    export DOCKER_SERVICE_PROTOCOL="http"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.https.conf
    # the file is NOT processed — only the two earlier results remain
    [ "${#NL_DSL_RESULTS[@]}" -eq 2 ]
}

@test "-or- group over different markers (https-or-dev)" {
    export ENVIRONMENT="development"
    export DOCKER_SERVICE_PROTOCOL="http"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.https-or-dev.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]

    export ENVIRONMENT="production"
    export DOCKER_SERVICE_PROTOCOL="https"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.https-or-dev.conf
    [ "${NL_DSL_RESULTS[1]##*/}" == "svc.https-or-dev.conf" ]

    export ENVIRONMENT="production"
    export DOCKER_SERVICE_PROTOCOL="http"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.https-or-dev.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 2 ] # neither clause → skipped
}

@test "AND across dot groups: prod.https requires both conditions" {
    export ENVIRONMENT="production"
    export DOCKER_SERVICE_PROTOCOL="https"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod.https.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]

    # production but plain http → not rendered
    export DOCKER_SERVICE_PROTOCOL="http"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod.https.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]

    # development with https → not rendered
    export ENVIRONMENT="development"
    export DOCKER_SERVICE_PROTOCOL="https"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.prod.https.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
}

@test "mode-* wildcard matches CONTAINER_MODE exactly" {
    export ENVIRONMENT="production"
    export CONTAINER_MODE="web"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" worker.mode-worker.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 0 ]

    export CONTAINER_MODE="worker"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" worker.mode-worker.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
}

@test "feat-* wildcard checks feature_registry membership on word boundaries" {
    export ENVIRONMENT="production"
    feature_registry="nginx supervisor"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" t.feat-nginx.conf t.feat-supervisor.conf t.feat-nginxx.conf
    # feat-nginx and feat-supervisor match; feat-nginxx must not (the padded
    # comparison " nginx " prevents the prefix hit)
    [ "${#NL_DSL_RESULTS[@]}" -eq 2 ]
    [ "${NL_DSL_RESULTS[0]##*/}" == "t.feat-nginx.conf" ]
    [ "${NL_DSL_RESULTS[1]##*/}" == "t.feat-supervisor.conf" ]
}

@test "groups without any known marker are neutral (unknown-marker files stay processed)" {
    # Documented DSL rule: a dot group that contains NO registered marker is
    # not a condition (that is how the "conf"/"sh" suffix groups pass). An
    # UNKNOWN marker therefore does not filter — only a KNOWN-but-false marker
    # does. Pinned here so a future "reject unknown markers" change is a
    # reviewed decision, not silent drift.
    export ENVIRONMENT="production"
    nl_dsl_run "${NL_UNIT_SANDBOX}" "*.conf" svc.bogus.conf
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
}

@test "the callback receives the full file path plus the additional arguments" {
    export ENVIRONMENT="production"
    local dir="${NL_UNIT_SANDBOX}/tpl"
    mkdir -p "${dir}"
    printf 'x' > "${dir}/one.prod.conf"
    for_each_filtered_file_in_dir "${dir}" nl_dsl_collect "*.conf" "extra-arg"
    [ "${NL_DSL_RESULTS[0]}" == "${dir}/one.prod.conf" ]
    [[ "${NL_DSL_ARGS[0]}" == *"extra-arg"* ]]
}

@test "the pattern argument restricts which files are considered" {
    export ENVIRONMENT="production"
    local dir="${NL_UNIT_SANDBOX}/tpl"
    mkdir -p "${dir}"
    printf 'x' > "${dir}/a.nginx.conf"
    printf 'x' > "${dir}/b.other.conf"
    for_each_filtered_file_in_dir "${dir}" nl_dsl_collect "*.nginx.conf"
    [ "${#NL_DSL_RESULTS[@]}" -eq 1 ]
    [ "${NL_DSL_RESULTS[0]##*/}" == "a.nginx.conf" ]
}

@test "an absent directory is skipped without failing" {
    run --separate-stderr for_each_filtered_file_in_dir "${NL_UNIT_SANDBOX}/does-not-exist" nl_dsl_collect "*.conf"
    [ "${status}" -eq 0 ]
}
