-- migration-version: 20260914094551
-- migration-name:    0294_the_purge_commits_inside_a_cursor_loop
--
-- 0294  THE PURGE COMMITS INSIDE A CURSOR LOOP
--
-- G63. The fix 0293 should have been. The nightly run purge (cron job 625) has
-- never once succeeded; every firing dies in a quarter-second with
--
--   ERROR:  invalid transaction termination
--   CONTEXT:  ottoq_retention_purge_runs(...) line 152 at COMMIT
--
-- because that COMMIT sits inside a `FOR v_reg IN <query> LOOP`. PL/pgSQL runs
-- such a loop over an internal cursor and a procedure may not commit while one
-- is open. The second COMMIT, outside both loops, was always fine.
--
-- THE CORRECTED A/B (db/checks/0226), differing in the right variable:
--
--   procedure                                    FOR..IN loops  COMMITs  result
--   ottoq_retention_purge_runs                               1        2  FAILS
--   ottoq_retention_purge_worker(int,int,...)                0        8  succeeds
--
-- 0293 blamed the cron command's statement count instead, on an A/B whose two
-- jobs differed in two ways. A single-statement probe failed identically and
-- refuted it. 0293's changes are kept -- they are correct in themselves -- but
-- they were never the cause.
--
-- ---------------------------------------------------------------------------
-- WHAT CHANGES, AND NOTHING ELSE CHANGES.
--
-- The registry is read into two arrays BEFORE the loop, and the loop becomes an
-- integer loop. That is the whole fix:
--
--   FOR v_reg IN SELECT g.table_name, g.column_name ... ORDER BY ... LOOP
--     -> SELECT array_agg(g.table_name ORDER BY ...), array_agg(g.column_name ORDER BY ...)
--          INTO v_tabs, v_cols ...
--        FOR v_i IN 1 .. COALESCE(array_length(v_tabs,1),0) LOOP
--
-- and the three references v_reg.t / v_reg.c become v_tabs[v_i] / v_cols[v_i].
--
-- THE ORDER BY IS PRESERVED CHARACTER FOR CHARACTER. Largest table first is
-- what makes p_time_budget_s spend itself where it matters, and A4 asserts the
-- new expression yields the same sequence as the old cursor query did.
--
-- EVERYTHING ELSE IS BYTE-IDENTICAL and A2 asserts it: the advisory lock, the
-- run-scope refusal, both 0250 allow-list guards, the 0269 scheduled-round
-- skip, the in-flight pair skip, the doomed-set SELECT, the micro-batched
-- DELETE, the 0251 stamping rule and the closing state update. This file
-- changes loop mechanics. It does not change what gets deleted, or when, or
-- what refuses.
--
-- AND THE TIMEOUT IS CARRIED FORWARD DELIBERATELY. CREATE OR REPLACE PROCEDURE
-- REPLACES proconfig: omit the SET clause and 0293's statement_timeout silently
-- disappears, leaving the purge under this database's 2-minute default. The new
-- definition keeps `SET statement_timeout TO '10min'` and A3 asserts it
-- survived.
--
-- ---------------------------------------------------------------------------
-- HOW THIS IS VERIFIED, because it cannot be verified the usual way. The
-- Supabase management SQL channel cannot execute a COMMIT-ing procedure at all
-- -- it wraps every submission in a transaction, so a bare CALL raises the same
-- 2D000 for an unrelated reason, a guaranteed false negative -- and it pools
-- connections, so pg_temp cannot be built up across statements. The only honest
-- instrument is a real pg_cron firing. After this applies, a transient probe
-- job calls the procedure with a 999-day keep window, which matches ZERO rows
-- (the oldest unpurged run is 2026-06-20) and so deletes nothing, while still
-- reaching the COMMIT -- the loop's COMMIT sits BEFORE its `EXIT WHEN v_n = 0`.
-- That probe is what caught 0293's wrong fix within two minutes.
--
-- ---------------------------------------------------------------------------
-- AND A1 CAUGHT THIS FILE'S OWN COMMENTS ON THE FIRST DRY RUN. The assertion
-- greps prosrc for the removed loop, and prosrc includes comments -- so an
-- explanatory comment that QUOTED the old shape satisfied the grep and failed
-- the assertion. The assertion is right and stays strict: the pattern must not
-- appear in this procedure's source at all, in code or in prose. The comments
-- were reworded and the removed shape is quoted in db/checks/0226 instead.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0294 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0294 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0294 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0294 P-: nothing in flight';
END $inflight$;

-- P0. SNAPSHOT + md5 GUARD ---------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (taken_at, label, object_kind, schema_name, object_name, definition, def_md5)
SELECT now(), '0294_pre', 'procedure', 'public',
       'ottoq_retention_purge_runs(integer,integer,interval,boolean)',
       pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure));

DO $p0$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure))
    INTO v_md5;
  IF v_md5 <> 'fefb3f38aa89373f53b452a38dd1c59c' THEN
    RAISE EXCEPTION '0294 P0: the procedure is not the definition this file was written '
                    'against (live md5 %). Re-read it and rebase rather than overwriting '
                    'someone else''s change', v_md5;
  END IF;
  RAISE NOTICE '0294 P0: snapshotted, and the live definition is the expected one';
END $p0$;

-- P1. THE DEFECT IS PRESENT AND IS THE ONE DESCRIBED -------------------------
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  IF position('FOR v_reg IN' in v_src) = 0 THEN
    RAISE EXCEPTION '0294 P1: the cursor loop this file removes is not there. Either it was '
                    'already fixed or the procedure changed shape; re-read it';
  END IF;
  IF position('      COMMIT;' in v_src) = 0 THEN
    RAISE EXCEPTION '0294 P1: the in-loop COMMIT is not where this file expects it';
  END IF;
  RAISE NOTICE '0294 P1: the FOR..IN cursor loop and its in-loop COMMIT are both present';
END $p1$;

-- P2. THE FAILURE IS ON THE RECORD -------------------------------------------
DO $p2$
DECLARE v_failed int;
BEGIN
  SELECT count(*) INTO v_failed FROM cron.job_run_details
   WHERE jobid = 625 AND status = 'failed'
     AND return_message ILIKE '%invalid transaction termination%';
  IF v_failed = 0 THEN
    RAISE EXCEPTION '0294 P2: no failed firing of job 625 with that error is on record. '
                    'This file exists to fix a measured failure; re-diagnose first';
  END IF;
  RAISE NOTICE '0294 P2: % failed firing(s) on record', v_failed;
END $p2$;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_runs(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_dry_run boolean DEFAULT false)
 LANGUAGE plpgsql
 SET statement_timeout TO '10min'
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
  v_bad     text;
  v_stamped boolean := false;   -- 0251
  -- 0294 (G63): was a record variable driven by a query cursor loop over the
  -- registry. A procedure may not COMMIT while a cursor is open, so the COMMIT
  -- below raised 2D000 on every firing this job ever had and it never purged a
  -- row. The registry is read into arrays before the loop instead; the removed
  -- shape is quoted in db/checks/0226, deliberately not here -- A1 greps this
  -- source for it and a comment would satisfy the grep.
  v_tabs    text[];
  v_cols    text[];
  v_i       int;
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
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s).', v_block;
  END IF;

  -- 0250 GUARD 1: the allow-list narrows the registry; it may never widen it.
  SELECT string_agg(a.table_name, ', ') INTO v_bad
    FROM public.ottoq_retention_engine_allowlist a
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_name = a.table_name AND g.class = 'engine'
                        AND g.table_schema = 'public');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed but not class=engine: %', v_bad;
  END IF;

  -- 0250 GUARD 2: no allow-listed table may parent a NO ACTION/RESTRICT FK.
  SELECT string_agg(DISTINCT c.confrelid::regclass::text || ' <- ' || c.conrelid::regclass::text, ', ')
    INTO v_bad
    FROM pg_constraint c
    JOIN public.ottoq_retention_engine_allowlist a
      ON a.table_name = c.confrelid::regclass::text
   WHERE c.contype = 'f' AND c.confdeltype IN ('a', 'r');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed table is the parent of a NO ACTION/RESTRICT FK: %', v_bad;
  END IF;

  -- 0269 (G23): A SCHEDULED ROUND, not merely a running pair.
  -- db/checks/0202: a round is ten pairs on 14-minute slots and a pair runs
  -- 130-270 s, so for most of a round nothing is in pg_stat_activity and the
  -- guard below sees an idle system. A purge landing in one of those gaps moves
  -- the residue canon BETWEEN two pairs of the same round. Placed here, after
  -- the run-scope check and both allow-list guards, so those three refusals stay
  -- reachable; skips rather than raises, because this runs from cron.
  -- Round jobs are matched by IMMINENCE (+/- 3 h of their own date-pinned fire
  -- time), never by existence: nothing unschedules them after they fire, so an
  -- existence test would disable the purge permanently after the first round.
  -- An unrecognised schedule shape blocks -- unrecognised means unsafe.
  IF EXISTS (
      SELECT 1 FROM cron.job j
       WHERE (j.active AND (j.command ILIKE '%ottoq_determinism_pair%'
                         OR j.command ILIKE '%ottoq_cert_battery_step%'))
          OR (j.jobname ~ '^r[0-9]+_' AND
              CASE WHEN j.schedule ~ '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ \*$'
                   THEN make_timestamptz(extract(year from now())::int,
                                         split_part(j.schedule,' ',4)::int,
                                         split_part(j.schedule,' ',3)::int,
                                         split_part(j.schedule,' ',2)::int,
                                         split_part(j.schedule,' ',1)::int, 0, 'UTC')
                        BETWEEN now() - interval '3 hours' AND now() + interval '3 hours'
                   ELSE true END)) THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: a certification round is scheduled - skipped';
    RETURN;
  END IF;

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

  -- 0294 (G63): READ THE REGISTRY INTO ARRAYS, THEN LOOP BY INDEX. The previous
  -- version iterated this same query with a record cursor, which holds a portal
  -- open across the COMMIT below -- PL/pgSQL forbids that, and it is the whole
  -- defect. The ORDER BY is preserved character for character: largest table
  -- first is what makes p_time_budget_s spend itself where it matters.
  SELECT array_agg(g.table_name  ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name),
         array_agg(g.column_name ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name)
    INTO v_tabs, v_cols
    FROM public.ottoq_run_scope_registry g
    JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
   WHERE g.class = 'engine' AND g.table_schema = 'public'
     AND to_regclass('public.' || g.table_name) IS NOT NULL;

  FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);

      IF p_dry_run THEN
        EXECUTE format('SELECT count(*) FROM public.%1$I WHERE %2$I = ANY($1)', v_tabs[v_i], v_cols[v_i])
          INTO v_n USING v_doomed;
        RAISE NOTICE '  dry run: % would lose % row(s)', v_tabs[v_i], v_n;
        v_total := v_total + v_n;
        EXIT;
      END IF;

      PERFORM set_config('ottoq.retention', 'on', true);

      EXECUTE format(
        'DELETE FROM public.%1$I WHERE ctid IN '
        '(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)',
        v_tabs[v_i], v_cols[v_i]) USING v_doomed, p_micro_batch;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- 0251: STAMP ON THE FIRST ROW ACTUALLY DELETED, IN THE SAME TRANSACTION
      -- as that delete, so the marker and the deletion commit together. From
      -- this moment the run's KPIs are not whole and ottoq_kpi_five must say so.
      -- Stamping before the loop would over-claim on a pass that deletes
      -- nothing; stamping at the end would leave a budget-cut pass unmarked,
      -- which is the common case and the dangerous one.
      IF v_n > 0 AND NOT v_stamped THEN
        UPDATE public.ottoq_sim_runs
           SET purged_at = now()
         WHERE sim_run_id = ANY(v_doomed) AND purged_at IS NULL;
        v_stamped := true;
      END IF;

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

-- ---------------------------------------------------------------------------
-- A1. THE CURSOR LOOP IS GONE AND THE COMMIT REMAINS.
DO $a1$
DECLARE v_src text; v_forin int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  IF position('FOR v_reg IN' in v_src) > 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the FOR..IN cursor loop is still there';
  END IF;
  SELECT count(*) INTO v_forin FROM regexp_matches(v_src, 'FOR\s+\w+\s+IN\s+SELECT', 'g');
  IF v_forin > 0 THEN
    RAISE EXCEPTION 'A1 FAILED: % query-driven FOR loop(s) remain; a COMMIT cannot live '
                    'inside one', v_forin;
  END IF;
  IF position('FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP' in v_src) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the integer loop that replaces it is not there';
  END IF;
  IF position('      COMMIT;' in v_src) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the in-loop COMMIT was lost -- the purge would never commit '
                    'a micro-batch and the time budget would be meaningless';
  END IF;
  RAISE NOTICE 'A1 OK: cursor loop gone, integer loop in, COMMIT still in the inner loop';
END $a1$;

-- A2. EVERY GUARD AND EVERY WRITE IS BYTE-IDENTICAL.
-- This file changes loop mechanics. If it changed WHAT is deleted, or what
-- refuses, that is a different migration and this one is wrong.
DO $a2$
DECLARE v_src text; v_missing text := '';
  v_frag text; v_frags text[] := ARRAY[
    'pg_try_advisory_lock(hashtext(''ottoq_retention_purge''))',
    'purge refused: % blocking run-scope defect(s).',
    'purge refused: allow-listed but not class=engine: %',
    'purge refused: allow-listed table is the parent of a NO ACTION/RESTRICT FK: %',
    'retention purge: a certification round is scheduled - skipped',
    'retention purge: % certification pair(s) in flight - skipped',
    'AND COALESCE(sr.run_by,'''') <> ''production_live''',
    'EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id)',
    '''DELETE FROM public.%1$I WHERE ctid IN ''',
    '''(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)''',
    'IF v_n > 0 AND NOT v_stamped THEN',
    'SET purged_at = now()',
    'WHERE sim_run_id = ANY(v_doomed) AND purged_at IS NULL',
    'SET pass_deleted = pass_deleted + v_total, updated_at = now()',
    'PERFORM set_config(''ottoq.retention'', ''on'', true)',
    'EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s)' ];
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  FOREACH v_frag IN ARRAY v_frags LOOP
    IF position(v_frag in v_src) = 0 THEN
      v_missing := v_missing || v_frag || ' | ';
    END IF;
  END LOOP;
  IF v_missing <> '' THEN
    RAISE EXCEPTION 'A2 FAILED: these must have survived unchanged and did not: %', v_missing;
  END IF;
  RAISE NOTICE 'A2 OK: all % guards, predicates and writes survived verbatim',
               array_length(v_frags, 1);
END $a2$;

-- A3. THE TIMEOUT SURVIVED THE REPLACE.
-- CREATE OR REPLACE PROCEDURE REPLACES proconfig. Omitting the SET clause would
-- have silently dropped 0293's statement_timeout and left the purge under this
-- database's 2-minute default.
DO $a3$
DECLARE v_config text;
BEGIN
  SELECT array_to_string(p.proconfig, ' | ') INTO v_config
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  IF v_config IS NULL OR v_config !~ 'statement_timeout=10min' THEN
    RAISE EXCEPTION 'A3 FAILED: statement_timeout=10min did not survive the replace (%)',
                    COALESCE(v_config, 'NULL');
  END IF;
  RAISE NOTICE 'A3 OK: procedure still carries %', v_config;
END $a3$;

-- A4. THE NEW ORDERING IS THE OLD ORDERING.
-- Not "an ORDER BY is present" but "it yields the same sequence the cursor
-- query did". Largest table first is load-bearing for the time budget.
DO $a4$
DECLARE v_arr text[]; v_cur text[];
BEGIN
  SELECT array_agg(g.table_name ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name)
    INTO v_arr
    FROM public.ottoq_run_scope_registry g
    JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
   WHERE g.class = 'engine' AND g.table_schema = 'public'
     AND to_regclass('public.' || g.table_name) IS NOT NULL;
  SELECT array_agg(t) INTO v_cur FROM (
    SELECT g.table_name AS t
      FROM public.ottoq_run_scope_registry g
      JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
     WHERE g.class = 'engine' AND g.table_schema = 'public'
       AND to_regclass('public.' || g.table_name) IS NOT NULL
     ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name) s;
  IF v_arr IS DISTINCT FROM v_cur THEN
    RAISE EXCEPTION 'A4 FAILED: the array ordering (%) differs from the cursor ordering (%)',
                    v_arr, v_cur;
  END IF;
  IF COALESCE(array_length(v_arr, 1), 0) = 0 THEN
    RAISE EXCEPTION 'A4 FAILED: the registry yields no tables, so the comparison is vacuous '
                    'and the purge would be a no-op for a reason unrelated to this file';
  END IF;
  RAISE NOTICE 'A4 OK: % tables, same order as the cursor query produced',
               array_length(v_arr, 1);
END $a4$;

-- A5. THIS FILE PURGED NOTHING.
DO $a5$
DECLARE v_purged int;
BEGIN
  SELECT count(*) INTO v_purged FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL;
  IF v_purged <> 939 THEN
    RAISE EXCEPTION 'A5 FAILED: purged run count is %, was 939 when this file was written. '
                    'Replacing a procedure must not run it', v_purged;
  END IF;
  RAISE NOTICE 'A5 OK: 939 purged runs, unchanged -- this file moved no data';
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0294_the_purge_commits_inside_a_cursor_loop', false,
 'G63. public.ottoq_retention_purge_runs COMMITs inside a FOR..IN query loop, which PL/pgSQL forbids because such a loop holds an open cursor -- so cron job 625 raised 2D000 on every firing it ever had and never purged a row. The registry query is hoisted into two arrays before the loop and the loop becomes FOR v_i IN 1 .. array_length, so no cursor is open across the COMMIT; the three v_reg.t / v_reg.c references become v_tabs[v_i] / v_cols[v_i]. Nothing else changes: A2 asserts sixteen fragments survived verbatim -- the advisory lock, the run-scope refusal, both 0250 allow-list guards, the 0269 scheduled-round skip, the in-flight pair skip, the doomed-set predicates, the micro-batched DELETE, the 0251 stamping rule, the retention-state update and the time-budget exit. A3 asserts statement_timeout=10min survived, because CREATE OR REPLACE PROCEDURE REPLACES proconfig and omitting the SET clause would silently have dropped 0293 change. A4 asserts the new array ORDER BY yields the same sequence the cursor query did, largest table first, and refuses to pass vacuously on an empty registry. A5 asserts no rows were purged by the replace itself. Supersedes 0293 diagnosis, which blamed the cron command statement count on an A/B whose two jobs differed in two ways; a single-statement probe failed identically and refuted it (db/checks/0226). forces_recert=false: no engine function, no frame, no decide path; the purge only ever touches runs already archived and finished, and the 0269 round guard is preserved verbatim.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 20260914094551 -- AND IT WAS ONLY HALF THE FIX.
--
-- Every precondition and assertion passed. The job still failed, at line 166
-- instead of 152 -- which is THE SAME in-loop COMMIT, displaced by the fourteen
-- lines of comment this file added. I briefly read that as this file having
-- failed. It had not.
--
-- There were TWO independent causes, and each alone was enough to break it:
--   1. the COMMIT inside the cursor loop, which this file removed;
--   2. the SET clause on the procedure, WHICH 0293 HAD JUST ADDED. A PostgreSQL
--      procedure carrying a SET clause may not execute transaction control.
--
-- So the fix for the first arrived at the same moment as the second, and the
-- symptom never changed. 0295 removes the SET clause; the probe then succeeded
-- in 62 seconds.
--
-- A3 IN THIS FILE IS NOW WRONG AND MUST NOT BE COPIED. It asserts
-- statement_timeout=10min survived the replace, which was correct as a guard
-- against CREATE OR REPLACE silently dropping proconfig -- and exactly the
-- wrong thing to want. The timeout must NOT be on the procedure at all. 0295's
-- A1 asserts the opposite and is the one to follow.
--
-- The loop change in this file is sound and stays. db/checks/0226 carries the
-- full corrected account.
-- ===========================================================================
