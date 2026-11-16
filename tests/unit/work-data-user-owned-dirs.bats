#!/usr/bin/env bats
# Tier 1 — util.d/sync-work-data.sh, util.d/user-owned-dir.sh, and the
# legacy.d/2026-11-12-build-mode-marker-and-variables.sh call-site contract.
#
# Targets:
#   sync_work_data_into_staging / restore_work_data_staging_symlink
#       — the staging ↔ work reset semantics: a rendered real work-data copy
#         is synced back into the staging area, the build-time work/data →
#         staging symlink is restored, and a FAILED sync keeps the rendered
#         copy as a real directory (warning, not failure).
#   ensure_user_owned_dir
#       — creates/chowns www-data dirs, no-op when correct, and a read-only
#         mount is a warning instead of a boot failure.
#   legacy_finish_deprecated_build_mode
#       — the legacy build-mode end: deprecation warning + the same sync.
#
# Both sync and ownership functions take their paths from the CONTAINER_*
# environment — the tests point them at sandbox directories mirroring the
# real layout (<sandbox>/work/data, <sandbox>/staging as siblings, so the
# "../staging" relative symlink resolves exactly like in the image).

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "util.d/sync-work-data.sh"
    nl_unit_source "util.d/user-owned-dir.sh"
    STDERR_FILE="${NL_UNIT_SANDBOX}/stderr"
    # Sandbox layout mirroring the image: work/data and its staging sibling.
    export CONTAINER_WORK_DATA_DIR="${NL_UNIT_SANDBOX}/work/data"
    export CONTAINER_WORK_STAGING_DIR="${NL_UNIT_SANDBOX}/staging"
    mkdir -p "${NL_UNIT_SANDBOX}/work"
    mkdir -p "${CONTAINER_WORK_STAGING_DIR}"
}

teardown() {
    nl_unit_teardown
}

@test "restore_work_data_staging_symlink replaces a real work-data copy with the relative staging link" {
    mkdir -p "${CONTAINER_WORK_DATA_DIR}"

    restore_work_data_staging_symlink

    [ -L "${CONTAINER_WORK_DATA_DIR}" ]
    # The SAME relative shape the installer creates — later RUN steps of the
    # build stage write through it into the staging area
    [ "$(readlink "${CONTAINER_WORK_DATA_DIR}")" == "../staging" ]
    [ -d "${CONTAINER_WORK_DATA_DIR}/" ] # the link resolves to the staging dir
}

@test "sync_work_data_into_staging syncs a rendered copy into staging and restores the link" {
    # Pristine build-time state vs. later build-step changes (the "rendered copy")
    printf 'pristine' > "${CONTAINER_WORK_STAGING_DIR}/rendered.conf"
    mkdir -p "${CONTAINER_WORK_DATA_DIR}"
    printf 'rendered-at-build-time' > "${CONTAINER_WORK_DATA_DIR}/rendered.conf"

    sync_work_data_into_staging

    # The rendered state won: staging now holds it, the work data points at it
    [ "$(cat "${CONTAINER_WORK_STAGING_DIR}/rendered.conf")" == "rendered-at-build-time" ]
    [ -L "${CONTAINER_WORK_DATA_DIR}" ]
    [ "$(readlink "${CONTAINER_WORK_DATA_DIR}")" == "../staging" ]
    # The sync's temp copy is cleaned up
    local leftovers
    leftovers="$(compgen -G "${NL_UNIT_SANDBOX}/staging.build-sync.*" || true)"
    [ -z "${leftovers}" ]
}

@test "sync_work_data_into_staging leaves an already-linked work data alone" {
    # work/data IS the staging link already (build-time shape): nothing to
    # sync, the content must not be copied anywhere
    ln -s "../staging" "${CONTAINER_WORK_DATA_DIR}"
    printf 'staging-content' > "${CONTAINER_WORK_STAGING_DIR}/marker"

    sync_work_data_into_staging

    [ "$(cat "${CONTAINER_WORK_STAGING_DIR}/marker")" == "staging-content" ]
    [ "$(readlink "${CONTAINER_WORK_DATA_DIR}")" == "../staging" ]
}

@test "sync_work_data_into_staging recreates the link when the work data is missing entirely" {
    rm -rf "${CONTAINER_WORK_DATA_DIR}"

    sync_work_data_into_staging

    [ -L "${CONTAINER_WORK_DATA_DIR}" ]
}

@test "a failed sync keeps the rendered copy as a real directory and only warns" {
    # Force the failure the warning path exists for: the sync needs to create
    # its temp copy NEXT TO the staging dir — pointing the staging dir into
    # the read-only /nl-test/unit mount makes that creation fail with a REAL
    # EROFS (a chmod-based simulation would not stop root, which overrides
    # DAC permissions in the container).
    mkdir -p "${CONTAINER_WORK_DATA_DIR}"
    printf 'rendered-copy' > "${CONTAINER_WORK_DATA_DIR}/rendered.conf"
    printf 'pristine' > "${CONTAINER_WORK_STAGING_DIR}/marker"
    export CONTAINER_WORK_STAGING_DIR="/nl-test/unit/ro-staging-fixture"

    # `run` shields the test from errexit: the warning branch intentionally
    # continues after failed commands.
    run --separate-stderr sync_work_data_into_staging
    [ "${status}" -eq 0 ] # a failed sync must not fail the caller

    [ ! -L "${CONTAINER_WORK_DATA_DIR}" ]
    [ "$(cat "${CONTAINER_WORK_DATA_DIR}/rendered.conf")" == "rendered-copy" ]
    [[ "${stderr}" == *"could not sync the work data back into the staging area"* ]]
}

@test "legacy_finish_deprecated_build_mode warns and performs the same staging sync" {
    # The layer's whole contract at its call site (entrypoint.sh, build-mode
    # end, "legacy" case): deprecation warning pointing at the migration guide,
    # then the shared sync — later RUN steps' work-data changes survive boots.
    # (The warning lines go to STDOUT here — unlike the command fallback, this
    # function predates the >&2 convention; pinned as-is.)
    nl_unit_source "legacy.d/2026-11-12-build-mode-marker-and-variables.sh"
    mkdir -p "${CONTAINER_WORK_DATA_DIR}"
    printf 'legacy-rendered' > "${CONTAINER_WORK_DATA_DIR}/marker.conf"

    run --separate-stderr legacy_finish_deprecated_build_mode
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"build mode was invoked by running the entrypoint without a command"* ]]
    [[ "${output}" == *"deprecated and will fail in a future release"* ]]
    [[ "${output}" == *"migration/2026-11-12-build-mode-marker-and-variables.md"* ]]
    [ "$(cat "${CONTAINER_WORK_STAGING_DIR}/marker.conf")" == "legacy-rendered" ]
    [ -L "${CONTAINER_WORK_DATA_DIR}" ]
}

# ---------------------------------------------------------------------------
# ensure_user_owned_dir
# ---------------------------------------------------------------------------

@test "ensure_user_owned_dir creates a missing directory owned by www-data" {
    local dir="${NL_UNIT_SANDBOX}/app-data"

    run --separate-stderr ensure_user_owned_dir "${dir}"
    [ "${status}" -eq 0 ]
    [ -d "${dir}" ]
    [ "$(stat -c '%U:%G' "${dir}")" == "www-data:www-data" ]
}

@test "ensure_user_owned_dir chowns an existing non-www-data directory recursively" {
    local dir="${NL_UNIT_SANDBOX}/app-data"
    mkdir -p "${dir}/nested"
    printf 'x' > "${dir}/nested/file"
    chown -R root:root "${dir}"

    run --separate-stderr ensure_user_owned_dir "${dir}"
    [ "${status}" -eq 0 ]
    [ "$(stat -c '%U' "${dir}")" == "www-data" ]
    [ "$(stat -c '%U' "${dir}/nested/file")" == "www-data" ]
}

@test "ensure_user_owned_dir is a no-op when the ownership is already correct" {
    local dir="${NL_UNIT_SANDBOX}/app-data"
    mkdir -p "${dir}"
    chown www-data:www-data "${dir}"
    printf 'x' > "${dir}/file"
    chown www-data:www-data "${dir}/file"
    local ctime_before
    ctime_before="$(stat -c '%Z' "${dir}")"

    run --separate-stderr ensure_user_owned_dir "${dir}"
    [ "${status}" -eq 0 ]
    # ctime only changes on metadata writes — equality proves NO chown ran.
    # (Second granularity: a same-second chown could slip through the check,
    # but the assertion failing would be the false alarm direction, never a
    # silently-passing regression.)
    [ "$(stat -c '%Z' "${dir}")" == "${ctime_before}" ]
    [ "$(stat -c '%U' "${dir}/file")" == "www-data" ]
}

@test "ensure_user_owned_dir warns instead of failing when creation is impossible (read-only mount)" {
    # /nl-test/unit is the tests directory bind-mounted READ-ONLY into this
    # container — a path under it that does not exist yet cannot be created.
    local dir="/nl-test/unit/ro-fixture-not-creatable"

    run --separate-stderr ensure_user_owned_dir "${dir}"
    [ "${status}" -eq 0 ]
    [ ! -e "${dir}" ]
    [[ "${stderr}" == *"could not be created (read-only mount)"* ]]
}

@test "ensure_user_owned_dir warns instead of failing when chown is impossible (read-only mount)" {
    # The mount point itself exists (owned by root) and cannot be chowned.
    run --separate-stderr ensure_user_owned_dir "/nl-test/unit"
    [ "${status}" -eq 0 ]
    [[ "${stderr}" == *"ownership of '/nl-test/unit' could not be changed (read-only mount)"* ]]
}
