#!/bin/bash

# This script is a simple way to keep local OpenSlides instances up to date
# with remote instances.  The purpose of this is to maintain backup instances
# to switch over to in case of problems on the remote.
#
# The synchronization process is very simple (ssh + rsync) and requires a cron
# setup.  The database is "synchronized" using SQL dumps; there is no streaming
# etc.  The synchronizing server needs to have SSH access to the main server.
#
# The local instances' states should be left up to this script as it has to
# drop and recreate the openslides table.
#
# In order to access synchronized local instances, e.g., in order to verify
# that the synchronization is working, do not start it.  Create and start
# a clone instead.

set -e
set -o pipefail

BASEDIR="/srv/openslides/docker-instances"
FROM="$1"
TO="$2"

[[ -n "$FROM" ]] || exit 23
[[ -n "$TO" ]] || exit 23

REMOTE="$(host "$FROM" |
  awk '/has address/ { print $4; exit; }
       /has IPv6 address/ { print $5; exit }'
)"

[[ -n "$REMOTE" ]] || exit 23

# check if remote is really (still) remote.  This may change
# in case of failover IPs.
ip address show | awk -v ip="$REMOTE" -v from="$FROM" '
  $1 ~ /^inet/ && $2 ~ ip {
    printf("ERROR: %s (%s) routes to this host.\n", from, ip)
    exit 3
  }'

FROM="${BASEDIR}/${FROM}/"
TO="${BASEDIR}/${TO}/"

cd "${TO}/"

# link volume in locally, once
if [[ ! -h personal_data ]]; then
  dir=$(
    docker inspect --format \
      "{{ range .Mounts }}{{ if eq .Destination \"/app/personal_data\" }}{{ .Source }}{{ end }}{{ end }}" \
      "$(docker-compose ps -q server)"
    )
  echo "Linking personal_data in $PWD."
  ln -s "$dir" personal_data
fi

# remote: setup and dump
ssh -T "${REMOTE}" << EOF
cd "${FROM}/"

# dump DB
docker exec -u postgres "\$(docker-compose ps -q postgres)" \
  /bin/bash -c "pg_dump openslides" > latest.sql

# link personal_data
if [[ ! -h personal_data ]]; then
  dir=\$(
    docker inspect --format \
      "{{ range .Mounts }}{{ if eq .Destination \"/app/personal_data\" }}{{ .Source }}{{ end }}{{ end }}" \
      "\$(docker-compose ps -q server)"
    )
  echo "Linking personal_data in \$PWD."
  ln -s "\$dir" personal_data
fi
EOF

# instance sync
rsync -ax --del \
  --exclude=settings.py \
  --exclude=personal_data \
  --exclude=metadata.txt \
  --exclude="*.swp" \
  "${REMOTE}:${FROM}/" ./

# personal_data sync (separate so we can use -x both times)
docker-compose up --no-start # Make sure volumes exist
rsync -ax "${REMOTE}:${FROM}/personal_data/" ./personal_data/

# import DB
docker-compose stop server prioserver client
docker-compose up -d --no-deps postgres
sleep 10 # :(
docker exec -i -u postgres "$(docker-compose ps -q postgres)" \
  bash -c "dropdb openslides; createdb openslides"
docker exec -i -u postgres "$(docker-compose ps -q postgres)" \
  psql -U openslides openslides < latest.sql
