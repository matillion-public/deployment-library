-- =============================================================================
-- Matillion Runner on Snowpark Container Services - deployment library install
-- =============================================================================
--
-- This is an alternative to installing the Runner via the Snowflake Native
-- App: instead of a Marketplace app install, it installs a small schema of
-- stored procedures (see R__stored_procedures.sql) that a customer then
-- CALLs to deploy, update, scale, and remove one or more Runner instances
-- directly on Snowpark Container Services. No app install, no release
-- directive.
--
-- Deployed via schemachange (https://github.com/Snowflake-Labs/schemachange),
-- not run directly - see ../scripts/install-library.py and ../README.md for
-- the day-to-day runbook. As a versioned (V) script, this one runs exactly
-- once per account, ever - schemachange tracks that in its own change
-- history table and skips it on every later run. If this file's content
-- ever needs to change, that has to happen as a NEW versioned script
-- (V1.0.1, etc.) with the delta, not by editing this one in place.
-- schemachange does record a checksum of each applied versioned script,
-- but an edit is not an error: it logs "Script checksum has drifted since
-- application" at INFO and skips the script, so the edit silently never
-- reaches an account that has already run it.
--
-- Prerequisites - the installing role needs:
--   GRANT CREATE DATABASE ON ACCOUNT TO ROLE <INSTALLER_ROLE>;
--   GRANT CREATE COMPUTE POOL ON ACCOUNT TO ROLE <INSTALLER_ROLE>;
--   GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE <INSTALLER_ROLE>;
--   GRANT CREATE ROLE ON ACCOUNT TO ROLE <INSTALLER_ROLE>; -- runner_operator, and a role per runner
--   GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE <INSTALLER_ROLE>; -- if not reusing one
-- and, for each warehouse a runner will use that it doesn't own:
--   GRANT USAGE ON WAREHOUSE <warehouse> TO ROLE <INSTALLER_ROLE> WITH GRANT OPTION;
-- =============================================================================

CREATE DATABASE IF NOT EXISTS matillion_runners;
USE DATABASE matillion_runners;

CREATE SCHEMA IF NOT EXISTS admin;   -- stored procedures + registry table
CREATE SCHEMA IF NOT EXISTS runners; -- one SERVICE object per deployed runner lives here
CREATE SCHEMA IF NOT EXISTS secrets; -- per-runner secrets, and the default keyvault for pipeline secrets

-- Lower-privileged role for day-to-day operation. The stored procedures in
-- R__stored_procedures.sql run EXECUTE AS OWNER, so this role only ever needs
-- USAGE on the schemas/database and EXECUTE on the procedures themselves -
-- never the underlying CREATE COMPUTE POOL / CREATE INTEGRATION privileges.
--
-- The one exception is secrets: operators create each runner's OAuth
-- credentials secret (and any pipeline secrets) themselves, with a plain
-- CREATE SECRET. A CALL passing the secret as an argument would keep it
-- verbatim in QUERY_HISTORY; a CREATE SECRET has the value redacted.
CREATE ROLE IF NOT EXISTS runner_operator;

GRANT USAGE ON DATABASE matillion_runners TO ROLE runner_operator;
GRANT USAGE ON SCHEMA admin TO ROLE runner_operator;
GRANT USAGE ON SCHEMA runners TO ROLE runner_operator;
GRANT USAGE ON SCHEMA secrets TO ROLE runner_operator;
GRANT CREATE SECRET ON SCHEMA secrets TO ROLE runner_operator;

-- Secrets runner_operator creates are owned by runner_operator, but the
-- procedures run as this (the installing) role: deploy_runner has to see
-- them and grant them to the runner's own role, and remove_runner has to
-- drop them. Granting runner_operator to the installing role gives it all
-- three. Built as a string because the role name is only known at install
-- time.
SET grant_operator_to_installer = 'GRANT ROLE runner_operator TO ROLE "' || CURRENT_ROLE() || '"';
EXECUTE IMMEDIATE $grant_operator_to_installer;

-- One row per deployed runner - lets a single installed library manage
-- multiple named runner instances in the same account (e.g. one per
-- environment), rather than being hard-coded to a single service/pool name.
CREATE TABLE IF NOT EXISTS admin.runners (
    runner_name STRING PRIMARY KEY,
    compute_pool STRING,
    image STRING,
    previous_image STRING, -- last known-good image, for admin.rollback_runner_image
    instances INTEGER,
    warehouse_name STRING,
    eai_name STRING,
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_LTZ
);

-- Image repository the customer pushes hotfixed/current images into.
-- Snowpark Container Services cannot pull an image directly from an
-- external registry (ECR, ACR, GCR, Docker Hub) - it must already be in a
-- Snowflake-managed image repository in this account. Pull the Runner image
-- from Matillion's public ECR repository and push it here, tagged by content
-- digest rather than a mutable tag - see ../README.md, "Why every image
-- needs its own tag", for why that tagging discipline is not optional.
CREATE IMAGE REPOSITORY IF NOT EXISTS admin.runner_images;

-- Wide-open egress, matching what the Native App grants today via its
-- external-access-integration reference. Narrow VALUE_LIST to known hosts if
-- a tighter allow-list is preferred for a given account.
CREATE NETWORK RULE IF NOT EXISTS admin.all_access_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80');

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS matillion_runner_eai
    ALLOWED_NETWORK_RULES = (admin.all_access_rule)
    ALLOWED_AUTHENTICATION_SECRETS = ALL
    ENABLED = true;
