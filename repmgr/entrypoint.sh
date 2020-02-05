#!/bin/bash

# Set up the postgres cluster
su postgres -c /usr/local/sbin/cluster-setup

# Create SSH privilege separation dir (needed when running /usr/sbin/sshd
# directly, see supervisor.conf)
mkdir -p /run/sshd

# By default, start supervisord in foreground
printf "INFO: Executing command: '%s'\n" "$*"
exec "$@"
