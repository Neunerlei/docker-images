#!/bin/bash

# Determines the application environment based on the ENVIRONMENT environment variable.
# If ENVIRONMENT is not set, defaults to "production".
# Normalizes common values like "prod" to "production" and "dev" to "development".
# Usage:
#   environment=$(find_environment)
#
find_environment() {
  local environment="${ENVIRONMENT:-production}"
  case "${environment,,}" in
    "prod"|"production")
      echo "production"
      ;;
    "dev"|"development")
      echo "development"
      ;;
    *)
      echo "${environment,,}"
      ;;
  esac
}
