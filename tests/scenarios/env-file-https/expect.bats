#!/usr/bin/env bats
# Tier 3 — env-file-https: an env-file DOCKER_PROJECT_PROTOCOL=https really
# switches the container to direct HTTPS (443 listen + 80 → 301 redirect),
# the behavior change the pipeline reordering documents.

load '../../lib/integration-helpers'

setup()         { nl_int_load_state; }
setup_file()    { nl_int_boot; }
teardown_file() { nl_int_teardown; }

@test "GET / on port 80 redirects to https" {
    # The redirect targets the REQUESTED host ($host — curl talks to
    # 127.0.0.1, so that is the Location's host), like https-direct-selfsigned.
    # nl_int_curl_header returns the full header LINE.
    [ "$(nl_int_curl_status "/")" == "301" ]
    [ "$(nl_int_curl_header "/" "" "Location")" == "Location: https://127.0.0.1/" ]
}

@test "the 443 ssl listen rendered from the env-file protocol" {
    run docker exec "${NL_INT_CONTAINER}" bash -c \
        'nginx -T 2>&1 | grep -E "listen 443 ssl"'
    [ "${status}" -eq 0 ]
}

@test "DOCKER_SERVICE_PROTOCOL followed the project protocol" {
    run docker exec "${NL_INT_CONTAINER}" bash -c 'printf "%s" "${DOCKER_SERVICE_PROTOCOL}"'
    [ "${output}" == "https" ]
}
