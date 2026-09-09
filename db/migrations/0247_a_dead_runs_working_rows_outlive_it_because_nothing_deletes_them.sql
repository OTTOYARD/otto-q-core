-- migration-version: PENDING
-- migration-name: 0247_a_dead_runs_working_rows_outlive_it_because_nothing_deletes_them
-- ===========================================================================
-- 0247  A DEAD RUN'S WORKING ROWS OUTLIVE IT BECAUSE NOTHING DELETES THEM
-- ===========================================================================
-- probe:          db/checks/0163, db/checks/0164 (and 0164's correction banner)
-- forces_recert:  FALSE
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only
-- authority; ottoq_sim_runs cannot see a pair (both arms are one transaction)
-- and cron.job_run_details reports an in-flight two-statement job as succeeded.
--
-- WHAT IS WRONG
--
-- 0163 measured it: ottoq_stall_bookings is 66% of every heap block this
-- database has ever read, at 1,028 MB, and 12.9% of its lifetime rows have been
-- deleted against 96.4% for the event stream. Nine other tables are in the same
-- position. The reason is not a missing policy. It is that the only SCHEDULED
-- deleter in the database is ottoq_retention_purge_worker, which walks three
-- tables by wall clock, and the calendar is not one of them.
--
-- 0164 asked the registry what it already knew and got a complete answer:
-- ottoq_stall_bookings.sim_run_id has been class='engine' since 0022 --
-- "run-scoped working data; must not outlive its run". Forty-seven tables carry
-- that classification. Nothing on a schedule acts on it.
--
-- WHY THE OBVIOUS FIX IS THE WRONG FIX, TWICE OVER
--
-- (a) Adding 'ottoq_stall_bookings' to the nightly worker's ARRAY would delete a
--     run-scoped table by wall clock -- a second deleter, on a second key, for a
--     table the registry already describes correctly.
--
-- (b) ottoq_purge_prior_runs DOES loop the registry's engine class, and 0164
--     first concluded it should simply be scheduled. That conclusion was wrong
--     and 0164 carries the correction. Its step (5) is
--         DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = ANY(v_doomed);
--     and v_doomed is every run but one. ottoq_cert_matrix reads every canon,
--     every streak and the recert floor from ottoq_sim_runs.validation_notes and
--     from nowhere else. Scheduling it would have destroyed 919 cert-harness
--     verdicts unrecoverably. It is a DEMO RESET, which is why its only caller
--     is ottoq_start_demo_run.
--
-- WHAT THIS MIGRATION DOES INSTEAD
--
-- Extends the machinery that is already correct rather than adding a third one.
-- ottoq_retention_purge_worker already has every property this needs -- an
-- advisory lock, a time budget, micro-batches with a COMMIT per iteration,
-- retention arming, a protected-run set, and an observability row in
-- ottoq_retention_state. What it does not have is a mode that deletes BY RUN.
--
--   1. A policy row (policy_key='engine_rows'), so the keep window is data.
--   2. public.ottoq_retention_purge_runs -- a sibling procedure that borrows the
--      worker's shape, loops the registry's class='engine' rows, and deletes
--      engine rows for runs that are finished, archived, not production, and
--      older than the window.
--   3. NOTHING IS SCHEDULED HERE. See "WHY NO CRON" below.
--
-- THE RUN ROW IS NEVER TOUCHED. ottoq_sim_runs.sim_run_id is class 'run_ledger',
-- which the engine loop does not select, and this procedure has no DELETE
-- against ottoq_sim_runs anywhere in its body -- asserted in A2 and A3, because
-- 0164's mistake was exactly a delete that sat OUTSIDE the class loop and
-- ignored the class entirely. The whole of ottoq_sim_runs is 5,088 kB for 938
-- runs. The certification history costs five megabytes and is kept forever.
--
-- MEASURED 2026-09-09 13:16 UTC: 938 runs, 0 running, 8 production_live, 923
-- archived, 738 older than 48h. 729 are purgeable under all four conditions --
-- so the archive guard costs 9 runs, not the purge.
--
-- WHY NO CRON IN THIS MIGRATION
--
-- A procedure that COMMITs per iteration cannot be CALLed inside a transaction
-- block, and apply_migration supplies one. So this migration CANNOT exercise
-- its own procedure -- every assertion below is structural, and none of them is
-- behavioural. Scheduling an unexercised deleter over 47 tables on the strength
-- of structural assertions alone is precisely the move that put 0244 into the
-- verdict. The first run is therefore MANUAL and OBSERVED, in a window with no
-- pair in flight, and a follow-up migration adds the cron entry once there is a
-- measured receipt. MEASURED first, ENFORCED after -- the same doctrine that
-- governs a verdict atom, applied to a deleter.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The window is data, not a literal.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_retention_policy (policy_key, enabled, keep_interval, day_aligned, notes)
VALUES (
  'engine_rows', true, '48 hours'::interval, false,
  'Keep window for RUN-SCOPED engine rows, deleted by ottoq_retention_purge_runs '
  'per ottoq_run_scope_registry class=''engine''. Distinct from policy_key=''events'', '
  'which is a WALL-CLOCK walk over three tables and also covers production rows '
  '(sim_run_id IS NULL) that no run purge can reach. day_aligned is false on purpose: '
  'the unit here is a run, not a day. The run row itself is never deleted -- '
  'ottoq_cert_matrix reads every canon from ottoq_sim_runs.validation_notes (0164).')
ON CONFLICT (policy_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. The procedure.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_runs(
  IN p_time_budget_s integer DEFAULT 60,
  IN p_micro_batch   integer DEFAULT 2000,
  IN p_keep          interval DEFAULT '48:00:00'::interval,
  IN p_dry_run       boolean  DEFAULT false)
LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep    interval;
  v_cut     timestamptz;
  v_t0      timestamptz := clock_timestamp();
  v_n       bigint;
  v_total   bigint := 0;
  v_doomed  uuid[];
  v_block   int;
  v_pairs   int;
  r         record;
BEGIN
  -- Forward-compatible resolution without a SET clause: a routine with SET
  -- cannot COMMIT, and this procedure commits per iteration. Same reason, same
  -- shape, as ottoq_retention_purge_worker.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  -- (1) One purge at a time, and never alongside the wall-clock worker: the
  --     SAME advisory lock, deliberately. They delete overlapping tables.
  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  -- (2) Refuse to run blind on a blocking run-scope defect. Borrowed verbatim
  --     from ottoq_purge_prior_runs, which had this part right.
  SELECT count(*) FILTER (WHERE severity = 'block') INTO v_block
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s). Run SELECT * FROM ottoq_check_run_scope_registry();', v_block;
  END IF;

  -- (3) THE STANDING RULE OF THIS PROJECT, ENFORCED IN CODE. pg_stat_activity is
  --     the only authority on a pair in flight: ottoq_sim_runs cannot see one
  --     (both arms are a single transaction) and cron.job_run_details reports an
  --     in-flight two-statement job as succeeded in ~1 s. `pid <> pg_backend_pid()`
  --     is load-bearing, not defensive -- without it THIS query's own text
  --     matches the pattern it searches for.
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%ottoq_determinism_pair%';
  IF v_pairs > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: % certification pair(s) in flight - skipped', v_pairs;
    RETURN;
  END IF;

  -- (4) Policy wins over the caller's argument, exactly as the events worker does.
  SELECT keep_interval INTO v_keep
    FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
  v_keep := COALESCE(v_keep, p_keep);
  v_cut  := now() - v_keep;

  -- (5) Decide what is going ONCE, up front, as a value -- so a run that starts
  --     mid-purge can never enter the doomed set. Four conditions, each with a
  --     reason:
  --       status <> 'running'        a live run's rows are its own
  --       run_by <> production_live  production data is not a sim artefact
  --       started_at < cut           the keep window
  --       archived                   ottoq_archive_run counts rows AT ARCHIVE
  --                                  TIME (0164 Q3), so purging first would
  --                                  zero the archive it has not written yet
  SELECT array_agg(sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs r
   WHERE r.status <> 'running'
     AND COALESCE(r.run_by,'') <> 'production_live'
     AND r.started_at < v_cut
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = r.sim_run_id);

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RAISE NOTICE 'retention purge (runs): nothing older than % is archived and finished', v_keep;
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RETURN;
  END IF;

  RAISE NOTICE 'retention purge (runs): keep %, cut %, % doomed run(s), dry_run=%',
               v_keep, v_cut, cardinality(v_doomed), p_dry_run;

  -- (6) THE ENGINE LOOP. The registry decides which tables and which column --
  --     never a hand-maintained array, which is the whole lesson of 0163/0164.
  --     ottoq_sim_runs is class 'run_ledger' and is therefore not selected here;
  --     there is no DELETE against it anywhere in this body, and A2/A3 assert so.
  --     BIGGEST FIRST, NOT ALPHABETICALLY. This ordering is load-bearing and the
  --     first draft had it wrong. Under ORDER BY table_name the three largest
  --     engine tables sit at alphabetical ranks 9, 15 and 26 of 47
  --     (ottoq_decisions 2,129 MB / ottoq_events 3,441 MB /
  --     ottoq_rule_evaluations 5,577 MB), and ottoq_stall_bookings -- the table
  --     0163 wrote this whole line of work about -- sits at rank 29 with
  --     ottoq_variability_cards at 35. A 60-second budget would be spent before
  --     the loop ever reached them, on every pass, forever: not a slow purge but
  --     a permanently starved one. Size-descending is also self-correcting,
  --     because a table that has been drained shrinks and yields its place.
  --     table_name breaks ties so the order stays deterministic.
  --
  --     to_regclass guards a registry row whose table has since been dropped:
  --     format('%I') would happily build a DELETE naming a table that is not
  --     there, and the whole pass would abort on it.
  FOR r IN
    SELECT table_name AS t, column_name AS c
      FROM public.ottoq_run_scope_registry
     WHERE class = 'engine' AND table_schema = 'public'
       AND to_regclass('public.' || table_name) IS NOT NULL
     ORDER BY pg_total_relation_size(('public.' || table_name)::regclass) DESC, table_name
  LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);

      IF p_dry_run THEN
        -- A TRUE COUNT, DELIBERATELY UNBOUNDED. The first draft applied
        -- p_micro_batch here, which would have reported '2000' for every large
        -- table and told the operator nothing -- a dry run whose number is the
        -- batch size is not a dry run. This is a read-only full count, run by
        -- hand in a quiet window, and the scan is the price of knowing.
        EXECUTE format('SELECT count(*) FROM public.%1$I WHERE %2$I = ANY($1)', r.t, r.c)
          INTO v_n USING v_doomed;
        RAISE NOTICE '  dry run: % would lose % row(s)', r.t, v_n;
        v_total := v_total + v_n;
        EXIT;                      -- one count per table, then move on
      END IF;

      -- Re-arm each transaction: COMMIT resets a LOCAL set_config, and the
      -- append-only guards refuse every DELETE below without it.
      PERFORM set_config('ottoq.retention', 'on', true);

      EXECUTE format(
        'DELETE FROM public.%1$I WHERE ctid IN '
        '(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)',
        r.t, r.c) USING v_doomed, p_micro_batch;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      COMMIT;                      -- each batch is permanent regardless of later failure
      EXIT WHEN v_n = 0;           -- this table is drained
    END LOOP;
  END LOOP;

  IF NOT p_dry_run THEN
    PERFORM set_config('ottoq.retention', 'on', true);
    -- ottoq_retention_state.table_name is a state KEY, not a relation name --
    -- the events worker stores 'ottoq_events' there because for it the two
    -- coincide. This pass spans 47 tables, so it keys on the policy instead.
    -- cursor_block carries the doomed-run count: observability only, nothing
    -- reads it back to make a decision.
    UPDATE public.ottoq_retention_state
       SET pass_deleted = pass_deleted + v_total, updated_at = now()
     WHERE table_name = 'engine_rows';
    IF NOT FOUND THEN
      INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
      VALUES ('engine_rows', cardinality(v_doomed), v_total, now())
      ON CONFLICT (table_name) DO NOTHING;
    END IF;
    COMMIT;
  END IF;

  RAISE NOTICE 'retention purge (runs): % row(s) % across % run(s)',
               v_total, CASE WHEN p_dry_run THEN 'MATCHED (dry run)' ELSE 'deleted' END,
               cardinality(v_doomed);
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$;

-- ---------------------------------------------------------------------------
-- 3. Assertions. All structural: this migration cannot CALL its own procedure
--    (see WHY NO CRON above), so none of these is behavioural, and the file
--    says so rather than implying a proof it does not have.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  -- A1. The procedure exists, and is a PROCEDURE (prokind 'p'), because only a
  --     procedure may COMMIT and the batching depends on that.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs' AND p.prokind = 'p';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: expected exactly 1 procedure ottoq_retention_purge_runs, found %', v_n;
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';

  -- A2. THE ASSERTION THAT EXISTS BECAUSE OF 0164. No DELETE against
  --     ottoq_sim_runs anywhere in the body. This is a textual check and it is
  --     the right kind: 0164's defect was a DELETE statement sitting outside the
  --     class loop, which no amount of reasoning about the loop would have caught.
  IF v_src ~* 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs' THEN
    RAISE EXCEPTION 'A2 FAILED: the purge contains a DELETE against ottoq_sim_runs. '
                    'That deletes validation_notes, which is where every canon lives (0164).';
  END IF;

  -- A3. The run ledger is not reachable through the loop either: assert its
  --     registry class is not 'engine'. A2 covers the literal statement; A3
  --     covers the dynamic path.
  SELECT count(*) INTO v_n FROM public.ottoq_run_scope_registry
   WHERE table_name = 'ottoq_sim_runs' AND class = 'engine';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A3 FAILED: ottoq_sim_runs is classified engine (% row(s)); '
                    'the engine loop would delete the run ledger', v_n;
  END IF;

  -- A4. The pair guard is present AND excludes this backend. Without
  --     pid <> pg_backend_pid() the guard matches its own query text and the
  --     purge would refuse to run, forever, for a reason nobody could see.
  IF v_src !~ 'pg_stat_activity' OR v_src !~ 'pg_backend_pid' THEN
    RAISE EXCEPTION 'A4 FAILED: the in-flight-pair guard is missing or does not exclude this backend';
  END IF;

  -- A5. The keep window resolves from the policy table, not from a literal.
  SELECT count(*) INTO v_n FROM public.ottoq_retention_policy
   WHERE policy_key = 'engine_rows' AND enabled;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A5 FAILED: expected 1 enabled engine_rows policy row, found %', v_n;
  END IF;

  -- A6. The archive guard is real: assert the doomed predicate would today
  --     exclude at least the runs with no archive row. Counts only, no delete.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs r
   WHERE r.status <> 'running'
     AND COALESCE(r.run_by,'') <> 'production_live'
     AND r.started_at < now() - interval '48 hours'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = r.sim_run_id);
  RAISE NOTICE 'A6: % finished non-production run(s) older than 48h are UNARCHIVED and therefore protected', v_n;

  -- A8. The loop filters table_schema='public'. Assert that filter hides nothing,
  --     rather than letting a non-public engine table be silently skipped.
  SELECT count(*) INTO v_n FROM public.ottoq_run_scope_registry
   WHERE class = 'engine' AND table_schema <> 'public';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A8 FAILED: % engine column(s) live outside schema public and '
                    'the purge loop would skip them silently', v_n;
  END IF;

  -- A7. Nothing is scheduled by this migration. Asserting the absence, so that
  --     a later edit that quietly adds a cron entry here fails loudly.
  SELECT count(*) INTO v_n FROM cron.job WHERE command ILIKE '%ottoq_retention_purge_runs%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A7 FAILED: % cron job(s) already call ottoq_retention_purge_runs; '
                    'the first run of this procedure is manual and observed by design', v_n;
  END IF;

  RAISE NOTICE 'A1-A8 PASSED (all structural; no behavioural assertion is possible '
               'inside a transaction block for a COMMITting procedure)';
END $$;

-- ===========================================================================
-- FIRST RUN, BY HAND, IN A WINDOW WITH NO PAIR IN FLIGHT:
--
--   CALL public.ottoq_retention_purge_runs(60, 2000, '48 hours', p_dry_run => true);
--   -- read the NOTICE, confirm the doomed count and the per-table match counts
--   CALL public.ottoq_retention_purge_runs(60, 2000);
--
-- THEN, AND ONLY THEN: a follow-up migration schedules it, and a REINDEX on
-- ottoq_stall_bookings' three GiST constraints -- deleting rows does not shrink
-- a GiST index, so the read cost 0163 measured does not come back without one
-- (0164 Q4).
-- ===========================================================================
