#!/bin/bash

# Only execute if entrypoint_command is not empty
if [ ${#entrypoint_command[@]} -eq 0 ]; then
  echo "[ENTRYPOINT.execute-command] No command specified to execute, skipping execution step.";
else
  # Backwards compatibility: some consumers pass the whole command line as a
  # single string argument (e.g. compose `command: ["npm run dev"]` or a
  # Kubernetes `args: ["php artisan queue:work"]`). That only ever worked
  # because the old implementation word-split the joined command string.
  # If we received exactly one argument that contains whitespace and is not
  # an executable on its own, split it like the shell would. This reproduces
  # the old word splitting, NOT the old quote handling — embedded quotes stay
  # literal, exactly as they did before. The fallback will be removed in a
  # future release; pass commands as separate arguments instead.
  if [ ${#entrypoint_command[@]} -eq 1 ] \
    && [[ "${entrypoint_command[0]}" == *[[:space:]]* ]] \
    && ! command -v "${entrypoint_command[0]}" >/dev/null 2>&1; then
    echo "[ENTRYPOINT.execute-command] Warning: the command was passed as a single string: \"${entrypoint_command[0]}\"." >&2
    echo "[ENTRYPOINT.execute-command] Warning: this is deprecated and will fail in a future release. Pass the command as separate arguments instead." >&2
    echo "Migration guide: https://github.com/Neunerlei/docker-images/blob/main/docs/migration/2026-11-12-exact-command-arguments.md" >&2
    # -d '' makes read consume the WHOLE string including newlines (plain read
    # stops at the first line and would silently drop everything after it);
    # read returns 1 at EOF, hence the || true.
    read -r -d '' -a entrypoint_command <<< "${entrypoint_command[0]}" || true
  fi

  echo "[ENTRYPOINT.execute-command] Bootstrapping completed, starting command \"$(printf '%q ' "${entrypoint_command[@]}")\"...";
  exec "${entrypoint_command[@]}"
fi
