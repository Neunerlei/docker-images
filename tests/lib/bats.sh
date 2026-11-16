#!/usr/bin/env bash
# bats.sh — the pinned bats-core release used by Tier 1 (unit) and Tier 3
# (integration).
#
# The pin is version + URL + sha256 of the release tarball; it is downloaded
# into tests/.cache/ (gitignored) on demand and reused from there. One pinned
# version for host and container runs: the unit tier runs the SAME bats binary
# inside the image under test (bind-mounted read-only at /nl-test/bats), the
# integration tier runs it on the host — so an assertion can never pass on the
# host and fail in the image because of a bats version difference.
#
# bats-core is a single bash project: the extracted release runs wherever bash
# ≥ 3.2 exists, no compilation, no host dependencies. The suite's only network
# use is image pulls plus this one-time tooling download — like pulling a base
# image, it fetches a fixed, checksum-verified artifact, never anything
# generated at run time.

BATS_VERSION="1.11.0"
BATS_TARBALL_URL="https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz"
# sha256 of the pinned tarball — a changed release (or a tampered download)
# fails the run instead of silently changing the assertion engine.
BATS_TARBALL_SHA256="aeff09fdc8b0c88b3087c99de00cf549356d7a2f6a69e3fcec5e0e861d2f9063"

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Absolute path of the pinned, extracted bats-core tree (contains bin/bats).
function nl_bats_pin_dir() {
    printf '%s\n' "${tests_dir}/.cache/bats-core/bats-core-${BATS_VERSION}"
}

# Ensure the pinned bats-core is present under tests/.cache/, downloading and
# checksum-verifying it on demand. Prints the pin directory.
function nl_ensure_bats_pin() {
    local pin_dir tarball actual_sha256
    pin_dir="$(nl_bats_pin_dir)"
    tarball="${tests_dir}/.cache/bats-core/bats-core-${BATS_VERSION}.tar.gz"

    # The bin/bats check doubles as the extraction guard: an interrupted
    # download/extraction leaves no usable pin and is retried on the next run.
    if [ -x "${pin_dir}/bin/bats" ]; then
        printf '%s\n' "${pin_dir}"
        return 0
    fi

    mkdir -p "${tests_dir}/.cache/bats-core"
    if [ ! -f "${tarball}" ]; then
        nl_log "Fetching pinned bats-core v${BATS_VERSION} (${BATS_TARBALL_URL})"
        curl -fsSL --retry 3 -o "${tarball}" "${BATS_TARBALL_URL}" \
            || nl_die "Could not download the pinned bats-core release. The suite needs it once; every later run reuses the cached copy."
    fi

    actual_sha256="$(sha256sum "${tarball}" | awk '{print $1}')"
    if [ "${actual_sha256}" != "${BATS_TARBALL_SHA256}" ]; then
        nl_die "bats-core tarball checksum mismatch (expected ${BATS_TARBALL_SHA256}, got ${actual_sha256}). Delete ${tarball} and re-run."
    fi

    # The tarball extracts as bats-core-<version>/; move it into place, then
    # drop the archive — the extracted tree is what is reused and mounted.
    tar -xzf "${tarball}" -C "${tests_dir}/.cache/bats-core"
    [ -x "${pin_dir}/bin/bats" ] || nl_die "bats-core extraction did not produce ${pin_dir}/bin/bats."
    rm -f "${tarball}"
    nl_log "bats-core v${BATS_VERSION} pinned at ${pin_dir}"
    printf '%s\n' "${pin_dir}"
}
