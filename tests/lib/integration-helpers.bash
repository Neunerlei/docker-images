#!/usr/bin/env bash
# Host-side helpers for the Tier 3 integration scenarios (expect.bats).
#
# Each scenario's expect.bats loads this file, boots its scenario in
# setup_file (nl_int_boot), asserts the live behavior in @test blocks, and
# removes its containers in teardown_file (nl_int_teardown). The scenario
# itself stays DATA: the same scenario.conf keys, env file and docker-args
# file the Tier 2 captures use are applied here — integration tests and
# goldens always describe the same boot.
#
# Conventions (inherited from lib/helpers.bash):
#   - every container carries --label nl-test=1 (sweep + removal by name);
#   - readiness is polled with bounded deadlines, never fixed sleeps;
#   - curl runs INSIDE the container (docker exec): no host port mapping,
#     no port juggling, identical answers on every machine.
#
# This file is loaded ONLY by bats (every expect.bats via `load`); the
# declaration below mirrors tests/unit/helpers.bash: the helpers use the
# bats ≥ 1.5 `run` flags API (`run --separate-stderr` for stderr
# assertions); the pin (1.11.0) guarantees it — declaring the minimum here
# silences the per-use BW02 warning for every expect.bats at once.
bats_require_minimum_version 1.5.0

# Resolve the suite's lib directory from this file's location, so the bats
# process gets the shared logging/gating/parsing helpers.
INT_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/helpers.bash
source "${INT_TESTS_DIR}/lib/helpers.bash"

# The container booted for the current scenario file (loaded per test by
# nl_int_load_state — see the state-file note below).
NL_INT_CONTAINER=""

# ---------------------------------------------------------------------------
# State hand-off between bats processes
# ---------------------------------------------------------------------------
# bats runs setup_file, every @test and teardown_file in SEPARATE bash
# processes — variables set in setup_file are invisible to the tests. The
# boot helpers therefore write their facts (container name, static exit
# code, stream dir) to a small state file under /tmp, and each test loads it
# via setup() -> nl_int_load_state. Key=value lines; values never contain
# '=' (container names are sanitized, exit codes numeric, paths plain).

function nl_int_state_file() {
    local scenario_dir="${NL_TEST_SCENARIO_DIR:?NL_TEST_SCENARIO_DIR not set}"
    local label="${NL_TEST_LABEL:-branch}"
    printf '/tmp/nl-int-state-%s-%s\n' "$(basename "${scenario_dir}")" "${label}"
}

function nl_int_write_state() {
    printf '%s\n' "$@" > "$(nl_int_state_file)"
}

function nl_int_load_state() {
    local state_file key value
    state_file="$(nl_int_state_file)"
    [ -f "${state_file}" ] || return 0
    while IFS='=' read -r key value; do
        case "${key}" in
            container)   NL_INT_CONTAINER="${value}" ;;
            static_exit) NL_INT_STATIC_EXIT="${value}" ;;
            static_dir)  NL_INT_STATIC_DIR="${value}" ;;
        esac
    done < "${state_file}"
}

# Boot the scenario's LIVE container: docker run -d with the scenario's env
# file + docker-args, then the same readiness gates the live captures use
# (supervisor RUNNING first — it makes the boot log causal — then HTTP).
# Requires the NL_TEST_* environment the run.sh integration runner provides.
function nl_int_boot() {
    local scenario_dir="${NL_TEST_SCENARIO_DIR:?NL_TEST_SCENARIO_DIR not set — run via tests/run.sh integration}"
    local image_ref="${NL_TEST_IMAGE_REF:?NL_TEST_IMAGE_REF not set}"
    local image_name="${NL_TEST_IMAGE:?NL_TEST_IMAGE not set}"
    local label="${NL_TEST_LABEL:-branch}"

    nl_parse_scenario_conf "${scenario_dir}"
    local scenario_name="${scenario_dir##*/}"

    local container_name="nl-test-int-${scenario_name}-${image_name}-${label}"
    container_name="$(printf '%s' "${container_name}" | tr -c 'a-zA-Z0-9-' '-')"
    nl_remove_container "${container_name}"

    # Scenario-relative paths resolve inside the docker-args eval, exactly
    # like capture.sh does.
    export SCENARIO_DIR="${scenario_dir}"

    local -a run_args=(
        --label "nl-test=1"
        --name "${container_name}"
        --detach
    )
    if [ -n "${SCENARIO_ENV_FILE}" ] && [ -f "${SCENARIO_ENV_FILE}" ]; then
        run_args+=(--env-file "${SCENARIO_ENV_FILE}")
    fi
    if [ -n "${SCENARIO_DOCKER_ARGS_FILE}" ] && [ -f "${SCENARIO_DOCKER_ARGS_FILE}" ]; then
        local line
        while IFS= read -r line || [ -n "${line}" ]; do
            case "${line}" in ''|\#*) continue ;; esac
            # Versioned test data — shell quoting honored (see capture.sh)
            eval "run_args+=( ${line} )"
        done < "${SCENARIO_DOCKER_ARGS_FILE}"
    fi

    docker run "${run_args[@]}" "${image_ref}" >/dev/null
    NL_INT_CONTAINER="${container_name}"
    nl_int_write_state "container=${container_name}"

    # Gate 1: every supervised program RUNNING (worker-mode scenarios declare
    # wait-http=false and rely on this gate alone).
    if ! nl_wait_for_supervisor "${NL_INT_CONTAINER}" 120; then
        nl_die "Integration boot of ${scenario_name}/${image_name}: supervisor never reached RUNNING."
    fi
    # Gate 2: HTTP answering (any status — a 401 proves readiness just as well)
    if [ "${SCENARIO_WAIT_HTTP}" == "true" ]; then
        if ! nl_wait_for_http "${NL_INT_CONTAINER}" 120; then
            nl_die "Integration boot of ${scenario_name}/${image_name}: never became HTTP-ready."
        fi
    fi
}

# Remove the scenario's containers. Called from teardown_file — and safe to
# call when the boot never happened. Also removes the state file.
function nl_int_teardown() {
    if [ -n "${NL_INT_CONTAINER}" ]; then
        nl_remove_container "${NL_INT_CONTAINER}"
        NL_INT_CONTAINER=""
    fi
    rm -f "$(nl_int_state_file)" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# HTTP assertions (curl inside the booted container)
# ---------------------------------------------------------------------------

# Status code of a GET request. Usage: nl_int_curl_status <path> [user:pass]
function nl_int_curl_status() {
    local path="${1:?request path required}"
    local userpass="${2:-}"
    local -a auth=()
    [ -n "${userpass}" ] && auth=(-u "${userpass}")
    docker exec "${NL_INT_CONTAINER}" curl -sS -o /dev/null --max-time 5 \
        -w '%{http_code}' "${auth[@]}" "http://127.0.0.1:80${path}" 2>/dev/null || printf '000'
}

# First value of one response header (CRs stripped so assertions compare
# clean). Usage: nl_int_curl_header <path> [user:pass] <header-name>
function nl_int_curl_header() {
    local path="${1:?request path required}"
    local userpass="${2:-}"
    local header="${3:?header name required}"
    local -a auth=()
    [ -n "${userpass}" ] && auth=(-u "${userpass}")
    docker exec "${NL_INT_CONTAINER}" curl -sS -o /dev/null -D - --max-time 5 \
        "${auth[@]}" "http://127.0.0.1:80${path}" 2>/dev/null \
        | tr -d '\r' | grep -iE "^${header}:" | head -n1 || true
}

# ---------------------------------------------------------------------------
# Static-boot assertions (aborts before any command — e.g. the malformed
# basic-auth scenario): attached run, exit code + streams recorded.
# ---------------------------------------------------------------------------

NL_INT_STATIC_EXIT=""
NL_INT_STATIC_DIR=""

# Boot the scenario ATTACHED and record exit code + stdout/stderr. Usage:
# nl_int_run_static [container-command...] (default: the image's CMD)
# The exit code and stream dir are written to the state file — bats runs the
# tests in a different process than setup_file (see nl_int_load_state).
function nl_int_run_static() {
    local scenario_dir="${NL_TEST_SCENARIO_DIR:?NL_TEST_SCENARIO_DIR not set}"
    local image_ref="${NL_TEST_IMAGE_REF:?NL_TEST_IMAGE_REF not set}"
    local label="${NL_TEST_LABEL:-branch}"
    nl_parse_scenario_conf "${scenario_dir}"
    local scenario_name="${scenario_dir##*/}"

    local container_name="nl-test-int-${scenario_name}-${NL_TEST_IMAGE}-${label}"
    container_name="$(printf '%s' "${container_name}" | tr -c 'a-zA-Z0-9-' '-')"
    nl_remove_container "${container_name}"
    export SCENARIO_DIR="${scenario_dir}"

    NL_INT_STATIC_DIR="$(mktemp -d /tmp/nl-int-static-XXXXXX)"
    local -a run_args=(--label "nl-test=1" --name "${container_name}" --rm)
    if [ -n "${SCENARIO_ENV_FILE}" ] && [ -f "${SCENARIO_ENV_FILE}" ]; then
        run_args+=(--env-file "${SCENARIO_ENV_FILE}")
    fi
    if [ -n "${SCENARIO_DOCKER_ARGS_FILE}" ] && [ -f "${SCENARIO_DOCKER_ARGS_FILE}" ]; then
        local line
        while IFS= read -r line || [ -n "${line}" ]; do
            case "${line}" in ''|\#*) continue ;; esac
            eval "run_args+=( ${line} )"
        done < "${SCENARIO_DOCKER_ARGS_FILE}"
    fi

    set +e
    if [ $# -gt 0 ]; then
        timeout --foreground 300 docker run "${run_args[@]}" "${image_ref}" "$@" \
            > "${NL_INT_STATIC_DIR}/stdout" 2> "${NL_INT_STATIC_DIR}/stderr"
    else
        timeout --foreground 300 docker run "${run_args[@]}" "${image_ref}" \
            > "${NL_INT_STATIC_DIR}/stdout" 2> "${NL_INT_STATIC_DIR}/stderr"
    fi
    # shellcheck disable=SC2034  # output contract, read by expect.bats
    NL_INT_STATIC_EXIT=$?
    set -e
    nl_int_write_state "container=${container_name}" "static_exit=${NL_INT_STATIC_EXIT}" "static_dir=${NL_INT_STATIC_DIR}"
}

function nl_int_static_teardown() {
    if [ -n "${NL_INT_STATIC_DIR}" ] && [ -d "${NL_INT_STATIC_DIR}" ]; then
        rm -rf "${NL_INT_STATIC_DIR}"
        NL_INT_STATIC_DIR=""
    fi
    rm -f "$(nl_int_state_file)" 2>/dev/null || true
}
