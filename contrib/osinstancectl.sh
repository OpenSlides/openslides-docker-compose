#!/bin/bash

# Manage dockerized OpenSlides instances
#
# -------------------------------------------------------------------
# Copyright (C) 2019,2021 by Intevation GmbH
# Author(s):
# Gernot Schulz <gernot@intevation.de>
#
# This program is distributed under the MIT license, as described
# in the LICENSE file included with the distribution.
# SPDX-License-Identifier: MIT
# -------------------------------------------------------------------

set -eu
set -o noclobber
set -o pipefail

# Defaults (override in /etc/osinstancectl)
TEMPLATE_REPO="/srv/openslides/OpenSlides"
# TEMPLATE_REPO="https://github.com/OpenSlides/openslides-docker-compose"
OSDIR="/srv/openslides"
INSTANCES="${OSDIR}/docker-instances"
YAML_TEMPLATE= # leave empty for automatic (default)
DOT_ENV_TEMPLATE=
HOOKS_DIR=

ME=$(basename -s .sh "${BASH_SOURCE[0]}")
CONFIG="/etc/osinstancectl"
MARKER=".osinstancectl-marker"
PRIMARY_DATABASE_NODE="pgnode1"
DOCKER_IMAGE_NAME_OPENSLIDES=
DOCKER_IMAGE_TAG_OPENSLIDES=
DOCKER_IMAGE_NAME_CLIENT=
DOCKER_IMAGE_TAG_CLIENT=
DOCKER_IMAGE_NAME_AUTOUPDATE=
DOCKER_IMAGE_TAG_AUTOUPDATE=
PROJECT_NAME=
PROJECT_DIR=
PROJECT_STACK_NAME=
PORT=
DEPLOYMENT_MODE=
MODE=
OPT_LONGLIST=
OPT_SECRETS=
OPT_METADATA=
OPT_METADATA_SEARCH=
OPT_IMAGE_INFO=
OPT_JSON=
OPT_ADD_ACCOUNT=1
OPT_LOCALONLY=
OPT_FORCE=
OPT_WWW=
OPT_FAST=
OPT_PATIENT=
OPT_USE_PARALLEL="${OPT_USE_PARALLEL:-1}"
FILTER_STATE=
FILTER_VERSION=
CLONE_FROM=
ADMIN_SECRETS_FILE="adminsecret.env"
USER_SECRETS_FILE="usersecret.env"
OPENSLIDES_USER_FIRSTNAME=
OPENSLIDES_USER_LASTNAME=
OPENSLIDES_USER_EMAIL=
OPENSLIDES_USER_PASSWORD=
DEFAULT_DOCKER_REGISTRY=
OPT_PRECISE_PROJECT_NAME=
CURL_OPTS=(--max-time 1 --retry 2 --retry-delay 1 --retry-max-time 3)

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
SYM_STOPPED="__"
JQ="jq --monochrome-output"

enable_color() {
  NCOLORS=$(tput colors) # no. of colors
  if [[ -n "$NCOLORS" ]] && [[ "$NCOLORS" -ge 8 ]]; then
    COL_NORMAL="$(tput sgr0)"
    COL_RED="$(tput setaf 1)"
    COL_YELLOW="$(tput setaf 3)"
    COL_GREEN="$(tput setaf 2)"
    COL_GRAY="$(tput bold; tput setaf 0)"
    JQ="jq --color-output"
  fi
}

usage() {
cat <<EOF
Usage: $ME [options] <action> <instance>

Manage OpenSlides Docker instances.

Actions:
  ls                   List instances and their status.  <instance> is
                       a grep ERE search pattern in this case.
  add                  Add a new instance for the given domain (requires FQDN)
  rm                   Remove <instance> (requires FQDN)
  start                Start, i.e., (re)deploy an existing instance
  stop                 Stop a running instance
  update               Update OpenSlides services to a new images
  erase                Remove an instance's volumes (stops the instance if
                       necessary)

Options:
  -d, --project-dir    Directly specify the project directory
  --yaml-template      Specify a YAML template
  --env-template       Specify a .env template
  --force              Disable various safety checks
  --color=WHEN         Enable/disable color output.  WHEN is never, always, or
                       auto.

  for ls:
    -a, --all          Equivalent to -l -m -i
    -l, --long         Include more information in extended listing format
    -s, --secrets      Include sensitive information such as login credentials
    -m, --metadata     Include metadata in instance list
    -i, --image-info   Show image version info (requires instance to be
                       started)
    -n, --online       Show only online instances
    -f, --offline      Show only stopped instances
    -e, --error        Show only running but unreachable instances
    -M,
    --search-metadata  Include metadata
    --fast             Include less information to increase listing speed
    --patient          Increase timeouts
    --version          Filter results based on the version reported by
                       OpenSlides (implies --online)
    -j, --json         Enable JSON output format

  for add & update:
    --server-image,
    --backend-image    Specify the OpenSlides server Docker image name
    --server-tag,
    --backend-tag      Specify the OpenSlides server Docker image tag
    --client-image,
    --frontend-image   Specify the OpenSlides client Docker image name
    --client-tag,
    --frontend-tag     Specify the OpenSlides client Docker image tag
    --autoupdate-image Specify the OpenSlides autoupdate service Docker image name
    --autoupdate-tag   Specify the OpenSlides autoupdate service Docker image tag
    -t, --all-tags     Specify the image tags for all OpenSlides components
                       (see above)
    --no-add-account   Do not add an additional, customized local admin account
    --local-only       Create an instance without setting up HAProxy and Let's
                       Encrypt certificates.  Such an instance is only
                       accessible on localhost, e.g., http://127.1:61000.
    --clone-from       Create the new instance based on the specified existing
                       instance
    --www              Add a www subdomain in addition to the specified
                       instance domain (to be passed to ACME clients)

Colored status indicators in ls mode:
  green                The instance appears to be fully functional
  red                  The instance is running but is unreachable
  yellow               The instance's status can not be determined
  gray                 The instance has been stopped
EOF
}

fatal() {
    echo 1>&2 "${COL_RED}ERROR${COL_NORMAL}: $*"
    exit 23
}

check_config_compatibility() {
  # XXX: During transition period, check that the YAML template and given
  # instance's .env configuration are either consistently based on a legacy OS3
  # or OS3+ setup
  local legacy_yaml=0 legacy_env=0
  grep -q DOCKER_OPENSLIDES_AUTOUPDATE_NAME "$DCCONFIG_TEMPLATE"  || legacy_yaml=1
  if [[ -f "${PROJECT_DIR}/.env" ]]; then
    # prevent start
    grep -q DOCKER_OPENSLIDES_AUTOUPDATE_NAME "${PROJECT_DIR}/.env" || legacy_env=1
  else
    # prevent create
    grep -q DOCKER_OPENSLIDES_AUTOUPDATE_NAME "${DOT_ENV_TEMPLATE}" || legacy_env=1
  fi
  if [[ $legacy_env -ne $legacy_yaml ]]; then
    fatal "Incompatible configuration (OS3 vs. OS3+)"
  fi
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
  case "$MODE" in
    "start" | "stop" | "remove" | "erase" | "update")
      [[ -d "$PROJECT_DIR" ]] || {
        fatal "Instance '${PROJECT_NAME}' not found."
      }
      [[ -f "${PROJECT_DIR}/${CONFIG_FILE}" ]] || {
        fatal "Not a ${DEPLOYMENT_MODE} instance."
      }
      ;;
    "clone")
      [[ -d "$CLONE_FROM_DIR" ]] || {
        fatal "$CLONE_FROM_DIR does not exist."
      }
      ;;
    "create")
      [[ ! -d "$PROJECT_DIR" ]] || {
        fatal "Instance '${PROJECT_NAME}' already exists."
      }
      ;;
  esac
  echo "$DOCKER_IMAGE_NAME_OPENSLIDES" \
    "$DOCKER_IMAGE_NAME_CLIENT" | grep -q -v ':' ||
    fatal "Image names must not contain colons.  Tags can be specified separately."
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
    --file "${project_dir}/${CONFIG_FILE}" "$@"
}

query_user_account_name() {
  if [[ -n "$OPT_ADD_ACCOUNT" ]]; then
    echo "Create local admin account for:"
    while [[ -z "$OPENSLIDES_USER_FIRSTNAME" ]] || \
          [[ -z "$OPENSLIDES_USER_LASTNAME" ]]
    do
      read -rp "First & last name: " \
        OPENSLIDES_USER_FIRSTNAME OPENSLIDES_USER_LASTNAME
      read -rp "Email (optional): " OPENSLIDES_USER_EMAIL
    done
  fi
}

next_free_port() {
  # Select new port
  #
  # This parses existing instances' YAML files to discover used ports and to
  # select the next one.  Other methods may be more suitable and robust but
  # have other downsides.  For example, `docker-compose port client 80` is
  # only available for running services.
  local HIGHEST_PORT_IN_USE
  local PORT
  HIGHEST_PORT_IN_USE=$(
    find "${INSTANCES}" -type f -name ".env" -print0 |
    xargs -0 grep -h "EXTERNAL_HTTP_PORT" |
    cut -d= -f2 | tr -d "[\"\']" | sort -rn | head -1
  )
  [[ -n "$HIGHEST_PORT_IN_USE" ]] || HIGHEST_PORT_IN_USE=61000
  PORT=$((HIGHEST_PORT_IN_USE + 1))

  # Check if port is actually free
  #  try to find the next free port (this situation can occur if there are test
  #  instances outside of the regular instances directory)
  n=0
  while ! ss -tnHl | awk -v port="$PORT" '$4 ~ port { exit 2 }'; do
    [[ $n -le 25 ]] || { fatal "Could not find free port"; }
    ((PORT+=1))
    [[ $PORT -le 65535 ]] || { fatal "Ran out of ports"; }
    ((n+=1))
  done
  echo "$PORT"
}

update_env_file() {
  # This function updates variables in given .env files.
  # The variable to be updated must already be present in the file; the
  # function can not be used to add new values to the .env file!
  [[ -f "$1" ]] || fatal "$1 not found."
  # Exit if variable is non-empty because it indicates a template customization
  [[ "${4:-NOFORCE}" = "--force" ]] || ( set +u; source "$1" && [[ -z "${!2}" ]] ) || return 0
  local temp_file="$(mktemp)"
  gawk -v env_var_name="$2" -v env_var_val="$3" '
    BEGIN { FS = "="; OFS=FS }
    $1 == env_var_name { $2 = env_var_val; s=1 }
    1
    # TODO: --force could be leveraged to enable appending variables not
    # already present in the template:
    # END { if (!s) printf("%s=%s\n", env_var_name, env_var_val) }
  ' "$1" >| "$temp_file"
  cp -f "$temp_file" "$1"
  rm "$temp_file"
}

create_config_from_template() {
  local _env="${PROJECT_DIR}/.env"
  local temp_file
  temp_file="$(mktemp)"
  # Create .env
  [[ ! -f "${_env}" ]] || cp -af "${_env}" "$temp_file"
  update_env_file "$temp_file" "EXTERNAL_HTTP_PORT" "$PORT"
  update_env_file "$temp_file" "INSTANCE_DOMAIN" "https://${PROJECT_NAME}"
  update_env_file "$temp_file" "DEFAULT_DOCKER_REGISTRY" "$DEFAULT_DOCKER_REGISTRY"
  update_env_file "$temp_file" "DOCKER_OPENSLIDES_BACKEND_NAME" "$DOCKER_IMAGE_NAME_OPENSLIDES"
  update_env_file "$temp_file" "DOCKER_OPENSLIDES_BACKEND_TAG" "$DOCKER_IMAGE_TAG_OPENSLIDES"
  update_env_file "$temp_file" "DOCKER_OPENSLIDES_FRONTEND_NAME" "$DOCKER_IMAGE_NAME_CLIENT"
  update_env_file "$temp_file" "DOCKER_OPENSLIDES_FRONTEND_TAG" "$DOCKER_IMAGE_TAG_CLIENT"
  update_env_file "$temp_file" "DOCKER_OPENSLIDES_AUTOUPDATE_NAME" "$DOCKER_IMAGE_NAME_AUTOUPDATE"
  update_env_file "$temp_file" "DOCKER_OPENSLIDES_AUTOUPDATE_TAG" "$DOCKER_IMAGE_TAG_AUTOUPDATE"
  update_env_file "$temp_file" "POSTFIX_MYHOSTNAME" "$PROJECT_NAME"
  cp -af "$temp_file" "${_env}"
  # Create config from template + .env
  ( set -a && source "${_env}" &&
    m4 -DPROJECT_DIR="$PROJECT_DIR" "$DCCONFIG_TEMPLATE" > "${DCCONFIG}" )
  rm -rf "$temp_file" # TODO: trap
}

create_instance_dir() {
  case "$DEPLOYMENT_MODE" in
    "compose")
      git clone "${TEMPLATE_REPO}" "${PROJECT_DIR}"
      ln -s docker/docker-compose.yml.m4 "${PROJECT_DIR}/docker-compose.yml.m4"
      cp "${TEMPLATE_REPO}/docker/.env" "${PROJECT_DIR}/.env"
      ;;
    "stack")
      # If the template repo is a local worktree, copy files from it
      if [[ -d "${TEMPLATE_REPO}" ]]; then
        mkdir -p "${PROJECT_DIR}"
      else
        # Template repo appears to be remote, so clone it
        git clone "${TEMPLATE_REPO}" "${PROJECT_DIR}"
        ln -s docker/docker-stack.yml.m4 "${PROJECT_DIR}/docker-stack.yml.m4"
        cp docker/.env "${PROJECT_DIR}/.env"
      fi
      ;;
  esac
  mkdir -p -m 700 "${PROJECT_DIR}/secrets"
  touch "${PROJECT_DIR}/${MARKER}"
  # Add .env if template available
  [[ ! -f "$DOT_ENV_TEMPLATE" ]] || cp -af "$DOT_ENV_TEMPLATE" "${PROJECT_DIR}/.env"
  # Add stack name to .env file
  update_env_file "${PROJECT_DIR}/.env" "PROJECT_STACK_NAME" "$PROJECT_STACK_NAME"
}

gen_pw() {
  local len="${1:-15}"
  read -r -n "$len" PW < <(LC_ALL=C tr -dc "[:alnum:]" < /dev/urandom)
  echo "$PW"
}

create_admin_secrets_file() {
  echo "Generating admin password..."
  [[ -d "${PROJECT_DIR}/secrets" ]] ||
    mkdir -m 700 "${PROJECT_DIR}/secrets"
  printf "OPENSLIDES_ADMIN_PASSWORD=%s\n" "$(gen_pw)" \
    > "${PROJECT_DIR}/secrets/${ADMIN_SECRETS_FILE}"
}

create_user_secrets_file() {
  if [[ -n "$OPT_ADD_ACCOUNT" ]]; then
    local first_name
    local last_name
    local email # optional
    local PW
    echo "Generating user credentials..."
    [[ -d "${PROJECT_DIR}/secrets" ]] ||
      mkdir -m 700 "${PROJECT_DIR}/secrets"
    first_name="$1"
    last_name="$2"
    email="$3"
    PW="$(gen_pw)"
    cat << EOF > "${PROJECT_DIR}/secrets/${USER_SECRETS_FILE}"
# Configured by $ME:
OPENSLIDES_USER_FIRSTNAME="$first_name"
OPENSLIDES_USER_LASTNAME="$last_name"
OPENSLIDES_USER_PASSWORD="$PW"
OPENSLIDES_USER_EMAIL="$email"
EOF
  fi
}

create_django_secrets_file() {
  echo "Generating Django secret key..."
  printf "DJANGO_SECRET_KEY='%s'\n" "$(gen_pw 64)" \
    > "${PROJECT_DIR}/secrets/django.env"
}

add_to_haproxy_cfg() {
  [[ -z "$OPT_LOCALONLY" ]] || return 0
  cp -f /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.osbak &&
    gawk -v target="${PROJECT_NAME}" -v port="${PORT}" -v www="${OPT_WWW}" '
    BEGIN {
      begin_block = "-----BEGIN AUTOMATIC OPENSLIDES CONFIG-----"
      end_block   = "-----END AUTOMATIC OPENSLIDES CONFIG-----"
      use_server_tmpl = "\tuse-server %s if { ssl_fc_sni_reg -i ^%s$ }"
      if ( www == 1 ) {
        use_server_tmpl = "\tuse-server %s if { ssl_fc_sni_reg -i ^(www\\.)?%s$ }"
      }
      server_tmpl = "\tserver     %s 127.1:%d  weight 0 check"
    }
    $0 ~ begin_block { b = 1 }
    $0 ~ end_block   { e = 1 }
    !e
    b && e {
      printf(use_server_tmpl "\n", target, target)
      printf(server_tmpl "\n", target, port)
      print
      e = 0
    }
  ' /etc/haproxy/haproxy.cfg.osbak >| /etc/haproxy/haproxy.cfg &&
    systemctl reload haproxy
}

rm_from_haproxy_cfg() {
  cp -f /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.osbak &&
  gawk -v target="${PROJECT_NAME}" -v port="${PORT}" '
    BEGIN {
      begin_block = "-----BEGIN AUTOMATIC OPENSLIDES CONFIG-----"
      end_block   = "-----END AUTOMATIC OPENSLIDES CONFIG-----"
    }
    $0 ~ begin_block { b = 1 }
    $0 ~ end_block   { e = 1 }
    b && !e && $2 == target { next }
    1
  ' /etc/haproxy/haproxy.cfg.osbak >| /etc/haproxy/haproxy.cfg &&
    systemctl reload haproxy
}

remove() {
  local PROJECT_NAME="$1"
  [[ -d "$PROJECT_DIR" ]] || {
    fatal "$PROJECT_DIR does not exist."
  }
  echo "Stopping and removing containers..."
  instance_erase
  echo "Removing instance repo dir..."
  rm -rf "${PROJECT_DIR}"
  echo "remove HAProxy config..."
  rm_from_haproxy_cfg
  echo "Done."
}

ping_instance_simple() {
  # Check if the instance's reverse proxy is listening
  #
  # This is used as an indicator as to whether the instance is supposed to be
  # running or not.  The reason for this check is that it is fast and that the
  # reverse proxy container rarely fails itself, so it is always running when
  # an instance has been started.  Errors usually happen in the server
  # container which is checked with ping_instance_websocket.
  nc -z 127.1 "$1" || return 1
}

instance_has_services_running() {
  # Check if the instance has been deployed.
  #
  # This is used as an indicator as to whether the instance is *supposed* to be
  # running or not.
  local instance="$1"
  case "$DEPLOYMENT_MODE" in
    "compose")
      # Check if a network exists
      docker network ls --format '{{ .Name }}' |
        grep -q "^${instance}_" || return 1
      ;;
    "stack")
      docker stack ls --format '{{ .Name }}' | grep -qw "^$instance\$" || return 1
      ;;
  esac
}

ping_instance_websocket() {
  # Connect to OpenSlides and parse its version string
  #
  # This is a way to test the availability of the app.  Most grave errors in
  # OpenSlides lead to this function failing.
  {
    LC_ALL=C curl -s "${CURL_OPTS[@]}" "http://127.0.0.1:${1}/apps/core/version/"
  } | gawk 'BEGIN { FPAT = "\"[^\"]*\"" } { gsub(/"/, "", $2); print $2}' || true
}

value_from_env() {
  local instance target
  instance="$1"
  target="$2"
  [[ -f "${instance}/.env" ]] || return 0
  ( source "${1}/.env" && printf "${!target:-""}" )
}

highlight_match() {
  # Highlight search term match in string
  if [[ -n "$NCOLORS" ]] && [[ -n "$PROJECT_NAME" ]]; then
    sed -e "s/${PROJECT_NAME}/$(tput smso)&$(tput rmso)/g" <<< "$1"
  else
    echo "$1"
  fi
}

ls_instance() {
  local instance="$1"
  local shortname
  local normalized_shortname=

  shortname=$(basename "$instance")

  local user_name=
  local OPENSLIDES_ADMIN_PASSWORD="—"

  [[ -f "${instance}/${CONFIG_FILE}" ]] && [[ -f "${instance}/.env" ]] ||
    fatal "$shortname is not a $DEPLOYMENT_MODE instance."

  #  For stacks, get the normalized shortname
  PROJECT_STACK_NAME="$(value_from_env "$instance" PROJECT_STACK_NAME)"
  [[ -z "${PROJECT_STACK_NAME}" ]] ||
    local normalized_shortname="${PROJECT_STACK_NAME}"

  # Determine instance state
  local port
  local sym="$SYM_UNKNOWN"
  local version=
  port="$(value_from_env "$instance" "EXTERNAL_HTTP_PORT")"
  [[ -n "$port" ]]

  # Check instance deployment state and health
  if ping_instance_simple "$port"; then
    # If we can open a connection to the reverse proxy, the instance has been
    # deployed.
    sym="$SYM_NORMAL"
    version="[skipped]"
    if [[ -z "$OPT_FAST" ]]; then
      # If we can fetch the version string from the app this is an indicator of
      # a fully functional instance.  If we can not, there is a problem.
      version=$(ping_instance_websocket "$port")
      [[ -n "$version" ]] || { sym="$SYM_ERROR"; version=; }
    fi
  else
    # If we can not connect to the reverse proxy, the instance may have been
    # stopped on purpose or there is a problem
    version=
    sym="$SYM_STOPPED"
    if [[ -z "$OPT_FAST" ]] &&
        instance_has_services_running "$normalized_shortname"; then
      # The instance has been deployed but it is unreachable
      version=
      sym="$SYM_ERROR"
    fi
  fi

  # Filter online/offline instances
  case "$FILTER_STATE" in
    online)
      [[ "$sym" = "$SYM_NORMAL" ]] || return 1 ;;
    stopped)
      [[ "$sym" = "$SYM_STOPPED" ]] || return 1 ;;
    error)
      [[ "$sym" = "$SYM_ERROR" ]] || [[ "$sym" = "$SYM_UNKNOWN" ]] || return 1 ;;
    *) ;;
  esac

  # Filter based on comparison with the currently running version (as reported
  # by the Web frontend)
  [[ -z "$FILTER_VERSION" ]] ||
    { [[ "$version" = "$FILTER_VERSION" ]] || return 1; }

  # Parse metadata for first line (used in overview)
  local first_metadatum=
  if [[ -r "${instance}/metadata.txt" ]]; then
    first_metadatum=$(head -1 "${instance}/metadata.txt")
    # Shorten if necessary.  This string will be printed as a column of the
    # general output, so it should not cause linebreaks.  Since the same
    # information will additionally be displayed in the extended output,
    # we can just cut it off here.
    # Ideally, we'd dynamically adjust to how much space is available.
    [[ "${#first_metadatum}" -lt 31 ]] ||
      first_metadatum="${first_metadatum:0:30}…"
    # Tasks for color support
    if [[ -n "$NCOLORS" ]]; then
      # Colors are enabled.  Since metadata.txt may include escape sequences,
      # reset them at the end
      if grep -Fq $'\e' <<< "$first_metadatum"; then
        first_metadatum+="[0m"
      fi
    else
      # Remove all escapes from comment.  This is the simplest method and will
      # leave behind the disabled escape codes.
      first_metadatum="$(echo "$first_metadatum" | tr -d $'\e')"
    fi
  fi

  # Extended parsing
  # ----------------
  # --long
  if [[ -n "$OPT_LONGLIST" ]] || [[ -n "$OPT_JSON" ]]; then
    # Parse docker-compose.yml
    local server_image client_image server_tag client_tag
    local autoupdate_image autoupdate_tag
    server_image="$(value_from_env "$instance" DOCKER_OPENSLIDES_BACKEND_NAME)"
    server_tag="$(value_from_env "$instance" DOCKER_OPENSLIDES_BACKEND_TAG)"
    client_image="$(value_from_env "$instance" DOCKER_OPENSLIDES_FRONTEND_NAME)"
    client_tag="$(value_from_env "$instance" DOCKER_OPENSLIDES_FRONTEND_TAG)"
    server_image="${server_image}:${server_tag}"
    client_image="${client_image}:${client_tag}"
    autoupdate_image="$(value_from_env "$instance" DOCKER_OPENSLIDES_AUTOUPDATE_NAME)"
    autoupdate_tag="$(value_from_env "$instance" DOCKER_OPENSLIDES_AUTOUPDATE_TAG)"
    autoupdate_image="${autoupdate_image}:${autoupdate_tag}"
  fi

  # --secrets
  if [[ -n "$OPT_SECRETS" ]] || [[ -n "$OPT_JSON" ]]; then
    # Parse admin credentials file
    if [[ -r "${instance}/secrets/${ADMIN_SECRETS_FILE}" ]]; then
      source "${instance}/secrets/${ADMIN_SECRETS_FILE}"
    fi
    # Parse user credentials file
    if [[ -r "${instance}/secrets/${USER_SECRETS_FILE}" ]]; then
      local OPENSLIDES_USER_FIRSTNAME=
      local OPENSLIDES_USER_LASTNAME=
      local OPENSLIDES_USER_PASSWORD=
      local OPENSLIDES_USER_EMAIL=
      source "${instance}/secrets/${USER_SECRETS_FILE}"
      if [[ -n "${OPENSLIDES_USER_FIRSTNAME}" ]] &&
          [[ -n "${OPENSLIDES_USER_LASTNAME}" ]]; then
        user_name="${OPENSLIDES_USER_FIRSTNAME} ${OPENSLIDES_USER_LASTNAME}"
      fi
    fi
  fi

  # --metadata
  local metadata=()
  if [[ -n "$OPT_METADATA" ]] || [[ -n "$OPT_JSON" ]]; then
    if [[ -r "${instance}/metadata.txt" ]]; then
      # Parse metadata file for use in long output
      readarray -t metadata < <(grep -v '^\s*#' "${instance}/metadata.txt")
    fi
  fi

  # --image-info
  local server_image_info= client_image_info=
  if [[ -n "$OPT_IMAGE_INFO" ]] || [[ -n "$OPT_JSON" ]]; then
    if [[ -n "$version" ]]; then
      server_image_info="$(curl -s "http://127.1:${port}/server-version.txt")"
      [[ "$server_image_info" =~ built\ on ]] || server_image_info=
      client_image_info="$(curl -s "http://127.1:${port}/client-version.txt")"
      [[ "$client_image_info" =~ built\ on ]] || client_image_info=
    fi
  fi

  # Output
  # ------
  # JSON
  if [[ -n "$OPT_JSON" ]]; then
    # Purposefully not using $JQ here because the output may get piped into
    # another jq process
    jq -n \
      --arg "shortname"     "$shortname" \
      --arg "stackname"     "$normalized_shortname" \
      --arg "directory"     "$instance" \
      --arg "version"       "$version" \
      --arg "instance"      "$instance" \
      --arg "version"       "$version" \
      --arg "status"        "$sym" \
      --arg "server_image"  "$server_image" \
      --arg "client_image"  "$client_image" \
      --arg "autoupdate_image" "$autoupdate_image" \
      --arg "port"          "$port" \
      --arg "admin"         "$OPENSLIDES_ADMIN_PASSWORD" \
      --arg "user_name"     "$user_name" \
      --arg "user_password" "$OPENSLIDES_USER_PASSWORD" \
      --arg "user_email"    "$OPENSLIDES_USER_EMAIL" \
      --arg "metadata"      "$(printf "%s\n" "${metadata[@]}")" \
      --arg "server_image_info" "$server_image_info" \
      --arg "client_image_info" "$client_image_info" \
      '{
        instances: [
          {
            name:      $shortname,
            stackname: $stackname,
            directory: $instance,
            version:   $version,
            status:    $status,
            server_image: $server_image,
            client_image: $client_image,
            autoupdate_image: $autoupdate_image,
            port:      $port,
            admin:     $admin,
            user: {
              user_name:    $user_name,
              user_password: $user_password,
              user_email: $user_email
            },
            metadata: $metadata,
            server_image_info: $server_image_info,
            client_image_info: $client_image_info
          }
        ]
      }'
    return
  fi

  # Basic output
  if [[ -z "$OPT_LONGLIST" ]] && [[ -z "$OPT_METADATA" ]] && [[ -z "$OPT_IMAGE_INFO" ]]
  then
    printf "%s %-30s\t%-10s\t%s\n" "$sym" "$shortname" "$version" "$first_metadatum"
  else
    # Hide details if they are going to be included in the long output format
    printf "%s %-30s\n" "$sym" "$shortname"
  fi

  # Additional output
  if [[ -n "$OPT_LONGLIST" ]]; then
    printf "   ├ %-17s %s\n" "Directory:" "$instance"
    if [[ -n "$normalized_shortname" ]]; then
      printf "   ├ %-17s %s\n" "Stack name:" "$normalized_shortname"
    fi
    printf "   ├ %-17s %s\n" "Version:" "$version"
    printf "   ├ %-17s %s\n" "Server image:" "$server_image"
    printf "   ├ %-17s %s\n" "Client image:" "$client_image"
    printf "   ├ %-17s %s\n" "Autoupdate image:" "$autoupdate_image"
    printf "   ├ %-17s %s\n" "Local port:" "$port"
  fi

  # --secrets
  if [[ -n "$OPT_SECRETS" ]]; then
    printf "   ├ %-17s %s : %s\n" "Login:" "admin" "$OPENSLIDES_ADMIN_PASSWORD"
    # Include secondary account credentials if available
    [[ -n "$user_name" ]] &&
      printf "   ├ %-17s \"%s\" : %s\n" \
        "Login:" "$user_name" "$OPENSLIDES_USER_PASSWORD"
    [[ -n "$OPENSLIDES_USER_EMAIL" ]] &&
      printf "   ├ %-17s %s\n" "Contact:" "$OPENSLIDES_USER_EMAIL"
  fi

  # --metadata
  if [[ ${#metadata[@]} -ge 1 ]]; then
    printf "   └ %s\n" "Metadata:"
    for m in "${metadata[@]}"; do
      m=$(highlight_match "$m") # Colorize match in metadata
      printf "     ┆ %s\n" "$m"
    done
  fi

  # --image-info
  if [[ -n "$server_image_info" ]]; then
    printf "   └ %s\n" "Server image info:"
    echo "${server_image_info}" | sed 's/^/     ┆ /'
  fi
  if [[ -n "$client_image_info" ]]; then
    printf "   └ %s\n" "Client image info:"
    echo "${client_image_info}" | sed 's/^/     ┆ /'
  fi
}

colorize_ls() {
  # Colorize the status indicators
  if [[ -n "$NCOLORS" ]] && [[ -z "$OPT_JSON" ]]; then
    # XXX: 2>/dev/null is used here to hide warnings such as
    # gawk: warning: escape sequence `\.' treated as plain `.'
    gawk 2>/dev/null \
      -v m="$PROJECT_NAME" \
      -v hlstart="$(tput smso)" \
      -v hlstop="$(tput rmso)" \
      -v bullet="${BULLET}" \
      -v normal="${COL_NORMAL}" \
      -v green="${COL_GREEN}" \
      -v yellow="${COL_YELLOW}" \
      -v gray="${COL_GRAY}" \
      -v red="${COL_RED}" \
    'BEGIN {
      FPAT = "([[:space:]]*[^[:space:]]+)"
      OFS = ""
      IGNORECASE = 1
    }
    # highlight matches in instance name
    /^[^ ]/ { gsub(m, hlstart "&" hlstop, $2) }
    # highlight matches in metadata
    $1 ~ /[[:space:]]+┆/ { gsub(m, hlstart "&" hlstop, $0) }
    # bullets
    /^OK/   { $1 = " " green  bullet normal }
    /^\?\?/ { $1 = " " yellow bullet normal }
    /^XX/   { $1 = " " red    bullet normal }
    /^__/   { $1 = " " gray   bullet normal }
    1'
  else
    cat -
  fi
}

list_instances() {
  # Find instances and filter based on search term.
  # PROJECT_NAME is used as a grep -E search pattern here.
  local i=()
  local j=()
  readarray -d '' i < <(
    find "${INSTANCES}" -mindepth 1 -maxdepth 1 -type d -print0 |
    sort -z
  )
  for instance in "${i[@]}"; do
    # skip directories that aren't instances
    [[ -f "${instance}/${CONFIG_FILE}" ]] && [[ -f "${instance}/.env" ]] || continue

    # Filter instances
    # 1. instance name/project dir matches (case-insensitive)
    if grep -i -E -q "$PROJECT_NAME" <<< "$(basename "$instance")"; then :
    # 2. metadata matches (case-insensitive)
    elif [[ -n "$OPT_METADATA_SEARCH" ]] && [[ -f "${instance}/metadata.txt" ]] &&
      grep -i -E -q "$PROJECT_NAME" "${instance}/metadata.txt"; then :
    else
      continue
    fi

    j+=("$instance")
  done

  # return here if no matches
  [[ "${#j[@]}" -ge 1 ]] || return

  merge_if_json() {
    if [[ -n "$OPT_JSON" ]]; then
      $JQ -s '{ instances: map(.instances[0]) }'
    else
      cat -
    fi
  }

  # list instances, either one by one or in parallel
  if [[ $OPT_USE_PARALLEL -ne 0 ]]; then
    env_parallel --no-notice --keep-order ls_instance ::: "${j[@]}"
  else
    for instance in "${j[@]}"; do
      ls_instance "$instance" || continue
    done
  fi | colorize_ls | column -ts $'\t' | merge_if_json
}

clone_secrets() {
  if [[ -d "${CLONE_FROM_DIR}/secrets/" ]]; then
    rsync -axv "${CLONE_FROM_DIR}/secrets/" "${PROJECT_DIR}/secrets/"
  fi
}

containerid_from_service_name() {
  local id
  local cid
  id="$(docker service ps -q --filter desired-state=running "$1")"
  [[ -n "$id" ]] ||
    fatal "Service $1 not found.  Make sure it is running."
  cid="$(docker inspect -f '{{.Status.ContainerStatus.ContainerID}}' "${id}")"
  echo "$cid"
}

get_clone_from_id() (
  PROJECT_STACK_NAME="$(value_from_env "${1}" PROJECT_STACK_NAME)"
  containerid_from_service_name "${PROJECT_STACK_NAME}_${PRIMARY_DATABASE_NODE}"
)

clone_db() {
  local clone_from_id
  local clone_to_id
  local available_dbs
  local port
  case "$DEPLOYMENT_MODE" in
    "compose")
      local clone_from_id
      local clone_to_id
      _docker_compose "$PROJECT_DIR" up -d --no-deps pgnode1
      clone_from_id="$(_docker_compose "$CLONE_FROM_DIR" ps -q "${PRIMARY_DATABASE_NODE}")"
      clone_to_id="$(_docker_compose "$PROJECT_DIR" ps -q pgnode1)"
      until _docker_compose "$PROJECT_DIR" exec -T pgnode1 pg_isready -q -p 5432
      do
        echo "Waiting for Postgres cluster to become available."
        sleep 5
      done
      ;;
    "stack")
      clone_from_id="$(get_clone_from_id "$CLONE_FROM_DIR")"
      PROJECT_STACK_NAME="$(value_from_env "${PROJECT_DIR}" PROJECT_STACK_NAME)"
      port="$(value_from_env "${PROJECT_DIR}" EXTERNAL_HTTP_PORT)"
      # Unlike in Compose mode, the complete instance is booted up.  For this
      # reason, we will also wait for the complete instance to become ready and
      # then shut down services that may access the database.
      instance_start
      until [[ -n "$(ping_instance_websocket "$port")" ]]; do
        echo "Waiting for new instance to become available."
        sleep 5
      done
      clone_to_id="$(containerid_from_service_name "${PROJECT_STACK_NAME}_pgnode1")"

      echo "Shutting down other services."
      docker service rm "${PROJECT_STACK_NAME}_pgbouncer"
      docker service rm "${PROJECT_STACK_NAME}_server-setup"
      docker service rm "${PROJECT_STACK_NAME}_server"
      docker service rm "${PROJECT_STACK_NAME}_media"
      ;;
  esac
  echo "DEBUG: from: $clone_from_id to: $clone_to_id"

  # Clone instance databases individually using pg_dump
  #
  # pg_dump's advantage is that it requires no special access (unlike
  # pg_dumpall) and does not require the cluster to be reinitialized (unlike
  # pg_basebackup).
  #
  # It is assumed that the originating database service is pgnode1.  If you
  # need to clone from a different node, change the PRIMARY_DATABASE_NODE
  # variable.  The PgBouncer service is not an option because it does not have
  # the required superuser access to the cluster.
  #
  # The pg_dump/psql method may very well run into issues with large mediafile
  # databases, however.  pg_dump/pg_restore using the custom format could be
  # worth a try.
  available_dbs=("$(docker exec -u postgres "$clone_from_id" \
    psql -d openslides -c '\l' -AtF '	' | cut -f1)")
  for db in openslides instancecfg mediafiledata; do
    echo "${available_dbs[@]}" | grep -wq "$db" || {
      echo "DB $db not found; skipping..."
      sleep 10
      continue
    }
    until [[ "$(docker exec -u postgres "$clone_to_id" \
      psql -qAt -c "select count(*) from pg_stat_activity WHERE datname='${db}';")" -eq 0 ]]
    do
      echo "DEBUG: Terminate connections to $db."
      docker exec -u postgres "$clone_to_id" psql -q -c "SELECT pg_terminate_backend(pid)
          FROM pg_stat_activity WHERE datname='${db}';"
      sleep 5
    done
    echo "Recreating db for new instance: ${db}..."
    docker exec -u postgres "$clone_to_id" dropdb --if-exists "$db"
    docker exec -u postgres "$clone_to_id" createdb -O openslides "$db"

    echo "Cloning ${db}..."
    docker exec -u postgres "$clone_from_id" \
      pg_dump -c --if-exists "$db" |
    docker exec -u postgres -i "$clone_to_id" psql "$db"
  done
}

append_metadata() {
  local m="${1}/metadata.txt"
  touch "$m"
  shift
  printf "%s\n" "$*" >> "$m"
}

ask_start() {
  local start=
  read -rp "Start the instance? [Y/n] " start
  case "$start" in
    Y|y|Yes|yes|YES|"")
      instance_start ;;
    *)
      echo "Not starting instance." ;;
  esac
}

instance_start() {
  check_config_compatibility
  # Write YAML config
  ( set -a  && source "${PROJECT_DIR}/.env" &&
    m4 -DPROJECT_DIR="$PROJECT_DIR" "$DCCONFIG_TEMPLATE" >| "${DCCONFIG}" )
  case "$DEPLOYMENT_MODE" in
    "compose")
      _docker_compose "$PROJECT_DIR" build
      _docker_compose "$PROJECT_DIR" up -d
      ;;
    "stack")
      PROJECT_STACK_NAME="$(value_from_env "${PROJECT_DIR}" PROJECT_STACK_NAME)"
      docker stack deploy -c "${PROJECT_DIR}/docker-stack.yml" \
        "$PROJECT_STACK_NAME"
      ;;
  esac
}

instance_stop() {
  case "$DEPLOYMENT_MODE" in
    "compose")
      _docker_compose "$PROJECT_DIR" down
      ;;
    "stack")
      PROJECT_STACK_NAME="$(value_from_env "${PROJECT_DIR}" PROJECT_STACK_NAME)"
      docker stack rm "$PROJECT_STACK_NAME"
    ;;
esac
}

instance_erase() {
  case "$DEPLOYMENT_MODE" in
    "compose")
      _docker_compose "$PROJECT_DIR" down --volumes
      ;;
    "stack")
      local vol=()
      instance_stop || true
      run_hook mid-erase
      readarray -t vol < <(
        docker volume ls --format '{{ .Name }}' |
        grep "^${PROJECT_STACK_NAME}_"
      )
      if [[ "${#vol[@]}" -gt 0 ]]; then
        echo "Please manually verify and remove the instance's volumes:"
        for i in "${vol[@]}"; do
          echo "  docker volume rm $i"
        done
        echo "WARN: Please note that $ME does not take volumes" \
          "on other nodes into account."
      fi
      ;;
  esac
}

instance_update() {
  local server_changed= client_changed=
  local autoupdate_changed=
  # Update values in .env
  # Backend
  if [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]]; then
    update_env_file "${PROJECT_DIR}/.env" \
      "DOCKER_OPENSLIDES_BACKEND_NAME" "$DOCKER_IMAGE_NAME_OPENSLIDES" --force
    server_changed=1
  fi
  if [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]]; then
    update_env_file "${PROJECT_DIR}/.env" \
      "DOCKER_OPENSLIDES_BACKEND_TAG" "$DOCKER_IMAGE_TAG_OPENSLIDES" --force
    server_changed=1
  fi
  # Frontend
  if [[ -n "$DOCKER_IMAGE_NAME_CLIENT" ]]; then
    update_env_file "${PROJECT_DIR}/.env" \
      "DOCKER_OPENSLIDES_FRONTEND_NAME" "$DOCKER_IMAGE_NAME_CLIENT" --force
    client_changed=1
  fi
  if [[ -n "$DOCKER_IMAGE_TAG_CLIENT" ]]; then
    update_env_file "${PROJECT_DIR}/.env" \
      "DOCKER_OPENSLIDES_FRONTEND_TAG" "$DOCKER_IMAGE_TAG_CLIENT" --force
    client_changed=1
  fi
  # Autoupdate
  if [[ -n "$DOCKER_IMAGE_NAME_AUTOUPDATE" ]]; then
    update_env_file "${PROJECT_DIR}/.env" \
      "DOCKER_OPENSLIDES_AUTOUPDATE_NAME" "$DOCKER_IMAGE_NAME_AUTOUPDATE" --force
    autoupdate_changed=1
  fi
  if [[ -n "$DOCKER_IMAGE_TAG_AUTOUPDATE" ]]; then
    update_env_file "${PROJECT_DIR}/.env" \
      "DOCKER_OPENSLIDES_AUTOUPDATE_TAG" "$DOCKER_IMAGE_TAG_AUTOUPDATE" --force
    autoupdate_changed=1
  fi

  # Start/update if instance was already running
  source "${PROJECT_DIR}/.env"

  # Metadata
  if [[ "$server_changed" ]]; then
    append_metadata "$PROJECT_DIR" "$(date +"%F %H:%M"): Updated server to" \
      "${DOCKER_IMAGE_NAME_OPENSLIDES}:${DOCKER_IMAGE_TAG_OPENSLIDES}"
  fi
  if [[ -n "$client_changed" ]]; then
    append_metadata "$PROJECT_DIR" "$(date +"%F %H:%M"): Updated client to" \
      "${DOCKER_IMAGE_NAME_CLIENT}:${DOCKER_IMAGE_TAG_CLIENT}"
  fi
  if [[ -n "$autoupdate_changed" ]]; then
    append_metadata "$PROJECT_DIR" "$(date +"%F %H:%M"): Updated autoupdate to" \
      "${DOCKER_IMAGE_NAME_AUTOUPDATE}:${DOCKER_IMAGE_TAG_AUTOUPDATE}"
  fi

  instance_has_services_running "$PROJECT_STACK_NAME" || {
    echo "WARN: ${PROJECT_NAME} is not running."
    echo "      The configuration has been updated and the instance will" \
         "be upgraded upon its next start."
    return 0
  }

  case "$DEPLOYMENT_MODE" in
    "compose")
      echo "Creating services"
      _docker_compose "$PROJECT_DIR" up -d
      ;;
    "stack")
      # Set missing variables from currently running service
      # Backend
      if [[ -z "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] && [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]]; then
        DOCKER_IMAGE_NAME_OPENSLIDES="$(docker service inspect \
          -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
          "$PROJECT_STACK_NAME"_server |
          gawk -F '[:@]' '{ print $1 }')"
      elif [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] && [[ -z "$DOCKER_IMAGE_TAG_OPENSLIDES" ]]; then
        DOCKER_IMAGE_TAG_OPENSLIDES="$(docker service inspect \
          -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
          "$PROJECT_STACK_NAME"_server |
          gawk -F '[:@]' '{ print $2 }')"
      fi
      # Frontend
      if [[ -z "$DOCKER_IMAGE_NAME_CLIENT" ]] && [[ -n "$DOCKER_IMAGE_TAG_CLIENT" ]]; then
        DOCKER_IMAGE_NAME_CLIENT="$(docker service inspect \
          -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
          "$PROJECT_STACK_NAME"_client |
          gawk -F '[:@]' '{ print $1 }')"
      elif [[ -n "$DOCKER_IMAGE_NAME_CLIENT" ]] && [[ -z "$DOCKER_IMAGE_TAG_CLIENT" ]]; then
        DOCKER_IMAGE_TAG_CLIENT="$(docker service inspect \
          -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
          "$PROJECT_STACK_NAME"_client |
          gawk -F '[:@]' '{ print $2 }')"
      fi
      # Autoupdate
      if [[ -z "$DOCKER_IMAGE_NAME_AUTOUPDATE" ]] && [[ -n "$DOCKER_IMAGE_TAG_AUTOUPDATE" ]]; then
        DOCKER_IMAGE_NAME_AUTOUPDATE="$(docker service inspect \
          -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
          "$PROJECT_STACK_NAME"_autoupdate |
          gawk -F '[:@]' '{ print $1 }')"
      elif [[ -n "$DOCKER_IMAGE_NAME_AUTOUPDATE" ]] && [[ -z "$DOCKER_IMAGE_TAG_AUTOUPDATE" ]]; then
        DOCKER_IMAGE_TAG_AUTOUPDATE="$(docker service inspect \
          -f '{{.Spec.TaskTemplate.ContainerSpec.Image}}' \
          "$PROJECT_STACK_NAME"_autoupdate |
          gawk -F '[:@]' '{ print $2 }')"
      fi

      # Update services
      # ---------------
      # Backend
      if [[ "$server_changed" ]]; then
        for i in server-setup server; do
          docker service update --image \
            "${DOCKER_IMAGE_NAME_OPENSLIDES}:${DOCKER_IMAGE_TAG_OPENSLIDES}" \
            "${PROJECT_STACK_NAME}_${i}"
        done
      fi
      # Frontend
      if [[ "$client_changed" ]]; then
        docker service update --image \
          "${DOCKER_IMAGE_NAME_CLIENT}:${DOCKER_IMAGE_TAG_CLIENT}" \
          "${PROJECT_STACK_NAME}_client"
      fi
      # Autoupdate
      if [[ "$autoupdate_changed" ]]; then
        docker service update --image \
          "${DOCKER_IMAGE_NAME_AUTOUPDATE}:${DOCKER_IMAGE_TAG_AUTOUPDATE}" \
          "${PROJECT_STACK_NAME}_autoupdate"
      fi
      ;;
  esac
}

run_hook() (
  local hook hook_name
  [[ -d "$HOOKS_DIR" ]] || return 0
  hook_name="$1"
  hook="${HOOKS_DIR}/${hook_name}"
  shift
  if [[ -x "$hook" ]]; then
    cd "$PROJECT_DIR"
    echo "INFO: Running $hook_name hook..."
    set +eu
    . "$hook"
    set -eu
  fi
  )


# Decide mode from invocation
case "$(basename "${BASH_SOURCE[0]}")" in
  "osinstancectl" | "osinstancectl.sh")
    DEPLOYMENT_MODE=compose
    ;;
  "osstackctl" | "osstackctl.sh")
    DEPLOYMENT_MODE=stack
    ;;
  *)
    echo "WARNING: could not determine desired deployment mode;" \
      " assuming 'compose'"
    DEPLOYMENT_MODE=compose
    ;;
esac

shortopt="halsjmiMnfed:t:"
longopt=(
  help
  color:
  long
  secrets
  json
  project-dir:
  force

  # Template opions
  yaml-template:
  env-template:

  # filtering
  all
  online
  offline
  error
  metadata
  image-info
  fast
  patient
  search-metadata
  version:

  # adding instances
  clone-from:
  local-only
  no-add-account
  www

  # adding & upgrading instances
  server-image:
  server-tag:
  backend-image:
  backend-tag:
  client-image:
  client-tag:
  frontend-image:
  frontend-tag:
  autoupdate-image:
  autoupdate-tag:
  all-tags:
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
fi

# Parse options
while true; do
  case "$1" in
    -d|--project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --yaml-template)
      YAML_TEMPLATE="$2"
      shift 2
      ;;
    --env-template)
      DOT_ENV_TEMPLATE="$2"
      shift 2
      ;;
    --server-image | --backend-image)
      DOCKER_IMAGE_NAME_OPENSLIDES="$2"
      shift 2
      ;;
    --server-tag | --backend-tag)
      DOCKER_IMAGE_TAG_OPENSLIDES="$2"
      shift 2
      ;;
    --client-image | frontend-image)
      DOCKER_IMAGE_NAME_CLIENT="$2"
      shift 2
      ;;
    --client-tag | frontend-tag)
      DOCKER_IMAGE_TAG_CLIENT="$2"
      shift 2
      ;;
    --autoupdate-image)
      DOCKER_IMAGE_NAME_AUTOUPDATE="$2"
      shift 2
      ;;
    --autoupdate-tag)
      DOCKER_IMAGE_TAG_AUTOUPDATE="$2"
      shift 2
      ;;
    -t|--all-tags)
      DOCKER_IMAGE_TAG_OPENSLIDES="$2"
      DOCKER_IMAGE_TAG_CLIENT="$2"
      DOCKER_IMAGE_TAG_AUTOUPDATE="$2"
      shift 2
      ;;
    --no-add-account)
      OPT_ADD_ACCOUNT=
      shift 1
      ;;
    -a|--all)
      OPT_LONGLIST=1
      OPT_METADATA=1
      OPT_IMAGE_INFO=1
      OPT_SECRETS=1
      shift 1
      ;;
    -l|--long)
      OPT_LONGLIST=1
      shift 1
      ;;
    -s|--secrets)
      OPT_SECRETS=1
      shift 1
      ;;
    -m|--metadata)
      OPT_METADATA=1
      shift 1
      ;;
    -M|--search-metadata)
      OPT_METADATA_SEARCH=1
      shift 1
      ;;
    -i|--image-info)
      OPT_IMAGE_INFO=1
      shift 1
      ;;
    -j|--json)
      OPT_JSON=1
      shift 1
      ;;
    -n|--online)
      FILTER_STATE="online"
      shift 1
      ;;
    -f|--offline)
      FILTER_STATE="stopped"
      shift 1
      ;;
    -e|--error)
      FILTER_STATE="error"
      shift 1
      ;;
    --version)
      FILTER_VERSION="$2"
      shift 2
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
    --fast)
      OPT_FAST=1
      OPT_PATIENT=
      shift 1
      ;;
    --patient)
      OPT_PATIENT=1
      OPT_USE_PARALLEL=0
      OPT_FAST=
      CURL_OPTS=(--max-time 60 --retry 5 --retry-delay 1 --retry-max-time 0)
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
    update)
      [[ -z "$MODE" ]] || { usage; exit 2; }
      MODE=update
      [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] ||
          [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]] ||
          [[ -n "$DOCKER_IMAGE_NAME_CLIENT" ]] ||
          [[ -n "$DOCKER_IMAGE_TAG_CLIENT" ]] ||
          [[ -n "$DOCKER_IMAGE_NAME_AUTOUPDATE" ]] ||
          [[ -n "$DOCKER_IMAGE_TAG_AUTOUPDATE" ]] || {
        fatal "Need at least one image name or tag for update"
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

# Use GNU parallel if found
if [[ "$OPT_USE_PARALLEL" -ne 0 ]] && [[ -f /usr/bin/env_parallel.bash ]]; then
  source /usr/bin/env_parallel.bash
  OPT_USE_PARALLEL=1
fi

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
  gawk
  jq
  m4
  nc
)
case "$DEPLOYMENT_MODE" in
  "compose")
    DEPS+=(docker-compose)
    ;;
esac
# Check dependencies
for i in "${DEPS[@]}"; do
    check_for_dependency "$i"
done

# PROJECT_NAME should be lower-case
PROJECT_NAME="$(echo "$PROJECT_NAME" | tr '[A-Z]' '[a-z]')"

# Prevent --project-dir to be used together with a project name
if [[ -n "$PROJECT_DIR" ]] && [[ -n "$PROJECT_NAME" ]]; then
  fatal "Mutually exclusive options"
fi
# Deduce project name from path
if [[ -n "$PROJECT_DIR" ]]; then
  PROJECT_NAME="$(basename "$(readlink -f "$PROJECT_DIR")")"
  OPT_METADATA_SEARCH=
# Treat the project name "." as --project-dir=.
elif [[ "$PROJECT_NAME" = "." ]]; then
  PROJECT_NAME="$(basename "$(readlink -f "$PROJECT_NAME")")"
  PROJECT_DIR="${INSTANCES}/${PROJECT_NAME}"
  OPT_METADATA_SEARCH=
  # Signal that the project name is based on the directory and could be
  # transformed into a more precise regexp internally:
  OPT_PRECISE_PROJECT_NAME=1
else
  PROJECT_DIR="${INSTANCES}/${PROJECT_NAME}"
fi

# The project name is a valid domain which is not suitable as a Docker
# stack name.  Here, we remove all dots from the domain which turns the
# domain into a compatible name.  This also appears to be the method
# docker-compose uses to name its containers, networks, etc.
PROJECT_STACK_NAME="$(echo "$PROJECT_NAME" | tr -d '.')"

case "$DEPLOYMENT_MODE" in
  "compose")
    CONFIG_FILE="docker-compose.yml"
    ;;
  "stack")
    CONFIG_FILE="docker-stack.yml"
    ;;
esac
DCCONFIG="${PROJECT_DIR}/${CONFIG_FILE}"

# If a template repo exists as a local worktree, copy files from there;
# otherwise, clone a repo and use its included files as templates
if [[ -d "${TEMPLATE_REPO}" ]]; then
  DEFAULT_DCCONFIG_TEMPLATE="${TEMPLATE_REPO}/docker/${CONFIG_FILE}.m4"
  DEFAULT_DOT_ENV_TEMPLATE="${TEMPLATE_REPO}/docker/.env"
else
  DEFAULT_DCCONFIG_TEMPLATE="${PROJECT_DIR}/docker/${CONFIG_FILE}.m4"
  DEFAULT_DOT_ENV_TEMPLATE="${PROJECT_DIR}/docker/.env"
fi
# Override default settings from either the config file or command-line options
DCCONFIG_TEMPLATE="${YAML_TEMPLATE:-${DEFAULT_DCCONFIG_TEMPLATE}}"
DOT_ENV_TEMPLATE="${DOT_ENV_TEMPLATE:-${DEFAULT_DOT_ENV_TEMPLATE}}"

case "$MODE" in
  remove)
    arg_check || { usage; exit 2; }
    [[ -n "$OPT_FORCE" ]] || marker_check
    # Ask for confirmation
    ANS=
    echo "Delete the following instance including all of its data and configuration?"
    # Show instance listing
    OPT_LONGLIST=1 OPT_METADATA=1 OPT_METADATA_SEARCH= \
      ls_instance "$PROJECT_DIR" | colorize_ls
    echo
    read -rp "Really delete? (uppercase YES to confirm) " ANS
    [[ "$ANS" = "YES" ]] || exit 0
    remove "$PROJECT_NAME"
    ;;
  create)
    [[ -f "$CONFIG" ]] && echo "Applying options from ${CONFIG}." || true
    arg_check || { usage; exit 2; }
    check_config_compatibility
    # Use defaults in the absence of options
    query_user_account_name
    echo "Creating new instance: $PROJECT_NAME"
    PORT=$(next_free_port)
    create_instance_dir
    create_config_from_template
    create_admin_secrets_file
    create_user_secrets_file "${OPENSLIDES_USER_FIRSTNAME}" \
      "${OPENSLIDES_USER_LASTNAME}" "${OPENSLIDES_USER_EMAIL}"
    create_django_secrets_file
    append_metadata "$PROJECT_DIR" ""
    append_metadata "$PROJECT_DIR" \
      "$(date +"%F %H:%M"): Instance created (${DEPLOYMENT_MODE})"
    [[ -z "$OPT_LOCALONLY" ]] ||
      append_metadata "$PROJECT_DIR" "No HAProxy config added (--local-only)"
    add_to_haproxy_cfg
    run_hook "post-${MODE}"
    ask_start
    ;;
  clone)
    CLONE_FROM_DIR="${INSTANCES}/${CLONE_FROM}"
    arg_check || { usage; exit 2; }
    echo "Creating new instance: $PROJECT_NAME (based on $CLONE_FROM)"
    PORT=$(next_free_port)
    DEFAULT_DOCKER_REGISTRY="$(value_from_env "$CLONE_FROM_DIR" DEFAULT_DOCKER_REGISTRY)"
    # Parse image and/or tag from original config if necessary
    [[ -n "$DOCKER_IMAGE_NAME_OPENSLIDES" ]] ||
      DOCKER_IMAGE_NAME_OPENSLIDES="$(value_from_env "$CLONE_FROM_DIR" DOCKER_OPENSLIDES_BACKEND_NAME)"
    [[ -n "$DOCKER_IMAGE_TAG_OPENSLIDES" ]] ||
      DOCKER_IMAGE_TAG_OPENSLIDES="$(value_from_env "$CLONE_FROM_DIR" DOCKER_OPENSLIDES_BACKEND_TAG)"
    [[ -n "$DOCKER_IMAGE_NAME_CLIENT" ]] ||
      DOCKER_IMAGE_NAME_CLIENT="$(value_from_env "$CLONE_FROM_DIR" DOCKER_OPENSLIDES_FRONTEND_NAME)"
    [[ -n "$DOCKER_IMAGE_TAG_CLIENT" ]] ||
      DOCKER_IMAGE_TAG_CLIENT="$(value_from_env "$CLONE_FROM_DIR" DOCKER_OPENSLIDES_FRONTEND_TAG)"
    [[ -n "$DOCKER_IMAGE_NAME_AUTOUPDATE" ]] ||
      DOCKER_IMAGE_NAME_AUTOUPDATE="$(value_from_env "$CLONE_FROM_DIR" DOCKER_OPENSLIDES_AUTOUPDATE_NAME)"
    [[ -n "$DOCKER_IMAGE_TAG_AUTOUPDATE" ]] ||
      DOCKER_IMAGE_TAG_AUTOUPDATE="$(value_from_env "$CLONE_FROM_DIR" DOCKER_OPENSLIDES_AUTOUPDATE_TAG)"
    create_instance_dir
    create_config_from_template
    clone_secrets
    clone_db
    instance_stop # to force pgnode1 to be restarted
    append_metadata "$PROJECT_DIR" ""
    append_metadata "$PROJECT_DIR" "Cloned from $CLONE_FROM on $(date)"
    [[ -z "$OPT_LOCALONLY" ]] ||
      append_metadata "$PROJECT_DIR" "No HAProxy config added (--local-only)"
    add_to_haproxy_cfg
    run_hook "post-${MODE}"
    ask_start
    ;;
  list)
    [[ -z "$OPT_PRECISE_PROJECT_NAME" ]] || PROJECT_NAME="^${PROJECT_NAME}$"
    list_instances
    ;;
  start)
    arg_check || { usage; exit 2; }
    instance_start
    run_hook "post-${MODE}"
    ;;
  stop)
    arg_check || { usage; exit 2; }
    instance_stop
    run_hook "post-${MODE}"
    ;;
  erase)
    arg_check || { usage; exit 2; }
    # Ask for confirmation
    ANS=
    echo "Stop the following instance, and remove its containers and volumes?"
    # Show instance listing
    OPT_LONGLIST=1 OPT_METADATA=1 OPT_METADATA_SEARCH= \
      ls_instance "$PROJECT_DIR" | colorize_ls
    echo
    read -rp "Really delete? (uppercase YES to confirm) " ANS
    [[ "$ANS" = "YES" ]] || exit 0
    instance_erase
    ;;
  update)
    [[ -f "$CONFIG" ]] && echo "Applying options from ${CONFIG}." || true
    arg_check || { usage; exit 2; }
    instance_update
    run_hook "post-${MODE}"
    ;;
  *)
    fatal "Missing command.  Please consult $ME --help."
    ;;
esac
