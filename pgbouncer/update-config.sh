#!/bin/bash

# -------------------------------------------------------------------
# Copyright (C) 2020 by Intevation GmbH
# Author(s):
# Gernot Schulz <gernot@intevation.de>
#
# This program is distributed under the MIT license, as described
# in the LICENSE file included with the distribution.
# SPDX-License-Identifier: MIT
# -------------------------------------------------------------------

[[ $# -eq 1 ]] || {
  echo "ERROR: requires exactly 1 argument."
  exit2
}

cat << EOF | tee /etc/pgbouncer/pgbouncer.database.ini
openslides    = host=$1
mediafiledata = host=$1 pool_size=250
*             = host=$1
EOF
