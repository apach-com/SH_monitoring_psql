#!/bin/bash
export PGPASSFILE="/etc/zabbix/.pgpass"
# Использование:
#   pg_wait_events.sh all              → LLD для всех БД
#   pg_wait_events.sh <metric> <db>    → конкретная метрика для БД

DB_USER="zabbix_monitor"
DB_HOST="127.0.0.1"
DB_PORT="5432"
MODE="$1"
DB_NAME="$2"

# Защита от инъекций
if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] && [ "$DB_NAME" != "all" ] && [ -n "$DB_NAME" ]; then
    echo "ZBX_NOTSUPPORTED: invalid database name"
    exit 1
fi

# Функция для получения SQL-выражения метрики
get_metric_sql() {
    case "$1" in
        wait_lock)     echo "COUNT(*) FILTER (WHERE wait_event_type = 'Lock')" ;;
        wait_lwlock)   echo "COUNT(*) FILTER (WHERE wait_event_type = 'LWLock')" ;;
        wait_io)       echo "COUNT(*) FILTER (WHERE wait_event_type = 'IO')" ;;
        wait_timeout)  echo "COUNT(*) FILTER (WHERE wait_event_type = 'Timeout')" ;;
        idle_in_tx)    echo "COUNT(*) FILTER (WHERE state = 'idle in transaction')" ;;
        total_conn)    echo "COUNT(*)" ;;
        *)             echo "ZBX_NOTSUPPORTED: unknown metric"; exit 1 ;;
    esac
}

case "$MODE" in
    all)
        # LLD: возвращаем JSON со всеми метриками для всех БД
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
            SELECT COALESCE(json_agg(json_build_object(
                '{#DBNAME}', datname,
                '{#WAIT_LOCK}', COALESCE(wait_lock, 0),
                '{#WAIT_LWLOCK}', COALESCE(wait_lwlock, 0),
                '{#WAIT_IO}', COALESCE(wait_io, 0),
                '{#WAIT_TIMEOUT}', COALESCE(wait_timeout, 0),
                '{#IDLE_IN_TX}', COALESCE(idle_in_transaction, 0),
                '{#TOTAL_CONN}', COALESCE(total_connections, 0)
            ))::text, '[]')
            FROM (
                SELECT db.datname,
                       COUNT(*) FILTER (WHERE wait_event_type = 'Lock') AS wait_lock,
                       COUNT(*) FILTER (WHERE wait_event_type = 'LWLock') AS wait_lwlock,
                       COUNT(*) FILTER (WHERE wait_event_type = 'IO') AS wait_io,
                       COUNT(*) FILTER (WHERE wait_event_type = 'Timeout') AS wait_timeout,
                       COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction,
                       COUNT(*) AS total_connections
                FROM pg_database db
                LEFT JOIN pg_stat_activity sa ON sa.datname = db.datname
                WHERE db.datname NOT IN ('postgres', 'template0', 'template1')
                GROUP BY db.datname
            ) t;
        "
        ;;
    wait_lock|wait_lwlock|wait_io|wait_timeout|idle_in_tx|total_conn)
        # Конкретная метрика для одной БД
        METRIC_SQL=$(get_metric_sql "$MODE")

        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
            SELECT COALESCE($METRIC_SQL, 0)
            FROM pg_stat_activity
            WHERE datname = '$DB_NAME';
        "
        ;;
    *)
        echo "ZBX_NOTSUPPORTED: unknown mode"
        exit 1
        ;;
esac
