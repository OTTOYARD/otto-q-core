-- tests/fixtures/run_control_grants_stub.sql: the seventeen run-control routines 0791 closes, in miniature.
--
-- What it reproduces from the live engine (db/migrations/0791 §1; read 2026-10-17 from 14:04:05 UTC, 9:04 AM CT):
--   * the seventeen routines with their LIVE definitions, byte for byte (pg_get_functiondef, read as base64 at
--     14:07:41 UTC and decoded; each block below names its md5), created with check_function_bodies off because most
--     of them name engine tables this stub does not carry, and their LIVE ACLs, granted in the order that reproduces
--     each ACL's text exactly;
--   * what the tests call them through: ottoq_sim_runs and ottoq_scenarios cut to the columns the bodies and the tests
--     use (live types and defaults), with their LIVE grants to the browser roles (authenticated SELECT, anon none) and
--     their LIVE row-security policies (plus one per table giving service_role what BYPASSRLS gives it on live), and
--     auth.role() and auth.uid() with their live bodies;
--   * the callees the live bodies of pause, resume and production start and stop reach, as small stand-ins with the
--     live signature and the live ACL (ottoq_record_event, SECURITY DEFINER, executable by authenticated before 0701;
--     ottoq_world_yield_to_start and ottoq_sim_release_depot, SECURITY DEFINER, postgres and service_role only;
--     ottoq_agentic_arm; ottoq_is_agent_actor), so a signed-in production start or stop is refused where live refuses
--     it, one call deeper;
--   * ottoq_sim_advance_tick and ottoq_sim_advance_tick_world as service_role-only stand-ins whose world step sets a
--     run's status as live's does, so ottoq_run_policy_to_end reaches a run write as it does on live (0791's census);
--   * the bookkeeping 0791 writes (ottoq_schema_snapshots, with its live SELECT grant to authenticated, and
--     ottoq_cert_lineage) and a settable in-flight probe;
--   * for G492, live's ottoq_one_running_run_per_depot index on ottoq_sim_runs, so a resume that waited behind a stop
--     whose transaction started another run at the depot is refused with 23505, as on live, before 0791; and live's
--     foreign key from the events to the run, on the event stand-in, so a door that records an event for a run that is
--     gone fails as live's would.
-- Loads on a plain PostgreSQL 16 or 17 as a superuser named postgres. Never run against live.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- the engine's bookkeeping, as the migrations use it
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(), label text NOT NULL,
  object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);
-- live: row security off, SELECT to authenticated, none to anon
REVOKE ALL ON public.ottoq_schema_snapshots FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_schema_snapshots TO authenticated;
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL, classified_at timestamptz NOT NULL,
  forces_dial_restart boolean);
CREATE TABLE public.stub_in_flight (n integer NOT NULL DEFAULT 0);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
RETURNS integer LANGUAGE sql STABLE AS $f$ SELECT n FROM public.stub_in_flight LIMIT 1 $f$;

-- the Supabase auth helpers the policies below call, bodies as live
CREATE SCHEMA IF NOT EXISTS auth;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $f$
  select
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$f$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $f$
  select
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$f$;

-- ottoq_sim_runs and ottoq_scenarios, cut to the columns the bodies and the tests use (live types and defaults, read
-- 2026-10-17 14:08:18 UTC), with their live grants (2026-10-15 13:20:01 UTC: authenticated=rxtm, service_role=arwdDxtm,
-- anon nothing; MAINTAIN is PostgreSQL 17's, so the stub grants the rest) and their live SELECT policies
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_id uuid NOT NULL,
  scenario_code text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  last_tick_at timestamptz,
  next_tick_due_at timestamptz,
  sim_clock_start timestamptz NOT NULL,
  sim_clock_current timestamptz NOT NULL,
  sim_clock_end timestamptz NOT NULL,
  time_scale numeric NOT NULL DEFAULT 60.0,
  tick_interval_seconds integer NOT NULL DEFAULT 30,
  tick_count integer NOT NULL DEFAULT 0,
  depot_id uuid,
  random_seed bigint NOT NULL DEFAULT 42,
  status text NOT NULL DEFAULT 'initializing'::text,
  failure_reason text,
  run_by text,
  notes text,
  payload jsonb DEFAULT '{}'::jsonb,
  policy text NOT NULL DEFAULT 'otto_q'::text,
  demo_speed_x numeric NOT NULL DEFAULT 1.0);
-- the one-running-run-per-depot index, as live (pg_get_indexdef, read 2026-10-17 at 14:34:53 UTC): what refuses
-- the resume with 23505 in G492's third case, when the stop's own transaction starts another run at the depot
CREATE UNIQUE INDEX ottoq_one_running_run_per_depot ON public.ottoq_sim_runs USING btree (depot_id)
  WHERE (status = 'running'::text);
CREATE TABLE public.ottoq_scenarios (
  scenario_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_code text NOT NULL,
  title text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'active'::text);
REVOKE ALL ON public.ottoq_sim_runs, public.ottoq_scenarios FROM PUBLIC, anon, authenticated;
GRANT SELECT, REFERENCES, TRIGGER ON public.ottoq_sim_runs, public.ottoq_scenarios TO authenticated;
GRANT ALL ON public.ottoq_sim_runs, public.ottoq_scenarios TO service_role;
ALTER TABLE public.ottoq_sim_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_scenarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY sim_runs_read ON public.ottoq_sim_runs FOR SELECT
  USING (auth.role() = ANY (ARRAY['authenticated'::text, 'service_role'::text]));
CREATE POLICY scenarios_read ON public.ottoq_scenarios FOR SELECT
  USING (auth.role() = ANY (ARRAY['authenticated'::text, 'anon'::text, 'service_role'::text]));
-- live's service_role has BYPASSRLS (pg_roles, read 2026-10-17 14:46:41 UTC). Roles are cluster-wide, and another
-- suite's stub may have created a scratch cluster's service_role without it, so the stub gives service_role the same
-- on these two tables by policy; anon and authenticated see only the live policies above
CREATE POLICY stub_service_role_bypasses_rls ON public.ottoq_sim_runs TO service_role USING (true) WITH CHECK (true);
CREATE POLICY stub_service_role_bypasses_rls ON public.ottoq_scenarios TO service_role USING (true) WITH CHECK (true);

-- what production start reads after its insert, and the event the doors record (stand-ins)
CREATE TABLE public.depots (id uuid PRIMARY KEY, slug text, feed_mode text);
CREATE TABLE public.ottoq_policy_params (
  scope_type text, scope_id uuid, param_key text, param_value numeric, updated_by text, updated_at timestamptz);
CREATE TABLE public.stub_events (
  event_type text NOT NULL, entity_id uuid, actor_id text, payload jsonb, sim_run_id uuid,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp());
-- live's ottoq_record_event writes p_sim_run_id into ottoq_events, whose foreign key to the run is NOT VALID and still
-- checks every new row (fk_ottoq_events_sim_run, read 2026-10-17 14:38:25 UTC): an event for a run that is gone fails
ALTER TABLE public.stub_events ADD CONSTRAINT fk_stub_events_sim_run FOREIGN KEY (sim_run_id)
  REFERENCES public.ottoq_sim_runs (sim_run_id) NOT VALID;
REVOKE ALL ON public.depots, public.ottoq_policy_params, public.stub_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.depots, public.ottoq_policy_params TO service_role;
INSERT INTO public.depots VALUES ('11111111-1111-1111-1111-111111111111', 'nashville-flagship', 'sim'),
                                 ('22222222-2222-2222-2222-222222222222', 'benchmark-crn', 'sim');
INSERT INTO public.ottoq_scenarios (scenario_id, scenario_code, title)
VALUES ('5c000000-0000-4000-8000-000000000791', 'production', 'production session');

-- the callees, live signatures and live ACLs (read 2026-10-17 14:08:24 UTC), bodies cut to what the tests need
CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $f$
  INSERT INTO public.stub_events (event_type, entity_id, actor_id, payload, sim_run_id)
  VALUES (p_event_type, p_entity_id, p_actor_id, p_payload, p_sim_run_id) RETURNING gen_random_uuid()
$f$;
REVOKE ALL ON FUNCTION public.ottoq_record_event(text, text, text, uuid, jsonb, text, jsonb, uuid, uuid, jsonb, jsonb, text, uuid, uuid, uuid, uuid, uuid, text, integer, text, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_record_event(text, text, text, uuid, jsonb, text, jsonb, uuid, uuid, jsonb, jsonb, text, uuid, uuid, uuid, uuid, uuid, text, integer, text, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_record_event(text, text, text, uuid, jsonb, text, jsonb, uuid, uuid, jsonb, jsonb, text, uuid, uuid, uuid, uuid, uuid, text, integer, text, text, text, uuid) TO authenticated;

CREATE FUNCTION public.ottoq_world_yield_to_start(p_who text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS
  $f$ SELECT jsonb_build_object('interrupted', '[]'::jsonb, 'who', p_who) $f$;
REVOKE ALL ON FUNCTION public.ottoq_world_yield_to_start(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_world_yield_to_start(text) TO service_role;

CREATE FUNCTION public.ottoq_sim_release_depot(p_sim_run_id uuid, p_reason text DEFAULT 'operator_stop'::text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS
  $f$ SELECT jsonb_build_object('released', p_sim_run_id, 'reason', p_reason) $f$;
REVOKE ALL ON FUNCTION public.ottoq_sim_release_depot(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_release_depot(uuid, text) TO service_role;

CREATE FUNCTION public.ottoq_agentic_arm(p_sim_run_id uuid, p_by text) RETURNS jsonb LANGUAGE sql AS
  $f$ SELECT jsonb_build_object('arming', jsonb_build_object('run', p_sim_run_id, 'by', p_by)) $f$;
REVOKE ALL ON FUNCTION public.ottoq_agentic_arm(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_agentic_arm(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agentic_arm(uuid, text) TO service_role;

CREATE FUNCTION public.ottoq_is_agent_actor(p_by text, p_actors text[] DEFAULT NULL::text[]) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $f$ SELECT false $f$;
GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text, text[]) TO anon;
GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text, text[]) TO service_role;

-- the tick ottoq_run_policy_to_end drives: postgres and service_role only, as live; the world step sets a run's
-- status as live's ottoq_sim_advance_tick_world does, so the census finds run_policy_to_end two calls above a write
CREATE FUNCTION public.ottoq_sim_advance_tick_world(p_sim_run_id uuid) RETURNS TABLE(out_completed boolean)
LANGUAGE plpgsql SECURITY DEFINER AS $f$
BEGIN
  UPDATE ottoq_sim_runs SET tick_count = tick_count + 1,
         status = CASE WHEN sim_clock_current >= sim_clock_end THEN 'completed' ELSE status END
   WHERE sim_run_id = p_sim_run_id AND status = 'running';
  RETURN QUERY SELECT NOT EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id AND status = 'running');
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_sim_advance_tick_world(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_advance_tick_world(uuid) TO service_role;
CREATE FUNCTION public.ottoq_sim_advance_tick(p_sim_run_id uuid) RETURNS TABLE(out_completed boolean)
LANGUAGE plpgsql SECURITY DEFINER AS $f$
BEGIN
  RETURN QUERY SELECT w.out_completed FROM ottoq_sim_advance_tick_world(p_sim_run_id) w;
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_sim_advance_tick(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_advance_tick(uuid) TO service_role;

-- ══ the seventeen, byte for byte as live ══════════════════════════════════════════════════════════════════════════
SET check_function_bodies = off;

-- ── public.ottoq_pause_run(uuid, text), pg_get_functiondef md5 1e3ec33aca6f4f3b008a0d83bff08c51 ──
CREATE OR REPLACE FUNCTION public.ottoq_pause_run(p_sim_run_id uuid, p_reason text DEFAULT 'operator_pause'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  IF v_run.status <> 'running' THEN
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not running');
  END IF;

  UPDATE ottoq_sim_runs
     SET status = 'paused',
         next_tick_due_at = NULL,
         payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('paused_at', clock_timestamp(), 'pause_reason', p_reason)
   WHERE sim_run_id = p_sim_run_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_paused', p_entity_type := 'sim_run',
    p_entity_id := p_sim_run_id, p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('reason', p_reason, 'tick_count', v_run.tick_count),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'paused',
    'frozen_at_sim_clock', v_run.sim_clock_current, 'tick_count', v_run.tick_count);
END;
$function$
;

-- ── public.ottoq_resume_run(uuid), pg_get_functiondef md5 b693dc33284db3914381f89bd7f21724 ──
CREATE OR REPLACE FUNCTION public.ottoq_resume_run(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run ottoq_sim_runs%ROWTYPE; v_paused_at timestamptz; v_paused_s numeric;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  IF v_run.status <> 'paused' THEN
    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,
                              'note', 'run was not paused');
  END IF;

  v_paused_at := (v_run.payload->>'paused_at')::timestamptz;
  v_paused_s  := GREATEST(0, EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_paused_at, clock_timestamp()))));

  -- ⭐ RE-ANCHOR THE LIVE CLOCK. Without this the first tick after resume advances the
  -- sim clock by the entire paused interval (see migration comment).
  UPDATE ottoq_sim_runs
     SET status = 'running',
         last_tick_at = clock_timestamp(),
         next_tick_due_at = now(),
         payload = (COALESCE(payload,'{}'::jsonb) - 'paused_at' - 'pause_reason')
                   || jsonb_build_object('last_pause_seconds', round(v_paused_s, 2))
   WHERE sim_run_id = p_sim_run_id;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'otto_twin',
    p_event_type := 'twin.sim_run_resumed', p_entity_type := 'sim_run',
    p_entity_id := p_sim_run_id, p_depot_id := v_run.depot_id,
    p_payload := jsonb_build_object('paused_seconds', round(v_paused_s, 2),
                                    'sim_clock_resumed_at', v_run.sim_clock_current),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
    p_sim_run_id := p_sim_run_id);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'running',
    'resumed_at_sim_clock', v_run.sim_clock_current,
    'paused_real_seconds', round(v_paused_s, 2),
    'clock_reanchored', true);
END;
$function$
;

-- ── public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone), pg_get_functiondef md5 77452e4a4d02700ddea8a450f468daee ──
CREATE OR REPLACE FUNCTION public.ottoq_sim_run_scenario(p_scenario_code text, p_seed bigint DEFAULT NULL::bigint, p_run_by text DEFAULT 'system_scheduler'::text, p_start_clock timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_scenario   ottoq_sim_scenarios%ROWTYPE;
  v_sim_run_id UUID := gen_random_uuid();
  v_seed       BIGINT;
  v_start      TIMESTAMPTZ;
  v_end        TIMESTAMPTZ;
  v_start_hour INT;
  v_prime_frac NUMERIC;
BEGIN
  SELECT * INTO v_scenario FROM ottoq_sim_scenarios
   WHERE scenario_code = p_scenario_code AND status = 'available';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario % not found or not available', p_scenario_code;
  END IF;

  --: 0297 / G107. THE CALLER MAY NOW NAME THE CLOCK, AND IF IT DOES, EVERYTHING
  --: BELOW IS BUILT AGAINST THAT ONE CLOCK. Before this parameter existed,
  --: ottoq_start_demo_run let this function pick 08:00 Central, primed 45 of 87
  --: dispatch rows against it, and THEN rewrote sim_clock_start to a seed-derived
  --: minute of the UTC day -- 7h25m away for seed 100020 -- leaving the world
  --: anchored to a clock the tick path never visits. Measured consequence: 32 rows
  --: stored actual_duration_min between -388 and -440 minutes, and KPI 1 credited
  --: them zero. p_start_clock is how the demo wrapper owns its own randomised start
  --: BEFORE the world exists instead of after. Every other caller passes NULL and
  --: gets byte-for-byte the previous behaviour.
  v_start := COALESCE(p_start_clock,
    CASE WHEN p_run_by = 'operator_demo'
      THEN ((date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours') AT TIME ZONE 'America/Chicago')
      ELSE NOW() END);
  v_start_hour := EXTRACT(HOUR FROM (v_start AT TIME ZONE 'America/Chicago'))::int;

  v_seed := COALESCE(p_seed, abs(hashtextextended(gen_random_uuid()::text, 42)));
  v_end  := v_start + (v_scenario.default_duration_hours || ' hours')::interval;

  INSERT INTO ottoq_scenarios (
    scenario_id, scenario_code, category, title, description,
    depot_id, sim_duration_minutes, default_time_scale, tick_interval_seconds,
    initial_conditions, arrival_profile, timeline, random_seed, status,
    introduced_in, created_at, updated_at
  ) VALUES (
    v_scenario.scenario_id, v_scenario.scenario_code,
    CASE
      WHEN p_scenario_code = 'normal_day' THEN 'normal_operations'
      WHEN p_scenario_code IN ('heat_wave','winter_storm','solar_underperformance_partly_cloudy',
                               'aggressive_fleet_turnover') THEN 'stress_test'
      WHEN p_scenario_code IN ('dr_event_cascade','charger_outage_morning_rush',
                               'grid_brownout_at_peak') THEN 'edge_case'
      ELSE 'demo' END,
    v_scenario.title, COALESCE(v_scenario.description, v_scenario.title),
    v_scenario.default_depot_id,
    (v_scenario.default_duration_hours * 60)::int,
    v_scenario.default_time_scale,
    v_scenario.default_tick_seconds,
    jsonb_build_object('weather_overrides', v_scenario.weather_overrides,
                       'fleet_overrides',   v_scenario.fleet_overrides),
    jsonb_build_object('shape', 'nyc_tlc_hourly_arrival_rate'),
    jsonb_build_object('grid_overrides',    v_scenario.grid_overrides,
                       'charger_overrides', v_scenario.charger_overrides,
                       'fault_injection',   v_scenario.fault_injection),
    v_seed, 'active', '20260619_twin_a6', NOW(), NOW()
  )
  ON CONFLICT (scenario_id) DO NOTHING;

  -- 0524 (G249): A START IS A STOP AND A START, NEVER A RELABEL. This was a bare UPDATE to 'completed': no
  -- release, no archive, and the old run's charges, tethers, pointers and dispatches left for the seed to trip over
  -- (db/checks/0392 §3). A live run at the depot -- running or paused, since the seed rewrites the world under both --
  -- now goes through the operator's stop door, as the cockpit's Stop and the governor take it. That door pins the run
  -- it tears down (ottoq.sim_run_id) and an 8-second lock timeout for the rest of the transaction; the new run is
  -- neither, so both are put back once the old runs are down.
  DECLARE
    v_live      uuid;
    v_stopped   int  := 0;
    v_lock_prev text := current_setting('lock_timeout');
  BEGIN
    FOR v_live IN
      SELECT r.sim_run_id FROM ottoq_sim_runs r
       WHERE r.depot_id = v_scenario.default_depot_id AND r.status IN ('running','paused')
       ORDER BY r.started_at, r.sim_run_id
    LOOP
      PERFORM public.ottoq_sim_stop_and_reset(v_live, 'superseded by ' || p_scenario_code);
      UPDATE ottoq_sim_runs SET notes = COALESCE(notes,'') || ' | superseded by ' || p_scenario_code
       WHERE sim_run_id = v_live;
      v_stopped := v_stopped + 1;
    END LOOP;
    IF v_stopped > 0 THEN
      PERFORM set_config('ottoq.sim_run_id', '', true);
      PERFORM set_config('lock_timeout', v_lock_prev, true);
    END IF;
  END;

  -- 0023: OWNERLESS needs only. A run's own open needs are closed by the run's
  -- OWN terminal transition (trigger ottoq_sim_runs_close_needs), including the
  -- run this call is superseding one statement above and the run the start button
  -- aborted before calling here. What no run transition can ever reach is a need
  -- with no sim_run_id at all -- that, and only that, is cleared here. A finished
  -- run's ledger is read-only.
  UPDATE ottoq_visit_needs vn SET status = 'superseded'
    FROM vehicles v
   WHERE vn.vehicle_id = v.id AND v.home_depot_id = v_scenario.default_depot_id
     AND vn.sim_run_id IS NULL
     AND vn.status IN ('open','in_progress');

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, status,
    sim_clock_start, sim_clock_current, sim_clock_end,
    started_at, last_tick_at, next_tick_due_at,
    depot_id, random_seed, time_scale, tick_interval_seconds,
    run_by, notes
  ) VALUES (
    v_sim_run_id, v_scenario.scenario_id, v_scenario.scenario_code, 'running',
    v_start, v_start, v_end, NOW(), NOW(), NOW(),
    v_scenario.default_depot_id, v_seed,
    v_scenario.default_time_scale, v_scenario.default_tick_seconds,
    p_run_by, 'Started via ottoq_sim_run_scenario(' || p_scenario_code || ')'
  );

  BEGIN
    -- 0531 (G256): dealt on the run's own start clock. It was now(): every reader of last_state_change takes a dwell
    -- as the SIM clock minus it, and a car dealt at the wall clock began its state in the sim's future.
    PERFORM twin.ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour, v_start);
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('seed_fleet', jsonb_build_object('ok', true))
     WHERE sim_run_id = v_sim_run_id;
  EXCEPTION WHEN OTHERS THEN
    -- 0524 (G249): a run the seed could not deal is not the scenario's day; it is whatever the depot held last. This
    -- wrote {"ok": false} into the payload and started the run anyway, and 929e323c ran five sim-hours on the
    -- previous run's cars (db/checks/0392). The start now fails and rolls back whole, the supersede above included,
    -- and says why. Unlike the agentic arm below, a run that could not be seeded is not a valid run.
    RAISE EXCEPTION 'fleet seed failed at depot %, so no run was started: %', v_scenario.default_depot_id, SQLERRM
      USING HINT = 'db/checks/0392 (G249)';
  END;

  -- CARD-2: the DRAW PHASE — every world + per-vehicle variable dealt before tick 1
  BEGIN
    PERFORM ottoq_run_boot_draw(v_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('boot_draw', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'run_boot_draw',
        p_event_type := 'twin.boot_draw_failed', p_entity_type := 'system',
        p_payload := jsonb_build_object('sim_run_id', v_sim_run_id, 'error', SQLERRM),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := v_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;

  BEGIN
    PERFORM ottoq_variability_instantiate(v_sim_run_id, p_scenario_code);
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  -- (A) SCENARIO FLEET OVERRIDES -- on the LOAD path, not in a wrapper. Runs AFTER
  --     ottoq_run_boot_draw (which unconditionally rewrites pm_interval_km /
  --     calib_interval_h) and BEFORE prime, so the wear phase offsets see the final
  --     intervals. Receipt, never silence: a failure here is recorded on the run.
  BEGIN
    PERFORM ottoq_scenario_apply_fleet_overrides(v_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('scenario_overrides', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
    RAISE WARNING 'scenario fleet overrides: %', SQLERRM;
  END;

  BEGIN
    IF NOT EXISTS (SELECT 1 FROM depots d
                    WHERE d.id = v_scenario.default_depot_id AND d.slug LIKE 'benchmark%') THEN
      DECLARE v_primed INTEGER; v_pool INTEGER; v_states JSONB;
      BEGIN
        SELECT COUNT(*) INTO v_pool FROM vehicles v
         WHERE v.home_depot_id = v_scenario.default_depot_id AND v.category = 'autonomous'
           AND v.current_soc >= 80
           AND v.current_state IN ('staged_for_departure','en_route_to_deployment','offline');
        SELECT jsonb_object_agg(s, n) INTO v_states
          FROM (SELECT current_state::text AS s, COUNT(*) AS n FROM vehicles
                 WHERE home_depot_id = v_scenario.default_depot_id AND category = 'autonomous'
                 GROUP BY 1) t;
        -- (B) prime at the SCENARIO's hour-shaped deployed target
        v_prime_frac := ottoq_deploy_target_fraction(
                          v_start_hour,
                          COALESCE((v_scenario.fleet_overrides->>'target_deployed_fraction')::numeric, 0.92));
        v_primed := ottoq_sim_prime_deployment(v_sim_run_id, v_start, v_prime_frac);
        UPDATE ottoq_sim_runs
           SET payload = COALESCE(payload,'{}'::jsonb)
                       || jsonb_build_object('boot_prime', jsonb_build_object(
                            'ok', true, 'primed', v_primed, 'candidate_pool', v_pool,
                            'prime_fraction', v_prime_frac, 'start_hour_cst', v_start_hour,
                            'state_histogram', v_states))
         WHERE sim_run_id = v_sim_run_id;
      END;
    ELSE
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('boot_prime', jsonb_build_object('ok', true, 'skipped', 'benchmark_depot'))
       WHERE sim_run_id = v_sim_run_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('boot_prime', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
  END;

  IF v_scenario.grid_overrides ? 'force_bess_starting_soc_pct' THEN
    UPDATE ottoq_bess_units
       SET current_soc_pct = (v_scenario.grid_overrides->>'force_bess_starting_soc_pct')::numeric,
           current_soc_kwh = capacity_kwh
                          * ((v_scenario.grid_overrides->>'force_bess_starting_soc_pct')::numeric) / 100.0
     WHERE depot_id = v_scenario.default_depot_id;
  END IF;

  -- 0323: ARM THE AGENTIC LAYER ON THE WAY IN. Across 1,147 runs nothing
  -- that started a run had ever done this, so every run booted with the
  -- proposer door shut and the UI could never show the agentic half
  -- working. Arming is part of STARTING now, at every door, so a run is
  -- armed because it was started and not because somebody remembered.
  --
  -- THE cert_harness TEST IS NOT OPTIONAL. Arming sets
  -- proposer_frame_facts=1, which changes what the decision frame carries
  -- (0265) -- the frame every canon was measured against. The arming
  -- routine refuses such a run by RAISING, so an unguarded call would
  -- abort the creation of every certification arm.
  IF COALESCE(p_run_by, '') <> 'cert_harness' THEN
    BEGIN
      PERFORM public.ottoq_agentic_arm(v_sim_run_id, 'auto:' || COALESCE(p_run_by, 'unknown'));
      UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, '{}'::jsonb)
             || jsonb_build_object('agentic_arm', jsonb_build_object('ok', true))
       WHERE sim_run_id = v_sim_run_id;
    EXCEPTION WHEN OTHERS THEN
      -- Receipt, never silence, and never a failed start: a run that could
      -- not be armed is still a valid run, and the reason is on the row.
      UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, '{}'::jsonb)
             || jsonb_build_object('agentic_arm',
                  jsonb_build_object('ok', false, 'error', SQLERRM))
       WHERE sim_run_id = v_sim_run_id;
    END;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type := 'system_scheduler', p_actor_id := 'twin_scenario_runner',
    p_event_type := 'twin.scenario_started', p_entity_type := 'system',
    p_payload := jsonb_build_object('sim_run_id', v_sim_run_id, 'scenario_code', p_scenario_code,
      'seed', v_seed, 'start_hour_cst', v_start_hour, 'duration_h', v_scenario.default_duration_hours),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := v_sim_run_id);

  RETURN v_sim_run_id;
END;
$function$
;

-- ── public.ottoq_benchmark_reset(uuid, numeric, numeric), pg_get_functiondef md5 17986725fa7566b0c6670c58af5f3d8f ──
CREATE OR REPLACE FUNCTION public.ottoq_benchmark_reset(p_depot uuid, p_arrival_soc numeric DEFAULT 30, p_target_soc numeric DEFAULT 80)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF p_depot NOT IN (SELECT id FROM depots WHERE slug LIKE 'benchmark%') THEN
    RAISE EXCEPTION 'ottoq_benchmark_reset refuses non-benchmark depot %', p_depot;  -- safety: never reset production
  END IF;
  -- self-heal zombie runs (worker death between scoring and abort)
  UPDATE ottoq_sim_runs SET status='aborted', ended_at=now(),
         notes = COALESCE(notes,'') || ' | auto-aborted by benchmark_reset (zombie heal)'
   WHERE depot_id=p_depot AND status='running';
  UPDATE stalls SET status='available', current_vehicle_id=NULL, reserved_by=NULL, reserved_at=NULL, reservation_expires_at=NULL WHERE depot_id=p_depot;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_heartbeat_at=now(), last_fault_code=NULL WHERE depot_id=p_depot;
  UPDATE ocpp_sessions o
     SET status='cancelled',
         -- 0233 / G36: the session's OWN run's clock, floored at its own start.
         ended_at = GREATEST(o.started_at,
                      COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                                 WHERE r.sim_run_id = o.sim_run_id), o.started_at)),
         stopped_reason='benchmark_reset',
         updated_at=now()
   WHERE o.depot_id=p_depot AND o.status='active';
  UPDATE vehicles SET current_state='arrived_at_gate', current_soc=p_arrival_soc, target_soc=p_target_soc,
         current_stall_id=NULL, last_state_change=now(),
         -- 0234 / G37: the tether is run-written residue too. 0053 stripped the
         -- arm residue it could see inside `config` and missed the four columns
         -- sitting beside it. Cleared in the SAME statement that moves the
         -- vehicle, which is exactly the case ottoq_arm_interlock_guard is
         -- written to permit: "including the case where this very statement is
         -- what lets go". With these NULL, sync_stall_occupancy also vacates the
         -- old stall instead of leaking it -- so both triggers agree, and neither
         -- needs a clock.
         robotic_tether_until=NULL, robotic_tether_stall_id=NULL,
         robotic_tether_direction=NULL, robotic_tether_phase=NULL,
         config=((COALESCE(config,'{}'::jsonb)-'svc_step')-'service_manifest')-'service_manifest_meta' - 'battery_soh_pct' - 'consumption_scalar' - 'charge_curve_scalar' - 'soil_rate' - 'pm_interval_km' - 'calib_interval_h' - 'service_speed_scalar' - 'wash_cadence_cycles' - 'cycles_since_wash' - 'condition_drawn_run' - 'charge_plan' - 'deploy_gate' - 'arm_fault_at' - 'arm_fault_reason' - 'arm_fault_awaiting_disposition'   -- 0053: run-written residue must not leak into the next cert arm
   WHERE home_depot_id=p_depot AND category='autonomous';
  UPDATE ottoq_visit_needs SET status='superseded'
   WHERE depot_id=p_depot AND status IN ('open','in_progress');
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id=p_depot AND status='pending';
END $function$
;

-- ── public.ottoq_run_policy_to_end(uuid, integer), pg_get_functiondef md5 1b40f798b8f5f8326bff260d0002cc09 ──
CREATE OR REPLACE FUNCTION public.ottoq_run_policy_to_end(p_sim_run_id uuid, p_max_ticks integer DEFAULT 48)
 RETURNS TABLE(ticks_run integer, completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_done boolean := false; v_i int := 0; v_tick bigint;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN QUERY SELECT 0, true; RETURN; END IF;
  WHILE v_i < p_max_ticks AND NOT v_done LOOP
    SELECT out_completed INTO v_done FROM ottoq_sim_advance_tick(p_sim_run_id);  -- tick now self-heartbeats
    v_i := v_i + 1;
  END LOOP;
  SELECT tick_count INTO v_tick FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  PERFORM ottoq_capture_decision_snapshot(p_sim_run_id, 1000000000::bigint + v_tick, v_depot,
            (SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id));
  RETURN QUERY SELECT v_i, v_done;
END;
$function$
;

-- ── public.ottoq_production_start(uuid), pg_get_functiondef md5 ea2945cbb0435c58ce73b4f5e038c501 ──
CREATE OR REPLACE FUNCTION public.ottoq_production_start(p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb; v_inherited jsonb;
  v_int jsonb;
BEGIN
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing);
  END IF;

  SELECT * INTO v_scenario FROM ottoq_scenarios WHERE scenario_code = 'production';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'production_scenario_missing');
  END IF;

  -- 0719 (G437). Production takes the world as the operator door does: every running check is cancelled, and the world
  -- lock waits for their rollback. Without it a session started inside a sweep arm got no tick until the arm ended
  -- (pg_cron runs one job at a time here, G141). A check cancelled here re-runs after the session ends.
  v_int := public.ottoq_world_yield_to_start('production_start');
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing, 'interrupted', v_int);
  END IF;

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, started_at, next_tick_due_at,
    sim_clock_start, sim_clock_current, sim_clock_end,
    time_scale, tick_interval_seconds, depot_id, random_seed,
    status, run_by, policy, demo_speed_x
  ) VALUES (
    gen_random_uuid(), v_scenario.scenario_id, 'production', now(), now(),
    now(), now(), now() + interval '100 years',
    1.0, 120, p_depot, 42,
    'running', 'production_live', 'otto_q', 1.0
  ) RETURNING sim_run_id INTO v_run;

  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  -- 0629. THE SESSION IS ARMED, as an operator's run is. Chase, 2026-10-08 CT: "Agent should always be on when runs are
  -- activated, and definitely when actual vehicle data is integrated." The agent proposes; the kernel disposes.
  -- ottoq_agentic_arm raises on any write the setter refuses or clamps, so a session never starts half-armed (0113's
  -- rule, kept), and it sets the arm's three tick-counted dials for a 120-second tick. No write under an agent's name
  -- reaches this session's settings: ottoq_policy_set refuses it (production_never_self_tunes, CLAUDE.md rule 10).
  v_ps := public.ottoq_agentic_arm(v_run, 'production_start');

  -- 0629. What this session inherits that was last written under an agent's name, at this depot's scope or the global
  -- one. Reported for a person (rule 10); never changed here.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('scope_type', pp.scope_type, 'param_key', pp.param_key,
                                               'value', pp.param_value, 'updated_by', pp.updated_by,
                                               'updated_at', pp.updated_at)
                            ORDER BY pp.scope_type, pp.param_key), '[]'::jsonb)
    INTO v_inherited
    FROM public.ottoq_policy_params pp
   WHERE ((pp.scope_type = 'depot' AND pp.scope_id = p_depot) OR pp.scope_type = 'global')
     AND public.ottoq_is_agent_actor(pp.updated_by);

  SELECT COALESCE(d.feed_mode, 'sim') INTO v_feed FROM depots d WHERE d.id = p_depot;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'production_start',
    p_event_type := 'production.session_started', p_entity_type := 'sim_run',
    p_payload := jsonb_build_object('depot_id', p_depot, 'feed_mode', v_feed, 'agents', 'armed (0629)',
                                    'agent_written_settings_in_force', v_inherited, 'interrupted', v_int,
                                    'tick', 'ottoq-depot-tick */2min -> twin.ottoq_world_advance (wall-elapsed) -> decide_and_dispatch'),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'depot_id', p_depot,
    'feed_mode', v_feed, 'run_by', 'production_live', 'policy', 'otto_q',
    'driver', 'ottoq-depot-tick cron (*/2 min) -> twin.ottoq_world_advance -> ottoq_sim_decide_and_dispatch',
    'agents', 'armed (0629): the agent proposes and the kernel disposes; no write under an agent''s name reaches this '
              'session''s settings',
    'arming', v_ps -> 'arming',
    'agent_written_settings_in_force', v_inherited, 'interrupted', v_int);
END
$function$
;

-- ── public.ottoq_production_stop(text), pg_get_functiondef md5 499ea8d51f65cd62463838ba940e075e ──
CREATE OR REPLACE FUNCTION public.ottoq_production_stop(p_reason text DEFAULT 'operator_stop'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run uuid; v_release jsonb;
BEGIN
  SELECT sim_run_id INTO v_run FROM ottoq_sim_runs
   WHERE run_by = 'production_live' AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_running_production_session');
  END IF;

  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  v_release := ottoq_sim_release_depot(v_run, p_reason);

  UPDATE ottoq_sim_runs
     SET status = 'completed', ended_at = now(), failure_reason = p_reason
   WHERE sim_run_id = v_run;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'production_stop',
    p_event_type := 'production.session_stopped', p_entity_type := 'sim_run',
    p_payload := jsonb_build_object('reason', p_reason, 'release', v_release),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'reason', p_reason,
                            'release', v_release);
END
$function$
;

-- ── public.ottoq_cert_arm_start(bigint, text, uuid, integer), pg_get_functiondef md5 9045e026e2c31eadca7d3bf311b063fa ──
CREATE OR REPLACE FUNCTION public.ottoq_cert_arm_start(p_seed bigint, p_policy text, p_ab_group uuid, p_fault_chargers integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_now timestamptz := now(); v_wseed bigint; v_deploy_n int; v_total int; v_sim0 timestamptz;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  /* ══════════ 0065: THE CERT SAMPLES A PINNED SLICE, NOT THE ARMING MINUTE ══════════
     This function hardcoded the run's SIM clock to v_now, so a cert pair sampled
     whichever 10-sim-hour slice of normal_day began at the wall-clock minute it was
     armed. Measured on one unchanged code path: re-cert #17 (armed 22:40Z) carried
     1,075 / 1,098 vehicle commands per arm; #18 (armed 00:32Z) carried 1,562 / 1,598
     -- ~45% more work from the arrival curve alone. Within-round A-vs-B stayed valid
     (both arms armed ~2 min apart in the same band), but no round could be differenced
     against another, so no fix in the 0045-0064 series could be MEASURED, only verified.

     v_sim0 pins the sim clock to 22:00 UTC of the current date: a real return-wave
     slice, and between the two loads above so the #17/#18 family stays roughly
     comparable. The REAL-time metronome stamps (started_at, last_tick_at,
     next_tick_due_at) deliberately keep v_now -- they schedule ticks in wall-clock and
     must not move. Everything in the SIM domain moves together: sim_clock_*,
     last_state_change, and the dispatch window. Moving last_state_change with the sim
     clock is required, not incidental: cold-start and dwell logic read
     (sim_clock - last_state_change), and leaving it on the real clock would put that
     delta in a different domain from the clock it is compared against.

     Harness only. ottoq_cert_arm_start has no caller outside the determinism cert;
     production scheduling semantics are untouched by this migration. */
  /* ══════════ 0070 (b): PIN THE DAY, NOT JUST THE HOUR ══════════
     0065 pinned the sim clock to 22:00 so a pair no longer sampled whichever slice the arming
     minute happened to land on. It pinned the hour and left the calendar day floating. Day-
     and block-lifespan variability is salted by a day number taken from that day:
     ottoq_twin_deal builds bucket 'day:'||p_sim_day, which becomes the salt handed to
     ottoq_sample_calibrated. Weather, wind, solar, the grid, climate stress and per-dispatch
     ETA cards all read it, so a re-cert one day later drew a different world from an identical
     seed. Measured at seed 424242 with only the day number varying: wind 5.544 / 9.252 / 7.416
     km/h across three consecutive days.
     The reference day is fixed here as a constant, and is deliberately the day the
     certification baseline was established. AT TIME ZONE 'UTC' is explicit rather than
     incidental: the previous expression resolved its day boundary in the session time zone,
     so a non-UTC session would have shifted the pinned instant.
     The REAL-domain stamps below still use v_now and still schedule ticks in wall clock; only
     the SIM domain is pinned, exactly as 0065 established. A controls interface that wants to
     move the reference day should promote this to a parameter -- that is a signature change,
     and therefore its own migration, not a body edit. */
  v_sim0 := (DATE '2026-08-22' + interval '22 hours') AT TIME ZONE 'UTC';
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  /* 0065: the charger fleet must start in the SIM domain too, or pinning the clock
     silently empties every proposal. ottoq_benchmark_reset stamps
     last_heartbeat_at = now() (REAL), and the proposers gate on
     last_heartbeat_at >= <sim clock> - 90 seconds -- ottoq_honour_reservation_proposal
     (the proposer ottoq_decide_tick calls first) and ottoq_l2_propose_stall_assignment;
     ottoq_book_appointment, ottoq_plan_opportunistic_charges and
     ottoq_sim_prearrival_contracts use a 35-minute window against p_clock. While the
     sim clock equalled the arming minute those comparisons happened to line up. Pinned,
     they do not: a real-clock heartbeat reads as OFFLINE against the pinned sim clock,
     every charger drops out of every proposal on tick 1, and nothing raises. The twin
     re-stamps these to the sim clock on every tick (ottoq_sim_advance_tick_world), so
     this supplies tick 1's value only, in the same domain the twin will use.
     ottoq_eval_hw_002_charger_state is safe either way: its v_now is
     COALESCE(p_context->>'now_ts', NOW()) and the decide path wires the sim clock in. */
  UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_sim0 WHERE depot_id = d;
  /* ══════════ 0070 (a): THE WORLD SEED IS THE RUN SEED, AND NOTHING ELSE ══════════
     This line mixed the A/B group UUID into the world seed. Every fact about the starting
     fleet is drawn from v_wseed -- each vehicle's SoC, which 85 of 100 deploy, and when each
     returns -- and a fresh group is allocated per re-certification, so the SAME seed produced
     a DIFFERENT world every time. Both arms of one pair share the group, which is exactly why
     determinism passed within a pair and failed across sessions.
     Measured before the change: re-cert #20 drew 7681532243817775720, re-cert #22 drew
     6347474725636378542, and their deployed sets overlapped 70 of 85 -- 30 vehicles in a
     different state, the exact discrepancy seen in the tick-1 frames. Proven by prediction
     rather than correlation: twin.ottoq_sim_seeded_random is IMMUTABLE, so the formula was
     evaluated independently and matched the arm-time record 85/85 with ZERO error on initial
     SoC and 85/85 on the deployed set.
     The group is still recorded on the run and still drives A/B pairing and scoring; it just
     no longer decides what world the run happens in. This makes common-random-numbers pairing
     stronger, not weaker. See docs/SEED_REPRODUCIBILITY_DIAGNOSIS.md. */
  v_wseed := abs(hashtextextended(p_seed::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);

  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 100 /* 0539: the fleet rests at full */, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=v_sim0   /* 0065: sim domain */
   WHERE home_depot_id=d AND category='autonomous';

  IF p_fault_chargers > 0 THEN
    UPDATE ottoq_ocpp_chargers SET station_state='Faulted', last_fault_code='STRESS_OUTAGE_CERT'
     WHERE charger_id IN (SELECT s.ocpp_charger_id FROM stalls s WHERE s.depot_id=d
        AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type) AND s.ocpp_charger_id IS NOT NULL
        ORDER BY s.stall_type, s.stall_code LIMIT p_fault_chargers);
  END IF;

  INSERT INTO ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES ('ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', v_sim0, v_sim0, v_sim0 + interval '24 hours',   /* 0065: pinned sim start */
    d, 60, 30, 'running', p_policy, 'benchmark', 0, p_seed, p_ab_group, v_now, v_now, v_now)
  RETURNING sim_run_id INTO v_run;

  /* 0056: determinism cert arms quiesce the REAL-async cuOpt proposer (see
     the 0056 note in ottoq_cuopt_refresh). Run-scoped: nothing outside this
     arm's own run is affected. */
  INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value)
  VALUES ('run', v_run, 'cuopt_propose_enabled', 0)
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = 0;

  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, v_run, p.fleet_operator_id, v_sim0,   /* 0065: sim domain */
         v_sim0 + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;

  UPDATE vehicles SET current_state='deployed', last_state_change=v_sim0   /* 0065: sim domain */
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=v_run AND status='active');

  RETURN v_run;
END;
$function$
;

-- ── public.ottoq_cert_arm_finish(uuid), pg_get_functiondef md5 02beeffec29daad712b8e19271c9adf4 ──
CREATE OR REPLACE FUNCTION public.ottoq_cert_arm_finish(p_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_score_run(p_run);

  /* ══════════ 0069: TEARDOWN RELEASES WHAT TEARDOWN LEAVES BEHIND ══════════
     ottoq_arm_interlock_guard compares robotic_tether_until against the sim clock of the
     RUNNING run and falls back to now() when none is running -- which is exactly the state
     between two cert arms. Tethers are sim-stamped (since 0065, ~21-22h ahead of real time),
     so a leftover tether reads as far-future forever and ottoq_benchmark_reset can never move
     the vehicle: the next arm_start dies on the interlock. Six vehicles were still tethered at
     the end of re-cert #19 arm A, and three arms were discarded and hand-cleared across
     #19-#21 before this landed. Only visible once the depot started working -- the livelock
     era ended runs with almost no DCFC sessions, and the arm gate fires on 100% of DCFC.
     The documented escape hatch is used rather than nulling the columns, because it also
     closes the open twin.arm_cycles rows and emits the proper events. The clock handed to it
     is this run's OWN sim_clock_current -- the sim-domain instant the run ended. Passing
     now() here would reintroduce the exact mismatch this exists to remove. */
  PERFORM twin.ottoq_arm_emergency_release(
            v.id,
            'cert_arm_finish teardown (0069)',
            'cert_harness',
            p_run,
            COALESCE((SELECT r.sim_clock_current FROM ottoq_sim_runs r
                       WHERE r.sim_run_id = p_run), now()))
     FROM vehicles v
    WHERE v.home_depot_id = d
      AND v.robotic_tether_until IS NOT NULL;

  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_fault_code=NULL
   WHERE depot_id=d AND last_fault_code='STRESS_OUTAGE_CERT';
END;
$function$
;

-- ── public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer), pg_get_functiondef md5 6d524d73fc1ea2f4fccaa36d9049c92c ──
CREATE OR REPLACE PROCEDURE public.ottoq_cert_arm(IN p_seed bigint, IN p_policy text, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone DEFAULT NULL::timestamp with time zone, IN p_fault_chargers integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE v_run uuid; i int; v_now timestamptz := COALESCE(p_start, now()); v_wseed bigint; v_deploy_n int; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);
  -- start-of-shift: whole fleet charged + staged
  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=v_now
   WHERE home_depot_id=d AND category='autonomous';
  IF p_fault_chargers > 0 THEN
    UPDATE ottoq_ocpp_chargers SET station_state='Faulted', last_fault_code='STRESS_OUTAGE_CERT'
     WHERE charger_id IN (SELECT s.ocpp_charger_id FROM stalls s WHERE s.depot_id=d
        AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL
        ORDER BY s.stall_type::text, s.stall_code LIMIT p_fault_chargers);
  END IF;
  INSERT INTO ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES ('ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', v_now, v_now, v_now + interval '24 hours',
    d, 60, 30, 'running', p_policy, 'benchmark', 0, p_seed, p_ab_group, v_now, v_now, v_now)
  RETURNING sim_run_id INTO v_run;
  -- WAVE: deploy 85% fresh; they drain over the shift and return as a clustered low-SoC wave
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, v_run, p.fleet_operator_id, v_now,
         v_now + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=v_now
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=v_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(v_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=v_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(v_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=v_run;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_fault_code=NULL
   WHERE depot_id=d AND last_fault_code='STRESS_OUTAGE_CERT';
END $procedure$
;

-- ── public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer), pg_get_functiondef md5 da8f1efa7c38c74dba996f7f75ea586f ──
CREATE OR REPLACE PROCEDURE public.ottoq_cert_arm_wave(IN p_seed bigint, IN p_policy text, IN p_ab_group uuid, IN p_ticks integer, IN p_fault_chargers integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE v_run uuid; i int; v_now timestamptz := now(); v_wseed bigint; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct = 90.0, current_temperature_c = 25.0 WHERE depot_id = d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  -- start-of-evening: whole fleet out on shift, charged this morning
  -- end-of-shift v2: the fleet is DEEP into its shift — low SoC, real charge demand
  UPDATE vehicles SET current_soc = 24 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*16,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=v_now
   WHERE home_depot_id=d AND category='autonomous';
  IF p_fault_chargers > 0 THEN
    UPDATE ottoq_ocpp_chargers SET station_state='Faulted', last_fault_code='SCARCITY_SWEEP_CERT'
     WHERE charger_id IN (SELECT s.ocpp_charger_id FROM stalls s WHERE s.depot_id=d
        AND s.stall_type::text IN ('dcfc','l2') AND s.ocpp_charger_id IS NOT NULL
        ORDER BY CASE WHEN s.stall_type::text='l2' THEN 0 ELSE 1 END, s.stall_code LIMIT p_fault_chargers);
  END IF;
  INSERT INTO ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES ('ef24648f-eaf6-4686-bd07-1e018a8224ab','overnight_wave', v_now, v_now, v_now + interval '24 hours',
    d, 60, 30, 'running', p_policy, 'benchmark', 0, p_seed, p_ab_group, v_now, v_now, v_now)
  RETURNING sim_run_id INTO v_run;
  -- THE WAVE: 100% of the fleet out, ALL returning within 60-180 min (compressed arrivals)
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous')
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, v_run, p.fleet_operator_id, v_now - interval '9 hours',
         v_now + ((60 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*120) || ' minutes')::interval,
         630, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=v_now
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=v_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(v_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=v_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(v_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=v_run;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_fault_code=NULL
   WHERE depot_id=d AND last_fault_code='SCARCITY_SWEEP_CERT';
END $procedure$
;

-- ── public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean), pg_get_functiondef md5 2c7b9c06574bfff33de5bfe664deba56 ──
CREATE OR REPLACE PROCEDURE public.ottoq_fr1_cert_arm(IN p_run uuid, IN p_seed bigint, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone, IN p_mpc boolean DEFAULT false)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE i int; v_wseed bigint; v_deploy_n int; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct=90.0, current_soc_kwh=capacity_kwh*0.90, current_temperature_c=25.0,
         current_power_kw=0 WHERE depot_id=d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);
  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=p_start
   WHERE home_depot_id=d AND category='autonomous';
  INSERT INTO ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES (p_run, 'ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', p_start, p_start, p_start + interval '24 hours',
    d, 60, 30, 'running', 'otto_q', 'benchmark', 0, p_seed, p_ab_group, p_start, p_start, p_start);
  IF p_mpc THEN PERFORM ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1); END IF;
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, p_run, p.fleet_operator_id, p_start,
         p_start + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=p_start
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(p_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(p_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
END $procedure$
;

-- ── public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric), pg_get_functiondef md5 6bc03eeafb83787966c53728e818798a ──
CREATE OR REPLACE PROCEDURE public.ottoq_safety_cert_arm(IN p_run uuid, IN p_seed bigint, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone, IN p_drain_frac numeric DEFAULT 0.65)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE i int; v_wseed bigint; d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 90);
  UPDATE ottoq_bess_units SET current_soc_pct=90, current_soc_kwh=capacity_kwh*0.9, current_power_kw=0, current_temperature_c=25 WHERE depot_id=d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'safety', 23));
  -- drained fleet: p_drain_frac below the 80% floor (55-79%), the rest safe (85-95%), all staged & ready
  UPDATE vehicles SET
    current_soc = CASE WHEN ottoq_sim_seeded_random(v_wseed,'drain:'||id::text) < p_drain_frac
                       THEN 55 + ottoq_sim_seeded_random(v_wseed,'lo:'||id::text)*24
                       ELSE 85 + ottoq_sim_seeded_random(v_wseed,'hi:'||id::text)*10 END,
    target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=p_start
   WHERE home_depot_id=d AND category='autonomous';
  INSERT INTO ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES (p_run, 'ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', p_start, p_start, p_start + interval '24 hours',
    d, 60, 30, 'running', 'otto_q', 'benchmark', 0, p_seed, p_ab_group, p_start, p_start, p_start);
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(p_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(p_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
END $procedure$
;

-- ── public.ottoq_demo_metronome(integer), pg_get_functiondef md5 d02b6af9e3fa622267247f7277ef7057 ──
CREATE OR REPLACE PROCEDURE public.ottoq_demo_metronome(IN p_budget_s integer DEFAULT 50)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_run RECORD; v_advanced timestamptz; v_interval numeric; v_base numeric := 6.0;
  v_any boolean; v_window_ms numeric; v_req bigint;
  v_max_ticks int; v_floor numeric; v_max_real_min numeric; v_stop_reason text;
  v_fire_beat_at timestamptz;
  v_tick_t0 timestamptz;
  v_worst_tick_s numeric := 0;
  v_ceiling_s numeric;
  v_reserve_s numeric;
  v_guard_on boolean := true;
  v_elapsed_s numeric;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  BEGIN
    SELECT s.setting::numeric / 1000.0 INTO v_ceiling_s
      FROM pg_settings s WHERE s.name = 'statement_timeout';
  EXCEPTION WHEN OTHERS THEN
    v_ceiling_s := 0;   -- unreadable ceiling => guard stands down rather than guessing
  END;
  v_ceiling_s := COALESCE(v_ceiling_s, 0);

  LOOP
    SELECT EXISTS (
      SELECT 1 FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    ) INTO v_any;
    EXIT WHEN NOT v_any;

    FOR v_run IN
      SELECT sim_run_id,
             COALESCE((payload->>'speed_x')::numeric, demo_speed_x, 1.0) AS spd,
             COALESCE(payload->>'playback_mode','fixed') AS pmode,
             next_tick_due_at, started_at,
             depot_id, COALESCE(policy,'otto_q') AS policy, COALESCE(tick_count,0) AS ticks
      FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    LOOP
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
      v_fire_beat_at := NULL;

      v_guard_on := ottoq_policy_get(v_run.sim_run_id, 'metronome_ceiling_guard', 1) >= 1;
      IF v_guard_on AND v_ceiling_s > 0 THEN
        v_elapsed_s := EXTRACT(EPOCH FROM (clock_timestamp() - v_start));
        v_reserve_s := GREATEST(v_worst_tick_s * 1.5, 15.0);
        EXIT WHEN v_elapsed_s + v_reserve_s > v_ceiling_s * 0.9;
      END IF;

      v_stop_reason := NULL;
      IF v_run.pmode = 'live' THEN
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks_live', 5000)::int);
        v_max_real_min := GREATEST(1, ottoq_policy_get(v_run.sim_run_id, 'demo_max_real_minutes', 60));
      ELSE
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks', 240)::int);
        v_max_real_min := NULL;
      END IF;

      IF v_run.ticks >= v_max_ticks THEN
        v_stop_reason := 'tick ceiling ' || v_max_ticks || ' reached';
      ELSIF v_max_real_min IS NOT NULL
        AND EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.started_at, clock_timestamp())))/60.0
            >= v_max_real_min THEN
        v_stop_reason := 'live-mode real-time ceiling ' || round(v_max_real_min,1) || ' real-min reached';
      END IF;

      IF v_stop_reason IS NOT NULL THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM ottoq_sim_stop_and_reset(
            v_run.sim_run_id,
            'auto-stopped by metronome: ' || v_stop_reason || ' (perpetuity backstop)');
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'metronome ceiling-stop % failed: % — forcing status', v_run.sim_run_id, SQLERRM;
          UPDATE ottoq_sim_runs
             SET status = 'completed',
                 ended_at = COALESCE(ended_at, now()),
                 failure_reason = COALESCE(failure_reason, v_stop_reason || '; forced stop')
           WHERE sim_run_id = v_run.sim_run_id;
        END;
        COMMIT;
        CONTINUE;
      END IF;

      v_floor := GREATEST(0.2, ottoq_policy_get(v_run.sim_run_id, 'tick_cadence_floor_s', 2.0));
      IF v_run.pmode = 'live' THEN
        v_interval := GREATEST(v_floor, v_base / GREATEST(v_run.spd, 0.25));
      ELSE
        v_interval := GREATEST(0.2, v_base / GREATEST(v_run.spd, 0.25));
      END IF;
      CONTINUE WHEN v_run.next_tick_due_at IS NOT NULL AND clock_timestamp() < v_run.next_tick_due_at;

      v_tick_t0 := clock_timestamp();
      -- 0654: with twin_operator_door on, the twin's operators answer OTTO-Q's directives in their own transaction,
      -- before the world moves: acks no longer happen inside OTTO-Q's.
      IF ottoq_policy_get(v_run.sim_run_id, 'twin_operator_door', 0) >= 1 THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM twin.ottoq_twin_operator_step(v_run.sim_run_id);
        EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome operators % failed: %', v_run.sim_run_id, SQLERRM;
          PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'operators', SQLERRM, SQLSTATE); END;
        COMMIT;
      END IF;
      v_advanced := NULL;
      BEGIN
        PERFORM set_config('lock_timeout', '8000', true);
        SELECT out_sim_clock_after INTO v_advanced FROM public.ottoq_sim_advance_tick_world(v_run.sim_run_id) LIMIT 1;
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome world % failed: %', v_run.sim_run_id, SQLERRM;
        PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'world', SQLERRM, SQLSTATE); END;

      IF v_advanced IS NOT NULL THEN
        IF (v_run.ticks % 2) = 1 THEN
          BEGIN
            PERFORM set_config('lock_timeout', '8000', true);
            PERFORM public.ottoq_sim_decide_and_dispatch(v_run.sim_run_id);
          EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome decide % failed: %', v_run.sim_run_id, SQLERRM;
            PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'decide', SQLERRM, SQLSTATE); END;
        ELSE
          IF v_run.policy = 'otto_q' THEN
            v_window_ms := ottoq_policy_get(v_run.sim_run_id, 'cuopt_solve_window_ms', 4000);
            IF v_window_ms > 0 THEN
              v_req := NULL;
              BEGIN
                PERFORM set_config('lock_timeout', '8000', true);
                v_req := ottoq_cuopt_refresh(v_run.sim_run_id);
              EXCEPTION WHEN OTHERS THEN NULL; END;
              v_fire_beat_at := clock_timestamp();
            END IF;
          END IF;
        END IF;
      END IF;

      v_worst_tick_s := GREATEST(v_worst_tick_s,
                                 EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0)));

      UPDATE ottoq_sim_runs
         SET next_tick_due_at = clock_timestamp() + make_interval(secs => v_interval),
             payload = CASE WHEN v_fire_beat_at IS NOT NULL
                            THEN COALESCE(payload,'{}'::jsonb)
                                 || jsonb_build_object('cuopt_fire_beat_at', v_fire_beat_at)
                            ELSE payload END
       WHERE sim_run_id = v_run.sim_run_id;
      COMMIT;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
    END LOOP;
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;

    IF v_guard_on AND v_ceiling_s > 0
       AND EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) + GREATEST(v_worst_tick_s * 1.5, 15.0)
           > v_ceiling_s * 0.9 THEN
      EXIT;
    END IF;

    PERFORM pg_sleep(0.4);
  END LOOP;
END;
$procedure$
;

-- ── public.ottoq_retention_purge_runs(integer, integer, interval, boolean), pg_get_functiondef md5 890d2de189d638c1622a53efc863fb66 ──
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_runs(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_dry_run boolean DEFAULT false)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep    interval;
  v_cut     timestamptz;
  v_t0      timestamptz := clock_timestamp();
  v_n       bigint;
  v_total   bigint := 0;
  v_doomed  uuid[];
  v_block   int;
  v_pairs   int;
  v_bad     text;
  v_stamped boolean := false;   -- 0251
  -- 0294 (G63): was a record variable driven by a query cursor loop over the
  -- registry. A procedure may not COMMIT while a cursor is open, so the COMMIT
  -- below raised 2D000 on every firing this job ever had and it never purged a
  -- row. The registry is read into arrays before the loop instead; the removed
  -- shape is quoted in db/checks/0226, deliberately not here -- A1 greps this
  -- source for it and a comment would satisfy the grep.
  v_tabs    text[];
  v_cols    text[];
  v_i       int;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  SELECT count(*) FILTER (WHERE severity = 'block') INTO v_block
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s).', v_block;
  END IF;

  -- 0250 GUARD 1: the allow-list narrows the registry; it may never widen it.
  SELECT string_agg(a.table_name, ', ') INTO v_bad
    FROM public.ottoq_retention_engine_allowlist a
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_name = a.table_name AND g.class = 'engine'
                        AND g.table_schema = 'public');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed but not class=engine: %', v_bad;
  END IF;

  -- 0250 GUARD 2: no allow-listed table may parent a NO ACTION/RESTRICT FK.
  SELECT string_agg(DISTINCT c.confrelid::regclass::text || ' <- ' || c.conrelid::regclass::text, ', ')
    INTO v_bad
    FROM pg_constraint c
    JOIN public.ottoq_retention_engine_allowlist a
      ON a.table_name = c.confrelid::regclass::text
   WHERE c.contype = 'f' AND c.confdeltype IN ('a', 'r');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed table is the parent of a NO ACTION/RESTRICT FK: %', v_bad;
  END IF;

  -- 0269 (G23): A SCHEDULED ROUND, not merely a running pair.
  -- db/checks/0202: a round is ten pairs on 14-minute slots and a pair runs
  -- 130-270 s, so for most of a round nothing is in pg_stat_activity and the
  -- guard below sees an idle system. A purge landing in one of those gaps moves
  -- the residue canon BETWEEN two pairs of the same round. Placed here, after
  -- the run-scope check and both allow-list guards, so those three refusals stay
  -- reachable; skips rather than raises, because this runs from cron.
  -- Round jobs are matched by IMMINENCE (+/- 3 h of their own date-pinned fire
  -- time), never by existence: nothing unschedules them after they fire, so an
  -- existence test would disable the purge permanently after the first round.
  -- An unrecognised schedule shape blocks -- unrecognised means unsafe.
  IF EXISTS (
      SELECT 1 FROM cron.job j
       WHERE (j.active AND (j.command ILIKE '%ottoq_determinism_pair%'
                         OR j.command ILIKE '%ottoq_cert_battery_step%'))
          OR (j.jobname ~ '^r[0-9]+_' AND
              CASE WHEN j.schedule ~ '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ \*$'
                   THEN make_timestamptz(extract(year from now())::int,
                                         split_part(j.schedule,' ',4)::int,
                                         split_part(j.schedule,' ',3)::int,
                                         split_part(j.schedule,' ',2)::int,
                                         split_part(j.schedule,' ',1)::int, 0, 'UTC')
                        BETWEEN now() - interval '3 hours' AND now() + interval '3 hours'
                   ELSE true END)) THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: a certification round is scheduled - skipped';
    RETURN;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%ottoq_determinism_pair%';
  IF v_pairs > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: % certification pair(s) in flight - skipped', v_pairs;
    RETURN;
  END IF;

  SELECT keep_interval INTO v_keep
    FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
  v_keep := COALESCE(v_keep, p_keep);
  v_cut  := now() - v_keep;

  SELECT array_agg(sr.sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs sr
   WHERE sr.status <> 'running'
     AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < v_cut
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id);

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RAISE NOTICE 'retention purge (runs): nothing older than % is archived and finished', v_keep;
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RETURN;
  END IF;

  RAISE NOTICE 'retention purge (runs): keep %, cut %, % doomed run(s), dry_run=%',
               v_keep, v_cut, cardinality(v_doomed), p_dry_run;

  -- 0294 (G63): READ THE REGISTRY INTO ARRAYS, THEN LOOP BY INDEX. The previous
  -- version iterated this same query with a record cursor, which holds a portal
  -- open across the COMMIT below -- PL/pgSQL forbids that, and it is the whole
  -- defect. The ORDER BY is preserved character for character: largest table
  -- first is what makes p_time_budget_s spend itself where it matters.
  SELECT array_agg(g.table_name  ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name),
         array_agg(g.column_name ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name)
    INTO v_tabs, v_cols
    FROM public.ottoq_run_scope_registry g
    JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
   WHERE g.class = 'engine' AND g.table_schema = 'public'
     AND to_regclass('public.' || g.table_name) IS NOT NULL;

  FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);

      IF p_dry_run THEN
        EXECUTE format('SELECT count(*) FROM public.%1$I WHERE %2$I = ANY($1)', v_tabs[v_i], v_cols[v_i])
          INTO v_n USING v_doomed;
        RAISE NOTICE '  dry run: % would lose % row(s)', v_tabs[v_i], v_n;
        v_total := v_total + v_n;
        EXIT;
      END IF;

      PERFORM set_config('ottoq.retention', 'on', true);

      EXECUTE format(
        'DELETE FROM public.%1$I WHERE ctid IN '
        '(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)',
        v_tabs[v_i], v_cols[v_i]) USING v_doomed, p_micro_batch;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- 0251: STAMP ON THE FIRST ROW ACTUALLY DELETED, IN THE SAME TRANSACTION
      -- as that delete, so the marker and the deletion commit together. From
      -- this moment the run's KPIs are not whole and ottoq_kpi_five must say so.
      -- Stamping before the loop would over-claim on a pass that deletes
      -- nothing; stamping at the end would leave a budget-cut pass unmarked,
      -- which is the common case and the dangerous one.
      IF v_n > 0 AND NOT v_stamped THEN
        UPDATE public.ottoq_sim_runs
           SET purged_at = now()
         WHERE sim_run_id = ANY(v_doomed) AND purged_at IS NULL;
        v_stamped := true;
      END IF;

      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END LOOP;

  IF NOT p_dry_run THEN
    PERFORM set_config('ottoq.retention', 'on', true);
    UPDATE public.ottoq_retention_state
       SET pass_deleted = pass_deleted + v_total, updated_at = now()
     WHERE table_name = 'engine_rows';
    IF NOT FOUND THEN
      INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
      VALUES ('engine_rows', cardinality(v_doomed), v_total, now())
      ON CONFLICT (table_name) DO NOTHING;
    END IF;
    COMMIT;
  END IF;

  RAISE NOTICE 'retention purge (runs): % row(s) % across % run(s)',
               v_total, CASE WHEN p_dry_run THEN 'MATCHED (dry run)' ELSE 'deleted' END,
               cardinality(v_doomed);
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$
;

-- ── public.ottoq_retention_purge_worker(integer, integer, interval, text[]), pg_get_functiondef md5 dff3b880934e2b84d07f771118a3e884 ──
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_tables text[] DEFAULT ARRAY['ottoq_events'::text])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep      interval;
  v_aligned   boolean;
  v_cut       timestamptz;
  v_t0        timestamptz := clock_timestamp();
  v_n         bigint;
  v_total     bigint := 0;
  v_from      timestamptz;
  v_batch_ts  timestamptz;
  v_drained   boolean := false;
  v_live      uuid[];
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and this procedure commits per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  -- (2) policy wins over the caller's argument; fall back to it if no row.
  SELECT keep_interval, day_aligned INTO v_keep, v_aligned
    FROM public.ottoq_retention_policy WHERE policy_key = 'events' AND enabled;
  v_keep    := COALESCE(v_keep, p_keep);
  v_aligned := COALESCE(v_aligned, true);

  -- (3) day-aligned cut: delete only COMPLETE days older than the window.
  v_cut := now() - v_keep;
  IF v_aligned THEN
    v_cut := date_trunc('day', v_cut AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  END IF;

  -- (4) runs whose data may never be touched.
  SELECT COALESCE(array_agg(sim_run_id), '{}'::uuid[]) INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status = 'running' OR COALESCE(run_by, '') = 'production_live';

  RAISE NOTICE 'retention purge: keep %, cut %, % protected run(s)',
               v_keep, v_cut, cardinality(v_live);

  -- ---------------------------------------------------------------------------
  -- EVENTS: oldest-first walk ordered by occurred_at — THE SAME COLUMN THE DELETE
  -- IS PREDICATED ON.
  --
  -- 0006 walked this table in event_seq order and stopped when a batch deleted
  -- nothing and its newest timestamp was inside the keep window. That stopping rule
  -- is an inference: "seq order is time order". It is false here -- occurred_at is
  -- the SIM clock and runs start at a random time of day, so a run whose clock sits
  -- behind the previous one writes old-timestamped rows at high event_seq. Measured
  -- 2026-08-05: 18 inversions in 23,697 adjacent pairs. Demonstrated end-to-end: with
  -- a 30-day-old row present and the real 7-day policy, the old worker processed one
  -- window, deleted 0, exited, and left the old row in place.
  --
  -- Ordering by occurred_at removes the inference entirely. There is nothing to
  -- guess: the loop ends when there are no rows older than the cut, which is the
  -- definition of finished rather than a proxy for it. It also needs no cursor --
  -- deleted rows are gone, so the next call naturally resumes at the oldest
  -- survivor. A pass cut short by the time budget costs nothing but time.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_events' = ANY (p_tables) THEN
    v_from := '-infinity'::timestamptz;   -- start at the left edge of the index

    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

      -- STEP 1 — pick this window's UPPER TIMESTAMP by reading exactly
      -- p_micro_batch index entries. This is a bounded, ordered slice of
      -- ottoq_events_occurred_at_retention_idx: O(batch), never O(heap).
      SELECT max(w.occurred_at) INTO v_batch_ts
        FROM (SELECT e.occurred_at
                FROM public.ottoq_events e
               WHERE e.occurred_at >= v_from
                 AND e.occurred_at <  v_cut
               ORDER BY e.occurred_at
               LIMIT p_micro_batch) w;

      -- No row at all older than the cut. That is not an inference about ordering --
      -- there is simply nothing left. THE ONLY EXIT THAT MEANS "DONE".
      IF v_batch_ts IS NULL THEN
        v_drained := true;
        COMMIT;
        EXIT;
      END IF;

      -- STEP 2 — delete the whole CLOSED TIMESTAMP RANGE [v_from, v_batch_ts].
      -- The window is a range of TIME, not a count of rows, and that is deliberate:
      -- it guarantees every row sharing v_batch_ts is inside this delete even if the
      -- LIMIT above cut the group in half. Without that, advancing the watermark past
      -- v_batch_ts could step over a deletable row that happened to share a
      -- microsecond with p_micro_batch protected ones. Many events DO share one
      -- occurred_at here -- it is the sim clock, and a tick writes 60-120 events at
      -- the same value -- so this is a real case, not a theoretical one.
      -- The window is therefore at most p_micro_batch plus the tail of one timestamp
      -- group; a group is bounded by one tick's event count, well under the batch.
      DELETE FROM public.ottoq_events e
       WHERE e.occurred_at >= v_from
         AND e.occurred_at <= v_batch_ts
         AND e.occurred_at <  v_cut
         AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- STEP 3 — advance. Everything at or below v_batch_ts and older than the cut
      -- has now been deleted or is protected, so stepping one microsecond past it
      -- (timestamptz resolution) cannot skip anything. v_from strictly increases
      -- every iteration, so the walk always terminates.
      v_from := v_batch_ts + interval '1 microsecond';

      -- Observability only. cursor_block is a bigint that nothing reads back to make
      -- a decision; it now carries the walk's time watermark as epoch seconds so a
      -- human can see where the pass got to. Never dropped, never repurposed away.
      UPDATE public.ottoq_retention_state
         SET cursor_block = floor(extract(epoch FROM v_from))::bigint,
             pass_deleted = pass_deleted + v_n,
             updated_at   = now()
       WHERE table_name = 'ottoq_events';
      IF NOT FOUND THEN
        INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
        VALUES ('ottoq_events', floor(extract(epoch FROM v_from))::bigint, v_n, now())
        ON CONFLICT (table_name) DO NOTHING;
      END IF;

      COMMIT;  -- each window's work is permanent regardless of later failures
    END LOOP;

    -- End-of-pass housekeeping, moved here from 0006's early exit. It now fires only
    -- when the backlog is GENUINELY drained; the old placement could unschedule the
    -- backlog job while old rows remained, which is the whole bug in miniature.
    IF v_drained THEN
      PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
      UPDATE public.ottoq_retention_state
         SET pass_deleted = 0, updated_at = now() WHERE table_name = 'ottoq_events';
      COMMIT;
    ELSE
      RAISE NOTICE 'retention purge: events pass stopped on the % s budget with work remaining; the next call resumes at the oldest survivor.', p_time_budget_s;
    END IF;

    -- Anchors follow their day. Because the cut is day-aligned, every event that
    -- could have folded onto one of these anchors has already gone.
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_event_state_anchor
     WHERE anchor_day < (v_cut AT TIME ZONE 'UTC')::date
       AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live)));
    COMMIT;
  END IF;

  -- ---------------------------------------------------------------------------
  -- The two small tables. Same batching, same budget, unchanged from 0006 -- both
  -- already walk by their own timestamp column, so neither had the defect.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_rule_evaluations' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
        SELECT evaluation_id FROM public.ottoq_rule_evaluations
         WHERE evaluated_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  IF 'ottoq_incident_reports' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
        SELECT incident_report_id FROM public.ottoq_incident_reports
         WHERE triggered_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$
;

-- ── public.ottoq_retention_purge_worker(integer, integer, interval), pg_get_functiondef md5 3eff6dd057ff5af612ca9bd9c063ed13 ──
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(IN p_time_budget_s integer DEFAULT 75, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_cut   timestamptz := now() - p_keep;
  v_t0    timestamptz := clock_timestamp();
  v_n     bigint;
  v_round bigint;
  v_total bigint := 0;
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and these procedures commit per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);
  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running — skipped';
    RETURN;
  END IF;

  LOOP
    EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
    v_round := 0;
    PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

    DELETE FROM public.ottoq_events WHERE event_id IN (
      SELECT event_id FROM public.ottoq_events WHERE occurred_at < v_cut LIMIT p_micro_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
      SELECT evaluation_id FROM public.ottoq_rule_evaluations WHERE evaluated_at < v_cut LIMIT p_micro_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
      SELECT incident_report_id FROM public.ottoq_incident_reports WHERE triggered_at < v_cut LIMIT p_micro_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    COMMIT;
    v_total := v_total + v_round;

    IF v_round = 0 THEN
      PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
      COMMIT;
      EXIT;
    END IF;
  END LOOP;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$
;

RESET check_function_bodies;

-- ══ the live ACLs (read 2026-10-15 13:14:57 UTC and 2026-10-17 14:04:15 UTC), each granted in the order that
--    reproduces its text: {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres} for pause, resume and
--    benchmark reset; {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} for start-a-scenario and
--    run-to-end; the default PUBLIC entry plus anon, authenticated and service_role for the other twelve ══
REVOKE ALL ON FUNCTION public.ottoq_pause_run(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_pause_run(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_pause_run(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.ottoq_resume_run(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_resume_run(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_resume_run(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_run_scenario(text, bigint, text, timestamp with time zone) TO service_role;
REVOKE ALL ON FUNCTION public.ottoq_benchmark_reset(uuid, numeric, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_benchmark_reset(uuid, numeric, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_benchmark_reset(uuid, numeric, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.ottoq_run_policy_to_end(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_run_policy_to_end(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_run_policy_to_end(uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_production_start(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.ottoq_production_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_production_start(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_production_stop(text) TO anon;
GRANT EXECUTE ON FUNCTION public.ottoq_production_stop(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_production_stop(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_start(bigint, text, uuid, integer) TO anon;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_start(bigint, text, uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_start(bigint, text, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_finish(uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_finish(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_cert_arm_finish(uuid) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm(bigint, text, uuid, integer, timestamp with time zone, integer) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_cert_arm_wave(bigint, text, uuid, integer, integer) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_fr1_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, boolean) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_safety_cert_arm(uuid, bigint, uuid, integer, timestamp with time zone, numeric) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_demo_metronome(integer) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_demo_metronome(integer) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_demo_metronome(integer) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval, text[]) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval, text[]) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval, text[]) TO service_role;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval) TO anon;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval) TO authenticated;
GRANT EXECUTE ON PROCEDURE public.ottoq_retention_purge_worker(integer, integer, interval) TO service_role;
