-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_eyes" to load this file. \quit


-- Версия расширения для PostgreSQL 9.6 и выше


-- Function: eyes.get_pg_stat_activity()

CREATE OR REPLACE FUNCTION eyes.get_pg_stat_activity()
    RETURNS SETOF pg_stat_activity AS
$body$
SELECT * FROM pg_stat_activity;
$body$
    LANGUAGE sql VOLATILE SECURITY DEFINER
    COST 100
    ROWS 1000;

ALTER FUNCTION eyes.get_pg_stat_activity()
    OWNER TO postgres;

COMMENT ON FUNCTION eyes.get_pg_stat_activity()
    IS 'Permition on pg_stat_activity for nosuperuser role';


-- Function: eyes.get_pg_stat_statements()

CREATE OR REPLACE FUNCTION eyes.get_pg_stat_statements()
    RETURNS SETOF pg_stat_statements AS
$body$
SELECT * FROM pg_stat_statements;
$body$
    LANGUAGE sql VOLATILE SECURITY DEFINER
    COST 100
    ROWS 1000;
  
ALTER FUNCTION eyes.get_pg_stat_statements()
    OWNER TO postgres;

COMMENT ON FUNCTION eyes.get_pg_stat_activity()
    IS 'Permition on pg_stat_statements for nosuperuser role';


-- Table: update_time

CREATE TABLE eyes.update_time (
    update_time timestamp with time zone
)
WITH (
    OIDS=FALSE
);

ALTER TABLE eyes.update_time
    OWNER TO postgres;

COMMENT ON TABLE eyes.update_time
    IS 'Last time execution funcion update_time()';

INSERT INTO eyes.update_time VALUES(now());


-- Function: eyes.update_time()

CREATE OR REPLACE FUNCTION eyes.update_time()
    RETURNS int AS
$body$
BEGIN
    IF NOT pg_is_in_recovery() THEN
        UPDATE eyes.update_time SET update_time = now();
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;
  
ALTER FUNCTION eyes.update_time()
    OWNER TO postgres;

COMMENT ON FUNCTION eyes.update_time()
    IS 'Fake update to test replication';


-- Function: eyes.get_activity();

CREATE OR REPLACE FUNCTION eyes.get_activity()
    RETURNS TABLE(stat_name character varying,
        stat_value bigint
    ) AS
$body$
DECLARE

/*
Описание:
    Получение метрик для систем мониторинга
*/

    -- pg_stat_activity
    v_total bigint;
    v_active bigint;
    v_active_1s bigint;
    v_active_time bigint;
    v_idle bigint;
    v_idle_in_tr bigint;
    v_idle_in_tr_1s bigint;
    v_idle_in_tr_time bigint;
    v_xact_time bigint;
    v_wait_lock bigint;
    v_wait_lock_1s bigint;
    v_wait_lock_time bigint;
    v_autovacuum bigint;
    v_autovacuum_time bigint;
    v_dba_task bigint;
    v_dba_task_time bigint;

    -- pg_stat_database
    v_backends_pct bigint;
    v_xact_total bigint;
    v_xact_commit bigint;
    v_xact_rollback bigint;
    v_blks_read bigint;
    v_blks_hit bigint;
    v_tup_returned bigint;
    v_tup_fetched bigint;
    v_tup_inserted bigint;
    v_tup_updated bigint;
    v_tup_deleted bigint;
    v_conflicts bigint;
    v_temp_files bigint;
    v_temp_bytes bigint;
    v_deadlocks bigint;

    -- pg_stat_database
    v_checkpoints_timed bigint;
    v_checkpoints_req bigint;
    v_checkpoint_write_time bigint;
    v_checkpoint_sync_time bigint;
    v_buffers_checkpoint bigint;
    v_buffers_clean bigint;
    v_maxwritten_clean bigint;
    v_buffers_backend bigint;
    v_buffers_backend_fsync bigint;
    v_buffers_alloc bigint;

    -- replication state
    v_last_xact_replay_timestamp timestamp with time zone;
    v_clock_timestamp timestamp with time zone;
    v_is_in_recovery bigint;
    v_ms_lag bigint;
    v_last_update_status bigint;

    -- wal
    v_wal_written_b bigint;

    r record;

BEGIN

    -- Get pg_stat_activity

    SELECT count(1) AS total,
        count(*) FILTER (WHERE state = 'active') AS active,
        count(*) FILTER (WHERE state = 'active'
            AND now() - query_start > interval '1s') AS active_1s,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE state = 'active'
            AND query NOT LIKE 'autovacuum:%'
            AND application_name != 'DBATask'
            ), 0) AS active_time,
        count(*) FILTER (WHERE state = 'idle') AS idle,
        count(*) FILTER (WHERE state LIKE 'idle in%') AS idle_in_tr,
        count(*) FILTER (WHERE state LIKE 'idle in%'
            AND statement_timestamp() - state_change > interval '1s')
            AS idle_in_tr_1s,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            state_change))*1000)) FILTER (WHERE state LIKE 'idle in%'),
            0) AS idle_in_tr_time,      
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            xact_start))*1000)) FILTER (WHERE state != 'idle'
            AND query NOT LIKE 'autovacuum:%'), 0) AS xact_time,
        count(*) FILTER (WHERE wait_event_type = 'Lock') AS wait_lock,
        count(*) FILTER (WHERE wait_event_type = 'Lock'
            AND statement_timestamp() - query_start > interval '1s')
            AS wait_lock_1s,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE wait_event_type = 'Lock'),
            0) AS wait_lock_time,    
        count(*) FILTER (WHERE state = 'active' AND query LIKE 'autovacuum:%')
            AS autovacuum,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE state = 'active'
            AND query LIKE 'autovacuum:%'), 0) AS autovacuum_time,
        count(*) FILTER (WHERE state = 'active'
            AND application_name = 'DBATask')
            AS dba_task,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE state = 'active'
            AND application_name = 'DBATask'), 0)
            AS dba_task_time
        INTO v_total,
            v_active, v_active_1s, v_active_time,
            v_idle, v_idle_in_tr, v_idle_in_tr_1s, v_idle_in_tr_time,
            v_xact_time, v_wait_lock, v_wait_lock_1s, v_wait_lock_time,
            v_autovacuum, v_autovacuum_time, v_dba_task, v_dba_task_time
    FROM pg_stat_activity;

    stat_name := 'pg_stat_activity.total';
    stat_value := v_total;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.active';
    stat_value := v_active;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.active_1s';
    stat_value := v_active_1s;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.active_time';
    stat_value := v_active_time;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.idle';
    stat_value := v_idle;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.idle_in_tr';
    stat_value := v_idle_in_tr;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.idle_in_tr_1s';
    stat_value := v_idle_in_tr_1s;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.idle_in_tr_time';
    stat_value := v_idle_in_tr_time;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.xact_time';
    stat_value := v_xact_time;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.wait_lock';
    stat_value := v_wait_lock;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.wait_lock_1s';
    stat_value := v_wait_lock_1s;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.wait_lock_time';
    stat_value := v_wait_lock_time;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.autovacuum';
    stat_value := v_autovacuum;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.autovacuum_time';
    stat_value := v_autovacuum_time;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.dba_task';
    stat_value := v_dba_task;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.dba_task_time';
    stat_value := v_dba_task_time;
    RETURN NEXT;

    -- Get pg_stat_database

    SELECT round(
            100*(sum(numbackends)/current_setting('max_connections')::numeric),
            0) AS backends_pct,
        sum(xact_commit + xact_rollback) AS xact_total,
        sum(xact_commit) AS xact_commit,
        sum(xact_rollback) AS xact_rollback,
        sum(blks_read) AS blks_read,
        sum(blks_hit) AS blks_hit,
        sum(tup_returned) AS tup_returned,
        sum(tup_fetched) AS tup_fetched,
        sum(tup_inserted) AS tup_inserted,
        sum(tup_updated) AS tup_updated,
        sum(tup_deleted) AS tup_deleted,
        sum(conflicts) AS conflicts,
        sum(temp_files) AS temp_files,
        sum(temp_bytes) AS temp_bytes,
        sum(deadlocks) AS deadlocks
        INTO v_backends_pct, v_xact_total, v_xact_commit, v_xact_rollback,
            v_blks_read, v_blks_hit, v_tup_returned, v_tup_fetched,
            v_tup_inserted, v_tup_updated, v_tup_deleted, v_conflicts,
            v_temp_files, v_temp_bytes, v_deadlocks
    FROM pg_stat_database;

    stat_name := 'pg_stat_database.backends_pct';
    stat_value := v_backends_pct;
    RETURN NEXT;
    stat_name := 'pg_stat_database.xact_total';
    stat_value := v_xact_total;
    RETURN NEXT;
    stat_name := 'pg_stat_database.xact_commit';
    stat_value := v_xact_commit;
    RETURN NEXT;
    stat_name := 'pg_stat_database.xact_rollback';
    stat_value := v_xact_rollback;
    RETURN NEXT;
    stat_name := 'pg_stat_database.blks_read';
    stat_value := v_blks_read;
    RETURN NEXT;
    stat_name := 'pg_stat_database.blks_hit';
    stat_value := v_blks_hit;
    RETURN NEXT;
    stat_name := 'pg_stat_database.tup_returned';
    stat_value := v_tup_returned;
    RETURN NEXT;
    stat_name := 'pg_stat_database.tup_fetched';
    stat_value := v_tup_fetched;
    RETURN NEXT;
    stat_name := 'pg_stat_database.tup_inserted';
    stat_value := v_tup_inserted;
    RETURN NEXT;
    stat_name := 'pg_stat_database.tup_updated';
    stat_value := v_tup_updated;
    RETURN NEXT;
    stat_name := 'pg_stat_database.tup_deleted';
    stat_value := v_tup_deleted;
    RETURN NEXT;
    stat_name := 'pg_stat_database.conflicts';
    stat_value := v_conflicts;
    RETURN NEXT;
    stat_name := 'pg_stat_database.temp_files';
    stat_value := v_temp_files;
    RETURN NEXT;
    stat_name := 'pg_stat_database.temp_bytes';
    stat_value := v_temp_bytes;
    RETURN NEXT;
    stat_name := 'pg_stat_database.deadlocks';
    stat_value := v_deadlocks;
    RETURN NEXT;

    -- Get pg_stat_bgwriter

    SELECT checkpoints_timed AS checkpoints_timed,
        checkpoints_req AS checkpoints_req,
        checkpoint_write_time AS checkpoint_write_time,
        checkpoint_sync_time AS checkpoint_sync_time,
        buffers_checkpoint AS buffers_checkpoint,
        buffers_clean AS buffers_clean,
        maxwritten_clean AS maxwritten_clean,
        buffers_backend AS buffers_backend,
        buffers_backend_fsync AS buffers_backend_fsync,
        buffers_alloc AS buffers_alloc
        INTO v_checkpoints_timed, v_checkpoints_req, v_checkpoint_write_time,
            v_checkpoint_sync_time, v_buffers_checkpoint, v_buffers_clean,
            v_maxwritten_clean, v_buffers_backend, v_buffers_backend_fsync,
            v_buffers_alloc
    FROM pg_stat_bgwriter;

    stat_name := 'pg_stat_bgwriter.checkpoints_timed';
    stat_value := v_checkpoints_timed;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.checkpoints_req';
    stat_value := v_checkpoints_req;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.checkpoint_write_time';
    stat_value := v_checkpoint_write_time;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.checkpoint_sync_time';
    stat_value := v_checkpoint_sync_time;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.buffers_checkpoint';
    stat_value := v_buffers_checkpoint;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.buffers_clean';
    stat_value := v_buffers_clean;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.maxwritten_clean';
    stat_value := v_maxwritten_clean;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.buffers_backend';
    stat_value := v_buffers_backend;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.buffers_backend_fsync';
    stat_value := v_buffers_backend_fsync;
    RETURN NEXT;
    stat_name := 'pg_stat_bgwriter.buffers_alloc';
    stat_value := v_buffers_alloc;
    RETURN NEXT;

    -- Get replication state

    IF NOT pg_is_in_recovery() THEN
        -- Если выполняется на primary

        v_is_in_recovery := 0;
        v_ms_lag := 0;

        -- Искуственный апдейт для проверки репликации
        v_last_update_status := eyes.update_time();

        -- Объем данных, записанных в WAL
        v_wal_written_b := pg_catalog.pg_xlog_location_diff(
            pg_catalog.pg_current_xlog_location(), '0/00000000');
        stat_name := 'wal_written_b';
        stat_value := v_wal_written_b;
        return next;

        -- Проверка отставания репликации
        FOR r IN SELECT application_name AS application_name,
            trunc(pg_xlog_location_diff(sent_location, replay_location)
                ) AS b_lag
            FROM pg_stat_replication
            WHERE state = 'streaming'
        LOOP
            stat_name := 'replication.streaming_'||r.application_name||'_b_lag';
            stat_value := r.b_lag;
            return next;
        END LOOP;

    ELSE
        -- Если выполняется на standby

        v_is_in_recovery := 1;
        v_last_xact_replay_timestamp := pg_last_xact_replay_timestamp();
        v_clock_timestamp := clock_timestamp();
        v_ms_lag := trunc(extract(epoch FROM age(v_clock_timestamp,
            coalesce(v_last_xact_replay_timestamp, v_clock_timestamp)))*1000);

    END IF;

    stat_name := 'replication.is_in_recovery';
    stat_value := v_is_in_recovery;
    RETURN NEXT;
    stat_name := 'replication.ms_lag';
    stat_value := v_ms_lag;
    RETURN NEXT;

    -- Время ответа функции
    stat_name := 'response_time';
    stat_value := trunc(extract(epoch FROM age(clock_timestamp(),
            current_timestamp))*1000);
    RETURN NEXT;   

    RETURN;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.get_activity()
    OWNER TO postgres;

COMMENT ON FUNCTION eyes.get_activity()
    IS 'Получение метрик для систем мониторинга';


-- Table: eyes.get_activity

CREATE TABLE eyes.get_activity (
    stat_name character varying(30) NOT NULL,
    stat_group character varying(30) NOT NULL,
    stat_query text NOT NULL,
    stat_description text,
    CONSTRAINT get_activity_pk PRIMARY KEY (stat_name)
);

ALTER TABLE eyes.get_activity
    OWNER TO postgres;

COMMENT ON TABLE eyes.get_activity
    IS 'Описание нестандартных метрик мониторинга';


-- Function: eyes.get_activity(p_stat_group character varying);

CREATE OR REPLACE FUNCTION eyes.get_activity(
    p_stat_group character varying)
    RETURNS TABLE(stat_name character varying,
        stat_value bigint
    ) AS
$body$
DECLARE

/*
Описание:
    Получение нестандартных метрик, описанных в таблице eyes.get_activity
    Таблица должна содержать заполненные поля:
    stat_name text - Имя метрики
    stat_query text - Текст запроса для молучения значения метрики(Число)
*/

    r record;

BEGIN

    FOR r IN
        SELECT * FROM eyes.get_activity
        WHERE stat_group = p_stat_group
    LOOP    
        stat_name := r.stat_name;
        EXECUTE r.stat_query INTO stat_value;
        RETURN NEXT;
    END LOOP; 

    RETURN;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.get_activity(p_stat_group character varying)
    OWNER TO postgres;

COMMENT ON FUNCTION eyes.get_activity(p_stat_group character varying)
    IS 'Получение метрик для систем мониторинга';


-- View: eyes.active_connections

CREATE OR REPLACE VIEW eyes.active_connections AS
SELECT sa.usename AS username,
    sa.datname AS dbname,
    sa.client_addr AS client_addr,
    sa.application_name AS application_name,
    count(*) AS total,
    count(*) FILTER (WHERE sa.state = 'active') AS active,
    count(*) FILTER (WHERE sa.state = 'idle in transaction') AS idle_in_tr,
    count(*) FILTER (WHERE sa.state = 'idle') AS idle
FROM eyes.get_pg_stat_activity() sa
GROUP BY sa.usename, sa.datname, sa.client_addr, sa.application_name
ORDER BY sa.usename, sa.datname, sa.client_addr, sa.application_name;

ALTER VIEW eyes.active_connections
    OWNER TO postgres;

COMMENT ON VIEW eyes.active_connections
    IS 'Get statistic about open connections in database';


-- View: eyes.active_queryes

-- DROP VIEW eyes.active_queryes;

CREATE OR REPLACE VIEW eyes.active_queryes AS
SELECT sa.pid, sa.usename, sa.datname, sa.client_addr, application_name,
    now() - sa.xact_start AS xact_time,
    CASE
        WHEN sa.state = 'active' THEN now() - sa.query_start
        ELSE '00:00:00'
    END AS query_time,
    now() - sa.state_change AS state_time,
    sa.wait_event_type, sa.wait_event,
    sa.state, sa.query
FROM eyes.get_pg_stat_activity() sa
WHERE sa.state != 'idle'
ORDER BY sa.xact_start;

ALTER VIEW eyes.active_queryes
    OWNER TO postgres;

COMMENT ON VIEW eyes.active_queryes
    IS 'Список всех активных запросов в базе данных';


-- View: eyes.blocked_queryes

CREATE OR REPLACE VIEW eyes.blocked_queryes AS
SELECT now() - ba.query_start AS locked_time,
    b.pid AS blocked_pid,
    ba.usename AS blocked_user,
    l.pid AS blocking_pid,
    la.usename AS blocking_user,
    ba.query AS blocked_statement,
    la.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks b
INNER JOIN eyes.get_pg_stat_activity() ba ON ba.pid = b.pid
INNER JOIN pg_catalog.pg_locks l ON l.locktype = b.locktype
        AND l.DATABASE IS NOT DISTINCT FROM b.DATABASE
        AND l.relation IS NOT DISTINCT FROM b.relation
        AND l.page IS NOT DISTINCT FROM b.page
        AND l.tuple IS NOT DISTINCT FROM b.tuple
        AND l.virtualxid IS NOT DISTINCT FROM b.virtualxid
        AND l.transactionid IS NOT DISTINCT FROM b.transactionid
        AND l.classid IS NOT DISTINCT FROM b.classid
        AND l.objid IS NOT DISTINCT FROM b.objid
        AND l.objsubid IS NOT DISTINCT FROM b.objsubid
        AND l.pid != b.pid
INNER JOIN eyes.get_pg_stat_activity() la ON la.pid = l.pid
WHERE NOT b.GRANTED
ORDER BY ba.query_start;

ALTER VIEW eyes.blocked_queryes
    OWNER TO postgres;

COMMENT ON VIEW eyes.blocked_queryes
    IS 'Get all blocked queryes in database';


-- View: eyes.db_objects

CREATE OR REPLACE VIEW eyes.db_objects AS
SELECT pn.nspname AS object_schema,
    pc.relname::TEXT AS object_name,
    CASE pc.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'i' THEN 'INDEX'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 't' THEN 'TOAST'
        WHEN 'f' THEN 'FOREING TABLE'
        WHEN 'c' THEN 'COMPOSITE'
    END AS object_type,
    pg_catalog.pg_get_userbyid(pc.relowner) AS object_owner
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
WHERE  pn.nspname !~ '^pg_'
    AND pn.nspname != 'information_schema'
UNION
SELECT pn.nspname AS object_schema,
    pp.proname || '('
        || pg_catalog.pg_get_function_arguments(pp.oid)
        || ')'::TEXT AS object_name,
    'FUNCTION' AS object_type,
    pg_catalog.pg_get_userbyid(pp.proowner) AS object_owner
FROM pg_catalog.pg_proc pp
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pp.pronamespace
WHERE  pn.nspname !~ '^pg_'
    AND pn.nspname != 'information_schema';

ALTER VIEW eyes.db_objects
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_objects
    IS 'Список всех объектов в базе данных';


-- View: eyes.db_functions

CREATE OR REPLACE VIEW eyes.db_functions AS
SELECT pn.nspname AS function_schema,
    pp.proname AS function_name,
    pg_catalog.pg_get_userbyid(pp.proowner) AS function_owner,
    pg_catalog.pg_get_function_result(pp.oid) as result_data_type,
    pg_catalog.pg_get_function_arguments(pp.oid) as argument_data_type,
    pp.prosrc AS source_code,
    pl.lanname AS function_language,
    CASE
        WHEN pp.provolatile = 'i' THEN 'IMMUTABLE'
        WHEN pp.provolatile = 's' THEN 'STABLE'
        WHEN pp.provolatile = 'v' THEN 'VOLATILE'
    END as function_volatility,
    CASE
        WHEN pp.prosecdef THEN 'SECURITY DEFINER'
        ELSE 'SECURITY INVOKER'
    END AS function_security
FROM pg_catalog.pg_proc pp
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pp.pronamespace
LEFT JOIN pg_catalog.pg_language pl ON pl.oid = pp.prolang
WHERE  pn.nspname !~ '^pg_'
    AND pn.nspname != 'information_schema';

ALTER VIEW eyes.db_functions
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_functions
    IS 'Список всех функций в базе данных';


-- View: eyes.tables_size

CREATE OR REPLACE VIEW eyes.tables_size AS
SELECT ts.table_name,
    pg_size_pretty(ts.table_size) AS table_size,
    pg_size_pretty(ts.indexes_size) AS indexes_size,
    pg_size_pretty(ts.total_size) AS total_size
FROM (
    SELECT bt.table_name,
        pg_table_size(bt.table_name) AS table_size,
        pg_indexes_size(bt.table_name) AS indexes_size,
        pg_total_relation_size(bt.table_name) AS total_size
    FROM (
        SELECT
            '"' || t.table_schema || '"."' || t.table_name || '"' AS table_name
        FROM information_schema.tables t
        WHERE table_type = 'BASE TABLE'
            AND table_schema != 'information_schema'
            AND table_schema != 'pg_catalog'
        ) AS bt
    ORDER BY total_size DESC
    ) AS ts;

ALTER VIEW eyes.tables_size
    OWNER TO postgres;

COMMENT ON VIEW eyes.tables_size
    IS 'Get size all tables in currently database';


-- View: eyes.top_queryes

CREATE OR REPLACE VIEW eyes.top_queryes AS
SELECT u.usename AS username,
    d.datname AS dbname,
    ss.queryid AS queryid,
    ss.query AS query_text,
    ss.calls AS calls,
    trunc(ss.calls*100/sum(ss.calls) OVER (), 2) AS calls_pct,
    ss.total_time,
    trunc(ss.total_time*10000/sum(ss.total_time) OVER ())/100 AS total_time_pct,
    ss.blk_read_time + ss.blk_write_time AS blk_rw_time,
    CASE
        WHEN sum(ss.blk_read_time + ss.blk_write_time) OVER () != 0 THEN
            trunc((ss.blk_read_time + ss.blk_write_time)*
                10000/sum(ss.blk_read_time + ss.blk_write_time) OVER ())/100 
        ELSE 0
    END AS blk_rw_time_pct
FROM eyes.get_pg_stat_statements() ss
LEFT JOIN pg_user u ON ss.userid= u.usesysid
LEFT JOIN pg_database d ON ss.dbid = d.oid
ORDER BY ss.total_time DESC;

ALTER VIEW eyes.top_queryes
    OWNER TO postgres;

COMMENT ON VIEW eyes.tables_size
    IS 'Get top queryes from pg_stat_statements';


-- View: eyes.settings

CREATE OR REPLACE VIEW eyes.settings AS
SELECT s.name, s.setting, s.unit, s.vartype, s.context
FROM pg_settings s
ORDER BY s.name;

ALTER VIEW eyes.settings
    OWNER TO postgres;

COMMENT ON VIEW eyes.settings
    IS 'Get parameters from pg_settings';


-- View: eyes.settings_change

CREATE OR REPLACE VIEW eyes.settings_change AS
SELECT s.name, s.setting, s.boot_val, s.unit, s.vartype, s.context,
    s.source, s.sourcefile, s.sourceline
FROM pg_settings s
WHERE s.boot_val != s.reset_val
ORDER BY s.name;

ALTER VIEW eyes.settings_change
    OWNER TO postgres;

COMMENT ON VIEW eyes.settings_change
    IS 'Get chenged parameters from pg_settings';


-- View: eyes.settings_user_change

CREATE OR REPLACE VIEW eyes.settings_user_change AS
SELECT s.name, s.setting, s.reset_val, s.unit, s.vartype, s.context, s.source
FROM pg_settings s
WHERE s.setting != s.reset_val and s.context = 'user'
ORDER BY s.name;

ALTER VIEW eyes.settings_user_change
    OWNER TO postgres;

COMMENT ON VIEW eyes.settings_user_change
    IS 'Get chenged parameters for carrent session';


-- API для выполнения операций, требующих повышение привилегий


-- Sequence: eyes.execute_logid_seq

CREATE SEQUENCE eyes.execute_logid_seq
    INCREMENT 1
    MINVALUE 0
    MAXVALUE 999999999999999
    START 1
    CACHE 1;

ALTER TABLE eyes.execute_logid_seq OWNER TO postgres;


-- Table: eyes.execute_log

CREATE TABLE eyes.execute_log
(
    logid BIGINT NOT NULL DEFAULT nextval('eyes.execute_logid_seq'),
    pid INTEGER NOT NULL,
    username NAME NOT NULL,
    dbname NAME NOT NULL,
    application_name TEXT,
    client_addr INET,
    begin_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time  TIMESTAMP WITH TIME ZONE NOT NULL,
    execute_status TEXT NOT NULL,
    execute_operation TEXT NOT NULL,
    execute_info TEXT,
    CONSTRAINT execute_log_pk PRIMARY KEY (logid)
)
WITH (
    OIDS=FALSE
);

ALTER TABLE eyes.execute_log OWNER TO postgres;


-- Function: eyes.execute_log(TEXT, TEXT, TEXT)

CREATE OR REPLACE FUNCTION eyes.execute_log(
        p_begin_time TIMESTAMP WITH TIME ZONE,
        p_end_time TIMESTAMP WITH TIME ZONE,
        p_execute_status TEXT,
        p_execute_operation TEXT,
        p_execute_info TEXT)
    RETURNS BIGINT AS
$body$
DECLARE

/*
Описание:
    Запись информации о выполнении операции в таблицу eyes.execute_log

    p_begin_time        - Время начала операции
    p_end_time          - Время окончания операции
    p_execute_status    - Статус выполнения
    p_execute_operation - Выполняемая операция
    p_execute_info      - Дополнительная информация
*/

    v_logid BIGINT;

BEGIN

    v_logid := nextval('eyes.execute_logid_seq');

    INSERT INTO eyes.execute_log (logid, pid, username, dbname,
        application_name, client_addr, begin_time, end_time, execute_status,
        execute_operation, execute_info)
    VALUES (
        v_logid, pg_backend_pid(), current_user, current_catalog,
        (SELECT setting FROM pg_settings WHERE name = 'application_name'),
        inet_client_addr(), p_begin_time, p_end_time, p_execute_status,
        p_execute_operation, p_execute_info
    );

    RETURN v_logid;

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.execute_log(TIMESTAMP WITH TIME ZONE,
    TIMESTAMP WITH TIME ZONE, TEXT, TEXT, TEXT) OWNER TO postgres;


-- Function: eyes.backend_terminate(INTEGER)

CREATE OR REPLACE FUNCTION eyes.backend_terminate(p_pid INTEGER)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Выполнение функции pg_terminate_backend(p_pid)
*/

    v_terminate_status BOOLEAN;
    v_execute_status TEXT; 

BEGIN

    EXECUTE 'SELECT pg_terminate_backend($1)'
    INTO v_terminate_status
    USING p_pid;

    IF v_terminate_status THEN
        v_execute_status := 'complete';
    ELSE
        v_execute_status := 'failure';
    END IF;

    IF NOT pg_is_in_recovery() THEN
        EXECUTE 'SELECT eyes.execute_log($1, $2, $3, $4, $5)'
        USING statement_timestamp(),
            statement_timestamp(),
            v_execute_status,
            'eyes.backend_terminate(' || p_pid || ')',
            null;
    END IF;
    
    RETURN v_execute_status;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.backend_terminate(INTEGER) OWNER TO postgres;

REVOKE ALL ON FUNCTION eyes.backend_terminate(INTEGER) FROM public;


-- Function: eyes.backend_cancel(INTEGER)

CREATE OR REPLACE FUNCTION eyes.backend_cancel(p_pid INTEGER)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Выполнение функции pg_cancel_backend(p_pid)
*/

    v_terminate_status BOOLEAN;
    v_execute_status TEXT; 

BEGIN

    EXECUTE 'SELECT pg_cancel_backend($1)'
    INTO v_terminate_status
    USING p_pid;

    IF v_terminate_status THEN
        v_execute_status := 'complete';
    ELSE
        v_execute_status := 'failure';
    END IF;

    IF NOT pg_is_in_recovery() THEN
        EXECUTE 'SELECT eyes.execute_log($1, $2, $3, $4, $5)'
        USING statement_timestamp(),
            statement_timestamp(),
            v_execute_status,
            'eyes.backend_cancel(' || p_pid || ')',
            null;
    END IF;

    RETURN v_execute_status;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.backend_cancel(INTEGER) OWNER TO postgres;

REVOKE ALL ON FUNCTION eyes.backend_cancel(INTEGER) FROM public;


-- Function: eyes.trigger_enable(TEXT, TEXT)

CREATE OR REPLACE FUNCTION eyes.trigger_enable(
        p_table TEXT,
        p_trigger TEXT)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Включение триггера p_trigger для таблицы p_table
*/

    v_terminate_status BOOLEAN;
    v_execute_status TEXT; 

BEGIN

    EXECUTE 'ALTER TABLE ' || p_table || ' ENABLE TRIGGER ' || p_trigger;

    v_execute_status := 'complete';

    EXECUTE 'SELECT eyes.execute_log($1, $2, $3, $4, $5)'
    USING statement_timestamp(),
        statement_timestamp(),
        v_execute_status,
        'eyes.trigger_enable(' || quote_literal(p_table) || ', ' ||
            quote_literal(p_trigger) || ')',
        null;

    RETURN v_execute_status;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.trigger_enable(TEXT, TEXT) OWNER TO postgres;

REVOKE ALL ON FUNCTION eyes.trigger_enable(text, text) FROM public;


-- Function: eyes.trigger_disable(TEXT, TEXT)

CREATE OR REPLACE FUNCTION eyes.trigger_disable(
        p_table TEXT,
        p_trigger TEXT)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Отключение триггера p_trigger для таблицы p_table
*/

    v_execute_status TEXT; 

BEGIN

    EXECUTE 'ALTER TABLE ' || p_table || ' DISABLE TRIGGER ' || p_trigger;

    v_execute_status := 'complete';

    EXECUTE 'SELECT eyes.execute_log($1, $2, $3, $4, $5)'
    USING statement_timestamp(),
        statement_timestamp(),
        v_execute_status,
        'eyes.trigger_disable(' || quote_literal(p_table) || ', ' ||
            quote_literal(p_trigger) || ')',
        null;

    RETURN v_execute_status;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.trigger_disable(TEXT, TEXT) OWNER TO postgres;

REVOKE ALL ON FUNCTION eyes.trigger_disable(text, text) FROM public;


-- END
