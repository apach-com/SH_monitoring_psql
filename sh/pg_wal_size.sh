#!/bin/bash
export PGPASSFILE="/etc/zabbix/.pgpass"

DB_USER="zabbix_monitor"
DB_HOST="127.0.0.1"
DB_PORT="5432"

psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
    SELECT COALESCE(round(sum(size) / 1024.0 / 1024.0, 0), 0)
    FROM pg_ls_waldir();
"
