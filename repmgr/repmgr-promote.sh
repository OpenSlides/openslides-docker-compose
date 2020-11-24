#!/bin/bash

# This script is called as repmgr's promote_command which is configured in
# /etc/repmgr.conf.
#
# -------------------------------------------------------------------
# Copyright (C) 2020 by Intevation GmbH
# Author(s):
# Gernot Schulz <gernot@intevation.de>
#
# This program is distributed under the MIT license, as described
# in the LICENSE file included with the distribution.
# SPDX-License-Identifier: MIT
# -------------------------------------------------------------------

BACKUP_DIR="/var/lib/postgresql/backup/"

# Source the backup() function
. /usr/local/lib/pg-basebackup.sh

# Promote node from standby to primary
/usr/bin/repmgr standby promote -f /etc/repmgr.conf &&
  { backup "Base backup after standby promotion" || true; }
