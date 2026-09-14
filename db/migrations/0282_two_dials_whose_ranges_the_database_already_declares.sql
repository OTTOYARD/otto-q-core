-- migration-version: 20260914061049
-- migration-name:    0282_two_dials_whose_ranges_the_database_already_declares
--
-- 0282  THE FIRST TWO OF THE NINETY, AND NEITHER RANGE IS A JUDGEMENT CALL
--
-- ---------------------------------------------------------------------------
-- WHAT 0281 MEASURED AND WHAT THIS FILE STARTS PAYING DOWN
--
-- 0281 built public.ottoq_policy_catalog_gap and deliberately catalogued
-- nothing. The instrument says: 152 keys the engine reads, 60 catalogued,
-- ~92 not. For every uncatalogued key ottoq_policy_set answers
--
--   {"ok": false, "error": "unknown_param", "param": "<key>"}
--
-- WITHOUT raising -- so a caller that does not read its receipt is told
-- nothing, and the only way to set the dial is to write the row by hand with
-- no validation of any kind. That is how 57-61 of the live rows got written.
--
-- The temptation is to fix ninety keys in one INSERT. That would be ninety
-- guessed ranges wearing the authority of a migration, and a guessed clamp is
-- worse than no clamp: it silently rewrites a value the engine would have
-- honoured. So the rule for this work, set when the task was opened:
--
--   READ THE RANGE OFF THE CONSUMER. NEVER CHOOSE IT.
--   PIN THE CONSUMER'S SHAPE IN A PRECONDITION, so the file refuses to apply
--   if the shape it was derived from ever changes.
--
-- These two keys are first because they are the two most-read uncatalogued
-- keys in the database (3 reader functions each, per the 0281 view), and
-- because for both of them the range is not merely derivable -- it is already
-- WRITTEN DOWN somewhere the engine enforces it.
--
-- ---------------------------------------------------------------------------
-- KEY 1 -- sensor_soil_threshold -- RANGE [0, 1], DECLARED BY A CHECK CONSTRAINT
--
-- Three readers, one caller default (0.35), two live rows (both 0.35, depot
-- scope). Every reader compares it against a soil measure:
--
--   ottoq.ottoq_observe_asset:
--     v_soil := COALESCE(v_w.soil_index, v_p.exterior_soil_level);
--     'sensor_clean', COALESCE(v_soil, 0) >= v_sensor_soil OR ...
--   public.ottoq_recall_naive_threshold_v1:
--     v_has_service_need := COALESCE(v_w.soil_index,0) >= v_sensor_soil
--     IF COALESCE(v_w.soil_index,0) >= v_sensor_soil THEN
--   public.ottoq_scenario_apply_fleet_overrides:
--     v_soil_max := COALESCE((v_phase->>'soil_seed_fraction')::numeric, 0.85)
--                   * v_soil_thresh;              -- seeds soil BELOW the dial
--
-- and the compared quantity has a hard domain the database enforces:
--
--   ottoq_vehicle_wear_soil_index_check
--     CHECK (soil_index >= 0 AND soil_index <= 1)
--
-- The fallback column, vehicle_need_profile.exterior_soil_level, carries no
-- constraint but observes [0.000, 1.000] across all 120 rows.
--
-- So the range is not chosen: below 0 and above 1 the comparison is constant
-- (never clean / always clean) because the left-hand side cannot leave [0,1].
-- P1 pins the CHECK constraint itself. If somebody rescales soil_index, this
-- file stops applying and the range is re-derived rather than silently wrong.
--
-- ---------------------------------------------------------------------------
-- KEY 2 -- reserve_margin_pct -- RANGE [0, 100], DECLARED BY ITS OWN CONSUMER
--
-- Three readers, one caller default (15), two live rows (both 25, depot
-- scope). It is a percentage-POINT addend to a state-of-charge percentage:
--
--   public.ottoq_recall_naive_threshold_v1:
--     v_reserve        := ottoq_effective_reserve_soc(p_vehicle_id, ...);
--     v_reserve_margin := ottoq_policy_get(..., 'reserve_margin_pct', 15);
--     IF v_soc <= v_reserve + v_reserve_margin THEN   -- the recall trigger
--   public.ottoq_hw_set_return_threshold / ottoq_hw_vehicle_status:
--     'effective_recall_pct', ottoq_effective_reserve_soc(...) + v_margin
--
-- ottoq_effective_reserve_soc returns an SoC percentage (an SLA's
-- return_reserve_soc_pct, else vehicles.min_soc_threshold, floored at 20).
-- And the scale is declared literally, in the same function, twelve lines down
-- from the comparison:
--
--     v_slot := LEAST(v_wave_bands, width_bucket(v_soc, 0, 100, v_wave_bands));
--
-- min 0: the dial is a MARGIN added to a reserve floor. A negative margin
--   would trigger recall BELOW the SLA reserve it is supposed to protect --
--   an inversion of the dial's purpose, not a setting.
-- max 100: v_reserve >= 20 by that function's own floor and v_soc <= 100, so
--   at margin 100 the comparison is already unconditionally true. Every value
--   above 100 is behaviourally identical to 100; the clamp loses nothing.
--
-- P2 pins both the comparison and the 0..100 width_bucket.
--
-- ---------------------------------------------------------------------------
-- WHY THIS CANNOT MOVE THE ENGINE (the forces_recert=false argument)
--
-- ottoq_policy_get resolves run -> depot -> global -> CALLER DEFAULT. It never
-- reads ottoq_policy_param_catalog at all -- P3 asserts that rather than
-- trusting it. So a catalog row is read by exactly one function,
-- ottoq_policy_set, which no certification arm calls. The four live rows are
-- untouched (A3) and both are inside the ranges declared here (P4).
--
-- What changes: the supported setter starts accepting these two keys, and
-- clamps instead of writing whatever it is handed.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0282 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0282 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0282 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0282 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. BOTH KEYS ARE STILL UNCATALOGUED (the file's premise) -------------------
DO $p0$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('sensor_soil_threshold','reserve_margin_pct');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0282 P0: % of the two keys are already catalogued; '
                    'this file''s premise no longer holds', v_n;
  END IF;
  RAISE NOTICE '0282 P0: both keys uncatalogued, as the 0281 view reports';
END $p0$;

-- P1. sensor_soil_threshold's RANGE IS STILL DECLARED BY THE DATABASE ---------
-- [0,1] is read off the CHECK on the column every reader compares it against.
-- Rescale soil_index and this precondition fails BEFORE the range is wrong.
DO $p1$
DECLARE v_def text; v_src text;
BEGIN
  SELECT pg_get_constraintdef(con.oid) INTO v_def
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
   WHERE rel.relname = 'ottoq_vehicle_wear'
     AND con.conname = 'ottoq_vehicle_wear_soil_index_check';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0282 P1: the soil_index CHECK constraint is gone; '
                    're-derive the range before cataloguing the dial';
  END IF;
  IF position('soil_index >= (0)::numeric' in v_def) = 0
     OR position('soil_index <= (1)::numeric' in v_def) = 0 THEN
    RAISE EXCEPTION '0282 P1: soil_index no longer runs [0,1] (%); '
                    'the dial''s range is derived from it and must be re-read', v_def;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0282 P1: ottoq_recall_naive_threshold_v1 does not exist';
  END IF;
  IF position('COALESCE(v_w.soil_index,0) >= v_sensor_soil' in v_src) = 0 THEN
    RAISE EXCEPTION '0282 P1: the dial is no longer compared against soil_index; '
                    'the [0,1] argument does not survive that change';
  END IF;
  RAISE NOTICE '0282 P1: soil_index is CHECK-constrained to [0,1] and the dial '
               'is still compared against it';
END $p1$;

-- P2. reserve_margin_pct's SCALE IS STILL 0..100, IN ITS OWN CONSUMER ---------
DO $p2$
DECLARE v_src text; v_res text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_recall_naive_threshold_v1';
  IF position('v_soc <= v_reserve + v_reserve_margin' in v_src) = 0 THEN
    RAISE EXCEPTION '0282 P2: the margin is no longer added to the reserve SoC; '
                    're-derive the range before applying';
  END IF;
  IF position('width_bucket(v_soc, 0, 100' in v_src) = 0 THEN
    RAISE EXCEPTION '0282 P2: the function no longer declares SoC on a 0..100 '
                    'scale; max_value is derived from that declaration';
  END IF;
  SELECT p.prosrc INTO v_res FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_effective_reserve_soc';
  IF v_res IS NULL OR position('return_reserve_soc_pct' in v_res) = 0 THEN
    RAISE EXCEPTION '0282 P2: ottoq_effective_reserve_soc no longer returns an '
                    'SoC percentage; the addend''s units would change with it';
  END IF;
  RAISE NOTICE '0282 P2: the margin is a percentage-point addend on a 0..100 SoC scale';
END $p2$;

-- P3. THE READ PATH STILL IGNORES THE CATALOG --------------------------------
-- This is the whole forces_recert=false argument, asserted instead of assumed:
-- if ottoq_policy_get ever started consulting the catalog, adding rows would
-- become an engine change and this file would need a certification window.
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0282 P3: ottoq_policy_get does not exist';
  END IF;
  IF position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0282 P3: ottoq_policy_get now READS the catalog -- adding a '
                    'row is an engine change and this file must be re-classified';
  END IF;
  RAISE NOTICE '0282 P3: ottoq_policy_get does not read the catalog; a new row '
               'changes no engine read';
END $p3$;

-- P4. EVERY EXISTING ROW IS ALREADY INSIDE THE RANGES DECLARED HERE -----------
-- 0279 P3's rule: cataloguing must never leave a live row the setter itself
-- would refuse to write. Checked, not hoped.
DO $p4$
DECLARE v_bad int; v_n int;
BEGIN
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE (param_key = 'sensor_soil_threshold' AND (param_value < 0 OR param_value > 1))
      OR (param_key = 'reserve_margin_pct'    AND (param_value < 0 OR param_value > 100));
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0282 P4: % existing row(s) fall outside the ranges this file '
                    'declares; correct them before cataloguing', v_bad;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('sensor_soil_threshold','reserve_margin_pct');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0282 P4: expected the 4 measured live rows, found % -- '
                    'somebody wrote these dials since the measurement', v_n;
  END IF;
  RAISE NOTICE '0282 P4: 4 live rows, all inside the declared ranges';
END $p4$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('sensor_soil_threshold',
 '0282: the soil level at or above which an asset is judged to need a sensor clean. Compared with >= against COALESCE(ottoq_vehicle_wear.soil_index, vehicle_need_profile.exterior_soil_level) by ottoq.ottoq_observe_asset and public.ottoq_recall_naive_threshold_v1, and used by public.ottoq_scenario_apply_fleet_overrides as the ceiling that seeded soil is scaled under (soil_seed_fraction * this dial), so raising it also raises the soil the scenario seeds. THE RANGE IS NOT CHOSEN: ottoq_vehicle_wear carries CHECK (soil_index >= 0 AND soil_index <= 1), so outside [0,1] the comparison is constant -- never clean below 0, always clean above 1. Rescale soil_index and re-derive this row; 0282 P1 pins the constraint so the derivation cannot go stale silently. default_value 0.35 is the caller default all three readers pass, read off them rather than picked.',
 0.35, 0, 1,
 'ottoq.ottoq_observe_asset, public.ottoq_recall_naive_threshold_v1, public.ottoq_scenario_apply_fleet_overrides'),
('reserve_margin_pct',
 '0282: percentage POINTS added to an asset''s effective reserve SoC to form the recall trigger -- public.ottoq_recall_naive_threshold_v1 recalls when v_soc <= ottoq_effective_reserve_soc(...) + this dial, and ottoq_hw_set_return_threshold / ottoq_hw_vehicle_status publish the same sum as effective_recall_pct. Bigger value = recall earlier, with more charge left. THE RANGE IS NOT CHOSEN: the reserve is an SoC percentage (an SLA''s return_reserve_soc_pct, else vehicles.min_soc_threshold, floored at 20) and the same function declares the scale literally, as width_bucket(v_soc, 0, 100, v_wave_bands). min 0 because a negative margin would trigger recall BELOW the SLA reserve it exists to protect, inverting the dial; max 100 because reserve >= 20 and SoC <= 100 make the comparison unconditionally true at 100, so every larger value is behaviourally identical and the clamp loses nothing. default_value 15 is the caller default all three readers pass. NOTE the two live rows are 25, not 15 -- the depots override it upward.',
 15, 0, 100,
 'public.ottoq_recall_naive_threshold_v1, public.ottoq_hw_set_return_threshold, public.ottoq_hw_vehicle_status');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER NOW ACCEPTS BOTH KEYS IT HAS ALWAYS REFUSED.
-- Scratch scope id, not any real run: ottoq_policy_set does not check that a
-- run exists, which is why a scratch write is safe and why A4 removes it.
DO $a1$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028200aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'sensor_soil_threshold', 0.5, '0282_proof');
  IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
    RAISE EXCEPTION 'A1 FAILED: setter still refuses sensor_soil_threshold: %', v_r;
  END IF;
  IF public.ottoq_policy_get(v_scratch, 'sensor_soil_threshold', -1) <> 0.5 THEN
    RAISE EXCEPTION 'A1 FAILED: sensor_soil_threshold did not read back as 0.5';
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'reserve_margin_pct', 20, '0282_proof');
  IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
    RAISE EXCEPTION 'A1 FAILED: setter still refuses reserve_margin_pct: %', v_r;
  END IF;
  IF public.ottoq_policy_get(v_scratch, 'reserve_margin_pct', -1) <> 20 THEN
    RAISE EXCEPTION 'A1 FAILED: reserve_margin_pct did not read back as 20';
  END IF;
  RAISE NOTICE 'A1 OK: both keys write through the setter and read back';
END $a1$;

-- A2. BOTH CLAMPS ARE TWO-SIDED AND THE RECEIPT SAYS SO.
-- One-sided clamp assertions are how a wrong min_value ships unnoticed.
DO $a2$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028200aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'sensor_soil_threshold', 5, '0282_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 1
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: soil 5 should clamp to 1 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'sensor_soil_threshold', -2, '0282_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: soil -2 should clamp to 0 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'reserve_margin_pct', 150, '0282_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 100
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: margin 150 should clamp to 100 and report it: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'reserve_margin_pct', -10, '0282_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 0
     OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
    RAISE EXCEPTION 'A2 FAILED: margin -10 should clamp to 0 and report it: %', v_r;
  END IF;
  RAISE NOTICE 'A2 OK: both dials clamp on both sides, every clamp reported';
END $a2$;

-- A3. AN IN-RANGE VALUE IS NOT TOUCHED.
-- The clamp must be invisible to every legitimate setting, including the two
-- the depots actually run (0.35 and 25).
DO $a3$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028200aa'::uuid; v_r jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'sensor_soil_threshold', 0.35, '0282_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 0.35
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: the live soil value 0.35 was altered: %', v_r;
  END IF;
  v_r := public.ottoq_policy_set('run', v_scratch, 'reserve_margin_pct', 25, '0282_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 25
     OR COALESCE((v_r->>'clamped')::boolean,true) THEN
    RAISE EXCEPTION 'A3 FAILED: the live margin value 25 was altered: %', v_r;
  END IF;
  RAISE NOTICE 'A3 OK: the two values the depots actually run pass through unchanged';
END $a3$;

-- A4. THE FOUR LIVE ROWS ARE UNTOUCHED AND THE SCRATCH IS GONE.
-- A proof must not leave a dial behind -- and per 0279's closing note, the
-- probe that mutates belongs INSIDE the transaction that can roll it back.
DO $a4$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params
   WHERE param_key IN ('sensor_soil_threshold','reserve_margin_pct')
     AND updated_by = '0282_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'A4 FAILED: expected to remove exactly 2 scratch rows, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('sensor_soil_threshold','reserve_margin_pct');
  IF v_n <> 4 THEN
    RAISE EXCEPTION 'A4 FAILED: % rows remain, expected the original 4', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('sensor_soil_threshold','reserve_margin_pct')
     AND param_value NOT IN (0.35, 25);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % surviving row(s) no longer hold their measured '
                    'values (0.35 / 25)', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: scratch removed, the original 4 rows survive at their measured values';
END $a4$;

-- A5. THE 0281 INSTRUMENT AGREES THE GAP JUST SHRANK BY TWO.
-- The view is the thing that will tell us when this work is done; if it cannot
-- see a key move from read_uncatalogued to ok, it is not measuring the work.
DO $a5$
DECLARE v_ok int; v_still int;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok'),
         count(*) FILTER (WHERE status <> 'ok')
    INTO v_ok, v_still
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('sensor_soil_threshold','reserve_margin_pct');
  IF v_still > 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % of the two keys still report a gap; the catalog '
                    'row and the view disagree about what was just done', v_still;
  END IF;
  -- Counted positively, not merely "no gaps": a key that fell out of the view
  -- entirely would satisfy the check above while proving nothing.
  IF v_ok <> 2 THEN
    RAISE EXCEPTION 'A5 FAILED: expected both keys to report ok, found % row(s)', v_ok;
  END IF;
  RAISE NOTICE 'A5 OK: both keys now report ok in ottoq_policy_catalog_gap';
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0282_two_dials_whose_ranges_the_database_already_declares', false,
 'Two rows in ottoq_policy_param_catalog: sensor_soil_threshold [0,1] default 0.35, reserve_margin_pct [0,100] default 15. Both ranges are read off the consumers, not chosen -- soil from the CHECK constraint ottoq_vehicle_wear_soil_index_check on the column every reader compares the dial against, the margin from ottoq_recall_naive_threshold_v1''s own width_bucket(v_soc, 0, 100, ...) plus the >= 20 floor in ottoq_effective_reserve_soc; P1 and P2 pin both derivations so the file refuses to apply if either shape changes. Effect: ottoq_policy_set stops answering unknown_param for these two keys and starts clamping two-sidedly with clamped:true in the receipt. No function is replaced. forces_recert=false, asserted rather than assumed: P3 proves ottoq_policy_get never reads the catalog, so a catalog row is consumed only by ottoq_policy_set, which no certification arm calls; the 4 pre-existing rows are untouched and asserted still at their measured values (A4). First payment against the ~92-key gap 0281 measured.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 06:10:49 UTC (1:10 AM CT) as
-- supabase_migrations.schema_migrations version 20260914061049.
--
-- Dry run: the file byte for byte inside BEGIN ... ROLLBACK, clean on the
-- first attempt. P-, P0, P1, P2, P3, P4 and A1-A5 all passed, and a
-- post-rollback re-count confirmed the dry run left nothing behind:
-- 0 catalog rows, the original 4 live rows, 0 rows tagged 0282.
--
-- VERIFIED AFTER APPLY, read-only (no probe that writes -- 0279's closing
-- note is the reason this verification asserts nothing it would have to
-- clean up afterwards):
--
--   ottoq_policy_param_catalog rows for the two keys    2   (was 0)
--   ottoq_policy_params rows for the two keys           4   (unchanged)
--   rows left behind by the proof                       0
--
--   ottoq_policy_catalog_gap, status = read_uncatalogued
--     before   90
--     after    88
--   ottoq_policy_catalog_gap, status = ok
--     before   60
--     after    62
--
-- Two keys down. The instrument that counts them is the same one that will
-- say when the work is finished, which is the point of having built it
-- before cataloguing anything.
-- ===========================================================================
