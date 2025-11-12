#!/bin/bash
set -e

# Usage: bin/discover-and-build.sh "image_name" "source_namespace" "source_image_name" "type" [--push] [--push-with-latest] [--plain]
# Parameters:
#  image_name            The name of the image to build (e.g. nginx) (This relates to the folder structure in src/)
#  source_namespace      The namespace of the source image to discover versions from (e.g. library)
#  source_image_name     The name of the source image to discover versions from (e.g. nginx)
#  source_image_suffix   An optional suffix to append to the source versions to track (e.g. debian for nginx:1.23-debian) (can be an empty string)
# Flags:
#  --push                 Push the built images to the Docker registry
#  --push-with-latest     Additionally tag the latest of the built images as "latest" and push it
#  --plain                Use plain output for the docker build process
# Examples:
#   bin/discover-and-build.sh "nginx" "library" "nginx"

echo "[DISCOVER AND BUILD] Starting discovery and build process..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKED_VERSION_NUM=3 # How many of the most recent versions to track/build

IMAGE_NAME=$1
SOURCE_NAMESPACE=$2
SOURCE_IMAGE_NAME=$3
# Assume the third argument is NOT a flag starting with '--'
if [[ -n "$4" && ! "$4" == --* ]]; then
  SOURCE_IMAGE_SUFFIX=$4
else
  # No type provided, or the third arg was a flag.
  SOURCE_IMAGE_SUFFIX=""
fi

# fail if image is not given
if [[ -z "${IMAGE_NAME}" ]]; then
  echo "Please provide an image name (e.g. php) as the first parameter!"
  exit 1
fi

# fail if source namespace was not given
if [[ -z "${SOURCE_NAMESPACE}" ]]; then
  echo "Please provide a source namespace (e.g. library) as the second parameter!"
  exit 1
fi

# fail if source image name was not given
if [[ -z "${SOURCE_IMAGE_NAME}" ]]; then
  echo "Please provide a source image name (e.g. nginx) as the third parameter!"
  exit 1
fi

source "${BIN_DIR}/util/docker-version-utils.sh"
source "${BIN_DIR}/util/find-source-path.sh"

VERSIONS_TO_BUILD=$(get_latest_versions "$SOURCE_IMAGE_NAME" "$TRACKED_VERSION_NUM" "$SOURCE_IMAGE_SUFFIX")

# If empty, exit here
if [[ -z "${VERSIONS_TO_BUILD}" ]]; then
  echo "[DISCOVER AND BUILD] No versions found to build for image ${SOURCE_IMAGE_NAME} with suffix '${SOURCE_IMAGE_SUFFIX}'"
  exit 0
fi

echo "[DISCOVER AND BUILD] Discovered versions to build: ${VERSIONS_TO_BUILD}"

for VERSION in $VERSIONS_TO_BUILD; do
  echo "[DISCOVER AND BUILD] Building version: ${VERSION}..."

  BUILD_PARAMS=()
  if [[ "$*" == *--push* ]]; then
    BUILD_PARAMS+=("--push")
  fi
  if [[ "$*" == *--plain* ]]; then
    BUILD_PARAMS+=("--plain")
  fi

  # The latest tag should be pushed and this is the latest version of those we found -> tell the build script
  if [[ "$*" == *--push-with-latest* && $(is_latest_version $VERSION $VERSIONS_TO_BUILD) ]]; then
    BUILD_PARAMS+=("--push-with-latest")
  fi

  # We must now convert the actual version of the source image to the best matching version folder in our source tree
  SOURCE_VERSION_DIR=$(find_source_path "${BIN_DIR}/../src/${IMAGE_NAME}" "${VERSION}")
  if [[ -z "${SOURCE_VERSION_DIR}" ]]; then
    echo "[DISCOVER AND BUILD] Could not find a suitable source directory for version ${VERSION}, skipping..."
    continue
  fi

  $BIN_DIR/build.sh "${IMAGE_NAME}" "${SOURCE_VERSION_DIR}" ${BUILD_PARAMS[@]} --build-arg="SOURCE_IMAGE_TAG=${VERSION}${SOURCE_IMAGE_SUFFIX:+-$SOURCE_IMAGE_SUFFIX}"
done
