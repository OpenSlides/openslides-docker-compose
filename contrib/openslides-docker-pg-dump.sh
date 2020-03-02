#!/bin/bash

set -euo pipefail
umask 0027

BACKUP_PATH="/backup/docker-sql-dumps"
NAME_FILTER="."
ME=$(basename -s .sh "${BASH_SOURCE[0]}")

usage() {
cat <<EOF
Usage: ${BASH_SOURCE[0]} [options] [<container name filter>]

Create SQL dumps from OpenSlides dockerized Postgres DBs.  Containers can be
specified using their names.  Without arguments, the script iterates over all
OpenSlides database containers!

Removal of dumps should be handled by an external tool.  The dumps are not
compressed to allow for more effective deduplication by backup tools.

Options:
  -o, --output-dir   Specify output directory for SQL dumps
                     (default: $BACKUP_PATH)
EOF
}

shortopt="ho:"
longopt="help,output-dir:"

ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

# Parse options
while true; do
  case "$1" in
    -o|--output-dir)
      BACKUP_PATH="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

[[ -d "$BACKUP_PATH" ]] || { echo "ERROR: $BACKUP_PATH not found!"; exit 3; }

NAME_FILTER="$*"

CONTAINERS=("$(docker ps \
  --filter label=org.openslides.role=postgres \
  --format '{{.ID}}\t{{.Names}}' |
    grep -v '_postgres_' | # exclude legacy containers
    sort -k2)")

while read id name; do
  printf "$name" | grep -q "$NAME_FILTER" || continue
  docker exec -u postgres "$id" pg_dumpall \
    > "${BACKUP_PATH}/${name}-$(date +'%F-%T').sql"
done <<< "${CONTAINERS[@]}"
