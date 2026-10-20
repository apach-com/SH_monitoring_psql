#!/bin/bash
export PGPASSFILE="/etc/zabbix/.pgpass"
# Использование: pg_show_param.sh <parameter_name>
# Пример: pg_show_param.sh autovacuum_work_mem

DB_USER="zabbix_monitor"
DB_HOST="127.0.0.1"
DB_PORT="5432"
PARAM="$1"

# Защита от инъекций
if [[ ! "$PARAM" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "ZBX_NOTSUPPORTED: invalid parameter name"
    exit 1
fi

# Получаем значение и единицы измерения
RESULT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -t -A -c "
    SELECT setting, unit
    FROM pg_settings
    WHERE name = '$PARAM';
")

SETTING=$(echo "$RESULT" | cut -d'|' -f1)
UNIT=$(echo "$RESULT" | cut -d'|' -f2)

# Если значение пустое (параметр не существует)
if [ -z "$SETTING" ]; then
    echo "ZBX_NOTSUPPORTED: parameter not found"
    exit 1
fi

# Преобразуем в MB
case "$UNIT" in
    ms)
        echo "scale=3; $SETTING / 1000" | bc
        ;;
    ms)
        echo "scale=3; $SETTING / 1000" | bc
        ;;
    kB)
        echo "scale=2; $SETTING / 1024" | bc
        ;;
    MB)
        echo "$SETTING"
        ;;
    GB)
        echo "scale=2; $SETTING * 1024" | bc
        ;;
    8kB)
        echo "scale=2; $SETTING * 8 / 1024" | bc
        ;;
    "")
        # Без единиц (например, число воркеров)
        echo "$SETTING"
        ;;
    *)
        echo "ZBX_NOTSUPPORTED: unknown unit $UNIT"
        exit 1
        ;;
esac
