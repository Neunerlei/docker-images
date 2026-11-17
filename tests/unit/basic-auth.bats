#!/usr/bin/env bats
# Tier 1 — util.d/basic-auth.sh
#
# Targets (real functions, sourced from /container/entrypoint/util.d):
#   collect_basic_auth_credentials  — the "<PREFIX>" / "<PREFIX>_<n>" collection,
#                                     printed to stdout for `mapfile -t` callers
#   register_basic_auth_credential_vars — the pattern-based registration of the
#                                     credential names in entrypoint_only_vars_registry
#   write_basic_auth_file           — the apr1 htpasswd writer (validation + hashing)
#   build_basic_auth_directives     — the "auth_basic" directive pair builder
#   snippet_manages_basic_auth      — whether a custom snippet OWNS the auth
#                                     config (brace-depth-0 rule)
#
# The goldens normalize the salted hashes (lib/normalize.sed) — that is why the
# round-trip is verified HERE, against openssl itself: the file's hash must
# equal `openssl passwd -apr1` re-hashed with the SAME salt, i.e. the hash in
# the password file really is the hash of the clear password.

load helpers

setup() {
    nl_unit_sandbox
    nl_unit_source "util.d/basic-auth.sh"
    # register_basic_auth_credential_vars appends to the entrypoint's
    # entrypoint_only_vars_registry (declared in entrypoint.sh next to the
    # steps that consume it: 050/090 keep registered names out of the
    # container-vars.sh snapshot, 100 unsets them before the final exec). The
    # unit tests source only util.d/basic-auth.sh, so the global is declared
    # here with the same shape entrypoint.sh gives it.
    declare -g -a entrypoint_only_vars_registry=()
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
# collect_basic_auth_credentials — the printing collector
# ---------------------------------------------------------------------------

@test "collect_basic_auth_credentials prints the credentials to stdout: unprefixed user first, then numbered ones in numeric order" {
    # The printing contract: one "username clear-password" line per credential
    # on stdout, consumed by the callers with `mapfile -t` (steps 020/025).
    # The function itself has no side effects — the credential registration in
    # the entrypoint-only registry is register_basic_auth_credential_vars'
    # job (asserted separately below).
    # _10 before _2 would be a plain string sort — the numeric order matters
    # for the htpasswd line order consumers rely on.
    export NGINX_BASIC_AUTH="first-user first-password"
    export NGINX_BASIC_AUTH_1="user-one pw-one"
    export NGINX_BASIC_AUTH_2="user-two pw-two"
    export NGINX_BASIC_AUTH_10="user-ten pw-ten"

    mapfile -t credentials < <(collect_basic_auth_credentials "NGINX_BASIC_AUTH")
    [ "${#credentials[@]}" -eq 4 ]
    [ "${credentials[0]}" == "first-user first-password" ]
    [ "${credentials[1]}" == "user-one pw-one" ]
    [ "${credentials[2]}" == "user-two pw-two" ]
    [ "${credentials[3]}" == "user-ten pw-ten" ]
}

@test "collect_basic_auth_credentials ignores _REALM, unrelated suffixes and empty values" {
    export NGINX_BASIC_AUTH="first-user first-password"
    export NGINX_BASIC_AUTH_1=""
    export NGINX_BASIC_AUTH_REALM="Some Realm"
    export NGINX_BASIC_AUTH_FOO="not-a-credential"
    unset NGINX_BASIC_AUTH_2

    mapfile -t credentials < <(collect_basic_auth_credentials "NGINX_BASIC_AUTH")
    [ "${#credentials[@]}" -eq 1 ]
    [ "${credentials[0]}" == "first-user first-password" ]
}

@test "collect_basic_auth_credentials works for the PROXY_<KEY> prefix the same way" {
    # The prefix is the function's argument — the per-proxy credentials of
    # step 025 are collected with the identical contract.
    export PROXY_API_BASIC_AUTH="api-user api-password"
    export PROXY_API_BASIC_AUTH_2="api-user-2 api-password-2"
    export PROXY_API_BASIC_AUTH_REALM="API Realm"

    mapfile -t credentials < <(collect_basic_auth_credentials "PROXY_API_BASIC_AUTH")
    [ "${#credentials[@]}" -eq 2 ]
    [ "${credentials[0]}" == "api-user api-password" ]
    [ "${credentials[1]}" == "api-user-2 api-password-2" ]
}

# ---------------------------------------------------------------------------
# register_basic_auth_credential_vars — the pattern-based entrypoint-only
# registration
# ---------------------------------------------------------------------------

@test "register_basic_auth_credential_vars registers every credential name present, numbered variants in numeric order" {
    # The registry IS the snapshot/unset contract (steps 050/090/100).
    # Registration is by NAME PATTERN over ALL currently visible variables —
    # NOT by what the collector happens to read in the current mode: in worker
    # mode nothing ever collects NGINX_BASIC_AUTH, and PROXY_<KEY>_BASIC_AUTH
    # is only collected for CONFIGURED proxy services, while a shared env file
    # between the web and the worker container of one stack makes exactly
    # those never-read variables the leak case. The scan sorts with `sort -V`,
    # so _2 lands before _10.
    export NGINX_BASIC_AUTH="first-user first-password"
    export NGINX_BASIC_AUTH_2="user-two pw-two"
    export NGINX_BASIC_AUTH_10="user-ten pw-ten"
    export PROXY_API_BASIC_AUTH="api-user api-password"
    export PROXY_API_BASIC_AUTH_10="api-user-ten api-password-ten"

    register_basic_auth_credential_vars

    [ "${entrypoint_only_vars_registry[*]}" == \
        "NGINX_BASIC_AUTH NGINX_BASIC_AUTH_2 NGINX_BASIC_AUTH_10 PROXY_API_BASIC_AUTH PROXY_API_BASIC_AUTH_10" ]
}

@test "register_basic_auth_credential_vars never registers the _REALM/_FILE/_DIR companions or unrelated variables" {
    # The companions are no secrets — they must stay in the snapshot and the
    # environment on purpose (the goldens intentionally show _REALM in the
    # container-vars snapshot). The patterns anchor at BOTH ends (^…$), so
    # superstrings of the credential names cannot slip in either.
    export NGINX_BASIC_AUTH_REALM="Some Realm"
    export NGINX_BASIC_AUTH_FILE="/somewhere/default.htpasswd"
    export NGINX_BASIC_AUTH_DIR="/somewhere"
    export PROXY_API_BASIC_AUTH_REALM="API Realm"
    export PROXY_API_BASIC="not-a-credential"
    export NGINX_BASIC_AUTHXY="not-a-credential"
    export NGINX_BASIC_AUTH_X="not-a-credential"
    export UNRELATED_VARIABLE="nothing-to-see"

    register_basic_auth_credential_vars

    [ "${#entrypoint_only_vars_registry[@]}" -eq 0 ]
}

@test "register_basic_auth_credential_vars registers empty-valued names too" {
    # An empty value is skipped as a credential by the collector, but the
    # NAME still matches the pattern — and the snapshot exclusion must not
    # depend on the current value: an unregistered empty NGINX_BASIC_AUTH_1
    # would leak the variable name (with its future value, e.g. once a custom
    # entrypoint script fills it) into container-vars.sh.
    export NGINX_BASIC_AUTH_1=""

    register_basic_auth_credential_vars
    [[ " ${entrypoint_only_vars_registry[*]} " == *" NGINX_BASIC_AUTH_1 "* ]]
}

@test "register_basic_auth_credential_vars is idempotent: the second call adds no duplicates" {
    # The function runs at the start of step 050 AND at the start of step 090
    # (custom entrypoint scripts in between can export credentials late). All
    # consumers compare the registry by exact name, so a duplicate entry would
    # only make them repeat their work — the function deduplicates.
    export NGINX_BASIC_AUTH="first-user first-password"
    export PROXY_API_BASIC_AUTH="api-user api-password"

    register_basic_auth_credential_vars
    [ "${#entrypoint_only_vars_registry[@]}" -eq 2 ]

    register_basic_auth_credential_vars
    [ "${#entrypoint_only_vars_registry[@]}" -eq 2 ]
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

@test "build_basic_auth_directives rejects a realm ending in a backslash" {
    # A trailing backslash escapes the closing quote of the generated
    # 'auth_basic "...";' directive — an unterminated string nginx rejects
    # (crash-looping the container). Bash quirk: inside single quotes the
    # trailing backslash stays literal.
    run --separate-stderr build_basic_auth_directives 'Backslash Realm\' "/tmp/f"
    [ "${status}" -eq 1 ]
    [[ "${stderr}" == *"must not end in a backslash"* ]]
}

@test "build_basic_auth_directives accepts a realm ending in other punctuation" {
    # The rejection is only about the TRAILING backslash; a question mark is a
    # legal realm character and must not be over-rejected.
    run --separate-stderr build_basic_auth_directives 'Realm?' "/tmp/f"
    [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# write_basic_auth_file — password length limit
# ---------------------------------------------------------------------------

@test "write_basic_auth_file rejects passwords longer than 256 characters" {
    # openssl passwd -apr1 silently truncates after 256 characters — the
    # stored hash would not match the intended password (login fails with a
    # cryptic mismatch while the boot log looks fine), so the writer must
    # reject loudly instead of hashing a prefix.
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    local long_pass
    long_pass="$(printf 'a%.0s' $(seq 1 257))"
    run --separate-stderr write_basic_auth_file "${auth_file}" "testuser ${long_pass}"
    [ "${status}" -eq 1 ]
    [ ! -e "${auth_file}" ]
    [[ "${stderr}" == *"silently truncates passwords after 256 characters"* ]]
}

@test "write_basic_auth_file accepts a password of exactly 256 characters" {
    # The boundary: the truncation starts AFTER 256, so the maximum legal
    # password must still hash and land in the file.
    local auth_file="${NL_UNIT_SANDBOX}/default.htpasswd"
    local max_pass
    max_pass="$(printf 'b%.0s' $(seq 1 256))"
    run --separate-stderr write_basic_auth_file "${auth_file}" "testuser ${max_pass}"
    [ "${status}" -eq 0 ]
    [ "$(cut -d: -f1 "${auth_file}")" == "testuser" ]
}

# ---------------------------------------------------------------------------
# snippet_manages_basic_auth — the brace-depth-0 ownership rule
# ---------------------------------------------------------------------------
# A snippet owns the auth config only when it declares "auth_basic" (enabled
# or "off") at brace depth 0 — the include point's own context. Anything
# NESTED in a location block changes the authentication in ITS context only
# and must NOT suppress the generated directives (treating it as ownership
# would silently unprotect the whole server / proxy location).

# Write a custom snippet with the given content and run the ownership check
# over the sandbox snippet glob — exactly the call shape of step 020
# ("${NGINX_CUSTOM_SNIPPETS_DIR}"/*.conf).
snippet_ownership_check() {
    local snippet_dir="${NL_UNIT_SANDBOX}/custom.d"
    mkdir -p "${snippet_dir}"
    printf '%s\n' "$@" > "${snippet_dir}/10-snippet.conf"
    snippet_manages_basic_auth "${snippet_dir}"/*.conf
}

@test "snippet_manages_basic_auth is true for a top-level enabled auth_basic (depth 0)" {
    # The mandate case: enabled directive at the include point's context —
    # the generated directives would be duplicates, so the snippet owns.
    run snippet_ownership_check 'auth_basic "Own Realm";'
    [ "${status}" -eq 0 ]
}

@test "snippet_manages_basic_auth is true for an INDENTED top-level off (indentation is not context, depth is)" {
    # The mandate case: "off" indented by whitespace but NOT nested in any
    # block — brace depth is still 0, so this IS the include point's context
    # and collides with the generated directives. Indentation carries no
    # meaning in nginx; only braces do.
    run snippet_ownership_check '    auth_basic off;'
    [ "${status}" -eq 0 ]

    # Same for a tab-indented one and for whitespace before the semicolon:
    run snippet_ownership_check $'\tauth_basic\toff ;'
    [ "${status}" -eq 0 ]
}

@test "snippet_manages_basic_auth is false for a nested (indented) auth_basic off" {
    # The mandate case: an "off" inside a location block (health-check
    # opt-out) lives in a DIFFERENT context — it only switches auth off in
    # its own location. Treating it as ownership would silently unprotect
    # the whole server, so the generated directives must stay in place.
    # The nested-off snippet is the regression case of the context-aware
    # detection (basic-auth-health-location scenario).
    run snippet_ownership_check 'location /health {' '    auth_basic off;' '}'
    [ "${status}" -eq 1 ]

    # Mixed file: a nested off does not smuggle ownership in, even next to
    # unrelated directives.
    run snippet_ownership_check 'try_files $uri =404;' 'location /health {' '    auth_basic off;' '}'
    [ "${status}" -eq 1 ]
}

@test "snippet_manages_basic_auth is false for a nested (indented) ENABLED auth_basic" {
    # The mandate case that CHANGED with the depth rule: an enabled directive
    # inside a location block (e.g. "location /admin { auth_basic "x"; }")
    # hardens ONLY that location. The old "any indent owns" reading would
    # have suppressed the generated server-wide directives because of a
    # nested hardening — silently DISABLING auth everywhere else.
    run snippet_ownership_check 'location /admin {' '    auth_basic "Own Realm";' '}'
    [ "${status}" -eq 1 ]

    # Depth, not the directive's argument: a nested "off" and a nested
    # enabled one are the same no-ownership case.
    run snippet_ownership_check 'location /admin {' '    auth_basic off;' '}'
    [ "${status}" -eq 1 ]
}

@test "snippet_manages_basic_auth is false for a one-line location block" {
    # The mandate case (boundary of the character walk): the whole block on
    # ONE line — the directive sits BETWEEN the braces (depth 1) even though
    # the line starts and ends at depth 0.
    run snippet_ownership_check 'location /health { auth_basic off; }'
    [ "${status}" -eq 1 ]

    run snippet_ownership_check 'location /admin { auth_basic "Own Realm"; }'
    [ "${status}" -eq 1 ]
}

@test "snippet_manages_basic_auth is true when a block closes before the directive" {
    # Boundary: the depth bookkeeping must RETURN to 0 after a closed block —
    # a directive following the closing brace (same line or next line) is at
    # the include point's context again and owns.
    run snippet_ownership_check 'location /health {' '    auth_basic off;' '}' 'auth_basic "Own Realm";'
    [ "${status}" -eq 0 ]

    # Same line as the closing brace:
    run snippet_ownership_check 'location /health { auth_basic off; }' 'auth_basic "Own Realm";'
    [ "${status}" -eq 0 ]
}

@test "snippet_manages_basic_auth is false when no snippet mentions auth_basic" {
    run snippet_ownership_check 'try_files $uri =404;' 'add_header X-Test 1;'
    [ "${status}" -eq 1 ]

    # No matching files at all (empty glob): not an ownership signal either.
    # The contract is "any non-zero counts as no ownership signal" (a falsy
    # status in the caller's `if snippet_manages_basic_auth ...; then`), so
    # assert that.
    run snippet_manages_basic_auth "${NL_UNIT_SANDBOX}/does-not-exist"/*.conf
    [ "${status}" -ne 0 ]
}

@test "snippet_manages_basic_auth is true when one of several snippets owns at depth 0" {
    # The check runs over the WHOLE custom snippet glob: the nested-off file
    # stays harmless, the top-level one takes ownership.
    local snippet_dir="${NL_UNIT_SANDBOX}/custom.d"
    mkdir -p "${snippet_dir}"
    printf '%s\n' 'location /health {' '    auth_basic off;' '}' > "${snippet_dir}/10-health.conf"
    printf '%s\n' 'auth_basic "Own Realm";' > "${snippet_dir}/20-auth.conf"
    run snippet_manages_basic_auth "${snippet_dir}"/*.conf
    [ "${status}" -eq 0 ]
}

@test "snippet_manages_basic_auth ignores commented-out directives" {
    # The mandate case: a '#' comment is stripped line-by-line before the
    # depth walk — a commented directive is no ownership signal.
    run snippet_ownership_check '# auth_basic "Own Realm";'
    [ "${status}" -eq 1 ]

    # A commented directive INSIDE a block must not leak ownership either
    # (the comment strip happens before the depth walk, so depth tracking
    # stays intact):
    run snippet_ownership_check 'location /health {' '    # auth_basic "Own Realm";' '}'
    [ "${status}" -eq 1 ]
}

@test "snippet_manages_basic_auth keeps auth_basic_user_file and longer names out" {
    # Right boundary: the directive name must be followed by whitespace (its
    # argument) — "auth_basic_user_file" (the file the generated pair writes
    # anyway) is a DIFFERENT directive and owns nothing.
    run snippet_ownership_check 'auth_basic_user_file /etc/nginx/htpasswd;'
    [ "${status}" -eq 1 ]

    # Left boundary: not the tail of a longer name.
    run snippet_ownership_check 'my_auth_basic "Own Realm";'
    [ "${status}" -eq 1 ]
}
