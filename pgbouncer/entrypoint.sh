#!/bin/bash

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
  pg_isready -h pgnode1 || continue
  (
    umask 077
    for i in "${SSH_CONFIG_FILES[@]}"; do
      echo "Fetching ${i} from database..."
      psql -h pgnode1 -d dbcfg -qtA \
        -c "SELECT data from files WHERE filename = '${i}' ORDER BY id DESC LIMIT 1" \
        | base64 -d - > "${i}"
    done
  ) && break
done

# Set PRIMARY or exit
. /usr/local/lib/find-primary.sh

update_config "$PRIMARY"

exec pgbouncer /etc/pgbouncer/pgbouncer.ini

# vim: set ft=sh sw=2 et:
