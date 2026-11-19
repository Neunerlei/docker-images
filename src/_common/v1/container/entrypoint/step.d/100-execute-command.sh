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

  # Entrypoint-only secrets (entrypoint_only_vars_registry, registered by
  # NAME PATTERN at the start of step 050 — unconditionally, so worker mode
  # without any nginx feature is covered too, see
  # util.d/basic-auth.sh) are unset right before the final exec: the exec'd
  # process — supervisord — and every child after it would otherwise carry
  # the clear-text basic auth credentials for the container's whole lifetime.
  # php-fpm runs with clear_env = no, so anything left in the supervisor
  # environment reaches every PHP worker, and "docker exec" shells see it as
  # well. The nginx configuration references the generated password files,
  # never these variables.
  for entrypoint_only_var in "${entrypoint_only_vars_registry[@]}"; do
    unset "${entrypoint_only_var}"
  done

  echo "[ENTRYPOINT.execute-command] Bootstrapping completed, starting command \"$(printf '%q ' "${entrypoint_command[@]}")\"...";
  exec "${entrypoint_command[@]}"
fi
