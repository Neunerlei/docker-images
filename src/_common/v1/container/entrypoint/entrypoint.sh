#!/bin/_bash
set -e

echo "[ENTRYPOINT] Starting bootstrapping process..."

declare entrypoint_dir="$(dirname $(realpath "${BASH_SOURCE[0]}"))"
declare step_dir="$entrypoint_dir/step.d"
declare util_dir="$entrypoint_dir/util.d"
declare legacy_dir="$entrypoint_dir/legacy.d"
declare -a entrypoint_command=("$@")

# If the entrypoint_command is empty, we automatically set the container mode to "build"
# This is useful when building libraries, running unit tests or simply want to initialize a multi-step build.
export CONTAINER_MODE=""
if [ ${#entrypoint_command[@]} -eq 0 ]; then
    export CONTAINER_MODE="build"
    echo "[ENTRYPOINT] No command specified, setting CONTAINER_MODE to 'build'."
fi

# There are three ways to reach build mode:
#
#  - NEW (supported): the "init-build-env" utility (/container/bin) sets the
#    CONTAINER_INIT_BUILD_ENV selector below before invoking this entrypoint.
#    That run writes the build mode marker at the end and syncs the work data
#    back into the staging area (so repeated runs keep accumulated state), but
#    an image built this way can never be booted as a final image — refusing
#    to boot is the expected behavior.
#  - NEW with --allow-boot: the same utility with the --allow-boot flag sets
#    the selector to "allow-boot" — full build mode, but NO marker is written
#    and a marker an earlier plain run left behind is REMOVED, so the image
#    may be booted (e.g. CI stages that run tests against a builder image).
#    The work data is synced back into the staging area, so changes made by
#    later build steps survive boots (util.d/sync-work-data.sh).
#  - LEGACY (deprecated compatibility layer, expires 2027-11-12): invoking the
#    entrypoint directly without a command, the way builds worked before the
#    marker existed. Everything runs, later `RUN` steps get the variables, no
#    marker is written — the image stays bootable — and, like images before
#    the work-data model, changes made by later build steps into the work data
#    survive boots (see legacy.d/2026-11-12-build-mode-marker-and-variables.sh).
#    A deprecation warning is logged.
#
# The selector is unset immediately: it is internal, and get_all_vars picks up
# every exported variable, so it must not leak into the container-vars.sh
# snapshot.
declare container_build_mode_invocation="legacy"
case "${CONTAINER_INIT_BUILD_ENV:-}" in
    "1") container_build_mode_invocation="new" ;;
    "allow-boot") container_build_mode_invocation="allow-boot" ;;
esac
unset CONTAINER_INIT_BUILD_ENV

echo "[ENTRYPOINT] Setting common environment variables..."

source "${entrypoint_dir}/common-env.sh"

# Sources all .sh files in the given directory in alphabetical order
#
# Usage:
#   source_files_in_dir_alphabetically "/path/to/directory"
function source_files_in_dir_alphabetically() {
    local dir_path="$1"
    if [ -d "$dir_path" ]; then
        while IFS= read -r -d '' file; do
            source "$file"
        done < <(find "$dir_path" -maxdepth 1 -name "*.sh" -print0 | sort -z)
    fi
}

# --- Legacy compatibility layers (legacy.d) --------------------------------
# Every deprecated compatibility layer lives as a function collection in
# legacy.d, one file per migration guide (same name, .sh suffix), with its
# expiry date and call sites documented in the file header. The files provide
# functions only — nothing executes at source time. When a layer expires, the
# file and its call site(s) are deleted together. See docs/contributing.md,
# "Legacy compatibility layers (legacy.d)".
source_files_in_dir_alphabetically "$legacy_dir"

# --- Build mode marker check -----------------------------------------------
# The "init-build-env" utility writes a marker file into the image layer. An
# image built that way must never be booted as a final image: the boot reset
# replaces the build-time work-data state with a runtime copy — silently
# discarding the changes later build steps made — and the entrypoint steps
# mutate the filesystem in ways that can not be tracked (extending images can
# add their own steps). Refusing to boot is deliberate, and it only hits images
# that explicitly opted in via init-build-env; builder stages that must remain
# bootable (e.g. CI test stages) use 'init-build-env --allow-boot' instead.
# The LEGACY no-command invocation writes no marker and stays bootable.
if [ "${CONTAINER_MODE}" != "build" ] && [ -f "${CONTAINER_BUILD_MODE_MARKER}" ]; then
    echo "[ENTRYPOINT] Error: this image ran 'init-build-env' (build mode) during its build." >&2
    echo "" >&2
    echo "Build mode is only meant for builder stages of a multi-stage build — an image like this" >&2
    echo "must not be booted: the boot would reset the build-time work data and silently discard" >&2
    echo "changes made by later build steps." >&2
    echo "" >&2
    echo "Fix: run your build in a builder stage and copy the artifacts into a fresh final stage:" >&2
    echo "" >&2
    echo "    FROM neunerlei/php-nginx:latest AS builder" >&2
    echo "    RUN init-build-env" >&2
    echo "    RUN <your build commands>" >&2
    echo "" >&2
    echo "    FROM neunerlei/php-nginx:latest" >&2
    echo "    COPY --from=builder /var/www/html ./" >&2
    echo "" >&2
    echo "If you really need to boot such an image (e.g. to run tests in a CI builder stage)," >&2
    echo "build it with 'init-build-env --allow-boot' instead." >&2
    echo "" >&2
    echo "Documentation: https://github.com/Neunerlei/docker-images/blob/main/docs/common.md#build-mode" >&2
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-12-build-mode-marker-and-variables.md" >&2
    exit 1
fi

# --- Legacy mount check (2026-02-05, expires 2027-02-05) --------------------
# Previously step.d/010-fail-on-legacy-mounts.sh; as a direct call it now
# aborts even earlier — before the entrypoint changes any state.
legacy_fail_on_legacy_mount_paths

# Registries for feature promotion
# Template Registry
# Key: Template Name (e.g., "nginx-conf")
# Value: The full, tab-separated registration line (type, name, sources, extra).
declare -gA template_registry
# A set to track which templates have already been processed.
# Key: Template Name
# Value: 1 (if processed)
declare -gA processed_tpl_registry
# File Markers
# The keys will be the marker strings (e.g., "prod"), and the values
# will be the names of the condition functions to call for that marker.
# If the function returns true, the marker condition is satisfied.
declare -gA file_marker_condition_registry
# Feature Toggles
# A list of feature names (nginx | supervisor | ...) to dynamically enable / disable
# entrypoint features
declare -g feature_registry
# User directories
# A list of directory paths that should be owned by the www-data user inside the container
declare -g -a user_owned_directories_registry=(
    "/run"
    "/var/lib/nginx"
    "/var/log/nginx"
    "${CONTAINER_DIR}"
    "${NGINX_SERVE_ROOT}"
    "/var/www" # This is the home directory of the www-data user by distribution default. It remains the application tree parent — the writable service home lives in the work directory (CONTAINER_WWW_DATA_HOME_DIR).
    "${NGINX_DOC_ROOT}"
    "${CONTAINER_WWW_DATA_HOME_DIR}"
)
# Additional user owned directories can be declared for the running container via the
# USER_OWNED_DIRECTORIES environment variable — the extension happens in step 070
# (after the custom environment files were loaded), so the variable may also be
# set from /container/custom/env/*.env.

# Entrypoint-only variables
# The EXACT names of the secret variables the entrypoint consumes itself — the
# clear-text basic auth credentials. Registration happens by NAME PATTERN,
# unconditionally, at the start of step 050 (register_basic_auth_credential_vars
# in util.d/basic-auth.sh): usage-based registration could not see variables the
# current mode never reads (worker mode never collects NGINX_BASIC_AUTH;
# PROXY_<KEY>_BASIC_AUTH is only collected in proxy mode), yet a shared env file
# between the web and the worker container of one stack makes exactly those
# leak into the snapshot and the exec'd environment. Steps 050/090 keep the
# registered names out of the container-vars.sh snapshot and step 100 unsets
# them right before the final exec, so supervisord and all child processes
# never inherit them — php-fpm runs with clear_env = no, so an inherited
# credential would reach every PHP worker and every exec shell. The
# <PREFIX>_REALM / _FILE / _DIR companions are not secrets and are not
# registered.
declare -g -a entrypoint_only_vars_registry=()

# Custom directory children
# The set of sub-directories that should exist inside CONTAINER_CUSTOM_DIR.
# Used by 005-init-custom-on-dev.sh to create the skeleton on first startup in development.
# Keys are the full paths; values are always 1.
# Image-specific step files can extend this registry by adding entries, just like feature_registry.
declare -gA container_custom_dir_child_registry=(
    ["${CONTAINER_CUSTOM_ENV_DIR}"]=1
    ["${CONTAINER_CUSTOM_ENTRYPOINT_DIR}"]=1
)

# --- Work data bootstrap -----------------------------------------------
# The staging area holds the pristine build-time state of the work data: during
# the build, work/data is a symlink to it, so everything written into the work
# data — by the installer, later build steps or child images — is captured
# there. On every boot, the work data is reset to exactly that state: the
# build-time symlink (or a stale runtime copy from a previous boot) is replaced
# by a real directory, and the entrypoint steps re-generate everything they
# need. A work directory mounted empty (tmpfs, Kubernetes emptyDir) is seeded
# the same way — the staging area lives outside the work directory, so a mount
# can not shadow it.
if [ ! -d "${CONTAINER_WORK_DIR}" ]; then
    echo "[ENTRYPOINT] Work directory is missing — creating it..."
    mkdir -p "${CONTAINER_WORK_DIR}"
fi

# --- Service user home bootstrap -----------------------------------------
# The www-data home lives in the work directory, so it is writable on every
# deployment — including read-only filesystems, where /container/work is the
# documented writable mount (tmpfs or emptyDir start empty, so the home must
# be created here). It has to exist before the entrypoint steps run: step 030
# (git) already writes to $HOME of the www-data user via gosu. The chown is
# conditional, matching ensure_user_owned_dir: already-correct setups — and
# environments where chown is not permitted — are left untouched.
if [ ! -d "${CONTAINER_WWW_DATA_HOME_DIR}" ]; then
    echo "[ENTRYPOINT] Creating www-data home directory: ${CONTAINER_WWW_DATA_HOME_DIR}"
    mkdir -p "${CONTAINER_WWW_DATA_HOME_DIR}"
fi
if [ "$(stat -c '%U' "${CONTAINER_WWW_DATA_HOME_DIR}")" != "www-data" ]; then
    # Recursive, like ensure_user_owned_dir: on a named volume at /container/work
    # the CONTENTS can keep a stale uid (e.g. PUID removed after a previous boot
    # reset /etc/passwd to uid 33) while step 070 would see the — by then fixed —
    # top-level owner and skip its repair. Conditional, so boots where the
    # ownership already matches remain a no-op. A failure is NOT fatal (matching
    # the read-only philosophy of ensure_user_owned_dir): on a read-only work-dir
    # mount the chown cannot succeed, but the world-readable files remain usable —
    # aborting the boot would break every such deployment for no gain.
    if ! chown -R www-data:www-data "${CONTAINER_WWW_DATA_HOME_DIR}" 2>/dev/null; then
        if findmnt -no OPTIONS --target "${CONTAINER_WWW_DATA_HOME_DIR}" 2>/dev/null | grep -qw ro; then
            echo "[ENTRYPOINT] Warning: ownership of '${CONTAINER_WWW_DATA_HOME_DIR}' could not be set to 'www-data' (read-only mount) — continuing, the world-readable files remain usable." >&2
        else
            echo "[ENTRYPOINT] Warning: ownership of '${CONTAINER_WWW_DATA_HOME_DIR}' could not be set to 'www-data' — continuing." >&2
        fi
    fi
fi

# --- Legacy dotfile bridge (2026-11-12, expires 2027-11-12) -----------------
# Historically the www-data home was /var/www, so consumers may have baked or
# mounted dotfiles there (.npmrc, .ssh, .gitconfig, .composer, ...). The
# bridge symlinks them into the new home — see the legacy.d function for the
# details and the read-only caveat.
legacy_bridge_var_www_dotfiles

echo "[ENTRYPOINT] Resetting work data from the staging area..."
rm -rf "${CONTAINER_WORK_DATA_DIR}"
if [ -d "${CONTAINER_WORK_STAGING_DIR}" ]; then
    cp -a "${CONTAINER_WORK_STAGING_DIR}" "${CONTAINER_WORK_DATA_DIR}"
else
    # The staging area is created by the installer during the image build and is as
    # much part of the image as the entrypoint itself — a healthy image can not boot
    # without it. Continuing with an empty work data directory would only die a few
    # steps later with a far less helpful "Output directory does not exist" error.
    echo "[ENTRYPOINT] Error: the work data staging area is missing at '${CONTAINER_WORK_STAGING_DIR}'. It is created by the installer during the image build — the image appears to be broken or was modified after the build. Aborting." >&2
    exit 1
fi

# Source the installer registry script to populate the in-memory registries
# (template_registry, container_custom_dir_child_registry).
if [ -f "${CONTAINER_INSTALLER_REGISTRY_SCRIPT}" ]; then
    echo "[ENTRYPOINT] Sourcing installer registry..."
    source "${CONTAINER_INSTALLER_REGISTRY_SCRIPT}"
fi

# Load utility scripts first
source_files_in_dir_alphabetically "$util_dir"

# Iterate all the steps to configure the container
source_files_in_dir_alphabetically "$step_dir"

if [ "$CONTAINER_MODE" == "build" ]; then
    case "$container_build_mode_invocation" in
        "new")
            # NEW build mode (init-build-env): write the build mode marker into
            # the image layer — an image built this way must never be booted as
            # a final image, and the check at the top enforces it. Rewriting the
            # marker on every build-mode run is fine. Like --allow-boot and the
            # legacy mode, the run ENDS by syncing the work data back into the
            # staging area and restoring the build-time symlink: files later
            # RUN steps wrote into the work-data copy between two build-mode
            # runs must survive the next run/boot, which resets work/data from
            # staging (the documented "repeated runs keep working" contract).
            echo "[ENTRYPOINT] Running in BUILD mode, writing the build mode marker: ${CONTAINER_BUILD_MODE_MARKER}"
            {
                echo "This image was built with 'init-build-env' (CONTAINER_MODE=build)."
                echo "Build mode is only meant for builder stages of a multi-stage build — never boot"
                echo "an image containing this marker as a final image."
                echo ""
                echo "Build mode run finished at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
            } > "${CONTAINER_BUILD_MODE_MARKER}"
            sync_work_data_into_staging
            ;;
        "allow-boot")
            # NEW build mode with --allow-boot: explicit opt-out of the marker.
            # The image may be booted (e.g. CI stages running tests against a
            # builder image) — a supported choice, so no deprecation warning.
            # A marker an EARLIER plain init-build-env run wrote is removed:
            # switching the stage to --allow-boot means the image is meant to
            # stay bootable, and a stale marker would make the next normal
            # boot refuse to start. The work data is synced back into the
            # staging area and the build-time symlink restored, so changes made
            # by later build steps SURVIVE boots: the image is bootable AND
            # consistent. Caveat: build-time rendered configuration (including
            # anything rendered from build-time env values) becomes part of the
            # pristine staging state — don't render secrets at build time.
            rm -f "${CONTAINER_BUILD_MODE_MARKER}"
            echo "[ENTRYPOINT] Running in BUILD mode with boot allowed — no build mode marker written, an existing marker was removed."
            sync_work_data_into_staging
            ;;
        *)
            # LEGACY build mode (entrypoint invoked without a command):
            # deprecated compatibility layer, expires 2027-11-12. Everything
            # it does — deprecation warning, work-data sync-back, build-time
            # symlink restore — lives in the legacy.d function.
            legacy_finish_deprecated_build_mode
            ;;
    esac
    # The variables for later `RUN` steps keep the container-vars.sh snapshot
    # written by the export steps (050/090) — in ALL modes. It is deliberately
    # NOT replaced with `export -p` here: get_all_vars leaves out HOME, PATH,
    # SHELL and similar on purpose — `export -p` would pin HOME=/root for every
    # later process and drag shell internals into the file. Note that builder
    # images pushed to a registry (e.g. as a CI cache) contain the derived
    # variables, including everything computed by custom/env files — do not
    # pull secrets in at build time.
else
    echo "[ENTRYPOINT] Running in NORMAL mode, executing entrypoint command: $(printf '%q ' "${entrypoint_command[@]}")"
    exec "${entrypoint_command[@]}"
fi
