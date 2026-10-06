-- verify-escape-sql-string.sql
--
-- CI-only live round-trip check for admin.escape_sql_string(). Running it
-- on every live-deploy run, rather than as a one-off manual check, keeps
-- the function verified against a real account as it changes.
--
-- Round-trips a value containing both an embedded single quote and a
-- trailing backslash - the specific case the function's own comment calls
-- out, since Snowflake string literals treat backslash as an escape
-- character - through escape_sql_string() and back through a real SQL
-- parse, and checks the result matches the original exactly. Prints a
-- single PASS/FAIL row; the caller (see
-- ../../.github/workflows/snowflake-test.yml) checks for a leading "PASS".
--
-- Not part of the installed library itself (hence living in scripts/, not
-- sql/ - the schemachange naming-convention CI check only applies to
-- sql/) - this is a test, never deployed to a customer account.

EXECUTE IMMEDIATE $$
DECLARE
    test_val STRING DEFAULT 'it''s a test\\ with a trailing backslash\\';
    escaped STRING;
    round_tripped STRING;
BEGIN
    escaped := matillion_runners.admin.escape_sql_string(:test_val);
    EXECUTE IMMEDIATE 'SELECT ''' || :escaped || ''' AS v';
    round_tripped := (SELECT v FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())));
    IF (:round_tripped != :test_val) THEN
        RETURN 'FAIL: escape_sql_string round-trip mismatch - expected [' || :test_val || '], got [' || :round_tripped || ']';
    END IF;
    RETURN 'PASS: escape_sql_string round-trip OK';
END;
$$;
