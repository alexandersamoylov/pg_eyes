# pg_eyes

Расширение включает в себя набор функций и представлений для мониторинга состояния базы данных PostgreSQL.

## Установка

###Версии расширения

В настоящий момент поддерживаются две ветки расширения для разных версий PostgreSQL:

* 0.x - для версии 9.4-9.5
* 1.x - для версии 9.6

Для установки файлов расширения можно выполнить *suso make install* или скопировать вручную файлы расширения(*pg_eyes.control* и *sql/pg_eyes\*.sql*) в директорию *SHAREDIR/extension/*

###Зависимости

pg_stat_statements

###Создание расширения

    CREATE EXTENSION pg_eyes CASCADE;

## Описание

### Функции мониторинга

Функции мониторинга представляют собой api для различных инструментов мониторинга, позволяющий получить из базы данных набор метрик в готовом виде. При вызове функции клиенту возвращаются метрики в виде таблицы: метрика, значение. Функции создаются с опцией SECURITY DEFINER, поэтому пользователю системы мониторинга достаточно привилегий на выполнение функций в схеме eyes.

#### eyes.get_activity()

Возвращает базовый набор метрик БД PostgreSQL, который можно собирать на всех экземплярах. Кол-во метрик, возвращаемых функцией, в разных экземплярах может отличатся в зависимости от наличия standby серверов.

*Описание метрик:*

> Большинство метрик включают в себя имена view, на основе которых формируются(*имя_представления.метрика*).

> Большая часть метрик из pg_stat_database и pg_stat_bgwriter накопительные. Для построения графиков по ним необходимо вычислять разницу между точками.

> Метрики с именами *_time возвращают время в миллисекундах.

| Имя метрики                           | Описание                                                                                                                                          |
|---------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| pg_stat_activity.total                | Кол-во открытых сессий.                                                                                                                           |
| pg_stat_activity.active               | Кол-во активных запросов.                                                                                                                         |
| pg_stat_activity.active_1s            | Кол-во активных запросов, работающих дольше 1 секунды.                                                                                            |
| pg_stat_activity.active_time          | Время работы самого долгого запроса. Не учитываются активные запросы процессов autovacuum.                                                        |
| pg_stat_activity.idle                 | Кол-во сессий в статусе idle.                                                                                                                     |
| pg_stat_activity.idle_in_tr           | Кол-во открытых транзакций, ожидающих в статусе idle in transaction.                                                                              |
| pg_stat_activity.idle_in_tr_1s        | Кол-во открытых транзакций, ожидающих в статусе idle in transaction дольше 1 секунды.                                                             |
| pg_stat_activity.idle_in_tr_time      | Самое долгое время ожидания в статусе idle in transaction.                                                                                        |
| pg_stat_activity.xact_time            | Время работы самой долгой открытой транзакции. Не учитываются активные запросы процессов autovacuum.                                              |
| pg_stat_activity.wait_lock            | Кол-во заблокированных запросов.                                                                                                                  |
| pg_stat_activity.wait_lock_1s         | Кол-во запросов, заблокированных дольше 1 секунды.                                                                                                |
| pg_stat_activity.wait_lock_time       | Самое долгое время блокировки запроса.                                                                                                            |
| pg_stat_activity.autovacuum           | Кол-во работающих процессов autovacuum                                                                                                            |
| pg_stat_activity.autovacuum_time      | Время работы самого старого процесса autovacuum.                                                                                                  |
| pg_stat_activity.dba_task_active      | Значение рассчитывается для application_name = "DBATask" аналогично pg_stat_activity.active                                                       |
| pg_stat_activity.dba_task_active_time | Значение рассчитывается для application_name = "DBATask" аналогично pg_stat_activity.active_time                                                  |
| pg_stat_activity.dba_task_xact_time   | Значение рассчитывается для application_name = "DBATask" аналогично pg_stat_activity.xact_time                                                    |
| pg_stat_database.backends_pct         | Процент открытых сессий от max_connections.                                                                                                       |
| pg_stat_database.xact_total           | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.xact_commit          | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.xact_rollback        | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.blks_read            | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.blks_hit             | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.tup_returned         | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.tup_fetched          | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.tup_inserted         | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.tup_updated          | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.tup_deleted          | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.conflicts            | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.temp_files           | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.temp_bytes           | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_database.deadlocks            | [pg_stat_database](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-database-view)                                    |
| pg_stat_bgwriter.checkpoints_timed    | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.checkpoints_req      | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.checkpoint_write_time| [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.checkpoint_sync_time | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.buffers_checkpoint   | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.buffers_clean        | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.maxwritten_clean     | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.buffers_backend      | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.buffers_backend_fsync| [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| pg_stat_bgwriter.buffers_alloc        | [pg_stat_bgwriter](https://postgrespro.ru/docs/postgresql/current/monitoring-stats.html#pg-stat-bgwriter-view)                                    |
| wal_written_b                         | Объем записанных в WAL данных.                                                                                                                    |
| replication.streaming_db02_b_lag      | Отставание репликации в байтах. Метрика формируется на мастере динамически(streaming_application_name_b_lag) на основе данных pg_stat_replication.|
| replication.is_in_recovery            | Возвращает 1, если база данных в процессе восстановления.                                                                                         |
| replication.ms_lag                    | Время отставания репликации standby базы данных в миллисекундах. На мастере время отставания всегда 0.                                            |
| response_time                         | Условное время отклика базы данных. Считается время работы текущей функции.                                                                       |
|                                       |                                                                                                                                                   |

*Пример использования:*

    SELECT stat_name, stat_value FROM eyes.get_activity();
                   stat_name                |   stat_value   
    ----------------------------------------+----------------
     pg_stat_activity.total                 |            150
     pg_stat_activity.active                |              5
     pg_stat_activity.active_1s             |              1
     pg_stat_activity.active_time           |           8233
     pg_stat_activity.idle                  |            134
     pg_stat_activity.idle_in_tr            |             11
     pg_stat_activity.idle_in_tr_1s         |             10
     pg_stat_activity.idle_in_tr_time       |          28972
     pg_stat_activity.xact_time             |          29967
     pg_stat_activity.wait_lock             |              0
     pg_stat_activity.wait_lock_1s          |              0
     pg_stat_activity.wait_lock_time        |              0
     pg_stat_activity.autovacuum            |              0
     pg_stat_activity.autovacuum_time       |              0
     pg_stat_activity.dba_task_active       |              0
     pg_stat_activity.dba_task_active_time  |              0
     pg_stat_activity.dba_task_xact_time    |              0
     pg_stat_database.backends_pct          |              8
     pg_stat_database.xact_total            |     2467775475
     pg_stat_database.xact_commit           |     2464139978
     pg_stat_database.xact_rollback         |        3635497
     pg_stat_database.blks_read             |    12695419761
     pg_stat_database.blks_hit              |  1595740885426
     pg_stat_database.tup_returned          | 49506807445278
     pg_stat_database.tup_fetched           |   375366791483
     pg_stat_database.tup_inserted          |      503839362
     pg_stat_database.tup_updated           |     1176437355
     pg_stat_database.tup_deleted           |      126931522
     pg_stat_database.conflicts             |              0
     pg_stat_database.temp_files            |            734
     pg_stat_database.temp_bytes            |    10883135968
     pg_stat_database.deadlocks             |            404
     pg_stat_bgwriter.checkpoints_timed     |           2656
     pg_stat_bgwriter.checkpoints_req       |            697
     pg_stat_bgwriter.checkpoint_write_time |     4068513155
     pg_stat_bgwriter.checkpoint_sync_time  |         618549
     pg_stat_bgwriter.buffers_checkpoint    |      244031859
     pg_stat_bgwriter.buffers_clean         |       40027187
     pg_stat_bgwriter.maxwritten_clean      |         271382
     pg_stat_bgwriter.buffers_backend       |       84082877
     pg_stat_bgwriter.buffers_backend_fsync |              0
     pg_stat_bgwriter.buffers_alloc         |     1290553764
     wal_written_b                          | 50313595651824
     replication.streaming_db03_b_lag       |          27384
     replication.streaming_db02_b_lag       |          27384
     replication.is_in_recovery             |              0
     replication.ms_lag                     |              0
     response_time                          |             14
    (48 строк)


####eyes.get_activity(p_stat_group character varying)

Функция для получения специфичных для конкретных баз данных или приложений метрик, настраиваемых дополнительно администраторами. Возвращает метрики только для заданной в параметре вызова группы. Для настройки нестандартных метрик используется таблица eyes.get_activity.

| Столбец          | Тип                  | Описание                                                                                                      |
|------------------|----------------------|---------------------------------------------------------------------------------------------------------------|
| stat_name        | character varying(30)| Имя метрики.                                                                                                  |
| stat_group       | character varying(30)| Группа метрик. Значение задается в качестве параметра при вызове функции eyes.get_activity(character varying).|
| stat_query       | text                 | Запрос для получения значения. Запрос должен возвращать одно значение целочисленного типа.                    |
| stat_description | text                 | Произвольное описание метрики.                                                                                |

*Пример использования:*

Например необходимо получать метрики по размеру таблицы testtable1 и ее индексов. Для настройки добавим соответствующие строки в таблицу с группой "table_size":

    INSERT INTO eyes.get_activity (stat_name,
        stat_group, 
        stat_query,
        stat_description)
    VALUES ( 'table_size.testtable1_size',
        'table_size',
        'SELECT pg_table_size(''testtable1'');',
        'Размер таблицы testtable1');
    
    INSERT INTO eyes.get_activity (stat_name,
        stat_group, 
        stat_query,
        stat_description)
    VALUES ( 'table_size.testtable1_idx_size',
        'table_size',
        'SELECT pg_indexes_size(''testtable1'');',
        'Размер индексов testtable1');

Получение метрик для группы "table_size":

    SELECT stat_name, stat_value FROM eyes.get_activity('table_size');
               stat_name            | stat_value 
    --------------------------------+------------
     table_size.testtable1_size     |      73728
     table_size.testtable1_idx_size |      32768
    (2 строки)

### Полезные представления и функции

####eyes.get_pg_stat_activity()

Функция возвращает результат запроса *"SELECT \* FROM pg_stat_activity;"*. Позволяет организовать полный доступ к данным представления pg_stat_activity пользователям без предоставления им роли superuser.

####eyes.get_pg_stat_statements()

Функция возвращает результат запроса *"SELECT \* FROM pg_stat_statements;"*. Позволяет организовать полный доступ к данным представления pg_stat_statements пользователям без предоставления им роли superuser.
