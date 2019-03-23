#!/bin/bash

# Set up a new OpenSlides docker-compose instance
#
# This script makes some assumptions and would need more options to become more
# flexible

set -eu
set -o noclobber

TEMPLATE_REPO="/srv/openslides/openslides-docker-compose"
# TEMPLATE_REPO="https://github.com/OpenSlides/openslides-docker-compose"
OSDIR="/srv/openslides"
INSTANCES="${OSDIR}/docker-instances"

NGINX_TEMPLATE=
PROJECT_NAME=
PROJECT_DIR=
PORT=
MODE=list
VERBOSE=
OPT_ADD_ACCOUNT=
FILTER=
GIT_CHECKOUT=
ADMIN_SECRETS_FILE="adminsecret.env"
USER_SECRETS_FILE="usersecret.env"
OPENSLIDES_USER_FIRSTNAME=
OPENSLIDES_USER_LASTNAME=

# Color and formatting settings
NCOLORS=
COL_NORMAL=""
COL_RED=""
COL_GREEN=""
BULLET='●'
SYM_NORMAL="_"
SYM_ERROR="X"
if [[ -t 1 ]]; then
  NCOLORS=$(tput colors) # no. of colors
  if [[ -n "$NCOLORS" ]] && [[ "$NCOLORS" -ge 8 ]]; then
    COL_NORMAL="$(tput sgr0)"
    COL_RED="$(tput setaf 1)"
    COL_GREEN="$(tput setaf 2)"
  fi
fi

usage() {
cat <<EOF
Usage: ${BASH_SOURCE[0]} [options] <action> <instance_domain>

Manage docker-compose-based OpenSlides instances.

Action:
  -a, --add       Add a new instance for the given domain (requires FQDN).
  -l, --list      List instances and their status.  <instance_domain> is a search
                  pattern in this case.
  -r, --remove    Remove the instance instance_domain (requires FQDN).

Options:
  -v, --verbose   Increase verbosity
  -n, --online    In list view, show only online instances
  -f, --offline   In list view, show only offline instances
  -c, --checkout  The server version to check out (for use with --add)
  --add-account   Add an additional, customized local admin account
EOF
}

check_for_dependency () {
    [[ -n "$1" ]] || return 0
    which "$1" > /dev/null || { echo "ERROR: Dependency not found: $1"; return 1; }
}


arg_check() {
  [[ -d "$OSDIR" ]] || { echo "ERROR: $OSDIR not found!"; return 2; }
  [[ -n "$PROJECT_NAME" ]] || {
    echo "ERROR: Please specify a project name"; return 2;
  }
}

query_user_account_name() {
  if [[ -n "$OPT_ADD_ACCOUNT" ]]; then
    echo "Create local admin account for:"
    read -p "First name: " OPENSLIDES_USER_FIRSTNAME
    read -p "Last name: " OPENSLIDES_USER_LASTNAME
  fi
}

verify_domain() {
  # Verify provided domain
  HOSTNAME=$(hostname -f)
  IP=$(host "$HOSTNAME" | awk '/has address/ { print $4; exit; } /has IPv6 address/ { print $5}')
  host "$PROJECT_NAME" | grep -q "$IP" || {
    echo "ERROR: $PROJECT_NAME does not point to this host?"
    return 3
  }
}


next_free_port() {
  # Select new port
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
    [[ $n -lt 5 ]] || { echo "ERROR: Could not find free port"; exit 3; }
    ((PORT+=1))
    ((n+=1))
  done
  echo "$PORT"
}

create_instance_dir() {
  # Update yaml
  git clone "${TEMPLATE_REPO}" "${PROJECT_DIR}"
  gawk -v port="${PORT}" -v git="$GIT_CHECKOUT" '
    BEGIN {FS=":"; OFS=FS}
    git != "" && $1 ~ /GIT_CHECKOUT/ { $2 = " " git }
    $2 == 61000 { $2 = port }
    1
  ' "${DCCONFIG}".example > "${DCCONFIG}"
  # prepare secrets files
  [[ -d "${PROJECT_DIR}/secrets" ]] ||
    mkdir -m 700 "${PROJECT_DIR}/secrets"
  touch "${PROJECT_DIR}/secrets/${ADMIN_SECRETS_FILE}" \
    "${PROJECT_DIR}/secrets/${USER_SECRETS_FILE}"
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
    cat << EOF >> "${PROJECT_DIR}/secrets/${USER_SECRETS_FILE}"
OPENSLIDES_USER_FIRSTNAME=$first_name
OPENSLIDES_USER_LASTNAME=$last_name
OPENSLIDES_USER_PASSWORD=$PW
EOF
  fi
}


update_nginx_config() {
# Create Nginx configs
  # First, without TLS
  sed -e "s/<INSTANCE>/${PROJECT_NAME}/" "$NGINX_TEMPLATE" \
    -e "/proxy_pass/s/61000/${PORT}/" \
    > /etc/nginx/sites-available/"${PROJECT_NAME}".conf
  ln -s ../sites-available/"${PROJECT_NAME}".conf /etc/nginx/sites-enabled/ || true
  systemctl reload nginx

  # Generate Let's Encrypt certificate
  acmetool want "${PROJECT_NAME}"
  echo "Got certificate."

  # Update Nginx to use TLS certs
  ex -s +"g/ssl-cert-snakeoil/d" +"g/ssl_certificate/s/#\ //" +x \
    /etc/nginx/sites-available/"${PROJECT_NAME}".conf
  systemctl reload nginx
}

remove() {
  local PROJECT_NAME="$1"
  [[ -d "$PROJECT_DIR" ]] || {
    echo "ERROR: $PROJECT_DIR does not exist."
    return 2
  }
  # Ask for confirmation
  local ANS=
  echo "Delete the following instance including all its data and configuration?"
  echo "  $PROJECT_DIR"
  read -p "Really delete? (uppercase YES to confirm) " ANS
  [[ "$ANS" = "YES" ]] || return 0

  echo "Stopping and removing containers..."
  cd "${PROJECT_DIR}" &&
    ./handle-instance.sh -f rm
  cd
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

ping_instance() {
  local instance="$1"
  local_port=$(grep -A1 ports: "${instance}/docker-compose.yml" | tail -1 | cut -d: -f2)
  # retrieve version string
  curl --silent --max-time 0.1 "http://127.0.0.1:${local_port}/apps/core/version/" |
  gawk 'BEGIN { FPAT = "\"[^\"]*\"" } { gsub(/"/, "", $2); print $2}'
}


list_instances() {
  a=($(find "${INSTANCES}" -mindepth 1 -maxdepth 1 -type d -iname \
    "*${PROJECT_NAME}*" -print | sort))
  for instance in "${a[@]}"; do
    local shortname=$(basename "$instance")
    local version=$(ping_instance "$instance")
    local sym="$SYM_NORMAL"
    if [[ -z "$version" ]]; then
      # Register as error
      version="DOWN"
      local sym="$SYM_ERROR"
    fi
    # Fiter online/offline instances
    case "$FILTER" in
      online)
        [[ "$version" != "DOWN" ]] || continue ;;
      offline)
        [[ "$version" = "DOWN" ]] || continue ;;
      *) ;;
    esac

    # Parse docker-compose.yml
    local git_commit_hash=$(
      awk '$1 == "GIT_CHECKOUT:" { print $2; exit; }' \
        "${instance}/docker-compose.yml"
      )

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
        # information will additionally be displayed in the --verbose output,
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

    printf "%s  %s\t\t%s\n" "$sym" "$shortname" "$first_metadatum"
    if [[ -n "$VERBOSE" ]]; then
      printf "     - %-12s %s\n" "Version:" "$version"
      printf "     - %-12s %s\n" "GIT_COMMIT:" "$git_commit_hash"
      printf "     - %-12s %s : %s\n" "Login:" "admin" "$OPENSLIDES_ADMIN_PASSWORD"

      # include secondary account credentials if available
      [[ -n "$user_name" ]] &&
        printf "     - %-12s \"%s\" : %s\n" \
          "Login:" "$user_name" "$OPENSLIDES_USER_PASSWORD"

      if [[ ${#metadata[@]} -ge 1 ]]; then
        printf "     - %s\n" "Metadata:"
        for m in "${metadata[@]}"; do
          printf "       %s\n" "$m"
        done
      fi
    fi
  done |
  # Colorize the status indicators
  if [[ -n "$NCOLORS" ]]; then
    sed "
      s/^${SYM_NORMAL}/${COL_GREEN}${BULLET}${COL_NORMAL}/;
      s/^${SYM_ERROR}/${COL_RED}${BULLET}${COL_NORMAL}/
    "
  else
    cat
  fi
}

shortopt="harslvnfc:"
longopt="help,add,checkout:,remove,list,verbose,online,offline,add-account"

ARGS=$(getopt -o "$shortopt" -l "$longopt" -- "$@")
if [ $? -ne 0 ]; then usage; exit 1; fi
eval set -- "$ARGS";

# [[ $# -gt 1 ]] || { usage; exit 2; }

while true; do
    case "$1" in
        -a|--add)
          MODE=create
          shift 1
          ;;
        -c|--checkout)
          GIT_CHECKOUT="$2"
          shift 2
          ;;
        --add-account)
          OPT_ADD_ACCOUNT=1
          shift 1
          ;;
        -r|--remove)
          MODE=remove
          shift 1
          ;;
        -l|--list)
          MODE=list
          shift 1
          ;;
        -v|--verbose)
          VERBOSE=1
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
        -h|--help) usage; exit 0 ;;
        --) shift ; break ;;
        *) usage; exit 1 ;;
    esac
done

[[ -n "$MODE" ]] || { usage; exit 2; }

DEPS=(
  gawk
  acmetool
)
# Check dependencies
for i in "${DEPS[@]}"; do
    check_for_dependency "$i"
done

PROJECT_NAME="${1-""}"
PROJECT_DIR="${INSTANCES}/${PROJECT_NAME}"
DCCONFIG="${PROJECT_DIR}/docker-compose.yml"
NGINX_TEMPLATE="${PROJECT_DIR}/contrib/nginx.conf.in"

case "$MODE" in
  remove)
    arg_check || { usage; exit 2; }
    remove "$PROJECT_NAME"
    exit 0
    ;;
  create)
    arg_check || { usage; exit 2; }
    query_user_account_name
    echo "Creating new instance: $PROJECT_NAME"
    verify_domain
    PORT=$(next_free_port)
    create_instance_dir
    create_admin_secrets_file
    create_user_secrets_file "${OPENSLIDES_USER_FIRSTNAME}" "${OPENSLIDES_USER_LASTNAME}"
    update_nginx_config
    ;;
  list)
    list_instances
    exit 0
esac

START=
read -p "Start containers? [Y/n] " START
case "$START" in
  Y|y|Yes|yes|YES|"")
    cd "${PROJECT_DIR}" &&
    ./handle-instance.sh -f run ;;
  *)
    echo "Not starting containers." ;;
esac
