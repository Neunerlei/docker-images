#!/bin/bash

# Helper to mask sensitive variable values for logging.
# If the variable name contains "TOKEN", "KEY", "PRIVATE", "SECRET" or "PASSWORD",
# the value is masked ENTIRELY: not even a first/last-two-character preview is
# shown — a short value leaves only a handful of candidates, and the preview
# also confirmed the exact length of long secrets.
# Usage: masked_value=$(mask_var "VAR_NAME" "VAR_VALUE")
mask_var() {
  local var_name="$1"
  local var_value="$2"

  if [[ "$var_name" =~ TOKEN|KEY|PRIVATE|SECRET|PASS|AUTH|CREDENTIAL ]]; then
    echo "**** [masked]"
  else
    echo "${var_value}"
  fi
}
