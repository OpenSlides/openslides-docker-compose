#!/bin/bash

# Wrapper script for clustershell to execute osinstancectl on multiple servers.
#
# The config file must contain one hostname per line, e.g.,
# root@openslides.example.com

fatal() {
    echo 1>&2 "ERROR: $*"
    exit 23
}

CONF="${HOME}/.config/openslides/servers.conf"

[[ -f "$CONF" ]] || fatal "No configuration file found"
readarray a < "$CONF"
printf -v nodes ",%s" ${a[@]}

[[ -n "$nodes" ]] || fatal "Nodes list is empty"
exec clush -o "-ttq -o BatchMode=yes" -b -w "${nodes:1}" osinstancectl $*
