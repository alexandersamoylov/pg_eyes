-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_eyes" to load this file. \quit


-- View: eyes.active_queryes

DROP VIEW eyes.active_queryes;

CREATE OR REPLACE VIEW eyes.active_queryes AS
SELECT sa.pid, sa.usename, sa.datname, sa.client_addr, application_name,
    now() - sa.xact_start AS xact_time,
    CASE
        WHEN sa.state = 'active' THEN now() - sa.query_start
        ELSE '00:00:00'
    END AS query_time,
    now() - sa.state_change AS state_time,
    sa.waiting, sa.state, sa.query
FROM eyes.get_pg_stat_activity() sa
WHERE sa.state != 'idle'
ORDER BY sa.xact_start;

ALTER VIEW eyes.active_queryes
    OWNER TO postgres;

COMMENT ON VIEW eyes.active_queryes
    IS 'Список всех активных запросов в базе данных';


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
    v_waiting bigint;
    v_waiting_1s bigint;
    v_waiting_time bigint;
    v_autovacuum bigint;
    v_autovacuum_time bigint;

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

    r record;

BEGIN

    -- Get pg_stat_activity

    SELECT count(1) AS total,
        count(*) FILTER (WHERE state = 'active') AS active,
        count(*) FILTER (WHERE state = 'active'
            AND now() - query_start > interval '1s') AS active_1s,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE state = 'active'),
            0) AS active_time,
        count(*) FILTER (WHERE state = 'idle') AS idle,
        count(*) FILTER (WHERE state LIKE 'idle in%') AS idle_in_tr,
        count(*) FILTER (WHERE state LIKE 'idle in%'
            AND statement_timestamp() - state_change > interval '1s')
            AS idle_in_tr_1s,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            state_change))*1000)) FILTER (WHERE state LIKE 'idle in%'),
            0) AS idle_in_tr_time,      
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            xact_start))*1000)) FILTER (WHERE state != 'idle'),
            0) AS xact_time,
        count(*) FILTER (WHERE waiting) AS waiting,
        count(*) FILTER (WHERE waiting
            AND statement_timestamp() - query_start > interval '1s')
            AS waiting_1s,   
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE waiting),
            0) AS waiting_time,    
        count(*) FILTER (WHERE state = 'active' AND query LIKE 'autovacuum:%')
            AS autovacuum,
        coalesce(max(round(extract(epoch FROM age(statement_timestamp(),
            query_start))*1000)) FILTER (WHERE state = 'active'
            AND query LIKE 'autovacuum:%'), 0) AS autovacuum_time          
        INTO v_total,
            v_active, v_active_1s, v_active_time,
            v_idle, v_idle_in_tr, v_idle_in_tr_1s, v_idle_in_tr_time,
            v_xact_time, v_waiting, v_waiting_1s, v_waiting_time,
            v_autovacuum, v_autovacuum_time
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
    stat_name := 'pg_stat_activity.waiting';
    stat_value := v_waiting;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.waiting_1s';
    stat_value := v_waiting_1s;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.waiting_time';
    stat_value := v_waiting_time;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.autovacuum';
    stat_value := v_autovacuum;
    RETURN NEXT;
    stat_name := 'pg_stat_activity.autovacuum_time';
    stat_value := v_autovacuum_time;
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
        -- If primary database
        v_is_in_recovery := 0;
        v_ms_lag := 0;
        -- Fake update to test replication
        v_last_update_status := eyes.update_time();
        -- Check the streaming replication lag
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
        -- If standby database
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


-- END
