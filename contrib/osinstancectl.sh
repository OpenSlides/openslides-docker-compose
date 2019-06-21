#!/bin/bash

# Set up a new OpenSlides docker-compose instance
#
# This script makes some assumptions and would need more options to become more
# flexible

set -eu
set -o noclobber

# Defaults (override in /etc/osinstancectl)
TEMPLATE_REPO="/srv/openslides/openslides-docker-compose"
# TEMPLATE_REPO="https://github.com/OpenSlides/openslides-docker-compose"
OSDIR="/srv/openslides"
INSTANCES="${OSDIR}/docker-instances"
DEFAULT_DOCKER_IMAGE_NAME_OPENSLIDES=openslides-server
DEFAULT_DOCKER_IMAGE_TAG_OPENSLIDES=latest
# If set, these variables override the defaults in the
# docker-compose.yml.example template file.  They can be configured on the
# command line as well as in /etc/osinstancectl.
RELAYHOST=

ME=$(basename -s .sh "${BASH_SOURCE[0]}")
CONFIG="/etc/osinstancectl"
MARKER=".osinstancectl-marker"
DOCKER_IMAGE_NAME_OPENSLIDES=
DOCKER_IMAGE_TAG_OPENSLIDES=
NGINX_TEMPLATE=
PROJECT_NAME=
PROJECT_DIR=
PORT=
MODE=
OPT_LONGLIST=
OPT_METADATA=
OPT_IMAGE_INFO=
OPT_ADD_ACCOUNT=1
OPT_LOCALONLY=
OPT_FORCE=
OPT_WWW=
FILTER=
CLONE_FROM=
ADMIN_SECRETS_FILE="adminsecret.env"
USER_SECRETS_FILE="usersecret.env"
OPENSLIDES_USER_FIRSTNAME=
OPENSLIDES_USER_LASTNAME=

# Color and formatting settings
OPT_COLOR=auto
NCOLORS=
COL_NORMAL=""
COL_RED=""
COL_YELLOW=""
COL_GREEN=""
BULLET='●'
SYM_NORMAL="OK"
SYM_ERROR="XX"
SYM_UNKNOWN="??"

enable_color() {
  NCOLORS=$(tput colors) # no. of colors
  if [[ -n "$NCOLORS" ]] && [[ "$NCOLORS" -ge 8 ]]; then
    COL_NORMAL="$(tput sgr0)"
    COL_RED="$(tput setaf 1)"
    COL_YELLOW="$(tput setaf 3)"
    COL_GREEN="$(tput setaf 2)"
  fi
}

usage() {
cat <<EOF
Usage: ${BASH_SOURCE[0]} [options] <action> <instance>

Manage docker-compose-based OpenSlides instances.

Actions:
  ls                   List instances and their status.  <instance> is
                       a grep ERE search pattern in this case.
  add                  Add a new instance for the given domain (requires FQDN)
  rm                   Remove <instance> (requires FQDN)
  start                Start an existing instance
  stop                 Stop a running instance
  update               Update OpenSlides to a new --image
  erase                Remove an instance's volumes (stops the instance if
                       necessary)
  flush                Flush Redis cache

Options:
  -d, --project-dir    Directly specify the project directory
  --force              Disable various safety checks
  --color=WHEN         Enable/disable color output.  WHEN is never, always, or
                       auto.

  for ls:
    -l, --long         Include more information in extended listing format
    -m, --metadata     Include metadata in instance list
    -n, --online       Show only online instances
    -f, --offline      Show only offline instances
    -i, --image-info   Show image version info (requires instance to be started)

  for add & update:
    -I, --image        Specify the OpenSlides server Docker image
    -t, --tag          Specify the OpenSlides server Docker image
    --no-add-account   Do not add an additional, customized local admin account
    --local-only       Create an instance without setting up Nginx and Let's
                       Encrypt certificates.  Such an instance is only
                       accessible on localhost, e.g., http://127.1:61000.
    --clone-from       Create the new instance based on the specified existing
                       instance
    --www              Add a www subdomain in addition to the specified
                       instance domain
    --mailserver       Mail server to configure as Postfix's smarthost (default
                       is the host system)

Meaning of colored status indicators in ls mode:
  green              The instance appears to be fully functional
  red                The instance is unreachable, probably stopped
  yellow             The instance is started but a websocket connection cannot
                     be established.  This usually means that the instance is
                     starting or, if the status persists, that something is
                     wrong.  Check the docker-compose logs in this case.
EOF
}

fatal() {
    echo 1>&2 "${COL_RED}ERROR${COL_NORMAL}: $*"
    exit 23
}

check_for_dependency () {
    [[ -n "$1" ]] || return 0
    which "$1" > /dev/null || { fatal "Dependency not found: $1"; }
}


arg_check() {
  [[ -d "$OSDIR" ]] || { fatal "$OSDIR not found!"; }
  [[ -n "$PROJECT_NAME" ]] || {
    fatal "Please specify a project name"; return 2;
  }
  if [[ "$MODE" = "clone" ]]; then
    [[ -d "$CLONE_FROM_DIR" ]] || {
      fatal "$CLONE_FROM_DIR does not exist."
      return 2
    }
  fi
}

marker_check() {
  [[ -f "${PROJECT_DIR}/${MARKER}" ]] || {
    fatal "This instance was not created with $ME." \
      "Refusing to delete unless --force is given."
  }
}

_docker_compose () {
  # This basically implements the missing docker-compose -C
  local project_dir="$1"
  shift
  docker-compose --project-directory "$project_dir" \
    --file "${project_dir}/docker-compose.yml" $*
}

query_user_account_name() {
  if [[ -n "$OPT_ADD_ACCOUNT" ]]; then
    echo "Create local admin account for:"
    while [[ -z "$OPENSLIDES_USER_FIRSTNAME" ]] || \
          [[ -z "$OPENSLIDES_USER_LASTNAME" ]]
    do
      read -p "First & last name: " \
        OPENSLIDES_USER_FIRSTNAME OPENSLIDES_USER_LASTNAME
    done
  fi
}

verify_domain() {
  # Verify provided domain
  HOSTNAME=$(hostname -f)
  IP=$(host "$HOSTNAME" | awk '/has address/ { print $4; exit; } /has IPv6 address/ { print $5}')
  host "$PROJECT_NAME" | grep -q "$IP" || {
    fatal "$PROJECT_NAME does not point to this host?"
    return 3
  }
}


next_free_port() {
  # Select new port
  #
  # `docker-compose port client 80` would be a nicer way to get the port
  # mapping; however, it is only available for running services.
  local HIGHEST_PORT_IN_USE=$(
    find "${INSTANCES}" -type f -name docker-compose.yml -print0 |
    xargs -0 grep -h -o "127.0.0.1:61[0-9]\{3\}:80"|
    cut -d: -f2 | sort -rn | head -1
  )
  [[ -n "$HIGHEST_PORT_IN_USE" ]] || HIGHEST_PORT_IN_USE=61000
  local PORT=$((HIGHEST_PORT_IN_USE + 1))

  # Check if port is actually free
  #  try to find the next free port (this situation can occur if there are test
  #  instances outside of the regular instances directory)
  n=0
  while ! ss -tnHl | awk -v port="$PORT" '$4 ~ port { exit 2 }'; do
    [[ $n -lt 5 ]] || { fatal "Could not find free port"; }
    ((PORT+=1))
    ((n+=1))
  done
  echo "$PORT"
}

create_config_from_template() {
  local templ="$1"
  local config="$2"
  gawk -v port="${PORT}" -v image="$DOCKER_IMAGE_NAME_OPENSLIDES" \
      -v tag="$DOCKER_IMAGE_TAG_OPENSLIDES" '
    BEGIN {FS=":"; OFS=FS}
    $0 ~ /^  (prio)?server:$/ {s=1}
    image != "" && $1 ~ /image/ && s { $2 = " " image; $3 = tag; s=0 }
    NF==3 && $1 ~ /127\.0\.0\.1/ && $3 ~ /80"$/ { $2 = port }
    1
    ' "$templ" |
  gawk -v proj="$PROJECT_NAME" -v relay="$RELAYHOST" '
    BEGIN {FS="="; OFS=FS}
    $1 ~ /MYHOSTNAME$/ { $2 = proj }
    relay != "" && $1 ~ /RELAYHOST$/ { $2 = relay }
    1
  ' > "$config"
}

create_instance_dir() {
  # Update yaml
  git clone "${TEMPLATE_REPO}" "${PROJECT_DIR}"
  # prepare secrets files
  [[ -d "${PROJECT_DIR}/secrets" ]] ||
    mkdir -m 700 "${PROJECT_DIR}/secrets"
  touch "${PROJECT_DIR}/secrets/${ADMIN_SECRETS_FILE}"
  touch "${PROJECT_DIR}/${MARKER}"
}

gen_pw() {
  read -r -n 15 PW < <(LC_ALL=C tr -dc "[:alnum:]" < /dev/urandom)
  echo "$PW"
}

create_admin_secrets_file() {
  echo "Generating admin password..."
  [[ -d "${PROJECT_DIR}/secrets" ]] ||
    mkdir -m 700 "${PROJECT_DIR}/secrets"
  printf "OPENSLIDES_ADMIN_PASSWORD=%s\n" "$(gen_pw)" \
    >> "${PROJECT_DIR}/secrets/${ADMIN_SECRETS_FILE}"
}

create_user_secrets_file() {
  if [[ -n "$OPT_ADD_ACCOUNT" ]]; then
    echo "Generating user credentials..."
    [[ -d "${PROJECT_DIR}/secrets" ]] ||
      mkdir -m 700 "${PROJECT_DIR}/secrets"
    local first_name="$1"
    local last_name="$2"
    local PW="$(gen_pw)"
    cat << EOF > "${PROJECT_DIR}/secrets/${USER_SECRETS_FILE}"
OPENSLIDES_USER_FIRSTNAME=$first_name
OPENSLIDES_USER_LASTNAME=$last_name
OPENSLIDES_USER_PASSWORD=$PW
EOF
  fi
}

update_nginx_config() {
  # Create Nginx configs
  [[ -z "$OPT_LOCALONLY" ]] || return 0

  # add optional www subdomain
  local www=
  [[ -z "$OPT_WWW" ]] || www="www.${PROJECT_NAME}"

  # First, without TLS
  sed -e "/server_name/s/<INSTANCE>/${PROJECT_NAME} ${www}/" \
      -e "s/<INSTANCE>/${PROJECT_NAME}/" \
      -e "/proxy_pass/s/61000/${PORT}/" \
      "$NGINX_TEMPLATE" > /etc/nginx/sites-available/"${PROJECT_NAME}".conf
  ln -s ../sites-available/"${PROJECT_NAME}".conf /etc/nginx/sites-enabled/ || true
  systemctl reload nginx

  # Generate Let's Encrypt certificate
  echo "Generating certificate..."
  if [[ -z "$OPT_WWW" ]]; then
    acmetool want "${PROJECT_NAME}"
  else
    acmetool want "${PROJECT_NAME}" "${www}"
  fi

  # Update Nginx to use TLS certs
  ex -s +"g/ssl-cert-snakeoil/d" +"g/ssl_certificate/s/#\ //" +x \
    /etc/nginx/sites-available/"${PROJECT_NAME}".conf
  systemctl reload nginx
}

link_settingspy() {
  # Create a symlink in the project directory to the settings file in Docker
  # volume (usually in /var/lib/docker/volumes/...)
  echo "Symlinking settings.py"
  local settings="$(get_personaldata_dir "$PROJECT_DIR")/var/settings.py"
  if [[ -f "$settings" ]]; then
    ln -s "$settings" "${PROJECT_DIR}/settings.py"
  else
    echo "INFO: Not symlinking because the volume does not exist yet."
  fi
}

remove() {
  local PROJECT_NAME="$1"
  [[ -d "$PROJECT_DIR" ]] || {
    fatal "$PROJECT_DIR does not exist."
  }
  # Ask for confirmation
  local ANS=
  echo "Delete the following instance including all its data and configuration?"
  echo "  $PROJECT_DIR"
  read -p "Really delete? (uppercase YES to confirm) " ANS
  [[ "$ANS" = "YES" ]] || return 0

  echo "Stopping and removing containers..."
  instance_erase
  echo "Removing instance repo dir..."
  rm -rf "${PROJECT_DIR}"
  echo "Remove config from Nginx..."
  rm -f /etc/nginx/sites-available/"${PROJECT_NAME}".conf \
     /etc/nginx/sites-enabled/"${PROJECT_NAME}".conf
  systemctl reload nginx
  echo "acmetool unwant..."
  acmetool unwant "$PROJECT_NAME"
  echo "Done."
}

local_port() {
  [[ -f "${1}/docker-compose.yml" ]] &&
  gawk 'BEGIN { FS=":" }
    $0 ~ / +ports:$/ { s = 1; next; }
    s == 1 && NF == 2 {
      gsub(/[\ "-]/, "")
      # split($2, a, /\//) # 80/tcp
      print $1
      exit
    }
    s == 1 && NF == 3 {
      gsub(/"/, "", "g")
      # split($3, a, /\//) # 80/tcp
      print $2
      exit
    }' "${instance}/docker-compose.yml"
  # better but slower:
  # docker inspect --format '{{ (index (index .NetworkSettings.Ports "80/tcp") 0).HostPort }}' \
  #   $(docker-compose ps -q client))
}

ping_instance_simple() {
  # Check if the instance's reverse proxy is listening
  #
  # This is used as an indicator as to whether the instance is supposed to be
  # running or not.  The reason for this check is that it is fast and that the
  # reverse proxy container rarely fails itself, so it is always running when
  # an instance has been started.  Errors usually happen in the server
  # container which is checked with ping_instance_websocket.
  nc -z localhost "$1" || return 1
}

ping_instance_websocket() {
  # Connect to OpenSlides and parse its version string
  #
  # This is a way to test the availability of the app.  Most grave errors in
  # OpenSlides lead to this function failing.
  LC_ALL=C curl --silent --max-time 0.1 \
    "http://127.0.0.1:${1}/apps/core/version/" |
  gawk 'BEGIN { FPAT = "\"[^\"]*\"" } { gsub(/"/, "", $2); print $2}'
}

value_from_yaml() {
  instance="$1"
  awk -v m="^ *${2}:$" \
    '$1 ~ m { print $2; exit; }' \
    "${instance}/docker-compose.yml"
}

image_from_yaml() {
  instance="$1"
  gawk '
    BEGIN {FS=":"}
    $0 ~ /^  (prio)?server:$/ {s=1}
    $1 ~ /image/ && s { printf("%s\n%s\n", $2, $3); exit; }
    ' "${instance}/docker-compose.yml"
}

list_instances() {
  # Find instances and filter based on search term.
  # PROJECT_NAME is used as a grep -E search pattern here.
  local i=()
  readarray -d '' i < <(
    find "${INSTANCES}" -mindepth 1 -maxdepth 1 -type d -print0 |
    sort -z
  )
  for instance in "${i[@]}"; do
    # skip directories that aren't instances
    [[ -f "${instance}/docker-compose.yml" ]] || continue

    # Filter instances
    # 1. instance name/project dir matches
    if grep -E -q "$PROJECT_NAME" <<< "$(basename $instance)"; then :
    # 2. metadata matches
    elif [[ $OPT_METADATA ]] && [[ -f "${instance}/metadata.txt" ]] &&
      grep -E -q "$PROJECT_NAME" "${instance}/metadata.txt"; then :
    else
      continue
    fi

    # Determine instance state
    local shortname=$(basename "$instance")
    local port=$(local_port "$instance")
    local sym="$SYM_NORMAL"
    # If we can fetch the version string from the app this is an indicator of
    # a fully functional instance.  If we cannot this could either mean that
    # the instance has been stopped or that it is only partially working.
    local version=$(ping_instance_websocket "$port")
    if [[ -z "$version" ]]; then
      local sym="$SYM_UNKNOWN"
      # The following function simply checks if the reverse proxy port is open.
      # If it is the instance is *supposed* to be running but is not fully
      # functional; otherwise, it is assumed to be turned off on purpose.
      ping_instance_simple "$port" || sym="$SYM_ERROR"
      version="DOWN"
    fi

    # Filter online/offline instances
    case "$FILTER" in
      online)
        [[ "$version" != "DOWN" ]] || continue ;;
      offline)
        [[ "$version" = "DOWN" ]] || continue ;;
      *) ;;
    esac

    # Parse docker-compose.yml
    local git_commit=$(value_from_yaml "$instance" "REPOSITORY_URL")
    local git_repo=$(value_from_yaml "$instance" "GIT_CHECKOUT")

    if [[ -z "$git_commit" ]]; then
      local image=$(value_from_yaml "$instance" "image")
    fi

    # Parse admin credentials file
    local OPENSLIDES_ADMIN_PASSWORD="—"
    if [[ -f "${instance}/secrets/${ADMIN_SECRETS_FILE}" ]]; then
      source "${instance}/secrets/${ADMIN_SECRETS_FILE}"
    fi

    # Parse user credentials file
    local OPENSLIDES_USER_FIRSTNAME=
    local OPENSLIDES_USER_LASTNAME=
    local OPENSLIDES_USER_PASSWORD=
    local user_name=
    if [[ -f "${instance}/secrets/${USER_SECRETS_FILE}" ]]; then
      source "${instance}/secrets/${USER_SECRETS_FILE}"
      local user_name="${OPENSLIDES_USER_FIRSTNAME} ${OPENSLIDES_USER_LASTNAME}"
    fi

    # Parse metadata file
    local metadata=()
    local first_metadatum=
    if [[ -r "${instance}/metadata.txt" ]]; then
      readarray -t metadata < <(grep -v '^\s*#' "${instance}/metadata.txt")
      if [[ ${#metadata[@]} -ge 1 ]]; then
        first_metadatum="${metadata[0]}"
        # Shorten if necessary.  This string will be printed as a column of the
        # general output, so it should not cause linebreaks.  Since the same
        # information will additionally be displayed in the extended output,
        # we can just cut if off here.
        # Ideally, we'd dynamically adjust to how much space is available.
        [[ "${#first_metadatum}" -le 40 ]] || {
          first_metadatum="${first_metadatum:0:30}"
          # append ellipsis and reset formatting.  The latter may be necessary
          # because we might be cutting this off above.
          first_metadatum+="…[0m"
        }
      fi
    fi

    printf "%s %-40s\t%s\n" "$sym" "$shortname" "$first_metadatum"
    if [[ -n "$OPT_LONGLIST" ]]; then
      printf "   ├ %-12s %s\n" "Directory:" "$instance"
      printf "   ├ %-12s %s\n" "Version:" "$version"
      if [[ -n "$git_commit" ]]; then
        printf "   ├ %-12s %s\n" "Git rev:" "$git_commit"
        printf "   ├ %-12s %s\n" "Git repo:" "$git_repo"
      elif [[ -n "$image" ]]; then
        printf "   ├ %-12s %s\n" "Image:" "$image"
      fi
      printf "   ├ %-12s %s\n" "Local port:" "$port"
      printf "   ├ %-12s %s : %s\n" "Login:" "admin" "$OPENSLIDES_ADMIN_PASSWORD"

      # include secondary account credentials if available
      [[ -n "$user_name" ]] &&
        printf "   ├ %-12s \"%s\" : %s\n" \
          "Login:" "$user_name" "$OPENSLIDES_USER_PASSWORD"
    fi

    if [[ -n "$OPT_METADATA" ]]; then
      if [[ ${#metadata[@]} -ge 1 ]]; then
        printf "   └ %s\n" "Metadata:"
        for m in "${metadata[@]}"; do
          printf "     ┆ %s\n" "$m"
        done
      fi
    fi

    if [[ -n "$OPT_IMAGE_INFO" ]] && [[ "$version" != DOWN ]]; then
      local image_info="$(curl -s http://localhost:${port}/image-version.txt)"
      if [[ "$image_info" =~ ^Built ]]; then
        printf "   └ %s\n" "Image info:"
        echo "${image_info}" | sed 's/^/     ┆ /'
      fi
    fi

  done |
  # Colorize the status indicators
  if [[ -n "$NCOLORS" ]]; then
    sed "
      s/^${SYM_NORMAL}/ ${COL_GREEN}${BULLET}${COL_NORMAL}/;
      s/^${SYM_UNKNOWN}/ ${COL_YELLOW}${BULLET}${COL_NORMAL}/;
      s/^${SYM_ERROR}/ ${COL_RED}${BULLET}${COL_NORMAL}/
    "
  else
    cat -
  fi
}

clone_secrets() {
  if [[ -d "${CLONE_FROM_DIR}/secrets/" ]]; then
    rsync -axv "${CLONE_FROM_DIR}/secrets/" "${PROJECT_DIR}/secrets/"
  fi
}

clone_db() {
  _docker_compose "$PROJECT_DIR" up -d --no-deps postgres
  local clone_from_id=$(_docker_compose "$CLONE_FROM_DIR" ps -q postgres)
  local clone_to_id=$(_docker_compose "$PROJECT_DIR" ps -q postgres)
  sleep 3 # XXX
  docker exec -u postgres "$clone_from_id" pg_dump -c --if-exists openslides |
  docker exec -i -u postgres "$clone_to_id" psql openslides
}

get_personaldata_dir() {
  docker inspect --format \
    '{{ range .Mounts }}{{ if eq .Destination "/app/personal_data" }}{{ .Source }}{{ end }}{{ end }}' \
    "$(_docker_compose "$1" ps -q server)"
}

clone_files() {
  _docker_compose "$PROJECT_DIR" up --no-start --no-deps server
  local from_dir=$(get_personaldata_dir "$CLONE_FROM_DIR")
  local to_dir=$(get_personaldata_dir "$PROJECT_DIR")
  rsync -axv "${from_dir}/" "${to_dir}/"
}

append_metadata() {
  local m="${1}/metadata.txt"
  touch "$m"
  shift
  printf "%s\n" "$*" >> "$m"
}

ask_start() {
  local start=
  read -p "Start containers? [Y/n] " start
  case "$start" in
    Y|y|Yes|yes|YES|"")
      instance_start ;;
    *)
      echo "Not starting containers." ;;
  esac
}

instance_start() {
  _docker_compose "$PROJECT_DIR" build
  _docker_compose "$PROJECT_DIR" up -d
}

instance_stop() {
  _docker_compose "$PROJECT_DIR" down
}

instance_erase() {
  _docker_compose "$PROJECT_DIR" down --volumes
}

instance_update() {
  gawk -v image="$DOCKER_IMAGE_NAME_OPENSLIDES" \
      -v tag="$DOCKER_IMAGE_TAG_OPENSLIDES" '
    BEGIN {FS=":"; OFS=FS}
    $0 ~ /^  (prio)?server:$/ {s=1}
    image != "" && $1 ~ /image/ && s { $2 = " " image; s=0 }
    tag != "" && $1 ~ /image/ && s { $3 = tag; s=0 }
    1
    ' "${DCCONFIG}" > "${DCCONFIG}.tmp" &&
  mv -f "${DCCONFIG}.tmp" "${DCCONFIG}"
  local build_opt=
  [[ -z "$OPT_FORCE" ]] || local build_opt="--no-cache"
  _docker_compose "$PROJECT_DIR" build "$build_opt" server
  echo "Creating services"
  _docker_compose "$PROJECT_DIR" up --no-start
  local server="$(_docker_compose "$PROJECT_DIR" ps -q server)"
  # Delete staticfiles volume
  local vol=$(docker inspect --format \
      '{{ range .Mounts }}{{ if eq .Destination "/app/openslides/static" }}{{ .Name }}{{ end }}{{ end }}' \
      "$server"
  )
  echo "Scaling down"
  _docker_compose "$PROJECT_DIR" up -d \
    --scale server=0 --scale prioserver=0 --scale client=0
  echo "Deleting staticfiles volume"
  docker volume rm "$vol"
  echo "Flushing redis cache"
  instance_flush
  echo "OK.  Bringing up all services"
  _docker_compose "$PROJECT_DIR" up -d
  append_metadata "$PROJECT_DIR" "$(date +"%F %H:%M"): Updated to" \
    "${DOCKER_IMAGE_NAME_OPENSLIDES}:${DOCKER_IMAGE_TAG_OPENSLIDES}"
}

instance_flush() {
  _docker_compose "$PROJECT_DIR" up -d --scale server=0 --scale prioserver=0
  local redis="$(_docker_compose "$PROJECT_DIR" ps -q rediscache)"
  docker exec "$redis" redis-cli flushall
  _docker_compose "$PROJECT_DIR" up -d --scale server=1 --scale prioserver=1
}


shortopt="hlminfd:I:t:"
longopt=(
  help
  color:
  long
  project-dir:
  force

  # filtering
  online
  offline
  metadata
  image-info

  # adding instances
  clone-from:
  local-only
  no-add-account
  mailserver:
  www

  # adding & upgrading instances
  image:
  tag:
)
# format options array to comma-separated string for getopt
longopt=$(IFS=,; echo "${longopt[*]}")

ARGS=$(getopt -o "$shortopt" -l "$longopt" -n "$ME" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";
unset ARGS

# Config file
if [[ -f "$CONFIG" ]]; then
  source "$CONFIG"
  # For legacy settings, make sure defaults are stored in DEFAULT_* vars and
  # that the CLI variables remain unset at this point
  [[ -z "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] ||
    DEFAULT_DOCKER_IMAGE_NAME_OPENSLIDES="$DOCKER_IMAGE_NAME_OPENSLIDES"
  [[ -z "$DOCKER_IMAGE_TAG_OPENSLIDES" ]] ||
    DEFAULT_DOCKER_IMAGE_TAG_OPENSLIDES="$DOCKER_IMAGE_TAG_OPENSLIDES"
  DOCKER_IMAGE_NAME_OPENSLIDES=
  DOCKER_IMAGE_TAG_OPENSLIDES=
fi

# Parse options
while true; do
  case "$1" in
    -d|--project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    -I|--image)
      DOCKER_IMAGE_NAME_OPENSLIDES="$2"
      shift 2
      ;;
    -t|--tag)
      DOCKER_IMAGE_TAG_OPENSLIDES="$2"
      shift 2
      ;;
    --mailserver)
      RELAYHOST="$2"
      shift 2
      ;;
    --no-add-account)
      OPT_ADD_ACCOUNT=
      shift 1
      ;;
    -l|--long)
      OPT_LONGLIST=1
      shift 1
      ;;
    -m|--metadata)
      OPT_METADATA=1
      shift 1
      ;;
    -i|--image-info)
      OPT_IMAGE_INFO=1
      shift 1
      ;;
    -n|--online)
      FILTER="online"
      shift 1
      ;;
    -f|--offline)
      FILTER="offline"
      shift 1
      ;;
    --clone-from)
      CLONE_FROM="$2"
      shift 2
      ;;
    --local-only)
      OPT_LOCALONLY=1
      shift 1
      ;;
    --www)
      OPT_WWW=1
      shift 1
      ;;
    --color)
      OPT_COLOR="$2"
      shift 2
      ;;
    --force)
      OPT_FORCE=1
      shift 1
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift ; break ;;
    *) usage; exit 1 ;;
  esac
done

# Parse commands
for arg; do
  case $arg in
    ls|list)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=list
      shift 1
      ;;
    add|create)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=create
      [[ -z "$CLONE_FROM" ]] || MODE=clone
      shift 1
      ;;
    rm|remove)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=remove
      shift 1
      ;;
    start|up)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=start
      shift 1
      ;;
    stop|down)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=stop
      shift 1
      ;;
    erase)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=erase
      shift 1
      ;;
    flush)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=flush
      shift 1
      ;;
    update)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=update
      [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] ||
      [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]] || {
        fatal "Need image or tag for update"
      }
      shift 1
      ;;
    *)
      # The final argument should be the project name/search pattern
      PROJECT_NAME="$arg"
      break
      ;;
  esac
done

case "$OPT_COLOR" in
  auto)
    if [[ -t 1 ]]; then enable_color; fi ;;
  always)
    enable_color ;;
  never) true ;;
  *)
    fatal "Unknown option to --color" ;;
esac


DEPS=(
  docker
  docker-compose
  gawk
  acmetool
  nc
)
# Check dependencies
for i in "${DEPS[@]}"; do
    check_for_dependency "$i"
done

# Prevent --project-dir to be used together with a project name
if [[ -n "$PROJECT_DIR" ]] && [[ -n "$PROJECT_NAME" ]]; then
  fatal "Mutually exclusive options"
fi
# Deduce project name from path
if [[ -n "$PROJECT_DIR" ]]; then
  PROJECT_NAME=$(basename $(readlink -f "$PROJECT_DIR"))
# Treat the project name "." as --project-dir=.
elif [[ "$PROJECT_NAME" = "." ]]; then
  PROJECT_NAME=$(basename $(readlink -f "$PROJECT_NAME"))
  PROJECT_DIR="${INSTANCES}/${PROJECT_NAME}"
else
  PROJECT_DIR="${INSTANCES}/${PROJECT_NAME}"
fi

DCCONFIG="${PROJECT_DIR}/docker-compose.yml"
NGINX_TEMPLATE="${PROJECT_DIR}/contrib/nginx.conf.in"

case "$MODE" in
  remove)
    arg_check || { usage; exit 2; }
    [[ -n "$OPT_FORCE" ]] || marker_check
    remove "$PROJECT_NAME"
    ;;
  create)
    [[ -f "$CONFIG" ]] && echo "Found ${CONFIG} file." || true
    arg_check || { usage; exit 2; }
    [[ -n "$OPT_FORCE" ]] || verify_domain
    # Use defaults in the absence of options
    [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] ||
      DOCKER_IMAGE_NAME_OPENSLIDES="$DEFAULT_DOCKER_IMAGE_NAME_OPENSLIDES"
    [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]] ||
      DOCKER_IMAGE_TAG_OPENSLIDES="$DEFAULT_DOCKER_IMAGE_TAG_OPENSLIDES"
    query_user_account_name
    echo "Creating new instance: $PROJECT_NAME"
    PORT=$(next_free_port)
    create_instance_dir
    create_config_from_template "${PROJECT_DIR}/docker-compose.yml.example" \
      "${PROJECT_DIR}/docker-compose.yml"
    create_admin_secrets_file
    create_user_secrets_file "${OPENSLIDES_USER_FIRSTNAME}" "${OPENSLIDES_USER_LASTNAME}"
    update_nginx_config
    append_metadata "$PROJECT_DIR" "$(date +"%F %H:%M"): Instance created"
    [[ -z "$OPT_LOCALONLY" ]] ||
      append_metadata "$PROJECT_DIR" "No Nginx config added (--local-only)"
    ask_start
    link_settingspy
    ;;
  clone)
    CLONE_FROM_DIR="${INSTANCES}/${CLONE_FROM}"
    arg_check || { usage; exit 2; }
    [[ -n "$OPT_FORCE" ]] || verify_domain
    echo "Creating new instance: $PROJECT_NAME (based on $CLONE_FROM)"
    PORT=$(next_free_port)
    # Parse image and/or tag from original config if necessary
    ia=()
    readarray -n 2 -t ia < <(image_from_yaml "$CLONE_FROM_DIR")
    for i in ${ia[@]}; do echo $i ; done
    [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] ||
      DOCKER_IMAGE_NAME_OPENSLIDES="${ia[0]}"
    [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]] ||
      DOCKER_IMAGE_TAG_OPENSLIDES="${ia[1]}"
    create_instance_dir
    create_config_from_template "${CLONE_FROM_DIR}/docker-compose.yml" \
      "${PROJECT_DIR}/docker-compose.yml"
    clone_secrets
    clone_files
    clone_db
    update_nginx_config
    append_metadata "$PROJECT_DIR" "Cloned from $CLONE_FROM on $(date)"
    [[ -z "$OPT_LOCALONLY" ]] ||
      append_metadata "$PROJECT_DIR" "No Nginx config added (--local-only)"
    ask_start
    link_settingspy
    ;;
  list)
    list_instances
    ;;
  start)
    arg_check || { usage; exit 2; }
    instance_start ;;
  stop)
    arg_check || { usage; exit 2; }
    instance_stop ;;
  erase)
    arg_check || { usage; exit 2; }
    echo "WARNING: This will stop the instance, and remove its containers and volumes!"
    ERASE=
    read -p "Continue? [y/N] " ERASE
    case "$ERASE" in
      Y|y|Yes|yes|YES)
        instance_erase ;;
    esac
    ;;
  update)
    [[ -f "$CONFIG" ]] && echo "Found ${CONFIG} file." || true
    arg_check || { usage; exit 2; }
    instance_update
    ;;
  flush)
    instance_flush
    ;;
  *)
    usage
    ;;
esac
