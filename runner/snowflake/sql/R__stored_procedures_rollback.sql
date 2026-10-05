-- =============================================================================
-- Matillion Runner on Snowpark Container Services - image update/rollback
-- =============================================================================
--
-- Hotfix rollout and rollback for a runner already deployed via
-- admin.deploy_runner() in R__stored_procedures.sql.
--
-- Deployed via schemachange (https://github.com/Snowflake-Labs/schemachange)
-- as a REPEATABLE (R) script - not run directly, see
-- ../scripts/install-library.py and ../README.md for the day-to-day
-- runbook.
--
-- Depends on the helpers (admin.is_valid_identifier,
-- admin.is_valid_image_ref, admin.build_runner_spec,
-- admin.create_runner_folders) defined in
-- R__stored_procedures.sql - this filename is chosen to sort after it
-- alphabetically ("R__stored_procedures.sql" < "R__stored_procedures_
-- rollback.sql"), since schemachange applies repeatable scripts in
-- alphabetical order and that file must already have run first.
--
-- IMPORTANT: every image pushed for this path must use a unique, immutable
-- tag (never "latest" or a tag that gets overwritten). Snowflake's service
-- spec has no imagePullPolicy field, and there is no documented way to force
-- SPCS to re-pull a given image reference. ALTER SERVICE ... FROM
-- SPECIFICATION only shuts down and restarts the container when the spec
-- text it's given - including the image: string - actually differs from
-- what's running. Tag every push with the image's content digest; see
-- ../README.md, "Push the Runner image to the account".
--
-- IMPORTANT: this restarts the container ungracefully - it does not drain
-- in-flight work. Calling it directly is fine for a first cut / Matillion-
-- operated use, but for anything self-service, sequence it behind a pause
-- via Matillion's public API instead of calling it bare - see ../README.md,
-- "Limitations".
-- =============================================================================

USE DATABASE matillion_runners;

CREATE OR REPLACE PROCEDURE admin.update_runner_image(runner_name STRING, new_image_path STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    spec STRING;
    dollar_quote STRING DEFAULT CHR(36) || CHR(36);
    runner_role STRING DEFAULT UPPER(:runner_name) || '_RUNNER_ROLE';
    registered BOOLEAN DEFAULT (SELECT COUNT(*) > 0 FROM admin.runners WHERE runner_name = UPPER(:runner_name));
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;
    IF (NOT admin.is_valid_image_ref(:new_image_path)) THEN
        RETURN 'Invalid new_image_path: expected a plain registry/repository[:tag|@digest] reference';
    END IF;
    -- Without a registry row the ALTER below could still succeed on a
    -- service created outside the library, and the UPDATE would then
    -- silently change nothing, losing track of the image now running.
    IF (NOT registered) THEN
        RETURN 'Runner not found: ' || :runner_name;
    END IF;

    -- The spec mounts the certificate and driver stages, which the runner
    -- role must be able to read. deploy_runner grants this too, but a runner
    -- deployed before V1.0.1__certificate_and_driver_stages.sql created the
    -- stages has never been redeployed since, so its first update is where
    -- it gets the grant. Repeating a grant is a no-op.
    BEGIN
        EXECUTE IMMEDIATE 'GRANT READ ON STAGE admin.custom_certificates_stage TO ROLE ' || :runner_role;
        EXECUTE IMMEDIATE 'GRANT READ ON STAGE admin.external_drivers_stage TO ROLE ' || :runner_role;
    EXCEPTION
        WHEN OTHER THEN
            RETURN 'Could not grant READ on the certificate and driver stages to ' || :runner_role ||
                ' - redeploy the runner with admin.deploy_runner, which recreates its role: ' || SQLERRM;
    END;
    -- Likewise the folders the spec mounts, which such a runner never had.
    BEGIN
        CALL admin.create_runner_folders(:runner_name);
    EXCEPTION
        WHEN OTHER THEN
            RETURN 'Could not create ' || :runner_name || '''s certificate and driver folders' ||
                ' - run admin.update_runner_image with a warehouse in use: ' || SQLERRM;
    END;

    spec := admin.build_runner_spec(:runner_name, :new_image_path);

    -- Unlike the Native App, there is no consumer reference to re-bind here
    -- (the EAI is a plain account object this library created itself), so
    -- ALTER SERVICE ... FROM SPECIFICATION works from any calling context.
    -- See the matching note in admin.deploy_runner() (R__stored_procedures.sql)
    -- for why the clause has no "=" and why the dollar-quote pair is built
    -- via CHR(36).
    EXECUTE IMMEDIATE 'ALTER SERVICE runners.' || :runner_name ||
        ' FROM SPECIFICATION ' || :dollar_quote || :spec || :dollar_quote;

    -- UPPER: admin.runners stores runner_name uppercase, and '=' on a STRING
    -- column is case-sensitive even though the object names Snowflake builds
    -- from it are not. See the header of R__stored_procedures.sql.
    --
    -- previous_image only shifts when the image actually changes, matching
    -- deploy_runner's MERGE - otherwise re-applying the image already
    -- running would set previous_image = image and destroy the rollback
    -- target, which is precisely what rollback exists to use.
    UPDATE admin.runners SET
        previous_image = IFF(image = :new_image_path, previous_image, image),
        image = :new_image_path,
        updated_at = CURRENT_TIMESTAMP() WHERE runner_name = UPPER(:runner_name);

    RETURN 'Runner ' || :runner_name || ' updating to ' || :new_image_path ||
        ' - check admin.get_runner_logs() / SHOW SERVICES until it reports READY';
END;
$$;

-- Rolls straight back to whatever was running before the last
-- update_runner_image / deploy_runner call. NOTE: this is one level deep
-- only - update_runner_image overwrites previous_image with the image being
-- replaced, so calling rollback twice in a row moves forward again rather
-- than back further. No history beyond one step is kept.
CREATE OR REPLACE PROCEDURE admin.rollback_runner_image(runner_name STRING)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    registered BOOLEAN DEFAULT (SELECT COUNT(*) > 0 FROM admin.runners WHERE runner_name = UPPER(:runner_name));
    prior_image STRING DEFAULT (SELECT previous_image FROM admin.runners WHERE runner_name = UPPER(:runner_name));
    update_result STRING;
BEGIN
    IF (NOT admin.is_valid_identifier(:runner_name)) THEN
        RETURN 'Invalid runner_name';
    END IF;
    IF (NOT registered) THEN
        RETURN 'Runner not found: ' || :runner_name;
    END IF;
    IF (:prior_image IS NULL) THEN
        RETURN 'No previous image recorded for ' || :runner_name;
    END IF;

    -- update_runner_image signals failure by RETURNING a string, not by
    -- raising - it re-validates prior_image with admin.is_valid_image_ref(),
    -- and a stored value that no longer passes would otherwise be reported
    -- here as a completed rollback. A rollback is the last operation that
    -- can afford to be optimistic about whether it worked.
    CALL admin.update_runner_image(:runner_name, :prior_image);
    update_result := (SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    IF (update_result NOT LIKE 'Runner %') THEN
        RETURN 'Rollback of ' || :runner_name || ' failed: ' || update_result;
    END IF;

    RETURN 'Rolled ' || :runner_name || ' back to ' || :prior_image ||
        ' - check admin.get_runner_logs() / SHOW SERVICES until it reports READY';
END;
$$;

GRANT USAGE ON PROCEDURE admin.update_runner_image(STRING, STRING) TO ROLE runner_operator;
GRANT USAGE ON PROCEDURE admin.rollback_runner_image(STRING) TO ROLE runner_operator;
