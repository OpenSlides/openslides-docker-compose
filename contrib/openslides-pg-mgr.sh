#!/bin/bash

ME="$(basename -s .sh "${BASH_SOURCE[0]}")"
CMD=
ERRORS=

readonly CMD_SWITCHOVER="repmgr standby switchover --fast-checkpoint --siblings-follow"

usage() {
cat << EOF
Usage: $ME <command>

Batch tool to control various aspects of OpenSlides database containers.

Commands:
  -b, --backup-mode=ACTION    Trigger backup mode in Postgres clusters
                              (actions: start, stop)
  -r, --repmgrd=ACTION        Control repmgrd daemon in Postgres cluster nodes
                              (actions: pause, unpause)
  --switch-from=PRIMARY       Initiate repmgr switchover from given primary
                              cluster (default: auto-detect).  May be combined
                              with --switch-to.
  --switch-to=STANDBY         Initiate repmgr switchover to given standby node
                              (default: service on localhost).  May be combined
                              with --switch-from.
  -h, --help                  Show this help message
EOF
}

longopt="help,backup-mode:,repmgrd:,switch-from:,switch-to:"
shortopt="hb:r:"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

# XXX: No checks for nonsensical combinations.  It would be better to
# differentiate between commands, e.g., switch, and options, e.g., to/from.

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
    --switch-from)
      CMD="repmgrd_switchover"
      SWITCH_FROM="$2"
      shift 2
      ;;
    --switch-to)
      CMD="repmgrd_switchover"
      SWITCH_TO="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

[[ -n "$CMD" ]] || { usage; exit 2; }

[[ "$SWITCH_FROM" ]] && [[ "$SWITCH_TO" ]] && {
  [[ "$SWITCH_FROM" != "$SWITCH_TO" ]] || {
    echo "ERROR: --switch-from and --switch-to must not be the same node."
    exit 2
  }
}

manage_backup_mode() {
  local action id name
  id="$1"
  name="$2"
  action="$ACTION"
  printf "INFO: Backup mode %s on node %s (%s)...\n" "$action" "$name" "$id"
  docker exec -u postgres "$id" pg_backuptrigger "$action"
}

manage_repmgrd_status() {
  local action id name
  id="$1"
  name="$2"
  action="$ACTION"
  printf "INFO: %s repmgr on node %s (%s)...\n" "$action" "$name" "$id"
  docker exec -u postgres "$id" repmgr daemon "$action"
}

repmgrd_switchover() {
  local id name
  id="$1"
  name="$2"
  local switch_source="$SWITCH_FROM"
  local switch_target="$SWITCH_TO"

  printf -- "-- %s --\n\n" "$name"

  local this_node
  this_node="$(docker exec -u postgres "$id" repmgr node check --csv |
    awk -F, '$1 == "\"Node name\"" { gsub(/"/, "", $2); print $2 }')"

  local current_primary
  current_primary="$(docker exec -u postgres "$id" repmgr cluster show |
    awk '$1 ~ /[0-9]/ && $5 == "primary" { print $3 }')"

  # Checks
  if [[ -n "$SWITCH_FROM" ]]; then
    [[ "$switch_source" = "$current_primary" ]] || {
      printf "%s is not the primary (%s); skipping it.\n" "$switch_source" "$current_primary"
      return 0 # Not an error but skip this instance
    }
  else
    switch_source="$current_primary"
  fi
  if [[ -n "$SWITCH_TO" ]]; then
    [[ "$switch_target" != "$current_primary" ]] || {
      printf "NOTICE: Cannot switch to %s because it is already a primary.\n" "$SWITCH_TO"
      return 0 # Not an error but skip this instance
    }
  else
    switch_target="$this_node"
  fi
  [[ "$switch_target" != "$switch_source" ]] || {
    printf "\nTarget and source node are identical (%s); skipping it.\n" "$switch_source"
    return 0
  }

  echo "Cluster status before switchover:"
  docker exec -u postgres "$id" repmgr cluster show || {
    printf "\nERROR: This cluster is unhealthy (%s); skipping it!\n" "$id"
    return 1
  }

  printf "\nAttempting repgrmd switch-over %s -> %s on node %s (%s)...\n\n" \
    "$switch_source" "$switch_target" "$name" "$id"

  echo "NOTICE: Pausing pgbouncer."
  docker exec -u postgres "$id" \
    psql -U postgres -h pgbouncer -d pgbouncer -c PAUSE

  # Initiate switch-over
  if [[ "$switch_target" = "$this_node" ]]; then
    # On local Docker node
    docker exec -u postgres "$id" $CMD_SWITCHOVER --dry-run &&
    docker exec -u postgres "$id" $CMD_SWITCHOVER
  else
    # On a remote Docker node (connect to remote repmgr node through
    # dbnet-internal SSH)
    docker exec -u postgres "$id" \
      ssh -n "$switch_target" "$CMD_SWITCHOVER" --dry-run &&
    docker exec -u postgres "$id" \
      ssh -n "$switch_target" "$CMD_SWITCHOVER"
  fi

  echo "INFO: Not resuming PgBouncer; relying on pgbouncer service's HEALTHCHECK for this."

  echo "Cluster status after switchover:"
  docker exec -u postgres "$id" repmgr cluster show
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
  "$CMD" "$id" "$name" || ERRORS=1
  echo
done <<< "${CONTAINERS[@]}"

if [[ $ERRORS ]]; then
  echo "WARNING: Finished but WITH ERRORS!"
  exit 1
fi
