-- migration-version: 20260919154650
-- migration-name:    the_purge_cannot_complete_and_the_twin_start_door_has_no_handler
--
-- 0344  ottoq_purge_prior_runs RAISES, ottoq_start_demo_run DOES NOT CATCH IT,
--       AND THE REASON IS A GUARD ASKING A COLUMN FOR A KEY IT CANNOT HAVE.
--
-- PROVEN 2026-09-19, in a transaction that was then aborted. The probe reproduces
-- the purge's own step (1) arming -- without which every DELETE hits an
-- append-only guard and the probe measures the guard instead of the constraint,
-- which is how an earlier attempt of mine produced an artifact and had to be
-- retracted (G63's original note):
--
--   run af2def1b: 3,592 engine rows cleared by step (4), 2 fire-log rows remain,
--   step (5) -> SQLSTATE 23503
--   "update or delete on table ottoq_sim_runs violates foreign key constraint
--    ottoq_proposer_fire_log_sim_run_id_fkey on table ottoq_proposer_fire_log"
--
-- So the purge cannot complete. `ottoq_start_demo_run` calls it at line 47 with
-- NO exception handler around it, so the raise propagates and the whole start
-- rolls back. Measured consequence: two attempts to start a run from a SQL client
-- produced no run row at all. THE TWIN'S START BUTTON IS BROKEN THROUGH THIS
-- DOOR, which is the blocker on demonstrating the agent/solver/kernel loop at
-- all -- the thing this build track exists to demonstrate.
--
-- ── THE CAUSE IS G61, AND IT IS NOT THE FOREIGN KEY'S FAULT ──────────────────
--
-- `ottoq_proposer_fire_log` is registered TWICE:
--   sim_run_id -> class 'evidence'  (0260: "every proposer sentence is quantified
--                                     from it, so it must survive its run")
--   tick_seq   -> class 'stamp'     (0260: "Provenance, not a scoping key;
--                                     sim_run_id is.")
--
-- The registry is PER-COLUMN. `ottoq_check_run_scope_registry` check (b) is
-- PER-TABLE: it reads "does this TABLE have an FK to ottoq_sim_runs" for every
-- engine/stamp ROW. So the `tick_seq` stamp row demands an FK -- and 0267 duly
-- added one -- while the `sim_run_id` evidence row's entire purpose requires the
-- table to outlive the run. The table was required to block the purge it was
-- registered to survive.
--
-- And note WHAT tick_seq IS. It is an integer tick counter. It is not a key into
-- ottoq_sim_runs and no foreign key on it could ever exist. The registry's own
-- note says so in as many words. Check (b) was asking a column for a constraint
-- that is not merely absent but impossible, and the only way to satisfy it was
-- to put the constraint somewhere else on the table, where it did damage.
--
-- ── THE FIX, AND WHY IT LOSES NO PROTECTION ─────────────────────────────────
--
-- Check (b) is SPLIT rather than weakened:
--   (b1) EXISTENCE, unchanged and still over EVERY engine/stamp row: a registered
--        table that has been dropped is still a blocking defect.
--   (b2) THE FK REQUIREMENT, now only for rows whose column is an actual
--        run-scoping key -- the same four names check (a) watches
--        (sim_run_id, run_id, owning_sim_run_id, source_run_id). A stamp row on
--        a non-key column is exempt, because orphaning is impossible through a
--        column that does not reference the parent.
--
-- MEASURED BLAST RADIUS, so this is a scalpel and not a loosened bolt. Exactly
-- TWO registry rows are engine/stamp on a non-run-key column:
--   ottoq_external_proposals.tick_seq (stamp) -- its table ALSO has sim_run_id
--     class 'engine', so (b2) still demands its FK. Nothing changes for it.
--   ottoq_proposer_fire_log.tick_seq  (stamp) -- its table's sim_run_id is
--     'evidence', so after the split nothing demands an FK. That is the one row
--     this file exists to exempt.
-- So the requirement changes for ONE table, and it is the table whose evidence
-- classification requires the change. A5 asserts ottoq_external_proposals is
-- still required to keep its FK, and still has it.
--
-- The direction is also safe by construction: (b2) considers FEWER rows than (b)
-- did, so it can only turn a block into a non-block. It cannot invent one.
--
-- Then, and only then, the FK goes. Its definition is snapshotted first.
--
-- ── AND THE ASSERTION THAT MATTERS IS AN EXECUTION, NOT AN ARGUMENT ──────────
--
-- A4 re-runs the proven-failing probe INSIDE this migration, in a subtransaction
-- it rolls back: arm retention, clear step (4) for a doomed run that carries
-- fire-log rows, then attempt step (5). It must now SUCCEED. If some second
-- constraint sits behind the first, A4 fails and names it -- which is the honest
-- outcome, because my two full-purge attempts timed out at 60 seconds rather than
-- erroring, so I have never seen past this blocker and will not claim to have.
--
-- NOT ADDRESSED HERE, deliberately. The purge is also SLOW: 1,246 accumulated
-- runs against 47 engine tables. That is a 60-second CLIENT ceiling, not a proven
-- engine limit -- the OTTO-Twin button started runs on 2026-09-17 with a
-- comparable backlog. Bounding the purge would be fixing something not yet proven
-- broken, so it stays open and measured rather than pre-emptively rebuilt.
-- Nothing here deletes anything: the founder has not authorised purging 1,238
-- runs, and this file does not.
--
-- forces_recert: FALSE. One guard function is narrowed and one constraint is
-- removed. No tick-path object, no decide path, no proposer, no frame. A6 asserts
-- the guard still reports zero blocking defects, which is the precondition the
-- purge itself checks at step (2).

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int; v_block int; v_exempt int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0344 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0344 P-: % certification pair(s) are active', v_pairs; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0344 P-: % Twin run(s) are active', v_runs; END IF;

  -- P1. The guard must be clean BEFORE this file, or a later failure cannot be
  -- attributed to it.
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry()
   WHERE severity='block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0344 P1: the registry guard already reports % blocking defect(s)', v_block;
  END IF;

  -- P2. The constraint this file removes must be exactly the one the probe
  -- caught: present, NO ACTION, on ottoq_proposer_fire_log.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname='ottoq_proposer_fire_log_sim_run_id_fkey'
                    AND conrelid='public.ottoq_proposer_fire_log'::regclass
                    AND confrelid='public.ottoq_sim_runs'::regclass
                    AND confdeltype='a') THEN
    RAISE EXCEPTION '0344 P2: the fire-log FK is not the NO ACTION one the probe caught';
  END IF;

  -- P3. THE CLASSIFICATION THAT MAKES THIS CORRECT. sim_run_id evidence,
  -- tick_seq stamp. If either has moved, the argument above no longer holds.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name='ottoq_proposer_fire_log' AND column_name='sim_run_id'
                    AND class='evidence')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                     WHERE table_name='ottoq_proposer_fire_log' AND column_name='tick_seq'
                       AND class='stamp') THEN
    RAISE EXCEPTION '0344 P3: ottoq_proposer_fire_log is not registered evidence+stamp as this file assumes';
  END IF;

  -- P4. THE BLAST RADIUS, ASSERTED RATHER THAN BELIEVED. Exactly two engine/stamp
  -- rows sit on a non-run-key column. If a third appeared since measuring, the
  -- "scalpel" claim in the header is no longer true and this must be re-reasoned.
  SELECT count(*) INTO v_exempt FROM public.ottoq_run_scope_registry
   WHERE class IN ('engine','stamp')
     AND column_name NOT IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id');
  IF v_exempt <> 2 THEN
    RAISE EXCEPTION '0344 P4: % engine/stamp rows sit on a non-run-key column, expected exactly 2', v_exempt;
  END IF;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0344-pre', 'function', 'public', 'ottoq_check_run_scope_registry()',
       pg_get_functiondef('public.ottoq_check_run_scope_registry()'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_check_run_scope_registry()'::regprocedure));

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0344-pre', 'constraint', 'public', 'ottoq_proposer_fire_log_sim_run_id_fkey',
       pg_get_constraintdef(oid), md5(pg_get_constraintdef(oid))
  FROM pg_constraint WHERE conname='ottoq_proposer_fire_log_sim_run_id_fkey';

-- ── the guard stops asking a tick counter for a foreign key ──────────────────
CREATE OR REPLACE FUNCTION public.ottoq_check_run_scope_registry()
RETURNS TABLE(table_schema text, table_name text, column_name text, problem text, severity text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- (a) a run-scoped column that nobody has classified
  SELECT c.table_schema::text, c.table_name::text, c.column_name::text,
         'unregistered run-scoped column'::text, 'warn'::text
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('public','proof_0015')
     AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_schema = c.table_schema
                        AND g.table_name   = c.table_name
                        AND g.column_name  = c.column_name)
  UNION ALL
  -- (b1) EXISTENCE. Unchanged, and still over EVERY engine/stamp row: a
  --      registered table that has been dropped is a blocking defect whatever
  --      column the row names. to_regclass (not a ::regclass cast) is deliberate:
  --      the cast RAISES on a dropped table, and the purge calls this guard, so
  --      one dropped scratch table would have made every run start fail.
  SELECT g.table_schema, g.table_name, g.column_name,
         'registered engine/stamp table no longer exists',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NULL
  UNION ALL
  -- (b2) THE FK REQUIREMENT, narrowed by 0344 to rows whose column is an actual
  --      run-scoping key -- the same four names (a) watches.
  --
  --      WHY. The registry is per-COLUMN; this check was per-TABLE. So
  --      ottoq_proposer_fire_log.tick_seq, class 'stamp', demanded an FK to
  --      ottoq_sim_runs -- while the same table's sim_run_id is class 'evidence'
  --      and must OUTLIVE the run. 0267 satisfied the demand by adding the FK,
  --      and that FK then made ottoq_purge_prior_runs step (5) raise 23503,
  --      which made ottoq_start_demo_run raise, which broke the Twin's start
  --      door. The table was required to block the purge it was registered to
  --      survive.
  --
  --      tick_seq is an integer tick counter. It is not a key into
  --      ottoq_sim_runs and no FK on it could exist -- the registry's own note
  --      says "Provenance, not a scoping key; sim_run_id is." Orphaning is
  --      impossible through a column that does not reference the parent, so no
  --      protection is lost. This considers strictly FEWER rows than before, so
  --      it cannot invent a block; and 0344 A5 asserts the one other affected
  --      table, ottoq_external_proposals, is still required to keep its FK by
  --      its own engine-class sim_run_id row.
  SELECT g.table_schema, g.table_name, g.column_name,
         'engine/stamp run-key column''s table has no FK to ottoq_sim_runs',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND g.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint k
        WHERE k.contype = 'f'
          AND k.conrelid = to_regclass(g.table_schema||'.'||g.table_name)
          AND k.confrelid = 'public.ottoq_sim_runs'::regclass)
  UNION ALL
  -- (c) any FK to the run table that has become CASCADE
  SELECT n.nspname::text, c.relname::text, 'sim_run_id'::text,
         'FK to ottoq_sim_runs is ON DELETE CASCADE — history can be silently erased',
         'block'
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE k.contype = 'f'
     AND k.confrelid = 'public.ottoq_sim_runs'::regclass
     AND k.confdeltype = 'c';
$function$;

COMMENT ON FUNCTION public.ottoq_check_run_scope_registry() IS
'The run-scope guard ottoq_purge_prior_runs calls at its step (2). (a) warns on an unclassified run-scoped column. (b1) blocks on a registered engine/stamp table that no longer exists. (b2) blocks on an engine/stamp RUN-KEY column whose table has no FK to ottoq_sim_runs. (c) blocks on a CASCADE FK to ottoq_sim_runs. 0344 SPLIT the old (b), which was per-TABLE while this registry is per-COLUMN: ottoq_proposer_fire_log.tick_seq, class stamp, demanded an FK that only sim_run_id could carry -- and that table''s sim_run_id is class evidence and must outlive its run. 0267 added the FK to satisfy the demand; the FK then made purge step (5) raise 23503, which made ottoq_start_demo_run raise, which broke the Twin start door. tick_seq is a tick counter, cannot reference the parent, and so cannot orphan anything -- exempting it loses no protection, and (b2) considers strictly fewer rows than (b) did, so it can only turn a block into a non-block.';

-- ── and now the FK can go ────────────────────────────────────────────────────
ALTER TABLE public.ottoq_proposer_fire_log
  DROP CONSTRAINT ottoq_proposer_fire_log_sim_run_id_fkey;

DO $assertions$
DECLARE
  v_block int; v_run uuid; r record; v_n bigint; v_cleared bigint := 0;
  v_state text; v_msg text; v_fire int;
BEGIN
  -- A1. The FK is gone and the evidence rows are still there. An FK drop must not
  -- have taken data with it.
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conname='ottoq_proposer_fire_log_sim_run_id_fkey') THEN
    RAISE EXCEPTION '0344 A1a: the FK is still present';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_proposer_fire_log) = 0 THEN
    RAISE EXCEPTION '0344 A1b: the fire log is empty — the drop took rows with it';
  END IF;

  -- A2. The guard is clean, which is exactly the purge's step (2) precondition.
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry()
   WHERE severity='block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0344 A2: the guard reports % blocking defect(s) after the fix', v_block;
  END IF;

  -- A3. (b1) still bites. Proven by construction rather than by reading: a
  -- registered engine row naming a table that does not exist must still block.
  -- Inserted and rolled back so the registry is untouched.
  BEGIN
    INSERT INTO public.ottoq_run_scope_registry
      (table_schema, table_name, column_name, class, note)
    VALUES ('public','ottoq_0344_no_such_table','sim_run_id','engine','0344 A3 probe');
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry()
                    WHERE severity='block' AND table_name='ottoq_0344_no_such_table') THEN
      RAISE EXCEPTION '0344 A3: (b1) no longer blocks on a registered table that does not exist';
    END IF;
    RAISE EXCEPTION 'ROLLBACK_A3';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'ROLLBACK_A3' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
              WHERE table_name='ottoq_0344_no_such_table') THEN
    RAISE EXCEPTION '0344 A3b: the A3 probe leaked a registry row';
  END IF;

  -- A4. THE ONE THAT MATTERS, AND IT IS AN EXECUTION. Re-run the probe that
  -- proved the blocker, in a subtransaction that is then rolled back. Step (5)
  -- must now succeed. If a second constraint sits behind the first, this fails
  -- and names it — which is the honest outcome, because the full purge has never
  -- been observed past this point.
  SELECT f.sim_run_id INTO v_run
    FROM public.ottoq_proposer_fire_log f
    JOIN public.ottoq_sim_runs s ON s.sim_run_id = f.sim_run_id
   WHERE COALESCE(s.run_by,'') <> 'production_live' AND s.status <> 'running'
   LIMIT 1;

  IF v_run IS NULL THEN
    RAISE WARNING '0344 A4: SKIPPED — no doomed run carries fire-log rows, so the blocker cannot be reproduced here';
  ELSE
    SELECT count(*) INTO v_fire FROM public.ottoq_proposer_fire_log WHERE sim_run_id = v_run;
    BEGIN
      PERFORM set_config('ottoq.retention', 'on', true);
      FOR r IN SELECT table_name t, column_name c FROM public.ottoq_run_scope_registry
                WHERE class='engine' ORDER BY table_name
      LOOP
        EXECUTE format('DELETE FROM public.%1$I WHERE %2$I = $1', r.t, r.c) USING v_run;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_cleared := v_cleared + v_n;
      END LOOP;
      DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
      v_state := 'ok';
      -- the fire-log rows must SURVIVE the parent's deletion: that is the whole
      -- point of the evidence class, and an FK drop that let them vanish would be
      -- the opposite of the fix.
      IF (SELECT count(*) FROM public.ottoq_proposer_fire_log WHERE sim_run_id = v_run) <> v_fire THEN
        v_state := 'evidence_lost';
      END IF;
      RAISE EXCEPTION 'ROLLBACK_A4';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM = 'ROLLBACK_A4' THEN
        NULL;
      ELSE
        v_state := SQLSTATE; v_msg := left(SQLERRM, 200);
      END IF;
    END;

    IF v_state = 'evidence_lost' THEN
      RAISE EXCEPTION '0344 A4a: the parent delete succeeded but took the evidence rows with it';
    END IF;
    IF v_state <> 'ok' THEN
      RAISE EXCEPTION '0344 A4b: purge step (5) still fails after the fix — state=% msg=% (a second constraint sits behind the fire log)',
        v_state, v_msg;
    END IF;
    RAISE NOTICE '0344 A4: purge step (5) now completes (run %, % engine rows, % evidence rows survived)',
      v_run, v_cleared, v_fire;
  END IF;

  -- A5. The other table the narrowing touches is STILL protected, by its own
  -- engine-class row. This is the assertion that keeps (b2) a scalpel.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name='ottoq_external_proposals' AND column_name='sim_run_id'
                    AND class='engine') THEN
    RAISE EXCEPTION '0344 A5a: ottoq_external_proposals.sim_run_id is no longer engine-class';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE contype='f' AND conrelid='public.ottoq_external_proposals'::regclass
                    AND confrelid='public.ottoq_sim_runs'::regclass) THEN
    RAISE EXCEPTION '0344 A5b: ottoq_external_proposals lost its FK and the guard did not catch it';
  END IF;
  -- and prove (b2) would catch that loss, rather than trusting it: temporarily
  -- reclassify a real engine row onto a table with no FK and require a block.
  BEGIN
    INSERT INTO public.ottoq_run_scope_registry
      (table_schema, table_name, column_name, class, note)
    VALUES ('public','ottoq_proposer_fire_log','run_id','engine','0344 A5 probe');
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry()
                    WHERE severity='block' AND table_name='ottoq_proposer_fire_log') THEN
      RAISE EXCEPTION '0344 A5c: (b2) does not block an engine run-key column whose table has no FK';
    END IF;
    RAISE EXCEPTION 'ROLLBACK_A5';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'ROLLBACK_A5' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
              WHERE table_name='ottoq_proposer_fire_log' AND column_name='run_id') THEN
    RAISE EXCEPTION '0344 A5d: the A5 probe leaked a registry row';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0344_the_purge_cannot_complete_and_the_twin_start_door_has_no_handler', false,
  'ottoq_purge_prior_runs raised 23503 at step (5) on ottoq_proposer_fire_log''s FK, and ottoq_start_demo_run has no handler, so the Twin start door was broken. Splits ottoq_check_run_scope_registry check (b) into existence (all engine/stamp rows, unchanged) and FK-required (run-key columns only), which stops a stamp row on a tick counter demanding a foreign key only sim_run_id could carry; then drops that FK. Measured blast radius is one table. No tick-path object touched; A4 proves step (5) now completes and the evidence rows survive it, in a rolled-back subtransaction. Recertification not required.',
  now())
ON CONFLICT(name) DO NOTHING;
