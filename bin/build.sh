#!/bin/bash

# Usage: bin/build.sh "image_name" "version"
# Parameters:
#  image_name     The name of the image to build (e.g. php) (This relates to the folder structure in src/)
#  version        The version of the image to build (e.g. 8.4) -> This is actually the version of the source image!
# Examples:
#   bin/build.sh "php" "8.4"

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CURRENT_DIR/../.github/.release/"
npm run install --silent --no-audit --no-fund --prefer-offline
node "./local-build.js" "$@"
