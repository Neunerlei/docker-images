#!/bin/bash
# probe.sh — runs INSIDE a container started from one of our images and
# prints the observable surface of the boot, one section at a time.
#
# The probe is BIND-MOUNTED into the container at /nl-test/ (a neutral path —
# never baked into the image, and never mounted under one of the paths the
# legacy mount check aborts on: /etc/ssl/certs, /etc/container/templates/...,
# /usr/bin/container/custom). Because it is mounted rather than baked, the
# SAME probe runs against a main build and a branch build — that is what
# makes captures comparable at all.
#
# Output contract (consumed by lib/capture.sh):
#   Sections are delimited on STDOUT by lines of the form
#       ===== nl-test-section: <name> =====
#   Everything BEFORE the first delimiter is not part of any section (in
#   static mode that region is the entrypoint's own boot log, which
#   capture.sh records as the stdout/stderr sections). The probe never
#   writes to stderr on purpose: a delimiter appearing in the stderr stream
#   is a probe bug and capture.sh fails loudly on it.
#
# Modes (plan §2.2):
#   static — the entrypoint ran all steps and exec'd THIS probe as the
#            container command; the container filesystem is in the exact
#            post-boot state.
#   live   — the container booted normally (entrypoint exec'd supervisord);
#            the probe runs via `docker exec` alongside the services. Static
#            sections are captured the same way, plus supervisor status,
#            per-process environment and HTTP probes.
#
# Section names: argv, nginx-T.conf, supervisor.conf, image-config.txt,
# vars.sh, passwd, ownership.txt, work-data.checksums, htpasswd.txt,
# supervisor-status, process-env, http.txt.
# The suite's own library: the probe runs inside the container and must never
# source host-side files; everything below is self-contained by design.
# shellcheck disable=SC2329  # collectors are dispatched indirectly via probe_collect
set -uo pipefail

# Deliberately NOT `set -e`: a single failing collector must degrade to a
# failure marker line inside its section, never truncate the remaining
# sections of the capture.

mode="${1:-}"
shift || true

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print a section delimiter. capture.sh splits the stream on these lines —
# the format doubles as the file name in the capture directory.
function section() {
    printf '===== nl-test-section: %s =====\n' "$1"
}

# Run a collector command as one section. stderr is folded INTO the section:
# collectors should be deterministic end to end, and a diagnostic line (e.g.
# nginx's "test is successful") is part of the observable surface. A failing
# collector leaves an explicit marker so an empty section can never be
# mistaken for "nothing to observe".
function probe_collect() {
    local name="$1"
    shift
    section "${name}"
    "$@" 2>&1 || printf '!! collector failed (exit=%s)\n' "$?"
}

# Deterministic sort for unordered output. LC_ALL=C pins the collation:
# the host/container locale must not reorder lines between runs.
function sorted() {
    LC_ALL=C sort "$@"
}

# ---------------------------------------------------------------------------
# Static sections (the post-boot filesystem surface)
# ---------------------------------------------------------------------------

# The argv the exec'd command received — everything after the mode word.
# This is the direct observation of the entrypoint's command handling
# (including the legacy single-string splitting), one argument per line so
# word boundaries are unambiguous.
function collect_argv() {
    printf 'argc=%s\n' "$#"
    local arg
    for arg in "$@"; do
        printf '%s\n' "${arg}"
    done
}

# The fully expanded nginx configuration (all includes resolved). nginx -T
# writes the dump to stdout and its test verdict to stderr — both belong in
# the capture.
function collect_nginx_t() {
    nginx -T
}

# The rendered supervisor configuration: the main file plus every conf.d
# program, in sorted order (glob order is readdir order — unordered).
function collect_supervisor_conf() {
    local file
    printf '# ---- /etc/supervisor/supervisord.conf ----\n'
    cat /etc/supervisor/supervisord.conf
    for file in $(sorted < <(compgen -G '/etc/supervisor/conf.d/*.conf' || true)); do
        printf '# ---- %s ----\n' "${file}"
        cat "${file}"
    done
}

# Rendered image-specific configuration, where the image defines any.
# Extensible table of paths: nginx has none of these (its rendered config is
# fully covered by nginx-T and the work data), python-nginx renders
# gunicorn.conf.py, php-nginx renders the ini and fpm pool dirs. A path that
# does not exist on the current image records "(not present)" — so adding a
# path here never breaks the nginx captures.
function collect_image_config() {
    local path
    local -a image_config_paths=(
        "/etc/gunicorn.conf.py"                 # python-nginx: gunicorn-conf template
        "/usr/local/etc/php/conf.d"             # php-nginx: php-ini template (dir)
        "/usr/local/etc/php-fpm.d"              # php-nginx: php-fpm template (pool dir)
    )
    for path in "${image_config_paths[@]}"; do
        printf '# ---- %s ----\n' "${path}"
        if [ -f "${path}" ]; then
            cat "${path}"
        elif [ -d "${path}" ]; then
            local file
            while IFS= read -r file; do
                printf '# -- %s --\n' "${file}"
                cat "${file}"
            done < <(find "${path}" -type f | sorted)
        else
            printf '(not present)\n'
        fi
    done
}

# The exported variable snapshot the entrypoint wrote for later `RUN` steps
# and docker exec shells (/container/work/container-vars.sh). Sorted: the
# snapshot is written in `compgen` order, which is alphabetical today but is
# an implementation detail, not a guarantee. NOTE: unlike the boot LOG, the
# snapshot holds UNMASKED values — synthetic scenario credentials will show
# up here, which is exactly why scenarios only ever contain test values.
function collect_vars_snapshot() {
    if [ -f "/container/work/container-vars.sh" ]; then
        sorted "/container/work/container-vars.sh"
    else
        printf '(snapshot missing: /container/work/container-vars.sh)\n'
    fi
}

# The www-data service user as the system sees it: the passwd entry (its home
# is the branch's moved service home) and the id resolution.
function collect_passwd() {
    printf '# getent passwd www-data\n'
    getent passwd www-data || printf '(www-data missing from passwd)\n'
    printf '# id www-data\n'
    id www-data || printf '(id www-data failed)\n'
}

# Owner/group/mode of everything under the user-owned directories and of
# /container itself. Sorted with LC_ALL=C; no timestamps — they are volatile
# and say nothing about behavior. Symlink targets (%l) are included because a
# link pointing at the wrong path is a real regression class (the work-data
# staging link is exactly such a symlink).
#
# The directory set mirrors user_owned_directories_registry in entrypoint.sh
# (built-in entries). NGINX_SERVE_ROOT / NGINX_DOC_ROOT defaults are
# replicated here rather than read from the environment: in live mode the
# probe runs via docker exec, where the entrypoint's exports do not exist.
# USER_OWNED_DIRECTORIES extensions are recorded in vars.sh; the find below
# stays a fixed list so its shape is identical across scenarios.
function collect_ownership() {
    local dir
    local -a dirs=(
        "/run"
        "/var/lib/nginx"
        "/var/log/nginx"
        "/container"
        "/var/www"
        "${NGINX_SERVE_ROOT:-/var/www/html}"
        "${NGINX_DOC_ROOT:-/var/www/html/public}"
        "/container/work/www-data-home"
    )
    for dir in "${dirs[@]}"; do
        if [ -d "${dir}" ]; then
            find "${dir}" -printf '%m %u %g %p %l\n'
        else
            printf '(absent: %s)\n' "${dir}"
        fi
    done | sorted
}

# Sorted checksum list of the work data — the boot-reset staging copy. Any
# content drift in the rendered configuration shows here even when nothing
# else surfaces it. Sorted by path (sort -z over the NUL-delimited list, so
# md5sum's output — which preserves input order — ends up path-sorted).
# NOTE: the basic-auth password files live OUTSIDE /container/work/data (in
# /container/work/nginx-basic-auth) precisely so their per-boot salted hashes
# cannot make this list nondeterministic.
# The rendered resolver snippet is EXCLUDED: its content embeds the resolver
# address the entrypoint detected from /etc/resolv.conf at boot
# (common-env.sh detect_dns_resolvers), so its md5 legitimately differs per
# environment and no normalization can reach a checksum. Nothing goes
# unasserted — the file's normalized CONTENT (resolver directive + knobs) is
# pinned by the nginx-T.conf golden section, and the explicit-resolver
# scenarios (resolver-explicit, resolver-multi-nameserver) pin the directive
# list itself. Only this file is exempted: no other work-data file was shown
# to embed environment values (CI divergence touched this file alone).
function collect_work_data_checksums() {
    find /container/work/data -type f \
        ! -path '/container/work/data/nginx-snippets-resolver' -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 -r md5sum
}

# The generated basic-auth password files (user:hash lines). The hashes are
# normalized (salted, random per boot) — what the golden pins is WHICH users
# and files exist. Absent directory = no auth configured, recorded as such.
function collect_htpasswd_files() {
    local dir="/container/work/nginx-basic-auth"
    if [ ! -d "${dir}" ]; then
        printf '(no basic auth files at %s)\n' "${dir}"
        return 0
    fi
    local file
    while IFS= read -r file; do
        printf '# ---- %s ----\n' "${file}"
        cat "${file}"
    done < <(find "${dir}" -type f | sorted)
    [ -n "$(ls -A "${dir}" 2>/dev/null)" ] || printf '(empty: %s)\n' "${dir}"
}

# ---------------------------------------------------------------------------
# Live-only sections (the running-service surface)
# ---------------------------------------------------------------------------

# supervisorctl status: which programs exist, are they RUNNING. PIDs and
# uptimes are volatile and normalized by normalize.sed.
function collect_supervisor_status() {
    supervisorctl status
}

# Per supervised program: the user it runs as and its HOME, read from the
# process itself — not from any config file. This is the exact surface of
# the consumer-HOME finding (plan §6): supervisor's user= only switches the
# uid, so HOME is whatever supervisord handed down unless the config pins it.
#
# php-fpm caveat (plan §2.2 note): /proc/<pid>/environ is an exec-time
# snapshot; for FPM WORKERS it is unreliable and must be probed with a
# mounted PHP script instead. Programs listed here are recorded with a
# marker instead of a possibly-wrong HOME. php-fpm is the reason this list
# exists — the php-fpm-home scenario probes the real worker environment via
# a PHP script in the document root, reported back through X-Nl-Test-*
# response headers (see collect_http).
function collect_process_env() {
    local -a environ_unreliable_programs=("php-fpm")
    local name _state pid uid gid user group home
    while read -r name _state _rest; do
        [ -n "${name}" ] || continue
        pid="$(supervisorctl pid "${name}" 2>/dev/null || printf '')"
        if [[ " ${environ_unreliable_programs[*]} " == *" ${name} "* ]]; then
            printf '%s: (process environment unreliable for this program — probe via its own runtime instead)\n' "${name}"
            continue
        fi
        if [ -z "${pid}" ] || [ ! -r "/proc/${pid}" ]; then
            printf '%s: (no running process)\n' "${name}"
            continue
        fi
        # No `ps` in the image (not part of the default dependencies): the
        # /proc/<pid> directory is owned by the process's real uid/gid, which
        # answers "which user is this running as" without extra tooling.
        uid="$(stat -c '%u' "/proc/${pid}")"
        gid="$(stat -c '%g' "/proc/${pid}")"
        user="$(getent passwd "${uid}" | cut -d: -f1 || printf 'uid:%s' "${uid}")"
        group="$(getent group "${gid}" | cut -d: -f1 || printf 'gid:%s' "${gid}")"
        # /proc/<pid>/environ needs ptrace-level access: processes that CHANGED
        # uid after exec (supervisor's user= setuid, gosu) have dumpable=0 and
        # their environ is unreadable even for root without CAP_SYS_PTRACE —
        # and a plain [ -r ] test lies, because root bypasses the DAC check
        # that test performs. So the read is attempted and its STATUS decides:
        # reporting "(unset)" after a failed read would be a FALSE fact — the
        # process HAS a HOME (gosu derives it from the passwd entry); it is
        # just not observable here. Mark the class instead; the exec-shell-env
        # section measures exactly those HOMEs through the runtime itself, and
        # worker scenarios have the command print its own HOME into the log.
        if ! environ_content="$(tr '\0' '\n' 2>/dev/null < "/proc/${pid}/environ")"; then
            printf '%s: user=%s group=%s (process environment unreadable — uid changed via supervisor/gosu; see the exec-shell-env section or the program own log output)\n' "${name}" "${user}" "${group}"
            continue
        fi
        home="$(printf '%s\n' "${environ_content}" | grep '^HOME=' || printf 'HOME=(unset)')"
        printf '%s: user=%s group=%s %s\n' "${name}" "${user}" "${group}" "${home}"
    done < <(supervisorctl status 2>/dev/null | LC_ALL=C sort)
}

# HOME and identity of the EXEC context (docker exec), which is the only way
# a capture can observe the process-launch paths the images actually use at
# runtime without booting consumer apps:
#   - a plain `bash -c` shell: the docker-exec environment (no entrypoint, no
#     gosu) — the wrapper sources container-vars.sh, which deliberately does
#     NOT carry HOME, so what prints here is what docker exec itself provides;
#   - the wrapped CLIs (`php`, `python`, `node`) run through
#     `gosu www-data` — EXACTLY how the worker-mode supervisor commands launch
#     them (plan §6): gosu derives HOME from the www-data passwd entry, so this
#     is the observable for the "everything started via gosu takes the passwd
#     home" claim. Binaries absent from the current image are recorded as such,
#     so one shared section shape works across all four images.
# Live-only: static captures exec the probe INSTEAD of a service process, so
# there is no independent exec context to observe there.
function collect_exec_shell_env() {
    printf '# docker exec shell (root, no gosu)\n'
    bash -c 'printf "bash: HOME=%s\n" "${HOME:-(unset)}"' 2>&1 || printf '!! bash invocation failed\n'
    if command -v gosu >/dev/null 2>&1 && id -u www-data >/dev/null 2>&1; then
        if command -v php >/dev/null 2>&1; then
            printf 'gosu www-data php: '
            gosu www-data php -r 'echo getenv("HOME") === false ? "(unset)" : getenv("HOME");' 2>&1 \
                || printf '!! php invocation failed'
            printf '\n'
        fi
        if command -v python >/dev/null 2>&1; then
            printf 'gosu www-data python: '
            gosu www-data python -c 'import os; print(os.environ.get("HOME", "(unset)"))' 2>&1 \
                || printf '!! python invocation failed'
        fi
        if command -v node >/dev/null 2>&1; then
            printf 'gosu www-data node: '
            gosu www-data node -p 'process.env.HOME === undefined ? "(unset)" : process.env.HOME' 2>&1 \
                || printf '!! node invocation failed'
        fi
    else
        printf '(gosu or www-data unavailable)\n'
    fi
}

# HTTP surface of the running service: status line plus the headers that
# carry behavior (Server, Content-Type, WWW-Authenticate, Location) plus the
# suite's own X-Nl-Test-* channel — scenarios mount probe scripts into the
# service runtime to report what /proc cannot show (the php-fpm worker
# environment reports getenv('HOME') through such a header, plan §2.2 note).
# Other headers — above all Date — are deliberately dropped here rather than
# normalized later: a value that is never captured cannot leak volatility.
# The request paths come from the scenario (http-probe= keys) and are passed
# as probe arguments in live mode. Curl CRs are stripped so lines diff clean.
function collect_http() {
    local path response
    for path in "$@"; do
        printf '== GET %s ==\n' "${path}"
        if ! response="$(curl -sS -o /dev/null -D - --max-time 5 "http://127.0.0.1:80${path}" 2>&1 | tr -d '\r')"; then
            printf '!! request failed\n'
            continue
        fi
        printf '%s\n' "${response}" \
            | grep -E '^(HTTP/|Server:|Content-Type:|WWW-Authenticate:|Location:|X-Nl-Test-)'
    done
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

case "${mode}" in
    static)
        probe_collect "argv" collect_argv "$@"
        probe_collect "nginx-T.conf" collect_nginx_t
        probe_collect "supervisor.conf" collect_supervisor_conf
        probe_collect "image-config.txt" collect_image_config
        probe_collect "vars.sh" collect_vars_snapshot
        probe_collect "passwd" collect_passwd
        probe_collect "ownership.txt" collect_ownership
        probe_collect "work-data.checksums" collect_work_data_checksums
        probe_collect "htpasswd.txt" collect_htpasswd_files
        ;;
    live)
        # Static sections first (same set, same order), so a static section
        # can be compared between modes with a plain file diff.
        probe_collect "argv" collect_argv "$@"
        probe_collect "nginx-T.conf" collect_nginx_t
        probe_collect "supervisor.conf" collect_supervisor_conf
        probe_collect "image-config.txt" collect_image_config
        probe_collect "vars.sh" collect_vars_snapshot
        probe_collect "passwd" collect_passwd
        probe_collect "ownership.txt" collect_ownership
        probe_collect "work-data.checksums" collect_work_data_checksums
        probe_collect "htpasswd.txt" collect_htpasswd_files
        probe_collect "supervisor-status" collect_supervisor_status
        probe_collect "process-env" collect_process_env
        probe_collect "exec-shell-env" collect_exec_shell_env
        # Live HTTP probes default to the document root when a scenario
        # defines nothing — the boot must at least answer on /
        if [ $# -eq 0 ]; then
            set -- "/"
        fi
        probe_collect "http.txt" collect_http "$@"
        ;;
    *)
        printf '[NL-TEST.probe] Error: unknown mode "%s". Expected "static" or "live".\n' "${mode}" >&2
        exit 2
        ;;
esac

exit 0
