-- migration-version: PENDING
-- migration-name:    0290_three_geometry_dials_and_one_the_catalog_cannot_express
--
-- 0290  THREE GEOMETRY DIALS, AND ONE THE CATALOG CANNOT EXPRESS
--
-- Sixth file under the 0282 rule. Four dials feed public.ottoq_site_geometry --
-- the site's plan-unit scale and the car body box. Three are catalogued here.
-- THE FOURTH IS DELIBERATELY LEFT OUT, and that omission is the most useful
-- thing in this file.
--
-- ---------------------------------------------------------------------------
-- WHAT THE CONSUMER DOES WITH EACH, AND WHAT EACH DOES WHEN PUSHED
--
-- Every line below was MEASURED by calling ottoq_site_geometry against a
-- scratch run with the dial written, inside a rolled-back transaction. None of
-- it is reasoned from the source alone.
--
--   dial                       at 0                    at -5
--   metres_per_plan_unit       RAISES division by zero every dimension negative
--   car_length_plan_units      length_m 0.0000         length_m -2.3925
--   car_width_plan_units       width_m 0.0000          width_m -2.3925
--   stall_pitch_perimeter_pu   gap_m -2.0097           gap_m -4.4022
--
-- mpu is the only DIVISOR: the function computes round(1.0 / a.mpu, 6) for
-- plan_units_per_metre and round(0.3048 / a.mpu, 6) for plan_units_per_foot.
-- The other three appear only in multiplications and in one subtraction.
--
-- ---------------------------------------------------------------------------
-- THE THREE THAT ARE CATALOGUED: min 0, max NULL
--
-- min 0 by INVERSION, the shape 0286 established for the soil dials -- a
-- negative does not merely make the value small, it reverses what the value
-- means:
--
--   car_length_plan_units   a negative gives a negative car length, so the
--                           collision body box is inside out.
--   car_width_plan_units    same, AND WORSE, and this is the one to notice:
--                           the function reports
--                             perimeter_body_gap_m = (pitch_pu - car_w_pu) * mpu
--                           so a NEGATIVE WIDTH INFLATES THE REPORTED CLEARANCE.
--                           Measured: width -5 pu reports a 5.1200 m perimeter
--                           gap where the default reports 0.7178 m. A consumer
--                           trusting that number would believe it had seven
--                           times the room it has.
--   stall_pitch_perimeter_pu a negative pitch is not a pitch. Note that 0 is
--                           already meaningful here -- it reports gap -2.0097,
--                           i.e. "the body is wider than the pitch" -- so 0 is
--                           the edge of meaning, not the edge of correctness,
--                           and it stays inside the range.
--
-- MAX NULL on all three: nothing in the consumer caps a dimension. A bigger car
-- is a bigger car. Writing any ceiling would be the 0285 trap -- inventing a
-- bound the engine never declared.
--
-- ---------------------------------------------------------------------------
-- AND THE ONE THAT IS NOT CATALOGUED: metres_per_plan_unit
--
-- The consumer DIVIDES by it, and 0 raises division_by_zero -- measured, not
-- inferred. So the value this dial must be protected from is exactly 0.
--
-- ottoq_policy_set clamps with GREATEST(min_value, LEAST(max_value, v)). That
-- bound is INCLUSIVE. There is no min_value that admits every positive number
-- and excludes zero:
--
--   min 0     admits 0, which crashes the consumer. Worse than no catalog row:
--             it would put the fatal value INSIDE the "safe range" the setter
--             advertises.
--   min 0.001 excludes 0, and is a number I made up. The whole rule of this
--             series is that a range is READ OFF the consumer, never chosen,
--             and the consumer declares no floor -- only that zero is fatal.
--
-- So the honest outcome is to leave it uncatalogued and say why, here and in
-- the gap instrument, rather than ship a range that is either unsafe or
-- invented. The catalog's vocabulary is missing an exclusive bound; at least
-- one dial needs one. Filed as G61.
--
-- THIS IS NOT A LOOPHOLE FOR SKIPPING HARD DIALS. It applies where the consumer
-- declares a bound the catalog cannot represent. Every other dial in the 56
-- still uncatalogued gets read off its consumer as before.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0290 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0290 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0290 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0290 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. PREMISE + THE forces_recert=false ARGUMENT -----------------------------
DO $p0$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('car_length_plan_units','car_width_plan_units',
                       'stall_pitch_perimeter_pu','metres_per_plan_unit');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0290 P0: % of the four geometry keys are already catalogued', v_n;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL OR position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0290 P0: ottoq_policy_get is missing or now reads the catalog';
  END IF;
  RAISE NOTICE '0290 P0: four geometry keys uncatalogued; the read path still ignores '
               'the catalog';
END $p0$;

-- P1. THE CONSUMER STILL DIVIDES BY mpu AND ONLY BY mpu ---------------------
-- This is the whole reason metres_per_plan_unit is excluded. If the division
-- ever goes away, that exclusion is stale and must be revisited.
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_site_geometry';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0290 P1: public.ottoq_site_geometry does not exist';
  END IF;
  IF position('round(1.0 / a.mpu, 6)' in v_src) = 0
     OR position('round(0.3048 / a.mpu, 6)' in v_src) = 0 THEN
    RAISE EXCEPTION '0290 P1: ottoq_site_geometry no longer divides by mpu. That '
                    'division is the entire reason metres_per_plan_unit is left out '
                    'of the catalog, so the omission must be re-argued';
  END IF;
  IF position('/ a.car_l_pu' in v_src) > 0
     OR position('/ a.car_w_pu' in v_src) > 0
     OR position('/ a.pitch_pu' in v_src) > 0 THEN
    RAISE EXCEPTION '0290 P1: one of the three catalogued dials is now a DIVISOR. '
                    'Their min of 0 was derived from them being multipliers only';
  END IF;
  RAISE NOTICE '0290 P1: mpu is still the only divisor; the other three are multipliers';
END $p1$;

-- P2. THE GAP IS STILL pitch MINUS width, TIMES mpu -------------------------
-- car_width_plan_units' min of 0 rests on a negative width INFLATING this.
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_site_geometry';
  IF position('round((a.pitch_pu - a.car_w_pu) * a.mpu, 4)' in v_src) = 0 THEN
    RAISE EXCEPTION '0290 P2: perimeter_body_gap_m is no longer (pitch - width) * mpu; '
                    'the argument that a negative width over-reports clearance came '
                    'from that expression';
  END IF;
  RAISE NOTICE '0290 P2: the perimeter gap is still (pitch - width) * mpu';
END $p2$;

-- P3. THE THREE LIVE ROWS ARE WHERE THEY WERE -------------------------------
DO $p3$
DECLARE v_n int; v_bad int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('car_length_plan_units','car_width_plan_units',
                       'stall_pitch_perimeter_pu');
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0290 P3: expected 3 live rows across the three catalogued keys, '
                    'found %', v_n;
  END IF;
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE param_key IN ('car_length_plan_units','car_width_plan_units',
                       'stall_pitch_perimeter_pu')
     AND param_value < 0;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0290 P3: % live row(s) are already negative', v_bad;
  END IF;
  RAISE NOTICE '0290 P3: 3 live rows, none negative';
END $p3$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('car_length_plan_units',
 '0290: the modelled vehicle body LENGTH in plan units, read by public.ottoq_site_geometry and reported both as length_plan_units and, multiplied by metres_per_plan_unit, as length_m and as the collision body box. min_value 0 by INVERSION: measured at -5 the function returns length_m -2.3925 without raising, i.e. a body box that is inside out rather than merely small. MAX NULL: the consumer caps no dimension, and inventing a ceiling would be the trap 0285 avoided. NOTE its sibling metres_per_plan_unit is deliberately NOT catalogued -- see 0290 and G61.',
 10.2, 0, NULL, 'public.ottoq_site_geometry'),
('car_width_plan_units',
 '0290: the modelled vehicle body WIDTH in plan units, read by public.ottoq_site_geometry. min_value 0 by INVERSION, and this one inverts something that matters: the function reports perimeter_body_gap_m = (stall_pitch_perimeter_pu - this) * metres_per_plan_unit, so a NEGATIVE WIDTH INFLATES THE REPORTED CLEARANCE. Measured: at -5 plan units the perimeter gap reads 5.1200 m where the default reads 0.7178 m -- a consumer trusting it would believe it had seven times the room it has. MAX NULL: no ceiling is declared anywhere.',
 4.2, 0, NULL, 'public.ottoq_site_geometry'),
('stall_pitch_perimeter_pu',
 '0290: centre-to-centre pitch of perimeter stalls in plan units, read by public.ottoq_site_geometry and reported in plan units, metres and feet, and as perimeter_body_gap_m = (this - car_width_plan_units) * metres_per_plan_unit. min_value 0 by INVERSION -- a negative pitch is not a pitch. NOTE 0 ITSELF IS MEANINGFUL and stays inside the range: measured at 0 the gap reads -2.0097 m, which is the coherent statement "the body is wider than the pitch". 0 is the edge of meaning, not the edge of correctness. MAX NULL: no ceiling is declared.',
 5.7, 0, NULL, 'public.ottoq_site_geometry');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER ACCEPTS ALL THREE, UNCLAMPED, AT THEIR OWN LIVE VALUES.
DO $a1$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029000cc'::uuid;
  v_r jsonb; k text; v numeric; v_n int := 0;
BEGIN
  FOR k, v IN
    SELECT DISTINCT param_key, param_value FROM public.ottoq_policy_params
     WHERE param_key IN ('car_length_plan_units','car_width_plan_units',
                         'stall_pitch_perimeter_pu')
       AND updated_by <> '0290_proof'
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, v, '0290_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'A1 FAILED: the setter still refuses %: %', k, v_r;
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A1 FAILED: the live value % = % was altered by the catalog: %',
                      k, v, v_r;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'A1 FAILED: re-offered % live values, expected 3', v_n;
  END IF;
  RAISE NOTICE 'A1 OK: all three live values pass through unchanged';
END $a1$;

-- A2. THE FLOOR FIRES, AND THE CEILING IS GENUINELY OPEN.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029000cc'::uuid;
  v_r jsonb; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['car_length_plan_units','car_width_plan_units',
                           'stall_pitch_perimeter_pu'] LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, -5, '0290_proof');
    IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
       OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
      RAISE EXCEPTION 'A2 FAILED: % set to -5 should clamp to 0 and say so: %', k, v_r;
    END IF;
    v_r := public.ottoq_policy_set('run', v_scratch, k, 5000, '0290_proof');
    IF COALESCE((v_r->>'applied')::numeric,-1) <> 5000
       OR COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A2 FAILED: % has no ceiling and must not be clamped at 5000: %',
                      k, v_r;
    END IF;
    IF (v_r->'safe_range'->>1) IS NOT NULL THEN
      RAISE EXCEPTION 'A2 FAILED: % should report an open upper bound: %', k, v_r;
    END IF;
  END LOOP;
  RAISE NOTICE 'A2 OK: the floor fires on all three and none has a ceiling';
END $a2$;

-- A3. THE CLAMP ACTUALLY PREVENTS THE MEASURED INVERSION, END TO END.
-- Not "the setter returned 0" but "the CONSUMER no longer reports a negative
-- dimension", which is the thing the range exists to stop.
--
-- SETS ALL THREE DIALS ITSELF, and the first draft did not, which is how this
-- assertion caught its own test rather than the code: A2 leaves the pitch at
-- 5000 (its open-ceiling probe), so an A3 that set only the two body dials read
-- a perimeter gap of 2392.5 m and failed a threshold written for a pitch of
-- 5.7. The threshold was the wrong instrument anyway. It is replaced below by a
-- SELF-CONSISTENT test that needs no magic number: with the width clamped to 0
-- the body occupies nothing, so the perimeter gap must equal the perimeter
-- itself, and the function reports both.
DO $a3$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029000cc'::uuid;
  v_geom jsonb; v_len numeric; v_wid numeric; v_gap numeric; v_per numeric;
BEGIN
  PERFORM public.ottoq_policy_set('run', v_scratch, 'car_length_plan_units',   -5, '0290_proof');
  PERFORM public.ottoq_policy_set('run', v_scratch, 'car_width_plan_units',    -5, '0290_proof');
  PERFORM public.ottoq_policy_set('run', v_scratch, 'stall_pitch_perimeter_pu', 5.7, '0290_proof');
  v_geom := public.ottoq_site_geometry(v_scratch);
  v_len := (v_geom->'car'->>'length_m')::numeric;
  v_wid := (v_geom->'car'->>'width_m')::numeric;
  v_gap := (v_geom->'stall_pitch'->>'perimeter_body_gap_m')::numeric;
  v_per := (v_geom->'stall_pitch'->>'perimeter_m')::numeric;
  IF v_len < 0 OR v_wid < 0 THEN
    RAISE EXCEPTION 'A3 FAILED: the consumer still reports a negative body '
                    '(length %, width %) after the catalog clamped the dials', v_len, v_wid;
  END IF;
  --: AND THE CLEARANCE IS NO LONGER OVER-REPORTED. A width of -5 produced a gap
  --: of 5.1200 m against a 2.7275 m perimeter before the catalog existed -- more
  --: clearance than the pitch physically contains. Clamped to 0 the two must be
  --: equal.
  IF v_gap <> v_per THEN
    RAISE EXCEPTION 'A3 FAILED: with the width clamped to 0 the perimeter gap (% m) '
                    'must equal the perimeter itself (% m); a gap larger than the '
                    'pitch is the inversion this range exists to stop', v_gap, v_per;
  END IF;
  RAISE NOTICE 'A3 OK: clamped dials give body % x % m, and the gap equals the '
               'perimeter at % m -- no inversion', v_len, v_wid, v_gap;
END $a3$;

-- A4. metres_per_plan_unit IS STILL REFUSED BY THE SETTER, ON PURPOSE.
-- The omission is deliberate; this proves it is still in force at apply time so
-- nobody reads the file and assumes it was catalogued after all.
DO $a4$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029000cc'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'metres_per_plan_unit', 0.5, '0290_proof');
  IF COALESCE((v_r->>'ok')::boolean, true) THEN
    RAISE EXCEPTION 'A4 FAILED: metres_per_plan_unit is catalogued after all; this '
                    'file argues at length that it must not be: %', v_r;
  END IF;
  IF COALESCE(v_r->>'error','') <> 'unknown_param' THEN
    RAISE EXCEPTION 'A4 FAILED: expected the setter to refuse it as unknown_param, got %',
                    v_r;
  END IF;
  RAISE NOTICE 'A4 OK: metres_per_plan_unit is still refused by the setter, as intended';
END $a4$;

-- A5. THE SCRATCH IS GONE AND THE THREE LIVE ROWS SURVIVE.
DO $a5$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0290_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'A5 FAILED: expected to remove exactly 3 scratch rows, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('car_length_plan_units','car_width_plan_units',
                       'stall_pitch_perimeter_pu');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'A5 FAILED: % rows remain across the three keys, expected the '
                    'original 3', v_n;
  END IF;
  RAISE NOTICE 'A5 OK: scratch removed, the original 3 live rows survive';
END $a5$;

-- A6. THE GAP INSTRUMENT AGREES: THREE CLOSED, ONE STILL OPEN ON PURPOSE.
DO $a6$
DECLARE v_ok int; v_mpu text;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok') INTO v_ok
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('car_length_plan_units','car_width_plan_units',
                       'stall_pitch_perimeter_pu');
  IF v_ok <> 3 THEN
    RAISE EXCEPTION 'A6 FAILED: expected all three to report ok, found %', v_ok;
  END IF;
  SELECT status INTO v_mpu FROM public.ottoq_policy_catalog_gap
   WHERE param_key = 'metres_per_plan_unit';
  IF v_mpu <> 'read_uncatalogued' THEN
    RAISE EXCEPTION 'A6 FAILED: metres_per_plan_unit reports %, expected it to remain '
                    'read_uncatalogued -- the omission is the point', v_mpu;
  END IF;
  RAISE NOTICE 'A6 OK: three closed, metres_per_plan_unit still open and still counted';
END $a6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0290_three_geometry_dials_and_one_the_catalog_cannot_express', false,
 'Three rows in ottoq_policy_param_catalog for the site geometry dials read by public.ottoq_site_geometry: car_length_plan_units, car_width_plan_units and stall_pitch_perimeter_pu, all min 0 max NULL. min 0 by INVERSION and MEASURED, not reasoned -- each was written to a scratch run and the consumer called inside a rolled-back transaction: at -5 the function returns length_m and width_m of -2.3925 without raising, and a negative WIDTH inflates perimeter_body_gap_m from 0.7178 m to 5.1200 m, so the engine would report seven times the clearance it has. 0 stays inside the range for the pitch because 0 there is meaningful (gap -2.0097 m, i.e. body wider than pitch). MAX NULL because the consumer caps no dimension. THE FOURTH DIAL, metres_per_plan_unit, IS DELIBERATELY NOT CATALOGUED: ottoq_site_geometry divides by it (round(1.0/a.mpu,6)) and 0 raises division_by_zero, measured -- so it needs a bound that admits every positive number and excludes zero, and ottoq_policy_set clamps with an INCLUSIVE GREATEST, so min 0 would advertise the fatal value as safe and any positive epsilon would be invented. Left out with the reason recorded rather than shipped unsafe or made up; the missing exclusive bound is filed as G61. P1 pins the division so the omission cannot go stale, P2 pins the gap expression the width argument rests on, A3 proves the clamp stops the inversion at the CONSUMER rather than just at the setter, and A4 proves the setter still refuses metres_per_plan_unit at apply time. forces_recert=false, asserted in P0: ottoq_policy_get never reads the catalog.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
