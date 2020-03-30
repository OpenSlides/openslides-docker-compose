#!/bin/bash

PRIMARY=
NEW_PRIMARY=
OLD_PRIMARY="$(awk '$1 == "PRIMARY:" { print $2 }' /etc/primary)"

# Try currently configured primary
if [[ -n "$OLD_PRIMARY" ]]; then
  echo "Trying current primary (${OLD_PRIMARY})..."
  if wait-for-it -q --timeout=20 "${OLD_PRIMARY}:22"; then
    if NEW_PRIMARY="$(ssh "${OLD_PRIMARY}" current-primary)"; then
      PRIMARY="$(awk '$1 == "PRIMARY:" { print $2 }' <<< "$NEW_PRIMARY")"
    else
      echo "ERROR: Could not determine primary from ${OLD_PRIMARY}."
    fi
  else
    echo "ERROR: Could not connect to primary ${OLD_PRIMARY}."
  fi
fi

# Try all nodes to set PRIMARY or exit
if [[ -z "$PRIMARY" ]]; then
  . /usr/local/lib/find-primary.sh
fi

if [[ "$OLD_PRIMARY" != "$PRIMARY" ]]; then
  echo "Primary changed from '$OLD_PRIMARY' to '$PRIMARY'!"
  /usr/local/bin/update-config.sh "$PRIMARY"
  pkill -HUP pgbouncer &&
  pkill -SIGUSR2 pgbouncer # RESUME
  exit 3
else
  echo "Primary unchanged (${PRIMARY})."
fi

exit 0
