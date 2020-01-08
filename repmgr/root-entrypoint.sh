#!/bin/bash

/etc/init.d/ssh start
su postgres -c "/usr/local/bin/entrypoint $*"
