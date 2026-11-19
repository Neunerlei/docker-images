#!/bin/bash

# Usage: bin/build.sh "image_name" "version" ["image_type"]
# Parameters:
#  image_name     The name of the image to build (e.g. php) (This relates to the folder structure in src/)
#  version        The version of the image to build (e.g. 8.4) -> This is actually the version of the source image!
#                 The version can be partial (e.g. 3.13), it will then be resolved to the newest matching version (e.g. 3.13.8)
#  image_type     Optional: the type of the image to build (e.g. fpm-alpine), if the image workflow defines multiple build jobs
# Examples:
#   bin/build.sh "php" "8.4"
#   bin/build.sh "python-nginx" "3.13"
#   bin/build.sh "php" "8.4" "fpm-alpine"
#
# Note: The local build applies the same tags the CI pipeline would publish
# (e.g. 3.13.8, the rolling 3.13 and "latest" where applicable), but does not push them.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$CURRENT_DIR/../.github/.release/"
npm run install --silent --no-audit --no-fund --prefer-offline
node "./local-build.js" "$@"
