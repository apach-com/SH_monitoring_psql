# 📊 SH PostgreSQL Custom Monitoring

Комплексный шаблон мониторинга PostgreSQL для Zabbix 7.4. Позволяет отслеживать ключевые параметры конфигурации, производительность, ожидания, WAL, VACUUM и состояние баз данных через LLD (Low-Level Discovery).

## Копирование проекта.

---
```

git clone https://git.nzmu.ru:8929/infra/SH_monitoring_psql.git

```


---

##  Структура проекта

```
SH_monitoring_psql/
├── sh/                              # Bash-скрипты для сбора метрик
│   ├── pg_cache_hit.sh              # Cache Hit Ratio + LLD по БД
│   ├── pg_show_param.sh             # Параметры конфигурации pg_settings
│   ├── pg_vacuum_progress.sh        # Активные VACUUM процессы
│   ├── pg_wait_events.sh            # Ожидания сессий + LLD
│   └── pg_wal_size.sh               # Размер WAL на диске
│
├── zabbix_agentd.conf.d/            # Конфигурация агента
│   └── pg_custom.conf               # UserParameter для всех ключей
│
├── install_SH.sh                    # Скрипт автоматического развёртывания
├── README.md                        # Документация
└── SH_PostgreSQL_Custom_Monitoring.xml  # Шаблон Zabbix для импорта
```

### Описание файлов

| Файл / Папка | Назначение |
|--------------|------------|
| `sh/` | Директория с bash-скриптами сбора метрик. При установке копируется в `/etc/zabbix/sh/` |
| `zabbix_agentd.conf.d/` | Директория с конфигом `UserParameter`. При установке копируется в `/etc/zabbix/zabbix_agentd.conf.d/` |
| `install_SH.sh` | Скрипт автоматического развёртывания: копирует файлы, назначает владельца `zabbix`, выставляет права, конвертирует CRLF → LF, перезапускает агент |
| `README.md` | Документация проекта |
| `SH_PostgreSQL_Custom_Monitoring.xml` | XML-шаблон Zabbix 7.4 — импортируется через веб-интерфейс |

### ⚠️ Файлы, которые НЕ хранятся в Git

Следующие файлы создаются **на целевом сервере** и не коммитятся в репозиторий (исключены через `.gitignore`):

| Файл | Где создаётся | Назначение |
|------|---------------|------------|
| `.pgpass` | `/etc/zabbix/.pgpass` | Пароль для подключения `zabbix_monitor` к PostgreSQL |
| `.pgpass.example` | корень репозитория | Шаблон для `.pgpass` (опционально) |

## 📄 Содержимое `pg_custom.conf`

```ini
UserParameter=pg.cache_hit[*],/etc/zabbix/sh/pg_cache_hit.sh "$1"
UserParameter=pg.wal_size,/etc/zabbix/sh/pg_wal_size.sh
UserParameter=pg.vacuum[*],/etc/zabbix/sh/pg_vacuum_progress.sh "$1"
UserParameter=pg.show[*],/etc/zabbix/sh/pg_show_param.sh "$1"
UserParameter=pg.wait_events[*],/etc/zabbix/sh/pg_wait_events.sh "$1" "$2"
```

### Соответствие ключей

| Ключ Zabbix | Скрипт | Параметры |
|-------------|--------|-----------|
| `pg.cache_hit[*]` | `pg_cache_hit.sh` | `$1` — имя БД или `all` для LLD |
| `pg.wal_size` | `pg_wal_size.sh` | без параметров |
| `pg.vacuum[*]` | `pg_vacuum_progress.sh` | `$1` — режим (`count` / `longest`) |
| `pg.show[*]` | `pg_show_param.sh` | `$1` — имя параметра из `pg_settings` |
| `pg.wait_events[*]` | `pg_wait_events.sh` | `$1` — тип метрики, `$2` — имя БД (или `all` для LLD) |

### Типы метрик для `pg.wait_events[*]`

| Значение `$1` | Описание |
|---------------|----------|
| `wait_lock` | Сессии, ожидающие тяжёлых блокировок (`Lock`) |
| `wait_lwlock` | Сессии, ожидающие лёгких блокировок (`LWLock`) |
| `wait_io` | Сессии, ожидающие ввода-вывода (`IO`) |
| `wait_timeout` | Сессии, ожидающие по таймауту (`Timeout`) |
| `idle_in_tx` | Неактивные транзакции |
| `total_conn` | Общее количество подключений к БД |
| `all` | LLD: JSON со всеми метриками для всех БД |

---


## ⚙️ Требования

- **Zabbix Server/Agent** версии 7.4+
- **PostgreSQL** 10+ (для `pg_stat_progress_vacuum`, `pg_ls_waldir()`, `wait_event_type`)
- Установленный пакет `bc` (для математических вычислений в `pg_show_param.sh`)
- Пользователь PostgreSQL `zabbix_monitor` с правами `pg_monitor`

---

## 🚀 Установка

### 1. Создание пользователя в PostgreSQL

```sql
-- Подключаемся к PostgreSQL от имени суперпользователя
sudo -u postgres psql

-- Создаём роль и пользователя
CREATE ROLE pg_monitor_role;
GRANT pg_monitor TO pg_monitor_role;

CREATE USER zabbix_monitor WITH PASSWORD 'ВАШ_БЕЗОПАСНЫЙ_ПАРОЛЬ';
GRANT pg_monitor_role TO zabbix_monitor;

\q
```

### 2. Настройка `pg_hba.conf`

Добавьте в `/etc/postgresql/<version>/main/pg_hba.conf`:

```
host    all    zabbix_monitor    127.0.0.1/32    md5
```

Перезагрузите PostgreSQL:
```bash
sudo systemctl reload postgresql
```

### 3. Размещение файлов

```bash
# Создаём директории
sudo mkdir -p /etc/zabbix/sh
sudo mkdir -p /etc/zabbix/zabbix_agentd.conf.d

# Копируем файлы из репозитория
sudo cp .pgpass /etc/zabbix/.pgpass
sudo cp sh/*.sh /etc/zabbix/sh/
sudo cp zabbix_agentd.conf.d/pg_custom.conf /etc/zabbix/zabbix_agentd.conf.d/
```

### 4. Настройка прав доступа

#### Владелец и права для `.pgpass` (критично!)

```bash
sudo chown zabbix:zabbix /etc/zabbix/.pgpass
sudo chmod 600 /etc/zabbix/.pgpass
```

⚠️ **Важно:** `psql` игнорирует `.pgpass`, если права не `600`.

#### Владелец для скриптов и конфигов

```bash
sudo chown -R zabbix:zabbix /etc/zabbix/sh
sudo chown zabbix:zabbix /etc/zabbix/zabbix_agentd.conf.d/pg_custom.conf
```

#### Исполняемость для скриптов

```bash
sudo chmod +x /etc/zabbix/sh/pg_cache_hit.sh
sudo chmod +x /etc/zabbix/sh/pg_show_param.sh
sudo chmod +x /etc/zabbix/sh/pg_vacuum_progress.sh
sudo chmod +x /etc/zabbix/sh/pg_wait_events.sh
sudo chmod +x /etc/zabbix/sh/pg_wal_size.sh
```

Или одной командой:
```bash
sudo chmod +x /etc/zabbix/sh/*.sh
```

### 5. Настройка `.pgpass`

Отредактируйте `/etc/zabbix/.pgpass` и укажите реальный пароль:

```
127.0.0.1:5432:*:zabbix_monitor:ВАШ_БЕЗОПАСНЫЙ_ПАРОЛЬ
```

⚠️ Формат строго: `хост:порт:БД:пользователь:пароль`

### 6. Проверка порта PostgreSQL

Если PostgreSQL слушает не стандартный порт `5432`, замените `DB_PORT="5432"` на актуальный во всех скриптах:

```bash
sudo sed -i 's/DB_PORT="5432"/DB_PORT="ВАШ_ПОРТ"/g' /etc/zabbix/sh/*.sh
```

### 7. Перезапуск Zabbix Agent

```bash
sudo systemctl restart zabbix-agent2
# или для классического агента:
sudo systemctl restart zabbix-agent
```

### 8. Импорт шаблона в Zabbix

1. Откройте веб-интерфейс Zabbix
2. Перейдите в **Data collection** → **Templates** → **Import** (в правом верхнем углу)
3. Выберите файл `SH PostgreSQL Custom Monitoring.xml`
4. Нажмите **Import**

### 9. Применение шаблона к хосту

1. Перейдите в **Data collection** → **Hosts**
2. Выберите нужный хост
3. Во вкладке **Templates** добавьте `SH PostgreSQL Custom Monitoring`
4. Сохраните

---

## 📊 Описание метрик

### Параметры конфигурации (pg.show)

| Метрика | Ключ | Тип | Ед. изм. | Интервал | Описание |
|---------|------|-----|----------|----------|----------|
| SH PostgreSQL: archive_mode | `pg.show[archive_mode]` | TEXT | — | 6h | Режим архивации WAL |
| SH PostgreSQL: autovacuum_max_workers | `pg.show[autovacuum_max_workers]` | FLOAT | — | 6h | Максимум воркеров autovacuum |
| SH PostgreSQL: autovacuum_work_mem | `pg.show[autovacuum_work_mem]` | FLOAT | MB | 6h | Память на воркер autovacuum |
| SH PostgreSQL: checkpoint_completion_target | `pg.show[checkpoint_completion_target]` | FLOAT | — | 6h | Доля интервала checkpoint |
| SH PostgreSQL: effective_cache_size | `pg.show[effective_cache_size]` | FLOAT | MB | 6h | Оценка размера кэша ОС |
| SH PostgreSQL: effective_io_concurrency | `pg.show[effective_io_concurrency]` | FLOAT | — | 6h | Количество одновременных IO |
| SH PostgreSQL: lock_timeout | `pg.show[lock_timeout]` | FLOAT | s | 6h | Таймаут ожидания блокировки |
| SH PostgreSQL: maintenance_work_mem | `pg.show[maintenance_work_mem]` | FLOAT | MB | 6h | Память для VACUUM/CREATE INDEX |
| SH PostgreSQL: max_connections | `pg.show[max_connections]` | FLOAT | — | 6h | Максимум подключений |
| SH PostgreSQL: max_parallel_workers_per_gather | `pg.show[max_parallel_workers_per_gather]` | FLOAT | — | 6h | Параллельных воркеров на Gather |
| SH PostgreSQL: max_replication_slots | `pg.show[max_replication_slots]` | FLOAT | — | 6h | Максимум слотов репликации |
| SH PostgreSQL: max_wal_senders | `pg.show[max_wal_senders]` | FLOAT | — | 6h | Максимум подключений для репликации |
| SH PostgreSQL: max_wal_size | `pg.show[max_wal_size]` | FLOAT | MB | 6h | Максимальный размер WAL до checkpoint |
| SH PostgreSQL: max_worker_processes | `pg.show[max_worker_processes]` | FLOAT | — | 6h | Максимум фоновых процессов |
| SH PostgreSQL: shared_buffers | `pg.show[shared_buffers]` | FLOAT | MB | 6h | Размер shared buffers |
| SH PostgreSQL: statement_timeout | `pg.show[statement_timeout]` | FLOAT | s | 6h | Таймаут выполнения запросов |
| SH PostgreSQL: wal_buffers | `pg.show[wal_buffers]` | FLOAT | MB | 6h | Буфер WAL |
| SH PostgreSQL: wal_level | `pg.show[wal_level]` | TEXT | — | 6h | Уровень детализации WAL |
| SH PostgreSQL: work_mem | `pg.show[work_mem]` | FLOAT | MB | 6h | Память на операцию сортировки |

### Оперативные метрики

| Метрика | Ключ | Тип | Ед. изм. | Интервал | Описание |
|---------|------|-----|----------|----------|----------|
| SH PostgreSQL: WAL size | `pg.wal_size` | FLOAT | MB | 5m | Общий размер файлов WAL на диске |
| SH PostgreSQL: Active VACUUM count | `pg.vacuum[count]` | FLOAT | — | 5m | Количество активных VACUUM |
| SH PostgreSQL: Longest VACUUM duration | `pg.vacuum[longest]` | FLOAT | s | 5m | Длительность самого долгого VACUUM |

### LLD-прототипы (по базам данных)

| Метрика | Ключ | Тип | Ед. изм. | Интервал | Описание |
|---------|------|-----|----------|----------|----------|
| SH Cache Hit Ratio: {#DBNAME} | `pg.cache_hit[{#DBNAME}]` | FLOAT | % | 1m | Процент попаданий в кэш |
| SH Idle in Transaction: {#DBNAME} | `pg.wait_events[idle_in_tx,{#DBNAME}]` | FLOAT | — | 1m | Неактивных транзакций |
| SH Total Connections: {#DBNAME} | `pg.wait_events[total_conn,{#DBNAME}]` | FLOAT | — | 1m | Всего подключений к БД |
| SH Wait IO: {#DBNAME} | `pg.wait_events[wait_io,{#DBNAME}]` | FLOAT | — | 1m | Сессий, ожидающих IO |
| SH Wait Lock: {#DBNAME} | `pg.wait_events[wait_lock,{#DBNAME}]` | FLOAT | — | 1m | Сессий, ожидающих блокировки |
| SH Wait LWLock: {#DBNAME} | `pg.wait_events[wait_lwlock,{#DBNAME}]` | FLOAT | — | 1m | Сессий, ожидающих LWLock |
| SH Wait Timeout: {#DBNAME} | `pg.wait_events[wait_timeout,{#DBNAME}]` | FLOAT | — | 1m | Сессий, ожидающих по таймауту |

---

## 🔧 Макросы шаблона

Все макросы настраиваются на уровне хоста или глобально.

| Макрос | По умолчанию | Описание |
|--------|:------------:|----------|
| `{$PG.AUTOVACUUM_MEM.MIN}` | 100 | Минимум `autovacuum_work_mem` (MB) |
| `{$PG.CACHE_HIT.HIGH}` | 90 | Критический порог Cache Hit Ratio (%) |
| `{$PG.CACHE_HIT.WARN}` | 95 | Порог предупреждения Cache Hit Ratio (%) |
| `{$PG.IDLE_TX.HIGH}` | 20 | Критическое число неактивных транзакций |
| `{$PG.IDLE_TX.WARN}` | 5 | Порог предупреждения для idle in transaction |
| `{$PG.MAX_CONN.MAX}` | 500 | Максимум `max_connections` |
| `{$PG.SHARED_BUFFERS.MIN}` | 128 | Минимум `shared_buffers` (MB) |
| `{$PG.TOTAL_CONN.HIGH}` | 100 | Критическое число подключений к БД |
| `{$PG.TOTAL_CONN.WARN}` | 80 | Порог предупреждения для подключений |
| `{$PG.VACUUM_COUNT.WARN}` | 5 | Порог предупреждения для активных VACUUM |
| `{$PG.VACUUM_LONGEST.MAX}` | 3600 | Максимальная длительность VACUUM (сек) |
| `{$PG.WAIT_IO.HIGH}` | 100 | Критическое число IO-ожиданий |
| `{$PG.WAIT_IO.WARN}` | 50 | Порог предупреждения для IO-ожиданий |
| `{$PG.WAIT_LOCK.HIGH}` | 50 | Критическое число блокировок |
| `{$PG.WAIT_LOCK.WARN}` | 20 | Порог предупреждения для блокировок |
| `{$PG.WAIT_LWLOCK.HIGH}` | 50 | Критическое число LWLock-ожиданий |
| `{$PG.WAIT_LWLOCK.WARN}` | 20 | Порог предупреждения для LWLock-ожиданий |
| `{$PG.WAIT_TIMEOUT.HIGH}` | 100 | Критическое число Timeout-ожиданий |
| `{$PG.WAIT_TIMEOUT.WARN}` | 50 | Порог предупреждения для Timeout-ожиданий |
| `{$PG.WAL_SIZE.MAX}` | 10240 | Максимальный размер WAL (MB, ~10 ГБ) |
| `{$PG.WORK_MEM.MIN}` | 4 | Минимум `work_mem` (MB) |

---

## 🔔 Триггеры

### Обычные триггеры

| Имя | Выражение | Приоритет |
|-----|-----------|-----------|
| PostgreSQL: autovacuum_work_mem слишком мал | `< {$PG.AUTOVACUUM_MEM.MIN}` | WARNING |
| PostgreSQL: max_connections слишком велик | `> {$PG.MAX_CONN.MAX}` | WARNING |
| PostgreSQL: shared_buffers слишком мал | `< {$PG.SHARED_BUFFERS.MIN}` | WARNING |
| PostgreSQL: work_mem слишком мал | `< {$PG.WORK_MEM.MIN}` | WARNING |
| PostgreSQL: WAL size слишком велик | `> {$PG.WAL_SIZE.MAX}` | WARNING |
| PostgreSQL: Много активных VACUUM | `> {$PG.VACUUM_COUNT.WARN}` | WARNING |
| PostgreSQL: Зависший VACUUM | `> {$PG.VACUUM_LONGEST.MAX}` | HIGH |

### Триггер-прототипы (LLD по БД)

| Имя | Выражение | Приоритет |
|-----|-----------|-----------|
| SH Critical cache hit ratio on {#DBNAME} | `< {$PG.CACHE_HIT.HIGH}` | HIGH |
| SH Low cache hit ratio on {#DBNAME} | `< {$PG.CACHE_HIT.WARN}` | WARNING |
| SH High idle in transaction on {#DBNAME} | `> {$PG.IDLE_TX.HIGH}` | HIGH |
| SH Elevated idle in transaction on {#DBNAME} | `> {$PG.IDLE_TX.WARN}` | WARNING |
| SH High total connections on {#DBNAME} | `> {$PG.TOTAL_CONN.HIGH}` | HIGH |
| SH Elevated total connections on {#DBNAME} | `> {$PG.TOTAL_CONN.WARN}` | WARNING |
| SH High wait IO on {#DBNAME} | `> {$PG.WAIT_IO.HIGH}` | HIGH |
| SH Elevated wait IO on {#DBNAME} | `> {$PG.WAIT_IO.WARN}` | WARNING |
| SH High wait lock on {#DBNAME} | `> {$PG.WAIT_LOCK.HIGH}` | HIGH |
| SH Elevated wait lock on {#DBNAME} | `> {$PG.WAIT_LOCK.WARN}` | WARNING |
| SH High wait LWLock on {#DBNAME} | `> {$PG.WAIT_LWLOCK.HIGH}` | HIGH |
| SH Elevated wait LWLock on {#DBNAME} | `> {$PG.WAIT_LWLOCK.WARN}` | WARNING |
| SH High wait timeout on {#DBNAME} | `> {$PG.WAIT_TIMEOUT.HIGH}` | HIGH |
| SH Elevated wait timeout on {#DBNAME} | `> {$PG.WAIT_TIMEOUT.WARN}` | WARNING |

---

## 🔍 Discovery Rules

### 1. SH PostgreSQL databases discovery

- **Ключ:** `pg.cache_hit[all]`
- **Интервал:** 1 час
- **Макросы LLD:** `{#DBNAME}` — имя базы данных, `{#HIT_RATIO}` — текущий cache hit ratio
- **Исключения:** `template0`, `template1`
- **Создаёт:** прототип Cache Hit Ratio для каждой БД

### 2. SH PostgreSQL wait events discovery

- **Ключ:** `pg.wait_events[all]`
- **Интервал:** 1 час
- **Макросы LLD:** `{#DBNAME}`, `{#WAIT_LOCK}`, `{#WAIT_LWLOCK}`, `{#WAIT_IO}`, `{#WAIT_TIMEOUT}`, `{#IDLE_IN_TX}`, `{#TOTAL_CONN}`
- **Исключения:** `postgres`, `template0`, `template1`
- **Создаёт:** 6 прототипов метрик ожиданий для каждой БД

---

## 🛠️ Troubleshooting

### Проверка работы скриптов

Выполните от имени пользователя `zabbix`:

```bash
sudo -u zabbix /etc/zabbix/sh/pg_show_param.sh shared_buffers
sudo -u zabbix /etc/zabbix/sh/pg_wal_size.sh
sudo -u zabbix /etc/zabbix/sh/pg_cache_hit.sh all
sudo -u zabbix /etc/zabbix/sh/pg_wait_events.sh all
sudo -u zabbix /etc/zabbix/sh/pg_vacuum_progress.sh count
sudo -u zabbix /etc/zabbix/sh/pg_vacuum_progress.sh longest
```

### Проверка подключения через `.pgpass`

```bash
sudo -u zabbix bash -c 'PGPASSFILE=/etc/zabbix/.pgpass psql -h 127.0.0.1 -p 5432 -U zabbix_monitor -d postgres -c "SELECT 1;"'
```

Должно вернуть `1` **без запроса пароля**.

### Проверка загрузки UserParameter

```bash
# Для zabbix-agent2
sudo zabbix_agent2 -t pg.cache_hit[all]
sudo zabbix_agent2 -t pg.wal_size
sudo zabbix_agent2 -t pg.wait_events[all]

# Для классического zabbix-agent
zabbix_get -s 127.0.0.1 -k pg.cache_hit[all]
zabbix_get -s 127.0.0.1 -k pg.wal_size
zabbix_get -s 127.0.0.1 -k pg.wait_events[all]
```

### Частые проблемы

| Проблема | Решение |
|----------|---------|
| `fe_sendauth: no password supplied` | Проверьте `.pgpass`: права `600`, владелец `zabbix:zabbix`, реальный пароль (не звёздочки) |
| `ZBX_NOTSUPPORTED: parameter not found` | Параметр не существует в данной версии PostgreSQL |
| `синтаксическая ошибка рядом с неожиданным маркером` | Проверьте синтаксис bash-скрипта: `bash -n /etc/zabbix/sh/<script>.sh` |
| Данные не собираются | Проверьте, что `UserParameter` загружен: `zabbix_agent2 -T \| grep pg.` |
| LLD не находит БД | Проверьте, что пользователь `zabbix_monitor` имеет права на `pg_stat_database` |
| `ZBX_NOTSUPPORTED: unknown unit` | В `pg_settings` появилась новая единица измерения — обновите `pg_show_param.sh` |
| Метрики ожиданий не собираются | Проверьте соответствие ключей в `pg_custom.conf` и XML-шаблоне (должно быть `pg.wait_events[*]`) |

### Полезные команды

```bash
# Проверка синтаксиса скрипта
bash -n /etc/zabbix/sh/pg_show_param.sh

# Тест UserParameter через zabbix_get
zabbix_get -s 127.0.0.1 -k pg.wal_size
zabbix_get -s 127.0.0.1 -k pg.show[shared_buffers]
zabbix_get -s 127.0.0.1 -k pg.cache_hit[all]
zabbix_get -s 127.0.0.1 -k pg.wait_events[wait_lock,mydb]

# Просмотр логов агента
sudo tail -f /var/log/zabbix/zabbix_agent2.log

# Проверка прав на .pgpass
ls -la /etc/zabbix/.pgpass

# Проверка версии PostgreSQL
sudo -u postgres psql -c "SELECT version();"

# Проверка загруженных UserParameter
sudo zabbix_agent2 -T | grep pg.
```

---

## 🔒 Безопасность

- Все скрипты используют **защиту от SQL-инъекций** через регулярные выражения для входных параметров
- Пароль хранится в `.pgpass` с правами `600` (доступен только владельцу)
- Пользователь `zabbix_monitor` имеет только права на чтение системных каталогов (`pg_monitor`)
- Скрипты подключаются только к `127.0.0.1` — сетевое взаимодействие исключено

---

## 📜 Скрипт автоматической установки

В репозитории доступен `install_SH.sh` — он автоматизирует все ручные шаги по развёртыванию: копирование файлов, назначение владельца `zabbix`, выставление прав и перезапуск агента.

### 🚀 Использование

```bash
chmod +x install_SH.sh
sudo ./install_SH.sh
```

### 📋 Что делает скрипт

| Шаг | Действие |
|-----|----------|
| 1 | Проверяет запуск от `root` и наличие нужных файлов |
| 2 | Создаёт директории `/etc/zabbix/sh/` и `/etc/zabbix/zabbix_agentd.conf.d/` |
| 3 | Копирует все `.sh` из `sh/` в `/etc/zabbix/sh/` |
| 4 | Копирует `.pgpass` в `/etc/zabbix/.pgpass`. Если файл существует, он не копируется. |
| 5 | Копирует `pg_custom.conf` в `/etc/zabbix/zabbix_agentd.conf.d/` |
| 6 | Назначает владельца `zabbix:zabbix` на все файлы |
| 7 | Ставит права `600` на `.pgpass` и `+x` на скрипты |
| 8 | Перезапускает `zabbix-agent2` (или `zabbix-agent`) |
| 9 | Конвертирует файлы в Unix-формат (LF) |

### ⚠️ Что скрипт НЕ делает

Эти шаги нужно выполнить **один раз вручную** на сервере PostgreSQL:

1. **Создать роль PostgreSQL** `zabbix_monitor` с паролем
2. **Добавить строку в `pg_hba.conf`**:
   ```
   host    all    zabbix_monitor    127.0.0.1/32    md5
   ```
3. **Перезагрузить PostgreSQL**: `sudo systemctl reload postgresql`
4. **Импортировать XML-шаблон** в Zabbix через веб-интерфейс
5. **Привязать шаблон** к хосту

---

## Лицензия / License

Проект предоставляется «как есть», без каких-либо гарантий. 
Используйте на свой страх и риск.

This project is provided "as-is", without warranty of any kind. 
Use at your own risk.

