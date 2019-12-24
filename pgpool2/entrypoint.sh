#!/bin/bash

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

  # Failover/failback settings
  sed -i '
    /^failover_on_backend_error/s/\<on\>/off/;
    /^search_primary_node_timeout/s/300/0/;
  ' "$CONFIG"

  # Delete settings that will be appended below
  sed -i '
    /pid_file_name/d;
    /^socket_dir/d;
    /^pcp_socket_dir/d;
    /^sr_check_/d;
    /^health_check_/d;
    /^backend_/d;
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

health_check_period = 20
health_check_max_retries = 10
health_check_user = 'repmgr'
health_check_password = 'repmgr'
health_check_database = 'repmgr'
health_check_max_retries = 10
health_check_retry_delay = 10

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

  # Wait for the main Postgres node.
  until pg_isready -h pgnode1; do
    echo "Waiting for Postgres master server to become available..."
    sleep 15
  done
fi

exec pgpool -f "$CONFIG" -n
