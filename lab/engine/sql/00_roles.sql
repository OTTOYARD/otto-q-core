-- lab/engine/sql/00_roles.sql
-- Cluster-level roles the engine's SQL names. Idempotent; run against the lab
-- server's `postgres` database before the lab database is (re)created.
--
-- The list is production's non-builtin roles, read from pg_roles on
-- 2026-11-03 15:58 UTC (9:58 AM CT) through the read-only Supabase MCP tool:
--   anon, authenticated, authenticator, cli_login_postgres, dashboard_user,
--   pgbouncer, postgres, service_role, supabase_admin, supabase_auth_admin,
--   supabase_etl_admin, supabase_functions_admin, supabase_privileged_role,
--   supabase_read_only_user, supabase_realtime_admin,
--   supabase_replication_admin, supabase_storage_admin
-- `postgres` already exists here (it is this cluster's bootstrap superuser;
-- on Supabase it is NOT a superuser, which is one of the shims' differences).
-- In the lab every one of them is NOLOGIN: nothing logs in as them. The
-- BYPASSRLS / SUPERUSER flags copy production's.
DO $roles$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('anon',                       false, false),
      ('authenticated',              false, false),
      ('service_role',               false, true),
      ('authenticator',              false, false),
      ('supabase_admin',             true,  true),
      ('supabase_auth_admin',        false, false),
      ('supabase_storage_admin',     false, false),
      ('supabase_functions_admin',   false, false),
      ('supabase_realtime_admin',    false, false),
      ('supabase_replication_admin', false, false),
      ('supabase_etl_admin',         false, true),
      ('supabase_read_only_user',    false, true),
      ('supabase_privileged_role',   false, false),
      ('dashboard_user',             false, false),
      ('pgbouncer',                  false, false),
      ('cli_login_postgres',         false, false)
    ) v(rolname, is_super, bypass)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.rolname) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN %s %s', r.rolname,
                     CASE WHEN r.is_super THEN 'SUPERUSER' ELSE 'NOSUPERUSER' END,
                     CASE WHEN r.bypass THEN 'BYPASSRLS' ELSE 'NOBYPASSRLS' END);
    END IF;
  END LOOP;
END
$roles$;

-- PostgREST's switch-role chain, as on Supabase.
GRANT anon, authenticated, service_role TO authenticator;
