#!/bin/bash

set -e

TARBALL="export.tar.gz"

cleanup() { rm -f openslides.sql mediafiledata.sql instancecfg.sql; }
trap cleanup EXIT

usage() {
cat << EOF
Usage: ${BASH_SOURCE[0]} <instance directory>

  This script generates an $TARBALL file from legacy instances.  The
  included SQL scripts can be used to import the OpenSlides database as well as
  all media files into new OpenSlides instances.
EOF
}

fatal() {
    echo 1>&2 "ERROR: $*"
    exit 23
}

INSTANCE="$1"
[[ $# -eq 1 ]] && [[ -d "$INSTANCE" ]] || { usage; exit 2; }
cd "$INSTANCE"

PRIOSERVER="$(docker-compose ps -q prioserver)"
POSTGRES="$(docker-compose ps -q postgres)"

PRIOSERVER_NAME="$(docker ps -q --filter id="$PRIOSERVER" \
  --filter status=running --format '{{ .Names }}')"
POSTGRES_NAME="$(docker ps -q --filter id="$PRIOSERVER" \
  --filter status=running --format '{{ .Names }}')"

[[ -n "$PRIOSERVER" ]] || fatal "Service prioserver must be running"
[[ -n "$POSTGRES" ]]   || fatal "Service postgres must be running"

###############
# Openslides DB
###############
echo "Exporting main openslides database from ${POSTGRES_NAME}..."
docker-compose exec -u postgres postgres pg_dump openslides > openslides.sql

#############
# Media files
#############
echo "Preparing media files from $PRIOSERVER_NAME for import into database..."
cat > mediafiledata.sql << EOF
-- based on openslides-media-service
CREATE TABLE IF NOT EXISTS mediafile_data (
    id int PRIMARY KEY,
    data bytea,
    mimetype varchar(255)
);
ALTER TABLE mediafile_data OWNER TO openslides;

EOF
docker-compose exec prioserver python manage.py export_mediafiles \
  --path /dev/stdout | tail +4 | head -n -1 >> mediafiledata.sql

###############
# Configuration
###############
echo "Gathering instance config from $PRIOSERVER_NAME for import into database..."
SETTINGS="$(cat << EOF | base64 -w0
$(docker-compose exec prioserver cat personal_data/var/settings.py)

# Mediafile database settings added by export script
DATABASES['mediafiles'] = {
    'ENGINE': 'django.db.backends.postgresql',
    'NAME': 'mediafiledata',
    'USER': 'openslides',
    'PASSWORD': 'openslides',
    'HOST': 'db',
    'PORT': '5432',
}
EOF
)"
cat > instancecfg.sql << EOF
UPDATE markers set configured = true;

INSERT INTO files(filename, data, from_host)
VALUES(
  'personal_data/var/settings.py',
  convert_from(decode('$SETTINGS','base64'), 'utf-8'),
  'Initial import from legacy export'
);
EOF


echo "Creating $TARBALL tarball..."
tar czvf "$TARBALL" openslides.sql mediafiledata.sql secrets instancecfg.sql metadata.txt

cat <<EOF
Done.

Please refer to README.md of an up-to-date repository for instructions on how
to import $TARBALL into a newly created instance.

EOF
