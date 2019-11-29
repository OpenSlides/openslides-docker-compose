#!/bin/bash

set -x

ORIG_CONFIG="/etc/pgpool2/pgpool.conf"
CONFIG="/etc/pgpool2/pgpool-customized.conf"

setup() {
  sed '
    /^listen_addresses/s/localhost/*/;
    /^master_slave_mode/s/off/on/;
    /^load_balance_mode/s/off/on/;
    /^log_hostname/s/off/on/;
    /^log_standby_delay/s/none/if_over_threshold/;
  ' "$ORIG_CONFIG" > "$CONFIG"

  # Delete settings that will be appended below
  sed -i '
    /pid_file_name/d;
    /^sr_check_/d;
    /^backend_/d;
    /^socket_dir/d;
    /^pcp_socket_dir/d;
  ' "$CONFIG"

cat >> "$CONFIG" << EOF
# Make sure these files do not survive a container restart
pid_file_name = '/dev/shm/pgpool.pid'
socket_dir = '/dev/shm/'
pcp_socket_dir = '/dev/shm/'

sr_check_period = 0
sr_check_user = 'repmgr'
sr_check_password = 'repmgr'
sr_check_database = 'repmgr'

EOF

  IFS="," read -ra node_list <<< "$PG_NODE_LIST"
  for n in ${node_list[@]}; do
    IFS=":" read -ra nodes <<< "$n"
    node_name="${nodes[0]}"
    backend_id="${nodes[1]}"
    echo "Adding backend configuration for ${node_name}..."
    cat >> "$CONFIG" << EOF
backend_hostname${backend_id} = '${node_name}'
backend_port${backend_id} = 5432
backend_weight${backend_id} = ${backend_id}
backend_data_directory${backend_id} = '/var/lib/postgresql/11/main'
backend_flag${backend_id} = 'ALLOW_TO_FAILOVER'

EOF
  done

  # PCP access
  echo "postgres:e8a48653851e28c69d0506508fb27fc5" >> /etc/pgpool2/pcp.conf
  echo "*:*:postgres:postgres" > /root/.pcppass
  chmod 600 /root/.pcppass

  # link socket to default location for convenience
  ln -s /dev/shm/.s.PGSQL.5432 /var/run/postgresql/.s.PGSQL.5432
}

if [[ ! -f "$CONFIG" ]]; then
  setup

  # Sleep to give Postgres services a chance to start.
  # The standby services may take significantly longer but hopefully it is enough
  # time for the master to get ready.  Obviously, we do not want to use
  # wait-for-it in this case.
  echo "Sleeping 15 seconds..."
  sleep 15
fi

exec pgpool -f "$CONFIG" -n
