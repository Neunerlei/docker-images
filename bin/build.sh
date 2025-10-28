#!/bin/bash
TAG_BASE="neunerlei/"

IMAGE_NAME=$1
VERSION=$2
TYPE=$3

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

if [[ -z "${TYPE}" ]]; then
  echo "Please provide the image type (e.g. fpm-debian) as third parameter!"
  exit 1
fi

BUILD_DIRECTORY="${BASH_SOURCE%/*}/../src/${IMAGE_NAME}/${VERSION}/${TYPE}"

if [[ ! -d "${BUILD_DIRECTORY}" ]]; then
  echo "The build directory ${BUILD_DIRECTORY} does not exist!"
  exit 1
fi

cd ${BUILD_DIRECTORY}

TAG="${TAG_BASE}${IMAGE_NAME}:${VERSION}-${TYPE}"
TAG_ARG="--tag ${TAG}"

# Parse the --plain flag
PLAIN_FLAG=""
for arg in "$@"; do
  if [[ "$arg" == "--plain" ]]; then
    PLAIN_FLAG="--progress=plain"
    break
  fi
done

docker build . ${PLAIN_FLAG} --file Dockerfile ${TAG_ARG}

if [[ "$*" == *--push* ]]; then
  docker push ${TAG}
fi
