#!/usr/bin/env bats
# Tier 1 — util.d/basic-auth.sh
#
# Targets (real functions, sourced from /container/entrypoint/util.d):
#   collect_basic_auth_credentials  — the "<PREFIX>" / "<PREFIX>_<n>" collection
#   write_basic_auth_file           — the apr1 htpasswd writer (validation + hashing)
#   build_basic_auth_directives     — the "auth_basic" directive pair builder
#
# The goldens normalize the salted hashes (lib/normalize.sed) — that is why the
# round-trip is verified HERE, against openssl itself: the file's hash must
# equal `openssl passwd -apr1` re-hashed with the SAME salt, i.e. the hash in
# the password file really is the hash of the clear password.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "util.d/basic-auth.sh"
}

teardown() {
    nl_unit_teardown
}

# ---------------------------------------------------------------------------
# write_basic_auth_file
# ---------------------------------------------------------------------------

@test "write_basic_auth_file writes an apr1 hash that round-trips against the clear password with the file's own salt" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "testuser test-password"
    [ "${status}" -eq 0 ]

    # Format: exactly one line "user:$apr1$<8-char-salt>$<22-char-digest>"
    [ "$(wc -l < "${auth_file}")" -eq 1 ]
    local line="${auth_file##*/}" hash salt rehashed
    line="$(cat "${auth_file}")"
    [ "${line%%:*}" == "testuser" ]
    hash="${line#*:}"
    [[ "${hash}" =~ ^\$apr1\$[./A-Za-z0-9]{8}\$[./A-Za-z0-9]{22}$ ]]

    # The round-trip: re-hash the clear password with the SALT FROM THE FILE.
    # Equality proves the stored hash was derived from this password — the
    # same verification nginx performs at request time.
    salt="$(printf '%s' "${hash}" | cut -d'$' -f3)"
    rehashed="$(printf '%s' 'test-password' | openssl passwd -apr1 -stdin -salt "${salt}")"
    [ "${rehashed}" == "${hash}" ]

    # And negatively: a different password must NOT produce the same hash.
    rehashed="$(printf '%s' 'wrong-password' | openssl passwd -apr1 -stdin -salt "${salt}")"
    [ "${rehashed}" != "${hash}" ]
}

@test "write_basic_auth_file writes multiple credentials in the given order" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "user1 pass1" "user2 pass2" "user3 pass3"
    [ "${status}" -eq 0 ]
    [ "$(wc -l < "${auth_file}")" -eq 3 ]
    [ "$(cut -d: -f1 "${auth_file}" | tr '\n' ' ')" == "user1 user2 user3 " ]
}

@test "write_basic_auth_file makes the password file world-readable (nginx workers read it at request time)" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "testuser test-password"
    [ "${status}" -eq 0 ]
    [ "$(stat -c '%a' "${auth_file}")" == "644" ]
}

@test "write_basic_auth_file keeps logging valid users before aborting on a later malformed one" {
    # Documented contract: "returns 1 (and leaves a possibly incomplete file
    # behind)". The valid user stays in the file, the abort is loud.
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "user1 pass1" "malformed-no-space"
    [ "${status}" -eq 1 ]
    [ "$(cut -d: -f1 "${auth_file}")" == "user1" ]
    [[ "${stderr}" == *"Malformed basic auth credential"* ]]
}

@test "write_basic_auth_file aborts on a credential without a separating space and writes no file" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "no-space-no-password"
    [ "${status}" -eq 1 ]
    [ ! -e "${auth_file}" ]
    [[ "${stderr}" == *"Malformed basic auth credential"* ]]
}

@test "write_basic_auth_file aborts on an empty password (trailing space only)" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "user "
    [ "${status}" -eq 1 ]
    [ ! -e "${auth_file}" ]
}

@test "write_basic_auth_file aborts on a username containing ':' (the htpasswd field separator)" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "user:name password"
    [ "${status}" -eq 1 ]
    [ ! -e "${auth_file}" ]
}

@test "write_basic_auth_file aborts on a password containing tabs or line breaks" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    # Tab in the password would corrupt the one-credential-per-line format
    # ($'...' ANSI-C quoting must stay OUTSIDE double quotes to expand)
    run --separate-stderr write_basic_auth_file "${auth_file}" $'user pass\tword'
    [ "${status}" -eq 1 ]
    [ ! -e "${auth_file}" ]
    [[ "${stderr}" == *"must not contain tabs or line breaks"* ]]
    # Line break splits the credential into two invalid entries
    run --separate-stderr write_basic_auth_file "${auth_file}" $'user pass\nword'
    [ "${status}" -eq 1 ]
}

@test "write_basic_auth_file aborts with a clear error when openssl is unavailable" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    # The PATH strip only affects this subshell (`export -f` hands the sourced
    # function to it); the error must NAME the missing dependency, never fall
    # back to writing an unhashed password.
    export -f write_basic_auth_file
    run --separate-stderr bash -c 'PATH=/nl-test-does-not-exist; write_basic_auth_file "$0" "user pass"' "${auth_file}"
    [ "${status}" -eq 1 ]
    [[ "${stderr}" == *"'openssl' is required"* ]]
}

@test "write_basic_auth_file never logs the password, only its length" {
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    run --separate-stderr write_basic_auth_file "${auth_file}" "testuser super-secret-pass" # 17 chars
    [ "${status}" -eq 0 ]
    # The progress line goes to STDOUT (only the error paths write to stderr)
    [[ "${output}" == *"Added user 'testuser' (password: 17 characters)"* ]]
    # Neither stream may ever carry the clear password
    [[ "${output}" != *"super-secret-pass"* ]]
    [[ "${stderr}" != *"super-secret-pass"* ]]
}

# ---------------------------------------------------------------------------
# collect_basic_auth_credentials
# ---------------------------------------------------------------------------

@test "collect_basic_auth_credentials returns the unprefixed user first, then the numbered ones in numeric order" {
    # _10 before _2 would be a plain string sort — the numeric order matters
    # for the htpasswd line order consumers rely on.
    export NGINX_BASIC_AUTH="first-user first-password"
    export NGINX_BASIC_AUTH_1="user-one pw-one"
    export NGINX_BASIC_AUTH_2="user-two pw-two"
    export NGINX_BASIC_AUTH_10="user-ten pw-ten"

    run collect_basic_auth_credentials "NGINX_BASIC_AUTH"
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" == "first-user first-password" ]
    [ "${lines[1]}" == "user-one pw-one" ]
    [ "${lines[2]}" == "user-two pw-two" ]
    [ "${lines[3]}" == "user-ten pw-ten" ]
    [ "${#lines[@]}" -eq 4 ]
}

@test "collect_basic_auth_credentials ignores _REALM, unrelated suffixes and empty values" {
    export NGINX_BASIC_AUTH="first-user first-password"
    export NGINX_BASIC_AUTH_1=""
    export NGINX_BASIC_AUTH_REALM="Some Realm"
    export NGINX_BASIC_AUTH_FOO="not-a-credential"
    unset NGINX_BASIC_AUTH_2

    run collect_basic_auth_credentials "NGINX_BASIC_AUTH"
    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" == "first-user first-password" ]
}

# ---------------------------------------------------------------------------
# build_basic_auth_directives
# ---------------------------------------------------------------------------

@test "build_basic_auth_directives renders the auth_basic pair for a realm and file" {
    run --separate-stderr build_basic_auth_directives "NL Test Realm" "/container/work/nginx-basic-auth/default.htpasswd"
    [ "${status}" -eq 0 ]
    [ "${output}" == 'auth_basic "NL Test Realm"; auth_basic_user_file /container/work/nginx-basic-auth/default.htpasswd;' ]
}

@test "build_basic_auth_directives rejects a realm containing double quotes" {
    run --separate-stderr build_basic_auth_directives 'Realm with "quotes"' "/tmp/f"
    [ "${status}" -eq 1 ]
    [[ "${stderr}" == *"Invalid basic auth realm"* ]]
}

@test "build_basic_auth_directives rejects a realm containing a dollar sign" {
    run --separate-stderr build_basic_auth_directives 'Realm $var' "/tmp/f"
    [ "${status}" -eq 1 ]
}

@test "build_basic_auth_directives rejects a realm containing line breaks" {
    run --separate-stderr build_basic_auth_directives $'Realm\nbroken' "/tmp/f"
    [ "${status}" -eq 1 ]
}
