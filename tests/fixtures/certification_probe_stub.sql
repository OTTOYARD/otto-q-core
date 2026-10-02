-- tests/fixtures/certification_probe_stub.sql: what db/migrations/0579 reads and replaces, as 0513 wrote it.
--
-- 0513's two functions are copied from db/migrations/0513 byte for byte (0579's P1 pins the rig's md5), with the cron
-- entries 0568 scheduled for the sweep and its window, the two ledgers every migration writes, an empty arms table (so a
-- read of it can be shown not to count as an arm) and a runner and an arm that only sleep for `ottoq.stub_sleep_s`.
DO $r$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END $r$;
CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE cron.job (jobid bigserial PRIMARY KEY, jobname text UNIQUE, schedule text, command text, active boolean DEFAULT true);
INSERT INTO cron.job (jobname, schedule, command) VALUES
  ('ottoq-throughput-sweep-runner', '*/2 * * * *', 'SET statement_timeout = 0; SELECT public.ottoq_throughput_sweep_runner();'),
  ('ottoq_sweep_window_open', '0 4 * * *',
   $c$SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_runner_enabled', 1, 'sweep_window_cron:open')$c$),
  ('ottoq_sweep_window_close', '0 11 * * *',
   $c$SELECT public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_runner_enabled', 0, 'sweep_window_cron:close')$c$);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text, classified_at timestamptz);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigint GENERATED ALWAYS AS IDENTITY, label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text, taken_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_throughput_sweep_arms (arm_id bigserial PRIMARY KEY, seed bigint);
CREATE FUNCTION public.ottoq_throughput_sweep_runner() RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_sleep(COALESCE(NULLIF(current_setting('ottoq.stub_sleep_s', true), ''), '3')::numeric);
  RETURN '{"ran": true}'::jsonb;
END $$;
CREATE FUNCTION public.ottoq_throughput_sweep_arm(p_cell uuid, p_seed bigint, p_replicate boolean) RETURNS jsonb
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_sleep(COALESCE(NULLIF(current_setting('ottoq.stub_sleep_s', true), ''), '3')::numeric);
  RETURN '{"arm": true}'::jsonb;
END $$;

-- ── as db/migrations/0513 wrote them ──
CREATE FUNCTION public.ottoq_certification_rig_matches(p_query text, p_with_dial boolean DEFAULT true)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path = pg_catalog
AS $fn$
  -- 0513 (G243). pg_stat_activity keeps the first 1 kB of a query (track_activity_query_size), and the recert runner
  -- (cron 746) names ottoq_determinism_pair past it (G194). Its advisory-lock key, ottoq_recert_runner, is in its
  -- first 100 characters, so that is what identifies it.
  SELECT COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_determinism_pair%', '%ottoq_ab_pair%', '%ottoq_recert_runner%'])
      OR (COALESCE(p_with_dial, true)
          AND COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_dial_pair%', '%ottoq_dial_experiment_runner%']));
$fn$;

CREATE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  -- 0513 (G243). SECURITY DEFINER: only a pg_read_all_stats member reads another role's query text, and the
  -- calibration tables are written by service_role, which is not one. The caller is never counted.
  -- ottoq.simulate_certification_in_flight = on adds one, so the guards can be proven without a second backend. It
  -- can only report a rig, never hide one.
  SELECT (SELECT count(*)::int FROM pg_stat_activity a
           WHERE a.pid <> pg_backend_pid() AND a.state IS DISTINCT FROM 'idle'
             AND public.ottoq_certification_rig_matches(a.query, p_with_dial))
       + CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END;
$fn$;

COMMENT ON FUNCTION public.ottoq_certification_in_flight(boolean) IS
  '0513 (G243). Backends other than the caller running a certification rig: a determinism, A/B or dial pair, the '
  'dial experiment runner, or the recert runner (matched by its lock key, since it names the pair past the 1 kB of '
  'query text pg_stat_activity keeps, G194). p_with_dial=false leaves out the dial rigs. Use this, not a copy.';
