-- migration-version: 20260909133442
-- migration-name: 0248_the_refusal_ledger_was_registered_engine_without_the_key_that_makes_it_true
-- ===========================================================================
-- 0248  THE REFUSAL LEDGER WAS REGISTERED engine WITHOUT THE KEY THAT MAKES
--       IT TRUE
-- ===========================================================================
-- probe:          the first live call of ottoq_retention_purge_runs (0247)
-- forces_recert:  FALSE
--
-- HOW THIS WAS FOUND, WHICH IS THE POINT
--
-- 0247 added a purge whose step (2) refuses to run if
-- ottoq_check_run_scope_registry() reports any blocking defect -- a guard
-- borrowed from ottoq_purge_prior_runs. The very first call, a DRY RUN, refused:
--
--   ERROR: purge refused: 1 blocking run-scope defect(s).
--
-- The guard fired before the purge had counted a single row, on a defect that
-- had been sitting in the database since 0211 and that nothing else looks at.
-- A registry with no consumer is documentation; a registry with a consumer that
-- refuses to proceed is an invariant. This is the first time it acted as one.
--
-- THE DEFECT
--
--   ottoq_recall_refusals.sim_run_id | engine/stamp table has no FK to
--                                    | ottoq_sim_runs                 | block
--
-- 0211 registered ottoq_recall_refusals.sim_run_id as class='engine' and did
-- not add the foreign key. Its sibling did: ottoq_recall_decisions, registered
-- by 0206 five migrations earlier, carries
-- ottoq_recall_decisions_sim_run_id_fkey. Two halves of the same C9 ledger,
-- added a week apart, and only one of them got the key.
--
-- WHY class='engine' WITHOUT THE FK IS NOT COSMETIC. The FK is what makes
-- "these rows die with their run" enforceable rather than merely intended. With
-- NO ACTION on 47 engine tables, a run row physically cannot be deleted while
-- its children exist -- which is how ottoq_purge_prior_runs discovers that its
-- own loop missed a table instead of silently orphaning the rows. On this one
-- table that net was absent.
--
-- MEASURED 2026-09-09 13:35 UTC, before the fix: 6 rows, 0 with a NULL
-- sim_run_id, 0 orphans. So the constraint can be added and validated
-- immediately; there is nothing to quarantine first. Small table, 80 kB.
--
-- AND ONE WARN, CLEARED WHILE HERE
--
--   ottoq_layout_backup_0011_stall_bookings.sim_run_id | unregistered
--                                                      | run-scoped column | warn
--
-- A backup table left by migration 0011: 1 row, 16 kB, no function or view
-- reads it, and its single row's sim_run_id points at a run that no longer
-- exists. It is registered 'evidence' rather than dropped -- evidence is exactly
-- "a row that may outlive its run", the purge loop does not select it, and 16 kB
-- is not worth a judgement call about someone else's backup. It is also one of
-- the ~100 scratch tables CLAUDE.md Part 3 names as awaiting classification;
-- this is one of them classified.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The key 0211 omitted. Same shape as its sibling: NO ACTION, so a run row
--    refuses deletion while refusals reference it.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ottoq_recall_refusals
  ADD CONSTRAINT ottoq_recall_refusals_sim_run_id_fkey
  FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);

-- ---------------------------------------------------------------------------
-- 2. The backup table's column, classified.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_layout_backup_0011_stall_bookings', 'sim_run_id', 'evidence',
        '0248: a backup left by migration 0011 -- 1 row, 16 kB, no reader, and its '
        'sim_run_id already points at a deleted run. Classified evidence rather than '
        'dropped: evidence is precisely "may outlive its run", the engine loop does '
        'not select it, and it was the only warn standing between the registry check '
        'and a clean bill.')
ON CONFLICT (table_schema, table_name, column_name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int; v_block int; v_warn int;
BEGIN
  -- A1. The FK exists and points where it should.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid = 'public.ottoq_recall_refusals'::regclass
     AND contype = 'f'
     AND confrelid = 'public.ottoq_sim_runs'::regclass;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: expected 1 FK from ottoq_recall_refusals to ottoq_sim_runs, found %', v_n;
  END IF;

  -- A2. It is VALIDATED, not NOT VALID -- an unvalidated constraint would let the
  --     registry check pass while the existing rows stayed unchecked.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid = 'public.ottoq_recall_refusals'::regclass
     AND conname = 'ottoq_recall_refusals_sim_run_id_fkey' AND convalidated;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: the new FK is not validated';
  END IF;

  -- A3. THE ASSERTION THAT MATTERS: the registry check is now clean of blocks,
  --     which is what 0247's purge gate reads. Warns are reported, not fatal.
  SELECT count(*) FILTER (WHERE severity = 'block'),
         count(*) FILTER (WHERE severity = 'warn')
    INTO v_block, v_warn
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    RAISE EXCEPTION 'A3 FAILED: % blocking run-scope defect(s) remain; 0247''s purge will still refuse', v_block;
  END IF;
  RAISE NOTICE 'A3: run-scope registry clean -- 0 blocking, % warn(s)', v_warn;

  -- A4. The sibling still has its own key. Fixing one half must not disturb the
  --     other, and the pair is what makes the C9 ledger whole.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid = 'public.ottoq_recall_decisions'::regclass
     AND contype = 'f' AND confrelid = 'public.ottoq_sim_runs'::regclass;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A4 FAILED: ottoq_recall_decisions lost its FK to ottoq_sim_runs';
  END IF;

  -- A5. Registering the backup did not accidentally make it purgeable.
  SELECT count(*) INTO v_n FROM public.ottoq_run_scope_registry
   WHERE table_name = 'ottoq_layout_backup_0011_stall_bookings' AND class = 'engine';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A5 FAILED: the 0011 backup is classified engine and would be purged';
  END IF;

  RAISE NOTICE 'A1-A5 PASSED';
END $$;
