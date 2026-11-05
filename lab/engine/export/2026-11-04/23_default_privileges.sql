-- 23_default_privileges.sql: 46 statements, exported from production's catalog
-- @@ default_acl postgres public f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO postgres;
-- @@ default_acl postgres public f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon;
-- @@ default_acl postgres public f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
-- @@ default_acl postgres public f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
-- @@ default_acl postgres public r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO postgres;
-- @@ default_acl postgres public r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT MAINTAIN, REFERENCES, SELECT, TRIGGER ON TABLES TO authenticated;
-- @@ default_acl postgres public r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO service_role;
-- @@ default_acl postgres public S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO postgres;
-- @@ default_acl postgres public S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO authenticated;
-- @@ default_acl postgres public S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO service_role;
-- @@ default_acl postgres storage f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT EXECUTE ON FUNCTIONS TO postgres;
-- @@ default_acl postgres storage f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT EXECUTE ON FUNCTIONS TO anon;
-- @@ default_acl postgres storage f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT EXECUTE ON FUNCTIONS TO authenticated;
-- @@ default_acl postgres storage f
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT EXECUTE ON FUNCTIONS TO service_role;
-- @@ default_acl postgres storage r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO postgres;
-- @@ default_acl postgres storage r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO anon;
-- @@ default_acl postgres storage r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO authenticated;
-- @@ default_acl postgres storage r
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO service_role;
-- @@ default_acl postgres storage S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO postgres;
-- @@ default_acl postgres storage S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO anon;
-- @@ default_acl postgres storage S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO authenticated;
-- @@ default_acl postgres storage S
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA storage GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO service_role;
-- @@ default_acl supabase_admin cron f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT EXECUTE ON FUNCTIONS TO postgres WITH GRANT OPTION;
-- @@ default_acl supabase_admin cron r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO postgres WITH GRANT OPTION;
-- @@ default_acl supabase_admin cron S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO postgres WITH GRANT OPTION;
-- @@ default_acl supabase_admin extensions f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT EXECUTE ON FUNCTIONS TO postgres WITH GRANT OPTION;
-- @@ default_acl supabase_admin extensions r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO postgres WITH GRANT OPTION;
-- @@ default_acl supabase_admin extensions S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA extensions GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO postgres WITH GRANT OPTION;
-- @@ default_acl supabase_admin public f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO postgres;
-- @@ default_acl supabase_admin public f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon;
-- @@ default_acl supabase_admin public f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
-- @@ default_acl supabase_admin public f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
-- @@ default_acl supabase_admin public r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO postgres;
-- @@ default_acl supabase_admin public r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO anon;
-- @@ default_acl supabase_admin public r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO authenticated;
-- @@ default_acl supabase_admin public r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO service_role;
-- @@ default_acl supabase_admin public S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO postgres;
-- @@ default_acl supabase_admin public S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO anon;
-- @@ default_acl supabase_admin public S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO authenticated;
-- @@ default_acl supabase_admin public S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO service_role;
-- @@ default_acl supabase_auth_admin auth f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT EXECUTE ON FUNCTIONS TO postgres;
-- @@ default_acl supabase_auth_admin auth f
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT EXECUTE ON FUNCTIONS TO dashboard_user;
-- @@ default_acl supabase_auth_admin auth r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO postgres;
-- @@ default_acl supabase_auth_admin auth r
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLES TO dashboard_user;
-- @@ default_acl supabase_auth_admin auth S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO postgres;
-- @@ default_acl supabase_auth_admin auth S
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_auth_admin IN SCHEMA auth GRANT SELECT, UPDATE, USAGE ON SEQUENCES TO dashboard_user;
