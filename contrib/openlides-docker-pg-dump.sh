#!/bin/bash

# Iterate over all OpenSlides Postgres Docker containers and generate SQL
# dumps.  Removal of dumps should be handled by an external tool, e.g., the
# bup-backup backup script.

set -euo pipefail
umask 0027

BACKUP_PATH="/backup/docker-sql-dumps"
[[ -d "$BACKUP_PATH" ]] || { echo "ERROR: $BACKUP_PATH not found!"; exit 3; }

docker ps --filter=name="_postgres_" --format "{{.ID}} {{.Names}} {{.Labels}}" |
while read id name labels; do
  # The _postgres_ part of the container name represents the service name from
  # the docker-compose file.  There is no way to know if this is an OpenSlides
  # Postgres container, so we need to inspect it for an OpenSlides-specific
  # label as well:
  printf "$labels" | grep -q "org.openslides.role=postgres" || continue
  docker exec -u postgres "$id" /bin/bash -c 'pg_dump openslides' \
    > "${BACKUP_PATH}/${name}-$(date +'%F-%T').sql"
done
