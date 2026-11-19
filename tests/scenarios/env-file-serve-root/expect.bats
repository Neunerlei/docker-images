#!/usr/bin/env bats
# Tier 3 — env-file-serve-root: the serve root from a custom env file is
# created and owned by www-data (the registry move to step 070).

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "the env-file serve root exists and is owned by www-data" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'stat -c "%U:%G" /var/www/app-root'
    [ "${status}" -eq 0 ]
    [ "${output}" == "www-data:www-data" ]
}

@test "the default doc root keeps serving while the custom serve root only affects ownership" {
    # NGINX_SERVE_ROOT is the application-tree/ownership root, not the nginx
    # document root (that is NGINX_DOC_ROOT, untouched here) — the baked app
    # must keep answering, proving the custom serve root changed only what
    # it is supposed to change.
    [ "$(nl_int_curl_status "/")" == "200" ]
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${NGINX_SERVE_ROOT}"'
    [ "${output}" == "/var/www/app-root" ]
}
