#!/bin/bash

# Only execute if entrypoint_command is not empty
if [ ${#entrypoint_command[@]} -eq 0 ]; then
  echo "[ENTRYPOINT.execute-command] No command specified to execute, skipping execution step.";
else
  # Backwards compatibility for single-string commands (deprecated, expires
  # 2027-11-12): splits a command that was passed as one non-executable string
  # argument into separate arguments, with a deprecation warning. No-op for
  # properly passed commands. See legacy.d/2026-11-12-exact-command-arguments.sh.
  legacy_apply_single_string_command_fallback

  echo "[ENTRYPOINT.execute-command] Bootstrapping completed, starting command \"$(printf '%q ' "${entrypoint_command[@]}")\"...";
  exec "${entrypoint_command[@]}"
fi
