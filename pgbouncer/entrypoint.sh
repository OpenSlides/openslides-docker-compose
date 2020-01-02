#!/bin/bash

update_config() {
  printf "* = host=%s\n" "$1" |
    tee /etc/pgbouncer/pgbouncer.database.ini
}

# Set PRIMARY or exit
. /usr/local/lib/find-primary.sh

update_config "$PRIMARY"

exec pgbouncer /etc/pgbouncer/pgbouncer.ini

# vim: set ft=sh sw=2 et:
