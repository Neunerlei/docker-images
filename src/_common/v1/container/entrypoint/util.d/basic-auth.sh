#!/bin/bash

# Helpers to configure NGINX HTTP basic authentication from environment variables.
#
# The convention for credentials is:
#   <PREFIX>="username clear-password"     the first user
#   <PREFIX>_1="username clear-password"   additional users, any number
#   <PREFIX>_2, <PREFIX>_3, ...
# The FIRST space separates username and password, everything after it belongs
# to the password (so passwords may contain spaces).
#
# Reference: https://docs.nginx.com/nginx/admin-guide/security-controls/configuring-http-basic-authentication/

# Registers every currently-set basic auth credential variable in the
# "entrypoint_only_vars_registry" (declared in entrypoint.sh), by NAME PATTERN
# and unconditionally:
#   NGINX_BASIC_AUTH, NGINX_BASIC_AUTH_1, NGINX_BASIC_AUTH_2, ...
#   PROXY_<KEY>_BASIC_AUTH, PROXY_<KEY>_BASIC_AUTH_1, PROXY_<KEY>_BASIC_AUTH_2, ...
# The "<PREFIX>_REALM" / "_FILE" / "_DIR" companions never match the patterns —
# they are not secrets and stay in the snapshot and the environment on purpose.
#
# Why by pattern instead of registering each name the moment the collector
# reads it: usage-based registration cannot see variables the current mode
# never reads. In worker mode (PHP_WORKER_COMMAND set — no nginx feature)
# nothing ever collects NGINX_BASIC_AUTH, and PROXY_<KEY>_BASIC_AUTH is only
# collected in proxy mode when a matching PROXY_<KEY>_CONTAINER service exists.
# A shared env file between the web and the worker container of one stack makes
# that cross-mode leakage realistic: the credentials would end up in the
# container-vars.sh snapshot AND in the environment of the exec'd process tree.
# Called at the start of step 050, before any exporting happens; steps 090 and
# 100 run later, so the registry is complete for all three consumers.
#
# The scan mirrors the collector below exactly ("compgen -A variable", the same
# variable set the collector reads), so every name the collector could ever
# consume is registered — whether or not the current mode actually reads it.
#
# Usage:
#   register_basic_auth_credential_vars
#
register_basic_auth_credential_vars() {
    local var
    while IFS= read -r var; do
        # Deduplicate: all consumers compare the registry by exact name, so a
        # duplicate entry would only make steps 050/090/100 repeat their work
        if [[ " ${entrypoint_only_vars_registry[*]} " == *" ${var} "* ]]; then
            continue
        fi
        entrypoint_only_vars_registry+=("${var}")
    done < <(compgen -A variable | grep -E '^(NGINX_BASIC_AUTH(_[0-9]+)?|PROXY_.+_BASIC_AUTH(_[0-9]+)?)$' | sort -V)
}

# Collects all basic auth credentials that follow the "<PREFIX>" / "<PREFIX>_<n>" convention.
# Prints one "username clear-password" entry per line, in a deterministic order
# (the unprefixed variable first, then the numbered ones in numeric order), so
# callers can consume the result with "mapfile -t".
#
# Variables like <PREFIX>_REALM or unrelated suffixes are ignored. Empty values are skipped.
#
# Usage:
#   mapfile -t credentials < <(collect_basic_auth_credentials "NGINX_BASIC_AUTH")
#
collect_basic_auth_credentials() {
    local prefix="$1"
    local var value

    while IFS= read -r var; do
        value="${!var}"
        # Skip empty values, so an accidentally empty variable does not abort the container
        if [[ -z "${value}" ]]; then
            continue
        fi
        printf '%s\n' "${value}"
    done < <(compgen -A variable | grep -E "^${prefix}(_[0-9]+)?$" | sort -V)
}

# Reports whether any of the given custom snippets MANAGES basic auth in the
# context the snippet is included in, i.e. whether the generated "auth_basic"
# directives must be suppressed to keep NGINX free of "directive is duplicate"
# errors. This mirrors how NGINX itself finds duplicates: a snippet manages
# auth when it declares an "auth_basic" directive — ENABLED or "off" — at its
# TOP LEVEL (brace depth 0, "#" comments stripped), because the include point
# (server context in step 020, location context in the proxy step) is exactly
# where the generated directives land, and two "auth_basic" directives in the
# same context make NGINX abort the whole configuration. A directive NESTED in
# a "location" block (e.g. an indented "auth_basic off;" inside a health-check
# opt-out, or an enabled one inside "location /admin") lives in a DIFFERENT
# context: it only changes the authentication there and must NOT suppress the
# generated directives — treating it as ownership would silently disable the
# authentication for the whole server / location.
#
# The comment stripping is deliberately LINE-based ("#" to end of line),
# matching NGINX's own parser tolerance. Known limitation: a "#" inside a
# quoted argument (e.g. auth_basic "re#alm") truncates the rest of that LINE
# for the scan, so a brace or directive later on the same line could be
# misjudged. Full string-aware lexing is not worth it — one directive per line
# is the convention here (as in all shipped templates), so the directive name
# and its depth are always evaluated where it matters.
#
# Files that cannot be read (e.g. a non-matching glob) count as "no snippet
# manages auth". "auth_basic_user_file" never matches: the directive name must
# be followed by whitespace (its argument), which the longer name fails.
#
# Usage:
#   if snippet_manages_basic_auth "${NGINX_CUSTOM_SNIPPETS_DIR}"/*.conf; then ...
snippet_manages_basic_auth() {
    local snippet
    for snippet in "$@"; do
        # An unmatched glob (no snippet files at all) stays a literal path —
        # skip it instead of letting awk fail on the missing file
        [ -f "${snippet}" ] || continue
        if awk '
            # Walk the comment-stripped line character by character, tracking
            # the brace depth; only a depth-0 position can start a directive
            # of the context the snippet is included in.
            {
                line = $0
                sub(/#.*/, "", line)
                len = length(line)
                for (i = 1; i <= len; i++) {
                    c = substr(line, i, 1)
                    if (c == "{") { depth++; continue }
                    if (c == "}") { if (depth > 0) depth--; continue }
                    if (depth != 0 || substr(line, i, 10) != "auth_basic") continue
                    # Left boundary: not the tail of a longer name ("my_auth_basic")
                    if (i > 1 && substr(line, i - 1, 1) ~ /[A-Za-z0-9_-]/) continue
                    # Right boundary: the directive name is followed by its
                    # argument, which keeps "auth_basic_user_file" out
                    nc = substr(line, i + 10, 1)
                    if (nc == " " || nc == "\t") { found = 1; exit }
                }
            }
            END { exit found ? 0 : 1 }
        ' "${snippet}"; then
            return 0
        fi
    done
    return 1
}

# Writes an NGINX compatible basic auth password file from "username clear-password" strings.
# The passwords are hashed with "openssl passwd -apr1" (MD5-based, understood by NGINX
# without further dependencies). openssl is part of the default image dependencies.
#
# The file is made world-readable on purpose: NGINX workers read it at request time,
# and their group id may be rewritten later by the user-permissions step when
# PUID/PGID is used, which would break a group-based permission. Hashes are not
# readable as clear passwords, and www-data is the only non-root user in the container.
#
# Deliberately NEVER logs any credential value — only error descriptions.
# Returns 1 (and leaves a possibly incomplete file behind) when a credential is malformed.
#
# Usage:
#   write_basic_auth_file "${NGINX_BASIC_AUTH_DIR}/default.htpasswd" "user1 pass1" "user2 pass2"
#
write_basic_auth_file() {
    local output_file="$1"
    shift

    if ! command -v openssl >/dev/null 2>&1; then
        echo "[UTIL.basic-auth] Error: 'openssl' is required to hash basic auth passwords, but was not found in the PATH." >&2
        return 1
    fi

    local credential username password hashed_password
    for credential in "$@"; do
        username="${credential%% *}"
        password="${credential#* }"

        # Validate: a separating space must exist, the username must be non-empty and may
        # not contain ":" (the htpasswd field separator), and the password must not be empty.
        if [[ "${credential}" != *" "* ]] \
            || [[ -z "${username}" ]] \
            || [[ "${username}" == *:* ]] \
            || [[ -z "${password}" ]]; then
            echo "[UTIL.basic-auth] Error: Malformed basic auth credential. Expected format: 'username clear-password' (separated by a space). The username must not be empty and must not contain ':' or spaces, the password must not be empty." >&2
            return 1
        fi
        # Line breaks or tabs would corrupt the one-credential-per-line htpasswd format
        if [[ "${password}" == *[$'\t'$'\n'$'\r']* ]]; then
            echo "[UTIL.basic-auth] Error: Malformed basic auth credential for user '${username}': the password must not contain tabs or line breaks." >&2
            return 1
        fi
        # "openssl passwd -apr1" silently truncates passwords after 256 characters
        # (verified: a 300-char password hashes identically to its 256-char prefix),
        # so the login would fail with a cryptic "password mismatch" while the boot
        # log looks fine — reject loudly instead. The variable the credential came
        # from is named by the calling step's abort message.
        if [[ ${#password} -gt 256 ]]; then
            echo "[UTIL.basic-auth] Error: The password for user '${username}' is ${#password} characters long. 'openssl passwd -apr1' silently truncates passwords after 256 characters — the stored hash would not match the intended password. Shorten the password." >&2
            return 1
        fi

        # Read the password from stdin, so it never shows up in a process listing
        if ! hashed_password="$(printf '%s' "${password}" | openssl passwd -apr1 -stdin)"; then
            echo "[UTIL.basic-auth] Error: Hashing the password for user '${username}' with openssl failed. Aborting." >&2
            return 1
        fi

        # An apr1 hash always has the form $apr1$<8-char-salt>$<22-char-digest>. An
        # empty or malformed output must never reach the password file — and must
        # not rely on the self-verification below alone, which a consistently
        # failing pipeline could trick with two equal garbage values.
        if ! [[ "${hashed_password}" =~ ^\$apr1\$[./A-Za-z0-9]{8}\$[./A-Za-z0-9]{22}$ ]]; then
            echo "[UTIL.basic-auth] Error: openssl produced no valid apr1 hash for user '${username}' (got ${#hashed_password} characters). Aborting." >&2
            return 1
        fi

        # Self-verification: re-hash with the same salt and compare, so a broken
        # hashing pipeline can never write an unverifiable password file.
        # The salt is the second "$"-separated field of the apr1 hash.
        local hash_salt
        hash_salt="$(printf '%s' "${hashed_password}" | cut -d'$' -f3)"
        if [ "$(printf '%s' "${password}" | openssl passwd -apr1 -stdin -salt "${hash_salt}")" != "${hashed_password}" ]; then
            echo "[UTIL.basic-auth] Error: The generated hash for user '${username}' failed the self-verification. Aborting." >&2
            return 1
        fi

        printf '%s:%s\n' "${username}" "${hashed_password}" >> "${output_file}"

        # Log the user with the password LENGTH (never the password itself). This makes
        # truncated values visible at a glance: some environment file parsers cut values
        # at characters like '#', and the login would otherwise fail with a cryptic
        # "password mismatch" while the boot log looks perfectly fine.
        echo "[UTIL.basic-auth] - Added user '${username}' (password: ${#password} characters)"
    done

    chmod 644 "${output_file}"
}

# Builds the "auth_basic" / "auth_basic_user_file" directive pair for a given realm and
# password file. Characters that would break the NGINX configuration (" and $, as well as
# line breaks) are rejected. Returns 1 on an invalid realm, prints the directives otherwise.
#
# Usage:
#   directives=$(build_basic_auth_directives "Restricted" "${NGINX_BASIC_AUTH_DIR}/default.htpasswd")
#
build_basic_auth_directives() {
    local realm="$1"
    local auth_file="$2"

    # A trailing backslash would escape the closing quote of the generated
    # 'auth_basic "...";' directive, leaving an unterminated string that makes
    # nginx reject the configuration and crash-loop the container
    if [[ "${realm}" == *'"'* || "${realm}" == *'$'* || "${realm}" == *[$'\t'$'\n'$'\r']* || "${realm: -1}" == "\\" ]]; then
        echo "[UTIL.basic-auth] Error: Invalid basic auth realm '${realm}': must not contain double quotes, dollar signs, tabs or line breaks, and must not end in a backslash (a trailing backslash escapes the closing quote and corrupts the generated configuration)." >&2
        return 1
    fi

    printf 'auth_basic "%s"; auth_basic_user_file %s;' "${realm}" "${auth_file}"
}
