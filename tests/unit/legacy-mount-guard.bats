#!/usr/bin/env bats
# Tier 1 — legacy.d/2026-02-05-migrate-to-centralized-container-dir.sh
#
# Target: legacy_fail_on_legacy_mount_paths — the boot guard that aborts with
# migration instructions when a pre-2026-02 mount path is used.
#
# The guard's paths are hardcoded (/etc/ssl/certs, ...), so the test uses a
# REAL bind mount: run.sh mounts tests/unit/fixtures/etc-ssl-certs read-only
# at /etc/ssl/certs for every unit container (hiding the CA bundle is fine —
# unit tests make no network use). `legacy_is_mounted` classifies a path as
# "mounted from the host" when findmnt's SOURCE starts with "/" — true for
# bind mounts like this fixture, false for in-image overlay/tmpfs paths. That
# is why the un-mounted branches of the map (still overlay-backed here) are
# NOT detected — and the test pins exactly that discrimination.
#
# The function `exit`s on detection, so it must run in a subshell — bats'
# `run` already provides one.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "legacy.d/2026-02-05-migrate-to-centralized-container-dir.sh"
}

@test "the boot aborts with the migration message when a legacy mount path is bind-mounted" {
    # /etc/ssl/certs is the fixture mount (read-only, from the host)
    run legacy_fail_on_legacy_mount_paths
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Detected legacy mount paths. These are no longer supported."* ]]
    # The abort message names every detected path's replacement target
    [[ "${output}" == *"/etc/ssl/certs"* ]]
    [[ "${output}" == *"./docker:/container/custom"* ]]
    [[ "${output}" == *"migration/2026-02-05-migrate-to-centralized-container-dir.md"* ]]
}

@test "the guard only reports the paths that ARE mounted" {
    # Only /etc/ssl/certs of the five legacy paths is a host bind mount here —
    # the other four sit on the container's overlay and must NOT be listed.
    run legacy_fail_on_legacy_mount_paths
    [ "${status}" -eq 1 ]
    ! grep -q '/usr/bin/container/custom' <<< "${output}"
    ! grep -q '/etc/container/templates' <<< "${output}"
}
