#!/bin/bash

# Environment orchestrator — the whole environment pipeline in one place.
# Absorbs the former step.d/017-custom-env.sh (custom env file loading) and
# the per-image step.d/015-image-vars.sh (image variables), which no longer
# exist in the base images (legacy.d/2026-11-17-environment-pipeline.sh
# keeps downstream overrides of both working until 2027-11-17).
#
# The problem this solves: values are DERIVED from other variables — upload
# byte sizes, keepalive timeouts, APP_ENV, PHP upload limits, ... — and those
# derivations used to run BEFORE the custom env files loaded, so every
# derived value was computed from the defaults forever. A .env with
# MAX_UPLOAD_SIZE=500M left NGINX_CLIENT_MAX_BODY_SIZE at 100M.
#
# A plain "load data first, derive afterwards" order cannot work either: the
# docs call static .env files the canonical place for project-level derived
# variables, and ${VAR} references in them expand at LOAD time. Loading them
# before the first derive pass would leave ${DOCKER_SERVICE_ABS_PATH} and
# friends empty. That is why everything derivable is derived MORE THAN ONCE:
#
#   pass 1: defaults exist (env files may reference them)
#   load *.env → pass 2: derivations see the static values
#   load *.env.sh → pass 3: derivations see the dynamic values too
#
# Recomputation is safe because every default goes through default_var
# (util.d/default-var.sh): a default that is still in place is recomputed, a
# value the user set is never touched. The order lives HERE, in code — not in
# step file names.
#
# Per-image environment logic is a file convention, not a step: an image may
# ship /container/entrypoint/image-env.sh with any subset of
#   image_env_features()  CONTAINER_MODE + feature_registry. Runs BEFORE the
#                         env files load, so mode-* and feat-* markers filter
#                         the env files like they always did.
#   image_env_defaults()  Runtime defaults, via default_var (tracked, so a
#                         later pass recomputes them from changed inputs).
#                         Runs after every derive pass; must be idempotent.
#   image_env_validate()  Checks that only make sense on final values (e.g.
#                         node's web command). Runs once, at the end.

echo "[ENTRYPOINT.environment] Configuring the environment pipeline..."

if [ -f "${CONTAINER_ENTRYPOINT_DIR}/image-env.sh" ]; then
    source "${CONTAINER_ENTRYPOINT_DIR}/image-env.sh"
fi

derive_common_env                                                   # 1. pass 1: everything a .env may reference

legacy_run_image_vars_override                                      # 2. LEGACY: a downstream step.d/015-image-vars.sh override runs exactly where 015 used to run

declare -F image_env_features >/dev/null && image_env_features      # 3. mode + features, before the env files are marker-filtered

declare -F image_env_defaults >/dev/null && image_env_defaults      # 4. image defaults, pass 1

if legacy_custom_env_override_present; then                         # 5. static *.env
    legacy_run_custom_env_override                                  #    (a LEGACY step.d/017-custom-env.sh override replaces BOTH loads)
else
    load_custom_env_files "*.env"
fi

derive_common_env                                                   # 6. pass 2: the .env inputs reach the derived values
declare -F image_env_defaults >/dev/null && image_env_defaults

legacy_custom_env_override_present || load_custom_env_files "*.env.sh"   # 7. dynamic *.env.sh

derive_common_env                                                   # 8. pass 3: the .env.sh inputs too
declare -F image_env_defaults >/dev/null && image_env_defaults

declare -F image_env_validate >/dev/null && image_env_validate      # 9. checks on the final values

echo "[ENTRYPOINT.environment] Environment pipeline completed."
