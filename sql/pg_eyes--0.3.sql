-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_eyes" to load this file. \quit


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
Description:
    Get statistic at database activity
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

    SELECT sum(xact_commit + xact_rollback) AS xact_total,
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
        INTO v_xact_total, v_xact_commit, v_xact_rollback, v_blks_read,
            v_blks_hit, v_tup_returned, v_tup_fetched, v_tup_inserted,
            v_tup_updated, v_tup_deleted, v_conflicts, v_temp_files,
            v_temp_bytes, v_deadlocks
    FROM pg_stat_database;

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

    RETURN;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.get_activity()
    OWNER TO postgres;

COMMENT ON FUNCTION eyes.get_activity()
    IS 'Get statistic at database activity';


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

CREATE OR REPLACE VIEW eyes.active_queryes AS
SELECT sa.pid, sa.usename, sa.datname, sa.client_addr,
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
    IS 'Get all active queryes in database';


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


-- END
