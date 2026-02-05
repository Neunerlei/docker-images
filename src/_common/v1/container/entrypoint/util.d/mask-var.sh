#!/bin/bash

# Helper to mask sensitive variable values for logging.
# If the variable name contains "TOKEN", "KEY", "PRIVATE", "SECRET" or "PASSWORD",
# the value is masked to show only the first and last 2 characters.
# Usage: masked_value=$(mask_var "VAR_NAME" "VAR_VALUE")
mask_var() {
  local var_name="$1"
  local var_value="$2"
  local masked_value=""

  if [[ "$var_name" =~ TOKEN|KEY|PRIVATE|SECRET|PASS|AUTH|CREDENTIAL ]]; then
    # If the value is less than or equal to 4 characters, mask the entire value
    if [ "${#var_value}" -le 4 ]; then
      echo "**** [masked]"
      return
    fi

    masked_value="${var_value:0:2}****${var_value: -2}"
    echo "${masked_value} [masked]"
  else
    echo "${var_value}"
  fi
}
