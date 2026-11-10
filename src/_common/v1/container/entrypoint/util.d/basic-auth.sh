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

        # Read the password from stdin, so it never shows up in a process listing
        hashed_password="$(printf '%s' "${password}" | openssl passwd -apr1 -stdin)"

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

    if [[ "${realm}" == *'"'* || "${realm}" == *'$'* || "${realm}" == *[$'\t'$'\n'$'\r']* ]]; then
        echo "[UTIL.basic-auth] Error: Invalid basic auth realm '${realm}': must not contain double quotes, dollar signs, tabs or line breaks." >&2
        return 1
    fi

    printf 'auth_basic "%s"; auth_basic_user_file %s;' "${realm}" "${auth_file}"
}
