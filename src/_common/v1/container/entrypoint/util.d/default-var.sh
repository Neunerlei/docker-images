#!/bin/bash

# Sets a tracked default for an environment variable.
#
# Usage:
#   default_var NAME VALUE
#
# Sets and exports NAME=VALUE only when
#   - NAME is empty, OR
#   - NAME still holds exactly the value THIS helper recorded the last time
#     it set NAME (i.e. nobody has touched it since).
# Any other value in NAME is a user decision (docker -e, Dockerfile ENV,
# custom/env file, an earlier legacy override) and is left untouched.
#
# The values this helper sets are recorded in the _default_var_registry
# associative array. The leading underscore keeps the registry out of
# get_all_vars() — it is internal bookkeeping, never a template variable and
# never exported. The registry deliberately records ONLY values this helper
# itself assigned: a value the user set is never recorded, so a later pass
# still treats it as user-owned.
#
# This is what makes re-deriving defaults safe: the environment pipeline
# calls default_var again after every custom environment file pass, and a
# default that is still in place is recomputed from the (possibly changed)
# inputs, while a value the user provided survives every pass. The one
# ambiguity: a variable the user sets to EXACTLY its current default value
# is indistinguishable from an untouched default and is recomputed — see
# docs/common.md, "Environment Files".
declare -gA _default_var_registry=()

default_var() {
    local name="${1:?variable name required}"
    local value="${2:-}"

    if [ -z "${!name}" ] || [ "${!name}" == "${_default_var_registry[${name}]:-}" ]; then
        export "${name}=${value}"
        _default_var_registry["${name}"]="${value}"
    fi
}
