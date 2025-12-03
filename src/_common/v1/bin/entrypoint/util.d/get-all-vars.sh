#!/bin/bash

# Returns all environment variable names as a space-separated string.
# Usage:
#   render_template "$(get_all_vars)" "path/to/template.tpl" "path/to/output.conf"
#
get_all_vars() {
    local bp='^(BASH_.*|BASH|BASHPID|EPOCHREALTIME|EPOCHSECONDS|FUNCNAME|LINENO|RANDOM|SRANDOM|SECONDS|PIPESTATUS|PWD|OLDPWD|SHLVL|UID|EUID|PPID|GROUPS|SHELLOPTS|BASHOPTS|DIRSTACK|HISTCMD|OPTERR|OPTIND|COMP_.*|_|bp|cep|MACHTYPE)$'
    local cep='^(HOME|PATH|SHELL|TERM|USER|LOGNAME|LANG|LC_.*|PS[1-4]|IFS|OSTYPE|HOSTTYPE|HOSTNAME|EDITOR|PAGER)$'

    compgen -v \
    | grep -E -v "$bp" \
    | grep -E -v "$cep" \
    | sort
}
