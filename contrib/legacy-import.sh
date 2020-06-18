#!/bin/bash

# Import export.tar.gz from legacy OpenSlides instances into a fresh database.

set -e

CONTAINER="$1"
TARBALL="$2"

usage() {
cat << EOF
Usage: ${BASH_SOURCE[0]} <pgnode1 container> <export.tar.gz>

  This script imports tarball exports from legacy instances.
EOF
}

[[ $# -eq 2 ]]        || { usage; exit 2; }
[[ -n "$CONTAINER" ]] || { usage; exit 2; }
[[ -f "$TARBALL" ]]   || { usage; exit 2; }

echo "WARNING: This script will delete the given database before importing data!"
read -p "Proceed? [y/N] " PROCEED
case "$PROCEED" in
  Y|y|Yes|yes|YES) ;;
  *) exit 0 ;;
esac

TEMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TEMPDIR"; }
trap cleanup EXIT

CONTAINER_ID="$(docker ps -q --filter status=running \
  --filter name="$CONTAINER")"
[[ -n "$CONTAINER_ID" ]] || { echo "ERROR: Container not found."; exit 1; }

echo "Preparing SQL scripts..."
tar --wildcards -C "$TEMPDIR" -xf "$TARBALL" "*.sql"

docker exec -u postgres "$CONTAINER_ID" dropdb openslides
docker exec -u postgres "$CONTAINER_ID" createdb -O openslides openslides

for i in openslides mediafiledata instancecfg; do
  echo "Importing ${i}..."
  docker exec -i -u postgres "$CONTAINER_ID" psql -q1 "$i" \
    < "${TEMPDIR}/${i}.sql" > /dev/null
done

echo "Extracting instance files from tarball..."
tar -vxf "$TARBALL" secrets metadata.txt
