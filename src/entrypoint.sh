#!/bin/sh

postgresql_config=/etc/postgresql/postgresql.conf
file_pg_hba=/etc/postgresql/pg_hba.conf
file_pg_ident=/etc/postgresql/pg_ident.conf
pgpass=~/.pgpass
initdb_dir="/entrypoint.d"
cache_dir="$initdb_dir/.cache"
tmp_server_is_running=1
superdb='postgres'
pg_ctl="/usr/local/bin/pg_ctl -D $PGDATA -o '-c config_file=$postgresql_config'"

# Check and define variables
if [ -z "$LANG" ]; then export LANG=en_US.UTF-8; fi
if [ -z "$PGDATA" ]; then export PGDATA='/var/lib/postgresql/data'; fi
if [ -z "$POSTGRES_HOST" ]; then export POSTGRES_HOST='localhost'; fi
if [ -z "$POSTGRES_PORT" ]; then export POSTGRES_PORT='5432'; fi
if [ -z "$POSTGRES_USER" ]; then export POSTGRES_USER='postgres'; fi
if [ -z "$POSTGRES_PASSWORD" ]; then export POSTGRES_PASSWORD='postgres'; fi
if [ -z "$POSTGRES_DB" ]; then export POSTGRES_DB='postgres'; fi
if [ -z "$POSTGRES_INITDB_ARGS" ]; then export POSTGRES_INITDB_ARGS=''; fi
if [ -z "$REPLICATION_USER" ]; then export REPLICATION_USER=''; fi
if [ -z "$REPLICATION_PASSWORD" ]; then export REPLICATION_PASSWORD=''; fi
if [ -z "$REPLICATION_SLOT" ]; then export REPLICATION_SLOT=''; fi
if [ -z "$SUPERUSER_USER" ]; then export SUPERUSER_USER='postgres'; fi
if [ -z "$SUPERUSER_PASSWORD" ]; then export SUPERUSER_PASSWORD='postgres'; fi

database_is_initialized() {
    if [ ! -d "$PGDATA" ]; then
        echo "Database is not initialized"
        return 1
    fi
    # check if the data directory is empty
    if [ -z "$(ls -A $PGDATA)" ]; then
        echo "Database is not initialized, data directory is empty"
        return 1
    fi

    if $pg_ctl status 2>&1 | grep -q "is not a database cluster directory"; then
        # check if the data directory is not empty
        if [ -n "$(ls -A $PGDATA)" ]; then
            echo "Database is not initialized, data directory is not empty"
            exit 1
        fi

        echo "Database is not initialized"
        return 1
    fi
}

make_pgpass() {
    local host=$POSTGRES_HOST
    local user=$1
    local password=$2
    if [ -f "$pgpass" ]; then
        if cat $pgpass | grep -qw "$host:$port:\\*:$user:"; then
            sed -i "/$host:\\*:\\*:$user:/d" $pgpass
            echo "$host:*:*:$user:$password" >>"$pgpass"
        else
            echo "$host:*:*:$user:$password" >>"$pgpass"
        fi
    else
        echo "$host:*:*:$user:$password" >"$pgpass"
    fi
    chmod 600 "$pgpass"
}

is_replica() {
    if [[ "$POSTGRES_HOST" != "localhost" && "$POSTGRES_HOST" != "127.0.0.0" && "$POSTGRES_HOST" != "::1" ]]; then
        return 0
    fi
    return 1
}

initialize_database() {
    if [ ! -d "$PGDATA" ]; then
        doas mkdir -p "$PGDATA"
    fi

    doas chown -R postgres:postgres "$PGDATA"
    doas chmod 700 "$PGDATA"

    if [ ! -d "$cache_dir" ]; then
        mkdir -p "$cache_dir"
        chown -R postgres:postgres "$cache_dir"
        chmod 700 "$cache_dir"
    fi

    if ! is_replica; then
        echo "initializing master server database..."
        local command='initdb -D "$PGDATA" --no-instructions --username "$POSTGRES_USER" --auth-host=scram-sha-256 --auth-local=trust -c config_file="$postgresql_config" -c unix_socket_directories="/var/run/postgresql" -c listen_addresses="*" --pwfile=<(echo -n "$POSTGRES_PASSWORD") $POSTGRES_INITDB_ARGS'
        eval $command
        if [ $? -ne 0 ]; then
            echo "failed to initialize master server database"
            exit 1
        fi
    elif [ -n "$REPLICATION_USER" -a -n "$REPLICATION_PASSWORD" -a -n "$REPLICATION_SLOT" ]; then
        if ! make_pgpass "$REPLICATION_USER" "$REPLICATION_PASSWORD"; then
            echo "failed to create pgpass file"
            exit 1
        fi
        local primary_conninfo="host=$POSTGRES_HOST port=$POSTGRES_PORT user=$REPLICATION_USER password=$REPLICATION_PASSWORD"
        echo "initializing replica server database..."
        wait_for_postgres $POSTGRES_PORT 60 $REPLICATION_USER
        pg_basebackup -vwPR \
            -h $POSTGRES_HOST \
            -p $POSTGRES_PORT \
            -U $REPLICATION_USER \
            -D $PGDATA \
            --slot=$REPLICATION_SLOT \
            --wal-method=stream
        if [ $? -ne 0 ]; then
            echo "failed to initialize replica server database"
            exit 1
        fi
        sed -i "s/hot_standby = off/hot_standby = on/" "$postgresql_config"
        sed -i "s/primary_conninfo = ''/primary_conninfo = '$primary_conninfo'/" "$postgresql_config"
    else
        echo "Failed to initialize database"
        echo "Replication user, password and slot name must be provided when initializing a remote database"
        echo "Please provide REPLICATION_USER, REPLICATION_PASSWORD and REPLICATION_SLOT environment variables"
        exit 1
    fi

}

start_temporary_server() {
    echo "Starting temporary server ..."
    pg_ctl -D "$PGDATA" -o "-c config_file=$postgresql_config -c listen_addresses='localhost'" start
    if [ $? -ne 0 ]; then
        echo "Failed to start temporary server"
        exit 1
    fi
    echo "Temporary server started successfully"
    tmp_server_is_running=1
}

stop_temporary_server() {
    if [ $tmp_server_is_running -ne 1 ]; then
        return
    fi
    pg_ctl stop
    if [ $? -ne 0 ]; then
        echo "Failed to stop temporary server"
        exit 1
    fi
    tmp_server_is_running=0
}

wait_for_postgres() {
    local port=$1
    local timeout=$2
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    local user=$POSTGRES_USER
    if [ -n "$3" ]; then user=$3; fi

    echo "waiting for establishing connection to server on $user@$POSTGRES_HOST:$port ..."
    while true; do
        if [ $end_time -lt $(date +%s) ]; then
            echo "erro connecting to server on $POSTGRES_HOST:$port, timeout reached"
            exit 1
        fi
        if psql -h $POSTGRES_HOST -p $port -U $user -d $POSTGRES_DB -c "SELECT 1" 2>/dev/null; then
            break
        fi
        sleep 1
    done
    echo "connection established on $POSTGRES_HOST:$port"
}

super_user_exists() {
    local query="SELECT 1 FROM pg_roles WHERE rolname='$SUPERUSER_USER'"
    psql -U "$SUPERUSER_USER" -d "$POSTGRES_DB" -Atc "$query" | grep -qw 1
    return $?
}

create_or_update_super_user() {
    if is_replica; then return; fi
    if [ "$SUPERUSER_USER" != $POSTGRES_USER ]; then
        echo "creating or updating superuser $SUPERUSER_USER"
        if super_user_exists; then
            psql -v ON_ERROR_STOP=1 --username "$SUPER_USER" --dbname "$POSTGRES_DB" <<-EOF
                ALTER ROLE $SUPERUSER_USER WITH SUPERUSER LOGIN ENCRYPTED PASSWORD '$SUPERUSER_PASSWORD';
EOF
        else
            psql -v ON_ERROR_STOP=1 --username "$SUPER_USER" --dbname "$POSTGRES_DB" <<-EOF
                CREATE ROLE $SUPERUSER_USER WITH SUPERUSER LOGIN ENCRYPTED PASSWORD '$SUPERUSER_PASSWORD';
EOF
        fi
    fi
}

replication_user_exists() {
    local query="SELECT 1 FROM pg_roles WHERE rolname='$REPLICATION_USER'"
    psql -U "$SUPERUSER_USER" -d "$POSTGRES_DB" -Atc "$query" | grep -qw 1
    return $?
}

create_or_update_replicant_user() {
    if is_replica; then return; fi
    if [ -z "$REPLICATION_USER" ] || [ -z "$REPLICATION_PASSWORD" ]; then return; fi
    if replication_user_exists; then
        psql -v ON_ERROR_STOP=1 --username "$SUPER_USER" --dbname "$POSTGRES_DB" <<-EOF
            ALTER ROLE $REPLICATION_USER WITH REPLICATION LOGIN ENCRYPTED PASSWORD '$REPLICATION_PASSWORD';
EOF
    else
        psql -v ON_ERROR_STOP=1 --username "$SUPER_USER" --dbname "$POSTGRES_DB" <<-EOF
            CREATE ROLE $REPLICATION_USER WITH REPLICATION LOGIN ENCRYPTED PASSWORD '$REPLICATION_PASSWORD';
EOF
    fi
}

create_replication_slot() {
    if [ -z "$REPLICATION_SLOT" ]; then return; fi
    if ! slot_name_exists; then
        echo "creating replication slot $REPLICATION_SLOT"
        local query="SELECT * FROM pg_create_physical_replication_slot('$REPLICATION_SLOT')"
        psql -U "$SUPERUSER_USER" -d "$POSTGRES_DB" -Atc "$query" | grep -qw $REPLICATION_SLOT
        if [ $? -ne 0 ]; then
            echo "failed to create replication slot $REPLICATION_SLOT"
            exit 1
        fi
    fi
}

slot_name_exists() {
    local query="SELECT 1 FROM pg_replication_slots WHERE slot_name='$REPLICATION_SLOT'"
    psql -U "$SUPERUSER_USER" -d "$POSTGRES_DB" -Atc "$query" | grep -qw 1
    return $?
}

script_exists_or_executed() {
    local origin=$1
    local cache="$cache_dir/$(basename $origin)"
    if [ ! -f "$cache" ]; then
        return 1
    fi

    # check if the script has been modified
    if [ "$origin" -nt "$cache" ]; then
        return 1
    fi

    # check if the script is different
    if ! diff -q "$origin" "$cache" >/dev/null; then
        return 1
    fi

    return 0
}

execute_init_scripts() {
    if [ -d "$initdb_dir" ]; then
        for f in $initdb_dir/*; do
            if [ ! -f "$f" ]; then continue; fi
            if [ ! -r "$f" ]; then
                echo "$0: ignoring $f - file is not readable"
                continue
            fi
            if script_exists_or_executed "$f"; then
                echo "$0: ignoring $f - script already executed"
                continue
            fi
            case "$f" in
            *.sh)
                echo "$0: running $f"
                sed '1i#!/bin/sh' "$f" | sh
                [ $? -eq 0 ] && cp "$f" "$cache_dir"
                ;;
            *.sql)
                echo "$0: running $f"
                psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
                [ $? -eq 0 ] && cp "$f" "$cache_dir"
                ;;
            *)
                echo "$0: ignoring $f"
                ;;
            esac
        done
    fi
}

update_pg_hba() {
    if [ -z "$REPLICATION_USER" ]; then
        return
    fi
    for brd in $(ip route list | grep -v default | cut -d ' ' -f1); do
        if ! cat "$file_pg_hba" | grep -q "'$brd'"; then
            echo "host    replication     $REPLICATION_USER   $brd    trust" >>$file_pg_hba
        fi
    done
}

if ! database_is_initialized; then
    echo "Initializing database"
    initialize_database
fi

if ! is_replica; then
    update_pg_hba
    make_pgpass "$POSTGRES_USER" "$POSTGRES_PASSWORD"
    make_pgpass "$SUPERUSER_USER" "$SUPERUSER_PASSWORD"
    start_temporary_server
    create_or_update_replicant_user
    create_replication_slot
    create_or_update_super_user
    execute_init_scripts
    stop_temporary_server
fi

if is_replica; then
    make_pgpass "$REPLICATION_USER" "$REPLICATION_PASSWORD"
    wait_for_postgres $POSTGRES_PORT 60 $REPLICATION_USER
fi

exec "$@"
