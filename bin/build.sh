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
#  --cascading-fallback   If this flag is set, the build will attempt to use a cascading fallback mechanism for the source directories, based on the given version number.
#  --source-image-tag=tag When using --cascading-fallback, this flag can be used to specify the source images tag to pass as "SOURCE_IMAGE_TAG" build-arg to the Docker build process.
#                         If omitted, the source tag will be ${version}-${type} or just ${version} if type was not set.
#  --source-image-type=type Basically the same as --source-image-tag, but defines only the type part of the tag. The version part is always taken from the given version parameter.
#                           If both --source-image-tag and --source-image-type are given, --source-image-tag takes precedence.
#  --build-arg=KEY=VALUE  Pass additional build arguments to the docker build process. Can be used multiple times.
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
  BUILD_DIRECTORY="${BIN_DIR}/../src/${IMAGE_NAME}"
  BUILD_TAG="${VERSION}"
else
  BUILD_DIRECTORY="${BIN_DIR}/../src/${IMAGE_NAME}/${TYPE}"
  BUILD_TAG="${VERSION}-${TYPE}"
fi

if [[ "$*" == *--cascading-fallback* ]]; then
  source "${BIN_DIR}/util/find-source-path.sh"
  echo "  - Looking for source path with cascading fallback for version: ${VERSION}"
  BUILD_DIRECTORY="$(find_source_path "${BUILD_DIRECTORY}" "${VERSION}")"

  if [[ -z "${BUILD_DIRECTORY}" ]]; then
    echo "  - Could not find a valid source directory for version ${VERSION}"
    exit 44
  fi
else
  BUILD_DIRECTORY="${BUILD_DIRECTORY}/${VERSION}"
fi

if [[ ! -d "${BUILD_DIRECTORY}" ]]; then
  echo "The build directory ${BUILD_DIRECTORY} does not exist!"
  exit 1
fi

cd "${BUILD_DIRECTORY}"

TAG="${TAG_BASE}${IMAGE_NAME}:${BUILD_TAG}"
TAG_LATEST=""
TAG_ARG="--tag ${TAG}"
if [[ "$*" == *--push-with-latest* ]]; then
  TAG_LATEST="${TAG_BASE}${IMAGE_NAME}:latest"
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
    BUILD_ARG_VALUE=$(echo "$arg" | cut -d'=' -f2-)
    BUILD_ARGS+=("--build-arg" "${BUILD_ARG_VALUE}")
  fi
done

# Add SOURCE_IMAGE_TAG build-arg if cascading-fallback is used
if [[ "$*" == *--cascading-fallback* ]]; then
  SOURCE_IMAGE_TAG=""
  if [[ "$*" == *--source-image-tag* ]]; then
    for arg in "$@"; do
      if [[ "$arg" == --source-image-tag* ]]; then
        SOURCE_IMAGE_TAG_VALUE=$(echo "$arg" | cut -d'=' -f2)
        SOURCE_IMAGE_TAG="${SOURCE_IMAGE_TAG_VALUE}"
        break
      fi
    done
  elif [[ "$*" == *--source-image-type* ]]; then
    SOURCE_IMAGE_TYPE_VALUE=""
    for arg in "$@"; do
      if [[ "$arg" == --source-image-type* ]]; then
        SOURCE_IMAGE_TYPE_VALUE=$(echo "$arg" | cut -d'=' -f2)
        break
      fi
    done
    if [[ -z "${SOURCE_IMAGE_TYPE_VALUE}" ]]; then
      SOURCE_IMAGE_TAG="${VERSION}"
    else
      SOURCE_IMAGE_TAG="${VERSION}-${SOURCE_IMAGE_TYPE_VALUE}"
    fi
  else
    if [[ -z "${TYPE}" ]]; then
      SOURCE_IMAGE_TAG="${VERSION}"
    else
      SOURCE_IMAGE_TAG="${VERSION}-${TYPE}"
    fi
  fi
  BUILD_ARGS+=("--build-arg" "SOURCE_IMAGE_TAG=${SOURCE_IMAGE_TAG}")
fi

echo "[BUILD] Building Docker image"
echo "  - Image Name: ${IMAGE_NAME}"
echo "  - Version: ${VERSION}"
echo "  - Tags: ${TAG}${TAG_LATEST:+, ${TAG_LATEST}}"
echo "  - Build directory: ${BUILD_DIRECTORY}"

if [ ${#BUILD_ARGS[@]} -gt 0 ]; then
  echo "  - Build arguments: ${BUILD_ARGS[*]}"
fi

echo "CMD > docker build . ${PLAIN_FLAG} --file Dockerfile ${TAG_ARG} ${BUILD_ARGS[*]}"
docker build . ${PLAIN_FLAG} --file Dockerfile ${TAG_ARG} ${BUILD_ARGS[@]}

if [[ "$*" == *--push* ]]; then
  docker push "${TAG}"
fi
if [[ "$*" == *--push-with-latest* ]]; then
  docker push "${TAG_LATEST}"
fi
