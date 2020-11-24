#!/bin/bash

# Check repmgr cluster status on all OpenSlides database nodes.
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

ME=$(basename -s .sh "${BASH_SOURCE[0]}")

usage() {
cat << EOF
Usage: $ME [--verbose]

This script iterates over all OpenSlides Postgres containers to check the
output of \`repmgr cluster show\`.

By default, the script is quiet and only prints output in case of errors.  The
repmgr command's results can be viewed by enabling the --verbose option.
EOF
}

shortopt="hv"
longopt="help,verbose"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS"
unset ARGS
# Parse options
while true; do
  case "$1" in
    -v | --verbose)
      VERBOSE=1
      shift 1
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

while read -r id name; do
  report="$(docker exec -u postgres "$id" repmgr cluster show)"
  error=$?
  [[ "$VERBOSE" ]] && [[ $error -eq 0 ]] && {
    printf "repmgr status for %s:\n\n%s\n\n" "$name" "$report"
  }
  [[ $error -eq 0 ]] || {
    printf "ERROR on %s! %s (%s) reports:\n\n%s\n\n" \
      "$(hostname)" "$name" "$id" "$report" 1>&2
  }
done < <(docker ps \
  --filter label=org.openslides.role=postgres \
  --format '{{.ID}}\t{{.Names}}' |
  grep -v '_postgres_' | # exclude legacy containers
  sort -k2)
