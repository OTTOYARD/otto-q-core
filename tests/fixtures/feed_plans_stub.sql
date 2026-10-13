-- A stub engine for 0716: ottoq_feed_plans as live has it (columns, the status CHECK, the unique version), the agent
-- predicate's default list (ottoq_prime and its sub-seats, as live f349c63a), and the registry and lineage tables.
CREATE TABLE public.ottoq_feed_plans (plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), var_key text, version integer,
  status text CHECK (status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text])), method text, plan jsonb,
  provenance jsonb, authored_by text, rationale text, created_at timestamptz DEFAULT now(), UNIQUE (var_key, version));
CREATE TABLE public.ottoq_run_scope_registry (table_schema text, table_name text, column_name text, class text, note text);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean, note text, classified_at timestamptz);
CREATE FUNCTION public.ottoq_certification_in_flight(p boolean) RETURNS integer LANGUAGE sql AS $f$ SELECT 0 $f$;
CREATE FUNCTION public.ottoq_is_agent_actor(p_actor text, p_actors text[] DEFAULT NULL) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $f$
  SELECT EXISTS (SELECT 1 FROM unnest(COALESCE(p_actors, ARRAY['ottoq_prime'])) a
                  WHERE p_actor = a OR p_actor LIKE a || ':%') $f$;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;
INSERT INTO public.ottoq_feed_plans (plan_id, var_key, version, status, method, plan, provenance, authored_by, rationale) VALUES
  ('ef4eac4a-d017-42ce-9b98-99112df8dcd7', 'charger_fault_repair', 1, 'superseded', 'quantile_grid',
   '{"base_session_fault_p": 0.05}', '{}', 'dossier_v1', 'sourced'),
  ('0dd38d00-710e-4825-aa71-cc61561ab7fd', 'charger_fault_repair', 4, 'active', 'quantile_grid',
   '{"base_session_fault_p": 0.055}', '{}', 'nemotron-3-ultra', 'fitted to the twin''s own rate'),
  (gen_random_uuid(), 'weather', 1, 'active', 'profile', '{}', '{}', 'dossier_v1', 'sourced');
