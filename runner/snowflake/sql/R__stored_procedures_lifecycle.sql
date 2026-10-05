-- =============================================================================
-- Matillion Runner on Snowpark Container Services - lifecycle operations
-- =============================================================================
--
-- Scale/stop/start/restart for a runner already deployed via
-- admin.deploy_runner() in R__stored_procedures.sql.
--
-- Deployed via schemachange (https://github.com/Snowflake-Labs/schemachange)
-- as a REPEATABLE (R) script - not run directly, see
-- ../scripts/install-library.py and ../README.md for the day-to-day
-- runbook.
--
-- Depends on the helper functions (admin.is_valid_identifier) defined in
-- R__stored_procedures.sql - this filename is chosen to sort after it
-- alphabetically ("R__stored_procedures.sql" < "R__stored_procedures_
-- lifecycle.sql"), since schemachange applies repeatable scripts in
-- alphabetical order and that file must already have run first.
-- =============================================================================

USE DATABASE matillion_runners;

-- -----------------------------------------------------------------------------
-- Repeatable operations: scale, restart, stop, start
-- -----------------------------------------------------------------------------

-- Resizes both the service AND the compute pool it runs on, to a fixed
-- count: runners don't autoscale, so each range is pinned to one number.
-- Resizing only the service could ask for more instances than the pool has
-- nodes, stranding the extra instances as pending indefinitely.
--
-- Note this maps one instance to one node. That holds while an instance
-- fills its node, which it does at the default CPU_X64_XS; a larger
-- instance family packing several instances per node would over-provision
-- the pool.
CREATE OR REPLACE PROCEDURE admin.scale_runner(runner_name STRING, instances INTEGER)
RETURNS STRING LANGUAGE SQL EXECUTE AS OWNER
AS
$$
DECLARE
    -- UPPER: admin.runners stores runner_name uppercase, and '=' on a STRING
    -- column is case-sensitive even though the object names Snowflake builds
    -- from it are not. See the header of R__stored_procedures.sql.
    pool_name STRING DEFAULT (SELECT compute_pool FROM admin.runners WHERE runner_name = UPPER(:runner_name));
    current_instances INTEGER DEFAULT (SELECT instances FROM admin.runners WHERE runner_name = UPPER(:runner_name));
    growing BOOLEAN;
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;
    IF (:instances < 1) THEN
        RETURN 'Invalid instances: must be at least 1';
    END IF;
    IF (:pool_name IS NULL) THEN
        RETURN 'Runner not found: ' || :runner_name;
    END IF;

    -- Order matters, and it's the opposite in each direction. Growing: the
    -- pool has to have the nodes before the service asks for the instances,
    -- or the extra instances sit pending until the pool catches up.
    -- Shrinking: the service has to give the instances up before the pool
    -- takes the nodes away.
    growing := (:instances >= :current_instances);

    IF (growing) THEN
        EXECUTE IMMEDIATE 'ALTER COMPUTE POOL IDENTIFIER(''' || :pool_name || ''')' ||
            ' SET MIN_NODES = ' || :instances || ' MAX_NODES = ' || :instances;
        EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name ||
            ' SET MIN_INSTANCES = ' || :instances || ', MAX_INSTANCES = ' || :instances;
    ELSE
        EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name ||
            ' SET MIN_INSTANCES = ' || :instances || ', MAX_INSTANCES = ' || :instances;
        EXECUTE IMMEDIATE 'ALTER COMPUTE POOL IDENTIFIER(''' || :pool_name || ''')' ||
            ' SET MIN_NODES = ' || :instances || ' MAX_NODES = ' || :instances;
    END IF;

    UPDATE admin.runners SET instances = :instances,
        updated_at = CURRENT_TIMESTAMP() WHERE runner_name = UPPER(:runner_name);
    RETURN 'Scaled ' || :runner_name || ' (service and compute pool) to ' || :instances || ' instance(s)';
END;
$$;

-- stop_runner and start_runner check the registry so that an unknown
-- runner gets a clear message rather than Snowflake's "does not exist".
CREATE OR REPLACE PROCEDURE admin.stop_runner(runner_name STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS OWNER
AS
$$
DECLARE
    registered BOOLEAN DEFAULT (SELECT COUNT(*) > 0 FROM admin.runners WHERE runner_name = UPPER(:runner_name));
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;
    IF (NOT registered) THEN
        RETURN 'Runner not found: ' || :runner_name;
    END IF;
    EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name || ' SUSPEND';
    RETURN 'Stopped ' || :runner_name;
END;
$$;

CREATE OR REPLACE PROCEDURE admin.start_runner(runner_name STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS OWNER
AS
$$
DECLARE
    registered BOOLEAN DEFAULT (SELECT COUNT(*) > 0 FROM admin.runners WHERE runner_name = UPPER(:runner_name));
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;
    IF (NOT registered) THEN
        RETURN 'Runner not found: ' || :runner_name;
    END IF;
    EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name || ' RESUME';
    RETURN 'Started ' || :runner_name;
END;
$$;

-- Restarts the *same* container instance - it does not change which image is
-- running, and it is NOT a graceful drain: in-flight work on that container
-- is interrupted, same as ALTER SERVICE ... FROM SPECIFICATION. For rolling
-- out new code, pause the runner in Matillion first and only then restart
-- it - see ../README.md, "Limitations".
--
-- SUSPEND returns before the service has actually suspended, so this waits
-- for the service to reach SUSPENDED before resuming. Issuing RESUME against
-- a service still draining either errors or does nothing, and the bare
-- stop-then-start version of this would report 'Restarted' either way,
-- leaving a service that is simply suspended.
CREATE OR REPLACE PROCEDURE admin.restart_runner(runner_name STRING)
RETURNS STRING LANGUAGE SQL EXECUTE AS OWNER
AS
$$
DECLARE
    -- ~60s at 3s per attempt. A service that hasn't suspended by then has a
    -- problem that silently resuming it would only hide.
    max_attempts INTEGER DEFAULT 20;
    attempt INTEGER DEFAULT 0;
    suspended BOOLEAN DEFAULT FALSE;
    step_result STRING;
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;

    -- These procedures signal failure by RETURNING a string, not by raising,
    -- so their result has to be read. Discarding it (as this procedure
    -- previously did) reports 'Restarted' even when neither step ran.
    CALL admin.stop_runner(:runner_name);
    step_result := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    IF (step_result NOT LIKE 'Stopped%') THEN
        RETURN step_result;
    END IF;

    WHILE (attempt < max_attempts AND NOT suspended) DO
        CALL SYSTEM$WAIT(3);
        -- Exact-match filter rather than a LIKE pattern, for the same
        -- underscore-as-wildcard reason as R__stored_procedures.sql.
        EXECUTE IMMEDIATE 'SHOW SERVICES IN SCHEMA runners';
        suspended := (SELECT COUNT(*) > 0 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
            WHERE "name" = UPPER(:runner_name) AND "status" = 'SUSPENDED');
        attempt := attempt + 1;
    END WHILE;

    IF (NOT suspended) THEN
        RETURN 'Timed out waiting for ' || :runner_name ||
            ' to suspend - it has NOT been resumed. Check SHOW SERVICES IN SCHEMA runners, then call admin.start_runner once it reports SUSPENDED';
    END IF;

    CALL admin.start_runner(:runner_name);
    step_result := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    IF (step_result NOT LIKE 'Started%') THEN
        RETURN step_result;
    END IF;

    RETURN 'Restarted ' || :runner_name;
END;
$$;

GRANT USAGE ON PROCEDURE admin.scale_runner(STRING, INTEGER) TO ROLE runner_operator;
GRANT USAGE ON PROCEDURE admin.stop_runner(STRING) TO ROLE runner_operator;
GRANT USAGE ON PROCEDURE admin.start_runner(STRING) TO ROLE runner_operator;
GRANT USAGE ON PROCEDURE admin.restart_runner(STRING) TO ROLE runner_operator;
