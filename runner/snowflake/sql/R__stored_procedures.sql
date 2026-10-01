-- =============================================================================
-- Matillion Runner on Snowpark Container Services - stored procedure library
-- =============================================================================
--
-- Deployed via schemachange (https://github.com/Snowflake-Labs/schemachange)
-- as a REPEATABLE (R) script - not run directly, see
-- ../scripts/install-library.py and ../README.md for the day-to-day
-- runbook. Repeatable scripts rerun automatically whenever their content
-- changes (schemachange tracks a checksum), which is exactly the semantics
-- procedure/function definitions want: no version bookkeeping needed here,
-- just edit this file and redeploy.
--
-- Covers deploy/remove/list/logs only. Lifecycle operations
-- (scale/stop/start/restart) and image update/rollback live in their own
-- repeatable scripts - R__stored_procedures_lifecycle.sql and
-- R__stored_procedures_rollback.sql - each depending on the
-- helper functions defined here, hence the filename ordering (schemachange
-- applies repeatable scripts alphabetically): both sort after this file.
--
-- Note this does NOT make CREATE OR REPLACE PROCEDURE safe against a
-- signature change on its own - schemachange rerunning this file doesn't
-- change Snowflake's own behaviour, where an added/removed parameter
-- creates a new, ambiguous overload instead of replacing the old one
-- (confirmed live). If a future edit changes a
-- procedure's signature, add the DROP PROCEDURE IF EXISTS <old signature>
-- for it directly in this file, ahead of the new CREATE OR REPLACE - since
-- there's no real prior-version history to preserve right now, none is
-- carried here; this note is what future changes should follow instead of
-- re-inventing the mechanism from scratch.
--
-- To see what's actually been applied to a given account, including
-- exactly when this file last changed and whether it succeeded:
--   SELECT * FROM matillion_runners.public.change_history ORDER BY installed_on;
--
-- Run V1.0.0__install_library.sql first. Each procedure below derives
-- object names from runner_name (e.g. "<runner_name>_RUNNER_POOL" for the
-- compute pool, "RUNNERS.<runner_name>" for the service,
-- "<runner_name>_RUNNER_ROLE" for the role that owns the service), so the
-- same installed library can manage several independent runners in one
-- account.
--
-- The procedures run EXECUTE AS OWNER, as the role that installed the
-- library. Services are the exception: each is owned by its own runner role
-- (see deploy_runner), which is granted to the installing role so that these
-- procedures can still alter and drop it.
--
-- All procedures use EXECUTE IMMEDIATE with string-built SQL to parameterise
-- identifiers, since identifiers can't be bind variables in every clause.
-- That means every value concatenated into one of these strings - not just
-- runner_name - MUST be validated first. See admin.is_valid_identifier() and
-- admin.is_valid_image_ref() below.
--
-- runner_name is case-INSENSITIVE to the caller but stored UPPERCASE in
-- admin.runners. Snowflake folds the unquoted identifiers these procedures
-- build (secrets, compute pool, service) to uppercase, so CALLing with
-- 'myrunner' and later 'MYRUNNER' addresses the same physical objects - but
-- admin.runners.runner_name is a plain STRING column, where '=' is
-- case-sensitive. Without normalising, the second call would resize the real
-- service while silently updating zero registry rows, or MERGE a duplicate
-- row for a runner that already exists. Every read and write of
-- admin.runners.runner_name therefore goes through UPPER(), here and in
-- R__stored_procedures_lifecycle.sql / R__stored_procedures_rollback.sql.
-- =============================================================================

USE DATABASE matillion_runners;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------

-- 64 chars total (1 + up to 63) is a deliberate, generous cap for a
-- runner/pool/warehouse name segment - well under Snowflake's own 255-char
-- identifier limit, not an attempt to match it.
CREATE OR REPLACE FUNCTION admin.is_valid_identifier(name STRING)
RETURNS BOOLEAN
AS
$$
  name REGEXP '^[a-zA-Z][a-zA-Z0-9_]{0,63}$'
$$;

-- Allow-list for image references passed into admin.build_runner_spec(),
-- which gets embedded, unescaped, inside the dollar-quoted spec text handed
-- to CREATE/ALTER SERVICE ... FROM SPECIFICATION. Deliberately excludes "$"
-- (a value containing a repeated dollar-sign pair matching the runtime-built
-- delimiter could otherwise terminate that dollar-quoted text early)
-- alongside anything else that isn't a legitimate
-- registry/repository/tag/digest character. 512 chars total accommodates a
-- long registry hostname plus a full "@sha256:<64 hex chars>" digest
-- reference, which a 256-char cap could reject.
CREATE OR REPLACE FUNCTION admin.is_valid_image_ref(image_path STRING)
RETURNS BOOLEAN
AS
$$
  image_path REGEXP '^[a-zA-Z0-9]([a-zA-Z0-9_./:@-]{0,511})$'
$$;

-- Defence in depth for any value concatenated into a single-quoted SQL
-- string literal built for EXECUTE IMMEDIATE (e.g. secret values). Escapes a
-- literal backslash first, then the single quote itself - Snowflake string
-- literals treat backslash as an escape character, so escaping the quote
-- alone is not sufficient if the value can end in one. Verified live on
-- every CI run against a value containing both an embedded single quote
-- and a trailing backslash - see ../scripts/verify-escape-sql-string.sql,
-- run by the live-deploy job in
-- ../../../.github/workflows/snowflake-test.yml.
CREATE OR REPLACE FUNCTION admin.escape_sql_string(value STRING)
RETURNS STRING
AS
$$
  REPLACE(REPLACE(value, '\\', '\\\\'), '''', '''''')
$$;

-- Returns the service spec YAML for a given runner, with secret names and
-- image substituted in. Same container shape as the Native App's service
-- spec.
CREATE OR REPLACE FUNCTION admin.build_runner_spec(runner_name STRING, image_path STRING)
RETURNS STRING
AS
$$
  'spec:\n' ||
  '  containers:\n' ||
  '  - name: cloud-agent\n' ||
  '    image: ' || image_path || '\n' ||
  '    readinessProbe:\n        port: 8080\n        path: /actuator/health\n' ||
  '    env:\n      CLOUD_PROVIDER: SNOWFLAKE\n' ||
  '      SNOWPARK_SECRET_EAI: "matillion_runner_eai"\n' ||
  '    secrets:\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_ACCOUNT_ID\n        envVarName: ACCOUNT_ID\n        secretKeyRef: secret_string\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_AGENT_ID\n        envVarName: AGENT_ID\n        secretKeyRef: secret_string\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_CREDENTIALS\n        envVarName: OAUTH_CLIENT_ID\n        secretKeyRef: username\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_CREDENTIALS\n        envVarName: OAUTH_CLIENT_SECRET\n        secretKeyRef: password\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_REGION\n        envVarName: MATILLION_REGION\n        secretKeyRef: secret_string\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_ENVIRONMENT\n        envVarName: MATILLION_ENV\n        secretKeyRef: secret_string\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_DEFAULT_KEYVAULT\n        envVarName: DEFAULT_KEYVAULT\n        secretKeyRef: secret_string\n' ||
  '      - snowflakeSecret: SECRETS.' || runner_name || '_EXPORT_LOGS\n        envVarName: EXPORT_LOGS\n        secretKeyRef: secret_string\n' ||
  '    resources:\n        requests:\n          memory: 4Gi\n          cpu: 1\n        limits:\n          memory: 4Gi\n          cpu: 1\n' ||
  '  endpoints:\n    - name: http\n      port: 8080\n' ||
  '  logExporters:\n    eventTableConfig:\n      logLevel: INFO\n'
  -- NOTE: the Native App's certificate/driver volume mounts are omitted here
  -- for brevity - add a volumes/volumeMounts block if that feature is needed
  -- for this deployment path.
$$;

-- -----------------------------------------------------------------------------
-- Deploy a new runner (or re-apply desired state to an existing one)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE admin.deploy_runner(
    runner_name STRING,
    image_path STRING,
    warehouse_name STRING,
    account_id STRING,
    agent_id STRING,
    matillion_region STRING,
    -- A fixed count: runners don't autoscale, so the compute pool's node
    -- range and the service's instance range are both pinned to it.
    instances INTEGER DEFAULT 1,
    instance_family STRING DEFAULT 'CPU_X64_XS',
    -- Mirrors the Native App's own defaults: environment
    -- is normally blank unless told otherwise by Matillion, log sharing
    -- defaults on, and the keyvault defaults to this database's own SECRETS
    -- schema (where this procedure creates its secrets, below). Like the
    -- Native App, the keyvault can be pointed elsewhere: <database>.<schema>.
    matillion_env STRING DEFAULT '',
    export_logs BOOLEAN DEFAULT true,
    default_keyvault STRING DEFAULT NULL
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    -- UPPER here, not just at the comparison sites: this value is both
    -- concatenated into object names (which Snowflake folds anyway) and
    -- stored in admin.runners.compute_pool (which it does not).
    pool_name STRING DEFAULT UPPER(:runner_name) || '_RUNNER_POOL';
    spec STRING;
    dollar_quote STRING DEFAULT CHR(36) || CHR(36);
    -- Uppercased to match how Snowflake stores the unquoted names it is
    -- compared against below.
    keyvault STRING DEFAULT UPPER(COALESCE(:default_keyvault, CURRENT_DATABASE() || '.SECRETS'));
    -- Owns this runner's service; see "Runner role" below.
    runner_role STRING DEFAULT UPPER(:runner_name) || '_RUNNER_ROLE';
    -- Inside an EXECUTE AS OWNER procedure this is the owner, i.e. the role
    -- that installed the library.
    owner_role STRING DEFAULT CURRENT_ROLE();
    runner_role_owner STRING;
    create_service_proc STRING DEFAULT 'admin.' || UPPER(:runner_name) || '_CREATE_SERVICE';
    create_service_stmt STRING;
    credentials_type STRING;
    pool_exists BOOLEAN;
    service_exists BOOLEAN;
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name: use letters, numbers and underscores, starting with a letter';
    END IF;
    IF (NOT admin.is_valid_identifier(:warehouse_name)) THEN
        RETURN 'Invalid warehouse_name: use letters, numbers and underscores, starting with a letter';
    END IF;
    IF (NOT admin.is_valid_identifier(:instance_family)) THEN
        RETURN 'Invalid instance_family';
    END IF;
    IF (NOT admin.is_valid_image_ref(:image_path)) THEN
        RETURN 'Invalid image_path: expected a plain registry/repository[:tag|@digest] reference';
    END IF;
    IF (:instances < 1) THEN
        RETURN 'Invalid instances: must be at least 1';
    END IF;

    -- The operator creates the credentials secret directly, not through a
    -- procedure (see V1.0.0__install_library.sql for why), and it must exist
    -- before the service spec can reference it. Fail loudly rather than
    -- deploying a service that will crash-loop on a missing secret (see
    -- ../README.md, "Troubleshooting", for exactly that failure mode -
    -- previously caught only by reading container logs). The type is checked
    -- too: the spec reads its username and password fields, which only a
    -- PASSWORD secret has.
    -- No LIKE pattern here deliberately - runner_name is validated above to
    -- allow underscores, which LIKE treats as a single-character wildcard,
    -- so a pattern-based match could false-positive against an unrelated
    -- secret (e.g. "test_runner" matching "testXrunner"). SHOW without a
    -- pattern plus an exact filter on the returned "name" column avoids
    -- that regardless of what characters the identifier contains.
    EXECUTE IMMEDIATE 'SHOW SECRETS IN SCHEMA secrets';
    credentials_type := (SELECT MAX("secret_type") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "name" = UPPER(:runner_name) || '_CREDENTIALS');
    IF (credentials_type IS NULL) THEN
        RETURN 'No credentials configured for ' || :runner_name ||
            ' - create secret matillion_runners.secrets.' || :runner_name ||
            '_credentials first (see README, "Set credentials, then deploy"), then retry admin.deploy_runner';
    END IF;
    IF (credentials_type != 'PASSWORD') THEN
        RETURN 'Secret matillion_runners.secrets.' || :runner_name || '_credentials is TYPE = ' ||
            credentials_type || ' - recreate it as TYPE = PASSWORD, then retry admin.deploy_runner';
    END IF;

    -- Only the shape is checked. The runner reads the keyvault as its own
    -- role, which is created below, so a keyvault outside this database can
    -- only be granted to it after the first deploy - see ../README.md,
    -- "Pipeline secrets".
    IF (ARRAY_SIZE(SPLIT(:keyvault, '.')) != 2
        OR NOT admin.is_valid_identifier(SPLIT_PART(:keyvault, '.', 1))
        OR NOT admin.is_valid_identifier(SPLIT_PART(:keyvault, '.', 2))) THEN
        RETURN 'Invalid default_keyvault: expected <database>.<schema>';
    END IF;

    -- Runner role. A service runs with its owner role's privileges, and
    -- Snowflake can't transfer a service's ownership, so the service is
    -- created as a role of its own (below) holding only what the container
    -- needs at runtime, rather than as this procedure's owner. Refuse a role
    -- of that name that this library didn't create: the runner would
    -- otherwise run with whatever that role already holds.
    EXECUTE IMMEDIATE 'SHOW ROLES';
    runner_role_owner := (SELECT MAX("owner") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "name" = :runner_role);
    IF (runner_role_owner IS NULL) THEN
        EXECUTE IMMEDIATE 'CREATE ROLE ' || :runner_role;
    ELSEIF (runner_role_owner != :owner_role) THEN
        RETURN 'Role ' || :runner_role || ' already exists and is owned by ' || runner_role_owner ||
            ', not by the role that owns this library - drop or rename it, then retry admin.deploy_runner';
    END IF;
    -- Lets the other procedures alter, suspend and drop the service, which
    -- only its owner can do.
    EXECUTE IMMEDIATE 'GRANT ROLE ' || :runner_role || ' TO ROLE "' || :owner_role || '"';

    -- IDENTIFIER(<expression>) naming a dynamically-built object name is only
    -- accepted inside dynamic SQL (EXECUTE IMMEDIATE), not as a static
    -- statement in a Scripting body - confirmed live, "unexpected '('" at
    -- compile time otherwise.
    EXECUTE IMMEDIATE
        'CREATE OR REPLACE SECRET IDENTIFIER(''secrets.' || :runner_name || '_account_id'')' ||
        ' TYPE = GENERIC_STRING SECRET_STRING = ''' || admin.escape_sql_string(:account_id) || '''';
    EXECUTE IMMEDIATE
        'CREATE OR REPLACE SECRET IDENTIFIER(''secrets.' || :runner_name || '_agent_id'')' ||
        ' TYPE = GENERIC_STRING SECRET_STRING = ''' || admin.escape_sql_string(:agent_id) || '''';
    EXECUTE IMMEDIATE
        'CREATE OR REPLACE SECRET IDENTIFIER(''secrets.' || :runner_name || '_region'')' ||
        ' TYPE = GENERIC_STRING SECRET_STRING = ''' || admin.escape_sql_string(:matillion_region) || '''';
    EXECUTE IMMEDIATE
        'CREATE OR REPLACE SECRET IDENTIFIER(''secrets.' || :runner_name || '_environment'')' ||
        ' TYPE = GENERIC_STRING SECRET_STRING = ''' || admin.escape_sql_string(:matillion_env) || '''';
    EXECUTE IMMEDIATE
        'CREATE OR REPLACE SECRET IDENTIFIER(''secrets.' || :runner_name || '_default_keyvault'')' ||
        ' TYPE = GENERIC_STRING SECRET_STRING = ''' || admin.escape_sql_string(:keyvault) || '''';
    EXECUTE IMMEDIATE
        'CREATE OR REPLACE SECRET IDENTIFIER(''secrets.' || :runner_name || '_export_logs'')' ||
        ' TYPE = GENERIC_STRING SECRET_STRING = ''' || IFF(:export_logs, 'true', 'false') || '''';

    -- CREATE COMPUTE POOL IF NOT EXISTS is a silent no-op on a rerun with
    -- different sizing - the registry table below would then record a size
    -- the real pool doesn't have. Branch explicitly instead: create it if
    -- it's genuinely new, otherwise resize the existing one to match.
    -- See the comment on the secrets check above - exact-match filter
    -- instead of a LIKE pattern, for the same underscore-wildcard reason.
    EXECUTE IMMEDIATE 'SHOW COMPUTE POOLS';
    pool_exists := (SELECT COUNT(*) > 0 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "name" = UPPER(:pool_name));
    IF (pool_exists) THEN
        EXECUTE IMMEDIATE
            'ALTER COMPUTE POOL IDENTIFIER(''' || :pool_name || ''')' ||
            ' SET MIN_NODES = ' || :instances || ' MAX_NODES = ' || :instances;
    ELSE
        EXECUTE IMMEDIATE
            'CREATE COMPUTE POOL IDENTIFIER(''' || :pool_name || ''')' ||
            ' MIN_NODES = ' || :instances ||
            ' MAX_NODES = ' || :instances ||
            ' INSTANCE_FAMILY = ' || :instance_family;
    END IF;

    -- Everything the running container uses, and nothing else. Reapplied on
    -- every deploy: CREATE OR REPLACE SECRET above drops the grants on the
    -- secrets it replaces. The credentials secret is owned by runner_operator,
    -- not by the installing role; granting on it works because
    -- V1.0.0__install_library.sql grants runner_operator to the installing role.
    EXECUTE IMMEDIATE 'GRANT USAGE ON DATABASE ' || CURRENT_DATABASE() || ' TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT USAGE ON SCHEMA admin TO ROLE ' || :runner_role; -- for the image repository
    EXECUTE IMMEDIATE 'GRANT USAGE ON SCHEMA runners TO ROLE ' || :runner_role;
    -- The runner reads a pipeline secret by creating a temporary Python UDF
    -- bound to it, in its session's schema - the service's own - then
    -- dropping it.
    -- Each runner role owns, and can call, only the functions it creates.
    EXECUTE IMMEDIATE 'GRANT CREATE FUNCTION ON SCHEMA runners TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT USAGE ON SCHEMA secrets TO ROLE ' || :runner_role;
    -- Secrets created for the agent from Matillion are written by the runner
    -- into its keyvault. It can add new ones, but can't replace secrets it
    -- doesn't own - other runners', or its own configuration below. Only
    -- this library's own schema is granted here; see ../README.md,
    -- "Pipeline secrets", for a keyvault elsewhere. Revoked when the keyvault
    -- moves, so a runner doesn't keep writing to one it no longer uses.
    IF (:keyvault = UPPER(CURRENT_DATABASE() || '.SECRETS')) THEN
        EXECUTE IMMEDIATE 'GRANT CREATE SECRET ON SCHEMA secrets TO ROLE ' || :runner_role;
    ELSE
        EXECUTE IMMEDIATE 'REVOKE CREATE SECRET ON SCHEMA secrets FROM ROLE ' || :runner_role;
    END IF;
    EXECUTE IMMEDIATE 'GRANT READ ON IMAGE REPOSITORY admin.runner_images TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT USAGE ON COMPUTE POOL ' || :pool_name || ' TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT USAGE ON INTEGRATION matillion_runner_eai TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_account_id TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_agent_id TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_credentials TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_region TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_environment TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_default_keyvault TO ROLE ' || :runner_role;
    EXECUTE IMMEDIATE 'GRANT READ, USAGE ON SECRET secrets.' || :runner_name || '_export_logs TO ROLE ' || :runner_role;
    BEGIN
        EXECUTE IMMEDIATE 'GRANT USAGE ON WAREHOUSE ' || :warehouse_name || ' TO ROLE ' || :runner_role;
    EXCEPTION
        WHEN OTHER THEN
            RETURN 'Could not grant USAGE on warehouse ' || :warehouse_name || ' to ' || :runner_role ||
                ' - the role that owns this library must own the warehouse, or hold USAGE on it WITH GRANT OPTION (see README, "Prerequisites")';
    END;

    spec := admin.build_runner_spec(:runner_name, :image_path);

    -- Same reasoning as the compute pool above: CREATE SERVICE IF NOT
    -- EXISTS silently leaves an already-running service untouched, so a
    -- redeploy with a new image or instance count would report "deployed"
    -- while the real container keeps running the old spec. Branch instead.
    --
    -- Two things confirmed live on the original happy-path version of this
    -- procedure, both the hard way:
    -- 1) CREATE/ALTER SERVICE's inline-spec clause is "FROM SPECIFICATION
    --    <text>" - no "=" - so "FROM SPECIFICATION=..." is a syntax error
    --    regardless of how the text after it is quoted.
    -- 2) A literal repeated-dollar-sign pair anywhere in this procedure's
    --    *source text* - even inside a comment - closes the outer
    --    dollar-quoted body early and breaks compilation. So the spec text
    --    is dollar-quoted using a pair built at runtime via CHR(36) instead
    --    of ever writing two "$" characters adjacent in this file.
    -- See the comment on the secrets check above - exact-match filter
    -- instead of a LIKE pattern, for the same underscore-wildcard reason.
    EXECUTE IMMEDIATE 'SHOW SERVICES IN SCHEMA runners';
    service_exists := (SELECT COUNT(*) > 0 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "name" = UPPER(:runner_name));
    IF (service_exists) THEN
        EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name ||
            ' FROM SPECIFICATION ' || :dollar_quote || :spec || :dollar_quote;
        EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name ||
            ' SET MIN_INSTANCES = ' || :instances || ', MAX_INSTANCES = ' || :instances;
    ELSE
        -- A service is owned by the role that runs CREATE SERVICE. To run it
        -- as the runner role, create a one-statement procedure, hand it to
        -- that role, and call it: an owner's-rights procedure runs as its
        -- owner. The runner role holds CREATE SERVICE only for the call, and
        -- the procedure is dropped afterwards.
        create_service_stmt :=
            'CREATE SERVICE runners.' || :runner_name ||
            ' IN COMPUTE POOL IDENTIFIER(''' || :pool_name || ''')' ||
            ' FROM SPECIFICATION ' || :dollar_quote || :spec || :dollar_quote ||
            ' MIN_INSTANCES = ' || :instances ||
            ' MAX_INSTANCES = ' || :instances ||
            ' EXTERNAL_ACCESS_INTEGRATIONS = (matillion_runner_eai)' ||
            ' QUERY_WAREHOUSE = ' || :warehouse_name;
        EXECUTE IMMEDIATE 'CREATE OR REPLACE PROCEDURE ' || :create_service_proc ||
            '(stmt STRING) RETURNS STRING LANGUAGE SQL EXECUTE AS OWNER AS ' || :dollar_quote ||
            ' BEGIN EXECUTE IMMEDIATE :stmt; RETURN CURRENT_ROLE(); END ' || :dollar_quote;
        EXECUTE IMMEDIATE 'GRANT OWNERSHIP ON PROCEDURE ' || :create_service_proc ||
            '(STRING) TO ROLE ' || :runner_role || ' COPY CURRENT GRANTS';
        EXECUTE IMMEDIATE 'GRANT CREATE SERVICE ON SCHEMA runners TO ROLE ' || :runner_role;
        BEGIN
            EXECUTE IMMEDIATE 'CALL ' || :create_service_proc || '(?)' USING (create_service_stmt);
        EXCEPTION
            WHEN OTHER THEN
                EXECUTE IMMEDIATE 'REVOKE CREATE SERVICE ON SCHEMA runners FROM ROLE ' || :runner_role;
                EXECUTE IMMEDIATE 'DROP PROCEDURE IF EXISTS ' || :create_service_proc || '(STRING)';
                RAISE;
        END;
        EXECUTE IMMEDIATE 'REVOKE CREATE SERVICE ON SCHEMA runners FROM ROLE ' || :runner_role;
        EXECUTE IMMEDIATE 'DROP PROCEDURE IF EXISTS ' || :create_service_proc || '(STRING)';
    END IF;

    -- previous_image only shifts when the image actually changes. This
    -- procedure explicitly supports re-applying desired state to an existing
    -- runner (see the header above), and an unconditional
    -- "previous_image = t.image" would set previous_image = image on such a
    -- rerun - discarding the real rollback target and leaving
    -- admin.rollback_runner_image() to "succeed" while changing nothing.
    MERGE INTO admin.runners t
    USING (SELECT UPPER(:runner_name) AS runner_name) s ON t.runner_name = s.runner_name
    WHEN MATCHED THEN UPDATE SET
        previous_image = IFF(t.image = :image_path, t.previous_image, t.image),
        image = :image_path, compute_pool = :pool_name,
        instances = :instances,
        warehouse_name = :warehouse_name, eai_name = 'matillion_runner_eai',
        updated_at = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (runner_name, compute_pool, image, instances,
        warehouse_name, eai_name)
        VALUES (UPPER(:runner_name), :pool_name, :image_path, :instances,
        :warehouse_name, 'matillion_runner_eai');

    RETURN 'Runner ' || :runner_name || ' deployed';
END;
$$;

GRANT USAGE ON PROCEDURE admin.deploy_runner(STRING, STRING, STRING, STRING, STRING, STRING, INTEGER, STRING, STRING, BOOLEAN, STRING) TO ROLE runner_operator;

-- -----------------------------------------------------------------------------
-- Remove a runner
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE admin.remove_runner(runner_name STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    pool_name STRING DEFAULT UPPER(:runner_name) || '_RUNNER_POOL';
    runner_role STRING DEFAULT UPPER(:runner_name) || '_RUNNER_ROLE';
    runner_role_owner STRING;
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;

    EXECUTE IMMEDIATE 'DROP SERVICE IF EXISTS runners.' || :runner_name;
    -- Left behind only if deploy_runner failed partway through creating the service.
    EXECUTE IMMEDIATE 'DROP PROCEDURE IF EXISTS admin.' || :runner_name || '_CREATE_SERVICE(STRING)';
    -- Only a role this library created: deploy_runner refuses to adopt one
    -- it didn't (see there), so a same-named role with another owner isn't ours.
    EXECUTE IMMEDIATE 'SHOW ROLES';
    runner_role_owner := (SELECT MAX("owner") FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "name" = :runner_role);
    IF (runner_role_owner = CURRENT_ROLE()) THEN
        EXECUTE IMMEDIATE 'DROP ROLE ' || :runner_role;
    END IF;
    EXECUTE IMMEDIATE 'DROP COMPUTE POOL IF EXISTS IDENTIFIER(''' || :pool_name || ''')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_account_id'')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_agent_id'')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_region'')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_environment'')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_default_keyvault'')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_export_logs'')';
    EXECUTE IMMEDIATE 'DROP SECRET IF EXISTS IDENTIFIER(''secrets.' || :runner_name || '_credentials'')';
    DELETE FROM admin.runners WHERE runner_name = UPPER(:runner_name);

    RETURN 'Removed ' || :runner_name;
END;
$$;

GRANT USAGE ON PROCEDURE admin.remove_runner(STRING) TO ROLE runner_operator;

-- -----------------------------------------------------------------------------
-- Status, logs, and listing runners
-- -----------------------------------------------------------------------------

-- The registry alone can say a runner exists after its service has been
-- dropped by hand, so each row is joined to the live service: status is
-- whatever SHOW SERVICES reports (RUNNING, PENDING, SUSPENDED, ...), or
-- MISSING when the service is gone.
CREATE OR REPLACE PROCEDURE admin.list_runners()
RETURNS TABLE()
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    EXECUTE IMMEDIATE 'SHOW SERVICES IN SCHEMA runners';
    res := (SELECT r.runner_name, COALESCE(s."status", 'MISSING') AS status, r.* EXCLUDE (runner_name)
        FROM admin.runners r
        LEFT JOIN TABLE(RESULT_SCAN(LAST_QUERY_ID())) s ON s."name" = r.runner_name
        ORDER BY r.runner_name);
    RETURN TABLE(res);
END;
$$;

CREATE OR REPLACE PROCEDURE admin.get_runner_logs(runner_name STRING, num_lines INTEGER DEFAULT 200)
RETURNS TABLE()
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    res RESULTSET;
    qry STRING;
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        qry := 'SELECT ''Invalid runner_name'' AS log_line';
    ELSE
        qry := 'SELECT SYSTEM$GET_SERVICE_LOGS(''runners.' || :runner_name ||
            ''', ''0'', ''cloud-agent'', ' || :num_lines || ') AS log_line';
    END IF;
    res := (EXECUTE IMMEDIATE :qry);
    RETURN TABLE(res);
END;
$$;

GRANT USAGE ON PROCEDURE admin.list_runners() TO ROLE runner_operator;
GRANT USAGE ON PROCEDURE admin.get_runner_logs(STRING, INTEGER) TO ROLE runner_operator;
GRANT SELECT ON TABLE admin.runners TO ROLE runner_operator;
