#!/bin/bash
set -e

# Usage: bin/discover-and-build.sh "image_name" "source_namespace" "source_image_name" [--filter=filter] [--push] [--push-with-latest] [--plain] [--precision=N]
# Parameters:
#  image_name            The name of the image to build (e.g. nginx) (This relates to the folder structure in src/)
#  source_namespace      The namespace of the source image to discover versions from (e.g. library)
#  source_image_name     The name of the source image to discover versions from (e.g. nginx)
# Flags:
#  --tracked-versions=N  Number of most recent versions to track/build (default: 3)
#  --type=type           The type of the image to build (e.g. fpm-debian) This is optional and can be omitted for images without sub-types. Will be forwarded to the build script.
#  --source-image-type=type Allows for filtering the tags for a certain type (e.g. "alpine" to get only alpine variants)
#  --push                Push the built images to the Docker registry
#  --push-with-latest    Additionally tag the latest of the built images as "latest" and push it
#  --plain               Use plain output for the docker build process
#  --precision=N         Number of version segments to consider when discovering versions (e.g., 2 for major.minor), default is 3 (major.minor.patch)
#  --last-version=x.y.z  Helper for deprecation. Can be set to a version that will be the last to built. Even if newer versions are discovered, they will not be built.
#                        If the given version is not found, no build will be performed. This must be in the format matching the precision.
# Examples:
#   bin/discover-and-build.sh "nginx" "library" "nginx"

echo "[DISCOVER AND BUILD] Starting discovery and build process..."

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKED_VERSION_NUM=3 # How many of the most recent versions to track/build

IMAGE_NAME=$1
IMAGE_TYPE=""
SOURCE_NAMESPACE=$2
SOURCE_IMAGE_NAME=$3
SOURCE_IMAGE_TYPE=""
SOURCE_IMAGE_VERSION_PRECISION=3

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

echo "[DISCOVER AND BUILD] Starting discovery for image: ${IMAGE_NAME}"
if [[ "$*" == *--type=* ]]; then
  IMAGE_TYPE=$(echo "$*" | grep -oP '(?<=--type=)[^ ]+')
  echo "  - Building type: ${IMAGE_TYPE} of image: ${IMAGE_NAME}"
fi

echo "  - Using source image: ${SOURCE_NAMESPACE}/${SOURCE_IMAGE_NAME}"

if [[ "$*" == *--source-image-type=* ]]; then
  SOURCE_IMAGE_TYPE=$(echo "$*" | grep -oP '(?<=--source-image-type=)[^ ]+')
  echo "  - Filtering sources by type: ${SOURCE_IMAGE_TYPE}"
fi
if [[ "$*" == *--precision=* ]]; then
  SOURCE_IMAGE_VERSION_PRECISION=$(echo "$*" | grep -oP '(?<=--precision=)[^ ]+')
fi

if ! [[ "${SOURCE_IMAGE_VERSION_PRECISION}" =~ ^[1-3]$ ]]; then
  echo "Invalid precision value: ${SOURCE_IMAGE_VERSION_PRECISION}. It must be 1, 2, or 3."
  exit 1
fi

echo "  - Using version precision: ${SOURCE_IMAGE_VERSION_PRECISION}"

if [[ "$*" == *--tracked-versions=* ]]; then
  TRACKED_VERSION_NUM=$(echo "$*" | grep -oP '(?<=--tracked-versions=)[^ ]+')
fi

if ! [[ "${TRACKED_VERSION_NUM}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid tracked versions number: ${TRACKED_VERSION_NUM}. It must be a positive integer."
  exit 1
fi

source "${BIN_DIR}/util/docker-version-utils.sh"

VERSIONS_TO_BUILD=$(get_latest_versions "$SOURCE_NAMESPACE" "$SOURCE_IMAGE_NAME" "$TRACKED_VERSION_NUM" "$SOURCE_IMAGE_TYPE" "$SOURCE_IMAGE_VERSION_PRECISION")

# If empty, exit here
if [[ -z "${VERSIONS_TO_BUILD}" ]]; then
  FILTER_MESSAGE=""
  if [[ -n "${SOURCE_IMAGE_TYPE}" ]]; then
    FILTER_MESSAGE=" with source type filter: '${SOURCE_IMAGE_TYPE}'"
  fi
  echo "[DISCOVER AND BUILD] No versions found to build for image ${SOURCE_IMAGE_NAME}${FILTER_MESSAGE}"
  exit 0
fi

# Special handling for --last-version flag (deprecation helper)
if [[ "$*" == *--last-version=* ]]; then
  LAST_VERSION=$(echo "$*" | grep -oP '(?<=--last-version=)[^ ]+')
  echo "[DISCOVER AND BUILD] Last version to build is set to: ${LAST_VERSION}"
  VERSIONS_CSV=$(printf "%s\n" "$VERSIONS_TO_BUILD" | paste -sd, -)
  echo "  - Checking if this version exists among the discovered versions (${VERSIONS_CSV})..."

  if ! echo "$VERSIONS_TO_BUILD" | grep -q "^${LAST_VERSION}$"; then
    # We need to make sure, that the "last version" is smaller than the greatest discovered version
    # If not, we assume the "last-version" is not yet released in the upstream
    # so we can simply build all discovered versions
    GREATEST_DISCOVERED_VERSION=$(echo "$VERSIONS_TO_BUILD" | sort -Vr | head -n1)
    if dpkg --compare-versions "$LAST_VERSION" "ge" "$GREATEST_DISCOVERED_VERSION"; then
      echo "[DISCOVER AND BUILD] The specified last version ${LAST_VERSION} is greater than or equal to the greatest discovered version ${GREATEST_DISCOVERED_VERSION}. All discovered versions will be built."
      # No filtering needed
      :
    else
      echo "[DISCOVER AND BUILD] The specified last version ${LAST_VERSION} was not found among the discovered versions. No build will be performed."
      echo "Triggering an error, to alert the maintainer, to remove the pipeline/job using this flag; completely phased out."
      exit 1
    fi
  fi

  # Filter the versions to only include up to and including the last version
  VERSIONS_TO_BUILD=$(echo "$VERSIONS_TO_BUILD" | awk -v last="$LAST_VERSION" '
  {
    for (i = 1; i <= NF; i++) {
      print $i
      if ($i == last) {
        exit
      }
    }
  }')
fi

VERSIONS_CSV=$(printf "%s\n" "$VERSIONS_TO_BUILD" | paste -sd, -)
echo "[DISCOVER AND BUILD] Discovered versions to build: ${VERSIONS_CSV}"

SOMETHING_WAS_BUILT=0

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
  if [[ "$*" == *--push-with-latest* && $(is_latest_version "$VERSION" "$VERSIONS_TO_BUILD") ]]; then
    BUILD_PARAMS+=("--push-with-latest")
  fi

  BUILD_PARAMS+=("--cascading-fallback")
  BUILD_PARAMS+=("--source-image-type=${SOURCE_IMAGE_TYPE}")

  # If the script exited with error code 44, it means no suitable source directory was found for this version, skip it silently
  BUILD_EXIT_CODE=0
  "${BIN_DIR}/build.sh" "${IMAGE_NAME}" "${VERSION}" "${IMAGE_TYPE}" "${BUILD_PARAMS[@]}" || BUILD_EXIT_CODE=$?
  if [ "${BUILD_EXIT_CODE}" -eq 44 ]; then
    echo "[DISCOVER AND BUILD] Skipping version ${VERSION} due to missing suitable source directory."
    continue
  elif [ "${BUILD_EXIT_CODE}" -ne 0 ]; then
    echo "[DISCOVER AND BUILD] Build failed for version ${VERSION} with exit code ${BUILD_EXIT_CODE}."
    exit ${BUILD_EXIT_CODE}
  fi

  SOMETHING_WAS_BUILT=1
done

if [ "${SOMETHING_WAS_BUILT}" -eq 0 ]; then
  echo "[DISCOVER AND BUILD] No versions were built."
  exit 1
fi
