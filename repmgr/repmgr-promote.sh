#!/bin/bash

# This script is called as repmgr's promote_command which is configured in
# /etc/repmgr.conf.

BACKUP_DIR="/var/lib/postgresql/backup/"

backup() {
  # Create base backup
  mkdir -p "$BACKUP_DIR"
  pg_basebackup -D - -Ft \
    --wal-method=fetch --checkpoint=fast \
    --write-recovery-conf \
    --label="Base backup during repmgr promotion to primary" |
  gzip > "${BACKUP_DIR}/backup-$(date '+%F-%H:%M:%S').tar.bz2"
}

# Promote node from standby to primary
/usr/bin/repmgr standby promote -f /etc/repmgr.conf &&
  backup
