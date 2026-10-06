-- =============================================================================
-- Matillion Runner on Snowpark Container Services - certificate and driver stages
-- =============================================================================
--
-- Adds the two stages a runner mounts as volumes for custom certificates and
-- external drivers, matching the Native App's custom_certificates_stage and
-- external_drivers_stage. A new versioned script rather than an edit to
-- V1.0.0__install_library.sql, which schemachange never reapplies once an
-- account has run it (see that file's header).
--
-- One of each per account, with a folder per runner named after it in
-- lowercase (e.g. @admin.external_drivers_stage/prod_runner/), so runners
-- can be given different files. admin.build_runner_spec() mounts the
-- runner's folder of each into its container, and the agent copies what it
-- finds there when the container starts:
--   custom_certificates_stage -> /mnt/certificates: .cer, .pem and .crt files,
--     imported into the agent's trust stores.
--   external_drivers_stage    -> /mnt/drivers: .jar, .so, .json, .lic and
--     .sso files, added to the agent's driver classpath.
-- Only files directly in the runner's folder are read, not subfolders.
-- admin.create_runner_folders() writes a README.txt into each folder, so it
-- exists to be mounted before anything is uploaded.
--
-- The folders are not a security boundary: READ, which the mount needs,
-- covers the whole stage, so a runner's role can read other runners' files
-- with SQL. Fine for certificates and drivers, but not for anything secret.
--
-- Each runner role is granted READ on both, by admin.deploy_runner() for a
-- new runner and admin.update_runner_image() for one deployed before this
-- script ran. READ is all a read-only stage mount needs: the agent copies
-- from the mounts and never writes back.
--
-- Default encryption, as the Native App's stages use. Stage volumes declared
-- with stageConfig (the generally available implementation) don't restrict
-- the encryption type.
-- =============================================================================

USE DATABASE matillion_runners;

-- DIRECTORY lets Snowsight list and browse each stage's files.
CREATE STAGE IF NOT EXISTS admin.custom_certificates_stage
    DIRECTORY = (ENABLE = true)
    COMMENT = 'Custom certificates for Matillion runners, mounted at /mnt/certificates';

CREATE STAGE IF NOT EXISTS admin.external_drivers_stage
    DIRECTORY = (ENABLE = true)
    COMMENT = 'External drivers for Matillion runners, mounted at /mnt/drivers';

-- Operators upload, list and remove the files. PUT needs READ and WRITE,
-- LIST needs READ, and REMOVE needs WRITE.
GRANT READ, WRITE ON STAGE admin.custom_certificates_stage TO ROLE runner_operator;
GRANT READ, WRITE ON STAGE admin.external_drivers_stage TO ROLE runner_operator;
