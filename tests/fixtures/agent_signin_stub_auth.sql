-- The one Supabase Auth table 0660 reads (ottoq_owner_account_link finds an account by email), on the scratch cluster
-- only: the stub engine has auth.uid() but no auth.users. Columns: only what 0660 reads.
DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'supabase_migrations') THEN
    RAISE EXCEPTION 'agent_signin_stub_auth.sql is a TEST STUB and this looks like a real Supabase project. Refusing.';
  END IF;
END $guard$;

CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, email text);
