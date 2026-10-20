#!/bin/bash
export PGPASSFILE="/etc/zabbix/.pgpass"

DB_USER="zabbix_monitor"
DB_HOST="127.0.0.1"
DB_PORT="5432"
DB_NAME="$1"

if [ "$DB_NAME" = "all" ]; then
    # LLD: возвращаем JSON-массив с макросами Zabbix
    # COALESCE(..., 0) — чтобы не было null для пустых БД
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
        SELECT json_agg(
            json_build_object(
                '{#DBNAME}', datname,
                '{#HIT_RATIO}', COALESCE(
                    round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 3),
                    0
                )
            )
        )::text
        FROM pg_stat_database
        WHERE datname NOT IN ('template0', 'template1')
          AND datname IS NOT NULL;
    "
else
    # Обычный Item: возвращаем одно число
    # Подключаемся к postgres, а не к $1 — надёжнее
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
        SELECT COALESCE(
            round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 3),
            0
        )
        FROM pg_stat_database
        WHERE datname = '$DB_NAME';
    "
fi

