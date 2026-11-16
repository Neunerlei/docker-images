#!/usr/bin/env bash
# run.sh — entry point of the docker-images test suite.
#
# Usage:
#   run.sh [options] unit | golden [--update] | integration | all | bats-pin
#
# Options:
#   --image <name>=<ref>   Use a pre-built image for <name> (repeatable), e.g.
#                          --image nginx=nl-test/nginx:1.29-branch — lets a
#                          developer iterate on tests without rebuilding.
#   --tree <path>          Source tree the default images are built from
#                          (default: this checkout). Phase 1 points this at a
#                          git worktree to build "main".
#   --label <name>         Label for test container names (default: branch)
#   --force-build          Rebuild default images even if the tag exists
#   --only-image <name>    Limit every tier to ONE image (nginx, php-nginx,
#                          node-nginx, python-nginx) — used by the per-image
#                          CI workflows and handy when iterating locally.
#
# Commands:
#   unit          Tier 1: bats tests (tests/unit/*.bats) run INSIDE each image
#                 under test — one throwaway container per image per run, with
#                 the pinned bats-core and the tests mounted at neutral paths.
#                 Also runs the legacy-layer mapping check (cheap, static).
#   golden        Tier 2: capture every scenario and diff against the recorded
#                 goldens; --update re-records them (run it after REVIEWING the
#                 diff, never to make a red run green)
#   integration   Tier 3: the pinned bats-core runs tests/scenarios/*/expect.bats
#                 ON THE HOST; each expect.bats boots its scenario's containers
#                 and asserts the live behavior.
#   all           unit, golden, integration
#   bats-pin      Ensure the pinned bats-core release exists under
#                 tests/.cache/ and print its path (used by CI to warm the
#                 pin before the tiers run).
#
# Everything the suite starts on docker carries --label nl-test=1: the sweep
# below removes leftovers of hard-killed runs before anything starts.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tests_dir="${repo_root}/tests"

# shellcheck source=tests/lib/helpers.bash
source "${tests_dir}/lib/helpers.bash"
# shellcheck source=tests/lib/build-image.sh
source "${tests_dir}/lib/build-image.sh"
# shellcheck source=tests/lib/bats.sh
source "${tests_dir}/lib/bats.sh"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

TREE="${repo_root}"
FORCE_BUILD="false"
LABEL="branch"
declare -A IMAGE_OVERRIDES=()
# The images the suite covers — the four _common-based images. The legacy
# src/php images are out of scope (plan §1.5). This list backs --only-image
# validation and the unit tier's image loop; golden/integration derive their
# images from the scenarios' own declarations.
readonly SUITE_IMAGES=(nginx php-nginx node-nginx python-nginx)
ONLY_IMAGE=""

function usage() {
    sed -n '2,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2
}

# ---------------------------------------------------------------------------
# Default image handling
# ---------------------------------------------------------------------------

# Resolve the image ref for an image name: the --image override when given,
# otherwise build-if-needed from --tree under an nl-test/* tag. The tag uses
# the RESOLVED version directory (nl-test/nginx:1.29-branch), so it stays
# meaningful even though we build with --version latest.
function ensure_image() {
    local image="${1:?image name required}"
    local override="${IMAGE_OVERRIDES[${image}]:-}"
    if [ -n "${override}" ]; then
        printf '%s\n' "${override}"
        return 0
    fi

    local version_dir tag
    version_dir="$(nl_resolve_version_dir "${TREE}" "${image}" latest)"
    tag="nl-test/${image}:$(basename "${version_dir}")-${LABEL}"

    if [ "${FORCE_BUILD}" == "true" ] || ! docker image inspect "${tag}" >/dev/null 2>&1; then
        # The derived SOURCE_IMAGE (nl_source_image_ref) is verified by the
        # build itself: docker build fails loudly when the tag does not exist
        # on the registry — there is deliberately no network tag listing.
        nl_build_image --image "${image}" --version latest --source-tree "${TREE}" --tag "${tag}"
    fi
    printf '%s\n' "${tag}"
}

# Validate the --only-image value early: a typo would otherwise silently run
# NOTHING (every filter comparison would be false) and report a green run.
function nl_validate_only_image() {
    [ -z "${ONLY_IMAGE}" ] && return 0
    local image
    for image in "${SUITE_IMAGES[@]}"; do
        [ "${ONLY_IMAGE}" == "${image}" ] && return 0
    done
    nl_die "Unknown --only-image '${ONLY_IMAGE}'. Valid: ${SUITE_IMAGES[*]}"
}

# True when the given image is part of the (possibly filtered) run.
function nl_image_selected() {
    [ -z "${ONLY_IMAGE}" ] || [ "${ONLY_IMAGE}" == "${1}" ]
}

# ---------------------------------------------------------------------------
# Legacy-layer mapping check
# ---------------------------------------------------------------------------
# Every compatibility layer in src/_common/.../legacy.d/ must be referenced by
# at least one scenario's `legacy-layer=` tag (plan §4): when a layer is
# removed, its scenarios must be removed with it, and a new layer cannot land
# without a scenario exercising it. Checked in BOTH directions — the
# reverse also catches a scenario tag whose layer file no longer exists.
# Runs at the top of the unit tier: it is static repo data, costs nothing,
# and the unit tier is the first thing CI runs.

function nl_check_legacy_layer_coverage() {
    local legacy_dir="${repo_root}/src/_common/v1/container/entrypoint/legacy.d"
    local layer_file layer_name conf value name covered
    local -a layers=()
    local failures=0

    for layer_file in "${legacy_dir}"/*.sh; do
        layers+=("${layer_file##*/}")
    done

    # Collect every legacy-layer= tag value across all scenarios. Parsing with
    # grep/cut instead of nl_parse_scenario_conf keeps this readable for
    # anyone auditing the mapping without running the parser's full contract.
    local -a tags=()
    for conf in "${tests_dir}"/scenarios/*/scenario.conf; do
        value="$(grep -E '^legacy-layer=' "${conf}" | cut -d= -f2- || true)"
        [ -n "${value}" ] || continue
        for name in ${value}; do
            tags+=("${name}")
        done
    done

    # Direction 1: layer -> scenario. Every file in legacy.d needs coverage.
    for layer_name in "${layers[@]}"; do
        covered=""
        for name in "${tags[@]}"; do
            if [ "${name}" == "${layer_name}" ]; then covered="1"; break; fi
        done
        if [ -z "${covered}" ]; then
            nl_log "LEGACY-COVERAGE FAIL: legacy layer '${layer_name}' is not referenced by any scenario's legacy-layer= tag."
            nl_log "  Add the tag to a scenario that exercises this layer (tests/scenarios/<name>/scenario.conf), or remove the layer."
            failures=$((failures + 1))
        fi
    done

    # Direction 2: scenario -> layer. A tag pointing at a nonexistent file is
    # stale data left behind by a removed layer.
    for name in "${tags[@]}"; do
        if [ ! -f "${legacy_dir}/${name}" ]; then
            nl_log "LEGACY-COVERAGE FAIL: a scenario references legacy layer '${name}', which does not exist in ${legacy_dir}."
            failures=$((failures + 1))
        fi
    done

    if [ "${failures}" -gt 0 ]; then
        nl_die "Legacy-layer mapping check failed with ${failures} problem(s)."
    fi
    nl_log "Legacy-layer mapping check: ${#layers[@]} layer(s), all covered by scenarios."
}

# ---------------------------------------------------------------------------
# Tier 1 — unit
# ---------------------------------------------------------------------------

# Run the pinned bats INSIDE the image under test: the functions under test
# mutate the filesystem (bridges symlink into real paths, auth files are
# written, work-data syncs move directories) and need the image's production
# dependencies (findmnt, openssl, gosu, the www-data user). One throwaway
# container per image per run; the tests and bats are bind-mounted READ-ONLY
# at neutral /nl-test/* paths, so nothing of the suite can be mutated.
# The image entrypoint is deliberately bypassed (--entrypoint /bin/bash): a
# boot would run all entrypoint steps and dump their log into the TAP stream —
# unit tests source the REAL files from /container/entrypoint/ themselves and
# set up exactly the environment each function contract requires.
function cmd_unit() {
    nl_check_legacy_layer_coverage

    local bats_dir image ref container_name rc failures=0
    bats_dir="$(nl_ensure_bats_pin)"

    for image in "${SUITE_IMAGES[@]}"; do
        nl_image_selected "${image}" || continue
        ref="$(ensure_image "${image}")"
        container_name="nl-test-unit-${image}-${LABEL}"
        container_name="$(printf '%s' "${container_name}" | tr -c 'a-zA-Z0-9-' '-')"
        nl_remove_container "${container_name}"

        nl_log "unit: running tests/unit/*.bats inside ${ref}"
        # The bats process exit code is the tier verdict: a failing assertion
        # fails the run. --rm cleans the container on every path the client
        # survives; the label + sweep cover the rest.
        # The fixtures/etc-ssl-certs mount gives the legacy mount guard a real
        # host bind mount to detect (see legacy-mount-guard.bats); hiding the
        # CA bundle is harmless — the unit tests make no network use.
        set +e
        timeout --foreground 600 \
            docker run --rm \
                --label "nl-test=1" \
                --name "${container_name}" \
                --entrypoint /bin/bash \
                -v "${tests_dir}/unit:/nl-test/unit:ro" \
                -v "${tests_dir}/unit/fixtures/etc-ssl-certs:/etc/ssl/certs:ro" \
                -v "${bats_dir}:/nl-test/bats:ro" \
                "${ref}" \
                /nl-test/bats/bin/bats /nl-test/unit
        rc=$?
        set -e
        if [ "${rc}" -ne 0 ]; then
            nl_log "FAIL: unit tier inside ${image} (bats exit ${rc})"
            failures=$((failures + 1))
        fi
    done

    if [ "${failures}" -gt 0 ]; then
        nl_die "unit tier failed for ${failures} image(s)."
    fi
    nl_log "unit: green."
}

# ---------------------------------------------------------------------------
# Tier 3 — integration
# ---------------------------------------------------------------------------

# The pinned bats runs ON THE HOST over every scenario's expect.bats. The
# scenario data (env file, docker-args, http probes) is applied by the shared
# helpers in tests/lib/integration-helpers.bash, which each expect.bats loads;
# the runner only picks the scenario/image combinations and hands them over as
# NL_TEST_* environment variables. Each expect.bats boots its containers in
# setup_file and removes them in teardown_file; the label + sweep catch
# anything a hard kill leaves behind.
function cmd_integration() {
    local bats_dir scenario_dir scenario_name image ref
    local ran=0 failures=0
    bats_dir="$(nl_ensure_bats_pin)"

    for scenario_dir in "${tests_dir}"/scenarios/*/; do
        scenario_dir="${scenario_dir%/}"
        [ -f "${scenario_dir}/expect.bats" ] || continue
        scenario_name="${scenario_dir##*/}"
        nl_parse_scenario_conf "${scenario_dir}"

        local -a images=()
        read -r -a images <<< "${SCENARIO_IMAGES}"
        for image in "${images[@]}"; do
            nl_image_selected "${image}" || continue
            ref="$(ensure_image "${image}")"
            nl_log "integration: ${scenario_name} / ${image} (${ref})"
            ran=$((ran + 1))
            # The bounded timeout only guards against a hung docker call —
            # every wait inside the helpers polls with its own deadline.
            if ! timeout --foreground 600 \
                    env NL_TEST_SCENARIO_DIR="${scenario_dir}" \
                        NL_TEST_IMAGE="${image}" \
                        NL_TEST_IMAGE_REF="${ref}" \
                        NL_TEST_LABEL="${LABEL}" \
                        "${bats_dir}/bin/bats" "${scenario_dir}/expect.bats"; then
                nl_log "FAIL: integration ${scenario_name} / ${image}"
                failures=$((failures + 1))
            fi
        done
    done

    if [ "${ran}" -eq 0 ]; then
        nl_die "No scenario with expect.bats matched the current image selection."
    fi
    if [ "${failures}" -gt 0 ]; then
        nl_die "integration tier failed for ${failures} scenario/image combination(s)."
    fi
    nl_log "integration: green (${ran} combination(s))."
}

# ---------------------------------------------------------------------------
# Tier 2 — golden
# ---------------------------------------------------------------------------

function cmd_golden() {
    local update="false"
    while [ $# -gt 0 ]; do
        case "$1" in
            --update) update="true"; shift ;;
            *) nl_die "Unknown option for golden: $1" ;;
        esac
    done

    local scenario_dir image mode ref ref_name cache_dir golden_dir diff_out
    local -a scenario_dirs=()
    for scenario_dir in "${tests_dir}"/scenarios/*/; do
        if [ -f "${scenario_dir}/scenario.conf" ]; then
            scenario_dirs+=("${scenario_dir}")
        fi
    done
    if [ ${#scenario_dirs[@]} -eq 0 ]; then
        nl_die "No scenarios found in ${tests_dir}/scenarios/"
    fi

    local failures=0 missing=0 updated=0 passed=0

    for scenario_dir in "${scenario_dirs[@]}"; do
        scenario_dir="${scenario_dir%/}"   # the glob leaves a trailing slash
        nl_parse_scenario_conf "${scenario_dir}"
        local scenario_name="${scenario_dir##*/}"

        local -a images=()
        read -r -a images <<< "${SCENARIO_IMAGES}"
        local -a modes=()
        read -r -a modes <<< "${SCENARIO_MODES}"

        for image in "${images[@]}"; do
            nl_image_selected "${image}" || continue
            ref="$(ensure_image "${image}")"
            ref_name="${ref##*/}"; ref_name="${ref_name%%:*}"

            for mode in "${modes[@]}"; do
                cache_dir="${tests_dir}/.cache/captures/${scenario_name}/${ref_name}/${mode}"
                golden_dir="${scenario_dir}/golden/${ref_name}/${mode}"
                local test_id="${scenario_name} / ${ref_name} / ${mode}"

                if ! "${tests_dir}/lib/capture.sh" --image "${ref}" --scenario "${scenario_dir}" \
                        --mode "${mode}" --out "${cache_dir}" --label "${LABEL}"; then
                    nl_log "FAIL (capture failed): ${test_id}"
                    failures=$((failures + 1))
                    continue
                fi

                if [ "${update}" == "true" ]; then
                    rm -rf "${golden_dir}"
                    mkdir -p "${golden_dir}"
                    cp -r "${cache_dir}/sections/." "${golden_dir}/"
                    nl_log "RECORDED: ${test_id} -> scenarios/${scenario_name}/golden/${ref_name}/${mode}"
                    updated=$((updated + 1))
                    continue
                fi

                if [ ! -d "${golden_dir}" ]; then
                    nl_log "NO GOLDEN: ${test_id} — record it with: tests/run.sh golden --update (after reviewing the capture)"
                    missing=$((missing + 1))
                    continue
                fi

                if diff_out="$(diff -ru "${golden_dir}" "${cache_dir}/sections" 2>&1)"; then
                    nl_log "PASS: ${test_id}"
                    passed=$((passed + 1))
                else
                    nl_log "FAIL (golden mismatch): ${test_id}"
                    printf '%s\n' "${diff_out}"
                    failures=$((failures + 1))
                fi
            done
        done
    done

    nl_log "Golden summary: ${passed} passed, ${failures} failed, ${missing} without golden, ${updated} recorded."
    [ "${failures}" -eq 0 ] && [ "${missing}" -eq 0 ]
}

function cmd_all() {
    local result=0
    cmd_unit || result=$?
    cmd_golden "$@" || result=$?
    cmd_integration || result=$?
    return "${result}"
}

# ---------------------------------------------------------------------------
# Argument dispatch
# ---------------------------------------------------------------------------

# Options after the subcommand are forwarded to it (golden's --update)
command=""
extra_command_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --image)
            [[ "${2:-}" == *=* ]] || nl_die "--image expects <name>=<ref>"
            IMAGE_OVERRIDES["${2%%=*}"]="${2#*=}"
            shift 2
            ;;
        --tree)        TREE="$(cd "${2:?--tree needs a path}" && pwd)"; shift 2 ;;
        --label)       LABEL="${2:?--label needs a name}"; shift 2 ;;
        --force-build) FORCE_BUILD="true"; shift ;;
        --only-image)  ONLY_IMAGE="${2:?--only-image needs an image name}"; shift 2 ;;
        -h|--help)     usage ;;
        *)
            if [ -z "${command}" ]; then
                command="$1"
            else
                extra_command_args+=("$1")
            fi
            shift
            ;;
    esac
done

nl_validate_only_image

case "${command}" in
    unit)        nl_require_docker; nl_sweep_test_containers; cmd_unit ;;
    integration) nl_require_docker; nl_sweep_test_containers; cmd_integration ;;
    golden)      nl_require_docker; nl_sweep_test_containers; cmd_golden ${extra_command_args[@]+"${extra_command_args[@]}"} ;;
    all)         nl_require_docker; nl_sweep_test_containers; cmd_all ${extra_command_args[@]+"${extra_command_args[@]}"} ;;
    bats-pin)    nl_ensure_bats_pin >/dev/null ;;
    '')          usage ;;
    *)           nl_die "Unknown command: '${command}'" ;;
esac

# Belt and braces: traps in capture.sh clean their own containers; the sweep
# catches anything a kill-during-capture could have left behind.
nl_sweep_test_containers
