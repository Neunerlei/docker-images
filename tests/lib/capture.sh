#!/usr/bin/env bash
# capture.sh — boot one image for one scenario in one mode, collect the probe
# output, and write a normalized capture directory.
#
# Usage:
#   capture.sh --image <ref> --scenario <dir> --mode <static|live> \
#              --out <dir> [--label <name>] [--timeout <sec>] [--port <n>]
#
# Capture directory layout:
#   <out>/raw/         un-normalized streams + meta.txt (debugging only —
#                      never diffed, never committed)
#   <out>/sections/    one normalized file per probe section — the only part
#                      of a capture that is ever diffed or recorded as golden
#
# Phase-1 parity (plan §3) reuses this exact tooling against two tags: the
# capture is image-tag agnostic (decision §1.4), so "run the permanent capture
# against a main build and a branch build and diff" needs nothing else.
#
# Contract with lib/probe.sh:
#   - the probe is bind-mounted at /nl-test/ (ro), never baked into the image
#   - sections are delimited on the probe's stdout; a delimiter in the stderr
#     stream is a probe bug and fails the capture loudly
#   - in static mode the entrypoint's own boot log is everything before the
#     first delimiter on each stream and is recorded as the stdout/stderr
#     sections; in live mode the container log is recorded as the logs section
set -euo pipefail

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/helpers.bash
source "${tests_dir}/lib/helpers.bash"

nl_require_docker

# ---------------------------------------------------------------------------
# Stream splitting
# ---------------------------------------------------------------------------
# Split a captured stream at the probe's section delimiters. Lines before the
# first delimiter land in <preamble_name> (the entrypoint boot log in static
# mode). The section name is validated: it doubles as a file name.
function capture_split_stream() {
    local stream_file="${1:?stream file required}"
    local preamble_name="${2:?preamble section name required}"
    local sections_dir="${3:?sections dir required}"
    local current="${preamble_name}" line section_name

    : > "${sections_dir}/${current}"
    while IFS= read -r line || [ -n "${line}" ]; do
        if [[ "${line}" == "===== nl-test-section: "* && "${line}" == *" =====" ]]; then
            section_name="${line#===== nl-test-section: }"
            section_name="${section_name% =====}"
            [[ "${section_name}" =~ ^[A-Za-z0-9._-]+$ ]] \
                || nl_die "Probe emitted an invalid section name: '${section_name}'"
            : > "${sections_dir}/${section_name}"
            # All following lines belong to the new section until the next
            # delimiter switches the target again
            current="${section_name}"
        else
            printf '%s\n' "${line}" >> "${sections_dir}/${current}"
        fi
    done < "${stream_file}"
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------

image_ref="" scenario_dir="" mode="" out_dir="" label="branch" timeout="120" port="80"
timeout_arg_given=0

while [ $# -gt 0 ]; do
    case "$1" in
        --image)    image_ref="${2}"; shift 2 ;;
        --scenario) scenario_dir="${2}"; shift 2 ;;
        --mode)     mode="${2}"; shift 2 ;;
        --out)      out_dir="${2}"; shift 2 ;;
        --label)    label="${2}"; shift 2 ;;
        --timeout)  timeout="${2}"; timeout_arg_given=1; shift 2 ;;
        --port)     port="${2}"; shift 2 ;;
        *) nl_die "Unknown option for capture.sh: $1 (see file header for usage)" ;;
    esac
done

[ -n "${image_ref}" ]    || nl_die "capture.sh requires --image <ref>"
[ -n "${scenario_dir}" ] || nl_die "capture.sh requires --scenario <dir>"
[ -n "${out_dir}" ]      || nl_die "capture.sh requires --out <dir>"
case "${mode}" in static|live) ;; *) nl_die "--mode must be 'static' or 'live'" ;; esac
docker image inspect "${image_ref}" >/dev/null 2>&1 || nl_die "Image '${image_ref}' not found locally. Build it first (see lib/build-image.sh) or pass a pre-built ref."

scenario_dir="$(cd "${scenario_dir}" && pwd)"
nl_parse_scenario_conf "${scenario_dir}"

scenario_name="${scenario_dir##*/}"

# A scenario may carry its own default timeout (key `timeout=<seconds>`);
# an explicit --timeout flag wins over it.
if [ "${timeout_arg_given}" == "0" ] && [ -n "${SCENARIO_TIMEOUT}" ]; then
    timeout="${SCENARIO_TIMEOUT}"
fi

# Scenario-relative mounts: docker-args lines are shell-expanded below, so a
# line may reference "${SCENARIO_DIR}" to mount files out of the scenario
# directory regardless of where the harness was invoked from. Host-side only —
# it never reaches the container environment. Exported on purpose: the
# docker-args eval expands it, which shellcheck cannot see.
export SCENARIO_DIR="${scenario_dir}"

# Validate the command-mode contract (see helpers.bash for what each mode does).
case "${SCENARIO_COMMAND_MODE}" in
    probe) ;;
    container)
        if [ "${mode}" == "live" ]; then
            nl_die "Scenario '${scenario_name}' uses command-mode=container, which is a static-only convention (live boots the image's default command)."
        fi
        if [ ${#SCENARIO_COMMAND[@]} -eq 0 ]; then
            nl_die "Scenario '${scenario_name}' uses command-mode=container but defines no command= — the container would boot its default CMD instead of the command under test."
        fi
        ;;
    *) nl_die "Scenario '${scenario_name}' declares command-mode='${SCENARIO_COMMAND_MODE}' — must be 'probe' or 'container'" ;;
esac

# Sanity: the image should be one the scenario declares. A mismatch is not an
# error — the Phase-1 parity runs arbitrary tags — but it must be visible.
ref_name="${image_ref##*/}"; ref_name="${ref_name%%:*}"
if [[ "${SCENARIO_IMAGES}" != *"${ref_name}"* ]]; then
    nl_warn "Image '${ref_name}' is not in the scenario's image list (${SCENARIO_IMAGES}) — capturing anyway."
fi
case " ${SCENARIO_MODES} " in
    *" ${mode} "*) ;;
    *) nl_die "Mode '${mode}' is not in scenario ${scenario_name}'s modes (${SCENARIO_MODES})" ;;
esac

# ---------------------------------------------------------------------------
# Docker arguments
# ---------------------------------------------------------------------------

container_name="nl-test-${scenario_name}-${mode}-${label}"
container_name="$(printf '%s' "${container_name}" | tr -c 'a-zA-Z0-9-' '-')"

run_args=(
    --label "nl-test=1"
    --name "${container_name}"
)

# Scenario environment. docker --env-file takes the values verbatim (no shell
# quoting), which is exactly how compose env files behave — the scenario
# values with spaces ("username clear-password") arrive intact.
if [ -n "${SCENARIO_ENV_FILE}" ] && [ -f "${SCENARIO_ENV_FILE}" ]; then
    run_args+=(--env-file "${SCENARIO_ENV_FILE}")
fi

# Extra docker run arguments from the scenario. Each non-comment line is
# shell-expanded into the argument list — quoting is honored for the same
# reason as the command= eval above: this is versioned test data.
if [ -n "${SCENARIO_DOCKER_ARGS_FILE}" ] && [ -f "${SCENARIO_DOCKER_ARGS_FILE}" ]; then
    while IFS= read -r line || [ -n "${line}" ]; do
        case "${line}" in ''|\#*) continue ;; esac
        eval "run_args+=( ${line} )"
    done < "${SCENARIO_DOCKER_ARGS_FILE}"
fi

# The probe mount. /nl-test is a neutral path the image knows nothing about;
# read-only proves the probe is never written (and could never be baked in).
run_args+=(-v "${tests_dir}/lib:/nl-test:ro")

# A leftover container from a killed previous run would make `docker run`
# fail with a name conflict; remove it first (no-op when absent).
nl_remove_container "${container_name}"

# ---------------------------------------------------------------------------
# Build-time scenarios (plan §2.3)
# ---------------------------------------------------------------------------
# A scenario with a `dockerfile=` declaration builds that Dockerfile ON TOP of
# the image under test and captures the DERIVED image. The build (and the
# per-scenario/per-image/per-label derived tag) lives in ONE shared
# implementation, nl_build_scenario_image (lib/helpers.bash) — the golden and
# integration tiers must always exercise the same derived image.
if [ -n "${SCENARIO_DOCKERFILE}" ]; then
    image_ref="$(nl_build_scenario_image "${scenario_dir}" "${image_ref}" "${ref_name}" "${label}")"
fi

# ---------------------------------------------------------------------------
# Output directory
# ---------------------------------------------------------------------------

rm -rf "${out_dir}"
mkdir -p "${out_dir}/raw" "${out_dir}/sections"

cat > "${out_dir}/raw/meta.txt" <<EOF
image:      ${image_ref}
scenario:   ${scenario_name}
mode:       ${mode}
label:      ${label}
captured:   $(date -u +'%Y-%m-%dT%H:%M:%SZ')
EOF

# ---------------------------------------------------------------------------
# Static capture: the entrypoint runs all steps, then execs the probe
# ---------------------------------------------------------------------------

if [ "${mode}" == "static" ]; then
    trap 'nl_remove_container "${container_name}"' EXIT INT TERM

    nl_log "Static capture: ${scenario_name} / ${image_ref}"
    # Attached run: the container's stdout and stderr arrive as SEPARATE
    # streams on the docker client — the only way to record the entrypoint's
    # boot log per stream. --rm cleans the container on the happy path; the
    # label + name + trap cover the paths where it cannot.
    #
    # command-mode=probe (default): the probe is exec'd as the container
    # command after the entrypoint steps; the scenario command rides along as
    # its argv section. command-mode=container: the scenario command IS the
    # container command — its own stdout/stderr/exit code is the observable
    # (legacy command-argument handling, build-time evidence files); the probe
    # stays mounted (harness invariant) but is deliberately not exec'd, so the
    # capture holds only the boot-log preamble sections.
    set +e
    if [ "${SCENARIO_COMMAND_MODE}" == "container" ]; then
        timeout --foreground "${timeout}" \
            docker run --rm "${run_args[@]}" "${image_ref}" \
            "${SCENARIO_COMMAND[@]}" \
            > "${out_dir}/raw/stdout" 2> "${out_dir}/raw/stderr"
    else
        timeout --foreground "${timeout}" \
            docker run --rm "${run_args[@]}" "${image_ref}" \
            /nl-test/probe.sh static "${SCENARIO_COMMAND[@]}" \
            > "${out_dir}/raw/stdout" 2> "${out_dir}/raw/stderr"
    fi
    run_exit=$?
    set -e

    if [ "${run_exit}" == "124" ]; then
        nl_die "Static capture timed out after ${timeout}s — see ${out_dir}/raw/"
    fi
    # The entrypoint always logs its first line before anything else can go
    # wrong; its absence means the image never started (missing binary, bad
    # platform, ...) — a harness failure, not a capture result.
    if ! grep -q "Starting bootstrapping process" "${out_dir}/raw/stdout" "${out_dir}/raw/stderr"; then
        tail -5 "${out_dir}/raw/stderr" >&2 || true
        nl_die "Image '${image_ref}' never started the entrypoint — see ${out_dir}/raw/"
    fi

    capture_split_stream "${out_dir}/raw/stdout" "stdout" "${out_dir}/sections"
    # The probe must keep its sections on stdout; the stderr stream belongs
    # to the entrypoint alone.
    if grep -q "nl-test-section:" "${out_dir}/raw/stderr"; then
        nl_die "Probe wrote section delimiters to stderr — probe contract violated."
    fi
    capture_split_stream "${out_dir}/raw/stderr" "stderr" "${out_dir}/sections"

    printf '%s\n' "${run_exit}" > "${out_dir}/sections/exit-code"

    trap - EXIT INT TERM
fi

# ---------------------------------------------------------------------------
# Live capture: backgrounded boot, poll readiness, probe via docker exec
# ---------------------------------------------------------------------------
# The plan's table sketches this as `docker run -d` + `docker logs`. The run-
# over-run determinism check caught why that cannot work byte-stably: docker
# logs MERGES the container's stdout and stderr pipes, and the interleaving
# of two pipes is scheduler-dependent (the entrypoint legitimately writes
# [TEMPLATE] lines to stdout and "Template directory ... does not exist" to
# stderr at the same stage). So the live boot runs ATTACHED in the background
# instead: the two streams land in separate files, each a single pipe and
# therefore order-deterministic — the same mechanism the static capture uses.
# Killing the client (SIGKILL — signals would be proxied to supervisord!)
# detaches it; the container itself is removed via the trap.

if [ "${mode}" == "live" ]; then
    # kill + disown: SIGKILL detaches the boot without signal proxying, and
    # disown stops bash from announcing the reaped background job ("Killed")
    # into the suite log.
    detach_boot_client() {
        kill -9 "${run_pid}" 2>/dev/null || true
        disown "${run_pid}" 2>/dev/null || true
    }
    trap 'nl_remove_container "${container_name}"; detach_boot_client' EXIT INT TERM

    nl_log "Live capture: ${scenario_name} / ${image_ref}"
    docker run "${run_args[@]}" "${image_ref}" \
        > "${out_dir}/raw/stdout" 2> "${out_dir}/raw/stderr" &
    run_pid=$!

    # Gate 1: every supervised program RUNNING (see the helper for why this
    # comes first — it makes the boot log causal and therefore stable).
    # wait-running=false (phase-1 consumer parity): the soft gate instead —
    # consumer apps crash without their databases, so BACKOFF/FATAL programs
    # are a recorded outcome; an early container exit is recorded too and
    # skips the HTTP gate + probe below instead of failing the capture.
    container_exited_early=""
    if [ "${SCENARIO_WAIT_RUNNING}" == "true" ]; then
        if ! nl_wait_for_supervisor "${container_name}" "${timeout}" "${run_pid}"; then
            nl_die "Supervisor did not reach RUNNING state within ${timeout}s — see streams in ${out_dir}/raw/"
        fi
    else
        gate_rc=0
        nl_wait_for_supervisor_report "${container_name}" "${timeout}" "${run_pid}" || gate_rc=$?
        if [ "${gate_rc}" == "2" ]; then
            nl_log "Container exited before supervisord was reportable — recording the boot failure as the capture outcome."
            container_exited_early="readiness"
        elif [ "${gate_rc}" == "3" ]; then
            nl_warn "supervisorctl never became reportable within ${timeout}s — continuing to the stability window."
        fi
    fi
    # Gate 2: HTTP answering (should succeed on the first poll now). Scenarios
    # with wait-http=false skip this gate — worker-mode containers have no web
    # server to answer; there the supervisor RUNNING gate above is the
    # readiness signal.
    if [ -z "${container_exited_early}" ] && [ "${SCENARIO_WAIT_HTTP}" == "true" ]; then
        if ! nl_wait_for_http "${container_name}" "${timeout}" "/" "${port}" "${run_pid}"; then
            nl_die "Container did not become HTTP-ready within ${timeout}s — see streams in ${out_dir}/raw/"
        fi
    fi

    # Gate 3: stability window (opt-in via scenario `stability=<seconds>`,
    # phase-1 consumer parity "start and STAY up"): bounded poll after the
    # readiness gates; its verdict lands in sections/stability.txt. An early
    # container exit is the recorded outcome — the probe (docker exec into a
    # dead container) is skipped, the boot log stays in the logs sections.
    if [ "${SCENARIO_STABILITY}" -gt 0 ]; then
        if ! nl_stability_poll "${container_name}" "${SCENARIO_STABILITY}" "${out_dir}/sections/stability.txt"; then
            container_exited_early="stability"
        fi
    fi

    # The http-probe paths travel as probe ARGUMENTS, not environment: an
    # env var would leak into the entrypoint's exported variable snapshot
    # (get_all_vars picks up every exported uppercase name) and pollute the
    # captured surface with suite plumbing.
    if [ -z "${container_exited_early}" ]; then
        set +e
        timeout --foreground "${timeout}" \
            docker exec "${container_name}" /nl-test/probe.sh live "${SCENARIO_HTTP_PROBES[@]}" \
            > "${out_dir}/raw/probe-stdout" 2> "${out_dir}/raw/probe-stderr"
        exec_exit=$?
        set -e
        if [ "${exec_exit}" == "124" ]; then
            nl_die "Live probe timed out after ${timeout}s — see ${out_dir}/raw/"
        fi
        if grep -q "nl-test-section:" "${out_dir}/raw/probe-stderr"; then
            nl_die "Probe wrote section delimiters to stderr — probe contract violated."
        fi
    else
        : > "${out_dir}/raw/probe-stdout"
        : > "${out_dir}/raw/probe-stderr"
    fi

    # Detach the boot (SIGKILL: SIGTERM would be proxied and stop supervisord
    # before the trap can record anything), then remove the container.
    detach_boot_client

    # Preambles are named probe-stdout / probe-stderr: in live mode the entry
    # point did NOT exec the probe, so there is no boot-log-before-sections —
    # any content there is unexpected probe noise, kept visible as its own
    # (normally empty) section instead of being silently dropped.
    capture_split_stream "${out_dir}/raw/probe-stdout" "probe-stdout" "${out_dir}/sections"
    capture_split_stream "${out_dir}/raw/probe-stderr" "probe-stderr" "${out_dir}/sections"

    # The container's own streams are the live logs: boot log plus the
    # services' runtime output, per stream (the entrypoint's boot log is
    # INCLUDED here — in live mode it never appears before a section
    # delimiter, because the probe is exec'd by docker exec, not by the boot).
    capture_split_stream "${out_dir}/raw/stdout" "logs" "${out_dir}/sections"
    capture_split_stream "${out_dir}/raw/stderr" "logs-stderr" "${out_dir}/sections"

    trap - EXIT INT TERM
    nl_remove_container "${container_name}"
fi

# ---------------------------------------------------------------------------
# Normalization
# ---------------------------------------------------------------------------

# One pass over every section, from the ONE explicit list. Nothing gets
# normalized anywhere else in the suite.
local_section=""
for local_section in "${out_dir}/sections"/*; do
    sed -i -f "${tests_dir}/lib/normalize.sed" "${local_section}"
done

nl_log "Capture written to ${out_dir}/sections ($(printf '%s\n' "${out_dir}/sections"/* | xargs -n1 basename | tr '\n' ' '))"
