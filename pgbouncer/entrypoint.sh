#!/bin/bash

set -e

SSH_CONFIG_FILES=(
  /var/lib/postgresql/.ssh/id_ed25519
  /var/lib/postgresql/.ssh/id_ed25519.pub
  /var/lib/postgresql/.ssh/known_hosts
)

update_config() {
  printf "* = host=%s\n" "$1" |
    tee /etc/pgbouncer/pgbouncer.database.ini
}

# Fetch SSH files from database
PG_NODE_LIST="${PG_NODE_LIST:-pgnode1,pgnode2,pgnode3}"
IFS="," read -ra node_list <<< "$PG_NODE_LIST"
for node in "${node_list[@]}"; do
  echo "SSH config: trying ${node}..."
  pg_isready -h "$node" -U pgproxy -d instancecfg || { sleep 5; continue; }

  (
    umask 077
    psql -h "$node" -U pgproxy -d instancecfg -qtA -v ON_ERROR_STOP=1 <<< "
      SELECT DISTINCT ON (filename, access) filename FROM dbcfg
      -- WHERE 'pgproxy' = ANY (access)
      ORDER BY filename, access, id DESC;" |
    while read target_filename; do
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

update_config "$PRIMARY"

exec pgbouncer /etc/pgbouncer/pgbouncer.ini

# vim: set ft=sh sw=2 et:
