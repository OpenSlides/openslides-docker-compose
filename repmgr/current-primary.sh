#!/bin/bash

# Determine and print out the current primary node

PRIMARY=

error() {
  printf "ERROR: %s\n" "$*" 1>&2
}

# Print primary if it is unquestionable
repmgr cluster show > /dev/null && {
  PRIMARY=$(repmgr cluster show --csv |
    awk -F, '$3 == 0 { printf("pgnode%d\n", $1) }'
    )
  printf "PRIMARY: %s\n" "$PRIMARY"
  exit 0
}

THIS_NODE=$(repmgr node status --csv | tr -d '"' |
    awk -F, '
    $1 == "Node name" { name = $2 }
    $1 == "Node ID" { id = $2 }
    END { printf("%s (%d)\n", name, id) }
    ')

# repmgr cluster show indicated a problem
NUMBER_OF_PRIMARIES=$(repmgr cluster show --csv | cut -d, -f3 | grep -c 0)
if [[ $NUMBER_OF_PRIMARIES -eq 1 ]]; then
  error "Cluster is degraded but a primary node is available"
  PRIMARY=$(repmgr cluster show --csv |
    awk -F, '$3 == 0 { printf("pgnode%d\n", $1) }'
    )
  printf "PRIMARY: %s\n" "$PRIMARY"
  exit 0
elif [[ $NUMBER_OF_PRIMARIES -ge 2 ]]; then
  error "Multiple primaries in cluster!  Trying to determine the correct primary..."
  THIS_NODE_ROLE=$(repmgr node status --csv | tr -d '"' |
    awk -F, '$1 == "Role" { print $2 }')
  if [[ "$THIS_NODE_ROLE" = "primary" ]]; then
    error "Node ${THIS_NODE} claims to be a primary" \
      "and can not be trusted.  Aborting..."
    exit 3
  elif [[ "$THIS_NODE_ROLE" = "standby" ]]; then
    echo "INFO: Node ${THIS_NODE} is a standby. " \
      "Trusting that it is following the correct primary." 1>&2
    # Node self-check
    repmgr node check > /dev/null || {
      error "Node self-check failed!"
      exit 25
    }
    PRIMARY=$(repmgr node status --csv | tr -d '"' |
      awk -F, '$1 == "Upstream node" { split($2, a, / /); print a[1] }'
    )
    printf "PRIMARY: %s\n" "$PRIMARY"
  else
    error "Cannot determine node role."
    exit 4
  fi
else
  error "No primary nodes available in cluster." \
    "The cluster may be in the process of promoting a new primary."
  exit 5
fi

# vim: ft=sh sw=2 et:
