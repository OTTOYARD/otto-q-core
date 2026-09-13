-- migration-version: PENDING
-- migration-name:    0267_the_fire_log_registered_a_stamp_and_never_bound_it_to_a_run
--
-- 0267  THE FIRE LOG REGISTERED A STAMP AND NEVER BOUND IT TO A RUN  (G23)
--
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS, AND WHY IT IS ONE LINE OF DDL
--
-- G23's retention purge has never had its one observed pass. The reason is not
-- scheduling and not the 0251 blocker, which is closed. It is that
-- public.ottoq_retention_purge_runs REFUSES TO RUN:
--
--   ERROR: P0001: purge refused: 1 blocking run-scope defect(s).
--   CONTEXT: PL/pgSQL function ottoq_retention_purge_runs(...) line 26 at RAISE
--
-- The defect, from public.ottoq_check_run_scope_registry():
--
--   public | ottoq_proposer_fire_log | tick_seq
--          | 'engine/stamp table has no FK to ottoq_sim_runs' | block
--
-- 0260 created ottoq_proposer_fire_log and registered BOTH of its run-scoped
-- columns -- sim_run_id as class 'evidence', tick_seq as class 'stamp' -- and
-- gave the table NO FOREIGN KEYS AT ALL. Measured: zero rows in pg_constraint
-- with contype='f' on that relation.
--
-- The guard's rule, read from its body rather than assumed (clause (b)):
--     WHERE g.class IN ('engine','stamp')
--       AND NOT EXISTS (SELECT 1 FROM pg_constraint k
--                        WHERE k.contype='f'
--                          AND k.conrelid = to_regclass(...)
--                          AND k.confrelid = 'public.ottoq_sim_runs'::regclass)
-- and its companion, clause (c), which is why the delete action matters:
--     any FK to ottoq_sim_runs with confdeltype='c' is ALSO 'block' --
--     "FK to ottoq_sim_runs is ON DELETE CASCADE - history can be silently erased"
--
-- So the fix is precisely constrained from both sides: the table needs SOME FK
-- to ottoq_sim_runs, and that FK must NOT be ON DELETE CASCADE. NO ACTION is the
-- only thing that satisfies both, and it is also what every peer already does:
--
--   ottoq_bay_binding_witness  FOREIGN KEY (sim_run_id) REFERENCES ottoq_sim_runs(sim_run_id)
--   ottoq_comms_messages       "
--   ottoq_external_proposals   "   <- ALSO class='stamp'; the direct precedent
--   ottoq_itinerary_legs       "
--   ottoq_recall_decisions     "
--   ottoq_stall_bookings       "
--   ottoq_variability_cards    "
--
-- NO ACTION never blocks the retention purge, because ottoq_sim_runs is NOT in
-- ottoq_retention_engine_allowlist -- the purge deletes a doomed run's CHILD
-- rows and leaves the run header (and its validation_notes, which is what
-- ottoq_cert_matrix and ottoq_cert_residue read) permanently in place.
--
-- WHY NOBODY SAW IT FOR A DAY. The defect is invisible to
-- tests/test_migration_hygiene.py, to scripts/check-drift.sql, and to CI: it
-- lives in the shape of the live schema, not in any file. Only
-- ottoq_check_run_scope_registry() reports it, and the only caller that acts on
-- it is the purge -- which has not successfully run since 0260 was applied on
-- 2026-09-12. A guard whose sole reader is a procedure nobody runs is a guard
-- nobody reads. That is a G12 ("CI runs the SQL") argument, recorded in
-- db/checks/0200.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. ADD FOREIGN KEY takes SHARE ROW EXCLUSIVE on BOTH
--    ottoq_proposer_fire_log and ottoq_sim_runs, and ottoq_sim_runs is the
--    hottest table in the certification path. Same predicate as 0266 section P,
--    copied rather than re-derived, including the deliberate asymmetry between
--    the two cron branches (round jobs by EXISTENCE, the standing cert battery
--    by ACTIVENESS).
-- ---------------------------------------------------------------------------
DO $p$
DECLARE v_busy int; v_jobs int; v_live int;
BEGIN
  SELECT count(*) INTO v_busy FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_busy > 0 THEN
    RAISE EXCEPTION '0267 P: % certification/pair call(s) in flight', v_busy;
  END IF;
  SELECT count(*) INTO v_jobs FROM cron.job
   WHERE (jobname ~ '^r[0-9]+_')
      OR (active AND (command ILIKE '%ottoq_determinism_pair%'
                      OR command ILIKE '%ottoq_cert_battery_step%'));
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0267 P: % certification job(s) still scheduled', v_jobs;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0267 P: % run(s) running or paused', v_live;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- G. THE PRE-IMAGE GUARD. Three facts pinned, and each one refuses a different
--    way for this file to be wrong:
--      * the table exists and has NO FK to ottoq_sim_runs -- if someone already
--        added one, this file is a no-op being applied blind and should stop;
--      * tick_seq is still registered class='stamp' -- if it were reclassified,
--        clause (b) no longer applies and the FK is not the right fix;
--      * NO ORPHANS. ADD FOREIGN KEY validates existing rows; one fire row whose
--        sim_run_id is not in ottoq_sim_runs aborts the ALTER. Measured 0 of 4
--        before writing this, and asserted here because "measured earlier" is
--        not "true now".
-- ---------------------------------------------------------------------------
DO $g$
DECLARE v_n int;
BEGIN
  IF to_regclass('public.ottoq_proposer_fire_log') IS NULL THEN
    RAISE EXCEPTION '0267 G: public.ottoq_proposer_fire_log does not exist';
  END IF;

  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE contype = 'f'
     AND conrelid = 'public.ottoq_proposer_fire_log'::regclass
     AND confrelid = 'public.ottoq_sim_runs'::regclass;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0267 G: ottoq_proposer_fire_log already has % FK(s) to ottoq_sim_runs; this file adds the first', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_run_scope_registry
   WHERE table_schema='public' AND table_name='ottoq_proposer_fire_log'
     AND column_name='tick_seq' AND class='stamp';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0267 G: tick_seq is not registered class=stamp (found % row(s)); clause (b) may not apply and the FK may not be the right fix', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_proposer_fire_log f
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = f.sim_run_id);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0267 G: % fire row(s) name a sim_run_id that does not exist; the ALTER would abort. Resolve the orphans first -- do NOT weaken the constraint', v_n;
  END IF;

  --: AND THE DEFECT IS ACTUALLY PRESENT. Without this the whole file could be
  --: applied against a database where the guard reports something else entirely,
  --: and A2 below would then be asserting a clean result this file did not cause.
  SELECT count(*) INTO v_n FROM public.ottoq_check_run_scope_registry()
   WHERE severity = 'block';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0267 G: expected exactly 1 blocking run-scope defect before this file, found % -- re-read ottoq_check_run_scope_registry() before applying', v_n;
  END IF;
END $g$;

-- ---------------------------------------------------------------------------
-- 1. THE FIX. One constraint, named explicitly rather than left to PostgreSQL's
--    default, so the name is the same on every database this is applied to and
--    A1 can pin it. NO ACTION is written by OMISSION, exactly as all seven peers
--    have it: spelling `ON DELETE NO ACTION` would be equivalent but would not
--    match the peer definitions byte-for-byte in pg_get_constraintdef, and a
--    future reader diffing them should see one shape, not two.
--
--    NOT `NOT VALID`. The table holds 4 rows; there is nothing to defer, and a
--    NOT VALID constraint would satisfy clause (b) while leaving the very
--    integrity claim it encodes unchecked -- a guard that reports green without
--    having looked, which is the defect class this repository keeps convicting.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ottoq_proposer_fire_log
  ADD CONSTRAINT ottoq_proposer_fire_log_sim_run_id_fkey
  FOREIGN KEY (sim_run_id) REFERENCES public.ottoq_sim_runs(sim_run_id);

COMMENT ON CONSTRAINT ottoq_proposer_fire_log_sim_run_id_fkey
  ON public.ottoq_proposer_fire_log IS
'0267 (G23). Added because ottoq_check_run_scope_registry() clause (b) blocks the retention purge for any table with a class=engine or class=stamp column and no FK to ottoq_sim_runs, and 0260 created this table with tick_seq registered class=stamp and no foreign keys at all. NO ACTION deliberately, not CASCADE: clause (c) blocks a CASCADE FK to ottoq_sim_runs outright ("history can be silently erased"), and the fire log is the evidence that a proposer was asked at all -- it must outlive the purge of the run body. NO ACTION costs the purge nothing because ottoq_sim_runs is not in ottoq_retention_engine_allowlist: the purge deletes a doomed run child rows and always leaves the run header, which is also what ottoq_cert_matrix and ottoq_cert_residue read.';

-- ---------------------------------------------------------------------------
-- 2. ASSERTIONS.
--
--    THE STANDARD THIS FILE IS HELD TO, stated because 0266 failed it twice in
--    draft: AN ASSERTION THAT PASSES BOTH BEFORE AND AFTER THE CHANGE IT GUARDS
--    IS MEASURING NOTHING. A2 is the one that matters here and it is
--    discriminating by construction -- section G has already refused to proceed
--    unless the block count was exactly 1, so A2's demand for 0 cannot be
--    satisfied by anything except this file's own ALTER.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE v_n int; v_def text; v_del char;
BEGIN
  --: A1. THE CONSTRAINT EXISTS, IN THE PEER SHAPE, AND IS VALIDATED.
  SELECT pg_get_constraintdef(oid), confdeltype INTO v_def, v_del
    FROM pg_constraint
   WHERE conname = 'ottoq_proposer_fire_log_sim_run_id_fkey'
     AND conrelid = 'public.ottoq_proposer_fire_log'::regclass;
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0267 A1: the constraint was not created';
  END IF;
  IF v_def <> 'FOREIGN KEY (sim_run_id) REFERENCES ottoq_sim_runs(sim_run_id)' THEN
    RAISE EXCEPTION '0267 A1: constraint shape is "%", expected the peer shape FOREIGN KEY (sim_run_id) REFERENCES ottoq_sim_runs(sim_run_id)', v_def;
  END IF;
  --: 'a' is NO ACTION. 'c' is CASCADE and is what clause (c) blocks.
  IF v_del <> 'a' THEN
    RAISE EXCEPTION '0267 A1: confdeltype is %, expected a (NO ACTION)', v_del;
  END IF;
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conname = 'ottoq_proposer_fire_log_sim_run_id_fkey'
     AND conrelid = 'public.ottoq_proposer_fire_log'::regclass
     AND convalidated;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0267 A1: the constraint is NOT VALID; it satisfies the guard without having checked the rows';
  END IF;

  --: A2. THE GUARD IS CLEAN -- the whole point, and the purge's precondition.
  --:     Fails before this file (section G pinned it at exactly 1), passes after.
  SELECT count(*) INTO v_n FROM public.ottoq_check_run_scope_registry()
   WHERE severity = 'block';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0267 A2: % blocking run-scope defect(s) remain; the retention purge will still refuse', v_n;
  END IF;

  --: A2b. AND CLAUSE (c) WAS NOT TRADED FOR CLAUSE (b). Asserted over EVERY FK
  --:      to the run table, not just this one: the failure worth catching is a
  --:      CASCADE appearing anywhere, and scoping it to the constraint this file
  --:      created would make it a restatement of A1 rather than a check.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE contype = 'f' AND confrelid = 'public.ottoq_sim_runs'::regclass
     AND confdeltype = 'c';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0267 A2b: % CASCADE FK(s) to ottoq_sim_runs exist; history can be silently erased', v_n;
  END IF;

  --: A3. NO ROW WAS LOST. An ALTER that adds a constraint cannot delete rows,
  --:     which is exactly why this is cheap to assert and worth asserting: if it
  --:     ever fires, the premise of the whole file is wrong.
  SELECT count(*) INTO v_n FROM public.ottoq_proposer_fire_log;
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0267 A3: fire log holds % row(s), expected the 4 present at the pre-image', v_n;
  END IF;

  --: A4. THE PURGE'S REFUSAL IS GONE, ASKED OF THE PURGE ITSELF rather than of
  --:     the guard it calls. A2 proves the guard is clean; this proves the
  --:     CALLER agrees, which is a different claim -- line 26 could refuse on a
  --:     count computed differently, and the only way to know is to call it.
  --:     p_dry_run => true, so this counts and deletes nothing (the dry-run
  --:     branch EXITs the inner loop before any DELETE and never reaches COMMIT).
  CALL public.ottoq_retention_purge_runs(5, 100, '48 hours', true);
  RAISE NOTICE '0267: A1-A4 passed; the run-scope guard is clean and the retention purge no longer refuses';
END $a$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- (not yet applied)
-- ---------------------------------------------------------------------------
