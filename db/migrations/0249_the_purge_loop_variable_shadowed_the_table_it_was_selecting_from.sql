-- migration-version: 20260909133615
-- migration-name: 0249_the_purge_loop_variable_shadowed_the_table_it_was_selecting_from
-- ===========================================================================
-- 0249  THE PURGE LOOP VARIABLE SHADOWED THE TABLE IT WAS SELECTING FROM
-- ===========================================================================
-- probe:          the second live call of ottoq_retention_purge_runs
-- forces_recert:  FALSE
-- REPAIRS:        0247, on its second dry run, before it deleted anything
--
-- THE DEFECT
--
--   ERROR: 55000: record "r" is not assigned yet
--   DETAIL: The tuple structure of a not-yet-assigned record is indeterminate.
--   CONTEXT: SELECT array_agg(sim_run_id) FROM public.ottoq_sim_runs r
--            WHERE r.status <> 'running' ...
--
-- 0247 declared `r record` for the engine-table loop and then, forty lines
-- earlier, aliased ottoq_sim_runs as `r` in the doomed-set query. PL/pgSQL
-- resolves an ambiguous qualified name in favour of the VARIABLE, so `r.status`
-- read a record that had not been assigned yet -- the loop it belongs to is
-- further down the body. Every reference in that query was silently pointed at
-- the wrong thing.
--
-- WHY IT DID NOT SHOW EARLIER. This is a RUNTIME error, not a parse error:
-- CREATE PROCEDURE accepted the body, so 0247's structural assertions A1-A8 all
-- passed against a procedure that could not execute its own fifth step. That is
-- the honest limit of 0247's own header -- it says every assertion is
-- structural and none is behavioural, and this is exactly the class of defect
-- that gap leaves open. The first dry run was refused earlier still, by the
-- run-scope gate (0248), so this was the second call and still the first one to
-- reach line 60.
--
-- NOTHING WAS DELETED. The error is raised while BUILDING the doomed set, before
-- the engine loop, and the call was a dry run in any case.
--
-- THE FIX. Rename the loop record to v_reg and alias the run table `sr`, so the
-- two cannot collide again by either route. No other line of the body changes:
-- the ordering, the guards, the batching and the four doomed-set conditions are
-- byte-for-byte 0247's.
-- ===========================================================================

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
  -- 0249: named v_reg, not r. As `r` it shadowed the `r` alias on
  -- ottoq_sim_runs in the doomed-set query below and PL/pgSQL resolved the
  -- qualified name to this unassigned record.
  v_reg     record;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  SELECT count(*) FILTER (WHERE severity = 'block') INTO v_block
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s). Run SELECT * FROM ottoq_check_run_scope_registry();', v_block;
  END IF;

  -- pg_stat_activity is the only authority on a pair in flight.
  -- pid <> pg_backend_pid() is load-bearing: without it this query's own text
  -- matches the pattern it searches for.
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%ottoq_determinism_pair%';
  IF v_pairs > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: % certification pair(s) in flight - skipped', v_pairs;
    RETURN;
  END IF;

  SELECT keep_interval INTO v_keep
    FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
  v_keep := COALESCE(v_keep, p_keep);
  v_cut  := now() - v_keep;

  --   status <> 'running'        a live run's rows are its own
  --   run_by <> production_live  production data is not a sim artefact
  --   started_at < cut           the keep window
  --   archived                   ottoq_archive_run counts rows AT ARCHIVE TIME
  --                              (0164 Q3), so purging first would zero an
  --                              archive it has not written yet
  SELECT array_agg(sr.sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs sr
   WHERE sr.status <> 'running'
     AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < v_cut
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id);

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RAISE NOTICE 'retention purge (runs): nothing older than % is archived and finished', v_keep;
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RETURN;
  END IF;

  RAISE NOTICE 'retention purge (runs): keep %, cut %, % doomed run(s), dry_run=%',
               v_keep, v_cut, cardinality(v_doomed), p_dry_run;

  -- BIGGEST FIRST, NOT ALPHABETICALLY: under ORDER BY table_name the three
  -- largest engine tables sit at alphabetical ranks 9, 15 and 26 of 47 and would
  -- spend the budget before the loop reached ottoq_stall_bookings at rank 29 --
  -- a permanently starved purge. Size-descending is self-correcting.
  -- to_regclass guards a registry row whose table has since been dropped.
  FOR v_reg IN
    SELECT table_name AS t, column_name AS c
      FROM public.ottoq_run_scope_registry
     WHERE class = 'engine' AND table_schema = 'public'
       AND to_regclass('public.' || table_name) IS NOT NULL
     ORDER BY pg_total_relation_size(('public.' || table_name)::regclass) DESC, table_name
  LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);

      IF p_dry_run THEN
        EXECUTE format('SELECT count(*) FROM public.%1$I WHERE %2$I = ANY($1)', v_reg.t, v_reg.c)
          INTO v_n USING v_doomed;
        RAISE NOTICE '  dry run: % would lose % row(s)', v_reg.t, v_n;
        v_total := v_total + v_n;
        EXIT;
      END IF;

      PERFORM set_config('ottoq.retention', 'on', true);

      EXECUTE format(
        'DELETE FROM public.%1$I WHERE ctid IN '
        '(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)',
        v_reg.t, v_reg.c) USING v_doomed, p_micro_batch;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END LOOP;

  IF NOT p_dry_run THEN
    PERFORM set_config('ottoq.retention', 'on', true);
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

DO $$
DECLARE v_src text; v_n int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';

  -- A1. 0247's assertions still hold: no DELETE against the run ledger.
  IF v_src ~* 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs' THEN
    RAISE EXCEPTION 'A1 FAILED: the purge contains a DELETE against ottoq_sim_runs (0164)';
  END IF;

  -- A2. THE FIX ITSELF: no bare `r` record declaration, and the run table is
  --     aliased sr. Either alone would close it; both make the collision
  --     unreachable by either route.
  IF v_src ~ '^\s*r\s+record' THEN
    RAISE EXCEPTION 'A2 FAILED: a record variable named r is back; it shadows the sr alias';
  END IF;
  IF v_src !~ 'FROM public\.ottoq_sim_runs sr' THEN
    RAISE EXCEPTION 'A2 FAILED: the doomed-set query no longer aliases ottoq_sim_runs as sr';
  END IF;

  -- A3. The guards survived the rewrite.
  IF v_src !~ 'pg_stat_activity' OR v_src !~ 'pg_backend_pid'
     OR v_src !~ 'ottoq_check_run_scope_registry'
     OR v_src !~ 'pg_total_relation_size' THEN
    RAISE EXCEPTION 'A3 FAILED: a guard or the size ordering was lost in the rewrite';
  END IF;

  -- A4. Still nothing scheduled.
  SELECT count(*) INTO v_n FROM cron.job WHERE command ILIKE '%ottoq_retention_purge_runs%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % cron job(s) call the purge; the first real run is manual', v_n;
  END IF;

  RAISE NOTICE 'A1-A4 PASSED';
END $$;
