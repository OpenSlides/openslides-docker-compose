#!/bin/bash

# -------------------------------------------------------------------
# Copyright (C) 2020 by Intevation GmbH
# Author(s):
# Gernot Schulz <gernot@intevation.de>
#
# This program is distributed under the MIT license, as described
# in the LICENSE file included with the distribution.
# SPDX-License-Identifier: MIT
# -------------------------------------------------------------------

set -e

SSH_CONFIG_FILES=(
  /var/lib/postgresql/.ssh/id_ed25519
  /var/lib/postgresql/.ssh/id_ed25519.pub
  /var/lib/postgresql/.ssh/known_hosts
)

# Fetch SSH files from database
PG_NODE_LIST="${PG_NODE_LIST:-pgnode1,pgnode2,pgnode3}"
IFS="," read -ra node_list <<< "$PG_NODE_LIST"
for node in "${node_list[@]}"; do
  (( n += 1 ))
  echo "SSH config: trying ${node} (${n}/${#node_list[@]})..."
  if ! pg_isready -h "$node" -U pgproxy -d instancecfg; then
    if [[ $n -lt ${#node_list[@]} ]]; then
      sleep 10
      continue
    else
      echo "ERROR: Could not establish SSH connection to any Postgres node."
      exit 3
    fi
  fi

  (
    umask 077
    psql -h "$node" -U pgproxy -d instancecfg -qtA0 -v ON_ERROR_STOP=1 <<< "
      SELECT DISTINCT ON (filename, access) filename FROM dbcfg
      -- WHERE 'pgproxy' = ANY (access)
      ORDER BY filename, access, id DESC;" |
    while IFS= read -r -d $'\0' target_filename; do
      echo "Fetching ${target_filename} from database..."
      psql -h "$node" -U pgproxy -d instancecfg -qtA <<< "
        SELECT DISTINCT ON (filename, access) data from dbcfg
          WHERE filename = '${target_filename}'
          -- AND   'pgproxy' = ANY (access)
          ORDER BY filename, access, id DESC;
        " | xxd -r -p > "${target_filename}"
    done
  ) && break
done

for i in "${SSH_CONFIG_FILES[@]}"; do
  [[ -f "$i" ]] || {
    echo "ERROR: $i does not exist.  Cannot continue."
    exit 3
  }
done

# Set PRIMARY or exit
. /usr/local/lib/find-primary.sh

/usr/local/bin/update-config.sh "$PRIMARY"
pkill -HUP pgbouncer &&
pkill -SIGUSR2 pgbouncer # RESUME

exec pgbouncer /etc/pgbouncer/pgbouncer.ini

# vim: set ft=sh sw=2 et:
