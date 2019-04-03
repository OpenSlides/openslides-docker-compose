#!/bin/bash

# Wrapper script for clustershell to execute osinstancectl on multiple servers.
#
# The config file must contain one hostname per line, e.g.,
# root@openslides.example.com

CONF="${HOME}/.config/openslides/servers.conf"

[[ -f "$CONF" ]] || exit 2
readarray a < "$CONF"
printf -v nodes ",%s" ${a[@]}

[[ -n "$nodes" ]] || exit 3
exec clush -o "-ttq -o BatchMode=yes" -b -w "${nodes:1}" osinstancectl $*
