#!/bin/bash

[[ $# -eq 1 ]] || {
  echo "ERROR: requires exactly 1 argument."
  exit2
}

cat << EOF | tee /etc/pgbouncer/pgbouncer.database.ini
openslides    = host=$1
mediafiledata = host=$1 pool_size=250
*             = host=$1
EOF
