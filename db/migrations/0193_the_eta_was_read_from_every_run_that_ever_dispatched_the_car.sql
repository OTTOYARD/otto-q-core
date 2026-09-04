-- =====================================================================
-- 0193  The ETA was read from every run that ever dispatched the car
-- =====================================================================
-- forces_recert = TRUE. This changes what a run reads at arrival time,
-- and therefore what every seeded run does on a database that holds
-- residue from earlier runs -- which is every database we have.
--
-- THE CONVICTION (db/checks/0108 left this open; this closes it)
-- ---------------------------------------------------------------------
-- The 48-tick pair at 15:44 UTC failed determinism: both arms complete,
-- identical boot fingerprint, every canon different. Diffed by true
-- insertion order (decision_seq), the two arms are BYTE-IDENTICAL for
-- the first 59 decisions of tick 1 and fork at position 60: the arm
-- that ran SECOND (3226179e) never emits the flow-contract amend_plan
-- for vehicle a1111111-...-0003 that the first arm, and both arms of the
-- 12-tick pair 24 minutes earlier, all emit.
--
-- amend_plan fires in twin.ottoq_sim_advance_flow_contract when a
-- vehicle holds a 'planned' leg more than 20 minutes late. In the
-- second arm, vehicle 0003's first service legs were planned at
--
--     2026-09-02 00:28:35.348786   (inspect)
--     2026-09-02 00:38:35.348786   (wash)
--     2026-09-02 00:46:35.348786   (inspect)
--
-- 22.5 sim-hours after it arrived. A leg planned that far ahead can
-- never be "late". Those six decimal places are a fingerprint: the same
-- instant exists in exactly one other place in the database --
--
--     ottoq_vehicle_dispatches, run efd467d4 (the FIRST arm),
--     vehicle 0003, dispatched 23:00, status 'aborted',
--     return_trigger 'run_stopped', scheduled_return_at
--     2026-09-02 00:28:35.348786, actual_return_at NULL.
--
-- The first arm re-dispatched the car at 23:00 and ended at 02:00 before
-- it came back. Teardown marked that dispatch aborted with a NULL return
-- (correctly, per 0181). Neither ottoq_tick_invariance_reset_fleet nor
-- ottoq_sim_stop_and_reset touches ottoq_vehicle_dispatches, so the row
-- survived into the second arm. And the second arm read it:
--
--   ottoq.ottoq_sim_prearrival_contracts, for each inbound vehicle:
--
--     SELECT COALESCE(MAX(d.scheduled_return_at), p_clock) INTO v_eta
--       FROM ottoq_vehicle_dispatches d
--      WHERE d.vehicle_id = v_rec.vehicle_id
--        AND d.actual_return_at IS NULL;              -- no sim_run_id
--     PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.vehicle_id,
--                                        GREATEST(p_clock, v_eta));
--
-- MAX() across every run that ever dispatched the car. The first arm's
-- unreturned 23:00 dispatch wins, the ETA becomes 00:28:35 the next day,
-- the itinerary is planned from there, and the arms diverge. A second
-- read three statements later (MIN(d.scheduled_return_at) AS eta_at,
-- same predicate) has the same defect.
--
-- This is the eighth instance of the class that runs 0145 -> 0053 ->
-- 0054 -> 0177 -> 0180 -> 0184 -> 0106: a run-scoped table read without
-- the run.
--
-- WHY IT HID, AND WHY IT SURFACED TODAY
-- ---------------------------------------------------------------------
-- The read is old. It only matters when a row exists with
-- actual_return_at NULL for a car that a LATER run will bring inbound,
-- and with a scheduled_return_at in that run's future. Three things had
-- to line up:
--
--  1. 0181 (2026-09-03 22:52). Before it, teardown stamped every
--     unreturned dispatch 'completed' with actual_return_at = now() -- a
--     lie (0181's finding), but a lie that left no NULL to read. 0181
--     made teardown honest: status aborted, actual_return_at NULL. The
--     residue class was born at that moment. The first rows appeared at
--     00:36 on 2026-09-04, left by round 13's 24-tick arms.
--  2. A first arm long enough to re-dispatch a car and end before it
--     returns. A 12-tick arm ends at 08:00 sim, before the first
--     redeploy of the day; it leaves nothing. A 24-tick arm left 3 rows.
--     A 48-tick arm leaves 20-31.
--  3. 0192, which unparked the fleet so cars are re-dispatched at all.
--
-- None of the three is the defect. 0181 was correct. 0192 was correct.
-- The horizon is a number. The defect is the missing predicate.
--
-- THE HARNESS COULD NOT SEE IT, AND STILL CANNOT ON ITS OWN
-- ---------------------------------------------------------------------
-- Two facts that matter more than this one bug:
--
--  a. The boot fingerprint counts other-run dispatch rows as 'fgn' only
--     when status IN ('active','returning'). An 'aborted' row with a NULL
--     return is exactly what 0181 creates and exactly what prearrival
--     reads, and it is invisible to the fingerprint. Both arms of the
--     failing pair reported fgn n = 0.
--
--  b. The REPEAT 48-tick pair at 16:29 PASSED -- equal on every canon --
--     with 61 tick-1 decisions per arm against 63 in the clean arm, and
--     neither arm amending vehicle 0003. It passed because by then the
--     residue already existed for BOTH arms. A pair only goes red when
--     the first arm CREATES residue the second arm then reads; when the
--     residue predates the pair, both arms are equally contaminated and
--     the verdict is green. A green pair is not evidence of determinism
--     on a database with residue in it.
--
-- Today there are 109 null-return dispatch rows across 42 flagship
-- vehicles from 6 finished runs, all post-0181. Every certification pair
-- since 00:36 today ran against some of them. Round 13's 12-tick columns
-- (23:16 the previous night) predate all residue and are clean; its
-- 24-tick columns ran with 3 rows and may be contaminated-but-equal;
-- today's 12-tick pair (15:20) ran with 6 rows, which means 0107's
-- reading of its canon shift as "0192 moved it" is confounded and is
-- corrected beneath 0107.
--
-- WHAT THIS MIGRATION DOES, AND DOES NOT
-- ---------------------------------------------------------------------
-- DOES: scopes the two reads in prearrival_contracts and one same-class
-- read in the manifest generator (a 'carried_over' visit looked up by
-- vehicle alone -- no residue today, same defect, same function already
-- holds p_sim_run_id). All three use the 0124 idiom already present in
-- the same functions, so production (NULL run) behaves as before.
--
-- DOES NOT widen the fingerprint. After this fix the engine no longer
-- reads other runs' dispatches, so a fingerprint that flagged them would
-- turn every pair red on any non-pristine database while the engine is
-- in fact deterministic. The defence against the NEXT unscoped read is
-- the census assertion below, which refuses this migration if any
-- tick-path function still reads the table unscoped -- and the
-- inter-pair test in the prediction, which no fingerprint can replace.
--
-- DOES NOT delete residue. Those rows are true history: the run ended
-- and the car had not returned. The ledger keeps them.
--
-- DOES NOT touch ottoq_reconcile_charger_states, which reads 'active'
-- ocpp_sessions by stall without a run. Zero such residue exists today,
-- the function takes only a depot id, and scoping it is a signature
-- change. Recorded here as the next instance to close, with evidence to
-- convict it still to be gathered rather than assumed.
-- =====================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. THE THREE ANCHORED EDITS
-- ─────────────────────────────────────────────────────────────────────
DO $mig$
DECLARE
  v_src text; v_n int;
  v_idiom_d  text := ' AND COALESCE(d.sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid) = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid) /* 0193 */';
  v_idiom_nk text := ' AND COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid) = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid) /* 0193 */';
  v_a1 text := 'WHERE d.vehicle_id = v_rec.vehicle_id AND d.actual_return_at IS NULL;';
  v_a2 text := 'WHERE d.vehicle_id = v.id AND d.actual_return_at IS NULL) AS eta_at';
  v_a3 text := 'WHERE vehicle_id = p_vehicle_id AND status = ''carried_over''';
BEGIN
  -- prearrival_contracts: two reads, one function
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_sim_prearrival_contracts';
  IF v_src IS NULL THEN RAISE EXCEPTION '0193: ottoq.ottoq_sim_prearrival_contracts not found'; END IF;
  IF position('/* 0193 */' in v_src) > 0 THEN
    RAISE EXCEPTION '0193: prearrival already carries a 0193 edit - refusing to double-apply';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, v_a1, ''))) / length(v_a1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0193: anchor A1 occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_a2, ''))) / length(v_a2);
  IF v_n <> 1 THEN RAISE EXCEPTION '0193: anchor A2 occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_a1,
             'WHERE d.vehicle_id = v_rec.vehicle_id AND d.actual_return_at IS NULL' || v_idiom_d || ';');
  v_src := replace(v_src, v_a2,
             'WHERE d.vehicle_id = v.id AND d.actual_return_at IS NULL' || v_idiom_d || ') AS eta_at');
  EXECUTE v_src;

  -- manifest generator: the carried_over lookup
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_generate_service_manifest';
  IF v_src IS NULL THEN RAISE EXCEPTION '0193: twin.ottoq_sim_generate_service_manifest not found'; END IF;
  IF position('/* 0193 */' in v_src) > 0 THEN
    RAISE EXCEPTION '0193: manifest generator already carries a 0193 edit - refusing to double-apply';
  END IF;
  IF position('ottoq_atoms_guard' in v_src) = 0 THEN
    RAISE EXCEPTION '0193: manifest generator has lost its 0192 guard - refusing to edit a body that is not the one certified';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, v_a3, ''))) / length(v_a3);
  IF v_n <> 1 THEN RAISE EXCEPTION '0193: anchor A3 occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_a3, v_a3 || v_idiom_nk);
  EXECUTE v_src;
END
$mig$;

-- ─────────────────────────────────────────────────────────────────────
-- 2. THE ASSERTIONS -- A CHECK THAT CANNOT FAIL IS NOT A CHECK
-- ─────────────────────────────────────────────────────────────────────
DO $assert$
DECLARE
  v_src text; v_n int;
  v_scoped   timestamptz;
  v_unscoped timestamptz;
  v_bad      text[];
BEGIN
  -- A1. Post-edit shape: prearrival has exactly two dispatch reads and
  --     exactly two 0193 markers; the manifest generator exactly one.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_sim_prearrival_contracts';
  v_n := (length(v_src) - length(replace(v_src, 'ottoq_vehicle_dispatches', ''))) / length('ottoq_vehicle_dispatches');
  IF v_n <> 2 THEN RAISE EXCEPTION '0193 A1 FAILED: prearrival dispatch reads = %, expected 2', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, '/* 0193 */', ''))) / length('/* 0193 */');
  IF v_n <> 2 THEN RAISE EXCEPTION '0193 A1 FAILED: prearrival 0193 markers = %, expected 2', v_n; END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_generate_service_manifest';
  v_n := (length(v_src) - length(replace(v_src, '/* 0193 */', ''))) / length('/* 0193 */');
  IF v_n <> 1 THEN RAISE EXCEPTION '0193 A1 FAILED: manifest 0193 markers = %, expected 1', v_n; END IF;

  -- A2. The predicate discriminates on LIVE data. For vehicle 0003 and a
  --     run id that has never existed, the scoped read must find nothing.
  --     The unscoped value is reported, not asserted: this migration must
  --     not depend on residue being present to apply.
  SELECT MAX(d.scheduled_return_at) INTO v_unscoped
    FROM ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = 'a1111111-0001-0001-0001-000000000003'
     AND d.actual_return_at IS NULL;
  SELECT MAX(d.scheduled_return_at) INTO v_scoped
    FROM ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = 'a1111111-0001-0001-0001-000000000003'
     AND d.actual_return_at IS NULL
     AND COALESCE(d.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE('ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
  IF v_scoped IS NOT NULL THEN
    RAISE EXCEPTION '0193 A2 FAILED: scoped read for a nonexistent run returned %', v_scoped;
  END IF;
  RAISE NOTICE '0193 A2: unscoped MAX(scheduled_return_at) for vehicle 0003 = % (the value the old code would have used); scoped = NULL',
    COALESCE(v_unscoped::text, '(no residue)');

  -- A3. THE CLASS, NOT THE INSTANCE. No function on the tick path may read
  --     ottoq_vehicle_dispatches without sim_run_id in the same statement.
  --     Statement = text from the FROM/JOIN to the first ';'. Allowed
  --     without a run: primary-key lookups by dispatch_id, and the boot
  --     fingerprint, which is depot-wide by design. Anything else refuses
  --     this migration, which is the point.
  WITH tick_fns AS (
    SELECT DISTINCT callee FROM (
      SELECT (regexp_match(m.line, '(ottoq_[a-z0-9_]+)\s*\('))[1] AS callee
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        CROSS JOIN LATERAL regexp_split_to_table(pg_get_functiondef(p.oid), E'\n') WITH ORDINALITY AS m(line, ord)
       WHERE n.nspname IN ('public','twin')
         AND p.proname IN ('ottoq_sim_advance_tick_world','ottoq_sim_decide_and_dispatch','ottoq_sim_advance_tick')
         AND m.line ~ '(PERFORM|:=|SELECT)\s.*ottoq_[a-z0-9_]+\s*\(' AND m.line !~ '^\s*--') q
     WHERE callee IS NOT NULL),
  fns AS (
    SELECT n.nspname||'.'||p.proname AS fn, pg_get_functiondef(p.oid) AS src
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind='f'
       AND (p.proname IN (SELECT callee FROM tick_fns)
            OR p.proname IN ('ottoq_sim_prearrival_contracts','ottoq_plan_visit_itinerary',
                             'ottoq_sim_generate_service_manifest','ottoq_book_appointment',
                             'ottoq_return_eta_minutes','ottoq_sim_advance_flow_contract'))
       AND p.proname <> 'ottoq_boot_state_fingerprint'),
  occ AS (
    SELECT f.fn, g AS occ_n, f.src,
           regexp_instr(f.src, '(FROM|JOIN)\s+(public\.)?ottoq_vehicle_dispatches', 1, g) AS pos
      FROM fns f, generate_series(1, 12) g),
  sl AS (
    SELECT fn, occ_n,
           substring(src FROM pos FOR GREATEST(1, position(';' in substring(src FROM pos)) - 1)) AS stmt
      FROM occ WHERE pos > 0)
  SELECT COALESCE(array_agg(fn||'#'||occ_n ORDER BY fn, occ_n), ARRAY[]::text[]) INTO v_bad
    FROM sl
   WHERE NOT (stmt ~ 'sim_run_id')
     AND NOT (stmt ~ 'dispatch_id\s*=\s*(p_dispatch_id|ANY\s*\(\s*p_dispatch_ids)');
  IF array_length(v_bad, 1) > 0 THEN
    RAISE EXCEPTION '0193 A3 FAILED: tick-path reads of ottoq_vehicle_dispatches still unscoped: %', v_bad;
  END IF;

  RAISE NOTICE '0193: all assertions passed.';
END
$assert$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. LINEAGE
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0193_the_eta_was_read_from_every_run_that_ever_dispatched_the_car', TRUE,
  'Root cause of the 15:44 UTC 48-tick pair failure (db/checks/0108). ottoq.ottoq_sim_prearrival_contracts computed each inbound '
  'vehicle''s ETA as MAX(scheduled_return_at) over ottoq_vehicle_dispatches filtered by vehicle and actual_return_at IS NULL with no '
  'sim_run_id, so the second arm read the first arm''s unreturned 23:00 dispatch for vehicle 0003 (aborted at teardown per 0181, '
  'return NULL) and planned that vehicle''s first legs at 2026-09-02 00:28:35.348786, where they could never be late; the arms fork '
  'at decision 60 of tick 1 on exactly that amend_plan. Eighth instance of the unscoped-read class (0145/0053/0054/0177/0180/0184/0106). '
  'The read is old; 0181 created the residue class by making teardown honest; 0192 made the fleet cycle enough for a 48-tick first arm '
  'to leave 20-31 such rows; none of the three is the defect. Three anchored edits: both prearrival reads and the manifest generator''s '
  'carried_over lookup, all with the 0124 NULL-safe idiom already used in the same functions. Assertion A2 proves the predicate excludes '
  'the live residue for a nonexistent run; A3 refuses the migration if any tick-path function still reads the table unscoped, '
  'PK lookups and the depot-wide fingerprint excepted. The fingerprint is deliberately NOT widened: after this fix the engine reads no '
  'other-run dispatch, so flagging residue would redden pairs on every non-pristine database while the engine is deterministic. '
  'Recorded: the repeat 48-tick pair at 16:29 PASSED because both arms read the same pre-existing residue - a green pair is not '
  'evidence of determinism on a database with residue in it; only inter-pair reproducibility is. 109 null-return rows across 42 '
  'vehicles from 6 post-0181 runs exist today; round 13''s 12-tick canons predate all of them, its 24-tick canons ran with 3 rows, '
  'today''s 12-tick pair ran with 6, so 0107''s attribution of that canon shift to 0192 alone is confounded and corrected. '
  'forces_recert=TRUE: every column must be re-established on the scoped read, and the proof is two consecutive 48-tick pairs that '
  'agree with each other, not merely within themselves.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-04 ~17:08 UTC. All assertions passed:
--   A1  prearrival: 2 dispatch reads, 2 markers; manifest: 1 marker;
--       the 0192 guard verified present before editing.
--   A2  scoped MAX() for vehicle 0003 against a nonexistent run = NULL;
--       the unscoped value the old code would have used was reported.
--   A3  no tick-path function reads ottoq_vehicle_dispatches unscoped
--       (PK lookups and the depot-wide fingerprint excepted).
--   lineage forces_recert = true.
-- Two 48-tick proof pairs scheduled back-to-back, non-overlapping.
--
-- =====================================================================
-- THE PREDICTION (published before the round)
-- =====================================================================
-- 1. Two consecutive 48-tick pairs at busy_day/171717/flagship, run
--    after this migration with the 109-row residue left in place, each
--    agree internally AND agree with each other on fp, h_cmd, h_dec,
--    h_bkg, h_nrg and endst. The second pair runs with strictly more
--    residue than the first (the first pair's own rows). If they differ,
--    there is another residue channel, and it is named by the same
--    decision_seq diff that named this one.
-- 2. Both arms of both pairs emit amend_plan for vehicle 0003 at tick 1
--    and record 63 tick-1 decisions, matching the clean arm of the 15:44
--    pair (efd467d4) -- because on a scoped read, residue is invisible
--    and the run behaves as if the database were pristine.
-- 3. Vehicle 0003's first service legs in every arm are planned in the
--    02:00-03:00 sim window, not on 2026-09-02.
-- 4. The 12-tick canon changes from today's 15:20 value (which read
--    6 rows of round-13 residue). Whether it returns to round 13's
--    23:16 value is NOT predicted: 0192 also moved it, and the two
--    causes cannot be separated from here.
-- =====================================================================
