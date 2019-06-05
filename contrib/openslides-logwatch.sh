#!/bin/bash

# Extract logs from OpenSlides journald logs

set -uo pipefail

ME=$(basename -s .sh "${BASH_SOURCE[0]}")
INSTANCES=()
SINCE=-10m # default value

usage() {
  cat << EOF
Usage: $ME [options] [instance directories...]

Poor journald logger's log monitoring: this script gathers Tracebacks from
OpenSlides server container logs and prints them to stdout.  It is intended to
be run as a cronjob.

Instances can be specified by their project directories.  Without arguments,
the script monitors all instances discoverable by osinstancectl.

Example crontab entry:
  */10 *  * * *   root    $ME --since=-10m

Prerequisites:
  - Docker must be configured to use the journald logging backend.
  - osinstancectl must be installed in PATH.

Options:
  -S, --since=    Show log since given date.  The date specification's format
                  must be valid for journalctl (see journalctl(1),
                  systemd.time(7)).  Default: $SINCE
EOF
}

shortopt="hS:"
longopt="help,since:"

ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

while true; do
  case "$1" in
    -S|--since)
      SINCE="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done
INSTANCES=($@)

LOGGING_DRIVER=$(docker info --format '{{.LoggingDriver}}')
if [[ "$LOGGING_DRIVER" != "journald" ]]; then
  echo "ERROR: Docker is not configured to use the journald logging driver!" \
    > /dev/stderr
  exit 23
fi

# Auto-discovery of instances if none specified
if [[ ${#INSTANCES[@]} -eq 0 ]]; then
  INSTANCES=(
    $(osinstancectl --color=never -l ls | awk '$2 == "Directory:" {print $3}')
    )
fi

for instance in ${INSTANCES[@]}; do
  if [[ ! -d "$instance" ]]; then
    echo "ERROR: $instance not found!" > /dev/stderr
    continue
  fi
  cd "$instance"
  for s in server prioserver; do
    id=$(docker-compose ps -q $s)
    [[ -n "$id" ]] || continue
    name="$(docker inspect --format '{{ .Name }}' $id | tr -d \/)"
    journalctl --output=short-iso --since="$SINCE" CONTAINER_NAME="$name" |
    gawk -v name="$name" '
      /Traceback/ {
        s=1;
        i=match($0, /Traceback/);
        a[NR]=$0;
        next;
      }
      s==1 {
        a[NR]=$0
        last_tb_line = substr($0, i, 1)
      }
      last_tb_line && last_tb_line != " " {
        # Traceback ends here
        s=0
        last_tb_line=""

        # ignore types of tracebacks:
        # if ( $0 ~ /ExampleKnownError:/ ) { delete a; next; }

        print "Traceback in", name
        for (i in a) { print a[i]; }
        print "---------------------------------------------------------------------"
        delete a
      }
      '
  done
done
