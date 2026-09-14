-- migration-version: 20260914144547
-- migration-name:    0309_benchmark_had_everything_except_a_scenario
--
-- 0309  THE BENCHMARK DEPOT HAD 160 STALLS, 100 VEHICLES AND NO WAY TO START
--       A RUN -- AND THAT, NOT A BROKEN DEPOT, IS WHY ALL NINE ABORTED
--
-- Chase, 2026-09-14, on bringing the loop live: "use whatever data input we
-- have or have from the Twin that is baked in for simulation... I want to make
-- sure our loops are fully analyzing what they would come in contact with from
-- a real time scenario with live vehicles, but just with a simulation/twin
-- variable data set. It should mimic work models and variables. I think we
-- have most of that already in the Twin."
--
-- We do. It was all pointed at one depot.
--
-- ---------------------------------------------------------------------------
-- WHAT WAS ACTUALLY WRONG WITH BENCHMARK
--
-- 0308 picked depot 22222222 (Benchmark) as the only place the self-improvement
-- loop may write dials, because it is the only full-size depot with no
-- certification history. Its nine sim runs all read status='aborted', which
-- looks like a broken depot, and db/checks/0234 §D deliberately refused to say
-- why -- failure_reason and validation_notes are NULL on all nine and the
-- events are gone to the 48h retention purge.
--
-- The cause turns out to be upstream of anything those rows could have said.
-- twin.ottoq_sim_start_run does NOT take a depot argument. It takes a scenario
-- code, and the depot comes from the scenario:
--
--     SELECT * INTO v_scenario FROM ottoq_scenarios WHERE scenario_code = ...
--     ... INSERT ... depot_id ... VALUES ... v_scenario.depot_id ...
--
-- and ottoq_scenarios held NINE rows, of which SEVEN point at the flagship
-- depot, ONE at the grid fixture, and ONE (production) at NULL. Not one
-- scenario has ever pointed at Benchmark. So the normal start path could not
-- target that depot AT ALL, and whatever created those nine runs bypassed it.
--
-- Measured, and this is the part that makes the fix small:
--
--     depot 22222222   stalls 160  (115 staging, 30 l2, 10 dcfc, 3 wash, 2 svc)
--                      vehicles 100 across 3 classes, every one class-coded
--                      BESS 1
--                      scenarios 0
--
-- For comparison the flagship depot has 120 vehicles and SOME OF THEM CARRY A
-- NULL vehicle_class_code. Benchmark is the cleaner world of the two. It was
-- never unfit; it was unreachable.
--
-- ---------------------------------------------------------------------------
-- WHY CLONE THE LIBRARY RATHER THAN WRITE ONE SCENARIO
--
-- The tension this resolves: the flagship depot has the realistic scenario
-- library -- normal_day, busy_day, heat_wave, charger_outage_morning_rush,
-- aggressive_fleet_turnover, which is exactly the "work models and variables"
-- the loop needs to be tested against -- but it is the depot the loop may
-- never touch. Benchmark may be tuned but had nothing to tune against. A
-- single hand-written scenario would have made the loop runnable and its
-- evidence worthless: an agent that converges on one flat day has proved
-- nothing about a heat wave or a charger outage.
--
-- The clone is cheap because the scenarios turn out to be DEPOT-PORTABLE, and
-- that was measured rather than assumed. For all five source rows:
--
--     fleet_operator_ids            = '{}' (empty) on every one
--     initial_conditions, arrival_profile, timeline, stress_params
--                                   contain NO uuid anywhere
--                                   (regex '[0-9a-f]{8}-...-[0-9a-f]{12}')
--
-- So nothing in a scenario payload names a flagship stall, vehicle, charger or
-- operator. depot_id is the only binding, and changing it is the whole port.
-- Had any payload embedded an id this migration would have to remap it, and
-- A3 below fails the migration if a future source row ever does.
--
-- ---------------------------------------------------------------------------
-- IDS ARE DERIVED, NOT MINTED
--
-- scenario_id is md5('ottoq-bench-scenario:' || code)::uuid rather than
-- gen_random_uuid(). Two reasons, and the second is this repo's own history:
-- it makes the migration idempotent (re-applying writes the same ids), and a
-- minted id is a fresh random value entering a table -- which is exactly the
-- shape of the defect 0280 fixed, where uuid_generate_v4() inside a hashed
-- frame made the content hash move on every capture. Benchmark is not
-- certified today, but deriving the id costs nothing and removes the question.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE.
--
-- This migration inserts rows, on a depot no certification column references,
-- with scenario codes no certification column names. It modifies no function
-- and no existing row. A2 asserts that ottoq_cert_columns names neither the
-- Benchmark depot nor any bench_ scenario, so no canon can read any of this.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- P0. THE TARGET DEPOT IS POPULATED. A scenario pointing at an empty depot
--     would start a run with nothing in it and "the loop converged" would mean
--     "the loop had nothing to do".
-- ---------------------------------------------------------------------------
DO $p0$
DECLARE v_stalls int; v_veh int; v_cls int;
BEGIN
  SELECT count(*) INTO v_stalls FROM public.stalls
   WHERE depot_id = '22222222-2222-2222-2222-222222222222';
  SELECT count(*), count(DISTINCT vehicle_class_code) INTO v_veh, v_cls FROM public.vehicles
   WHERE home_depot_id = '22222222-2222-2222-2222-222222222222';

  IF v_stalls < 50 OR v_veh < 50 OR v_cls < 2 THEN
    RAISE EXCEPTION 'P0 FAILED: Benchmark holds % stall(s), % vehicle(s), % class(es) -- too thin to be a realistic twin',
                    v_stalls, v_veh, v_cls;
  END IF;
END $p0$;

-- ---------------------------------------------------------------------------
-- P1. THE SOURCE SCENARIOS EXIST AND ARE DEPOT-PORTABLE. If a payload ever
--     starts embedding a uuid, a blind clone would carry a flagship id onto
--     Benchmark -- refuse rather than do that.
-- ---------------------------------------------------------------------------
DO $p1$
DECLARE v_n int; v_bad text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_scenarios
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
     AND scenario_code IN ('normal_day','busy_day','heat_wave',
                           'charger_outage_morning_rush','aggressive_fleet_turnover');
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'P1 FAILED: expected 5 source scenarios on the flagship depot, found %', v_n;
  END IF;

  SELECT string_agg(scenario_code, ', ') INTO v_bad FROM public.ottoq_scenarios
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
     AND scenario_code IN ('normal_day','busy_day','heat_wave',
                           'charger_outage_morning_rush','aggressive_fleet_turnover')
     AND ( (COALESCE(initial_conditions::text,'') || COALESCE(arrival_profile::text,'')
         || COALESCE(timeline::text,'')           || COALESCE(stress_params::text,''))
           ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
           OR COALESCE(array_length(fleet_operator_ids, 1), 0) > 0 );
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'P1 FAILED: scenario(s) [%] bind flagship ids; a clone would carry them to Benchmark', v_bad;
  END IF;
END $p1$;

-- ---------------------------------------------------------------------------
-- P2. NOTHING IN FLIGHT. pg_stat_activity is the authority (0308's lesson: an
--     uncommitted pair is invisible in ottoq_sim_runs).
-- ---------------------------------------------------------------------------
DO $p2$
DECLARE v_backends int; v_running int; v_cron int;
BEGIN
  SELECT count(*) INTO v_backends FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
       OR query ILIKE '%ottoq_decide_tick%'      OR query ILIKE '%ottoq_cil_tick%');
  IF v_backends <> 0 THEN
    RAISE EXCEPTION 'P2 FAILED: % engine backend(s) executing; apply in a quiesced window', v_backends;
  END IF;

  SELECT count(*) INTO v_running FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_running <> 0 THEN
    RAISE EXCEPTION 'P2 FAILED: % sim run(s) running', v_running;
  END IF;

  SELECT count(*) INTO v_cron FROM cron.job WHERE jobname ~ '^r[0-9]+' AND active;
  IF v_cron <> 0 THEN
    RAISE EXCEPTION 'P2 FAILED: % round job(s) armed', v_cron;
  END IF;
END $p2$;

-- ===========================================================================
-- THE CLONE
-- ===========================================================================

INSERT INTO public.ottoq_scenarios (
  scenario_id, scenario_code, category, title, description, validates,
  expected_outcome, depot_id, fleet_operator_ids, sim_duration_minutes,
  default_time_scale, tick_interval_seconds, initial_conditions, arrival_profile,
  timeline, random_seed, stress_params, status, tags, introduced_in)
SELECT
  md5('ottoq-bench-scenario:' || s.scenario_code)::uuid,
  'bench_' || s.scenario_code,
  s.category,
  'Benchmark — ' || s.title,
  COALESCE(s.description, '') ||
    ' [0309: cloned from the flagship scenario of the same name onto the Benchmark depot, '
    'which is the only full-size depot the self-improvement loop is permitted to tune (0308). '
    'Payload is byte-identical to the source; depot_id is the only field changed.]',
  s.validates,
  s.expected_outcome,
  '22222222-2222-2222-2222-222222222222'::uuid,
  s.fleet_operator_ids,
  s.sim_duration_minutes,
  s.default_time_scale,
  s.tick_interval_seconds,
  s.initial_conditions,
  s.arrival_profile,
  s.timeline,
  s.random_seed,
  s.stress_params,
  s.status,
  s.tags,
  '0309'
FROM public.ottoq_scenarios s
WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
  AND s.scenario_code IN ('normal_day','busy_day','heat_wave',
                          'charger_outage_morning_rush','aggressive_fleet_turnover')
ON CONFLICT (scenario_id) DO NOTHING;

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A1. FIVE SCENARIOS NOW POINT AT BENCHMARK, AND THEIR PAYLOADS MATCH THEIR
--     SOURCES EXACTLY. A clone that quietly altered a payload would give the
--     loop a different world than the one the flagship library describes.
-- ---------------------------------------------------------------------------
DO $a1$
DECLARE v_n int; v_drift text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_scenarios
   WHERE depot_id = '22222222-2222-2222-2222-222222222222';
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'A1 FAILED: Benchmark now has % scenario(s), expected 5', v_n;
  END IF;

  SELECT string_agg(b.scenario_code, ', ') INTO v_drift
    FROM public.ottoq_scenarios b
    JOIN public.ottoq_scenarios s
      ON s.scenario_code = substr(b.scenario_code, 7)
     AND s.depot_id = '11111111-1111-1111-1111-111111111111'
   WHERE b.depot_id = '22222222-2222-2222-2222-222222222222'
     AND ( b.initial_conditions   IS DISTINCT FROM s.initial_conditions
        OR b.arrival_profile      IS DISTINCT FROM s.arrival_profile
        OR b.timeline             IS DISTINCT FROM s.timeline
        OR b.stress_params        IS DISTINCT FROM s.stress_params
        OR b.sim_duration_minutes IS DISTINCT FROM s.sim_duration_minutes
        OR b.tick_interval_seconds IS DISTINCT FROM s.tick_interval_seconds
        OR b.default_time_scale   IS DISTINCT FROM s.default_time_scale );
  IF v_drift IS NOT NULL THEN
    RAISE EXCEPTION 'A1 FAILED: cloned scenario(s) [%] differ from their source beyond depot_id', v_drift;
  END IF;
END $a1$;

-- ---------------------------------------------------------------------------
-- A2. NO CERTIFICATION COLUMN CAN SEE ANY OF THIS. The forces_recert=false
--     claim, asserted rather than argued.
-- ---------------------------------------------------------------------------
DO $a2$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_cert_columns
   WHERE depot_id = '22222222-2222-2222-2222-222222222222'
      OR scenario LIKE 'bench\_%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A2 FAILED: % certification column(s) reference Benchmark or a bench_ scenario; '
                    'this migration is NOT forces_recert=false', v_n;
  END IF;
END $a2$;

-- ---------------------------------------------------------------------------
-- A3. THE FLAGSHIP LIBRARY IS UNTOUCHED. A clone must add, never edit.
-- ---------------------------------------------------------------------------
DO $a3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_scenarios
   WHERE depot_id = '11111111-1111-1111-1111-111111111111';
  IF v_n <> 7 THEN
    RAISE EXCEPTION 'A3 FAILED: the flagship depot now has % scenario(s), expected the original 7', v_n;
  END IF;
END $a3$;

-- ---------------------------------------------------------------------------
-- A4. THE GUARD FROM 0308 STILL PERMITS BENCHMARK. If cloning a scenario had
--     somehow made Benchmark look certified, the loop would have nowhere to
--     run and this migration would have defeated 0308.
-- ---------------------------------------------------------------------------
DO $a4$
DECLARE v_reason text; v_run uuid;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '22222222-2222-2222-2222-222222222222'
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'A4 FAILED: no Benchmark run to test the guard against'; END IF;

  v_reason := public.ottoq_cil_tune_refusal(v_run);
  IF v_reason = 'depot_under_certification' THEN
    RAISE EXCEPTION 'A4 FAILED: Benchmark now reads as a certified depot; the loop has nowhere to run';
  END IF;
END $a4$;
