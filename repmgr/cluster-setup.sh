#!/bin/bash

set -e
set -o pipefail

export PGDATA=/var/lib/postgresql/11/main
MARKER=/var/lib/postgresql/do-not-remove-this-file
BACKUP_DIR="/var/lib/postgresql/backup/"

# repmgr configuration through ENV
export REPMGR_NODE_NAME="pgnode${REPMGR_NODE_ID}"
REPMGR_ENABLE_ARCHIVE="${REPMGR_WAL_ARCHIVE:-on}"
REPMGR_RECONNECT_ATTEMPTS="${REPMGR_RECONNECT_ATTEMPTS:-30}" # upstream default: 6
REPMGR_RECONNECT_INTERVAL="${REPMGR_RECONNECT_INTERVAL:-10}"

SSH_HOST_KEY="/var/lib/postgresql/.ssh/ssh_host_ed25519_key"
SSH_REPMGR_USER_KEY="/var/lib/postgresql/.ssh/id_ed25519"
SSH_PGPROXY_USER_KEY="/var/lib/postgresql/.ssh/id_ed25519_pgproxy"

SSH_CONFIG_FILES=(
  "${SSH_HOST_KEY}::{\"repmgr\"}"
  "${SSH_HOST_KEY}.pub::{\"repmgr\"}"
  "${SSH_PGPROXY_USER_KEY}:/var/lib/postgresql/.ssh/id_ed25519:{\"pgproxy\"}"
  "${SSH_PGPROXY_USER_KEY}.pub:/var/lib/postgresql/.ssh/id_ed25519.pub:{\"pgproxy\"}"
  "${SSH_REPMGR_USER_KEY}::{\"repmgr\"}"
  "${SSH_REPMGR_USER_KEY}.pub::{\"repmgr\"}"
  "/var/lib/postgresql/.ssh/authorized_keys::{\"repmgr\"}"
  "/var/lib/postgresql/.ssh/known_hosts::{\"repmgr\", \"pgproxy\"}"
)

# Source the backup() function
. /usr/local/lib/pg-basebackup.sh

primary_ssh_setup() {
  # Generate SSH keys
  local PGNODES="pgnode1,pgnode2,pgnode3" # XXX
  echo "INFO: Generating $SSH_HOST_KEY."
  ssh-keygen -t ed25519 -N '' -f "$SSH_HOST_KEY" > /dev/null
  echo "INFO: Generating $SSH_REPMGR_USER_KEY."
  ssh-keygen -t ed25519 -N '' -f "$SSH_REPMGR_USER_KEY" -C "repmgr node key" > /dev/null
  echo "INFO: Generating $SSH_PGPROXY_USER_KEY."
  ssh-keygen -t ed25519 -N '' -f "$SSH_PGPROXY_USER_KEY" \
    -C "Pgbouncer access key" > /dev/null
  # Setup access
  echo "INFO: Setting up SSH keys and config for localhost."
  cp "${SSH_REPMGR_USER_KEY}.pub" /var/lib/postgresql/.ssh/authorized_keys
  printf 'command="/usr/local/bin/current-primary" %s\n' \
    "$(cat "${SSH_PGPROXY_USER_KEY}.pub")" \
    >> /var/lib/postgresql/.ssh/authorized_keys
  printf '%s %s\n' "${PGNODES}" "$(cat "${SSH_HOST_KEY}.pub")" \
    > /var/lib/postgresql/.ssh/known_hosts
}

ssh_keys_from_db() (
  umask 077
  psql -qAt0 instancecfg <<< "
    SELECT DISTINCT ON (filename, access) filename FROM dbcfg
    WHERE 'repmgr' = ANY (access)
    ORDER BY filename, access, id DESC;" |
  while IFS= read -r -d $'\0' target_filename; do
    echo "Fetching ${target_filename} from database."
    psql -d instancecfg -qtA <<< "
      SELECT DISTINCT ON (filename, access) data FROM dbcfg
        WHERE filename = '${target_filename}'
        AND   'repmgr' = ANY (access)
        ORDER BY filename, access, id DESC;
      " | xxd -r -p > "${target_filename}"
  done
  )

insert_config_into_db() {
  local real_filename target_filename access b64
  real_filename="$1"
  target_filename="$2"
  access="$3"
  b64="$(base64 < "$real_filename")"
  psql -q -v ON_ERROR_STOP=1 -1 -d instancecfg \
    -c "INSERT INTO dbcfg (filename, data, from_host, access)
      VALUES('${target_filename}',
        decode('$b64', 'base64'),
        '$(hostname)', '${access}')"
}

hidden_pg_start() {
  # Temporarily change port of node to stay hidden from services that wait for
  # it
  sed -i -e '/^port/s/5432/5433/' \
    /etc/postgresql/11/main/postgresql.conf
  pg_ctlcluster 11 main start
  until pg_isready -q -p 5433; do
    echo "Waiting for Postgres cluster to become available."
    sleep 3
  done
}

update_pgconf() {
  psql -v ON_ERROR_STOP=1 \
    -c "ALTER SYSTEM SET listen_addresses = '*';" \
    -c "ALTER SYSTEM SET archive_mode = on;" \
    -c "ALTER SYSTEM SET archive_command = '/bin/true';" \
    -c "ALTER SYSTEM SET wal_log_hints = on;" \
    -c "ALTER SYSTEM SET wal_keep_segments = 10;" \
    -c "ALTER SYSTEM SET shared_preload_libraries = 'repmgr';" \
    -c "ALTER SYSTEM SET max_connections = 200;" \
    -c "ALTER SYSTEM SET shared_buffers = '1GB';" \
    -c "ALTER SYSTEM SET work_mem = '100MB';" \
    -c "ALTER SYSTEM SET maintenance_work_mem = '256MB';"
}

enable_wal_archiving() {
  psql -v ON_ERROR_STOP=1 \
    -c "ALTER SYSTEM SET archive_mode = 'on';" \
    -c "ALTER SYSTEM SET archive_command =
        'gzip < %p > /var/lib/postgresql/wal-archive/%f'"
}

primary_node_setup() {
  echo "INFO: Configuring cluster."
  update_pgconf
  [[ "$REPMGR_ENABLE_ARCHIVE" = "off" ]] || {
    echo "INFO: Enabling WAL archiving."
    enable_wal_archiving
  }
  pg_ctlcluster 11 main restart
  echo "INFO: Begin repmgr setup."
  createuser -s repmgr && createdb repmgr -O repmgr
  repmgr -f /etc/repmgr.conf -p 5433 primary register
  repmgr -f /etc/repmgr.conf -p 5433 cluster show

  echo "INFO: Configuring cluster for OpenSlides."
  # create OpenSlides specific user and db
  createuser openslides && createdb openslides -O openslides

  # create mediafiles database; the schema is created by the media service
  createdb -O openslides mediafiledata "OpenSlides user-provided binary files"

  # create OpenSlides settings table
  createdb instancecfg "OpenSlides instance metadata and configuration"
  psql -v ON_ERROR_STOP=1 -d instancecfg <<< "
    BEGIN;
    CREATE TABLE dbcfg (
      id INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
      filename VARCHAR NOT NULL,
      data BYTEA NOT NULL,
      created TIMESTAMP DEFAULT now(),
      from_host VARCHAR,
      access VARCHAR []);
    ALTER TABLE dbcfg ENABLE ROW LEVEL SECURITY;
    COMMENT ON TABLE dbcfg IS 'repmgr node configuration files';
    CREATE ROLE pgproxy WITH LOGIN;
    GRANT SELECT ON dbcfg TO pgproxy;
    CREATE POLICY dbcfg_read_policy
      ON dbcfg USING (CURRENT_USER = ANY (access) OR access = '{\"public\"}');
    --
    COMMIT;
    "

  # Insert SSH files
  echo "INFO: Begin inserting config files into database."
  for i in "${SSH_CONFIG_FILES[@]}"; do
    IFS=: read -r item target_filename access <<< "$i"
    [[ -n "$target_filename" ]] || target_filename="$item"
    echo "INFO: Inserting ${item}→${target_filename}."
    insert_config_into_db "$item" "$target_filename" "$access"
  done

  # delete pgproxy key
  rm -f "${SSH_PGPROXY_USER_KEY}" "${SSH_PGPROXY_USER_KEY}.pub"
}

standby_node_setup() {
  # Remove cluster data dir, so it can be cloned into
  rm -r "$PGDATA" && mkdir "$PGDATA"
  # Wait for master node
  local max n
  max=10
  n=0
  until pg_isready -q -h "$REPMGR_PRIMARY"; do
    n=$(( n+1 ))
    echo "Waiting for Postgres master server to become available ($n/$max)."
    sleep 3
    [[ $n -lt $max ]] || {
      echo "ERROR: Could not connect to primary node after $max attempts.  Exiting."
      exit 5
    }
  done
  repmgr -h "$REPMGR_PRIMARY" -U repmgr -d repmgr \
    -f /etc/repmgr.conf standby clone --fast-checkpoint
  pg_ctlcluster 11 main start
  until pg_isready; do
    echo "Waiting for Postgres cluster to become available."
    sleep 3
  done
  pg_ctlcluster 11 main restart
  repmgr -f /etc/repmgr.conf standby register --force
  repmgr -f /etc/repmgr.conf cluster show || true
}

mkdir -p "/var/lib/postgresql/wal-archive/"

echo "INFO: Begin cluster setup"
echo "INFO: Configuring repmgr (/etc/repmgr.conf)."
REPMGR_SERVICE_START_COMMAND='/usr/bin/pg_ctlcluster 11 main start' \
  envsubst < /etc/repmgr.conf.in > /etc/repmgr.conf

# Update pg_hba.conf from image template
echo "INFO: Creating Postgres cluster's pg_hba.conf."
cp -fv /var/lib/postgresql/pg_hba.conf /etc/postgresql/11/main/pg_hba.conf

# Check if another primary exists anyway
CURRENT_PRIMARY=
if pg_isready -q -h pgbouncer; then
  echo "INFO: pgbouncer is already accepting connections."
  # Use "hosts" column from pgbouncer output
  CURRENT_PRIMARY="$(psql -qAt -h pgbouncer pgbouncer <<< "show databases;" |
    awk -F"|" '$1 == "openslides" { print $2 }')"
  echo "INFO: According to pgbouncer, the current primary is $CURRENT_PRIMARY."
fi

# Current primary node unknown (possibly cold instance start)
if [[ -z "$CURRENT_PRIMARY" ]]; then
  echo "INFO: The current primary node is unknown."
  if [[ -f "$MARKER" ]]; then
    echo "INFO: This cluster has been set up already."
    echo "INFO: Assuming node configuration is correct.  Starting up."
    hidden_pg_start
    ssh_keys_from_db
  elif [[ -z "$REPMGR_PRIMARY" ]]; then
    echo "INFO: Configuring cluster as primary node according to configuration."
    primary_ssh_setup
    hidden_pg_start
    primary_node_setup
    # Create an initial basebackup
    echo "Creating base backup in ${BACKUP_DIR}."
    backup "Initial base backup (entrypoint)"
    echo "INFO: Successful repmgr setup as node id $REPMGR_NODE_ID" | tee "$MARKER"
  else
    echo "INFO: Configuring cluster as standby node according to configuration."
    standby_node_setup
    ssh_keys_from_db
    echo "Successful repmgr setup as node id $REPMGR_NODE_ID" | tee "$MARKER"
  fi
# This node has been set up and is a primary according to pgbouncer
elif [[ -f "$MARKER" ]] && [[ "$CURRENT_PRIMARY" = "$REPMGR_NODE_NAME" ]]; then
  echo "INFO: This node is a primary according to pgbouncer.  Starting up."
  hidden_pg_start
  ssh_keys_from_db
# This node has been set up but it is not a primary according to pgbouncer
elif [[ -f "$MARKER" ]] && [[ "$CURRENT_PRIMARY" != "$REPMGR_NODE_NAME" ]]; then
  # Query primary about this node's role
  echo "INFO: Checking repmgr cluster status on $CURRENT_PRIMARY."
  # Node type registered in primary's repmgr database
  REG_NODE_TYPE="$(psql -qAt -U repmgr -d repmgr -h "$CURRENT_PRIMARY" \
      -v this_node="$REPMGR_NODE_NAME" \
      <<< "SELECT type FROM repmgr.nodes WHERE node_name = :'this_node';"
  )" || true
  echo "INFO: $CURRENT_PRIMARY tracks $REPMGR_NODE_NAME as a $REG_NODE_TYPE."
  # Self-perception
  # Start cluster for the following query and to ensure that is has been shut
  # down cleanly before attempting pg_rewind
  echo "INFO: Temporarily starting cluster."
  hidden_pg_start
  SELF_NODE_TYPE="$(psql -p 5433 -qAt -U repmgr -d repmgr -h "$REPMGR_NODE_NAME" \
      -v this_node="$REPMGR_NODE_NAME" \
      <<< "SELECT type FROM repmgr.nodes WHERE node_name = :'this_node';"
  )"
  echo "INFO: $REPMGR_NODE_NAME's local database lists itself as $SELF_NODE_TYPE."
  if [[ "$REG_NODE_TYPE" = primary ]] || [[ "$SELF_NODE_TYPE" = 'primary' ]]; then
    # We apparently were a primary before and should become a standby
    echo "WARN: This node ($REPMGR_NODE_NAME) has been set up as a primary node" \
      "but another primary node ($CURRENT_PRIMARY) exists!"
    echo "INFO: Creating base backup prior to rewind in ${BACKUP_DIR}."
    backup "Base backup prior to repmgr node rejoin"
    # Stop cluster (cleanly)
    sed -i -e '/^port/s/5433/5432/' /etc/postgresql/11/main/postgresql.conf
    pg_ctlcluster 11 main stop
    # Rejoin
    echo "INFO: Rejoining as standby."
    repmgr -d "host='$CURRENT_PRIMARY' dbname=repmgr user=repmgr" \
      node rejoin --force-rewind --verbose
  else
    # Regular standby startup
    echo "INFO: This node has been set up as a standby before.  Starting up."
    ssh_keys_from_db
  fi
# There is a primary node for which this node should be come a standby
else
  echo "INFO: This is a new cluster.  Joining as standby for existing $CURRENT_PRIMARY."
  REPMGR_PRIMARY="$CURRENT_PRIMARY"
  standby_node_setup
  ssh_keys_from_db
  echo "Successful repmgr setup as node id $REPMGR_NODE_ID" | tee "$MARKER"
fi

echo "INFO: Setup finished.  Reverting temporary config changes."
# Revert Postgres port in case it was temporarily changed above
sed -i -e '/^port/s/5433/5432/' /etc/postgresql/11/main/postgresql.conf
# Change repmgr's Postgres start to supervisorctl, so Postgres will be
# recognized as running by supervisord in case of future failovers.
REPMGR_SERVICE_START_COMMAND='supervisorctl start postgres' \
  envsubst < /etc/repmgr.conf.in > /etc/repmgr.conf
# Stop cluster, so it can be started by supervisord
echo "INFO: Stopping cluster, so it can be started by supervisord."
pg_ctlcluster 11 main stop || true
