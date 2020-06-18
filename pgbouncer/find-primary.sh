#!/bin/bash

# This file is sourced by other scripts that need to determine the
# cluster's current primary node.

PG_NODE_LIST="${PG_NODE_LIST:-pgnode1,pgnode2,pgnode3}"
PRIMARY=
OLD_PRIMARY="${OLD_PRIMARY:-}"

IFS="," read -ra node_list <<< "$PG_NODE_LIST"

echo "Trying all configured nodes (${PG_NODE_LIST})..."
for node in "${node_list[@]}"; do
  [[ "$node" = "$OLD_PRIMARY" ]] && continue
  if wait-for-it -q --timeout=20 "${node}:22"; then
    NEW_PRIMARY="$(ssh "${node}" current-primary)" && break
  fi
done

PRIMARY="$(awk '$1 == "PRIMARY:" { print $2 }' <<< "$NEW_PRIMARY")"

if [[ -n "$PRIMARY" ]]; then
  echo "Found primary node: $PRIMARY"
  printf "PRIMARY: %s\n" "$PRIMARY" > /etc/primary
else
  echo "ERROR: Failed to find primary node."
  > /etc/primary
  pkill -SIGUSR1 pgbouncer # PAUSE
  exit 2
fi

# vim: set ft=sh sw=2 et:
