#!/bin/bash

# This script iterates over a number of OpenSlides Docker instances and updates
# them to the given tag.
#
# -------------------------------------------------------------------
# Copyright (C) 2020 by Intevation GmbH
# Author(s):
# Gernot Schulz <gernot@intevation.de>
#
# This program is distributed under the MIT license, as described
# in the LICENSE file included with the distribution.
# SPDX-License-Identifier: MIT
# -------------------------------------------------------------------

INSTANCES=()
MODE=swarm
OSCTL=osstackctl
PATTERN=
TAG=
TIME=
ME="$(basename -s .sh "${BASH_SOURCE[0]}")"

usage() {
cat << EOF
Usage: $ME [<options>] --tag <tag> < INSTANCES

  -t TAG, --tag=TAG   Docker image tag to which to update
  --at=TIME           "at" timespec, cf. \`man at\`
  --mode=MODE         Select Docker deployment mode, 'swarm' (default)
                      or 'compose'

$ME expects the output of "osinstancectl ls" on its standard input.
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

# Read instance listing from osinstancectl/osstackctl on stdin
INSTANCES="$(
  while IFS= read -r line; do
    # Skip irrelevant lines, probably from ls --long
    grep -q '^[^\ ]' <<< "$line" || continue
    read -r status instance version memo <<< "$line"
    # Pre-select instances
    [[ -n "$status" ]] || continue
    if [[ "$status" = "OK" ]]; then
      checked="ON"
    else
      checked="OFF"
      version="offline"
    fi
    # XXX: Currently, this code can only parse osinstancectl's default short
    # listing output because it include the version directly on the same line.
    # Multi-line parsing for `ls --long` output could be added if necessary.
    [[ -n "$version" ]] || version="parsing_error"
    # Prepare output for whiptail
    printf "%s (%s) %s\n" "$instance" "$version" "$checked"
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
     "$OSCTL" --all-tags "$TAG" update "$i"
   done
else
  # Prepare "at" job
  for i in "${INSTANCES[@]}"; do
    echo "chronic \"$OSCTL\" --all-tags \"$TAG\" update \"$i\""
  done |
  at "$TIME"
fi
