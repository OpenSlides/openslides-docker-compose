#!/bin/bash

ME="$(basename -s .sh "${BASH_SOURCE[0]}")"
BACKUP_DIR="/var/lib/postgresql/backup/"

usage() {
cat <<EOF
Usage: $ME [<backup label>]
EOF
}

case "$1" in
  --help | -h) usage; exit 0 ;;
esac

# Source the backup() function
. /usr/local/lib/pg-basebackup.sh

MSG="Manual backup invocation"
[[ $# -eq 0 ]] || MSG="$*"

backup "$MSG"
