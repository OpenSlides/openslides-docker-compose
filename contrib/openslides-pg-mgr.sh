#!/bin/bash

ME="$(basename -s .sh "${BASH_SOURCE[0]}")"
CMD=
ERRORS=

usage() {
cat << EOF
Usage: $ME <command>

Batch tool to control various aspects of OpenSlides database containers.

Commands:
  -b, --backup-mode=ACTION    Trigger backup mode in Postgres clusters
                              (actions: start, stop)
  -r, --repmgrd=ACTION        Control repmgrd daemon in Postgres cluster nodes
                              (actions: pause, unpause)
  -h, --help                  Show this help message
EOF
}

longopt="help,backup-mode:,repmgrd:"
shortopt="hb:r:"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

# Parse options
while true; do
  case "$1" in
    -b|--backup-mode)
      CMD="manage_backup_mode"
      ACTION="$2"
      case "$ACTION" in
        "start" | "stop") : ;;
        *) echo "ERROR"; exit 2 ;;
      esac
      break
      ;;
    -r|--repmgrd)
      CMD="manage_repmgrd_status"
      ACTION="$2"
      case "$ACTION" in
        "pause" | "unpause") : ;;
        *) echo "ERROR"; exit 2 ;;
      esac
      break
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

[[ -n "$CMD" ]] && [[ -n "$ACTION" ]] || { usage; exit 2; }

manage_backup_mode() {
  local action id name
  action="$1"
  id="$2"
  name="$3"
  printf "INFO: Backup mode %s on node %s (%s)...\n" "$action" "$name" "$id"
  docker exec -u postgres "$id" pg_backuptrigger "$action"
}

manage_repmgrd_status() {
  local action id name
  action="$1"
  id="$2"
  name="$3"
  printf "INFO: %s repgrmd on node %s (%s)...\n" "$action" "$name" "$id"
  docker exec -u postgres "$id" repmgr daemon "$action"
}

CONTAINERS=("$(docker ps \
  --filter label=org.openslides.role=postgres \
  --format '{{.ID}}\t{{.Names}}' |
    grep -v '_postgres_' | # exclude legacy containers
    sort -k2)")

[[ -n "${CONTAINERS[@]}" ]] || {
  echo "No running OpenSlides database containers found."
  exit 0
}

cat << EOF
This will affect the following instances on this host:

${CONTAINERS[@]}

EOF

read -p "Continue? [y/N] " ANS
case "$ANS" in
  Y|y|Yes|yes|YES) : ;;
  *)
    echo "Aborting..."
    exit 0
    ;;
esac

while read -r id name; do
  "$CMD" "$ACTION" "$id" "$name" || ERRORS=1
  echo
done <<< "${CONTAINERS[@]}"

if [[ $ERRORS ]]; then
  echo "WARNING: Finished but WITH ERRORS!"
  exit 1
fi
