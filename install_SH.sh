#!/usr/bin/env bash
#
# install_SH.sh — развёртывание SH PostgreSQL Custom Monitoring
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Настройки
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ZBX_USER="zabbix"
ZBX_GROUP="zabbix"

SH_DIR="/etc/zabbix/sh"
CONF_DIR="/etc/zabbix/zabbix_agentd.conf.d"
PGPASS_DST="/etc/zabbix/.pgpass"

# ---------------------------------------------------------------------------
# Проверки
# ---------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo $0"; exit 1; }

[[ -d "$SCRIPT_DIR/sh" ]] || { echo "Нет директории sh/ рядом со скриптом"; exit 1; }
[[ -f "$SCRIPT_DIR/.pgpass" ]] || { echo "Нет файла .pgpass рядом со скриптом"; exit 1; }
[[ -d "$SCRIPT_DIR/zabbix_agentd.conf.d" ]] || { echo "Нет директории zabbix_agentd.conf.d/ рядом со скриптом"; exit 1; }

id "$ZBX_USER" >/dev/null 2>&1 || { echo "Пользователь $ZBX_USER не существует"; exit 1; }

# ---------------------------------------------------------------------------
# Создание директорий
# ---------------------------------------------------------------------------
echo "Создаю директории..."
mkdir -p "$SH_DIR"
mkdir -p "$CONF_DIR"

# ---------------------------------------------------------------------------
# Копирование скриптов
# ---------------------------------------------------------------------------
echo "Копирую скрипты в $SH_DIR..."
cp -v "$SCRIPT_DIR"/sh/*.sh "$SH_DIR/"

# ---------------------------------------------------------------------------
# Копирование .pgpass (только если не существует)
# ---------------------------------------------------------------------------
PGPASS_COPIED=0
if [ -f "$PGPASS_DST" ]; then
    echo "Файл $PGPASS_DST уже существует — пропускаю (не трогаю ни содержимое, ни права)."
else
    echo "Копирую .pgpass в $PGPASS_DST..."
    cp -v "$SCRIPT_DIR/.pgpass" "$PGPASS_DST"
    PGPASS_COPIED=1
fi

# ---------------------------------------------------------------------------
# Копирование конфига агента
# ---------------------------------------------------------------------------
echo "Копирую pg_custom.conf в $CONF_DIR..."
cp -v "$SCRIPT_DIR"/zabbix_agentd.conf.d/pg_custom.conf "$CONF_DIR/"

# ---------------------------------------------------------------------------
# Конвертация в Unix-формат (LF) — защита от CRLF
# ---------------------------------------------------------------------------
echo "Конвертирую файлы в Unix-формат (LF)..."
sed -i 's/\r$//' "$SH_DIR"/*.sh
sed -i 's/\r$//' "$CONF_DIR/pg_custom.conf"
if (( PGPASS_COPIED )); then
    sed -i 's/\r$//' "$PGPASS_DST"
fi

# ---------------------------------------------------------------------------
# Назначение владельца и прав для скриптов и конфига
# ---------------------------------------------------------------------------
echo "Назначаю владельца $ZBX_USER:$ZBX_GROUP и права..."
chown -R "$ZBX_USER:$ZBX_GROUP" "$SH_DIR"
chmod +x "$SH_DIR"/*.sh

chown "$ZBX_USER:$ZBX_GROUP" "$CONF_DIR/pg_custom.conf"

# ---------------------------------------------------------------------------
# Владелец и права для .pgpass — только если его копировали
# ---------------------------------------------------------------------------
if (( PGPASS_COPIED )); then
    echo "Назначаю владельца и права для нового .pgpass..."
    chown "$ZBX_USER:$ZBX_GROUP" "$PGPASS_DST"
    chmod 600 "$PGPASS_DST"
fi

# ---------------------------------------------------------------------------
# Перезапуск Zabbix Agent
# ---------------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet zabbix-agent2; then
        echo "Перезапускаю zabbix-agent2..."
        systemctl restart zabbix-agent2
    elif systemctl is-active --quiet zabbix-agent; then
        echo "Перезапускаю zabbix-agent..."
        systemctl restart zabbix-agent
    else
        echo "Агент Zabbix не запущен. Запустите вручную."
    fi
else
    echo "systemctl не найден. Перезапустите агент вручную."
fi

echo
echo "Готово!"
echo "  Скрипты      : $SH_DIR"
echo "  UserParameter: $CONF_DIR/pg_custom.conf"
if (( PGPASS_COPIED )); then
    echo "  Парольный файл: $PGPASS_DST (права 600, создан заново)"
else
    echo "  Парольный файл: $PGPASS_DST (существующий, не изменён)"
fi
