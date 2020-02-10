#!/bin/bash

# This is a wrapper script that will activate Postgres' backup mode on
# all OpenSlides database containers.  The containers are identified by
# the label org.openslides.role=postgres.

ME=$(basename -s .sh "${BASH_SOURCE[0]}")
ACTION=
ERRORS=

usage() {
cat <<EOF
Usage: $ME <start|stop>

Trigger Postgres's backup mode in all OpenSlides database containers.
The containers are identified by the label org.openslides.role=postgres.
EOF
}

case "$1" in
  start)
    ACTION=start ;;
  stop)
    ACTION=stop ;;
  *)
    usage
    exit 2 ;;
esac

while read -r id name; do
  printf "INFO: Backup mode %s on node %s (%s)...\n" "$ACTION" "$name" "$id"
  docker exec -u postgres "$id" pg_backuptrigger "$ACTION" || ERRORS=1
  echo
done < <(docker ps \
  --filter label=org.openslides.role=postgres \
  --format '{{.ID}}\t{{.Names}}' | sort -k2)

if [[ $ERRORS ]]; then
  echo "WARNING: Finished but WITH ERRORS!"
  exit 1
fi
