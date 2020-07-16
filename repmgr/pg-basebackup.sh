#!/bin/bash

backup() {
  mkdir -p "$BACKUP_DIR"
  pg_basebackup -D - -Ft \
    --wal-method=fetch --checkpoint=fast \
    --write-recovery-conf \
    --label="$*" |
  gzip > "${BACKUP_DIR}/backup-$(date '+%F-%H:%M:%S').tar.gz"
}
