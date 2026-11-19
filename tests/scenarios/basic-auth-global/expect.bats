#!/usr/bin/env bats
# Tier 3 — basic-auth-global: the documented global basic auth behavior
# (docs/nginx.md, "Basic Authentication") against a LIVE container.
#
# The golden (Tier 2) pins the rendered directives and WHICH users exist; the
# hashes there are normalized because they are salted. THIS tier proves the
# part a normalized golden cannot: the generated hashes actually WORK — 401
# without credentials, 200 with the right ones, 401 for a wrong password, and
# the realm text from NGINX_BASIC_AUTH_REALM reaching the challenge header.

load '../../lib/integration-helpers'

setup() {
    # bats runs each test in its own process — reload the boot state written
    # by setup_file (container name, etc.)
    nl_int_load_state
}

setup_file() {
    nl_int_boot
}

teardown_file() {
    nl_int_teardown
}

@test "GET / without credentials answers 401 with the configured realm" {
    [ "$(nl_int_curl_status "/")" == "401" ]
    [ "$(nl_int_curl_header "/" "" "WWW-Authenticate")" == 'WWW-Authenticate: Basic realm="NL Test Realm"' ]
}

@test "GET / with the correct first-user credentials answers 200" {
    # testuser/test-password from the scenario env — the proof that the apr1
    # hash in the golden-normalized password file really matches this password
    [ "$(nl_int_curl_status "/" "testuser:test-password")" == "200" ]
}

@test "GET / with the correct second-user credentials answers 200 (multi-user collection)" {
    # NGINX_BASIC_AUTH_1 was collected into the same password file
    [ "$(nl_int_curl_status "/" "seconduser:other-password")" == "200" ]
}

@test "GET / with a wrong password answers 401" {
    [ "$(nl_int_curl_status "/" "testuser:totally-wrong")" == "401" ]
}

@test "GET / with an unknown user answers 401" {
    [ "$(nl_int_curl_status "/" "nobody:nope")" == "401" ]
}

# php-nginx only: the baked health-location opt-out under global auth
# (root.nginx.conf carries an INDENTED `auth_basic off;` inside the fpm
# location — a nested opt-out, not an ownership signal, so the generated
# directives stay and /fpm-ping must keep answering orchestrator probes).
@test "GET /fpm-ping answers 200 WITHOUT credentials under global auth (php-nginx health opt-out)" {
    if [ "${NL_TEST_IMAGE}" != "php-nginx" ]; then
        skip "the fpm health locations only exist on php-nginx"
    fi
    [ "$(nl_int_curl_status "/fpm-ping")" == "200" ]
}

@test "GET /fpm-ping stays open even with wrong credentials (auth_basic off, no challenge) (php-nginx)" {
    if [ "${NL_TEST_IMAGE}" != "php-nginx" ]; then
        skip "the fpm health locations only exist on php-nginx"
    fi
    [ "$(nl_int_curl_status "/fpm-ping" "testuser:totally-wrong")" == "200" ]
}

# ---------------------------------------------------------------------------
# Secrets never leak (the entrypoint-only registry contract, entrypoint.sh +
# step.d/050/090/100): the credentials exist to generate the htpasswd files
# during boot and must not survive anywhere a consumer can read them. The
# golden pins the snapshot's VISIBLE side; these tests pin the abscences on
# the live container.
# ---------------------------------------------------------------------------

@test "a regular env var still reaches a www-data exec shell (the pre-exec unset is surgical)" {
    # APP_ENV=nl-int-check from the scenario env. The exec shell runs as
    # www-data — proving both that the exec path works for the unprivileged
    # user and that the registry-based unset removed ONLY the registered
    # credential names: regular variables keep flowing. Empty stderr is part
    # of the contract: no permission warnings, no sourcing failures.
    run --separate-stderr docker exec -u www-data "${NL_INT_CONTAINER}" bash -c 'echo -n "${APP_ENV}"'
    [ "${status}" -eq 0 ]
    [ "${output}" == "nl-int-check" ]
    [ -z "${stderr}" ]
}

@test "no NGINX_BASIC_AUTH credential leaks into the supervisord or nginx process environments" {
    # Step 100 unsets every registered name right before the final exec —
    # supervisord (and everything it spawns, php-fpm and node children
    # included) must boot WITHOUT the credentials. Read from /proc/<pid>/
    # environ: the kernel's view of what a process actually received, not
    # what a shell would print. The comm-based scan also proves BOTH target
    # processes were actually seen, so a pgrep-like failure cannot make the
    # check pass vacuously.
    run --separate-stderr docker exec "${NL_INT_CONTAINER}" bash -s <<'SCAN'
supervisor_seen=0
nginx_seen=0
for p in /proc/[0-9]*; do
    comm="$(cat "${p}/comm" 2>/dev/null)" || continue
    case "${comm}" in
        supervisord) supervisor_seen=1 ;;
        nginx)       nginx_seen=1 ;;
        *)           continue ;;
    esac
    if tr '\0' '\n' < "${p}/environ" 2>/dev/null | grep -q '^NGINX_BASIC_AUTH'; then
        echo "NGINX_BASIC_AUTH leaked into the environment of pid ${p##*/} (${comm})"
        exit 1
    fi
done
[ "${supervisor_seen}" -eq 1 ] && [ "${nginx_seen}" -eq 1 ]
SCAN
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "container-vars.sh holds the realm but never a credential" {
    # The snapshot is world-readable BY DESIGN (644, see step 050) — the
    # secret exclusion is what keeps it safe to be. _REALM (and the _FILE/
    # _DIR companions) are no secrets and stay exported; the exact credential
    # names (NGINX_BASIC_AUTH, NGINX_BASIC_AUTH_<n>) must not appear. The
    # regex is name-exact so the companions cannot false-positive it.
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'grep -c "^export NGINX_BASIC_AUTH_REALM=" /container/work/container-vars.sh'
    [ "${status}" -eq 0 ]
    [ "${output}" -ge 1 ]

    run --separate-stderr docker exec "${NL_INT_CONTAINER}" bash -c \
        'grep -cE "^export NGINX_BASIC_AUTH(_[0-9]+)?=" /container/work/container-vars.sh'
    # grep -c prints "0" (and exits 1) when nothing matched — both are the
    # assertion; a real match would print a positive count.
    [ "${output}" == "0" ]
    [ -z "${stderr}" ]
}
