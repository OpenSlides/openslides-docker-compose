#!/bin/bash

set -e

usage() {
  cat << EOF
Usage: ${BASH_SOURCE[0]} <instance directory>

This script can be used to migrate instances to the new, .env-only
configuration setup.

It retrieves the settings.py file from the database, extracts relevant
configuration, and appends it to .env.  Additionally, Django's secret key is
copied to ./secrets/django.env.  (Courtesy of convert.py.)

If SAML was configured, its configuration is copied to the instance's
./secrets/saml/ directory.
EOF
}

get_file() {
  docker exec -u postgres "$CONTAINERID" \
    psql -d instancecfg -qtA -c "
      SELECT DISTINCT ON (filename) data FROM files
        WHERE filename = '$1'
        ORDER BY filename, id DESC;
        " | xxd -r -p
}

CONVERTPY="$(realpath "$(dirname "${BASH_SOURCE[0]}")/convert.py")"
[[ -f "$CONVERTPY" ]] || {
  echo "ERROR: Dependency $CONVERTPY not found."
  exit 3
}

[[ $# -eq 1 ]] || { usage; exit 2; }

INSTANCE="$(realpath -- "$1")"

[[ -d "$INSTANCE" ]] || { usage; exit 4; }
[[ -f "${INSTANCE}/.env" ]] || { usage; exit 5; }

cd "$INSTANCE"
. .env

TASK_ID="$(docker service ps --filter "desired-state=running" \
  --format '{{.ID}}' "${PROJECT_STACK_NAME}_pgnode1")"
CONTAINERID="$(docker inspect \
  -f '{{.Status.ContainerStatus.ContainerID}}' ${TASK_ID})"

[[ -n "$CONTAINERID" ]] || {
  echo "ERROR: Could not find database container."
  exit 6
}

echo "Converting settings.py to .env."
get_file /app/personal_data/var/settings.py > "${INSTANCE}/settings.py"
echo "
# OpenSlides Backend settings (settings.py)
# -----------------------------------------" >> "${INSTANCE}/.env"
python3 "$CONVERTPY"

# SAML
. .env
[[ "$ENABLE_SAML" = True ]] || exit 0
echo "Retrieving SAML configuration."
mkdir -p "${INSTANCE}/secrets/saml"
get_file /app/personal_data/var/saml_settings.json > \
  "${INSTANCE}/secrets/saml/saml_settings.json"
get_file /app/personal_data/var/certs/sp.crt > \
  "${INSTANCE}/secrets/saml/sp.crt"
get_file /app/personal_data/var/certs/sp.key > \
  "${INSTANCE}/secrets/saml/sp.key"
