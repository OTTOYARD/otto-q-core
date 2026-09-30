-- A STUB EXTENSION for exercising db/migrations/0568 on a throwaway PostgreSQL. NOT the engine. Loaded AFTER
-- tests/fixtures/throughput_stub_engine.sql and tests/fixtures/site_buildout_stub.sql, and BEFORE 0565-0568.
--
-- The arm protocol calls a dozen engine functions. Each is reduced here to what the harness's own logic can be tested
-- against: the door creates a run, a tick advances its clock by tick_interval_seconds x time_scale, the atoms and the
-- boot image are pure functions of the seed, the seat and the depot's stall census (so a replicate agrees and a
-- build-out shows), and every call writes what it saw into stub_calls. stub_faults makes a chosen seed fail at a tick
-- (an engine error the arm must record) or at the door (a failure the runner must record and move past).
-- tests/test_throughput_sweep_sql.py says what each must do.

-- The throughput stub keeps one run live for 0565's backfill test; a sweep runs only between runs.
UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = 'a0000000-0000-0000-0000-000000000002';

ALTER TABLE public.ottoq_sim_runs ADD COLUMN validation_notes text;
CREATE TABLE public.stub_calls (n bigserial, fn text, args jsonb);
CREATE TABLE public.stub_faults (seed bigint, at_tick integer, at_door boolean DEFAULT false);
CREATE TABLE public.stub_floor (floor timestamptz);
INSERT INTO public.stub_floor VALUES ('2026-09-01 00:00+00');

-- pg_cron, reduced to the job table and schedule()
CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid bigserial PRIMARY KEY, jobname text UNIQUE, schedule text, command text,
                       active boolean NOT NULL DEFAULT true, username text NOT NULL DEFAULT current_user);
CREATE FUNCTION cron.schedule(job_name text, schedule text, command text) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job (jobname, schedule, command) VALUES (job_name, schedule, command)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
  RETURNING jobid $$;

-- dials
CREATE TABLE public.ottoq_policy_param_catalog (
  param_key text PRIMARY KEY, min_value numeric, max_value numeric, default_value numeric, description text,
  affects text, agent_writable boolean);
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value) VALUES
  ('proposer_seat', 0, 2, 0), ('deploy_peak_fraction', 0.30, 1.00, 0.90), ('cuopt_propose_enabled', 0, 1, 1),
  ('cuopt_first_refusal_max_defers', 0, 5, 1), ('orchestrator_agent_enabled', 0, 1, 1),
  ('charge_batch_order', 0, 1, 0),                 -- as 0570 catalogues it (0571's premise)
  ('energy_orchestration_enabled', 0, 1, 1);       -- the engine's energy switch (0575's premise)
CREATE TABLE public.ottoq_policy_params (
  scope_type text, scope_id uuid, param_key text, param_value numeric, updated_by text,
  PRIMARY KEY (scope_type, scope_id, param_key));
CREATE FUNCTION public.ottoq_policy_get(p_run uuid, p_key text, p_default numeric) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT param_value FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = p_run AND param_key = p_key),
    (SELECT param_value FROM public.ottoq_policy_params WHERE scope_type = 'global' AND param_key = p_key),
    p_default) $$;
CREATE FUNCTION public.ottoq_policy_set(p_scope_type text, p_scope_id uuid, p_key text, p_value numeric, p_by text)
RETURNS jsonb LANGUAGE sql AS $$
  INSERT INTO public.ottoq_policy_params VALUES (p_scope_type, p_scope_id, p_key, p_value, p_by)
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by
  RETURNING jsonb_build_object('ok', true) $$;

-- certification, the floor, the engine hash, the world lock
CREATE TABLE public.ottoq_determinism_canon (enabled boolean, satisfies_floor boolean);
CREATE FUNCTION public.ottoq_dial_pair_floor() RETURNS timestamptz LANGUAGE sql STABLE AS $$ SELECT floor FROM public.stub_floor $$;
CREATE FUNCTION public.ottoq_engine_hash() RETURNS text LANGUAGE sql STABLE AS $$ SELECT 'engine-stub' $$;
CREATE FUNCTION public.ottoq_try_world_lock(p_attempts integer DEFAULT 20, p_sleep_s numeric DEFAULT 0.5) RETURNS boolean
LANGUAGE sql AS $$ SELECT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint) $$;

-- the two markers 0568's P1 reads
CREATE FUNCTION public.ottoq_dial_pair(p_experiment uuid, p_seed bigint, p_budget integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- UPDATE public.ottoq_sim_runs SET time_scale = 2 * x.sim_min_per_tick, tick_interval_seconds = 30 WHERE sim_run_id = v_run;
  RETURN;
END $$;
CREATE FUNCTION public.ottoq_operator_start_run() RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM hashtext('ottoq_recert_runner'); END $$;

CREATE TABLE public.ottoq_sim_scenarios (scenario_code text, status text, default_depot_id uuid);
INSERT INTO public.ottoq_sim_scenarios VALUES ('busy_day', 'available', '11111111-1111-1111-1111-111111111111');
CREATE TABLE public.ottoq_bess_units (depot_id uuid, current_soc_kwh numeric);
INSERT INTO public.ottoq_bess_units VALUES ('11111111-1111-1111-1111-111111111111', 500);

CREATE FUNCTION public.stub_census(p_depot uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT count(*) FILTER (WHERE stall_type = 'dcfc') || 'dcfc/' || count(*) FILTER (WHERE stall_type = 'l2') || 'l2'
    FROM public.stalls WHERE depot_id = p_depot $$;

-- the fleet reset: records the tagging GUC it ran under
CREATE FUNCTION public.ottoq_tick_invariance_reset_fleet(p_depot uuid, p_seed bigint, p_as_of timestamptz) RETURNS integer
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.stub_calls (fn, args) VALUES ('reset', jsonb_build_object(
    'seed', p_seed, 'guc', current_setting('ottoq.sim_run_id', true), 'census', public.stub_census(p_depot)));
  RETURN 0;
END $$;

-- the operator's door: a running run on the depot as it is now
CREATE FUNCTION public.ottoq_sim_run_scenario(p_code text, p_seed bigint, p_run_by text, p_start timestamptz) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_run uuid := gen_random_uuid();
BEGIN
  IF EXISTS (SELECT 1 FROM public.stub_faults WHERE seed = p_seed AND at_door) THEN
    RAISE EXCEPTION 'fleet seed failed at depot 11111111-1111-1111-1111-111111111111, so no run was started: stub';
  END IF;
  INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, scenario_code, random_seed, tick_count, policy,
                                     tick_interval_seconds, time_scale, sim_clock_start, sim_clock_current, started_at,
                                     run_by, payload)
  VALUES (v_run, '11111111-1111-1111-1111-111111111111', 'running', p_code, p_seed, 0, 'otto_q', 30, 60, p_start, p_start,
          now(), p_run_by, '{}'::jsonb);
  INSERT INTO public.stub_calls (fn, args) VALUES ('door', jsonb_build_object(
    'seed', p_seed, 'run_by', p_run_by, 'census', public.stub_census('11111111-1111-1111-1111-111111111111')));
  RETURN v_run;
END $$;

CREATE FUNCTION ottoq.ottoq_world_fingerprint(p_depot uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT md5(public.stub_census(p_depot)) $$;
CREATE FUNCTION public.ottoq_boot_state_fingerprint(p_depot uuid, p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('seed', r.random_seed, 'census', public.stub_census(p_depot), 'calibration', jsonb_build_object('h', 'cal-1'))
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run $$;

-- a tick: the clock moves by the run's own cadence; a car arrives on tick 1 and leaves fully charged on tick 3
CREATE FUNCTION public.ottoq_sim_advance_tick(p_run uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r public.ottoq_sim_runs%ROWTYPE; v_next timestamptz;
BEGIN
  SELECT * INTO r FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  IF EXISTS (SELECT 1 FROM public.stub_faults WHERE seed = r.random_seed AND at_tick = r.tick_count + 1) THEN
    RAISE EXCEPTION 'stub engine error at tick %', r.tick_count + 1;
  END IF;
  v_next := r.sim_clock_current + make_interval(secs => r.tick_interval_seconds * r.time_scale);
  UPDATE public.ottoq_sim_runs SET tick_count = tick_count + 1, sim_clock_current = v_next WHERE sim_run_id = p_run;
  IF r.tick_count + 1 = 1 THEN
    INSERT INTO public.ottoq_visit_needs VALUES (gen_random_uuid(), 'c0000000-0000-0000-0000-0000000000ee', p_run,
      r.depot_id, 'D_charge_and_go', v_next, v_next + interval '2 hours', 100,
      jsonb_build_array(jsonb_build_object('svc', 'charge', 'status', 'done', 'must_do', true,
                                           'closed_at', v_next + make_interval(secs => r.tick_interval_seconds * r.time_scale))));
    INSERT INTO public.ocpp_sessions VALUES (p_run, 'd0000000-0000-0000-0000-00000000dc01', v_next,
      v_next + make_interval(secs => r.tick_interval_seconds * r.time_scale), 30, 150);
  ELSIF r.tick_count + 1 = 3 THEN
    INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, soc_at_dispatch_pct)
    VALUES ('c0000000-0000-0000-0000-0000000000ee', p_run, v_next, 100);
  END IF;
END $$;

-- the atoms: a pure function of seed, seat and census, so a replicate agrees and a build-out shows
CREATE FUNCTION public.ottoq_ab_arm_atoms(p_depot uuid, p_run uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'h_evt', md5(r.random_seed || '|' || public.ottoq_policy_get(p_run, 'proposer_seat', 0) || '|' || public.stub_census(p_depot)),
    'h_dec', md5('dec|' || r.random_seed || '|' || public.ottoq_policy_get(p_run, 'proposer_seat', 0)),
    'ticks', r.tick_count, 'fp', md5(public.stub_census(p_depot)))
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run $$;

-- the arm metrics: OTTO-Q's seat deploys five more car-hours, so the pairs have something to show. Every seat is asked
-- for the same 120 car-hours; OTTO-Q leaves 20 unmet, FIFO 24 and greedy 26, and OTTO-Q's site costs $11.25 more.
-- 0570's dial at 1 leaves 3 fewer unmet, so a night-2 contrast has something to show too. With the energy planner off
-- (0575's control cells) the site costs $150 a day more and peaks 400 kW higher; on, every value is as before.
CREATE FUNCTION public.ottoq_dial_arm_metrics(p_run uuid, p_depot uuid, p_soc0 numeric) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'rule_evaluations', 12, 'soc_start_kwh', p_soc0,
    'demand_car_hours', 120,
    'deployed_car_hours', 100 + CASE WHEN seat = 0 THEN 5 ELSE 0 END,
    'unmet_demand_car_hours', CASE seat WHEN 0 THEN 20 WHEN 1 THEN 24 ELSE 26 END - 3 * batch_order,
    'unmet_demand_pct', 3.5,
    'site_cost_usd_per_day', CASE WHEN seat = 0 THEN 431.50 ELSE 420.25 END + CASE WHEN energy = 0 THEN 150 ELSE 0 END,
    'peak_site_kw', 900 + CASE WHEN energy = 0 THEN 400 ELSE 0 END)
    FROM (SELECT public.ottoq_policy_get(p_run, 'proposer_seat', 0) AS seat,
                 public.ottoq_policy_get(p_run, 'charge_batch_order', 0) AS batch_order,
                 public.ottoq_policy_get(p_run, 'energy_orchestration_enabled', 1) AS energy) z
$$;

CREATE FUNCTION public.ottoq_sim_stop_and_reset(p_run uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.ottoq_sim_runs SET status = 'stopped' WHERE sim_run_id = p_run;
  PERFORM set_config('ottoq.sim_run_id', p_run::text, true);   -- as the real one pins the run it tore down
  INSERT INTO public.stub_calls (fn, args) VALUES ('stop', jsonb_build_object('reason', p_reason,
    'census', public.stub_census('11111111-1111-1111-1111-111111111111')));
  RETURN jsonb_build_object('ok', true);
END $$;
