#!/bin/bash

# Wrapper script for clustershell to execute osinstancectl on multiple servers.
#
# The config file must contain one hostname per line, e.g.,
# root@openslides.example.com

fatal() {
    echo 1>&2 "ERROR: $*"
    exit 23
}

# Decide mode from invocation
case "$(basename "${BASH_SOURCE[0]}")" in
  "rosinstancectl.sh")
    REMOTE_COMMAND=osinstancectl
    ;;
  "rosstackctl.sh")
    REMOTE_COMMAND=osstackctl
    ;;
  *)
    echo "WARNING: could not determine desired deployment mode;" \
      " assuming 'compose'"
    REMOTE_COMMAND=osinstancectl
    ;;
esac

CONF="${HOME}/.config/openslides/servers.conf"

[[ -f "$CONF" ]] || fatal "No configuration file found"
readarray a < "$CONF"
printf -v nodes ",%s" ${a[@]}

[[ -n "$nodes" ]] || fatal "Nodes list is empty"

# Test if --json output was requested
#
# XXX: This will fail CLI options such as "-nj" instead of "-n -j".  To fix
# this, getopt should be used here as well.
if grep -qwE -- "(--json|-j)" <<< "$*"; then
    out="$(clush -o "-ttq -o BatchMode=yes" -qS -b -w "${nodes:1}" \
            "$REMOTE_COMMAND" "$@" --color=never |
        # Filter out clush headers (we do not use the -L/-N options to prevent
        # clush from aggregating the output)
        awk '/^-{15}$/ {h++; next;} h == 1 {next;} h == 2 {h=0;} 1')"
    len="$(jq '. | length' <<< "$out")"
    # Compare string because jq may return, e.g., '1 1'.  There is probably
    # a better way to use jq.
    if [[ "$len" = '1' ]]; then
      jq <<< "$out" # simply print
    else
      # merge records from different sources
      jq -s '{ instances: map(.instances[0]) }' <<< "$out"
    fi
else
    exec clush -o "-ttq -o BatchMode=yes" -qS -b -w "${nodes:1}" "$REMOTE_COMMAND" "$@"
fi
