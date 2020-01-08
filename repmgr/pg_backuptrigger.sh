#!/bin/bash

DEFAULT_LABEL="Backup triggered externally on $(date +%F-%H:%M:%S)"

usage() {
  cat << EOF
Usage: ${BASH_SOURCE[0]} <start|stop> [backup label]

  start: Invokes a backup using pg_start_backup()
  stop:  Stops backups on cluster using pg_stop_backup()
EOF
}

case $1 in
  "start")
    shift
    LABEL=${1:-$DEFAULT_LABEL}
    psql -tAv ON_ERROR_STOP=1 -v label="$LABEL" <<< \
      "SELECT pg_start_backup(:'label')" &&
      cat 11/main/backup_label
    ;;
  "stop")
    psql -tAv ON_ERROR_STOP=1 <<< "SELECT pg_stop_backup()"
    ;;
  *)
    usage
    exit 0
    ;;
esac
