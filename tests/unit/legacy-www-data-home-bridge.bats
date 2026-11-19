#!/usr/bin/env bats
# Tier 1 — legacy.d/2026-11-12-www-data-home-directory.sh
#
# Target: legacy_bridge_var_www_dotfiles — the bridge keeping legacy dotfiles
# under /var/www (the OLD www-data home) readable from the moved home
# (CONTAINER_WWW_DATA_HOME_DIR).
#
# The function reads /var/www as a hardcoded path — the tests create their
# dot-entries there for real (the image's /var/www only holds html/), point
# CONTAINER_WWW_DATA_HOME_DIR at a sandbox directory, and remove every created
# entry in teardown so no test can pollute the next one.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "legacy.d/2026-11-12-www-data-home-directory.sh"
    STDERR_FILE="${NL_UNIT_SANDBOX}/stderr"
    # The new home is a sandbox dir — the bridge writes ONLY there; the real
    # image home (/container/work/www-data-home) is never touched by this test.
    export CONTAINER_WWW_DATA_HOME_DIR="${NL_UNIT_SANDBOX}/home"
    mkdir -p "${CONTAINER_WWW_DATA_HOME_DIR}" "${NL_UNIT_SANDBOX}/var-www"
    # The dot-entries this test creates in /var/www (removed again in teardown;
    # setup and test body run in the SAME shell per bats test, so the array
    # needs no export)
    BRIDGE_CREATED=("${NL_UNIT_SANDBOX}/var-www/dummy")
}

teardown() {
    # Remove everything the test created under /var/www before the sandbox —
    # order does not matter, both go away.
    local entry
    if [ -n "${BRIDGE_CREATED:-}" ]; then
        for entry in "${BRIDGE_CREATED[@]}"; do
            rm -rf "${entry}"
        done
    fi
    # And the bridge links the function may have created IN the sandbox home
    # (only relevant when a test pointed the home elsewhere than the sandbox).
    if [ -d "${CONTAINER_WWW_DATA_HOME_DIR:-}" ]; then
        chmod -R u+w "${CONTAINER_WWW_DATA_HOME_DIR}" 2>/dev/null || true
    fi
    nl_unit_teardown
}

@test "bridges /var/www dotfiles into the home as symlinks with a deprecation warning" {
    printf 'npmrc-marker' > /var/www/.npmrc
    BRIDGE_CREATED+=("/var/www/.npmrc")

    nl_unit_capture_stderr "${STDERR_FILE}" legacy_bridge_var_www_dotfiles

    [ -L "${CONTAINER_WWW_DATA_HOME_DIR}/.npmrc" ]
    [ "$(readlink "${CONTAINER_WWW_DATA_HOME_DIR}/.npmrc")" == "/var/www/.npmrc" ]
    # Readable through the bridge — the property the bridge exists for
    [ "$(cat "${CONTAINER_WWW_DATA_HOME_DIR}/.npmrc")" == "npmrc-marker" ]

    grep -q "bridging legacy '/var/www/.npmrc'" "${STDERR_FILE}"
    grep -q 'migration/2026-11-12-www-data-home-directory.md' "${STDERR_FILE}"
}

@test "bridges dot-directories like .ssh as a whole" {
    mkdir -p /var/www/.ssh
    printf 'ssh-config-marker' > /var/www/.ssh/config
    BRIDGE_CREATED+=("/var/www/.ssh")

    nl_unit_capture_stderr "${STDERR_FILE}" legacy_bridge_var_www_dotfiles

    [ -L "${CONTAINER_WWW_DATA_HOME_DIR}/.ssh" ]
    [ "$(cat "${CONTAINER_WWW_DATA_HOME_DIR}/.ssh/config")" == "ssh-config-marker" ]
}

@test "never overwrites a pre-existing home entry" {
    # A real file already in the home wins — the bridge must neither replace
    # it with a symlink nor touch its content.
    printf 'home-wins' > "${CONTAINER_WWW_DATA_HOME_DIR}/.npmrc"
    printf 'var-www-version' > /var/www/.npmrc
    BRIDGE_CREATED+=("/var/www/.npmrc")

    nl_unit_capture_stderr "${STDERR_FILE}" legacy_bridge_var_www_dotfiles

    [ ! -L "${CONTAINER_WWW_DATA_HOME_DIR}/.npmrc" ]
    [ "$(cat "${CONTAINER_WWW_DATA_HOME_DIR}/.npmrc")" == "home-wins" ]
}

@test "removes a stale bridge link whose /var/www source has disappeared" {
    # A mount removed while the home lives on a named volume leaves a dangling
    # link — it must not accumulate over boots.
    ln -s /var/www/.gone "${CONTAINER_WWW_DATA_HOME_DIR}/.gone"
    # (no /var/www/.gone exists)

    # run is safe here: the bridge mutates the filesystem, not globals
    run --separate-stderr legacy_bridge_var_www_dotfiles
    [ "${status}" -eq 0 ]

    [ ! -e "${CONTAINER_WWW_DATA_HOME_DIR}/.gone" ] && [ ! -L "${CONTAINER_WWW_DATA_HOME_DIR}/.gone" ]
    # The removal notice goes to STDOUT (not >&2 like the bridging warning)
    [[ "${output}" == *"Removing stale bridge link"* ]]
}

@test "leaves real files and non-/var/www symlinks in the home alone" {
    printf 'real-dotfile' > "${CONTAINER_WWW_DATA_HOME_DIR}/.gitconfig"
    ln -s /tmp/somewhere-else "${CONTAINER_WWW_DATA_HOME_DIR}/.unrelated"

    nl_unit_capture_stderr "${STDERR_FILE}" legacy_bridge_var_www_dotfiles

    # The stale-link sweep only matches bridge-shaped links (target /var/www/*)
    [ -L "${CONTAINER_WWW_DATA_HOME_DIR}/.unrelated" ]
    [ "$(readlink "${CONTAINER_WWW_DATA_HOME_DIR}/.unrelated")" == "/tmp/somewhere-else" ]
    [ "$(cat "${CONTAINER_WWW_DATA_HOME_DIR}/.gitconfig")" == "real-dotfile" ]
}

@test "bridges only dot-entries, never the application tree" {
    mkdir -p /var/www/notadotdir
    printf 'app' > /var/www/notadotdir/index.html
    BRIDGE_CREATED+=("/var/www/notadotdir")

    nl_unit_capture_stderr "${STDERR_FILE}" legacy_bridge_var_www_dotfiles

    # html/ etc. are not dot-entries — bridging them would shadow the real
    # application tree in the home
    [ ! -e "${CONTAINER_WWW_DATA_HOME_DIR}/notadotdir" ]
}
