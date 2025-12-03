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

_file_marker_has_nginx_feature() {
  # The spaces are important to avoid partial matches (note the padding of BOTH sides)
  [[ " $feature_registry " == *" nginx "* ]]
}
file_marker_condition_registry["feat-nginx"]=_file_marker_has_nginx_feature

_file_marker_is_web_mode() {
  [[ "${CONTAINER_MODE}" == "web" ]]
}
file_marker_condition_registry["mode-web"]=_file_marker_is_web_mode

_file_marker_is_worker_mode() {
  [[ "${CONTAINER_MODE}" == "worker" ]]
}
file_marker_condition_registry["mode-worker"]=_file_marker_is_worker_mode

_file_marker_is_build_mode() {
  [[ "${CONTAINER_MODE}" == "build" ]]
}
file_marker_condition_registry["mode-build"]=_file_marker_is_build_mode
