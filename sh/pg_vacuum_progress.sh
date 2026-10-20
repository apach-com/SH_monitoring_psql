#!/bin/bash
# Использование:
#   pg_vacuum_progress.sh count           → сколько VACUUM идёт
#   pg_vacuum_progress.sh longest         → длительность самого долгого (сек)
#   pg_vacuum_progress.sh details         → JSON со всеми активными VACUUM
#   pg_vacuum_progress.sh table <db> <tbl>→ прогресс по конкретной таблице

export PGPASSFILE="/etc/zabbix/.pgpass"
DB_USER="zabbix_monitor"
DB_HOST="127.0.0.1"
DB_PORT="5432"
MODE="$1"

case "$MODE" in
count)
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
    SELECT count(*) FROM pg_stat_progress_vacuum;
    "
    ;;
longest)
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
    SELECT COALESCE(
        round(extract(epoch from (now() - a.query_start))),
        0
    )
    FROM pg_stat_progress_vacuum p
    JOIN pg_stat_activity a ON p.pid = a.pid
    ORDER BY a.query_start ASC
    LIMIT 1;
    "
    ;;
*)
    echo "ZBX_NOTSUPPORTED: unknown mode"
    exit 1
    ;;
esac
