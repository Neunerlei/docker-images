# LEGACY LAYER — exact command arguments (single-string fallback)
# Migration guide: docs/migration/2026-11-12-exact-command-arguments.md
# Compatibility layer until: 2027-11-12
#
# When this layer expires: delete this file and its call site in
# step.d/100-execute-command.sh (search for
# "legacy_apply_single_string_command_fallback"), then note the removal in
# the migration guide. See docs/contributing.md, "Legacy compatibility
# layers (legacy.d)".
#
# Some consumers pass the whole command line as a single string argument
# (e.g. compose `command: ["npm run dev"]` or a Kubernetes
# `args: ["php artisan queue:work"]`). That only ever worked because the old
# implementation word-split the joined command string. This fallback splits a
# single-string command like the shell would — reproducing the old word
# splitting, NOT the old quote handling (embedded quotes stay literal,
# exactly as before).
#
# This file provides functions only — it must not execute anything at source
# time. entrypoint.sh sources it before any state is changed.

# If the command was passed as exactly one non-executable argument containing
# whitespace, split it into separate arguments with a deprecation warning.
# No-op for properly passed (multi-argument) commands.
# Operates on the global "entrypoint_command" array.
# Call site: step.d/100-execute-command.sh.
function legacy_apply_single_string_command_fallback() {
    if [ ${#entrypoint_command[@]} -eq 1 ] \
        && [[ "${entrypoint_command[0]}" == *[[:space:]]* ]] \
        && ! command -v "${entrypoint_command[0]}" >/dev/null 2>&1; then
        echo "[ENTRYPOINT.execute-command] Warning: the command was passed as a single string: \"${entrypoint_command[0]}\"." >&2
        echo "[ENTRYPOINT.execute-command] Warning: this is deprecated and will fail in a future release. Pass the command as separate arguments instead." >&2
        echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-12-exact-command-arguments.md" >&2
        # -d '' makes read consume the WHOLE string including newlines (plain
        # read stops at the first line and would silently drop everything
        # after it); read returns 1 at EOF, hence the || true.
        read -r -d '' -a entrypoint_command <<< "${entrypoint_command[0]}" || true
    fi
}
