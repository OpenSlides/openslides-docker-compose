#!/bin/bash

# Check repmgr cluster status on all OpenSlides database nodes.

while read -r id name; do
  report="$(docker exec -u postgres "$id" repmgr cluster show)"
  [[ $? -eq 0 ]] || {
    printf "ERROR on %s! %s (%s) reports:\n" "$(hostname)" "$name" "$id"
    printf "\n%s\n\n" "$report"
  }
done < <(docker ps \
  --filter label=org.openslides.role=postgres \
  --format '{{.ID}}\t{{.Names}}' | sort -k2)
