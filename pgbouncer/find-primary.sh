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
  echo "ERROR: Failed to find primary node.  Pausing all connections."
  > /etc/primary
  # PAUSE
  pkill -SIGUSR1 pgbouncer || true

  # Exit without an error.  The HEALTHCHECK script is responsible for retrying
  # connections to a primary cluster; it is not necessary to start a new
  # container every time.  HEALTHCHECK's timeout setting should eventually
  # cause the container to be stopped if there was an unexpected problem.
  #
  # Finally, it is important to exit cleanly here, so that PgBouncer can be
  # paused manually, e.g., for database maintenance tasks.  If the script were
  # to exit with an error, HEALTHCHECK would stop the container and spawn a new
  # one which would be unpaused!
  exit 0
fi

# vim: set ft=sh sw=2 et:
