#!/usr/bin/env bats
# Tier 3 — puid-pgid-read-only: PUID/PGID on a read-only root filesystem
# aborts the boot cleanly (docs/common.md, "Read-only filesystems").
#
# STATIC scenario: the boot exits 1 in step 060, BEFORE any usermod/groupmod
# could die on the read-only /etc. The golden (Tier 2) pins the exact log
# bytes; this tier pins the CONTRACT (exit 1 + the named message) so a
# regression — a silent continue with the wrong ownership, or a raw
# usermod/groupmod lock error — stays loud even if the log formatting drifts.

load '../../lib/integration-helpers'

setup() {
    # bats runs each test in its own process — reload the static-boot state
    # written by setup_file (exit code, stream dir)
    nl_int_load_state
}

setup_file() {
    # Attached run; the container removes itself (--rm). The command under it
    # is irrelevant — the abort happens before any command could run.
    nl_int_run_static true
}

teardown_file() {
    nl_int_static_teardown
}

@test "the boot exits 1 when PUID/PGID is requested on a read-only root filesystem" {
    [ "${NL_INT_STATIC_EXIT}" -eq 1 ]
}

@test "the abort names the read-only limitation and the files that cannot be updated" {
    # The exact message of the step 060 guard — fixed text, so the contract
    # is pinned verbatim.
    grep -qF "[ENTRYPOINT.user-setup] Error: PUID/PGID are not supported with a read-only root filesystem (cannot update /etc/passwd and /etc/group). Aborting." \
        "${NL_INT_STATIC_DIR}/stderr"
}

@test "the abort happens before any usermod/groupmod attempt" {
    # The guard sits in front of the remap: neither the remap tools nor the
    # "Current www-data UID/GID" line (printed after the guard) may appear —
    # a raw "cannot lock /etc/group" here would mean the guard did not fire.
    ! grep -qE "usermod|groupmod|cannot lock" "${NL_INT_STATIC_DIR}/stderr"
    ! grep -q "Current www-data UID/GID" "${NL_INT_STATIC_DIR}/stderr"
}
