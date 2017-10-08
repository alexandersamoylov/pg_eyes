-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_eyes" to load this file. \quit


-- View: eyes.db_objects

DROP VIEW IF EXISTS eyes.db_objects;

CREATE OR REPLACE VIEW eyes.db_objects AS
SELECT pc.oid AS object_oid,
    pn.nspname AS schema_name,
    pc.relname AS object_name,
    CASE pc.relkind
        WHEN 'r' THEN 'table'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized view'
        WHEN 'i' THEN 'index'
        WHEN 'S' THEN 'sequence'
        WHEN 't' THEN 'toast'
        WHEN 'f' THEN 'foreign table'
        WHEN 'c' THEN 'composite'
    END AS object_type,
    pg_catalog.pg_get_userbyid(pc.relowner) AS object_owner,
    pt.spcname AS tablespace,
    pc.reloptions AS object_options
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_catalog.pg_tablespace pt ON pc.reltablespace = pt.oid
;

ALTER VIEW eyes.db_objects
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_objects
    IS 'Список объектов в базе данных';


-- View: eyes.db_tables

DROP VIEW IF EXISTS eyes.db_tables;

CREATE OR REPLACE VIEW eyes.db_tables AS
SELECT pc.oid AS table_oid,
    pn.nspname AS schema_name,
    pc.relname AS table_name,
    pg_catalog.pg_get_userbyid(pc.relowner) AS table_owner,
    pt.spcname AS tablespace,
    psat.seq_scan AS seq_scan,
    psat.seq_tup_read AS seq_tup_read,
    psat.idx_scan AS idx_scan,
    psat.idx_tup_fetch AS idx_tup_fetch,
    psat.n_tup_ins AS n_tup_ins,
    psat.n_tup_upd AS n_tup_upd,
    psat.n_tup_del AS n_tup_del,
    psat.n_tup_hot_upd AS n_tup_hot_upd
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_catalog.pg_tablespace pt ON pc.reltablespace = pt.oid
LEFT JOIN pg_catalog.pg_stat_all_tables psat ON pc.oid = psat.relid
WHERE pc.relkind = 'r'
;

ALTER VIEW eyes.db_tables
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_tables
    IS 'Список таблиц в базе данных';


-- View: eyes.db_tables_size

DROP VIEW IF EXISTS eyes.tables_size;
DROP VIEW IF EXISTS eyes.db_tables_size;

CREATE OR REPLACE VIEW eyes.db_tables_size AS
SELECT pc.oid AS table_oid,
    pn.nspname AS schema_name,
    pc.relname AS table_name,
    pg_catalog.pg_get_userbyid(pc.relowner) AS table_owner,
    pt.spcname AS tablespace,
    psat.seq_scan AS seq_scan,
    psat.seq_tup_read AS seq_tup_read,
    psat.idx_scan AS idx_scan,
    psat.idx_tup_fetch AS idx_tup_fetch,
    psat.n_tup_ins AS n_tup_ins,
    psat.n_tup_upd AS n_tup_upd,
    psat.n_tup_del AS n_tup_del,
    psat.n_tup_hot_upd AS n_tup_hot_upd,
    pg_table_size(pc.oid::regclass) AS table_size,
    pg_indexes_size(pc.oid::regclass) AS indexes_size,
    pg_total_relation_size(pc.oid::regclass) AS total_size
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_catalog.pg_tablespace pt ON pc.reltablespace = pt.oid
LEFT JOIN pg_catalog.pg_stat_all_tables psat ON pc.oid = psat.relid
WHERE pc.relkind = 'r'
;

ALTER VIEW eyes.db_tables_size
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_tables_size
    IS 'Список таблиц в базе данных с расчетом размеров';


-- View: eyes.db_indexes

DROP VIEW IF EXISTS eyes.db_indexes;

CREATE OR REPLACE VIEW eyes.db_indexes AS
SELECT psai.relid AS table_oid,
    pc.oid AS index_oid,
    pn.nspname AS schema_name,
    psai.relname AS table_name,
    pc.relname AS index_name,
    pt.spcname AS tablespace,
    pg_get_indexdef(pc.oid) AS index_def,
    psai.idx_scan AS idx_scan,
    psai.idx_tup_read AS idx_tup_read,
    psai.idx_tup_fetch AS idx_tup_fetch
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_catalog.pg_tablespace pt ON pc.reltablespace = pt.oid
LEFT JOIN pg_catalog.pg_stat_all_indexes psai ON pc.oid = psai.indexrelid
WHERE pc.relkind = 'i'
;

ALTER VIEW eyes.db_indexes
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_indexes
    IS 'Список индексов в базе данных';


-- View: eyes.db_indexes_size

DROP VIEW IF EXISTS eyes.db_indexes_size;

CREATE OR REPLACE VIEW eyes.db_indexes_size AS
SELECT psai.relid AS table_oid,
    pc.oid AS index_oid,
    pn.nspname AS schema_name,
    psai.relname AS table_name,
    pc.relname AS index_name,
    pt.spcname AS tablespace,
    pg_get_indexdef(pc.oid) AS index_def,
    psai.idx_scan AS idx_scan,
    psai.idx_tup_read AS idx_tup_read,
    psai.idx_tup_fetch AS idx_tup_fetch,
    pg_table_size(pc.oid::regclass) AS index_size
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_catalog.pg_tablespace pt ON pc.reltablespace = pt.oid
LEFT JOIN pg_catalog.pg_stat_all_indexes psai ON pc.oid = psai.indexrelid
WHERE pc.relkind = 'i'
;

ALTER VIEW eyes.db_indexes_size
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_indexes_size
    IS 'Список индексов в базе данных с расчетом размеров';


-- View: eyes.db_attributes

DROP VIEW IF EXISTS eyes.db_attributes;

CREATE OR REPLACE VIEW eyes.db_attributes AS
SELECT pc.oid AS object_oid,
    pn.nspname AS schema_name,
    pc.relname AS object_name,
    CASE pc.relkind
        WHEN 'r' THEN 'table'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized view'
        WHEN 'i' THEN 'index'
        WHEN 'S' THEN 'sequence'
        WHEN 't' THEN 'toast'
        WHEN 'f' THEN 'foreign table'
        WHEN 'c' THEN 'composite'
    END AS object_type,
    pa.attnum AS attribute_num,
    pa.attname AS attribute_name,
    pg_catalog.format_type(pa.atttypid, pa.atttypmod) AS attribute_type,
    pa.attnotnull AS is_not_null
FROM pg_catalog.pg_class pc
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pc.relnamespace
LEFT JOIN pg_catalog.pg_tablespace pt ON pc.reltablespace = pt.oid
LEFT JOIN pg_catalog.pg_attribute pa ON pc.oid = pa.attrelid
    AND pa.attnum > 0
    AND NOT pa.attisdropped
;

ALTER VIEW eyes.db_attributes
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_attributes
    IS 'Список атрибутов в базе данных';


-- View: eyes.db_functions

DROP VIEW IF EXISTS eyes.db_functions;

CREATE OR REPLACE VIEW eyes.db_functions AS
SELECT pp.oid AS function_oid,
    pn.nspname AS schema_name,
    pp.proname || '(' || pg_get_function_identity_arguments(pp.oid) || ')'
        AS function_name,
    pg_catalog.pg_get_userbyid(pp.proowner) AS function_owner,
    CASE
        WHEN proisagg THEN null
        ELSE pg_get_functiondef(pp.oid)
    END AS function_def
FROM pg_catalog.pg_proc pp
LEFT JOIN pg_catalog.pg_namespace pn ON pn.oid = pp.pronamespace
LEFT JOIN pg_catalog.pg_language pl ON pl.oid = pp.prolang
;

ALTER VIEW eyes.db_functions
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_functions
    IS 'Список функций в базе данных';


-- View: eyes.db_settings

DROP VIEW IF EXISTS eyes.settings;
DROP VIEW IF EXISTS eyes.settings_change;
DROP VIEW IF EXISTS eyes.settings_user_change;

CREATE OR REPLACE VIEW eyes.db_settings AS
SELECT s.name AS name,
    current_setting(s.name) AS setting,
    s.context AS context,
    s.source AS source,
    s.sourcefile AS sourcefile,
    s.sourceline AS sourceline
FROM pg_settings s
ORDER BY s.name;

ALTER VIEW eyes.db_settings
    OWNER TO postgres;

COMMENT ON VIEW eyes.db_settings
    IS 'Список параметров';


-- END
