#!/bin/bash

set -e

DOCKER_REPOSITORY="openslides"
DOCKER_TAG="latest"
CONFIG="/etc/osinstancectl"
OPTIONS=()
BUILT_IMAGES=()
DEFAULT_TARGETS=(repmgr)

usage() {
  cat << EOF
Usage: $(basename ${BASH_SOURCE[0]}) [<options>] [<dir>...]

Options:
  -D, --docker-repo  Specify a Docker repository
                     (default: unspecified, i.e., system default)
  -t, --tag          Tag the Docker image (default: $DOCKER_TAG)
  --no-cache         Pass --no-cache to docker-build
EOF
}

# Config file
if [[ -f "$CONFIG" ]]; then
  echo "Found ${CONFIG} file."
  source "$CONFIG"
fi

shortopt="hr:D:t:"
longopt="help,docker-repo:,tag:,no-cache"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

# Parse options
while true; do
  case "$1" in
    -D|--docker-repo)
      DOCKER_REPOSITORY="$2"
      shift 2
      ;;
    -t|--tag)
      DOCKER_TAG="$2"
      shift 2
      ;;
    --no-cache)
      OPTIONS+="--no-cache"
      shift 1
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

TARGETS=($@)
[[ "${#TARGETS[@]}" -ge 1 ]] || TARGETS=("${DEFAULT_TARGETS[@]}")

# Check availability of all requested targets beforehand
for i in "${TARGETS[@]}"; do
  DOCKERFILE="$(dirname "${BASH_SOURCE[0]}")/${i}/Dockerfile"
  [[ -f "$DOCKERFILE" ]] || {
    echo "ERROR: $DOCKERFILE not found."
    exit 2
  }
  DOCKERFILE=
done

for i in "${TARGETS[@]}"; do
  IMG_NAME="openslides-${i}"
  IMG="${IMG_NAME}:${DOCKER_TAG}"
  if [[ -n "$DOCKER_REPOSITORY" ]]; then
    IMG="${DOCKER_REPOSITORY}/${IMG}"
  fi

  (
    cd "$(dirname "${BASH_SOURCE[0]}")/${i}"
    echo "Building $IMG..."
    set -x
    docker build --tag "$IMG" --pull "${OPTIONS[@]}" .
    set +x
  )
  BUILT_IMAGES+=("$IMG")
done

for IMG in "${BUILT_IMAGES[@]}"; do
  read -p "Push image '$IMG' to repository? [y/N] " REPL
  case "$REPL" in
    Y|y|Yes|yes|YES)
      docker push "$IMG" ;;
  esac
done
