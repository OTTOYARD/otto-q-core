-- migration-version: PENDING
-- migration-name:    the_purge_deletes_engine_tables_alphabetically_not_by_dependency
--
-- 0345  "CHILDREN FIRST" WAS ORDER BY table_name. THAT IS ALPHABETICAL, NOT
--       DEPENDENCY ORDER, AND THREE OF SIX ENGINE FKs RUN THE WRONG WAY.
--
-- 0344 removed the first constraint blocking ottoq_purge_prior_runs and said
-- plainly that the full purge had never been observed past that point. It has now.
-- Driven server-side through pg_cron so no client timeout could mask it:
--
--   cron jobid 726, 2026-09-19 15:48:00 UTC, ran 1m20s, FAILED:
--   ERROR: update or delete on table "ottoq_recall_decisions" violates foreign
--   key constraint "ottoq_recall_refusals_recall_id_fkey" on table
--   "ottoq_recall_refusals"
--   CONTEXT: SQL statement "DELETE FROM public.ottoq_recall_decisions WHERE
--   sim_run_id = ANY($1)"
--
-- So no run was created. `ottoq_start_demo_run` still cannot complete, and the
-- Twin's start door is still shut. 0344 was necessary and not sufficient.
--
-- ── THE DEFECT IS ONE CLAUSE, AND ITS COMMENT ASSERTS THE OPPOSITE ──────────
--
-- Step (4) reads:
--     FOR r IN SELECT table_name, column_name FROM ottoq_run_scope_registry
--               WHERE class = 'engine' ORDER BY table_name
-- under a comment that says "(4) CHILDREN FIRST, every engine table".
--
-- ORDER BY table_name is alphabetical. It has no knowledge of foreign keys. That
-- it works at all is a coincidence of naming, and the coincidence holds for only
-- half the graph. Measured over pg_constraint, restricted to FKs where BOTH ends
-- are engine-class tables -- six relationships, seven constraints:
--
--   child (must be deleted first)     parent                      alphabetical
--   ottoq_recall_refusals          -> ottoq_recall_decisions       WRONG
--   ottoq_rule_evaluations         -> ottoq_events  (x2 fkeys)     WRONG
--   ottoq_ocpp_messages            -> ocpp_sessions                WRONG
--   ottoq_itinerary_legs           -> ottoq_vehicle_itineraries    right
--   ottoq_ops_approvals            -> ottoq_visit_needs            right
--   ottoq_rider_cleaning_flags     -> ottoq_visit_needs            right
--
-- THREE OF SIX ARE DELETED PARENT-FIRST. The purge could only ever complete for a
-- doomed set in which all three child tables happened to be empty. One of them is
-- `ottoq_rule_evaluations`, which this engine writes on essentially every tick --
-- so this has been broken for as long as those FKs have existed, and the failure
-- was invisible because the only caller, ottoq_start_demo_run, has no handler and
-- the whole start simply rolled back.
--
-- AND IT IS NOT THE NIGHTLY JOB. cron 625 `ottoq-run-purge-nightly` calls
-- `ottoq_retention_purge_runs(300, 2000, '48 hours', false)`, a different,
-- allowlisted, bounded function -- which is why BUILD_QUEUE's observed 7,300,205-
-- row purge on 2026-09-13 succeeded while this one cannot. Two purges, one
-- working. I briefly mis-stated this as the same job; CLAUDE.md already had it
-- right.
--
-- ── THE FIX: DEPENDENCY ORDER, COMPUTED, NOT NAMED ──────────────────────────
--
-- Step (4) now orders by a depth computed from pg_constraint itself:
--   depth 0 = an engine table that is NOT a child of any engine table
--   depth n = a child of a depth n-1 engine table
-- and deletion runs in DESCENDING depth, so a child is always deleted before
-- anything it references. Derived from the live catalog on every call, so a
-- future FK between two engine tables is ordered correctly the day it is added --
-- which a hand-maintained list would not be. The recursion carries a depth < 20
-- cycle guard.
--
-- THE ROW SET IS UNCHANGED. It is still every (table_name, column_name) row of
-- class 'engine' -- not DISTINCT table_name -- so a table registered on two
-- run-scoping columns is still deleted once per column, exactly as before. Only
-- the ORDER changes. A2 asserts the count of rows iterated is identical.
--
-- A BOUNDED RETRY BACKSTOP, AND WHY IT IS NOT EXCEPTION-SWALLOWING. With correct
-- ordering no retry should ever be needed. But a cycle, or an FK through a table
-- registered under a name that no longer resolves, would leave a residue -- and
-- silently skipping it is precisely the class of bug this file is fixing. So a
-- failed DELETE is retried for at most 3 passes, and if anything still remains
-- the procedure RAISES and NAMES every survivor with its SQLSTATE. The original
-- promise, "NO exception swallowed", is kept: an unresolvable failure still stops
-- the purge, it just stops with a diagnosis instead of the first error it meets.
--
-- ── forces_recert: TRUE, and this is the honest classification ──────────────
--
-- It would be easy to argue FALSE: the purge is not on the tick path and deletes
-- only prior runs. But 0145/0146 established that UNSCOPED READERS EXIST in this
-- engine -- routines that read a table without filtering sim_run_id. For such a
-- reader, "prior runs' rows are present" versus "absent" is a different world,
-- and this file changes a purge that currently always fails into one that
-- succeeds. That is a change to the world a new run boots into, which is exactly
-- what a recertification exists to detect. Claiming otherwise would be the
-- cheaper answer, not the true one.
--
-- NOTHING IS DELETED BY THIS FILE. It changes the order in which a future purge
-- deletes. The 1,238 accumulated runs are not purged here; that remains the
-- founder's call, and the first real purge will happen when a run is next started.

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int; v_block int; v_bad int; v_md5 text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0345 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0345 P-: % certification pair(s) are active', v_pairs; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0345 P-: % Twin run(s) are active', v_runs; END IF;

  -- P1. 0344 must be in place: the guard clean and the fire-log FK gone. This
  -- file is the second half of that fix and is meaningless without the first.
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry()
   WHERE severity='block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0345 P1a: the registry guard reports % blocking defect(s)', v_block;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE conname='ottoq_proposer_fire_log_sim_run_id_fkey') THEN
    RAISE EXCEPTION '0345 P1b: 0344 has not been applied (the fire-log FK is still present)';
  END IF;

  -- P2. THE DEFECT MUST STILL BE THERE, in the exact clause the header quotes.
  SELECT prosrc INTO v_md5 FROM pg_proc
   WHERE oid='public.ottoq_purge_prior_runs(uuid)'::regprocedure;
  IF v_md5 NOT LIKE '%WHERE class = ''engine'' ORDER BY table_name%' THEN
    RAISE EXCEPTION '0345 P2: the alphabetical ORDER BY is not present; the purge has been changed since measuring';
  END IF;

  -- P3. AND THE MISORDERING MUST BE REAL, recomputed here rather than trusted
  -- from the header. At least one engine->engine FK whose child sorts AFTER its
  -- parent, which is what alphabetical order gets wrong.
  SELECT count(*) INTO v_bad
    FROM pg_constraint c
   WHERE c.contype='f' AND c.conrelid <> c.confrelid
     AND c.conrelid::regclass::text IN
         (SELECT table_name FROM public.ottoq_run_scope_registry WHERE class='engine')
     AND c.confrelid::regclass::text IN
         (SELECT table_name FROM public.ottoq_run_scope_registry WHERE class='engine')
     AND c.conrelid::regclass::text > c.confrelid::regclass::text;
  IF v_bad = 0 THEN
    RAISE EXCEPTION '0345 P3: no engine FK is misordered alphabetically; this fix is not needed';
  END IF;
  RAISE NOTICE '0345: % engine->engine FK constraint(s) are deleted parent-first by the alphabetical sweep', v_bad;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0345-pre', 'function', 'public', 'ottoq_purge_prior_runs(uuid)',
       pg_get_functiondef('public.ottoq_purge_prior_runs(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_purge_prior_runs(uuid)'::regprocedure));

CREATE OR REPLACE FUNCTION public.ottoq_purge_prior_runs(p_keep_run uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  r record; v_n bigint; v_total bigint := 0; v_runs int;
  v_doomed uuid[]; v_block int; v_engine int; v_cleared jsonb := '{}'::jsonb;
  v_warn jsonb;
  v_pending jsonb := '[]'::jsonb;   -- (table, column, sqlstate) still failing
  v_next    jsonb;
  v_pass    int;
  v_progress boolean;
BEGIN
  -- (1) ARM. Without this the append-only guards refuse every DELETE below.
  PERFORM set_config('ottoq.retention', 'on', true);

  -- (2) REFUSE TO RUN BLIND on a blocking defect.
  SELECT count(*) FILTER (WHERE severity = 'block'),
         COALESCE(jsonb_agg(table_name || '.' || column_name)
                  FILTER (WHERE severity = 'warn'), '[]'::jsonb)
    INTO v_block, v_warn
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s). Run SELECT * FROM ottoq_check_run_scope_registry();', v_block;
  END IF;

  SELECT count(*) INTO v_engine FROM public.ottoq_run_scope_registry WHERE class='engine';
  IF v_engine = 0 THEN
    RAISE EXCEPTION 'purge refused: run-scope registry holds no engine tables';
  END IF;

  -- (3) Decide what is going ONCE, up front, as a value.
  SELECT array_agg(sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs
   WHERE sim_run_id <> p_keep_run
     AND COALESCE(run_by,'') <> 'production_live'
     AND status <> 'running';

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'kept', p_keep_run, 'rows_purged', 0,
      'prior_runs_deleted', 0, 'cleared_by_table', v_cleared,
      'unregistered_run_scoped', v_warn, 'retention_armed', true);
  END IF;

  -- (4) CHILDREN FIRST -- AND SINCE 0345 THAT IS TRUE RATHER THAN HOPED.
  --
  -- This was `ORDER BY table_name`, which is alphabetical and knows nothing about
  -- foreign keys. Measured 2026-09-19: of six FK relationships where both ends
  -- are engine tables, THREE are deleted parent-first by that ordering --
  -- ottoq_recall_refusals -> ottoq_recall_decisions,
  -- ottoq_rule_evaluations -> ottoq_events, and
  -- ottoq_ocpp_messages    -> ocpp_sessions.
  -- The first of those raised 23503 on cron jobid 726 and rolled back an entire
  -- ottoq_start_demo_run, which is why the Twin start door was shut.
  --
  -- Depth is computed from pg_constraint on every call, so an FK added between
  -- two engine tables tomorrow is ordered correctly without editing this
  -- function. depth 0 = not a child of any engine table; deletion runs DESC, so
  -- a child always precedes what it references.
  FOR r IN
    WITH RECURSIVE eng AS (
      SELECT table_name, column_name
        FROM public.ottoq_run_scope_registry
       WHERE class = 'engine'
    ),
    tbl AS (SELECT DISTINCT table_name FROM eng),
    edge AS (
      SELECT DISTINCT c.conrelid::regclass::text  AS child,
                      c.confrelid::regclass::text AS parent
        FROM pg_constraint c
       WHERE c.contype = 'f'
         AND c.conrelid <> c.confrelid
         AND c.conrelid::regclass::text  IN (SELECT table_name FROM tbl)
         AND c.confrelid::regclass::text IN (SELECT table_name FROM tbl)
    ),
    depth AS (
      SELECT t.table_name, 0 AS d
        FROM tbl t
       WHERE NOT EXISTS (SELECT 1 FROM edge e WHERE e.child = t.table_name)
      UNION ALL
      SELECT e.child, d.d + 1
        FROM edge e
        JOIN depth d ON d.table_name = e.parent
       WHERE d.d < 20        -- cycle guard: terminate rather than recurse forever
    ),
    ranked AS (
      SELECT table_name, max(d) AS d FROM depth GROUP BY table_name
    )
    SELECT eng.table_name AS t, eng.column_name AS c,
           COALESCE(ranked.d, 0) AS d
      FROM eng
      LEFT JOIN ranked ON ranked.table_name = eng.table_name
     ORDER BY COALESCE(ranked.d, 0) DESC, eng.table_name, eng.column_name
  LOOP
    BEGIN
      EXECUTE format('DELETE FROM public.%1$I WHERE %2$I = ANY($1)', r.t, r.c)
        USING v_doomed;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      IF v_n > 0 THEN
        v_cleared := v_cleared || jsonb_build_object(r.t, v_n);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- NOT swallowed: parked for the bounded retry below, and RAISED by name if
      -- it never resolves. With correct ordering this should stay empty.
      v_pending := v_pending || jsonb_build_array(
        jsonb_build_object('t', r.t, 'c', r.c, 'sqlstate', SQLSTATE,
                           'msg', left(SQLERRM, 200)));
    END;
  END LOOP;

  -- (4b) BOUNDED RETRY. A cycle, or an ordering the catalog could not express,
  -- would leave residue here. Silently skipping it is the bug this file fixes, so
  -- retry at most three passes and then raise with every survivor named.
  v_pass := 0;
  WHILE jsonb_array_length(v_pending) > 0 AND v_pass < 3 LOOP
    v_pass := v_pass + 1;
    v_next := '[]'::jsonb;
    v_progress := false;
    FOR r IN SELECT (e->>'t') AS t, (e->>'c') AS c
               FROM jsonb_array_elements(v_pending) e
    LOOP
      BEGIN
        EXECUTE format('DELETE FROM public.%1$I WHERE %2$I = ANY($1)', r.t, r.c)
          USING v_doomed;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_total := v_total + v_n;
        v_progress := true;
        IF v_n > 0 THEN
          v_cleared := v_cleared || jsonb_build_object(r.t, v_n);
        END IF;
      EXCEPTION WHEN OTHERS THEN
        v_next := v_next || jsonb_build_array(
          jsonb_build_object('t', r.t, 'c', r.c, 'sqlstate', SQLSTATE,
                             'msg', left(SQLERRM, 200)));
      END;
    END LOOP;
    v_pending := v_next;
    IF NOT v_progress THEN EXIT; END IF;   -- no point in another identical pass
  END LOOP;

  IF jsonb_array_length(v_pending) > 0 THEN
    RAISE EXCEPTION 'purge refused: % engine table(s) could not be cleared after % retry pass(es): %',
      jsonb_array_length(v_pending), v_pass, v_pending::text;
  END IF;

  -- (5) The parent. vehicles.owning_sim_run_id is ON DELETE SET NULL; every other
  --     FK is NO ACTION, so if (4) missed anything this RAISES instead of orphaning.
  DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = ANY(v_doomed);
  GET DIAGNOSTICS v_runs = ROW_COUNT;

  RETURN jsonb_build_object(
    'ok', true, 'kept', p_keep_run, 'rows_purged', v_total,
    'prior_runs_deleted', v_runs, 'cleared_by_table', v_cleared,
    'evidence_preserved', (SELECT count(*) FROM public.ottoq_run_scope_registry WHERE class='evidence'),
    'retry_passes', v_pass,
    'unregistered_run_scoped', v_warn, 'retention_armed', true);
END;
$function$;

DO $assertions$
DECLARE
  v_src text; v_rows_before int; v_rows_after int; v_bad int; v_order text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid='public.ottoq_purge_prior_runs(uuid)'::regprocedure;

  -- A1. The alphabetical ordering is gone and a computed one replaces it.
  IF v_src LIKE '%WHERE class = ''engine'' ORDER BY table_name%' THEN
    RAISE EXCEPTION '0345 A1a: the alphabetical ORDER BY survives';
  END IF;
  IF v_src NOT LIKE '%WITH RECURSIVE eng AS%' OR v_src NOT LIKE '%ORDER BY COALESCE(ranked.d, 0) DESC%' THEN
    RAISE EXCEPTION '0345 A1b: the dependency ordering is not present';
  END IF;

  -- A2. THE ROW SET IS UNCHANGED, only reordered. A DISTINCT slipped into the
  -- iteration would silently stop deleting a table registered on two columns.
  SELECT count(*) INTO v_rows_before
    FROM public.ottoq_run_scope_registry WHERE class='engine';
  WITH RECURSIVE eng AS (
    SELECT table_name, column_name FROM public.ottoq_run_scope_registry WHERE class='engine'
  ),
  tbl AS (SELECT DISTINCT table_name FROM eng),
  edge AS (
    SELECT DISTINCT c.conrelid::regclass::text AS child, c.confrelid::regclass::text AS parent
      FROM pg_constraint c
     WHERE c.contype='f' AND c.conrelid <> c.confrelid
       AND c.conrelid::regclass::text IN (SELECT table_name FROM tbl)
       AND c.confrelid::regclass::text IN (SELECT table_name FROM tbl)
  ),
  depth AS (
    SELECT t.table_name, 0 AS d FROM tbl t
     WHERE NOT EXISTS (SELECT 1 FROM edge e WHERE e.child = t.table_name)
    UNION ALL
    SELECT e.child, d.d+1 FROM edge e JOIN depth d ON d.table_name = e.parent WHERE d.d < 20
  ),
  ranked AS (SELECT table_name, max(d) AS d FROM depth GROUP BY table_name)
  SELECT count(*) INTO v_rows_after
    FROM eng LEFT JOIN ranked ON ranked.table_name = eng.table_name;
  IF v_rows_after <> v_rows_before THEN
    RAISE EXCEPTION '0345 A2: the ordering query yields % rows, the registry has % engine rows',
      v_rows_after, v_rows_before;
  END IF;

  -- A3. THE ORDER IS ACTUALLY CORRECT, evaluated against every engine->engine FK
  -- rather than argued. For each edge, the child's position must precede the
  -- parent's. This is the assertion the original function never had.
  WITH RECURSIVE eng AS (
    SELECT table_name, column_name FROM public.ottoq_run_scope_registry WHERE class='engine'
  ),
  tbl AS (SELECT DISTINCT table_name FROM eng),
  edge AS (
    SELECT DISTINCT c.conrelid::regclass::text AS child, c.confrelid::regclass::text AS parent
      FROM pg_constraint c
     WHERE c.contype='f' AND c.conrelid <> c.confrelid
       AND c.conrelid::regclass::text IN (SELECT table_name FROM tbl)
       AND c.confrelid::regclass::text IN (SELECT table_name FROM tbl)
  ),
  depth AS (
    SELECT t.table_name, 0 AS d FROM tbl t
     WHERE NOT EXISTS (SELECT 1 FROM edge e WHERE e.child = t.table_name)
    UNION ALL
    SELECT e.child, d.d+1 FROM edge e JOIN depth d ON d.table_name = e.parent WHERE d.d < 20
  ),
  ranked AS (SELECT table_name, max(d) AS d FROM depth GROUP BY table_name),
  pos AS (
    SELECT DISTINCT eng.table_name,
           row_number() OVER (ORDER BY COALESCE(ranked.d,0) DESC, eng.table_name) AS ord
      FROM eng LEFT JOIN ranked ON ranked.table_name = eng.table_name
  )
  SELECT count(*) INTO v_bad
    FROM edge e
    JOIN pos pc ON pc.table_name = e.child
    JOIN pos pp ON pp.table_name = e.parent
   WHERE pc.ord >= pp.ord;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0345 A3: % engine FK edge(s) are STILL ordered parent-first', v_bad;
  END IF;

  -- A4. And prove the OLD ordering would have failed A3 — so A3 is a real test
  -- and not one that any ordering passes.
  WITH eng AS (
    SELECT DISTINCT table_name FROM public.ottoq_run_scope_registry WHERE class='engine'
  ),
  edge AS (
    SELECT DISTINCT c.conrelid::regclass::text AS child, c.confrelid::regclass::text AS parent
      FROM pg_constraint c
     WHERE c.contype='f' AND c.conrelid <> c.confrelid
       AND c.conrelid::regclass::text IN (SELECT table_name FROM eng)
       AND c.confrelid::regclass::text IN (SELECT table_name FROM eng)
  ),
  pos AS (SELECT table_name, row_number() OVER (ORDER BY table_name) AS ord FROM eng)
  SELECT count(*) INTO v_bad
    FROM edge e JOIN pos pc ON pc.table_name=e.child JOIN pos pp ON pp.table_name=e.parent
   WHERE pc.ord >= pp.ord;
  IF v_bad = 0 THEN
    RAISE EXCEPTION '0345 A4: the alphabetical ordering passes the same test, so A3 proves nothing';
  END IF;
  RAISE NOTICE '0345 A4: the previous alphabetical ordering misordered % engine FK edge(s); the new ordering misorders 0', v_bad;

  -- A5. The retry backstop still RAISES rather than swallowing.
  IF v_src NOT LIKE '%purge refused: % engine table(s) could not be cleared%' THEN
    RAISE EXCEPTION '0345 A5: the residue raise is missing — a failure could now pass silently';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0345_the_purge_deletes_engine_tables_alphabetically_not_by_dependency', true,
  'Step (4) of ottoq_purge_prior_runs iterated engine tables ORDER BY table_name under a comment claiming "CHILDREN FIRST". Alphabetical order misorders three of six engine->engine FK relationships (recall_refusals->recall_decisions, rule_evaluations->events, ocpp_messages->ocpp_sessions); the first raised 23503 on cron jobid 726 and rolled back an entire ottoq_start_demo_run, which is why the Twin start door was shut. Ordering is now a depth computed from pg_constraint on every call, deletion runs children-first, and a bounded 3-pass retry raises with every survivor named rather than swallowing. forces_recert TRUE because 0145/0146 established unscoped readers exist, and this turns an always-failing purge into a succeeding one -- a change to the world a new run boots into.',
  now())
ON CONFLICT(name) DO NOTHING;
