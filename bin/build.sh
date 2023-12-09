#!/bin/bash
TAG_BASE="neunerlei/php"

VERSION=$1

# fail if version was not given
if [[ -z "${VERSION}" ]]; then
  echo "Please provide a version as the first parameter!"
  exit 1
fi

TYPE=$2
if [[ -z "${TYPE}" ]]; then
  echo "Please provide the image type as second parameter!"
  exit 1
fi

cd ${BASH_SOURCE%/*}/../src/${VERSION}/${TYPE}

TAG="${TAG_BASE}:${VERSION}-${TYPE}"
TAG_ARG="--tag ${TAG}"

docker build . --file Dockerfile ${TAG_ARG}

if [[ "$*" == *--push* ]]; then
  docker push ${TAG}
fi
