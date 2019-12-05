#!/bin/bash

set -x
set -e

export PGDATA=/var/lib/postgresql/11/main
MARKER=/var/lib/postgresql/do-not-remove-this-file

update_configs() {
  sed -i \
      -e '/^#archive_mode/s/off/on/' \
      -e '/^#listen_addresses/s/localhost/*/' \
      -e '/^#listen_addresses/s/#//' \
      -e '/^#wal_log_hints/s/off/on/' \
      -e '/^#wal_log_hints/s/#//' \
      /etc/postgresql/11/main/postgresql.conf
  echo "shared_preload_libraries = 'repmgr'" \
      >> /etc/postgresql/11/main/postgresql.conf
  #
  cat /var/lib/postgresql/pg_hba.conf \
      >> /etc/postgresql/11/main/pg_hba.conf
  #
  echo "Configuring repmgr"
  sed -e "s/<NODEID>/${REPMGR_NODE_ID}/" /etc/repmgr.conf.in |
  tee /etc/repmgr.conf
}

primary_node_setup() {
  # Temporarily change port of master node during setup
  sed -i -e '/^port/s/5432/5433/' \
    /etc/postgresql/11/main/postgresql.conf
  pg_ctlcluster 11 main start
  wait-for-it localhost:5433
  createuser -s repmgr && createdb repmgr -O repmgr
  repmgr -f /etc/repmgr.conf -p 5433 primary register
  repmgr -f /etc/repmgr.conf -p 5433 cluster show

  # create OpenSlides specific user and db
  createuser -s openslides && createdb openslides -O openslides

  pg_ctlcluster 11 main stop
  sed -i -e '/^port/s/5433/5432/' \
    /etc/postgresql/11/main/postgresql.conf
}

standby_node_setup() {
  # Remove cluster data dir, so it can be cloned into
  rm -r "$PGDATA" && mkdir "$PGDATA"
  # wait for master node
  wait-for-it pgnode1:5432
  # Give the master a little more time to start up.  This isn't strictly
  # necessary but may avoid a few container restarts.
  sleep 10
  repmgr -h pgnode1 -U repmgr -d repmgr -f /etc/repmgr.conf standby clone
  pg_ctlcluster 11 main start
  wait-for-it localhost:5432
  repmgr -f /etc/repmgr.conf standby register
  repmgr -f /etc/repmgr.conf cluster show
}

if [[ ! -f "$MARKER" ]]; then
  echo "New container: creating new database cluster"
  pg_dropcluster 11 main || true
  pg_createcluster 11 main
  update_configs
  if [[ "$REPMGR_NODE_ID" -eq 1 ]]; then
    primary_node_setup
  else
    standby_node_setup
  fi
  echo "Successful repmgr setup as node id $REPMGR_NODE_ID" > "$MARKER"
fi

# Start cluster in background
pg_ctlcluster 11 main status || pg_ctlcluster 11 main start
# sudo /etc/init.d/ssh start
wait-for-it localhost:5432
# Start repmgrd in foreground
repmgrd -f /etc/repmgr.conf --pid-file /dev/shm/repmgrd.pid --daemonize=false
