# LEGACY LAYER — environment pipeline reordering (015-image-vars / 017-custom-env absorbed)
# Migration guide: docs/migration/2026-11-17-environment-pipeline.md
# Compatibility layer until: 2027-11-17
#
# When this layer expires: delete this file, delete the
# "legacy_is_absorbed_step" argument in the step loop call of entrypoint.sh
# (source_files_in_dir_alphabetically "$step_dir" legacy_is_absorbed_step →
# source_files_in_dir_alphabetically "$step_dir") and note the removal in
# the migration guide. See docs/contributing.md, "Legacy compatibility
# layers (legacy.d)".
#
# The environment pipeline was reordered ("derive twice, track defaults"):
# the per-image step.d/015-image-vars.sh and the shared step.d/017-custom-env.sh
# no longer exist in the base images. Their roles moved to
# container/entrypoint/image-env.sh (per image, three optional functions) and
# to the shared orchestrator step.d/015-environment.sh (custom env loading
# plus the repeated derive passes), see util.d/default-var.sh for the
# default-tracking mechanism.
#
# OVERRIDE DETECTION IS BY FILE EXISTENCE: this repository ships neither
# file, so the presence of step.d/015-image-vars.sh or step.d/017-custom-env.sh
# in an image means a DOWNSTREAM image added one (COPY container /container
# overlays the common layer). The layer then restores the old precedence:
#
#   - A modified copy of the old 015 runs exactly where 015 used to run
#     (before the image's own features/defaults). Its CONTAINER_MODE decision
#     happens first, so the base image_env_features() skips (the mode is
#     already set; nginx additionally keeps overriding the "build" mode by
#     design). Its exported values count as USER-SET — default_var never
#     recorded them — and the base image_env_defaults() fills in only what is
#     still missing. That is exactly the pre-2026-11-17 precedence.
#   - A 015 that only ADDS exports changes nothing: the base feature/mode
#     logic still runs.
#   - A 017 override replaces BOTH env-file loads (static *.env and dynamic
#     *.env.sh). The derive passes still run around it, but only ever change
#     values that were defaulted.
#
# NOT SUPPORTED (documented in the migration guide): an override that
# REMOVES a feature the base image sets. feature_registry is additive; a
# downstream 015 copy that omits the base's features cannot switch them off.
#
# Scope note: source inside a function makes `declare` local — the same is
# true today for the step loop, which also sources step files inside a
# function.
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before the steps run.

# True for the two step files this migration absorbed. Used as the step-loop
# filter in entrypoint.sh, so a downstream 015-image-vars.sh / 017-custom-env.sh
# is skipped by the numeric loop (the orchestrator runs it at its correct
# position instead — otherwise it would run TWICE).
# Call site: entrypoint.sh, source_files_in_dir_alphabetically "$step_dir".
# Arguments:
#   $1 — the step file path about to be sourced
function legacy_is_absorbed_step() {
    case "${1##*/}" in
        015-image-vars.sh|017-custom-env.sh) return 0 ;;
    esac
    return 1
}

# Sources a downstream step.d/015-image-vars.sh if one exists (deprecation
# warning first). Runs before the image's own image_env_features(), exactly
# where the old 015 ran.
# Call site: step.d/015-environment.sh, between derive pass 1 and
# image_env_features.
function legacy_run_image_vars_override() {
    local step_file="${CONTAINER_ENTRYPOINT_DIR}/step.d/015-image-vars.sh"
    if [ ! -f "${step_file}" ]; then
        return 0
    fi
    echo "[ENTRYPOINT.environment] WARNING: A custom 'step.d/015-image-vars.sh' was found in this image. The step no longer exists in the base images — its role moved to 'container/entrypoint/image-env.sh'. It keeps working (sourced by the environment orchestrator, step.d/015-environment.sh) until 2027-11-17, afterwards it will be silently ignored. Move the logic into image-env.sh." >&2
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-17-environment-pipeline.md" >&2
    # shellcheck source=/dev/null
    source "${step_file}"
}

# True if a downstream step.d/017-custom-env.sh exists. Such an override
# replaces BOTH custom env file loads — the old step owned all of them.
# Call sites: step.d/015-environment.sh, before the static *.env load and
# before the dynamic *.env.sh load.
function legacy_custom_env_override_present() {
    [ -f "${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh" ]
}

# Sources a downstream step.d/017-custom-env.sh with a deprecation warning.
# Call site: step.d/015-environment.sh, in place of the static *.env load
# (guarded by legacy_custom_env_override_present).
function legacy_run_custom_env_override() {
    local step_file="${CONTAINER_ENTRYPOINT_DIR}/step.d/017-custom-env.sh"
    if [ ! -f "${step_file}" ]; then
        return 0
    fi
    echo "[ENTRYPOINT.environment] WARNING: A custom 'step.d/017-custom-env.sh' was found in this image. The step no longer exists in the base images — loading the custom env files is now handled by the environment orchestrator (step.d/015-environment.sh, util.d/load-custom-env-files.sh). It keeps working (replacing both env-file loads) until 2027-11-17, afterwards it will be silently ignored. Move the logic into a util.d helper or an env file." >&2
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-17-environment-pipeline.md" >&2
    # shellcheck source=/dev/null
    source "${step_file}"
}
