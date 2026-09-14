-- migration-version: PENDING
-- migration-name:    0283_five_floors_the_engine_already_writes_down_and_two_ceilings_it_does_not
--
-- 0283  SEVEN MORE DIALS, AND THE FIRST HONEST NULLS
--
-- ---------------------------------------------------------------------------
-- CONTINUING 0282 UNDER THE SAME RULE
--
--   READ THE RANGE OFF THE CONSUMER. NEVER CHOOSE IT.
--
-- 0282 catalogued the two keys whose ranges the database itself declares.
-- These seven are the next tier, and they force the rule's hard case: FIVE of
-- them have a floor written literally into the consumer, and only TWO have any
-- ceiling anywhere in the engine.
--
-- The temptation is obvious -- put 1440 on a minutes dial, 10 on an attempts
-- dial, and the catalog looks complete. That is exactly the guess this whole
-- task exists to refuse. A max_value is an ASSERTION ABOUT THE ENGINE, and
-- min_value/max_value are nullable for a reason:
--
--   ottoq_policy_set computes  GREATEST(v_min, LEAST(v_max, p_param_value))
--
-- and LEAST/GREATEST ignore NULL operands in Postgres, so a NULL bound is not
-- a broken clamp -- it is NO clamp on that side, which is the truthful state
-- when no consumer declares one. A3 proves that rather than assuming it.
--
-- AND THE CATALOG ROW IS WORTH HAVING EVEN WITH ONE BOUND NULL, because the
-- clamp was never the main point. The main point is that ottoq_policy_set
-- answers {"ok":false,"error":"unknown_param"} for an uncatalogued key WITHOUT
-- raising, so the only way to set the dial is a hand-written row with no
-- receipt and no validation at all. A row with a floor and a NULL ceiling
-- converts that into a supported write. Half a clamp and a real receipt beats
-- no clamp and no receipt.
--
-- ---------------------------------------------------------------------------
-- THE SEVEN, AND WHERE EACH BOUND IS READ FROM
--
-- 1-2. depot_night_start_hour (20) and depot_night_end_hour (6)   [0, 23]
--      One window, one consumer. public.ottoq_is_depot_night:
--        WITH h AS (SELECT EXTRACT(HOUR FROM p_at AT TIME ZONE 'America/Chicago') AS hr)
--        ... CASE WHEN w.s <= w.e THEN h.hr >= w.s AND h.hr < w.e
--                                 ELSE h.hr >= w.s OR  h.hr < w.e END
--      Both dials are compared against EXTRACT(HOUR ...), whose range is 0..23
--      by definition. Outside it the CASE is constant. Catalogued together
--      because they are one window -- a start without an end is half a dial.
--      (ottoq_charge_plan_for_visit reads the start hour too, as ::int.)
--
-- 3.   overnight_holdout_pct (1)                                  [1, 100]
--      BOTH bounds are in one line of ottoq_is_overnight_holdout:
--        (abs(hashtextextended(...)) % 100) < GREATEST(1, COALESCE(p_pct,1))
--      The left side is 0..99, so 100 already selects every vehicle and
--      anything larger is identical; and the consumer floors the dial at 1
--      itself, so 0 and -5 are already 1 today. This one is fully derived.
--      It is also a genuine percent despite the default of 1 -- 1%, not 100%.
--
-- 4.   return_eta_minutes (30)                              min 1, max NULL
--      public.ottoq_return_eta_minutes IS the accessor, and it says:
--        SELECT GREATEST(1, COALESCE(ottoq_policy_get(..., 'return_eta_minutes', 30), 30));
--      The floor is the consumer's own word. No reader anywhere bounds it
--      above -- twin.ottoq_sim_advance_deployed_telemetry just adds it as an
--      interval, ottoq_reoptimize_reservation_book does GREATEST(600, eta*60+1200).
--      So max_value stays NULL.
--
-- 5-6. service_bay_default_min (45), wash_bay_default_min (25)  min 1, max NULL
--      Both readers floor the resulting interval at one minute, independently:
--        ottoq_decide_tick (both sites):
--          v_bay_until := v_clock + GREATEST(COALESCE(v_bay_dur,
--                            make_interval(mins => <dial>::int)), interval '1 minute');
--        ottoq.ottoq_bind_unbooked_bay_occupants:
--          v_until := GREATEST(COALESCE(..., p_clock + make_interval(mins => <dial>::int)),
--                              p_clock + interval '1 minute');
--      So a value at or below 1 already behaves as 1 -- min 1 is measured, not
--      preferred. Nothing caps a bay duration above, so max_value stays NULL.
--      (Both sites cast ::int, so a fractional value is rounded by the cast,
--      not by the clamp. Noted, not fixed here.)
--
-- 7.   visit_readmit_max_attempts (3)                       min 0, max NULL
--      Both readers write the floor themselves:
--        ottoq.ottoq_readmit_reopened_needs:
--          v_max := GREATEST(COALESCE(ottoq_policy_get(...,3),3)::int, 0);
--        ottoq.ottoq_readmit_resumed_visits:  the same GREATEST(..., 0)
--      min 0 is read off that, and 0 is meaningful (readmit nothing). No
--      reader caps the attempt count, so max_value stays NULL.
--
-- ---------------------------------------------------------------------------
-- ENGINE IMPACT: NONE, for the same reason as 0282
--
-- ottoq_policy_get resolves run -> depot -> global -> caller default and never
-- reads ottoq_policy_param_catalog (P0 asserts it). A catalog row is consumed
-- by ottoq_policy_set alone, which no certification arm calls. The two live
-- rows (depot_night_start_hour=20, depot_night_end_hour=6, both global) are
-- untouched and asserted in range before anything is declared.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0283 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0283 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0283 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0283 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. PREMISE + THE forces_recert=false ARGUMENT -----------------------------
DO $p0$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('depot_night_start_hour','depot_night_end_hour','overnight_holdout_pct',
                       'return_eta_minutes','service_bay_default_min','wash_bay_default_min',
                       'visit_readmit_max_attempts');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0283 P0: % of the seven keys are already catalogued', v_n;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0283 P0: ottoq_policy_get does not exist';
  END IF;
  IF position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0283 P0: ottoq_policy_get now READS the catalog -- adding rows '
                    'is an engine change and this file must be re-classified';
  END IF;
  RAISE NOTICE '0283 P0: seven keys uncatalogued; the read path still ignores the catalog';
END $p0$;

-- P1. THE NIGHT WINDOW IS STILL COMPARED AGAINST AN HOUR-OF-DAY --------------
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_is_depot_night';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0283 P1: ottoq_is_depot_night does not exist';
  END IF;
  IF position('EXTRACT(HOUR FROM p_at AT TIME ZONE' in v_src) = 0 THEN
    RAISE EXCEPTION '0283 P1: the window is no longer compared against an '
                    'EXTRACT(HOUR ...); [0,23] is derived from that and must be re-read';
  END IF;
  IF position('''depot_night_start_hour''' in v_src) = 0
     OR position('''depot_night_end_hour''' in v_src) = 0 THEN
    RAISE EXCEPTION '0283 P1: ottoq_is_depot_night no longer reads both ends of '
                    'the window; they are catalogued here as one dial pair';
  END IF;
  RAISE NOTICE '0283 P1: both night-window dials are compared against hour-of-day (0..23)';
END $p1$;

-- P2. THE HOLDOUT DRAW IS STILL mod 100 WITH A FLOOR OF 1 --------------------
-- Both bounds live in this one expression. If either moves, both bounds move.
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname = 'ottoq_is_overnight_holdout';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0283 P2: ottoq_is_overnight_holdout does not exist';
  END IF;
  IF position('% 100)' in v_src) = 0 THEN
    RAISE EXCEPTION '0283 P2: the holdout draw is no longer taken mod 100; '
                    'max_value 100 is derived from that modulus';
  END IF;
  IF position('GREATEST(1, COALESCE(p_pct,1))' in v_src) = 0 THEN
    RAISE EXCEPTION '0283 P2: the holdout percentage no longer floors at 1; '
                    'min_value 1 is derived from that floor';
  END IF;
  RAISE NOTICE '0283 P2: holdout draw is (hash %% 100) < GREATEST(1, pct) -- range [1,100]';
END $p2$;

-- P3. THE ETA ACCESSOR STILL DECLARES ITS OWN FLOOR OF 1 ---------------------
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_return_eta_minutes';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0283 P3: ottoq_return_eta_minutes does not exist';
  END IF;
  IF position('GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id, ''return_eta_minutes'', 30), 30))' in v_src) = 0 THEN
    RAISE EXCEPTION '0283 P3: the ETA accessor no longer floors at 1 minute; '
                    'min_value is derived from that floor';
  END IF;
  RAISE NOTICE '0283 P3: the ETA accessor floors at 1 minute and caps at nothing';
END $p3$;

-- P4. BOTH BAY-DURATION READERS STILL FLOOR AT ONE MINUTE --------------------
-- Two independent functions, three call sites, one floor. min_value 1 is what
-- the engine already does, not what this file would prefer.
DO $p4$
DECLARE v_dec text; v_bind text;
BEGIN
  SELECT p.prosrc INTO v_dec FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  SELECT p.prosrc INTO v_bind FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_bind_unbooked_bay_occupants';
  IF v_dec IS NULL OR v_bind IS NULL THEN
    RAISE EXCEPTION '0283 P4: a bay-duration reader is missing (decide_tick %, bind %)',
                    (v_dec IS NOT NULL), (v_bind IS NOT NULL);
  END IF;
  IF position('''wash_bay_default_min''' in v_dec) = 0
     OR position('''service_bay_default_min''' in v_dec) = 0 THEN
    RAISE EXCEPTION '0283 P4: ottoq_decide_tick no longer reads both bay dials';
  END IF;
  IF position('interval ''1 minute''' in v_dec) = 0 THEN
    RAISE EXCEPTION '0283 P4: ottoq_decide_tick no longer floors a bay window at '
                    'one minute; min_value is derived from that floor';
  END IF;
  IF position('p_clock + interval ''1 minute''' in v_bind) = 0 THEN
    RAISE EXCEPTION '0283 P4: ottoq_bind_unbooked_bay_occupants no longer floors at '
                    'one minute; min_value is derived from that floor';
  END IF;
  RAISE NOTICE '0283 P4: both bay-duration readers floor the window at one minute';
END $p4$;

-- P5. BOTH READMIT READERS STILL FLOOR THE ATTEMPT COUNT AT ZERO -------------
DO $p5$
DECLARE v_a text; v_b text;
BEGIN
  SELECT p.prosrc INTO v_a FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_readmit_reopened_needs';
  SELECT p.prosrc INTO v_b FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_readmit_resumed_visits';
  IF v_a IS NULL OR v_b IS NULL THEN
    RAISE EXCEPTION '0283 P5: a readmit reader is missing';
  END IF;
  IF position('''visit_readmit_max_attempts'',3),3)::int, 0)' in v_a) = 0 THEN
    RAISE EXCEPTION '0283 P5: ottoq_readmit_reopened_needs no longer floors the '
                    'attempt count at 0; min_value is derived from that floor';
  END IF;
  IF position('''visit_readmit_max_attempts'',3)::int, 3), 0)' in v_b) = 0 THEN
    RAISE EXCEPTION '0283 P5: ottoq_readmit_resumed_visits no longer floors the '
                    'attempt count at 0; min_value is derived from that floor';
  END IF;
  RAISE NOTICE '0283 P5: both readmit readers floor the attempt count at zero';
END $p5$;

-- P6. THE LIVE ROWS ARE INSIDE THE RANGES THIS FILE DECLARES -----------------
DO $p6$
DECLARE v_n int; v_bad int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('depot_night_start_hour','depot_night_end_hour','overnight_holdout_pct',
                       'return_eta_minutes','service_bay_default_min','wash_bay_default_min',
                       'visit_readmit_max_attempts');
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0283 P6: expected the 2 measured live rows across the seven '
                    'keys, found % -- somebody wrote these dials since the measurement', v_n;
  END IF;
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE param_key IN ('depot_night_start_hour','depot_night_end_hour')
     AND (param_value < 0 OR param_value > 23);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0283 P6: % night-window row(s) are outside [0,23]', v_bad;
  END IF;
  RAISE NOTICE '0283 P6: 2 live rows (the night window, global scope), both in [0,23]';
END $p6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('depot_night_start_hour',
 '0283: hour of the depot-local day (America/Chicago, named in one place inside public.ottoq_is_depot_night) at which the depot night window OPENS. Paired with depot_night_end_hour; the consumer handles a wrapping window (20 -> 6) and a non-wrapping one (1 -> 5) with the same CASE. THE RANGE IS NOT CHOSEN: both ends are compared against EXTRACT(HOUR FROM p_at AT TIME ZONE ...), whose values are 0..23, so outside [0,23] the predicate is constant. Also read by public.ottoq_charge_plan_for_visit as ::int. 0283 P1 pins the comparison.',
 20, 0, 23,
 'public.ottoq_is_depot_night, public.ottoq_charge_plan_for_visit'),
('depot_night_end_hour',
 '0283: hour of the depot-local day at which the depot night window CLOSES; the other half of depot_night_start_hour and catalogued with it, because a start without an end is half a dial. Same derivation: compared against EXTRACT(HOUR ...) inside public.ottoq_is_depot_night, so the range is [0,23] and not a preference. 0283 P1 pins it.',
 6, 0, 23,
 'public.ottoq_is_depot_night'),
('overnight_holdout_pct',
 '0283: percent of the fleet held back overnight rather than recalled -- a vehicle is in the holdout set when (abs(hashtextextended(vehicle:seed:local-date)) % 100) < this dial, so the selection is seeded and stable within a night (0052 keyed it on random_seed, never sim_run_id). BOTH BOUNDS ARE READ OFF THAT ONE LINE in ottoq_is_overnight_holdout: the left side is 0..99 so 100 already holds back everything and larger values are identical, and the consumer itself writes GREATEST(1, COALESCE(p_pct,1)) so 0 and negatives are already 1 today. It is a true percent despite the default of 1 -- that is one percent. 0283 P2 pins both.',
 1, 1, 100,
 'public.ottoq_recall_naive_threshold_v1, twin.ottoq_sim_auto_dispatch_tick, public.ottoq_is_overnight_holdout'),
('return_eta_minutes',
 '0283: minutes a deployed vehicle takes to reach the depot once it is returning; the twin stamps it onto the dispatch with eta_source = policy_constant:return_eta_minutes. min_value 1 IS THE CONSUMER''S OWN WORD -- public.ottoq_return_eta_minutes is literally GREATEST(1, COALESCE(ottoq_policy_get(..., 30), 30)). MAX_VALUE IS DELIBERATELY NULL: no reader bounds it above (the twin adds it as an interval; ottoq_reoptimize_reservation_book only does GREATEST(600, eta*60+1200)), so a ceiling here would be an invented one. A NULL bound is no clamp on that side, not a broken clamp -- ottoq_policy_set computes GREATEST(min, LEAST(max, v)) and LEAST/GREATEST ignore NULLs. 0283 P3 pins the floor, A3 proves the NULL ceiling.',
 30, 1, NULL,
 'public.ottoq_return_eta_minutes, twin.ottoq_sim_prime_deployment, twin.ottoq_sim_advance_deployed_telemetry'),
('service_bay_default_min',
 '0283: fallback duration in minutes for a service-bay occupancy when the twin has not supplied one. min_value 1 is measured, not preferred: BOTH readers already floor the resulting window at one minute -- ottoq_decide_tick does v_bay_until := v_clock + GREATEST(COALESCE(v_bay_dur, make_interval(mins => <dial>)), interval ''1 minute''), and ottoq.ottoq_bind_unbooked_bay_occupants floors at p_clock + interval ''1 minute'' -- so a value at or below 1 already behaves as 1. MAX_VALUE NULL: nothing caps a bay window above. Note both sites cast ::int, so a fractional value is rounded by the cast rather than by the clamp. 0283 P4 pins both floors.',
 45, 1, NULL,
 'public.ottoq_decide_tick, ottoq.ottoq_bind_unbooked_bay_occupants'),
('wash_bay_default_min',
 '0283: fallback duration in minutes for a wash- or detail-bay occupancy when the twin has not supplied one (the two share the wash lane; the purpose label is chosen from bay_kind, not from this dial). Same derivation as service_bay_default_min: both readers floor the window at one minute, so min_value 1 is what the engine already does; nothing caps it above, so max_value stays NULL. 0283 P4 pins both floors.',
 25, 1, NULL,
 'public.ottoq_decide_tick, ottoq.ottoq_bind_unbooked_bay_occupants'),
('visit_readmit_max_attempts',
 '0283: how many times a reopened need or a resumed visit may be readmitted before it is left alone. min_value 0 IS THE CONSUMERS'' OWN WORD -- ottoq.ottoq_readmit_reopened_needs and ottoq.ottoq_readmit_resumed_visits both wrap the read in GREATEST(..., 0), and 0 is meaningful: readmit nothing. MAX_VALUE NULL: neither reader caps the attempt count, so a ceiling would be invented. 0283 P5 pins both floors.',
 3, 0, NULL,
 'ottoq.ottoq_readmit_reopened_needs, ottoq.ottoq_readmit_resumed_visits');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER ACCEPTS ALL SEVEN KEYS IT HAS ALWAYS REFUSED.
DO $a1$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000028300aa'::uuid;
  v_r jsonb; k text; v numeric;
  v_probe CONSTANT jsonb := jsonb_build_object(
    'depot_night_start_hour', 21, 'depot_night_end_hour', 5,
    'overnight_holdout_pct', 7, 'return_eta_minutes', 35,
    'service_bay_default_min', 50, 'wash_bay_default_min', 30,
    'visit_readmit_max_attempts', 2);
BEGIN
  FOR k, v IN SELECT key, value::text::numeric FROM jsonb_each(v_probe) LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0283_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'A1 FAILED: the setter still refuses %: %', k, v_r;
    END IF;
    IF public.ottoq_policy_get(v_scratch, k, -1) <> v THEN
      RAISE EXCEPTION 'A1 FAILED: % did not read back as %', k, v;
    END IF;
  END LOOP;
  RAISE NOTICE 'A1 OK: all seven keys write through the setter and read back';
END $a1$;

-- A2. THE BOUNDED DIALS CLAMP ON BOTH SIDES, AND THE RECEIPT SAYS SO.
DO $a2$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028300aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'depot_night_start_hour', 25, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 23
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: hour 25 should clamp to 23 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'depot_night_end_hour', -3, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: hour -3 should clamp to 0 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'overnight_holdout_pct', 500, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 100
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: holdout 500 should clamp to 100 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'overnight_holdout_pct', 0, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: holdout 0 should clamp to 1 and report it: %', v_r;
  END IF;
  RAISE NOTICE 'A2 OK: the three bounded dials clamp on both sides, every clamp reported';
END $a2$;

-- A3. A NULL CEILING IS NO CEILING -- NOT A CEILING OF ZERO.
-- This is the assertion the four half-bounded rows rest on. If LEAST(NULL, v)
-- did not behave this way, those rows would silently pin every write to their
-- floor, which is a far worse defect than the one being fixed.
DO $a3$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028300aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'return_eta_minutes', 100000, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 100000
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: a NULL max_value must impose no ceiling, but '
                    '100000 came back as %', v_r;
  END IF;
  IF (v_r->'safe_range'->>1) IS NOT NULL THEN
    RAISE EXCEPTION 'A3 FAILED: the receipt should report an open upper bound: %', v_r;
  END IF;
  -- and the floor on the same key still fires
  v_r := public.ottoq_policy_set('run', v_scratch, 'return_eta_minutes', 0, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 1
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A3 FAILED: the floor of 1 did not fire on 0: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'visit_readmit_max_attempts', -5, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A3 FAILED: the attempts floor of 0 did not fire on -5: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'wash_bay_default_min', 9999, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 9999
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: a NULL max_value clamped a bay duration: %', v_r;
  END IF;
  RAISE NOTICE 'A3 OK: NULL ceilings impose nothing, and every declared floor still fires';
END $a3$;

-- A4. THE TWO VALUES THE DEPOT ACTUALLY RUNS PASS THROUGH UNCHANGED.
DO $a4$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028300aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'depot_night_start_hour', 20, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 20
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A4 FAILED: the live night-start 20 was altered: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'depot_night_end_hour', 6, '0283_proof');
  IF COALESCE((v_r->>'applied')::numeric,-1) <> 6
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A4 FAILED: the live night-end 6 was altered: %', v_r;
  END IF;
  RAISE NOTICE 'A4 OK: the live night window (20 -> 6) passes through unchanged';
END $a4$;

-- A5. THE SCRATCH IS GONE AND THE TWO LIVE ROWS SURVIVE UNTOUCHED.
DO $a5$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0283_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 7 THEN
    RAISE EXCEPTION 'A5 FAILED: expected to remove exactly 7 scratch rows, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('depot_night_start_hour','depot_night_end_hour','overnight_holdout_pct',
                       'return_eta_minutes','service_bay_default_min','wash_bay_default_min',
                       'visit_readmit_max_attempts');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'A5 FAILED: % rows remain across the seven keys, expected the original 2', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE (param_key = 'depot_night_start_hour' AND param_value = 20 AND scope_type = 'global')
      OR (param_key = 'depot_night_end_hour'   AND param_value =  6 AND scope_type = 'global');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'A5 FAILED: the live night window is no longer 20 -> 6 at global scope';
  END IF;
  RAISE NOTICE 'A5 OK: scratch removed, the original 2 rows survive at their measured values';
END $a5$;

-- A6. THE 0281 INSTRUMENT AGREES THE GAP SHRANK BY SEVEN.
DO $a6$
DECLARE v_ok int; v_still int;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok'), count(*) FILTER (WHERE status <> 'ok')
    INTO v_ok, v_still
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('depot_night_start_hour','depot_night_end_hour','overnight_holdout_pct',
                       'return_eta_minutes','service_bay_default_min','wash_bay_default_min',
                       'visit_readmit_max_attempts');
  IF v_still > 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % of the seven still report a gap', v_still;
  END IF;
  IF v_ok <> 7 THEN
    RAISE EXCEPTION 'A6 FAILED: expected all seven to report ok, found %', v_ok;
  END IF;
  RAISE NOTICE 'A6 OK: all seven now report ok in ottoq_policy_catalog_gap';
END $a6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0283_five_floors_the_engine_already_writes_down_and_two_ceilings_it_does_not', false,
 'Seven rows in ottoq_policy_param_catalog: depot_night_start_hour [0,23]/20 and depot_night_end_hour [0,23]/6 (compared against EXTRACT(HOUR ...) in ottoq_is_depot_night), overnight_holdout_pct [1,100]/1 (both bounds in one line of ottoq_is_overnight_holdout: (hash % 100) < GREATEST(1, pct)), and four half-bounded dials whose floor the consumer writes down and whose ceiling nothing in the engine declares -- return_eta_minutes min 1 (GREATEST(1, ...) in its own accessor), service_bay_default_min and wash_bay_default_min min 1 (both readers floor the window at interval ''1 minute''), visit_readmit_max_attempts min 0 (GREATEST(..., 0) in both readers). Those four carry max_value NULL on purpose: ottoq_policy_set computes GREATEST(min, LEAST(max, v)) and LEAST/GREATEST ignore NULLs, so a NULL bound is no clamp on that side rather than a broken one, and A3 proves it two ways (a huge value passes unclamped with an open safe_range, every declared floor still fires). Inventing a ceiling would be the exact failure this task exists to avoid. P1-P5 pin each derivation; P6 checks the 2 live rows first. forces_recert=false, asserted in P0: ottoq_policy_get never reads the catalog, so these rows are consumed only by ottoq_policy_set, which no certification arm calls. The 2 live rows (the global night window, 20 -> 6) are untouched and re-asserted in A5.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
