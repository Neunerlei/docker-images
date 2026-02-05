#!/bin/bash

# Only execute if entrypoint_command is not empty
if [ -z "$entrypoint_command" ]; then
  echo "[ENTRYPOINT.execute-command] No command specified to execute, skipping execution step.";
else
  echo "[ENTRYPOINT.execute-command] Bootstrapping completed, starting command \"$entrypoint_command\"...";
  exec $entrypoint_command
fi
