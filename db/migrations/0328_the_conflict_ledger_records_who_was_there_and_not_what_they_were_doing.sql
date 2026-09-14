-- migration-version: 20260914235653
-- migration-name:    0328_the_conflict_ledger_records_who_was_there_and_not_what_they_were_doing
-- ============================================================================
-- 0328 — THE CONFLICT LEDGER RECORDS *WHO* WAS IN THE STALL AND NOT *WHAT THEY
--        WERE DOING*, SO 96% OF CONFLICTS CANNOT BE EXPLAINED FROM IT.
-- ============================================================================
-- MEASURED across twin runs 34ffb2d9 and 2235ce6e (busy_day, seeds 909090 and
-- 515151, flagship depot, 235 conflicts between them):
--
--   conflict_kind                 n    present_vehicle_id  present_vehicle_STATE
--   assignment_refused_occupied  226                 226                      0
--   stale_claim_displaced          9                   9                      9
--
-- Both writers fill `present_vehicle_id`. Only ONE fills the state:
--   ottoq.ottoq_reconcile_displace_stale_claim  -> sets it
--   ottoq.ottoq_emit_vehicle_command            -> does NOT
--
-- WHY THIS IS THE BLOCKING GAP AND NOT A COSMETIC ONE. The engine dispatches a
-- vehicle at an ALREADY-OCCUPIED stall on roughly a third of its stall-bearing
-- commands -- 116 of 347 on run 34ffb2d9, 67 of 226 on run 2235ce6e, two
-- different seeds agreeing at 33% and 30%. Nothing double-occupies, because the
-- preflight refuses every one; the cost is paid in TIME. The same two runs
-- measure p95 time-to-service at 285 and 349.5 sim-minutes against a p50 of 90
-- and 60, with a worst case of 660 and 540. Vehicles are not lost --
-- `returns_unserved` is 0 on both runs -- they WAIT.
--
-- To shorten that wait you must know which of two opposite situations the
-- blocker is in, because they need opposite fixes:
--
--   * the blocker FINISHED and has not physically left  -> the release path is
--     late: the stall is free on the calendar and occupied in reality, and the
--     answer is to command the finished vehicle out before offering the stall.
--   * the blocker is genuinely MID-SERVICE                -> the selection is
--     wrong: the kernel chose a stall that was never going to be free, and the
--     answer is in the stall-picking predicate.
--
-- `present_vehicle_state` is exactly the field that separates them, and it is
-- NULL on all 226. So the ledger built to explain who overruled whom cannot
-- explain the case it records 96% of the time. This file closes that, and
-- closes nothing else -- it changes no decision, no selection and no command.
--
-- ── THE ONE DESIGN DECISION, AND IT IS A LEFT JOIN ─────────────────────────
-- The blocker id comes from `v_check->>'blocker_vehicle_id'`, a payload value.
-- Joining `public.vehicles` INNER would mean that a blocker id which no longer
-- resolves to a row DROPS THE WHOLE LEDGER INSERT -- turning an instrumentation
-- fix into an instrumentation LOSS, silently, in exactly the contested moments
-- the ledger exists for. The join is LEFT: a missing blocker yields a NULL
-- state, which is precisely today's behaviour, so this change can only ever add
-- information and never remove a row. A3 asserts the join stays LEFT.
--
-- Scope: one INSERT's column list and its SELECT. No DROP. No new column (the
-- ledger already has `present_vehicle_state`, nullable). No behaviour change.
-- ============================================================================

DO $pre$
DECLARE v_src text; v_n int;
BEGIN
  -- P1. The function exists and still contains the exact text being replaced.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_emit_vehicle_command';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0328 P1: ottoq.ottoq_emit_vehicle_command not found';
  END IF;
  IF position('conflict_kind, resolution, present_vehicle_id, displaced_vehicle_id, detail' in v_src) = 0 THEN
    RAISE EXCEPTION '0328 P1: the ledger INSERT column list is not the one this file was written against';
  END IF;
  IF position('present_vehicle_state' in v_src) > 0 THEN
    RAISE EXCEPTION '0328 P1: the function already sets present_vehicle_state; nothing to do';
  END IF;
  RAISE NOTICE '0328 P1: emitter found, column list matches, state not yet set';

  -- P2. The target column exists and is NULLABLE -- a NOT NULL here would turn
  --     a missing blocker into a failed ledger write, the opposite of the goal.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='space_conflict_ledger'
     AND column_name='present_vehicle_state' AND is_nullable='YES';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0328 P2: space_conflict_ledger.present_vehicle_state missing or NOT NULL';
  END IF;
  RAISE NOTICE '0328 P2: present_vehicle_state exists and is nullable';

  -- P3. The gap this file closes, measured rather than asserted.
  SELECT count(*) INTO v_n FROM public.space_conflict_ledger
   WHERE conflict_kind::text='assignment_refused_occupied' AND present_vehicle_state IS NULL;
  RAISE NOTICE '0328 P3: % assignment_refused_occupied rows carry no present_vehicle_state', v_n;
END $pre$;

-- PRE-SNAPSHOT: this rewrites a live body by substitution, so the prior source
-- is captured first and the replacement is verifiable against it.
-- Columns read from information_schema before writing, not remembered: the
-- first attempt at this file invented (taken_at, reason, payload) and was
-- refused by the database with 42703. The snapshot stores the FUNCTIONDEF,
-- because that -- not prosrc -- is the text the substitution below operates on.
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0328 pre: ottoq_emit_vehicle_command before the ledger-state fix',
       'function', 'ottoq', 'ottoq_emit_vehicle_command',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ottoq' AND p.proname='ottoq_emit_vehicle_command';

DO $sub$
DECLARE v_def text; v_new text;
  a_old text := E'           conflict_kind, resolution, present_vehicle_id, displaced_vehicle_id, detail)\n';
  a_new text := E'           conflict_kind, resolution, present_vehicle_id, present_vehicle_state,\n'
             || E'           displaced_vehicle_id, detail)\n';
  b_old text := E'               (v_check->>''blocker_vehicle_id'')::uuid, p_vehicle,\n';
  b_new text := E'               (v_check->>''blocker_vehicle_id'')::uuid,\n'
             || E'               -- 0328: WHAT the blocker was doing, not merely who it was. NULL here\n'
             || E'               -- still means "could not resolve the blocker", never "no conflict".\n'
             || E'               bv.current_state::text,\n'
             || E'               p_vehicle,\n';
  c_old text := E'  FROM public.stalls s WHERE s.id = (p_payload->>''stall_id'')::uuid;\n';
  c_new text := E'  FROM public.stalls s\n'
             || E'  -- 0328: LEFT, deliberately. An INNER join would drop the entire ledger row\n'
             || E'  -- whenever the blocker id does not resolve -- losing the record of a conflict\n'
             || E'  -- in exactly the contested moments this ledger exists to capture.\n'
             || E'  LEFT JOIN public.vehicles bv ON bv.id = (v_check->>''blocker_vehicle_id'')::uuid\n'
             || E' WHERE s.id = (p_payload->>''stall_id'')::uuid;\n';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_emit_vehicle_command';

  v_new := replace(v_def, a_old, a_new);
  IF v_new = v_def THEN RAISE EXCEPTION '0328 S1: column-list substitution changed nothing'; END IF;
  v_def := v_new;

  v_new := replace(v_def, b_old, b_new);
  IF v_new = v_def THEN RAISE EXCEPTION '0328 S2: value-list substitution changed nothing'; END IF;
  v_def := v_new;

  v_new := replace(v_def, c_old, c_new);
  IF v_new = v_def THEN RAISE EXCEPTION '0328 S3: FROM-clause substitution changed nothing'; END IF;

  EXECUTE v_new;
  RAISE NOTICE '0328: emitter replaced, three substitutions applied';
END $sub$;

DO $post$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_emit_vehicle_command';

  -- A1. The state is now written.
  IF position('present_vehicle_state' in v_src) = 0 THEN
    RAISE EXCEPTION '0328 A1: present_vehicle_state is still not set';
  END IF;
  IF position('bv.current_state' in v_src) = 0 THEN
    RAISE EXCEPTION '0328 A1: the blocker state is not read from the vehicle row';
  END IF;

  -- A2. The emitter still records the conflict at all. A fix that silences the
  --     ledger while making one column prettier is a net loss.
  IF position('assignment_refused_occupied' in v_src) = 0 THEN
    RAISE EXCEPTION '0328 A2: the emitter no longer records assignment_refused_occupied';
  END IF;

  -- A3. THE JOIN IS LEFT, and this is the assertion that matters most. An INNER
  --     join would delete conflict records instead of explaining them.
  IF v_src !~ 'LEFT JOIN public\.vehicles bv' THEN
    RAISE EXCEPTION '0328 A3: the blocker join is not a LEFT JOIN -- a missing blocker would now drop the ledger row';
  END IF;

  -- A4. The refusal row itself is untouched: this file explains conflicts, it
  --     does not change which commands are refused.
  IF position('''refused'', v_check->>''code''' in v_src) = 0 THEN
    RAISE EXCEPTION '0328 A4: the refusal write changed; this file must not alter refusal behaviour';
  END IF;

  RAISE NOTICE '0328 A1-A4: state written, conflict still recorded, join is LEFT, refusal untouched';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0328_the_conflict_ledger_records_who_was_there_and_not_what_they_were_doing', true,
   'Adds present_vehicle_state to the assignment_refused_occupied row written by '
   'ottoq.ottoq_emit_vehicle_command, via a LEFT JOIN on the blocker vehicle. Measured gap: '
   '226 such rows across runs 34ffb2d9 and 2235ce6e carry present_vehicle_id and none carry '
   'the state (285,782 whole-table), so 96% of recorded conflicts cannot be explained from the '
   'ledger -- and the state is what separates "the blocker finished and has not left" (fix the '
   'release path) from "the blocker is mid-service" (fix the selection predicate). '
   'space_conflict_ledger is NOT one of the fourteen atoms, so this SHOULD move no canon. '
   'Classified TRUE anyway on 0320''s rule: "should change nothing" is a prediction for a round '
   'to judge, not a classification. It changes no decision, no selection and no command; A4 '
   'pins the refusal write unchanged.',
   now())
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- APPLIED 20260914235653 (2026-09-14 23:56:53 UTC / 6:56 PM CT)
-- ============================================================================
-- Window: quiesced and verified first -- 0 active backends other than this one,
-- 0 engine-pattern queries, 0 active r4*/cert cron jobs.
--
-- FIRST ATTEMPT REFUSED, 42703: the snapshot INSERT named (taken_at, reason,
-- payload), a shape I wrote from memory. ottoq_schema_snapshots actually has
-- (label, object_kind, schema_name, object_name, definition, def_md5). The
-- migration is transactional, so nothing applied -- the emitter's md5 was
-- re-read afterwards and was still 1f1df91284c57936a108cc600cc43a28 with
-- present_vehicle_state absent. Corrected in 7eff50d before re-applying.
--
-- HEADER CONDENSED AT APPLY -- and here is the digest that proves it was only
-- the header. Normalising BOTH the committed file and the stored migration text
-- from `DO $pre$` onward by dropping blank lines and lines whose trimmed form
-- begins with `--`:
--
--   committed file  ->  351b9cbd522c25395f22b77a0d82b37f   6239 bytes
--   applied text    ->  351b9cbd522c25395f22b77a0d82b37f   6239 bytes
--
-- Identical. Every difference between the two is a comment line; no executable
-- text differs. (Raw, un-normalised: file body 7480 bytes, applied body 6254 --
-- the 1,226-byte gap is exactly the commentary stripped to fit the apply call.)
--
-- RESULT, measured after apply:
--   ottoq.ottoq_emit_vehicle_command  md5 1f1df912...  ->  3c19552b2e8a5edd9fa3a52246ec9543
--                                     len 3705         ->  4272
--   A1 bv.current_state::text present  : true
--   A2 assignment_refused_occupied kept: true
--   A3 LEFT JOIN public.vehicles bv    : true
--   A4 refusal write untouched         : asserted in-transaction, passed
--   pre-snapshot rows                  : 1  (def_md5 62acc28c788e55eba896293dad13aeca,
--                                            the FUNCTIONDEF, which is the text the
--                                            three substitutions operate on)
--   lineage forces_recert              : true
--
-- P3 printed the gap at apply time: 285,782 assignment_refused_occupied rows
-- carrying no present_vehicle_state. The 226 in the header is the two-run
-- scoped figure; 285,782 is the whole table since the ledger began. Both are
-- stated because they answer different questions and the smaller one is the
-- one this fix was reasoned from.
--
-- NOT YET PROVEN, and this is the next step, not a claim: that the column now
-- POPULATES on live traffic. A function body containing the assignment is not
-- a ledger row containing the state. That takes a twin run.
-- ============================================================================
