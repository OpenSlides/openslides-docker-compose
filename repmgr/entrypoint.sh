#!/bin/bash

# -------------------------------------------------------------------
# Copyright (C) 2019 by Intevation GmbH
# Author(s):
# Gernot Schulz <gernot@intevation.de>
#
# This program is distributed under the MIT license, as described
# in the LICENSE file included with the distribution.
# SPDX-License-Identifier: MIT
# -------------------------------------------------------------------

set -e

[[ -n "${REPMGR_NODE_ID}" ]] || {
  echo "ERROR: REPMGR_NODE_ID not set.  Cannot continue."
  sleep 10
  exit 2
}

# Set up the postgres cluster
su postgres -c /usr/local/sbin/cluster-setup

# Create SSH privilege separation dir (needed when running /usr/sbin/sshd
# directly, see supervisor.conf)
mkdir -p /run/sshd

# By default, start supervisord in foreground
printf "INFO: Executing command: '%s'\n" "$*"
exec "$@"
