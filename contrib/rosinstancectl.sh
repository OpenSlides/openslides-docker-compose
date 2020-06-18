#!/bin/bash

# Wrapper script for clustershell to execute osinstancectl on multiple servers.
#
# The config file must contain one hostname per line, e.g.,
# root@openslides.example.com

DEFAULT_CONF="${HOME}/.config/openslides/servers.conf"
CONF="${CONF:-"$DEFAULT_CONF"}"
JQ=jq
JSON=

fatal() {
    echo 1>&2 "ERROR: $*"
    exit 23
}

usage() {
  cat << EOF
Usage: ${BASH_SOURCE[0]} [options] -- <command>

Options:
  -c, --config  Config file (default: $DEFAULT_CONF)
  -j, --json    JSON output
EOF
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
      " assuming 'swarm'"
    REMOTE_COMMAND=osstackctl
    ;;
esac

shortopt="hc:j"
longopt="help,config:,json"
ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS"
# Parse options
while true; do
  case "$1" in
    -c | --config)
      CONF="$2"
      [[ -r "$CONF" ]] || exit 2
      shift 2
      ;;
    -j | --json) JSON=1; shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

[[ -f "$CONF" ]] || fatal "No configuration file found"
readarray a < "$CONF"
printf -v nodes ",%s" ${a[@]}

[[ -n "$nodes" ]] || fatal "Nodes list is empty"
[[ -t 1 ]] || {
  REMOTE_COMMAND="$REMOTE_COMMAND --color=never"
  JQ="$JQ --monochrome-output"
}

# Test if --json output was requested
#
if [[ "$JSON" ]]; then
    out="$(clush -o "-ttq -o BatchMode=yes" -qS -b -w "${nodes:1}" \
            "$REMOTE_COMMAND" "$@" --json --color=never |
        # Filter out clush headers (we do not use the -L/-N options to prevent
        # clush from aggregating the output)
        awk '/^-{15}$/ {h++; next;} h == 1 {next;} h == 2 {h=0;} 1')"
    len="$(jq '. | length' <<< "$out")"
    # Compare string because jq may return, e.g., '1 1'.  There is probably
    # a better way to use jq.
    if [[ "$len" = 1 ]]; then
      $JQ '.' <<< "$out" # simply print
    else
      # merge records from different sources
      $JQ -s '{ instances: map(.instances[0]) }' <<< "$out"
    fi
else
    exec clush -o "-ttq -o BatchMode=yes" -qS -b -w "${nodes:1}" \
      "$REMOTE_COMMAND" "$@"
fi
