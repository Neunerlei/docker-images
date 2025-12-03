#!/bin/bash

_file_marker_is_build_mode() {
  [[ "${CONTAINER_MODE}" == "build" ]]
}
file_marker_condition_registry["mode-build"]=_file_marker_is_build_mode
