-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_eyes" to load this file. \quit


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

    EXECUTE 'SELECT eyes.execute_log($1, $2, $3, $4, $5)'
    USING statement_timestamp(),
        statement_timestamp(),
        v_execute_status,
        'eyes.backend_terminate(' || p_pid || ')',
        null;

    RETURN v_execute_status;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.backend_terminate(INTEGER) OWNER TO postgres;

REVOKE ALL ON FUNCTION eyes.backend_terminate(integer) FROM public;


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

    EXECUTE 'SELECT eyes.execute_log($1, $2, $3, $4, $5)'
    USING statement_timestamp(),
        statement_timestamp(),
        v_execute_status,
        'eyes.backend_cancel(' || p_pid || ')',
        null;

    RETURN v_execute_status;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER
    COST 100;

ALTER FUNCTION eyes.backend_cancel(INTEGER) OWNER TO postgres;

REVOKE ALL ON FUNCTION eyes.backend_cancel(integer) FROM public;


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


-- API для управления привилегиями


-- Function: eyes.grant_read_in_schema(
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_read_in_schema(
        p_grantee CHARACTER VARYING,
        p_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Выдача привилегий на чтение всех объектов в указанных схемах

    p_grantee      - Имя роли
    p_schemas   - Список схем
*/

    v_schema CHARACTER VARYING;

BEGIN

    FOREACH v_schema IN ARRAY p_schemas
    LOOP

        EXECUTE 'GRANT USAGE ON SCHEMA ' ||
            v_schema || ' TO ' || p_grantee || ';';
        EXECUTE 'GRANT SELECT ON ALL TABLES IN SCHEMA ' ||
            v_schema || ' TO ' || p_grantee || ';';

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_read_in_schema(CHARACTER VARYING,
    CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_read_in_all_schemas(
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_read_in_all_schemas(
        p_grantee CHARACTER VARYING,
        p_exclude_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Выдача привилегий на чтение всех объектов во всех пользовательских схемах

    p_grantee           - Имя роли
    p_exclude_schemas   - Исключения
*/

    r record;

BEGIN

    FOR r IN SELECT n.nspname::CHARACTER VARYING AS schemaname
            FROM pg_catalog.pg_namespace n
            WHERE n.nspname !~ '^pg_'
                AND n.nspname != 'information_schema'
                AND n.nspname != ALL (p_exclude_schemas)
            ORDER BY 1
    LOOP

        EXECUTE 'SELECT eyes.grant_read_in_schema($1, $2);'
            USING p_grantee, ARRAY[r.schemaname];

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_read_in_all_schemas(CHARACTER VARYING,
    CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_read_default_in_schema(
--     CHARACTER VARYING,
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_read_default_in_schema(
        p_grantor CHARACTER VARYING,
        p_grantee CHARACTER VARYING,
        p_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Установка привилегий по умолчанию на чтение данных в указанных схемах

    p_grantor  - Роль - владелец привилегий
    p_grantee  - Роль - получатель привилегий
    p_schemas  - Список схем
*/

    v_schema CHARACTER VARYING;

BEGIN

    FOREACH v_schema IN ARRAY p_schemas
    LOOP

        EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE ' || p_grantor ||
            ' IN SCHEMA ' || v_schema || ' GRANT SELECT ON TABLES TO ' ||
            p_grantee || ';';

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_read_default_in_schema(CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_read_default_in_all_schemas(
--     CHARACTER VARYING,
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_read_default_in_all_schemas(
        p_grantor CHARACTER VARYING,
        p_grantee CHARACTER VARYING,
        p_exclude_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Установка привилегий по умолчанию на чтение всех объектов во всех
    пользовательских схемах

    p_grantee           - Имя роли
    p_exclude_schemas   - Исключения
*/

    r record;

BEGIN

    FOR r IN SELECT n.nspname::CHARACTER VARYING AS schemaname
            FROM pg_catalog.pg_namespace n
            WHERE n.nspname !~ '^pg_'
                AND n.nspname != 'information_schema'
                AND n.nspname != ALL (p_exclude_schemas)
            ORDER BY 1
    LOOP

        EXECUTE 'SELECT eyes.grant_read_default_in_schema($1, $2, $3);'
            USING p_grantor, p_grantee, ARRAY[r.schemaname];

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_read_default_in_all_schemas(CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_modify_in_schema(
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_modify_in_schema(
        p_grantee CHARACTER VARYING,
        p_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Выдача привилегий на чтение и изменение данных всех объектов в указанных
    схемах

    p_grantee   - Имя роли
    p_schemas   - Список схем
*/

    v_schema CHARACTER VARYING;

BEGIN

    FOREACH v_schema IN ARRAY p_schemas
    LOOP

        EXECUTE 'GRANT USAGE ON SCHEMA ' ||
            v_schema || ' TO ' || p_grantee || ';';
        EXECUTE 'GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA ' ||
            v_schema || ' TO ' || p_grantee || ';';
        EXECUTE 'GRANT USAGE ON ALL SEQUENCES IN SCHEMA ' ||
            v_schema || ' TO ' || p_grantee || ';';

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_modify_in_schema(CHARACTER VARYING,
    CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_modify_in_all_schemas(
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_modify_in_all_schemas(
        p_grantee CHARACTER VARYING,
        p_exclude_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Выдача привилегий на чтение и изменение данных всех объектов во всех
    пользовательских схемах

    p_grantee           - Имя роли
    p_exclude_schemas   - Исключения
*/

    r record;

BEGIN

    FOR r IN SELECT n.nspname::CHARACTER VARYING AS schemaname
            FROM pg_catalog.pg_namespace n
            WHERE n.nspname !~ '^pg_'
                AND n.nspname != 'information_schema'
                AND n.nspname != ALL (p_exclude_schemas)
            ORDER BY 1
    LOOP

        EXECUTE 'SELECT eyes.grant_modify_in_schema($1, $2);'
            USING p_grantee, ARRAY[r.schemaname];

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_modify_in_all_schemas(CHARACTER VARYING,
    CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_modify_default_in_schema(
--     CHARACTER VARYING,
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_modify_default_in_schema(
        p_grantor CHARACTER VARYING,
        p_grantee CHARACTER VARYING,
        p_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Установка привилегий по умолчанию на чтение и изменение данных в указанных
    схемах

    p_grantor  - Роль - владелец привилегий
    p_grantee  - Роль - получатель привилегий
    p_schemas  - Список схем
*/

    v_schema CHARACTER VARYING;

BEGIN

    FOREACH v_schema IN ARRAY p_schemas
    LOOP

        EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE ' || p_grantor
            || ' IN SCHEMA ' || v_schema
            || ' GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO '
            || p_grantee || ';';
        EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE ' || p_grantor ||
            ' IN SCHEMA ' || v_schema || ' GRANT USAGE ON SEQUENCES TO ' ||
            p_grantee || ';';

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_modify_default_in_schema(CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING ARRAY) OWNER TO postgres;


-- Function: eyes.grant_modify_default_in_all_schemas(
--     CHARACTER VARYING,
--     CHARACTER VARYING,
--     CHARACTER VARYING ARRAY)

CREATE OR REPLACE FUNCTION eyes.grant_modify_default_in_all_schemas(
        p_grantor CHARACTER VARYING,
        p_grantee CHARACTER VARYING,
        p_exclude_schemas CHARACTER VARYING ARRAY)
    RETURNS TEXT AS
$body$
DECLARE

/*
Описание:
    Установка привилегий по умолчанию на чтение и изменение данных всех объектов
    во всех пользовательских схемах

    p_grantee           - Имя роли
    p_exclude_schemas   - Исключения
*/

    r record;

BEGIN

    FOR r IN SELECT n.nspname::CHARACTER VARYING AS schemaname
            FROM pg_catalog.pg_namespace n
            WHERE n.nspname !~ '^pg_'
                AND n.nspname != 'information_schema'
                AND n.nspname != ALL (p_exclude_schemas)
            ORDER BY 1
    LOOP

        EXECUTE 'SELECT eyes.grant_modify_default_in_schema($1, $2, $3);'
            USING p_grantor, p_grantee, ARRAY[r.schemaname];

    END LOOP;

    RETURN 'complete';

END;
$body$
    LANGUAGE plpgsql VOLATILE
    COST 100;

ALTER FUNCTION eyes.grant_modify_default_in_all_schemas(CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING ARRAY) OWNER TO postgres;


-- END
