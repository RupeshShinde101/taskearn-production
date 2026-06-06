-- =============================================================
-- RAILWAY POSTGRES SECURITY HARDENING SCRIPT
-- Run this ONCE in Railway's Postgres shell / query tool
-- after changing your database password.
-- =============================================================

-- 1. Drop dangerous extensions that allow network access from the DB server.
--    These are the most common vectors for "network scanning" abuse.
DROP EXTENSION IF EXISTS dblink CASCADE;
DROP EXTENSION IF EXISTS postgres_fdw CASCADE;
DROP EXTENSION IF EXISTS pg_net CASCADE;
DROP EXTENSION IF EXISTS http CASCADE;
DROP EXTENSION IF EXISTS plperlu CASCADE;
DROP EXTENSION IF EXISTS plpythonu CASCADE;

-- 2. Revoke the ability for the app user (postgres) to create new extensions.
--    Only superusers should be able to load extensions.
--    (Railway's managed postgres does not expose a separate app user by default,
--     but if you create one, apply this to it.)
-- REVOKE CREATE ON DATABASE railway FROM your_app_user;

-- 3. Set a global statement timeout so no query can run for more than 60 seconds.
--    This limits the window for any port-scan query even if one slips through.
ALTER DATABASE railway SET statement_timeout = '60s';

-- 4. Set a global idle-in-transaction timeout to kill abandoned connections.
ALTER DATABASE railway SET idle_in_transaction_session_timeout = '120s';

-- 5. Restrict network-capable functions (belt-and-suspenders on top of step 1).
--    Revoke EXECUTE on pg_read_server_files, pg_write_server_files (file-system access).
REVOKE EXECUTE ON FUNCTION pg_read_server_files(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_write_server_files(text, bytea) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION pg_ls_dir(text) FROM PUBLIC;

-- 6. Verify no dangerous extensions remain.
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
  AND name IN ('dblink','postgres_fdw','pg_net','http','plperlu','plpythonu');
-- Expected: 0 rows returned.

-- Done. Now disable Public Networking in Railway dashboard (see README).
