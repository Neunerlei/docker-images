#!/usr/bin/env bash
# Shared helpers for the docker-images test suite.
#
# Everything in here is host-side tooling — the probe (lib/probe.sh) is
# deliberately self-contained, because it runs INSIDE the container and must
# never depend on files that are not bind-mounted in.
#
# Conventions (mirroring the entrypoint code in src/_common):
#   - Suite log lines are prefixed "[NL-TEST]" so they are greppable next to
#     the "[ENTRYPOINT]" lines of a boot log.
#   - No fixed sleeps: waiting code always polls with a bounded deadline.
#   - Helpers are written for `set -euo pipefail` callers; arguments that may
#     legitimately be empty are read with ${x:-}.

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# Plain suite log line. Goes to stderr, so capture streams on stdout stay clean.
function nl_log() {
    printf '[NL-TEST] %s\n' "$*" >&2
}

# Warning: something is off, but the run can continue.
function nl_warn() {
    printf '[NL-TEST] WARNING: %s\n' "$*" >&2
}

# Fatal: abort the suite run with a readable message.
function nl_die() {
    printf '[NL-TEST] ERROR: %s\n' "$*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------

# The suite is docker end to end — without a working daemon nothing can run.
# The info query is deliberately not "docker ps": an unreachable daemon and a
# missing binary then produce different, diagnosable messages.
function nl_require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        nl_die "docker CLI not found in PATH. The test suite drives docker directly."
    fi
    if ! docker info >/dev/null 2>&1; then
        nl_die "docker daemon not reachable. Start the daemon and re-run."
    fi
}

# ---------------------------------------------------------------------------
# Container lifecycle
# ---------------------------------------------------------------------------

# Every container the suite starts carries "--label nl-test=1". The sweep runs
# at run.sh start and after runs, so a hard-killed run (SIGKILL skips traps)
# can never leave test containers behind to pollute the host — and never shadow
# container names on the next run.
function nl_sweep_test_containers() {
    local ids
    ids="$(docker ps -aq --filter 'label=nl-test=1' 2>/dev/null || true)"
    if [ -n "${ids}" ]; then
        nl_log "Sweeping leftover test containers: $(echo "${ids}" | wc -l) container(s)"
        # xargs -r: do not call docker rm at all when the list is empty
        echo "${ids}" | xargs -r docker rm -f >/dev/null
    fi
}

# Guarded removal of one named container. Used by capture traps: the container
# may already be gone (--rm, completed run), which must not fail the suite.
function nl_remove_container() {
    local name="${1:-}"
    [ -n "${name}" ] || return 0
    docker rm -f "${name}" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Readiness polling
# ---------------------------------------------------------------------------

# Poll a container's HTTP endpoint until it answers ANY response — the poll
# deliberately accepts 4xx/5xx (curl without -f): a 401 from a basic-auth
# scenario proves the server is up just as well as a 200. Fails hard when the
# boot has definitively failed, retries while the boot is merely slow:
# "container not found" right after `docker run` was started in the
# background usually means the client has not created it YET, not that it
# died — distinguishable via the client pid.
#
# Usage: nl_wait_for_http <container-name> [timeout-seconds] [path] [port] [client-pid]
# Returns 0 when ready; 1 on timeout; aborts (nl_die) when the boot failed.
function nl_wait_for_http() {
    local container="${1:?container name required}"
    local timeout="${2:-60}"
    local path="${3:-/}"
    local port="${4:-80}"
    local client_pid="${5:-}"
    local deadline=$((SECONDS + timeout))
    local url="http://127.0.0.1:${port}${path}"

    nl_log "Waiting up to ${timeout}s for HTTP readiness on ${url}..."
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        # Empty when the container does not exist (yet) — that is only a
        # failure if the `docker run` client has already exited.
        local running
        running="$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || echo "")"
        if [ "${running}" != "true" ]; then
            if [ -n "${client_pid}" ] && ! kill -0 "${client_pid}" 2>/dev/null; then
                docker logs "${container}" 2>&1 | tail -20 >&2 || true
                nl_die "docker run (pid ${client_pid}) exited without a running container while waiting for ${url}."
            fi
            if [ "${running}" == "false" ]; then
                docker logs "${container}" 2>&1 | tail -20 >&2 || true
                nl_die "Container '${container}' exited while waiting for ${url}."
            fi
        fi
        # The poll interval keeps this a poll loop, not a fixed sleep: the
        # first successful request ends the wait immediately.
        if docker exec "${container}" curl -sS -o /dev/null --max-time 2 "${url}" >/dev/null 2>&1; then
            nl_log "Container ready after ${SECONDS}s."
            return 0
        fi
        sleep 0.3
    done
    docker logs "${container}" 2>&1 | tail -20 >&2 || true
    return 1
}

# ---------------------------------------------------------------------------
# Scenario configuration parsing
# ---------------------------------------------------------------------------
# A scenario is data, not code (plan §2.3). scenario.conf holds key=value
# lines; '#' starts a comment. Parsed into the SCENARIO_* globals below —
# shared by run.sh (which iterates scenarios) and capture.sh (which runs one).
function nl_parse_scenario_conf() {
    local scenario_dir="${1:?scenario dir required}"
    local conf="${scenario_dir}/scenario.conf"
    [ -f "${conf}" ] || nl_die "No scenario.conf in ${scenario_dir}"

    SCENARIO_IMAGES=""
    SCENARIO_MODES="static live"
    SCENARIO_ENV_FILE="${scenario_dir}/env"
    # Like the env file, the docker-args file is auto-detected when present
    # (plan §2.3: all scenario files are optional; an explicit docker-args=
    # key may still point at a differently named file).
    SCENARIO_DOCKER_ARGS_FILE="${scenario_dir}/docker-args"
    SCENARIO_LEGACY_LAYER=""
    # command-mode=probe (default): the container command is
    #   "/nl-test/probe.sh static <scenario command...>" — the probe is exec'd
    #   and reports the full surface. command-mode=container: the scenario
    #   command IS the container command; the capture is the boot log plus the
    #   command's own stdout/stderr/exit code (used where the command handling
    #   itself is the observable, e.g. the legacy single-string scenarios).
    SCENARIO_COMMAND_MODE="probe"
    # dockerfile=<file in the scenario dir>: build-time scenario (plan §2.3) —
    # capture.sh builds the Dockerfile ON TOP of the image under test
    # (ARG BASE / FROM ${BASE}) and captures the derived image.
    SCENARIO_DOCKERFILE=""
    # wait-http=false: skip the HTTP readiness gate in live mode (worker-mode
    # scenarios have no web server; the supervisor RUNNING gate is the
    # readiness signal there).
    SCENARIO_WAIT_HTTP="true"
    # wait-running=false: replace the strict all-RUNNING supervisor gate with
    # the soft variant (phase-1 consumer parity): real consumer apps crash
    # without their databases, so some programs report BACKOFF/FATAL forever
    # — that is a recorded parity outcome, not a harness failure. The soft
    # gate only waits until supervisorctl is reportable at all (or the
    # container exited, which the stability window then records).
    SCENARIO_WAIT_RUNNING="true"
    # stability=<seconds>: bounded stability poll AFTER the readiness gates
    # (phase-1 consumer parity, plan §3.3 "start and STAY up"): polls the
    # container + supervisorctl status for the window; the container exiting
    # or programs leaving RUNNING ends up as an explicit verdict in the
    # stability.txt section. 0 (default) skips the window entirely.
    SCENARIO_STABILITY="0"
    # timeout=<seconds>: capture.sh's --timeout default for this scenario
    # (heavier consumer boots — vite dev servers, apt at boot — need more
    # than the 120s default; the --timeout flag still wins when given).
    SCENARIO_TIMEOUT=""
    # shellcheck disable=SC2034  # output contract, consumed by capture.sh
    SCENARIO_COMMAND=()
    SCENARIO_HTTP_PROBES=()

    local line key value
    while IFS= read -r line || [ -n "${line}" ]; do
        case "${line}" in
            ''|\#*) continue ;;
        esac
        [[ "${line}" == *=* ]] || nl_die "Malformed line in ${conf}: ${line}"
        key="${line%%=*}"
        value="${line#*=}"
        # The SCENARIO_* variables are the parser's OUTPUT CONTRACT: set here,
        # consumed by run.sh and capture.sh — standalone analysis of this file
        # cannot see that, hence the explicit suppression.
        # shellcheck disable=SC2034
        case "${key}" in
            images)       SCENARIO_IMAGES="${value}" ;;
            modes)        SCENARIO_MODES="${value}" ;;
            env)          SCENARIO_ENV_FILE="${scenario_dir}/${value}" ;;
            docker-args)  SCENARIO_DOCKER_ARGS_FILE="${scenario_dir}/${value}" ;;
            legacy-layer) SCENARIO_LEGACY_LAYER="${value}" ;;
            http-probe)   SCENARIO_HTTP_PROBES+=("${value}") ;;
            command-mode) SCENARIO_COMMAND_MODE="${value}" ;;
            dockerfile)   SCENARIO_DOCKERFILE="${value}" ;;
            wait-http)    SCENARIO_WAIT_HTTP="${value}" ;;
            wait-running) SCENARIO_WAIT_RUNNING="${value}" ;;
            stability)    SCENARIO_STABILITY="${value}" ;;
            timeout)      SCENARIO_TIMEOUT="${value}" ;;
            command)
                # The command may need EXACT argument boundaries (a legacy
                # single-string scenario passes one argument containing
                # double spaces — word splitting would destroy the very
                # behavior under test), so shell quoting is honored here.
                # eval is acceptable: scenario.conf is versioned test data in
                # this repository, not user input.
                eval "SCENARIO_COMMAND=( ${value} )"
                ;;
            *) nl_die "Unknown key '${key}' in ${conf}" ;;
        esac
    done < "${conf}"
}

# Poll a container's supervisor until EVERY program is in the RUNNING state.
# Used before the HTTP readiness poll in live captures: without this gate,
# supervisord's "entered RUNNING state" log lines (emitted startsecs=1 after
# spawn) race the probe's HTTP requests, and whether they land before or
# after an access-log line in the captured stream depends on scheduling.
# Gating on the actual state transition makes the boot log causal: boot
# lines, RUNNING lines, then — and only then — request lines.
#
# Usage: nl_wait_for_supervisor <container-name> [timeout-seconds] [client-pid]
function nl_wait_for_supervisor() {
    local container="${1:?container name required}"
    local timeout="${2:-60}"
    local client_pid="${3:-}"
    local deadline=$((SECONDS + timeout))

    nl_log "Waiting up to ${timeout}s for all supervisor programs to reach RUNNING..."
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        local running
        running="$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || echo "")"
        if [ "${running}" != "true" ]; then
            if [ -n "${client_pid}" ] && ! kill -0 "${client_pid}" 2>/dev/null; then
                docker logs "${container}" 2>&1 | tail -20 >&2 || true
                nl_die "docker run (pid ${client_pid}) exited without a running container while waiting for supervisor."
            fi
            if [ "${running}" == "false" ]; then
                docker logs "${container}" 2>&1 | tail -20 >&2 || true
                nl_die "Container '${container}' exited while waiting for supervisor."
            fi
            sleep 0.3
            continue
        fi
        local statuses
        statuses="$(docker exec "${container}" supervisorctl status 2>/dev/null \
            | awk '{print $2}' | LC_ALL=C sort -u || true)"
        # Every program RUNNING — and at least one program at all, so an
        # empty status output (socket not up yet) keeps us polling
        if [ "${statuses}" == "RUNNING" ]; then
            nl_log "All supervisor programs RUNNING after ${SECONDS}s."
            return 0
        fi
        sleep 0.3
    done
    docker exec "${container}" supervisorctl status 2>&1 | tail -20 >&2 || true
    return 1
}

# Soft variant of the supervisor gate for phase-1 consumer parity: real
# consumer apps crash without their databases, so "every program RUNNING"
# may never become true — that is a recorded parity outcome, not a harness
# failure. Waits only until supervisorctl reports at least one program line
# (ANY state — BACKOFF/FATAL are legitimate reportable states), while
# treating an early container exit as a RESULT (return 2) instead of dying.
# A timeout (return 3) is also non-fatal: the stability window records what
# actually happened.
#
# Usage: nl_wait_for_supervisor_report <container-name> [timeout-seconds] [client-pid]
function nl_wait_for_supervisor_report() {
    local container="${1:?container name required}"
    local timeout="${2:-60}"
    local client_pid="${3:-}"
    local deadline=$((SECONDS + timeout))

    nl_log "Waiting up to ${timeout}s for supervisorctl to become reportable (soft gate)..."
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        local running
        running="$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || echo "")"
        if [ "${running}" != "true" ]; then
            if [ -n "${client_pid}" ] && ! kill -0 "${client_pid}" 2>/dev/null && [ "${running}" == "" ]; then
                # Container never got created AND the client gave up: the
                # boot failed before supervisord could exist. Recorded, not
                # fatal — the streams in raw/ hold the boot failure.
                return 2
            fi
            if [ "${running}" == "false" ]; then
                return 2
            fi
        fi
        # Only REAL status lines count as "reportable": `program STATE ...`.
        # A rendered supervisor config with supervisord not yet up makes
        # supervisorctl print its connection error ("unix:///... no such
        # file") to STDOUT — that line must not count (verified on
        # php-nginx: supervisord.conf renders early, before custom
        # entrypoint scripts that may abort the boot).
        local lines
        lines="$(docker exec "${container}" supervisorctl status 2>/dev/null \
            | grep -cE '^[A-Za-z0-9_.:-]+[[:space:]]+[A-Z]{2,}' || true)"
        if [ "${lines}" -ge 1 ]; then
            nl_log "supervisorctl reportable after ${SECONDS}s."
            return 0
        fi
        sleep 0.3
    done
    return 3
}

# Bounded stability window for live captures (plan §3.3: supervised processes
# must start AND STAY up): polls the container state and supervisorctl status
# for <seconds>, then writes a deterministic verdict file. Poll loop with a
# deadline — no fixed sleeps. The file records ONLY timing-independent facts:
# the verdict (container alive / exited with which code), the window length
# and the FINAL status snapshot as sorted program=state pairs. Per-sample
# state histories are deliberately NOT recorded — how many BACKOFF samples
# land inside the window is scheduler-dependent and would make captures
# nondeterministic; the final status is the comparable fact.
#
# Usage: nl_stability_poll <container-name> <seconds> <out-file>
# Returns 0 when the container stayed alive for the whole window, 1 otherwise.
function nl_stability_poll() {
    local container="${1:?container name required}"
    local seconds="${2:?stability window seconds required}"
    local out_file="${3:?output file required}"
    local deadline=$((SECONDS + seconds))
    local final_status="" running exit_code=""

    nl_log "Stability window: polling ${container} for ${seconds}s..."
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        running="$(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null || echo "")"
        if [ "${running}" != "true" ]; then
            break
        fi
        # program=state pairs from REAL status lines only, sorted, states
        # only — no PIDs/uptimes (they are volatile and normalized away
        # everywhere else in the suite too). The grep filters supervisorctl's
        # stdout connection error the same way the soft readiness gate does.
        final_status="$(docker exec "${container}" supervisorctl status 2>/dev/null \
            | grep -E '^[A-Za-z0-9_.:-]+[[:space:]]+[A-Z]{2,}' \
            | awk '{print $1"="$2}' | LC_ALL=C sort | tr '\n' ' ' || true)"
        sleep 0.5
    done

    {
        printf 'window=%s\n' "${seconds}"
        if [ "${running}" == "true" ]; then
            printf 'verdict=stable\n'
            printf 'final-status: %s\n' "${final_status:-<supervisorctl not reportable>}"
        else
            exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${container}" 2>/dev/null || echo "unknown")"
            printf 'verdict=container-exited\n'
            printf 'exit=%s\n' "${exit_code}"
            [ -n "${final_status}" ] && printf 'last-status: %s\n' "${final_status}"
        fi
    } > "${out_file}"
    [ "${running}" == "true" ]
}

# ---------------------------------------------------------------------------
# Assertions (used by run.sh golden checks now, by bats helpers in checkpoint 3)
# ---------------------------------------------------------------------------

function nl_assert_equals() {
    local actual="${1:-}" expected="${2:-}" message="${3:-values differ}"
    if [ "${actual}" != "${expected}" ]; then
        nl_log "ASSERT FAILED: ${message}"
        nl_log "  expected: ${expected}"
        nl_log "  actual:   ${actual}"
        return 1
    fi
}

function nl_assert_contains() {
    local haystack="${1:-}" needle="${2:-}" message="${3:-substring not found}"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        nl_log "ASSERT FAILED: ${message}"
        nl_log "  needle: ${needle}"
        return 1
    fi
}
