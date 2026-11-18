#!/usr/bin/env bats
# Tier 1 — legacy.d/2026-11-17-environment-pipeline.sh
#
# Targets:
#   legacy_is_absorbed_step
#       — the step-loop filter: true exactly for the two absorbed step files,
#         so a downstream 015-image-vars.sh / 017-custom-env.sh is skipped by
#         the numeric loop (the orchestrator runs it instead).
#   legacy_run_image_vars_override / legacy_custom_env_override_present /
#   legacy_run_custom_env_override
#       — override detection BY FILE EXISTENCE plus the deprecation warning
#         contract (stable wording + migration guide URL, like the other
#         layers), and the sourcing itself.
#   source_files_in_dir_alphabetically + legacy_is_absorbed_step
#       — the entrypoint.sh call-site contract: with the filter, absorbed
#         step files are skipped and every other step still runs.
#
# The functions resolve the step files against ${CONTAINER_ENTRYPOINT_DIR};
# the tests point that at a sandbox copy so the real image's entrypoint
# directory is never mutated.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "legacy.d/2026-11-17-environment-pipeline.sh"
    export CONTAINER_ENTRYPOINT_DIR="${NL_UNIT_SANDBOX}/entrypoint"
    mkdir -p "${CONTAINER_ENTRYPOINT_DIR}/step.d"
}

teardown() {
    nl_unit_teardown
}

# ---------------------------------------------------------------------------
# legacy_is_absorbed_step
# ---------------------------------------------------------------------------

@test "the filter accepts exactly the two absorbed step files" {
    run legacy_is_absorbed_step "${CONTAINER_ENTRYPOINT_DIR}/step.d/015-image-vars.sh"
    [ "${status}" -eq 0 ]
    run legacy_is_absorbed_step "${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh"
    [ "${status}" -eq 0 ]
}

@test "the filter rejects the orchestrator and unrelated steps" {
    # The NEW orchestrator must keep running in the numeric loop — filtering
    # it would run the whole pipeline zero times.
    run legacy_is_absorbed_step "${CONTAINER_ENTRYPOINT_DIR}/step.d/015-environment.sh"
    [ "${status}" -ne 0 ]
    run legacy_is_absorbed_step "${CONTAINER_ENTRYPOINT_DIR}/step.d/018-php.sh"
    [ "${status}" -ne 0 ]
    run legacy_is_absorbed_step "${CONTAINER_ENTRYPOINT_DIR}/step.d/020-nginx.sh"
    [ "${status}" -ne 0 ]
}

@test "the filter matches on the file NAME, not the path" {
    # entrypoint.sh hands it the absolute path inside the image; a downstream
    # base image may nest the same step file under a different root.
    run legacy_is_absorbed_step "/somewhere/else/step.d/017-custom-env.sh"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# legacy_run_image_vars_override
# ---------------------------------------------------------------------------

@test "without a downstream 015-image-vars.sh the override is a silent no-op" {
    run --separate-stderr legacy_run_image_vars_override
    [ "${status}" -eq 0 ]
    [ -z "${stderr}" ]
}

@test "a downstream 015-image-vars.sh is sourced with the deprecation warning" {
    printf 'export LEGACY_015_RAN=yes\nexport LEGACY_MEMORY_LIMIT=256M\n' \
        > "${CONTAINER_ENTRYPOINT_DIR}/step.d/015-image-vars.sh"

    # In-process (not bats' `run`): the source must mutate THIS shell's
    # environment — a subshell would swallow the exports (helpers.bash).
    nl_unit_capture_stderr "${NL_UNIT_SANDBOX}/stderr" legacy_run_image_vars_override
    [ "${LEGACY_015_RAN}" == "yes" ]
    [ "${LEGACY_MEMORY_LIMIT}" == "256M" ]
    grep -qF "WARNING: A custom 'step.d/015-image-vars.sh' was found" "${NL_UNIT_SANDBOX}/stderr"
    grep -qF "until 2027-11-17" "${NL_UNIT_SANDBOX}/stderr"
    grep -qF "docs/migration/2026-11-17-environment-pipeline.md" "${NL_UNIT_SANDBOX}/stderr"
}

# ---------------------------------------------------------------------------
# legacy_custom_env_override_present / legacy_run_custom_env_override
# ---------------------------------------------------------------------------

@test "override presence is detected by file existence" {
    run legacy_custom_env_override_present
    [ "${status}" -ne 0 ]

    printf 'echo legacy-017\n' > "${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh"
    run legacy_custom_env_override_present
    [ "${status}" -eq 0 ]
}

@test "a downstream 017-custom-env.sh is sourced with the deprecation warning" {
    printf 'export LEGACY_017_RAN=yes\n' \
        > "${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh"

    # In-process: the source must mutate THIS shell (see helpers.bash).
    nl_unit_capture_stderr "${NL_UNIT_SANDBOX}/stderr" legacy_run_custom_env_override
    [ "${LEGACY_017_RAN}" == "yes" ]
    grep -qF "WARNING: A custom 'step.d/017-custom-env.sh' was found" "${NL_UNIT_SANDBOX}/stderr"
    grep -qF "until 2027-11-17" "${NL_UNIT_SANDBOX}/stderr"
    grep -qF "docs/migration/2026-11-17-environment-pipeline.md" "${NL_UNIT_SANDBOX}/stderr"
}

@test "without a downstream 017-custom-env.sh the runner is a silent no-op" {
    run --separate-stderr legacy_run_custom_env_override
    [ "${status}" -eq 0 ]
    [ -z "${stderr}" ]
}

# ---------------------------------------------------------------------------
# The entrypoint.sh call site: the step loop with the filter
# ---------------------------------------------------------------------------

@test "the step loop skips absorbed step files and sources everything else" {
    # source_files_in_dir_alphabetically is defined in entrypoint.sh — a
    # script, not a library, so it cannot be sourced without running a boot.
    # Extracting the function's text from the SHIPPED file keeps the test on
    # the real implementation (a copy here could drift silently).
    eval "$(sed -n '/^function source_files_in_dir_alphabetically/,/^}/p' \
        "${UNIT_ENTRYPOINT_DIR}/entrypoint.sh")"

    printf 'export STEP_015_RAN=yes\n' > "${CONTAINER_ENTRYPOINT_DIR}/step.d/015-image-vars.sh"
    printf 'export STEP_017_RAN=yes\n' > "${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh"
    printf 'export STEP_018_RAN=yes\n' > "${CONTAINER_ENTRYPOINT_DIR}/step.d/018-runtime.sh"
    printf 'export STEP_020_RAN=yes\n' > "${CONTAINER_ENTRYPOINT_DIR}/step.d/020-nginx.sh"

    source_files_in_dir_alphabetically "${CONTAINER_ENTRYPOINT_DIR}/step.d" legacy_is_absorbed_step

    [ -z "${STEP_015_RAN:-}" ]   # absorbed — the orchestrator runs it instead
    [ -z "${STEP_017_RAN:-}" ]   # absorbed — the orchestrator runs it instead
    [ "${STEP_018_RAN}" == "yes" ]
    [ "${STEP_020_RAN}" == "yes" ]
}

@test "the step loop without a filter still sources every file (layer expiry shape)" {
    # When the layer expires, only the filter argument is deleted — the loop
    # must keep working exactly like before the migration.
    eval "$(sed -n '/^function source_files_in_dir_alphabetically/,/^}/p' \
        "${UNIT_ENTRYPOINT_DIR}/entrypoint.sh")"

    printf 'export STEP_017_RAN=yes\n' > "${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh"

    source_files_in_dir_alphabetically "${CONTAINER_ENTRYPOINT_DIR}/step.d"

    [ "${STEP_017_RAN}" == "yes" ]
}
