# docker-mamonsu
Контейнер для mamonsu. Активный агент мониторинга PostgreSQL для zabbix

Докер основан на образе debian https://hub.docker.com/_/debian

* Контейнер работает под пользователем postgres c внутренними ключами uid=999 и gid=999

* Контейнер рассчитан на работу в bootstrap режиме с кластером. В этом режиме создаётся специальная БД с именем mamonsu в которой находятся некоторые функции для работы части плагинов. Создаётся специальный пользователь с именем mamonsu и выполняется необходимая настройка его прав.

* Внутрь контейнера дополнительно установлена утилита pg-probackup, для того, чтобы можно было использовать новые плагины по контролю за состоянием каталога бэкапов.

* Стартовый файл с mamonsu запускается через программу dumb-init, чтобы иметь возможность транслировать корректно внешние сигналы процессу mamonsu.

* Добавлена настройка параметра WORK_MEM для функции mamonsu_buffer_cache(). Это необходимо для того, чтобы исключить использование дисковых операций при запросах к буферному кэшу.

* В контейнер включён плагин pg_stat_replication.py, который позволяет корректно контролировать лаг репликации на репликах (до 2-х реплик). Этот плагин работает на мастере. На репликах он никаких метрик не формирует. Для контроля лага репликации на серверах репликах используется модифицированная версия функции mamonsu_timestamp_get():

```
CREATE OR REPLACE FUNCTION public.mamonsu_timestamp_get() RETURNS double precision AS
$BODY$
  select case when pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() then 0
              else extract (epoch from now() - pg_last_xact_replay_timestamp())
         end;
$BODY$
LANGUAGE sql VOLATILE SECURITY DEFINER;
```

Плагин pg_stat_replication.py опирается на код функции mamonsu_pg_stat_replication():

```
CREATE OR REPLACE FUNCTION public.mamonsu_pg_stat_replication()
RETURNS TABLE(write_lag double precision, flush_lag double precision, replay_lag double precision) AS
$BODY$
  select coalesce(extract(epoch from write_lag),0) as write_lag,
         coalesce(extract(epoch from flush_lag),0) as flush_lag,
         coalesce(extract(epoch from replay_lag),0) as replay_lag
  from pg_catalog.pg_stat_replication
  order by client_hostname;
$BODY$
LANGUAGE sql VOLATILE SECURITY DEFINER;
```

# Переменные окружения контейнера

Переменные по подключению к БД:
| Name             | Default value | Description                                                                                                                                        |
| ---------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| MAMONSU_PASSWORD | None          | Пароль пользователя для подключения к БД mamonsu для bootstrap режима. None - это специальное слово (не пароль), которое говорит об его отсутствии |
| PGHOST           | 127.0.0.1     | Имя хоста для подключения                                                                                                                          |
| PGPASSWORD       |               | Определяет пароль пользователя postgres. Требуется при настройке bootstrap режима                                                                  |
| PGPORT           | 5432          | Номер порта для подключения к кластеру БД                                                                                                          |

Переменные общего характера:
| Name | Default value | Description                                                                                       |
| ---- | ------------- | ------------------------------------------------------------------------------------------------- |
| TZ   |               | Указывает на временную зону в которой работает контейнер. Например: "Europe/Moscow" или "Etc/UTC" |

Переменные влияющие на работу плагинов:
| Name                           | Default value | Description                                                                                          |
| ------------------------------ | ------------- | ---------------------------------------------------------------------------------------------------- |
| CLIENT_HOSTNAME                |               | секция [zabbix] Имя текущего сервера в том виде как это заведено в настройках zabbix в разделе Hosts |
| ZABBIX_SERVER_IP               |               | секция [zabbix] IP адрес или имя сервера zabbix                                                      |
| ZABBIX_SERVER_PORT             | 10051         | секция [zabbix] Порт по которому нужно подключаться к zabbix                                         |
| MAMONSU_AGENTHOST              | 127.0.0.1     | секция [agent] Определяет как подключаться к mamonsu для доступа к метрикам из командной строки      |
| INTERVAL_PGBUFFERCACHE         | 1200          | секция [pgbuffercache] Интервал в секундах для обновления плагина pgbuffercache                      |
| PGPROBACKUP_ENABLED            | False         | секция [pgprobackup] Должен ли работать плагин pgprobackup                                           |
| MEMORYLEAKDIAGNOSTIC_ENABLED   | True          | секция [memoryleakdiagnostic] Должен ли работать плагин memoryleakdiagnostic                         |
| MEMORYLEAKDIAGNOSTIC_THRESHOLD | 4GB           | секция [memoryleakdiagnostic] Порог срабатывания алерта плагина memoryleakdiagnostic                 |

На сейчас пока есть возможность изменить только эти настройки.

Можно мапить следующие каталоги контейнера:

```
    /mnt/pgbak        - требуется для работы плагина pgprobackup
    /var/log/mamonsu  - лог работы masmonsu
    /etc/mamonsu/     - настройки mamonsu. Если каталог пуст, то в нём создадутся всё необходимы файлы настройки. Это позволит легко в них внести правки.
```

# Пример docker-compose файла

```
version: '3.5'
services:
  mamonsu:
    build:
      context: ./docker-mamonsu
      dockerfile: Dockerfile
 
    volumes:
      - "/mnt/pgbak/:/mnt/pgbak/"
      - "/var/log/mamonsu:/var/log/mamonsu"
      - "/etc/mamonsu/:/etc/mamonsu/"
 
    environment:
#      TZ: "Etc/UTC"
      TZ: "Europe/Moscow"
      PGPASSWORD: qweasdzxc
#      PGHOST: 10.10.2.139
#      PGHOST: 127.0.0.1
      PGHOST: postgres
      PGPORT: 5432
      MAMONSU_PASSWORD: 1234512345
      ZABBIX_SERVER_IP: proxy.my_zbx.ru
      ZABBIX_SERVER_PORT: 10051
      CLIENT_HOSTNAME: postgres_data
      MAMONSU_AGENTHOST: 127.0.0.1
      INTERVAL_PGBUFFERCACHE: 1200
      PGPROBACKUP_ENABLED: "False"
 
    restart: always
    ports:
      - "10051:10051"
      - "10052:10052"
```

Такие управляющие файлы рекомендуется запускать командами:

```
#!/bin/bash
clear
rm -rf /var/log/mamonsu/*
docker-compose -f "mamonsu-service.yml" up --build "$@"
```
