#!/bin/bash

backends="$(grep -c '^backend_hostname' /etc/pgpool2/pgpool-customized.conf)"
backends=$((backends - 1))

for i in $(seq 0 "$backends"); do
  pcp_node_info -v -h localhost -w -U postgres "$i"
  echo
done
