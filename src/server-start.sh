#!/bin/sh

if [ -z "$PGDATA" ]; then PGDATA=/var/lib/postgresql/data; fi
if [ -z $1 ]; then
    config=/etc/postgresql/postgresql.conf
else
    config=$1
fi
postgres -D $PGDATA -c config_file=$config -c listen_addresses='*'
