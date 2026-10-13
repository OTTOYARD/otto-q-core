-- tests/fixtures/production_start_stub.sql -- what 0719 meets. public.ottoq_production_start is the live definition of
-- 2026-10-13 (pg_get_functiondef, byte for byte: md5 c0ae7ec68b695cd76c22268852568bea). public.ottoq_operator_start_run
-- is a stub carrying the live door's world-lock key and its cancel predicate verbatim (checked against the live
-- definition at 20:42 UTC), which is all 0719 reads of it. The tables are minimal stand-ins. Used by
-- tests/test_production_start_world_sql.py.
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE TABLE public.t_inflight (n int NOT NULL DEFAULT 0); INSERT INTO public.t_inflight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql
  AS 'SELECT n FROM public.t_inflight';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial, label text, object_kind text, schema_name text,
  object_name text, definition text, def_md5 text, captured_at timestamptz DEFAULT now());
CREATE TABLE public.depots (id uuid PRIMARY KEY, feed_mode text);
CREATE TABLE public.ottoq_scenarios (scenario_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), scenario_code text);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, scenario_id uuid, scenario_code text, started_at timestamptz,
  next_tick_due_at timestamptz, sim_clock_start timestamptz, sim_clock_current timestamptz, sim_clock_end timestamptz,
  time_scale numeric, tick_interval_seconds int, depot_id uuid, random_seed bigint, status text, run_by text, policy text,
  demo_speed_x numeric);
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric,
  updated_by text, updated_at timestamptz);
CREATE TABLE public.t_events (event_type text, payload jsonb);
CREATE FUNCTION public.ottoq_agentic_arm(uuid, text) RETURNS jsonb LANGUAGE sql AS $s$SELECT '{"arming": {}}'::jsonb$s$;
CREATE FUNCTION public.ottoq_is_agent_actor(text) RETURNS boolean LANGUAGE sql AS $s$SELECT $1 LIKE 'ottoq_prime%'$s$;
CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_actor_id text, p_event_type text, p_entity_type text,
  p_payload jsonb, p_severity text, p_ingest_source text, p_data_source text, p_sim_run_id uuid) RETURNS void
  LANGUAGE sql AS $s$INSERT INTO public.t_events VALUES (p_event_type, p_payload)$s$;
CREATE FUNCTION public.ottoq_operator_start_run(p_scenario_code text, p_seed bigint DEFAULT NULL::bigint,
  p_run_by text DEFAULT 'operator_demo'::text, p_start_clock timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb LANGUAGE plpgsql AS $function$
DECLARE
  c_world  constant bigint := hashtext('ottoq_recert_runner')::bigint;   -- the key ottoq_try_world_lock takes
  r record;
BEGIN
  -- a stub: only the cancel predicate and the lock key are the live door's (0719's P1 and V2 read them)
  FOR r IN
    SELECT a.pid
      FROM pg_stat_activity a
     WHERE a.pid <> pg_backend_pid()
       AND a.datname = current_database()
       AND COALESCE(a.query, '') !~* 'migration-version:'
       AND (   a.pid IN (SELECT l.pid FROM pg_locks l
                          WHERE l.locktype = 'advisory' AND l.granted AND l.objsubid = 1
                            AND ((l.classid::bigint << 32) | l.objid::bigint) = c_world)
            OR (a.state = 'active' AND a.query ~* 'ottoq_(determinism|dial|ab)_pair\s*\('))
  LOOP NULL; END LOOP;
  RETURN '{}'::jsonb;
END;
$function$;
-- the live definition, byte for byte
CREATE OR REPLACE FUNCTION public.ottoq_production_start(p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb; v_inherited jsonb;
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
                                    'agent_written_settings_in_force', v_inherited,
                                    'tick', 'ottoq-depot-tick */2min -> twin.ottoq_world_advance (wall-elapsed) -> decide_and_dispatch'),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'depot_id', p_depot,
    'feed_mode', v_feed, 'run_by', 'production_live', 'policy', 'otto_q',
    'driver', 'ottoq-depot-tick cron (*/2 min) -> twin.ottoq_world_advance -> ottoq_sim_decide_and_dispatch',
    'agents', 'armed (0629): the agent proposes and the kernel disposes; no write under an agent''s name reaches this '
              'session''s settings',
    'arming', v_ps -> 'arming',
    'agent_written_settings_in_force', v_inherited);
END
$function$;
RESET check_function_bodies;
