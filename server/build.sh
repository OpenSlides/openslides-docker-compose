#!/bin/bash

set -e

IMG_NAME="openslides"
REPOSITORY_URL="https://github.com/OpenSlides/OpenSlides.git"
GIT_CHECKOUT="master"
DOCKER_REPOSITORY=
DOCKER_TAG="latest"
CONFIG="/etc/osinstancectl"

usage() {
  cat << EOF
Usage: $(basename ${BASH_SOURCE[0]}) [<options>] [<dir>]

Options:
  -r, --revision     The OpenSlides version to check out
                     (default: $GIT_CHECKOUT)
  -R, --repo         The OpenSlides repository to clone
                     (default: $REPOSITORY_URL)
  -D, --docker-repo  Specify a Docker repository
                     (default: unspecified, i.e., system default)
  -t, --tag          Tag the Docker image (default: $DOCKER_TAG)
EOF
}

# Config file
if [[ -f "$CONFIG" ]]; then
  echo "Found ${CONFIG} file."
  source "$CONFIG"
fi

shortopt="hr:R:D:t:"
longopt="help,revision:,repo:,docker-repo:,tag:"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

# Parse options
while true; do
  case "$1" in
    -r|--revision)
      GIT_CHECKOUT="$2"
      shift 2
      ;;
    -R|--repo)
      REPOSITORY_URL="$2"
      shift 2
      ;;
    -D|--docker-repo)
      DOCKER_REPOSITORY="$2"
      shift 2
      ;;
    -t|--tag)
      DOCKER_TAG="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

DIR="$1"
if [[ -d "$DIR" ]]; then
  cd "$DIR"
else
  cd "$(dirname ${BASH_SOURCE[0]})"
fi

IMG="${IMG_NAME}:${DOCKER_TAG}"
if [[ -n "$DOCKER_REPOSITORY" ]]; then
  IMG="${DOCKER_REPOSITORY}/${IMG}"
fi

read -p "Build image '$IMG'? [y/N] " REPL
case "$REPL" in
  Y|y|Yes|yes|YES)
    echo "Building $IMG..." ;;
  *)
    exit 0;;
esac

set -x
docker build \
  --build-arg "REPOSITORY_URL=${REPOSITORY_URL}" \
  --build-arg "GIT_CHECKOUT=${GIT_CHECKOUT}" \
  --tag "$IMG" \
  --pull \
  .
set +x

read -p "Push image '$IMG' to repository? [y/N] " REPL
case "$REPL" in
  Y|y|Yes|yes|YES)
    docker push "$IMG" ;;
esac
