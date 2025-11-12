#!/bin/bash
set -e

# Usage: bin/build.sh "image_name" "version" "type" [--push] [--push-with-latest] [--plain]
# Parameters:
#  image_name     The name of the image to build (e.g. php) (This relates to the folder structure in src/)
#  version        The version of the image to build (e.g. 8.4)
#  type           The type of the image to build (e.g. fpm-debian) This is optional and can be omitted for images without sub-types
# Flags:
#  --push                 Push the built image to the Docker registry
#  --push-with-latest     Additionally tag the built image as "latest" and push it
#  --plain                Use plain output for the docker build process
# Examples:
#   bin/build.sh "php" "8.4" "fpm-debian"

echo "[BUILD] Starting build process..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG_BASE="neunerlei/"

IMAGE_NAME=$1
VERSION=$2
# Assume the third argument is NOT a flag starting with '--'
if [[ -n "$3" && ! "$3" == --* ]]; then
  TYPE=$3
else
  # No type provided, or the third arg was a flag.
  TYPE=""
fi

# fail if image is not given
if [[ -z "${IMAGE_NAME}" ]]; then
  echo "Please provide an image name (e.g. php) as the first parameter!"
  exit 1
fi

# fail if version was not given
if [[ -z "${VERSION}" ]]; then
  echo "Please provide a version (e.g. 8.4) as the second parameter!"
  exit 1
fi

BUILD_DIRECTORY=""
BUILD_TAG=""
if [[ -z "${TYPE}" ]]; then
  BUILD_DIRECTORY="${BIN_DIR}/../src/${IMAGE_NAME}/${VERSION}"
  BUILD_TAG="${VERSION}"
else
  BUILD_DIRECTORY="${BIN_DIR}/../src/${IMAGE_NAME}/${VERSION}/${TYPE}"
  BUILD_TAG="${VERSION}-${TYPE}"
fi

if [[ ! -d "${BUILD_DIRECTORY}" ]]; then
  echo "The build directory ${BUILD_DIRECTORY} does not exist!"
  exit 1
fi

cd ${BUILD_DIRECTORY}

TAG="${TAG_BASE}${IMAGE_NAME}:${BUILD_TAG}"
TAG_LATEST="${TAG_BASE}${IMAGE_NAME}:latest"
TAG_ARG="--tag ${TAG}"
if [[ "$*" == *--push-with-latest* ]]; then
  TAG_ARG="--tag ${TAG} --tag ${TAG_LATEST}"
fi

# Parse the --plain flag
PLAIN_FLAG=""
for arg in "$@"; do
  if [[ "$arg" == "--plain" ]]; then
    PLAIN_FLAG="--progress=plain"
    break
  fi
done

# Get all of the given build args
BUILD_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == --build-arg* ]]; then
    BUILD_ARGS+=("$arg")
  fi
done

echo "[BUILD] Building Docker image with tag(s): ${TAG}${TAG_LATEST:+, ${TAG_LATEST}}"

if [ ${#BUILD_ARGS[@]} -gt 0 ]; then
  echo "[BUILD] Using build arguments: ${BUILD_ARGS[*]}"
fi

docker build . ${PLAIN_FLAG} --file Dockerfile ${TAG_ARG} "${BUILD_ARGS[@]}"

if [[ "$*" == *--push* ]]; then
  docker push ${TAG}
fi
if [[ "$*" == *--push-with-latest* ]]; then
  docker push ${TAG_LATEST}
fi
