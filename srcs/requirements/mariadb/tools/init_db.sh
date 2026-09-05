#!/bin/bash
set -e

DB_PASSWORD=$(cat /run/secrets/db_password)
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[init_db] First run: initializing data directory"

    mariadb-install-db \
        --user=mysql \
        --datadir=/var/lib/mysql \
        --auth-root-authentication-method=normal > /dev/null

    # Start mariadbd temporarily (socket only) to run setup SQL
    mariadbd --user=mysql --datadir=/var/lib/mysql \
        --skip-networking --socket=/run/mysqld/mysqld.sock &
    pid="$!"

    until mariadb-admin ping --socket=/run/mysqld/mysqld.sock --silent 2>/dev/null; do
        sleep 1
    done

    mariadb --socket=/run/mysqld/mysqld.sock -u root <<-EOSQL
        CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
        ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
        FLUSH PRIVILEGES;
EOSQL

    mariadb-admin --socket=/run/mysqld/mysqld.sock -u root -p"${DB_ROOT_PASSWORD}" shutdown
    wait "$pid"
    echo "[init_db] Initialization complete"
fi

# PID 1: run mariadbd in the foreground (no daemonizing, no tail -f tricks)
exec mariadbd --user=mysql --datadir=/var/lib/mysql --bind-address=0.0.0.0
