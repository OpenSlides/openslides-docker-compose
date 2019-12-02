#!/bin/bash

set -e

# Insert settings.py into the configuration database

# same as function from entrypoint, so this could be improved
insert_settings_into_db() {
  local b64="$(base64 < "/app/personal_data/var/settings.py")"
  psql -h db -d instancecfg \
    -c "INSERT INTO django(filename, data)
      VALUES(
        'settings.py',
        convert_from(decode('$b64','base64'), 'utf-8')
      )"
}

insert_settings_into_db

echo "settings.py updated:"

psql -h db -d instancecfg \
    -c "SELECT id, created FROM django
      WHERE filename = 'settings.py'
      ORDER BY id DESC LIMIT 1"

echo
echo "Hint: run \`docker service update --force \$service\`" \
  "to update all service containers."
