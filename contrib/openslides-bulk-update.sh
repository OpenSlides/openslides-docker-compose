#!/bin/bash

# This script iterates over a number of OpenSlides Docker instances and updates
# them to the given tag.

INSTANCES=()
MODE=swarm
OSCTL=osstackctl
PATTERN=
TAG=
TIME=
ME="$(basename -s .sh "${BASH_SOURCE[0]}")"

usage() {
cat << EOF
Usage: $ME [<options>] --tag <tag> [--] [<name pattern>...]

  -t, --tag   Docker image tag to which to update
  --at        "at" timespec, cf. \`man at\`
  --mode      Select Docker deployment mode, 'swarm' (default) or 'compose'

The pattern is passed to $OSCTL; so, for details, see \`$OSCTL --help\`.
EOF
}

fatal() {
    echo 1>&2 "ERROR: $*"
    exit 23
}

instance_menu() {
  local tag
  local instances
  tag="$1"
  instances="$2"
  whiptail --title "OpenSlides bulk update" \
    --checklist "Select instances to include in bulk update to tag $tag" \
    25 78 16 \
    --separate-output \
    --clear \
    ${instances[@]} \
    3>&2 2>&1 1>&3
}

shortopt="ht:"
longopt="help,tag:,at:,mode:"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS"
unset ARGS
# Parse options
while true; do
  case "$1" in
    -t | --tag)
      TAG="$2"
      shift 2
      ;;
    --at)
      TIME="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done
PATTERN="$@"

case "$MODE" in
  swarm)   OSCTL=osstackctl;;
  compose) OSCTL=osinstancectl;;
esac

# Verify dependencies
DEPS=(
  "$OSCTL"
  whiptail
  at
  chronic
)
for i in "${DEPS[@]}"; do
  which "$i" > /dev/null || { fatal "Dependency not found: $i"; }
done
# Verify options
[[ -n "$TAG" ]] || { fatal "Missing option: --tag"; }

# Pre-select instances and prepare output for whiptail
readarray INSTANCES_PRE < <("$OSCTL" --color=never ls "$PATTERN")
INSTANCES="$(
  awk '
    $1 == "OK" { i = $3; s = "ON"; printf("%s (%s) %s\n", $2, i, s) }
    $1 == "XX" { i = "offline"; s = "OFF"; printf("%s (%s) %s\n", $2, i, s) }
  ' <<< "${INSTANCES_PRE[@]}" |
  while read -r i v c; do
    printf "%s %s %s\n" "$i" "$v" "$c"
  done
  )"
INSTANCES=($(instance_menu "$TAG" "${INSTANCES[@]}")) # User-selected instances
if [[ $? -eq 0 ]]; then clear; else exit 3; fi
[[ ${#INSTANCES[@]} -ge 1 ]] || exit 0

if [[ -z "$TIME" ]]; then
  # Execute immediately
  n=0
   for i in "${INSTANCES[@]}"; do
     (( n++ ))
     str=" Updating ${i} (${n}/${#INSTANCES[@]})... "
     echo
     echo "$str" | sed -e 's/./—/g'
     echo "$str"
     echo "$str" | sed -e 's/./—/g'
     "$OSCTL" --tag "$TAG" update "$i"
   done
else
  # Prepare "at" job
  for i in "${INSTANCES[@]}"; do
    echo "chronic \"$OSCTL\" --tag \"$TAG\" update \"$i\""
  done |
  at "$TIME"
fi
