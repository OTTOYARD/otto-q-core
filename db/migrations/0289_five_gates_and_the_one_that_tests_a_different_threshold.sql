-- migration-version: 20260914081939
-- migration-name:    0289_five_gates_and_the_one_that_tests_a_different_threshold
--
-- 0289  FIVE GATES, AND THE ONE THAT TESTS A DIFFERENT THRESHOLD
--
-- Fifth file under the 0282 rule: READ THE RANGE OFF THE CONSUMER, NEVER CHOOSE
-- IT. Five keys, all boolean gates, all [0,1] by the same argument 0286 used
-- for allow_concurrent_runs and enforce_site_charge_cap: a dial that is only
-- ever compared against one threshold can express exactly two things, so one
-- value on each side of it is the whole of its range.
--
--   key                                     consumer's test            default
--   bay_reservation_reconcile_enabled       ... < 1  THEN RETURN 0           1
--   indepot_guard_enforce                   v_enforce < 1 AND ...            1
--   indepot_critical_requires_immobilizing  v_req < 1                        1
--   metronome_ceiling_guard                 ... >= 1                         1
--   deploy_ready_gate_enabled               ... > 0                          1
--
-- ---------------------------------------------------------------------------
-- THE ONE THAT IS NOT LIKE THE OTHERS, AND IT IS WORTH THE PARAGRAPH
--
-- Four of the five test the dial against ONE: `< 1` to mean off, `>= 1` to mean
-- on. The fifth, deploy_ready_gate_enabled, tests it against ZERO:
--
--   IF COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_ready_gate_enabled',1),1) > 0
--
-- These are the same for 0 and 1 and DIFFERENT for everything between. A dial
-- set to 0.5 is OFF in four of these gates and ON in the fifth. Nothing in the
-- database currently sets any of them to a fraction -- there are no live rows at
-- all (P6) -- so this is latent, not live. It is recorded here, and in that
-- key's catalog row, because the next person to read one of these gates will
-- carry the idiom from the others and be wrong about this one.
--
-- The catalogued range is [0,1] for all five regardless: both idioms agree that
-- 0 is off and 1 is on, and the range is what the setter clamps to, not a
-- statement about the threshold. Unifying the idiom is a separate change to the
-- decide path and is not attempted here.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE CANNOT ASSERT, SAID BEFORE IT IS NOTICED
--
-- 0282 through 0286 each ended with an assertion that re-offers every DISTINCT
-- LIVE VALUE of the catalogued keys to the setter and requires it through
-- unclamped -- the check that the catalog cannot silently move a value the
-- engine is already using. There are ZERO live rows across all five keys here,
-- so that assertion has nothing to check and is NOT WRITTEN. P6 measures the
-- zero instead and REFUSES TO APPLY if rows have appeared, so "there was
-- nothing to check" is a recorded fact rather than an assertion that passed
-- because it was empty -- and the day somebody writes one of these dials, this
-- file stops being correct and says so.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0289 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0289 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0289 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0289 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. PREMISE + THE forces_recert=false ARGUMENT -----------------------------
DO $p0$
DECLARE v_n int; v_src text;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                       'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                       'metronome_ceiling_guard');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0289 P0: % of the five keys are already catalogued', v_n;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get';
  IF v_src IS NULL OR position('ottoq_policy_param_catalog' in v_src) > 0 THEN
    RAISE EXCEPTION '0289 P0: ottoq_policy_get is missing or now reads the catalog';
  END IF;
  RAISE NOTICE '0289 P0: five keys uncatalogued; the read path still ignores the catalog';
END $p0$;

-- P1. bay_reservation_reconcile_enabled IS STILL A `< 1` GATE ---------------
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_reconcile_bay_reservations';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0289 P1: ottoq.ottoq_reconcile_bay_reservations does not exist';
  END IF;
  IF position('''bay_reservation_reconcile_enabled'',1),1) < 1' in v_src) = 0 THEN
    RAISE EXCEPTION '0289 P1: bay_reservation_reconcile_enabled is no longer a < 1 gate';
  END IF;
  RAISE NOTICE '0289 P1: bay_reservation_reconcile_enabled still tests < 1';
END $p1$;

-- P2. BOTH IN-DEPOT GUARD DIALS ARE STILL `< 1` GATES -----------------------
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_indepot_reassignment_guard';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0289 P2: public.ottoq_indepot_reassignment_guard does not exist';
  END IF;
  IF position('''indepot_guard_enforce'', 1), 1)' in v_src) = 0
     OR position('v_enforce < 1' in v_src) = 0 THEN
    RAISE EXCEPTION '0289 P2: indepot_guard_enforce is no longer read and tested as a '
                    '< 1 gate';
  END IF;
  IF position('''indepot_critical_requires_immobilizing'',1),1)' in v_src) = 0
     OR position('v_req < 1' in v_src) = 0 THEN
    RAISE EXCEPTION '0289 P2: indepot_critical_requires_immobilizing is no longer read '
                    'and tested as a < 1 gate';
  END IF;
  RAISE NOTICE '0289 P2: both in-depot guard dials still test < 1';
END $p2$;

-- P3. metronome_ceiling_guard IS STILL A `>= 1` GATE ------------------------
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_demo_metronome';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0289 P3: public.ottoq_demo_metronome does not exist';
  END IF;
  IF position('''metronome_ceiling_guard'', 1) >= 1' in v_src) = 0 THEN
    RAISE EXCEPTION '0289 P3: metronome_ceiling_guard is no longer a >= 1 gate';
  END IF;
  RAISE NOTICE '0289 P3: metronome_ceiling_guard still tests >= 1';
END $p3$;

-- P4. deploy_ready_gate_enabled IS STILL THE ODD ONE, TESTING `> 0` ---------
-- This precondition exists to catch the day somebody "tidies" it to >= 1. That
-- would be a behaviour change for any fractional value, and this file's note
-- about the two idioms would silently become false.
DO $p4$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0289 P4: twin.ottoq_sim_advance_service_flow does not exist';
  END IF;
  IF position('''deploy_ready_gate_enabled'',1),1) > 0' in v_src) = 0 THEN
    RAISE EXCEPTION '0289 P4: deploy_ready_gate_enabled is no longer a > 0 gate; this '
                    'file records that it is the only one of the five testing against '
                    'zero rather than one, and that note must not go stale silently';
  END IF;
  RAISE NOTICE '0289 P4: deploy_ready_gate_enabled still tests > 0, unlike the other four';
END $p4$;

-- P5. THE TWO IDIOMS REALLY DO DIFFER, DEMONSTRATED RATHER THAN ASSERTED ----
DO $p5$
BEGIN
  IF NOT (0.5 > 0) THEN
    RAISE EXCEPTION '0289 P5: arithmetic is broken';
  END IF;
  IF (0.5 >= 1) THEN
    RAISE EXCEPTION '0289 P5: arithmetic is broken';
  END IF;
  RAISE NOTICE '0289 P5: 0.5 is ON under > 0 and OFF under >= 1 -- the two idioms '
               'disagree on every value strictly between 0 and 1';
END $p5$;

-- P6. THERE ARE NO LIVE ROWS, MEASURED ------------------------------------
DO $p6$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                       'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                       'metronome_ceiling_guard');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0289 P6: % live row(s) exist across the five keys. This file says '
                    'there are none and therefore writes no pass-through assertion; '
                    'with rows present it MUST, so re-derive before applying', v_n;
  END IF;
  RAISE NOTICE '0289 P6: zero live rows across all five keys -- every run takes the '
               'caller default of 1';
END $p6$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES
('bay_reservation_reconcile_enabled',
 '0289: whether ottoq.ottoq_reconcile_bay_reservations runs at all. Tested as COALESCE(ottoq_policy_get(run,''bay_reservation_reconcile_enabled'',1),1) < 1 THEN RETURN 0 -- a boolean gate, so [0,1] is the whole of what the engine can distinguish: 0 skips reconciliation, anything at or above 1 performs it. 0289 P1 pins the test. No live row: every run takes the caller default of 1.',
 1, 0, 1, 'ottoq.ottoq_reconcile_bay_reservations'),
('indepot_guard_enforce',
 '0289: whether public.ottoq_indepot_reassignment_guard ENFORCES its verdict or merely records it. Read into v_enforce and tested as v_enforce < 1 AND p_reason IN (''resource_fault'',''vehicle_fault''), so below 1 the guard stands down for those two reasons. A boolean gate, hence [0,1]. 0289 P2 pins both the read and the test. No live row: every run takes the caller default of 1, i.e. enforcing.',
 1, 0, 1, 'public.ottoq_indepot_reassignment_guard'),
('indepot_critical_requires_immobilizing',
 '0289: whether a CRITICAL in-depot reassignment additionally requires the payload to declare immobilizing. Read into v_req and tested as v_req < 1, which also selects the audit reason ''policy_immobilizing_check_disabled'' -- so the engine records WHY it stood down, and that string is the tell that this is a two-state dial. [0,1]. 0289 P2 pins the test. No live row: default 1.',
 1, 0, 1, 'public.ottoq_indepot_reassignment_guard'),
('metronome_ceiling_guard',
 '0289: whether public.ottoq_demo_metronome reserves time at the end of its budget rather than starting a tick it may not finish. Tested as ottoq_policy_get(run,''metronome_ceiling_guard'',1) >= 1 into v_guard_on. A boolean gate, hence [0,1]. 0289 P3 pins the test. No live row: default 1.',
 1, 0, 1, 'public.ottoq_demo_metronome'),
('deploy_ready_gate_enabled',
 '0289: whether twin.ottoq_sim_advance_service_flow holds a vehicle back until it is READY rather than merely finished. THE ONE OF THESE FIVE GATES THAT TESTS AGAINST ZERO, NOT ONE: COALESCE(ottoq_policy_get(run,''deploy_ready_gate_enabled'',1),1) > 0. The other four use < 1 or >= 1, so a dial set to 0.5 would be OFF in those four and ON in this one. Nothing sets any of them fractionally today and there are no live rows at all, so this is latent -- but a reader carrying the idiom across from the others will be wrong here. The range is still [0,1]: both idioms agree that 0 is off and 1 is on, and the range is what the setter clamps to, not a statement about the threshold. The function''s own comment names 0 as "gate off, pre-2026-08-02 behaviour". 0289 P4 pins the > 0 so this note cannot go stale silently.',
 1, 0, 1, 'twin.ottoq_sim_advance_service_flow');

-- ---------------------------------------------------------------------------
-- A1. THE SETTER ACCEPTS ALL FIVE, UNCLAMPED, AT AN IN-RANGE VALUE.
DO $a1$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000028900aa'::uuid;
  v_r jsonb; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                           'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                           'metronome_ceiling_guard'] LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, 0, '0289_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'A1 FAILED: the setter still refuses %: %', k, v_r;
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A1 FAILED: % was clamped from the in-range value 0: %', k, v_r;
    END IF;
    IF public.ottoq_policy_get(v_scratch, k, -1) <> 0 THEN
      RAISE EXCEPTION 'A1 FAILED: % did not read back as 0', k;
    END IF;
  END LOOP;
  RAISE NOTICE 'A1 OK: all five keys write through the setter, unclamped, and read back';
END $a1$;

-- A2. BOTH BOUNDS FIRE, ON EVERY KEY.
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000028900aa'::uuid;
  v_r jsonb; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                           'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                           'metronome_ceiling_guard'] LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, 7, '0289_proof');
    IF COALESCE((v_r->>'applied')::numeric,-1) <> 1
       OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
      RAISE EXCEPTION 'A2 FAILED: % set to 7 should clamp to 1 and say so: %', k, v_r;
    END IF;
    v_r := public.ottoq_policy_set('run', v_scratch, k, -3, '0289_proof');
    IF COALESCE((v_r->>'applied')::numeric,-1) <> 0
       OR NOT COALESCE((v_r->>'clamped')::boolean,false) THEN
      RAISE EXCEPTION 'A2 FAILED: % set to -3 should clamp to 0 and say so: %', k, v_r;
    END IF;
  END LOOP;
  RAISE NOTICE 'A2 OK: every declared bound fires on every key';
END $a2$;

-- A3. THE CATALOG DOES NOT MAKE A GATE UNREACHABLE.
-- A [0,1] range must still admit BOTH states; a bound that clamped 1 away would
-- turn a gate into a constant.
DO $a3$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000028900aa'::uuid;
  v_r jsonb; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                           'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                           'metronome_ceiling_guard'] LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, k, 1, '0289_proof');
    IF COALESCE((v_r->>'applied')::numeric,-1) <> 1
       OR COALESCE((v_r->>'clamped')::boolean,true) THEN
      RAISE EXCEPTION 'A3 FAILED: % cannot be set to 1 unclamped; the catalog turned a '
                      'gate into a constant: %', k, v_r;
    END IF;
  END LOOP;
  RAISE NOTICE 'A3 OK: both states remain reachable on all five gates';
END $a3$;

-- A4. THE SCRATCH IS GONE, AND THERE ARE STILL NO LIVE ROWS.
DO $a4$
DECLARE v_n int;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0289_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 5 THEN
    RAISE EXCEPTION 'A4 FAILED: expected to remove exactly 5 scratch rows, removed %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key IN ('bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                       'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                       'metronome_ceiling_guard');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % row(s) remain across the five keys, expected none', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: scratch removed, still zero live rows';
END $a4$;

-- A5. THE 0281 INSTRUMENT AGREES THE GAP SHRANK BY FIVE.
DO $a5$
DECLARE v_ok int; v_still int;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'ok'), count(*) FILTER (WHERE status <> 'ok')
    INTO v_ok, v_still
    FROM public.ottoq_policy_catalog_gap
   WHERE param_key IN ('bay_reservation_reconcile_enabled','deploy_ready_gate_enabled',
                       'indepot_guard_enforce','indepot_critical_requires_immobilizing',
                       'metronome_ceiling_guard');
  IF v_still > 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % of the five still report a gap', v_still;
  END IF;
  IF v_ok <> 5 THEN
    RAISE EXCEPTION 'A5 FAILED: expected all five to report ok, found %', v_ok;
  END IF;
  RAISE NOTICE 'A5 OK: all five now report ok in ottoq_policy_catalog_gap';
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0289_five_gates_and_the_one_that_tests_a_different_threshold', false,
 'Five rows in ottoq_policy_param_catalog, all boolean gates at [0,1] default 1, every range read off the single consumer that reads each key: bay_reservation_reconcile_enabled (< 1, ottoq_reconcile_bay_reservations), indepot_guard_enforce and indepot_critical_requires_immobilizing (both < 1, ottoq_indepot_reassignment_guard), metronome_ceiling_guard (>= 1, ottoq_demo_metronome), deploy_ready_gate_enabled (> 0, twin.ottoq_sim_advance_service_flow). RECORDED BECAUSE IT IS LATENT AND WILL BITE: deploy_ready_gate_enabled is the only one of the five testing against ZERO rather than ONE, so a fractional value would be OFF in the other four and ON in it; P4 pins the > 0 and P5 demonstrates the two idioms disagreeing, so the note cannot go stale silently. Unifying the idiom is a decide-path change and is not attempted. There are ZERO live rows across all five keys (P6 measures it), so the pass-through assertion 0282-0286 all carried is NOT written here rather than allowed to pass vacuously; A3 replaces it with a check that the catalog has not made either state of a gate unreachable. forces_recert=false, asserted in P0: ottoq_policy_get never reads the catalog.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 2026-09-14 08:19:39 UTC (3:19 AM CT) as
-- supabase_migrations.schema_migrations version 20260914081939.
--
-- Dry run: the WHOLE file byte for byte inside BEGIN ... ROLLBACK, no
-- abbreviation anywhere, clean on the first attempt. P-, P0-P6 and A1-A5 all
-- passed. All seven precondition literals were pre-verified against live prosrc
-- beforehand and every one returned a non-zero position, so none of them is
-- passing vacuously.
--
-- VERIFIED AFTER APPLY, read-only:
--
--   ottoq_policy_catalog_gap, read_uncatalogued   61 -> 56
--   ottoq_policy_catalog_gap, ok                  89 -> 94
--   ottoq_policy_param_catalog rows               97 -> 102
--   ottoq_policy_params rows across the five      0, unchanged
--   rows tagged updated_by = '0289_proof'         0 (A4 removed its own scratch)
--   ottoq_cert_lineage.forces_recert              false
--
-- AND THE PROCESS NOTE THIS FILE OWES THE PREVIOUS ONE. 0288 was added to
-- db/migrations/ without running scripts/regen-artefacts.sh, and CI caught it:
-- MIGRATION_LOG.md and scripts/check-drift.sql both index the FILES on disk,
-- not the applied set, and the index has a "PENDING / no -- pending" column for
-- exactly the held case. The rule is about the file existing. The regen for
-- THIS file is in the same commit as its APPLIED banner, where it belongs.
