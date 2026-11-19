# Persists the rendered work data for bootable build-mode runs.
#
# Syncs the current work-data copy back into the pristine staging area and
# restores the build-time work/data → work-data-staging symlink, so later
# `RUN` steps of the same build stage write through to the staging area and
# their changes SURVIVE boots (every boot resets the work data from the
# staging area). Used by "init-build-env --allow-boot" and by the deprecated
# no-command legacy build mode (see legacy.d/2026-11-12-build-mode-marker-
# and-variables.sh).
#
# Failure semantics: the symlink is only restored after a SUCCESSFUL sync (or
# when there is no rendered copy that could be lost). If the sync fails
# (read-only filesystem, no space left, ...), the work-data copy is kept as a
# real directory — it holds this run's rendered state, and deleting it would
# expose later `RUN` steps to the unrendered staging state. Only persistence
# across boots is lost in that case.
#
# Caveat: a successful sync bakes build-time rendered configuration —
# including anything rendered from build-time env values — into the pristine
# staging state. That is the price of a bootable build-mode image; don't
# render secrets at build time.

# Best-effort restore of the build-time work/data → staging symlink (the same
# relative link the installer creates), so later `RUN` steps of the same
# build stage write through to the staging area again. Never fails the boot:
# on a read-only filesystem a failing rm/ln must not abort the entrypoint.
function restore_work_data_staging_symlink() {
    rm -rf "${CONTAINER_WORK_DATA_DIR}" 2>/dev/null \
        && ln -s "../$(basename "${CONTAINER_WORK_STAGING_DIR}")" "${CONTAINER_WORK_DATA_DIR}" 2>/dev/null \
        || echo "[ENTRYPOINT] Warning: could not restore the work-data staging symlink (read-only filesystem?). Later build steps write into the work-data copy instead." >&2
}

function sync_work_data_into_staging() {
    if [ -d "${CONTAINER_WORK_DATA_DIR}" ] && [ ! -L "${CONTAINER_WORK_DATA_DIR}" ]; then
        echo "[ENTRYPOINT] Running in BUILD mode, syncing work data back into the staging area..."
        local staging_tmp="${CONTAINER_WORK_STAGING_DIR}.build-sync.$$"
        if rm -rf "${staging_tmp}" 2>/dev/null \
            && cp -a "${CONTAINER_WORK_DATA_DIR}" "${staging_tmp}" 2>/dev/null \
            && rm -rf "${CONTAINER_WORK_STAGING_DIR}" 2>/dev/null \
            && mv "${staging_tmp}" "${CONTAINER_WORK_STAGING_DIR}" 2>/dev/null; then
            echo "[ENTRYPOINT] Build-time changes to the work data were preserved in the staging area."
            # Only restored on success: the rendered copy is gone (moved into
            # the staging area), so later build steps must write through to it.
            restore_work_data_staging_symlink
        else
            # The sync failed. The work-data copy is intentionally KEPT as a
            # real directory: it holds this run's rendered state, and the
            # symlink restore would delete it, exposing later `RUN` steps to
            # the unrendered staging state. They keep reading and writing the
            # consistent copy — only persistence across boots is lost.
            rm -rf "${staging_tmp}" 2>/dev/null
            echo "[ENTRYPOINT] Warning: could not sync the work data back into the staging area (read-only filesystem? no space left?). Build-time changes will not survive the next boot; the work-data copy stays in place for the rest of this build stage." >&2
        fi
    else
        # Nothing to sync — work/data is already the staging symlink (or
        # missing entirely). No rendered copy exists that could be lost, so
        # (re-)creating the symlink is always safe.
        restore_work_data_staging_symlink
    fi
}
