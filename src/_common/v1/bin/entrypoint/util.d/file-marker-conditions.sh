#!/bin/bash

_file_marker_is_prod() {
  [[ "${ENVIRONMENT}" == "production" ]]
}
file_marker_condition_registry["prod"]=_file_marker_is_prod

_file_marker_is_dev() {
  [[ "${ENVIRONMENT}" == "development" ]]
}
file_marker_condition_registry["dev"]=_file_marker_is_dev

_file_marker_is_https() {
  [[ "${DOCKER_SERVICE_PROTOCOL}" == "https" ]]
}
file_marker_condition_registry["https"]=_file_marker_is_https

_file_marker_has_feature() {
  local feature="$1"
  # The spaces are important to avoid partial matches (note the padding of BOTH sides)
  [[ " ${feature_registry} " == *" ${feature} "* ]]
}
file_marker_condition_registry["feat-*"]=_file_marker_has_feature

_file_marker_is_env() {
  local env="$1"
  [[ "${ENVIRONMENT}" == "${env}" ]] ||
  [[ "${env}" == "prod" && "${ENVIRONMENT}" == "production" ]] ||
  [[ "${env}" == "dev" && "${ENVIRONMENT}" == "development" ]]
}
file_marker_condition_registry["env-*"]=_file_marker_is_env

_file_marker_is_mode() {
  local mode="$1"
  [[ "${CONTAINER_MODE}" == "${mode}" ]]
}
file_marker_condition_registry["mode-*"]=_file_marker_is_mode
