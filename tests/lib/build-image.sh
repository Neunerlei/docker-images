#!/usr/bin/env bash
# Build one of OUR images from a given source tree under a test-local tag.
#
# This mirrors the exact `docker build` invocation of the release tooling
# (.github/.release/local-build.js):
#
#     cd <buildPath> && docker build -t <target>:<tag> \
#         --build-context common=<tree>/src/_common \
#         --progress=plain \
#         --build-arg SOURCE_IMAGE=<source-image-with-tag> .
#
# Two rules are non-negotiable here:
#   1. NEVER tag test images as "neunerlei/*". A local neunerlei/nginx tag would
#      shadow the registry image for EVERY other project on this machine that
#      builds FROM neunerlei/... — they would silently pick up the test build.
#      All test tags live under nl-test/<image>:<version>-<label>.
#   2. Version-directory fallback must behave exactly like the release tooling
#      (.github/.release/util/build-matrix-generation.js findBuildPath): the
#      requested version maps to the NEAREST PREVIOUS version directory, e.g.
#      php-nginx 8.5 -> src/php-nginx/8.2, node-nginx 25 -> 24, python-nginx
#      3.14 -> 3.13. Consumers build "8.5" while only an "8.2" implementation
#      directory exists.
#
# Unlike the release tooling, we do NOT list Docker Hub tags over the network
# (the suite's only allowed network use is image pulls): the SOURCE_IMAGE tag
# is derived from the workflow configuration table below as
# "<namespace>/<name>:<version>[-<filter>]". That is exactly the tag the
# release tooling selects when the version was discovered on the registry —
# `docker build` fails loudly if the derived tag does not exist.
#
# amd64 only: the release pipelines build multi-platform; the suite always
# pins --platform linux/amd64 so captures are comparable on every dev machine.

# ---------------------------------------------------------------------------
# Source image configuration (mirrors .github/workflows/<image>.yml)
# ---------------------------------------------------------------------------
# Keep this table in sync with the "with:" block of each publish workflow:
#   <image>|<source-image-namespace>/<source-image-name>|<source-image-type>|<source-image-os>
# The tag filter is built like the release tooling's buildTagFilterByArgs():
# "<type>" if set, then "-" then "<os>", so php-nginx resolves tags like
# "8.3-fpm-trixie". An image missing from this table (or without version
# directories, like the legacy src/php) is rejected with a clear error.
function nl_source_image_ref() {
    local image="${1:?image name required}"
    local version="${2:?version required}"
    local namespace name filter
    case "${image}" in
        nginx)        namespace="library"; name="nginx"; filter="trixie" ;;
        php-nginx)    namespace="library"; name="php"; filter="fpm-trixie" ;;
        node-nginx)   namespace="library"; name="node"; filter="trixie" ;;
        python-nginx) namespace="library"; name="python"; filter="slim-trixie" ;;
        *) nl_die "No source image configuration for image '${image}'. Add it to lib/build-image.sh, mirroring .github/workflows/${image}.yml." ;;
    esac
    printf '%s/%s:%s%s' "${namespace}" "${name}" "${version}" "${filter:+-${filter}}"
}

# ---------------------------------------------------------------------------
# Version comparison (semver.coerce semantics, in bash)
# ---------------------------------------------------------------------------

# Normalize a dotted numeric version to exactly three integer segments —
# the bash equivalent of semver.coerce() in docker-version-utils.js ("24"
# becomes 24.0.0, "1.29" becomes 1.29.0). Prints "a b c".
function nl_version_segments() {
    local version="${1:?version required}"
    local -a segs
    IFS='.' read -r -a segs <<< "${version}"
    printf '%d %d %d' "${segs[0]:-0}" "${segs[1]:-0}" "${segs[2]:-0}"
}

# Returns 0 when versionA <= versionB (segment-wise numeric).
function nl_version_lte() {
    local -a a b
    read -r -a a <<< "$(nl_version_segments "$1")"
    read -r -a b <<< "$(nl_version_segments "$2")"
    local i
    for i in 0 1 2; do
        if [ "${a[$i]}" -lt "${b[$i]}" ]; then return 0; fi
        if [ "${a[$i]}" -gt "${b[$i]}" ]; then return 1; fi
    done
    return 0
}

# Returns 0 when versionA > versionB.
function nl_version_gt() {
    ! nl_version_lte "$1" "$2"
}

# ---------------------------------------------------------------------------
# Version-directory fallback (release tooling findBuildPath, in bash)
# ---------------------------------------------------------------------------

# Resolve the build directory for an image + requested version inside a source
# tree: the newest version directory that is <= the requested version. The
# special version "latest" resolves to the newest directory, matching the
# release tooling where "latest" is always the newest tracked version.
#
# Usage: nl_resolve_version_dir <source-tree> <image> <version>
# Prints the absolute directory; fails when nothing matches.
function nl_resolve_version_dir() {
    local tree="${1:?source tree required}"
    local image="${2:?image name required}"
    local version="${3:?version required}"
    local base_dir="${tree}/src/${image}"

    if [ ! -d "${base_dir}" ]; then
        nl_die "Image source directory does not exist: ${base_dir}"
    fi

    local entry best="" name
    for entry in "${base_dir}"/*; do
        [ -d "${entry}" ] || continue
        name="${entry##*/}"
        # Only numeric dotted directories are version directories; anything
        # else in src/<image>/ (docs, scripts) must not hijack the fallback.
        [[ "${name}" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue
        if [ "${version}" == "latest" ]; then
            # "latest": track the highest directory seen so far
            if [ -z "${best}" ] || nl_version_gt "${name}" "${best}"; then
                best="${name}"
            fi
        else
            # Nearest previous: <= requested, but the highest such directory
            if nl_version_lte "${name}" "${version}"; then
                if [ -z "${best}" ] || nl_version_gt "${name}" "${best}"; then
                    best="${name}"
                fi
            fi
        fi
    done

    if [ -z "${best}" ]; then
        nl_die "No version directory <= '${version}' found in ${base_dir}."
    fi
    printf '%s\n' "${base_dir}/${best}"
}

# ---------------------------------------------------------------------------
# The build itself
# ---------------------------------------------------------------------------

# Build one image.
#
# Usage: nl_build_image --image <name> --version <version> \
#           --source-tree <path> --tag <output-tag> \
#           [--source-image <ref:tag>] [--no-platform] [--no-cache] \
#           [--cache-from <spec>] [--cache-to <spec>] [--load]
#
# --source-tree is the repository checkout to build from — NOT necessarily the
# current one: Phase 1 builds "main" from a git worktree and the branch from
# the current checkout, with byte-identical tooling.
#
# --cache-from/--cache-to are optional buildx cache specs (repeatable). They
# exist for CI (type=gha); the local default stays cache-flag-free so the
# network-free local path is untouched.
#
# --load is an opt-in passthrough for CI: the test engine builds through a
# docker-container-driver builder (docker/setup-buildx-action's default), and
# with that driver the result stays INSIDE the buildx cache unless --load
# exports it into the local Docker image store — without it, `docker run
# <tag>` in the tiers would find no image. Local builds run on the default
# docker driver, which loads automatically; they simply never pass the flag,
# keeping the local invocation unchanged.
#
# --no-cache is a verbatim docker build --no-cache passthrough (run.sh
# --no-cache): a full rebuild without layer reuse. The default rebuild stays
# cheap through BuildKit's cache, so this exists only for the rare "the cache
# itself is suspect" case.
function nl_build_image() {
    local image="" version="" source_tree="" tag="" source_image="" no_platform="false" no_cache="false" load="false"
    local -a cache_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --image) image="${2}"; shift 2 ;;
            --version) version="${2}"; shift 2 ;;
            --source-tree) source_tree="${2}"; shift 2 ;;
            --tag) tag="${2}"; shift 2 ;;
            --source-image) source_image="${2}"; shift 2 ;;
            --no-platform) no_platform="true"; shift ;;
            --no-cache) no_cache="true"; shift ;;
            --load) load="true"; shift ;;
            --cache-from) cache_args+=(--cache-from "${2}"); shift 2 ;;
            --cache-to) cache_args+=(--cache-to "${2}"); shift 2 ;;
            *) nl_die "Unknown option for nl_build_image: $1" ;;
        esac
    done

    [ -n "${image}" ] && [ -n "${version}" ] && [ -n "${source_tree}" ] && [ -n "${tag}" ] \
        || nl_die "nl_build_image requires --image, --version, --source-tree and --tag."

    # Test tags must never collide with registry names (see file header).
    if [[ "${tag}" == neunerlei/* ]]; then
        nl_die "Refusing to tag a test image as '${tag}': local neunerlei/* tags shadow the registry for every other project on this machine. Use nl-test/*."
    fi
    if [ ! -d "${source_tree}" ]; then
        nl_die "Source tree does not exist: ${source_tree}"
    fi
    # Absolutize the tree BEFORE any cd: the build below cd's into the build
    # directory, so a relative --source-tree (the CI workflow passes ".") would
    # resolve --build-context common=<tree>/src/_common against the wrong cwd.
    source_tree="$(cd "${source_tree}" && pwd)"

    local build_dir source_image_version
    build_dir="$(nl_resolve_version_dir "${source_tree}" "${image}" "${version}")"
    # The SOURCE_IMAGE tag follows the REQUESTED source version — that is what
    # the release tooling does (sourceVersion -> sourceImageWithTag), even when
    # the implementation directory is older (php-nginx 8.5 builds from dir 8.2
    # with the php:8.5 source image). "latest" is the one exception: it is not
    # a registry tag of the source image but the newest tracked version, i.e.
    # the resolved directory's version.
    source_image_version="${version}"
    if [ "${version}" == "latest" ]; then
        source_image_version="${build_dir##*/}"
    fi
    if [ -z "${source_image}" ]; then
        # Derived floating tag ("<namespace>/<name>:<version>[-<filter>]" —
        # the same ref the release tooling selects for a discovered version).
        # An explicit --source-image (the CI workflow, the version-agnostic
        # proof runs) still wins. The goldens are version-agnostic
        # (lib/normalize.sed normalizes upstream version VALUES by variable
        # name), so the floating tag moving with an upstream patch release
        # cannot turn the suite red — docker build fails loudly when the
        # derived tag does not exist at all.
        source_image="$(nl_source_image_ref "${image}" "${source_image_version}")"
    fi

    nl_log "Building ${tag}"
    nl_log "  source tree: ${source_tree}"
    nl_log "  build dir:   ${build_dir} (requested: ${version})"
    nl_log "  SOURCE_IMAGE: ${source_image}"

    local -a build_args=(
        --build-context "common=${source_tree}/src/_common"
        --progress=plain
        --build-arg "SOURCE_IMAGE=${source_image}"
    )
    # Pin the platform so a capture taken on an arm64 machine is still
    # comparable to the amd64 goldens (the release images publish multi-arch).
    if [ "${no_platform}" != "true" ]; then
        build_args+=(--platform linux/amd64)
    fi
    # CI cache specs land verbatim; empty locally (network-free default path)
    if [ ${#cache_args[@]} -gt 0 ]; then
        build_args+=("${cache_args[@]}")
    fi
    # Full rebuild without layer reuse (see the --no-cache docs above)
    if [ "${no_cache}" == "true" ]; then
        build_args+=(--no-cache)
    fi
    # Only appended when explicitly requested (see the --load docs above):
    # the local default docker driver already puts results into the image
    # store, so local callers never pass the flag and their invocation stays
    # byte-identical to before.
    if [ "${load}" == "true" ]; then
        build_args+=(--load)
    fi

    (
        set -e
        cd "${build_dir}"
        docker build -t "${tag}" "${build_args[@]}" .
    )
}

# When executed directly (not sourced), expose the resolution steps for
# debugging: `build-image.sh resolve <tree> <image> <version>` prints the
# resolved build directory and derived SOURCE_IMAGE.
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    # Library mode expectations: die() comes from helpers.bash, which callers
    # source first. For direct use, source it here.
    # shellcheck source=tests/lib/helpers.bash
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helpers.bash"
    case "${1:-}" in
        resolve)
            shift
            dir="$(nl_resolve_version_dir "${1:?tree}" "${2:?image}" "${3:?version}")"
            # Same "latest maps to the resolved version" rule as nl_build_image
            source_version="${3}"
            [ "${source_version}" == "latest" ] && source_version="${dir##*/}"
            printf 'build dir:    %s\n' "${dir}"
            printf 'SOURCE_IMAGE: %s\n' "$(nl_source_image_ref "${2}" "${source_version}")"
            ;;
        build)
            shift
            nl_build_image "$@"
            ;;
        *)
            nl_die "Usage: build-image.sh resolve <tree> <image> <version> | build <nl_build_image options>"
            ;;
    esac
fi
