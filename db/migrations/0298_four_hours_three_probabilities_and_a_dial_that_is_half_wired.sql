-- migration-version: PENDING
-- migration-name:    0298_four_hours_three_probabilities_and_a_dial_that_is_half_wired
--
-- 0298  FOUR HOURS, THREE PROBABILITIES, A FRACTION -- AND ONE DIAL THAT IS
--       ONLY HALF WIRED TO THE THING IT IS NAMED AFTER
--
-- Eight more of the 27 dials ottoq_policy_set refuses. As in 0297, every bound
-- is READ OFF THE CONSUMER. Three distinct derivations, and one finding that
-- has nothing to do with the catalog and was turned up by reading for it.
--
-- ---------------------------------------------------------------------------
-- DERIVATION 1 -- FOUR HOUR-OF-DAY DIALS, min 0 max 23
--
--   night_wave_start_hour        23   public.ottoq_recall_naive_threshold_v1
--   night_wave_end_hour           6   public.ottoq_recall_naive_threshold_v1
--   overnight_recall_start_hour  22   twin.ottoq_sim_auto_dispatch_tick
--   overnight_recall_end_hour     3   twin.ottoq_sim_auto_dispatch_tick
--
-- Each is compared against v_hour, and both consumers produce v_hour the same
-- way:  EXTRACT(HOUR FROM <clock> AT TIME ZONE 'America/Chicago')::int.  That
-- expression has range 0..23, so 24 and above make `v_hour >= start` never
-- true -- indistinguishable from "never" -- and below 0 make it always true --
-- indistinguishable from 0. 0..23 is the smallest interval that still
-- expresses every distinguishable behaviour.
--
-- The night-wave pair has a SECOND, independent witness: the wrap arithmetic
--
--     v_hours_in := CASE WHEN v_hour >= v_wave_start THEN v_hour - v_wave_start
--                        ELSE v_hour + 24 - v_wave_start END;
--
-- uses 24 as the modulus explicitly. A start outside 0..23 puts v_hours_in
-- outside the hour arithmetic the bands are cut on.
--
-- And 0 vs 24 costs nothing at the other end: with start 23, end=24 gives
-- `23 <= 24` so `hour >= 23 AND hour < 24` -- hour 23 alone; end=0 gives the
-- wrap branch `hour >= 23 OR hour < 0` -- hour 23 alone. Same window.
--
-- ---------------------------------------------------------------------------
-- DERIVATION 2 -- THREE THRESHOLDS AGAINST A [0,1) DRAW, min 0 max 1
--
--   vehicle_fault_rate_per_tick        0.004  twin.ottoq_sim_vehicle_exception_handler
--   vehicle_fault_immobilizing_share   0.35   twin.ottoq_sim_vehicle_exception_handler
--   run_start_deployed_fraction        0.55   twin.ottoq_sim_start_run
--
-- The first two are the right-hand side of a comparison whose left-hand side
-- is twin.ottoq_sim_seeded_random, and that function's last line is
--
--     RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
--
-- i.e. normalised to [0, 1). So 0 means "never fires", 1 means "always fires",
-- and every value outside [0,1] is indistinguishable from one of those two.
-- The range is the draw's range; it was not chosen. P4 pins that line, because
-- if the normalisation ever changes these two bounds are wrong.
--
-- Corroboration for the second, from a dial already in the catalog:
-- vehicle_fault_service_incompatible_share is catalogued 0..1 and its read site
-- is LEAST(<that dial>, v_immob_share) -- the same quantity, ceiled by this one.
--
-- run_start_deployed_fraction is not compared to a draw; it is multiplied:
--
--     v_limit := GREATEST(0, LEAST(v_total, CEIL(v_total * COALESCE(p_fraction, 0.92))::int));
--
-- The consumer clamps the RESULTING COUNT to [0, v_total]. A fraction of 2
-- therefore produces exactly what 1 produces, and -1 produces exactly what 0
-- produces. Same argument, arrived at through the arithmetic instead of the
-- comparison. (Note in passing, recorded not fixed: the callee's own fallback
-- is 0.92 while twin.ottoq_sim_start_run passes 0.55. The caller never passes
-- NULL, so the 0.92 is unreachable today -- but it is a second default for one
-- quantity and the two do not agree.)
--
-- ---------------------------------------------------------------------------
-- DERIVATION 3 -- ONE PERCENTAGE, min 0 max 100
--
--   sensor_health_clean_pct   90   ottoq.ottoq_observe_asset
--
-- Read site:  COALESCE(v_p.sensor_health_pct, 100) < v_sensor_health_floor.
-- The consumer's own COALESCE declares the top of the scale -- a missing
-- reading is treated as a perfect 100 -- so the comparand is a 0..100 percent,
-- and a floor outside that is indistinguishable from one of the endpoints.
-- Corroboration, not proof: the 120 live vehicle_need_profile rows span
-- 88.1 to 99.7.
--
-- ---------------------------------------------------------------------------
-- G64 -- THE FINDING. overnight_recall_end_hour IS ONLY HALF WIRED.
--
-- It is catalogued here, with the caveat in its own description row, because
-- shipping the dial without the caveat would be worse than not shipping it.
--
-- twin.ottoq_sim_auto_dispatch_tick reads the dial into v_win_end and then
-- opens the recall window with a LITERAL:
--
--     IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN
--                                                            ^
--                                            not v_win_end -- 6
--
-- v_win_end is not dead -- it reaches two other places:
--   * passed on as p_win_end to ottoq.ottoq_plan_dispatch_tick, whose
--     eligibility test is
--         AND ((p_hour >= p_win_end AND p_hour < p_win_start)
--              OR NOT ottoq_is_overnight_holdout(...))
--   * and into the event payload's 'holdout_active' flag.
--
-- So at the dial's own default of 3, between 03:00 and 05:59 America/Chicago
-- the WINDOW IS OPEN (the literal 6) while the PLANNER believes the overnight
-- window has already ended -- which makes its first branch true for every
-- vehicle and BYPASSES the per-vehicle holdout check entirely for those three
-- hours. The event stream reports holdout_active = false there, consistent
-- with the planner and not with the gate.
--
-- The honest sentence: "overnight_recall_end_hour sets where the per-vehicle
-- overnight holdout stops applying, not where the recall window closes; the
-- window closes at the literal 6 in the twin's gate, and at the dial's default
-- of 3 the two disagree for three hours a night."
--
-- NOT FIXED HERE, DELIBERATELY. Replacing that 6 with v_win_end changes what
-- the twin does on a tick path, so it is forces_recert=TRUE and belongs in a
-- certification window, not riding along with a catalog file. P5 pins BOTH
-- source lines, so the day the gate is fixed this file's own precondition
-- fails and the description that describes the split gets revisited instead of
-- quietly going stale.
--
-- ---------------------------------------------------------------------------
-- THREE LIVE ROWS, AND WHY THEY DO NOT DISTURB ANYTHING
--
-- This paragraph said TWO when it was first written, and P0 refused the file on
-- its dry run because there are THREE. The error was mine and it was the usual
-- one: I checked the live-row count for the keys I had already been looking at
-- (the four hours) and reported it as though I had checked all eight. The
-- precondition is what caught it, which is the entire reason it counts rather
-- than assumes.
--
-- Unlike 0297's ten, three of these eight DO have live rows, all GLOBAL scope,
-- all written on 2026-08-13, all by paths that bypassed ottoq_policy_set --
-- which they had to, since the keys were uncatalogued and the setter would have
-- refused them. That is G62, visible in the data:
--
--   night_wave_start_hour        23    claude_night_waves  2026-08-13 14:32 UTC
--   night_wave_end_hour           6    claude_night_waves  2026-08-13 14:32 UTC
--   run_start_deployed_fraction   0.55 claude_cold_start   2026-08-13 04:09 UTC
--
-- Every one of the three equals its own caller fallback exactly, and every one
-- sits inside the bounds this file imposes -- so they are belt-and-braces rows
-- that change nothing, and cataloguing moves no value in force. P0 asserts that
-- rather than assuming it, and A3 re-reads all three afterwards with a
-- deliberately impossible caller default (-1) so the read can only be satisfied
-- by the stored row and not by a fallback that happens to agree.
--
-- forces_recert = FALSE. Catalog inserts only; ottoq_policy_get never reads
-- the catalog (P3). Probe writes go to a scratch run inside a block that
-- raises on success, so the savepoint discards them (A4 checks).
--
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   ottoq_policy_param_catalog rows              133 -> 141
--   ottoq_policy_catalog_gap, read_uncatalogued   27 ->  19
--   values in force                            unchanged (A3)
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0298 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0298 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0298 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0298 P-: nothing in flight';
END $inflight$;

-- P0. EIGHT UNCATALOGUED, AND EVERY LIVE ROW ALREADY SITS INSIDE THE BOUND
-- THIS FILE IMPOSES. A catalog that orphans a value already in force would be
-- a silent behaviour change dressed as documentation.
DO $p0$
DECLARE
  v_cat int; r record; v_n_live int := 0;
  v_keys text[] := ARRAY[
    'night_wave_start_hour','night_wave_end_hour',
    'overnight_recall_start_hour','overnight_recall_end_hour',
    'sensor_health_clean_pct','vehicle_fault_rate_per_tick',
    'vehicle_fault_immobilizing_share','run_start_deployed_fraction'];
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog
   WHERE param_key = ANY (v_keys);
  IF v_cat <> 0 THEN
    RAISE EXCEPTION '0298 P0: % of the eight are already catalogued', v_cat;
  END IF;

  FOR r IN
    SELECT pp.param_key, pp.scope_type, pp.param_value
      FROM public.ottoq_policy_params pp
     WHERE pp.param_key = ANY (v_keys)
  LOOP
    v_n_live := v_n_live + 1;
    IF r.param_key IN ('night_wave_start_hour','night_wave_end_hour',
                       'overnight_recall_start_hour','overnight_recall_end_hour')
       AND (r.param_value < 0 OR r.param_value > 23) THEN
      RAISE EXCEPTION '0298 P0: % holds % in force, outside the 0..23 this file '
                      'would impose. Cataloguing it would silently move it.',
                      r.param_key, r.param_value;
    END IF;
    IF r.param_key = 'sensor_health_clean_pct'
       AND (r.param_value < 0 OR r.param_value > 100) THEN
      RAISE EXCEPTION '0298 P0: sensor_health_clean_pct holds % in force, outside 0..100',
                      r.param_value;
    END IF;
    IF r.param_key IN ('vehicle_fault_rate_per_tick','vehicle_fault_immobilizing_share',
                       'run_start_deployed_fraction')
       AND (r.param_value < 0 OR r.param_value > 1) THEN
      RAISE EXCEPTION '0298 P0: % holds % in force, outside 0..1', r.param_key, r.param_value;
    END IF;
  END LOOP;

  IF v_n_live <> 3 THEN
    RAISE EXCEPTION '0298 P0: % live rows for these eight, expected exactly 3 '
                    '(the two night_wave globals and run_start_deployed_fraction). '
                    'The header reasons about those three by name; a different set '
                    'means re-reading before cataloguing.', v_n_live;
  END IF;
  RAISE NOTICE '0298 P0: eight uncatalogued, three live rows, all already in range';
END $p0$;

-- P1. EVERY DERIVATION PINNED TO ITS SOURCE. Six fragments, each of which is
-- the actual reason a bound in this file is what it is.
DO $p1$
DECLARE r record; v_hits int; v_n int := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- the hour domain, at both consumers
      ('public','ottoq_recall_naive_threshold_v1','hour domain (night waves)',
       'v_hour    := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE ''America/Chicago'')::int;'),
      ('twin','ottoq_sim_auto_dispatch_tick','hour domain (overnight recall)',
       'v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE ''America/Chicago'')::int;'),
      -- the wrap the night-wave pair is cut on
      ('public','ottoq_recall_naive_threshold_v1','wrap window',
       'ELSE v_hour >= v_wave_start OR  v_hour < v_wave_end END;'),
      ('public','ottoq_recall_naive_threshold_v1','wrap modulus 24',
       'ELSE v_hour + 24 - v_wave_start END;'),
      -- the percentage scale
      ('ottoq','ottoq_observe_asset','health floor comparison',
       'COALESCE(v_p.sensor_health_pct, 100) < v_sensor_health_floor'),
      -- the count clamp behind run_start_deployed_fraction
      ('twin','ottoq_sim_prime_deployment','deployed-count clamp',
       'v_limit := GREATEST(0, LEAST(v_total, CEIL(v_total * COALESCE(p_fraction, 0.92))::int));')
    ) AS t(nsp, fn, what, frag)
  LOOP
    SELECT count(*) INTO v_hits
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = r.nsp AND p.proname = r.fn
       AND position(r.frag in p.prosrc) > 0;
    IF v_hits <> 1 THEN
      RAISE EXCEPTION '0298 P1: %.% no longer contains the % this file read a '
                      'bound off (found %)', r.nsp, r.fn, r.what, v_hits;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 6 THEN
    RAISE EXCEPTION '0298 P1: pinned % derivation sites, expected 6', v_n;
  END IF;
  RAISE NOTICE '0298 P1: all six derivation sites still say what this file copied';
END $p1$;

-- P2. THE SETTER REFUSES ALL EIGHT RIGHT NOW.
DO $p2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029800cc'::uuid;
  r record; v_r jsonb; v_refused int := 0;
BEGIN
  FOR r IN SELECT unnest(ARRAY[
      'night_wave_start_hour','night_wave_end_hour',
      'overnight_recall_start_hour','overnight_recall_end_hour',
      'sensor_health_clean_pct','vehicle_fault_rate_per_tick',
      'vehicle_fault_immobilizing_share','run_start_deployed_fraction']) AS k
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, r.k, 1, '0298_probe');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
      RAISE EXCEPTION '0298 P2: the setter did NOT refuse % -- it answered %', r.k, v_r;
    END IF;
    v_refused := v_refused + 1;
  END LOOP;
  IF v_refused <> 8 THEN
    RAISE EXCEPTION '0298 P2: only % refusals, expected 8', v_refused;
  END IF;
  RAISE NOTICE '0298 P2: ottoq_policy_set refuses all eight (unknown_param)';
END $p2$;

-- P3. forces_recert=false, executed.
DO $p3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0298 P3: ottoq_policy_get reads the catalog; not forces_recert=false';
  END IF;
  RAISE NOTICE '0298 P3: the read path still ignores the catalog';
END $p3$;

-- P4. THE DRAW IS STILL [0,1). Two of the eight get their ceiling from this
-- one line and nothing else; if the normalisation changes, they are wrong.
DO $p4$
DECLARE v_n int; v_sample numeric;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_seeded_random'
     AND position('RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;' in p.prosrc) > 0;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0298 P4: twin.ottoq_sim_seeded_random no longer normalises to '
                    '[0,1) the way this file read it (found %)', v_n;
  END IF;
  -- and exercise it, so the pin is not merely textual
  SELECT twin.ottoq_sim_seeded_random(4242, '0298_range_probe') INTO v_sample;
  IF v_sample IS NULL OR v_sample < 0 OR v_sample >= 1 THEN
    RAISE EXCEPTION '0298 P4: the draw returned %, outside [0,1)', v_sample;
  END IF;
  RAISE NOTICE '0298 P4: the seeded draw is [0,1) by source and by sample (%)', v_sample;
END $p4$;

-- P5. G64 IS STILL TRUE. Both halves of the split this file documents must be
-- present, or the caveat written into overnight_recall_end_hour's description
-- is stale on the day it ships.
DO $p5$
DECLARE v_gate int; v_planner int;
BEGIN
  SELECT count(*) INTO v_gate
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_auto_dispatch_tick'
     AND position('IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN' in p.prosrc) > 0;
  SELECT count(*) INTO v_planner
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick'
     AND position('AND ((p_hour >= p_win_end AND p_hour < p_win_start)' in p.prosrc) > 0;
  IF v_gate <> 1 THEN
    RAISE EXCEPTION '0298 P5: the twin''s recall gate no longer closes on the literal 6 '
                    '(found %). G64 may be fixed -- if so, rewrite '
                    'overnight_recall_end_hour''s description before cataloguing it.', v_gate;
  END IF;
  IF v_planner <> 1 THEN
    RAISE EXCEPTION '0298 P5: ottoq.ottoq_plan_dispatch_tick no longer gates the holdout '
                    'on p_win_end (found %); the caveat describes something else now', v_planner;
  END IF;
  RAISE NOTICE '0298 P5: G64 intact -- gate closes on the literal 6, planner gates on p_win_end';
END $p5$;

-- ===========================================================================
-- THE CHANGE
-- ===========================================================================

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('night_wave_start_hour',
   '0298: local hour (America/Chicago) at which the overnight recall wave opens '
   'in public.ottoq_recall_naive_threshold_v1. 0..23 READ OFF the consumer: it '
   'compares against EXTRACT(HOUR ...)::int, and its own wrap arithmetic uses 24 '
   'as the modulus (v_hour + 24 - v_wave_start). Live GLOBAL row = 23, written '
   '2026-08-13 by claude_night_waves before this key was catalogued.',
   23, 0, 23, 'public.ottoq_recall_naive_threshold_v1'),

  ('night_wave_end_hour',
   '0298: local hour at which the overnight recall wave closes. Same 0..23 '
   'derivation as night_wave_start_hour; the window CASE handles the midnight '
   'wrap explicitly, and end=0 and end=24 select the same window, so the ceiling '
   'costs nothing. Live GLOBAL row = 6.',
   6, 0, 23, 'public.ottoq_recall_naive_threshold_v1'),

  ('overnight_recall_start_hour',
   '0298: local hour at which twin.ottoq_sim_auto_dispatch_tick opens the '
   'overnight surplus recall window. 0..23 read off EXTRACT(HOUR FROM '
   'p_sim_clock_now AT TIME ZONE ''America/Chicago'')::int. Also passed on to '
   'ottoq.ottoq_plan_dispatch_tick as p_win_start.',
   22, 0, 23, 'twin.ottoq_sim_auto_dispatch_tick; ottoq.ottoq_plan_dispatch_tick'),

  ('overnight_recall_end_hour',
   '0298 / G64 -- HALF WIRED, and the name oversells it. This does NOT close the '
   'recall window. The twin''s gate is IF v_recall_on AND (v_hour >= v_win_start '
   'OR v_hour < 6) -- a LITERAL 6, not this dial. What this dial actually sets is '
   'where the PER-VEHICLE OVERNIGHT HOLDOUT stops applying: it is passed on as '
   'p_win_end and ottoq.ottoq_plan_dispatch_tick treats p_hour >= p_win_end as '
   '"outside the overnight window", which makes every vehicle eligible and skips '
   'the holdout check. At the default 3 the two disagree between 03:00 and 05:59 '
   'local: window open, holdout bypassed, and the event payload''s holdout_active '
   'reports false. Fixing the gate is forces_recert=TRUE and needs a cert window. '
   '0..23 read off the same EXTRACT(HOUR ...) domain.',
   3, 0, 23, 'twin.ottoq_sim_auto_dispatch_tick; ottoq.ottoq_plan_dispatch_tick'),

  ('sensor_health_clean_pct',
   '0298: the sensor-health percentage BELOW which ottoq.ottoq_observe_asset '
   'declares a sensor clean needed. 0..100 read off the consumer''s own '
   'COALESCE(v_p.sensor_health_pct, 100) -- a missing reading is treated as a '
   'perfect 100, which is the scale declaring its own top. Corroborated, not '
   'proven, by 120 live vehicle_need_profile rows spanning 88.1 to 99.7.',
   90, 0, 100, 'ottoq.ottoq_observe_asset'),

  ('vehicle_fault_rate_per_tick',
   '0298: per-vehicle probability of a new fault on one tick. 0..1 is the range '
   'of the thing it is compared against -- twin.ottoq_sim_seeded_random, which '
   'returns (hash mod 1000000)/1000000.0, i.e. [0,1). 0 = faults never fire; 1 = '
   'every vehicle faults every tick.',
   0.004, 0, 1, 'twin.ottoq_sim_vehicle_exception_handler'),

  ('vehicle_fault_immobilizing_share',
   '0298: share of CRITICAL faults that immobilize the vehicle -- a TUNABLE '
   'ASSUMPTION standing in for the OEM fault code''s drivable bit, as the '
   'consumer''s own comment says. 0..1 from the same [0,1) draw. Corroborated by '
   'vehicle_fault_service_incompatible_share, already catalogued 0..1, which this '
   'dial CEILS: v_si_share := LEAST(<that>, v_immob_share).',
   0.35, 0, 1, 'twin.ottoq_sim_vehicle_exception_handler'),

  ('run_start_deployed_fraction',
   '0298: fraction of the fleet twin.ottoq_sim_start_run primes as deployed when '
   'a run begins with nothing deployed. 0..1 derived from the arithmetic rather '
   'than a comparison: twin.ottoq_sim_prime_deployment computes GREATEST(0, '
   'LEAST(v_total, CEIL(v_total * fraction))), so 2 produces exactly what 1 does '
   'and -1 exactly what 0 does. NOTE: that callee''s own fallback is 0.92 while '
   'the caller passes 0.55; the caller never passes NULL so the 0.92 is '
   'unreachable, but one quantity has two disagreeing defaults. A live GLOBAL '
   'row also holds 0.55, written 2026-08-13 by claude_cold_start before this '
   'key was catalogued -- equal to the caller value, so it changes nothing.',
   0.55, 0, 1, 'twin.ottoq_sim_start_run; twin.ottoq_sim_prime_deployment');

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. The counts this file predicted before it ran.
DO $a1$
DECLARE v_rows int; v_cat int; v_gap int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_param_catalog
   WHERE description LIKE '0298%';
  IF v_rows <> 8 THEN
    RAISE EXCEPTION 'A1 FAILED: % rows tagged 0298, expected 8', v_rows;
  END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 141 THEN
    RAISE EXCEPTION 'A1 FAILED: catalog holds % rows, predicted 141', v_cat;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 19 THEN
    RAISE EXCEPTION 'A1 FAILED: gap is %, predicted 19', v_gap;
  END IF;
  RAISE NOTICE 'A1 OK: catalog 133 -> 141, gap 27 -> 19';
END $a1$;

-- A2. EVERY BOUND FIRES AT ITS OWN NUMBER, both ends. All eight have a
-- ceiling, so unlike 0297 there is no open-ceiling branch to take.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029800cc'::uuid;
  v_r jsonb; r record; v_n int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.param_key, c.min_value, c.max_value
        FROM public.ottoq_policy_param_catalog c
       WHERE c.description LIKE '0298%'
       ORDER BY c.param_key
    LOOP
      IF r.max_value IS NULL THEN
        RAISE EXCEPTION 'A2 FAILED: % has no ceiling; every dial in 0298 should '
                        'have one and the header says so', r.param_key;
      END IF;
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key,
                                     r.min_value - 1, '0298_proof');
      IF COALESCE((v_r->>'applied')::numeric, -999) <> r.min_value
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: % below its floor must clamp to % and say so: %',
                        r.param_key, r.min_value, v_r;
      END IF;
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key,
                                     r.max_value + 1, '0298_proof');
      IF COALESCE((v_r->>'applied')::numeric, -1) <> r.max_value
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: % above its ceiling must clamp to % and say so: %',
                        r.param_key, r.max_value, v_r;
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n <> 8 THEN
      RAISE EXCEPTION 'A2 FAILED: tested % dials, the file inserted 8', v_n;
    END IF;
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: all eight clamp at both ends; scratch writes discarded';
END $a2$;

-- A3. NOTHING IN FORCE MOVED. All three live globals must still resolve to the
-- values they held before this file ran. The caller default passed here is -1,
-- a value none of the three can legitimately hold, so a read that returns 23, 6
-- or 0.55 can only have come from the stored row -- not from a fallback that
-- happens to agree with it, which is exactly what would hide a lost row.
DO $a3$
DECLARE v_start numeric; v_end numeric; v_frac numeric;
BEGIN
  v_start := public.ottoq_policy_get(NULL, 'night_wave_start_hour',       -1);
  v_end   := public.ottoq_policy_get(NULL, 'night_wave_end_hour',         -1);
  v_frac  := public.ottoq_policy_get(NULL, 'run_start_deployed_fraction', -1);
  IF v_start IS DISTINCT FROM 23 OR v_end IS DISTINCT FROM 6 THEN
    RAISE EXCEPTION 'A3 FAILED: the night-wave window in force is %..%, was 23..6. '
                    'Cataloguing a key must not move a value already in force.',
                    v_start, v_end;
  END IF;
  IF v_frac IS DISTINCT FROM 0.55 THEN
    RAISE EXCEPTION 'A3 FAILED: run_start_deployed_fraction in force is %, was 0.55', v_frac;
  END IF;
  RAISE NOTICE 'A3 OK: all three live globals still read 23 / 6 / 0.55 from their stored rows';
END $a3$;

-- A4. NO RESIDUE.
DO $a4$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000029800cc'::uuid
      OR updated_by IN ('0298_probe','0298_proof');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % probe row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: no probe rows survived';
END $a4$;
