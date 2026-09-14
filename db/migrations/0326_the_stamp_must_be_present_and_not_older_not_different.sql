-- migration-version: 20260914193928
-- migration-name:    0326_the_stamp_must_be_present_and_not_older_not_different
-- ============================================================================
-- 0326 — 0322's TRIGGER REFUSES A CORRECT WRITE, BECAUSE "THE STAMP MUST MOVE"
--        IS NOT THE INVARIANT. THE INVARIANT IS "THE STAMP MUST BE PRESENT AND
--        NOT STALE."
-- ============================================================================
-- MEASURED 2026-09-14 19:36 UTC. The first pair of round 44 died in 1 s:
--
--   ottoq_assert_eta_provenance: dispatch 263d5043-... changes
--   return_eta_minutes NULL -> 2.5 without moving eta_refreshed_at
--   (still 2026-09-01 02:30:00+00)
--
-- and the call stack names the refused writer:
--
--   ottoq_determinism_pair
--     -> ottoq_sim_advance_tick -> ..._world
--       -> ottoq_sim_advance_deployed_telemetry  (line 228, the PERFORM 0321 added)
--         -> public.ottoq_refresh_return_eta     (line 34, the UPDATE 0320 created)
--
-- THE REFUSED WRITE IS 0320's OWN FUNCTION, AND IT SETS ALL THREE COLUMNS IN ONE
-- STATEMENT. It is the most compliant writer in the database. The trigger
-- refused it anyway.
--
-- ---------------------------------------------------------------------------
-- WHY, AND WHY MY OWN SELF-TESTS COULD NOT SEE IT
--
-- ottoq_refresh_return_eta stamps `eta_refreshed_at = p_sim_clock` -- the SIM
-- clock, deliberately, because a wall clock there is the G15 defect class.
-- WITHIN ONE TICK THE SIM CLOCK DOES NOT ADVANCE. So when a dispatch row is
-- written twice inside one tick -- which is ordinary, not pathological -- the
-- second write's NEW.eta_refreshed_at EQUALS OLD.eta_refreshed_at, and 0322's
-- UPDATE branch says:
--
--   IF NEW.eta_refreshed_at IS NOT DISTINCT FROM OLD.eta_refreshed_at THEN RAISE
--
-- I conflated two different statements:
--   (a) the value and its provenance are written TOGETHER   <- the real invariant
--   (b) the sim clock ADVANCES between two writes           <- not true, not required
--
-- 0322 enforced (b) while its header, its COMMENT and its commit message all
-- argued for (a).
--
-- AND THE SELF-TESTS PASSED. 0322's A2 proved the guard refuses an unstamped
-- write; A3 proved it permits a stamped one. Both used a SINGLE UPDATE against a
-- row whose stored stamp differed from the one being written. Neither could
-- express "two correct writes at the same sim clock", which is the only case
-- that fails. A guard tested only on the cases it was designed for is a guard
-- tested on its author's assumptions -- the same shape as 0240, 0241, 0318,
-- 0323's A1 and round 44's own truncated-uuid error.
--
-- ---------------------------------------------------------------------------
-- THE CORRECTED RULE
--
-- An UPDATE that changes return_eta_minutes must supply:
--   * eta_refreshed_at NOT NULL, and
--   * eta_refreshed_at >= OLD.eta_refreshed_at  (never a stamp older than the
--     one already on the row), and
--   * eta_source NOT NULL.
--
-- `>=` rather than `>`. Equality is exactly the legitimate same-tick case. What
-- is still caught is the case 0322 was written for: a writer that changes the
-- ETA and does not touch the stamp AT ALL, in a LATER tick -- it carries the
-- earlier tick's stamp forward, which is strictly older, and is refused.
--
-- The narrowed hole, stated rather than hidden: a forgetful writer inside the
-- SAME tick as the row's last stamp now passes. It is a smaller hole than a
-- trigger that stops the engine, and it is the honest trade.
--
-- INSERT branch: UNCHANGED. It was never wrong.
--
-- ---------------------------------------------------------------------------
-- BLAST RADIUS, MEASURED BEFORE WRITING THIS
--
-- Production was NOT down. Between 0322's apply (19:24) and the diagnosis
-- (19:36), ottoq-demo-metronome ran 13 times, ottoq-depot-tick 7, and
-- ottoq-run-governor 7 -- all `succeeded`, zero failures -- because no twin run
-- was active for the metronome to advance. What WAS blocked: every certification
-- pair, and every run the UI could have started. The window between applying a
-- broken trigger and catching it was twelve minutes and cost one cert pair.
-- ============================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0326 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0326 P-: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN RAISE EXCEPTION '0326 P-: % sim run(s) are in flight', v_runs; END IF;
  RAISE NOTICE '0326 P-: nothing in flight';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0326_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_assert_eta_provenance';

-- P0. THE DEFECT IS STILL PRESENT. If someone already relaxed it, stop.
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_assert_eta_provenance';
  IF v_src IS NULL THEN RAISE EXCEPTION '0326 P0: ottoq_assert_eta_provenance not found'; END IF;
  IF v_src !~ 'IS NOT DISTINCT FROM OLD\.eta_refreshed_at' THEN
    RAISE EXCEPTION '0326 P0: the distinctness clause is already gone; this migration is stale';
  END IF;
END $p0$;

CREATE OR REPLACE FUNCTION public.ottoq_assert_eta_provenance()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.eta_refreshed_at IS NULL OR NEW.eta_source IS NULL THEN
      RAISE EXCEPTION
        'ottoq_assert_eta_provenance: dispatch % inserts return_eta_minutes=% with '
        'eta_refreshed_at=% and eta_source=%. A forecast must carry a stamp and a source (0322).',
        NEW.dispatch_id, NEW.return_eta_minutes, NEW.eta_refreshed_at, COALESCE(NEW.eta_source,'NULL');
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE. 0326: the stamp must be PRESENT and NOT OLDER -- not "different".
  -- Equality is the legitimate same-tick case: eta_refreshed_at is the SIM clock,
  -- and two correct writes inside one tick necessarily share it.
  IF NEW.eta_refreshed_at IS NULL THEN
    RAISE EXCEPTION
      'ottoq_assert_eta_provenance: dispatch % changes return_eta_minutes % -> % with a NULL '
      'eta_refreshed_at. The value and its provenance move together (0322/0326).',
      NEW.dispatch_id, COALESCE(OLD.return_eta_minutes::text,'NULL'), NEW.return_eta_minutes;
  END IF;
  IF OLD.eta_refreshed_at IS NOT NULL AND NEW.eta_refreshed_at < OLD.eta_refreshed_at THEN
    RAISE EXCEPTION
      'ottoq_assert_eta_provenance: dispatch % changes return_eta_minutes % -> % but carries a '
      'STALE eta_refreshed_at (% is older than the % already on the row) -- the label would '
      'describe an earlier write (0322/0326).',
      NEW.dispatch_id, COALESCE(OLD.return_eta_minutes::text,'NULL'), NEW.return_eta_minutes,
      NEW.eta_refreshed_at, OLD.eta_refreshed_at;
  END IF;
  IF NEW.eta_source IS NULL THEN
    RAISE EXCEPTION
      'ottoq_assert_eta_provenance: dispatch % writes return_eta_minutes=% with a NULL '
      'eta_source. Name the origin (0322).', NEW.dispatch_id, NEW.return_eta_minutes;
  END IF;
  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_eta_provenance() IS
'Refuses any write that puts a value in ottoq_vehicle_dispatches.return_eta_minutes without a '
'non-null eta_refreshed_at and eta_source, or with a stamp OLDER than the one already on the '
'row. 0326 replaced 0322''s "the stamp must MOVE" with "the stamp must be present and not '
'older": eta_refreshed_at is the SIM clock, which does not advance within a tick, so two '
'correct writes in one tick necessarily share it and the original rule refused 0320''s own '
'refresh function on round 44''s first pair. Clearing the ETA to NULL remains exempt. 0322/0326.';

DO $post$
DECLARE v_src text; v_victim uuid; v_old timestamptz; v_fired boolean; v_ok boolean;
BEGIN
  -- A1. THE DISTINCTNESS CLAUSE IS GONE.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_assert_eta_provenance';
  IF v_src ~ 'IS NOT DISTINCT FROM OLD\.eta_refreshed_at' THEN
    RAISE EXCEPTION '0326 A1: the distinctness clause survived'; END IF;
  IF v_src !~ 'NEW\.eta_refreshed_at < OLD\.eta_refreshed_at' THEN
    RAISE EXCEPTION '0326 A1: the not-older clause is missing'; END IF;

  SELECT dispatch_id, eta_refreshed_at INTO v_victim, v_old
    FROM public.ottoq_vehicle_dispatches
   WHERE return_eta_minutes IS NOT NULL AND eta_refreshed_at IS NOT NULL
   ORDER BY dispatch_id LIMIT 1;
  IF v_victim IS NULL THEN
    RAISE EXCEPTION '0326 A2: no stamped dispatch row to exercise the guard against';
  END IF;

  -- A2. THE SAME-TICK WRITE IS NOW PERMITTED -- the case that broke round 44.
  --     Same stamp as the row already carries, which the old rule refused.
  BEGIN
    UPDATE public.ottoq_vehicle_dispatches
       SET return_eta_minutes = return_eta_minutes + 1,
           eta_refreshed_at   = v_old,            -- IDENTICAL, deliberately
           eta_source         = 'migration_selftest:0326'
     WHERE dispatch_id = v_victim;
    RAISE EXCEPTION 'ottoq_0326_selftest_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM = 'ottoq_0326_selftest_rollback' THEN v_ok := true;
    ELSE RAISE EXCEPTION '0326 A2: the guard still refuses a same-tick write: %', SQLERRM; END IF;
  END;
  IF NOT COALESCE(v_ok,false) THEN RAISE EXCEPTION '0326 A2: the same-tick write did not complete'; END IF;
  RAISE NOTICE '0326 A2: a same-tick write (identical stamp) is permitted, and was rolled back';

  -- A3. A STALE STAMP IS STILL REFUSED -- the case 0322 was written for.
  BEGIN
    UPDATE public.ottoq_vehicle_dispatches
       SET return_eta_minutes = return_eta_minutes + 1,
           eta_refreshed_at   = v_old - interval '1 hour',   -- OLDER
           eta_source         = 'migration_selftest:0326'
     WHERE dispatch_id = v_victim;
    v_fired := false;
  EXCEPTION WHEN raise_exception THEN
    v_fired := (SQLERRM ~ 'STALE eta_refreshed_at');
  END;
  IF NOT v_fired THEN
    RAISE EXCEPTION '0326 A3: a stale stamp was accepted; the guard no longer guards anything';
  END IF;
  RAISE NOTICE '0326 A3: a stale stamp is still refused';

  -- A4. NO RESIDUE.
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches
              WHERE eta_source = 'migration_selftest:0326') THEN
    RAISE EXCEPTION '0326 A4: self-test sentinel survived';
  END IF;
  RAISE NOTICE '0326 A4: no self-test residue';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0326_the_stamp_must_be_present_and_not_older_not_different', true,
   'Replaces 0322''s UPDATE rule. 0322 required NEW.eta_refreshed_at to DIFFER from OLD; but '
   'eta_refreshed_at is the SIM clock, which does not advance within a tick, so two correct '
   'writes in one tick share it. That refused ottoq_refresh_return_eta -- 0320''s own function, '
   'which writes all three columns in one statement -- and killed round 44''s first pair in 1 s. '
   'The rule is now: stamp present, stamp not OLDER than the row''s, source not null. Equality '
   'is the legitimate same-tick case; a writer that ignores the stamp in a LATER tick still '
   'carries a strictly older one and is still refused. 0322''s A2/A3 passed because both tested '
   'a SINGLE write against a row whose stamp differed -- neither could express the failing case.',
   now())
ON CONFLICT (name) DO NOTHING;
