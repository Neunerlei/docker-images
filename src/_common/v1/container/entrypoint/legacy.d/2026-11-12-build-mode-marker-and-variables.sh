# LEGACY LAYER — build mode marker and variables (deprecated no-command build mode)
# Migration guide: docs/migration/2026-11-12-build-mode-marker-and-variables.md
# Compatibility layer until: 2027-11-12
#
# When this layer expires: delete this file, the "legacy" case in
# entrypoint.sh (search for "legacy_finish_deprecated_build_mode") and the
# "legacy" state of the CONTAINER_INIT_BUILD_ENV selector mapping, then note
# the removal in the migration guide. See docs/contributing.md, "Legacy
# compatibility layers (legacy.d)" and "Build Mode Internals".
#
# Invoking the entrypoint directly WITHOUT a command was the way builds
# worked before the "init-build-env" utility existed. This layer restores the
# ORIGINAL pre-marker behavior: everything runs, no marker is written (the
# image stays bootable), a deprecation warning points at the migration guide,
# and changes made by later build steps into the work data survive boots —
# the sync itself lives in util.d/sync-work-data.sh, shared with
# "init-build-env --allow-boot".
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before any state is changed.

# Finishes a legacy (no-command) build-mode run: deprecation warning plus the
# same work-data persistence "init-build-env --allow-boot" performs.
# Call site: entrypoint.sh, build-mode end branch, "legacy" case.
function legacy_finish_deprecated_build_mode() {
    echo "[ENTRYPOINT] Warning: build mode was invoked by running the entrypoint without a command."
    echo "[ENTRYPOINT] Warning: this is deprecated and will fail in a future release. Use the 'init-build-env' command instead."
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-12-build-mode-marker-and-variables.md"
    sync_work_data_into_staging
}
