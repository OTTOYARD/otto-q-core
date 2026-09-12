-- migration-version: 20260912034252
-- migration-name: 0251_a_purged_run_must_say_gone_not_zero
-- ===========================================================================
-- 0251  A PURGED RUN MUST SAY "GONE", NOT "ZERO"
-- ===========================================================================
-- probe:          db/checks/0165 ("STILL OPEN", item 1)
-- forces_recert:  FALSE
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT. pg_stat_activity is the only
-- authority.
--
-- THE DEFECT, READ FROM ottoq_kpi_five's LIVE BODY
--
-- KPI 1 and KPI 2 are wrapped in COALESCE(..., '{}'::jsonb). KPIs 3, 4 and 5 are
-- scalar subqueries against per-run views. So for a run whose engine rows have
-- been deleted, the CLI returns:
--
--   asset_hours_available_per_day          {}
--   service_point_turns_per_point_per_day  {}
--   peak_site_kw                           null
--   touch_events_per_turn                  null
--   p95_time_to_service_min                null
--
-- which is EXACTLY what a real run with no bookings and no touch events returns.
-- The payload is well-formed, it carries a run ID, and it is empty for a reason
-- it cannot state. "No number ships without a run ID" is the floor of this
-- project; a number that ships WITH a run ID and is silently hollow is worse
-- than no number, because it passes the check.
--
-- This is the blocker on scheduling the purge at all. 0250 made the purge
-- fail-closed about WHAT it deletes; this makes the KPI honest about what has
-- been deleted. The calendar must not be purged before both are true.
--
-- WHAT "PURGED" MEANS HERE, PRECISELY
--
-- Not "fully purged". A run is stamped the moment the FIRST of its rows is
-- deleted, because from that moment its KPIs are no longer whole -- and a pass
-- cut short by its time budget leaves a run partially purged, which is the
-- common case, not the exception. The column is therefore a claim about
-- COMPLETENESS, not about completion, and its comment says so.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The marker.
-- ---------------------------------------------------------------------------
ALTER TABLE public.ottoq_sim_runs
  ADD COLUMN IF NOT EXISTS purged_at timestamptz;

COMMENT ON COLUMN public.ottoq_sim_runs.purged_at IS
  '0251: set by ottoq_retention_purge_runs the moment the FIRST engine row '
  'belonging to this run is deleted. It means "this run''s row set is no longer '
  'whole", NOT "this run is fully purged" -- a pass cut short by its time budget '
  'leaves a run partially purged and that is the common case. Once set, '
  'ottoq_kpi_five reports the run as purged and refuses to present its headline '
  'KPIs as complete. Never cleared. The run''s VERDICT (validation_notes) is '
  'untouched by any purge and stays authoritative.';

-- ---------------------------------------------------------------------------
-- 2. The purge stamps it, once, on its first real delete.
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
  v_bad     text;
  v_stamped boolean := false;   -- 0251
  v_reg     record;             -- 0249: not `r`; it shadowed the sr alias below
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

  FOR v_reg IN
    SELECT g.table_name AS t, g.column_name AS c
      FROM public.ottoq_run_scope_registry g
      JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
     WHERE g.class = 'engine' AND g.table_schema = 'public'
       AND to_regclass('public.' || g.table_name) IS NOT NULL
     ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name
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
-- 3. Backfill the runs the two 13:38-13:46 passes already touched.
--
--    Those passes ran before this column existed, so their runs are unmarked
--    and would report hollow KPIs as complete. The doomed predicate is
--    reconstructed with the SAME keep window and conditions the passes used.
--    0165 records what was actually reached: ottoq_rule_evaluations (drained)
--    and ottoq_events (partial).
--
--    THE CUTOFF IS 2026-09-07 13:38, AND THE FIRST DRAFT OF THIS FILE HAD IT
--    WRONG. It said 2026-09-09 11:38 -- I wrote "48 hours before the purge" and
--    then subtracted two hours instead of two days. Verified read-only before
--    applying:
--
--      cutoff 2026-09-07 13:38  ->  729 runs   (matches the purge's own doomed
--                                               set exactly, which is the check)
--      cutoff 2026-09-09 11:38  ->  911 runs
--      difference               ->  182 runs WRONGLY STAMPED
--
--    Those 182 span rounds 31-35. Every one of them is intact, and stamping
--    them would have made today's certification runs report their KPIs as GONE.
--
--    AND THE COMMENT THAT LET IT THROUGH IS CORRECTED TOO. The first draft said
--    "an over-stamp here is safe (it says 'not whole' of a run that is whole)."
--    THAT IS FALSE. Over-stamping suppresses a real number; under-stamping ships
--    a hollow one. Both are wrong, in opposite directions, and calling one of
--    them safe is what made a two-day arithmetic slip look tolerable instead of
--    fatal. The cutoff is not a judgement call with a safe side -- it either
--    reproduces the doomed set or it does not, and the test is that it returns
--    exactly 729.
-- ---------------------------------------------------------------------------
UPDATE public.ottoq_sim_runs sr
   SET purged_at = '2026-09-09 13:38:00+00'::timestamptz
 WHERE sr.purged_at IS NULL
   AND sr.status <> 'running'
   AND COALESCE(sr.run_by,'') <> 'production_live'
   AND sr.started_at < '2026-09-07 13:38:00+00'::timestamptz   -- 48h before the pass
   AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id);

-- ---------------------------------------------------------------------------
-- 4. The KPI says so.
--
--    The existing hundred-line body is MOVED, not retyped: derived from
--    pg_get_functiondef with a uniqueness-asserted anchor, exactly as 0243 and
--    0246 did. Retyping a body that computes eight shipped numbers is how a
--    silent arithmetic change gets in behind a migration whose stated purpose
--    is something else.
--
--    Headline keys keep their names and shapes so a consumer does not break,
--    but a purged run reports null instead of {} or a hollow scalar, and carries
--    a 'purged' block saying why.
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
  d  text;
  a  text := 'FUNCTION public.ottoq_kpi_five(p_run uuid)';
  nd text;
BEGIN
  d := pg_get_functiondef('public.ottoq_kpi_five(uuid)'::regprocedure);

  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN
    RAISE EXCEPTION 'anchor % occurs % time(s) in ottoq_kpi_five, expected exactly 1',
      a, (length(d) - length(replace(d, a, ''))) / length(a);
  END IF;

  nd := replace(d, a, 'FUNCTION public.ottoq_kpi_five_raw(p_run uuid)');
  EXECUTE nd;
END
$mig$;

COMMENT ON FUNCTION public.ottoq_kpi_five_raw(uuid) IS
  '0251: the pre-0251 body of ottoq_kpi_five, moved verbatim by anchored '
  'substitution from pg_get_functiondef. It computes the numbers; it does not '
  'know whether the rows behind them still exist. ottoq_kpi_five wraps it and '
  'answers that question. Call the wrapper, never this.';

CREATE OR REPLACE FUNCTION public.ottoq_kpi_five(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH p AS (SELECT purged_at FROM public.ottoq_sim_runs WHERE sim_run_id = p_run)
  SELECT public.ottoq_kpi_five_raw(p_run)
         || CASE WHEN (SELECT purged_at FROM p) IS NULL
                 THEN jsonb_build_object('purged', NULL)
                 ELSE jsonb_build_object(
                        'purged', jsonb_build_object(
                          'purged_at', (SELECT purged_at FROM p),
                          'meaning', 'Engine rows for this run have been deleted by '
                                     'ottoq_retention_purge_runs. Its KPIs are NOT '
                                     'recomputable and the nulls below mean GONE, not ZERO. '
                                     'The certification verdict is unaffected: '
                                     'validation_notes lives on ottoq_sim_runs and no purge '
                                     'touches it.',
                          'affected_kpis', jsonb_build_array(
                            'asset_hours_available_per_day',
                            'service_point_turns_per_point_per_day',
                            'peak_site_kw', 'peak_site_kw_demand',
                            'touch_events_per_turn',
                            'p95_time_to_service_min', 'p50_time_to_service_min',
                            'returns_unserved')),
                        'asset_hours_available_per_day',          NULL,
                        'service_point_turns_per_point_per_day',  NULL,
                        'peak_site_kw',                           NULL,
                        'peak_site_kw_demand',                    NULL,
                        'touch_events_per_turn',                  NULL,
                        'p95_time_to_service_min',                NULL,
                        'p50_time_to_service_min',                NULL,
                        'returns_unserved',                       NULL)
            END;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int; v_src text; v_purged uuid; v_clean uuid;
BEGIN
  -- A1. The column exists and is nullable.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_sim_runs'
     AND column_name='purged_at' AND is_nullable='YES';
  IF v_n <> 1 THEN RAISE EXCEPTION 'A1 FAILED: purged_at missing or NOT NULL'; END IF;

  -- A2. The purge stamps it, and stamps it on a real delete rather than up front.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_retention_purge_runs';
  IF v_src !~ 'SET purged_at = now\(\)' THEN
    RAISE EXCEPTION 'A2 FAILED: the purge does not stamp purged_at';
  END IF;
  IF v_src !~ 'IF v_n > 0 AND NOT v_stamped' THEN
    RAISE EXCEPTION 'A2 FAILED: the stamp is not gated on a row actually being deleted';
  END IF;

  -- A3. 0250 and 0164 survive the rewrite.
  IF v_src ~* 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs' THEN
    RAISE EXCEPTION 'A3 FAILED: DELETE against ottoq_sim_runs (0164)';
  END IF;
  IF v_src !~ 'ottoq_retention_engine_allowlist' THEN
    RAISE EXCEPTION 'A3 FAILED: the allow-list join is gone (0250)';
  END IF;

  -- A4. BEHAVIOURAL, and the first one this line of work has had. A purged run
  --     and a clean run must not return the same shape.
  SELECT sim_run_id INTO v_purged FROM public.ottoq_sim_runs
   WHERE purged_at IS NOT NULL LIMIT 1;
  SELECT sim_run_id INTO v_clean  FROM public.ottoq_sim_runs
   WHERE purged_at IS NULL AND validation_notes IS NOT NULL
   ORDER BY started_at DESC LIMIT 1;

  IF v_purged IS NULL THEN
    RAISE EXCEPTION 'A4 FAILED: no purged run to test against -- the backfill did nothing';
  END IF;
  IF jsonb_typeof(public.ottoq_kpi_five(v_purged)->'purged') <> 'object' THEN
    RAISE EXCEPTION 'A4 FAILED: a purged run does not report the purged block';
  END IF;
  IF public.ottoq_kpi_five(v_purged)->'asset_hours_available_per_day' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'A4 FAILED: a purged run still reports KPI 1 as if complete';
  END IF;
  IF v_clean IS NOT NULL THEN
    IF public.ottoq_kpi_five(v_clean)->'purged' <> 'null'::jsonb THEN
      RAISE EXCEPTION 'A4 FAILED: an unpurged run is reported as purged';
    END IF;
  END IF;

  -- A5. The move happened and the wrapper delegates rather than duplicating.
  IF to_regprocedure('public.ottoq_kpi_five_raw(uuid)') IS NULL THEN
    RAISE EXCEPTION 'A5 FAILED: ottoq_kpi_five_raw was not created';
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_kpi_five';
  IF v_src !~ 'ottoq_kpi_five_raw' THEN
    RAISE EXCEPTION 'A5 FAILED: ottoq_kpi_five does not delegate to the moved body';
  END IF;

  -- A6. The eleven keys still exist on an UNPURGED run -- the move must not have
  --     dropped a number while relabelling the payload.
  IF v_clean IS NOT NULL THEN
    SELECT count(*) INTO v_n FROM jsonb_object_keys(public.ottoq_kpi_five(v_clean)) k
     WHERE k IN ('asset_hours_available_per_day','service_point_turns_per_point_per_day',
                 'peak_site_kw','peak_site_kw_demand','touch_events_per_turn',
                 'p95_time_to_service_min','p50_time_to_service_min','returns_unserved',
                 'run_key','audit','provenance');
    IF v_n <> 11 THEN
      RAISE EXCEPTION 'A6 FAILED: an unpurged payload lost keys -- found % of 11', v_n;
    END IF;
  END IF;

  -- A7. THE BACKFILL REPRODUCED THE PURGE'S DOOMED SET, NOT SOMETHING NEAR IT.
  --     Pinned to 729 because that is what the pass actually doomed; a cutoff
  --     that is off by so much as a batch of runs fails here instead of quietly
  --     suppressing good KPIs. This assertion exists because the first draft's
  --     cutoff was two DAYS off and would have stamped 182 intact runs, rounds
  --     31-35 among them.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL;
  IF v_n <> 729 THEN
    RAISE EXCEPTION 'A7 FAILED: backfill stamped % run(s); the purge doomed exactly 729. '
                    'A mismatch means the cutoff does not reproduce the doomed set.', v_n;
  END IF;
  RAISE NOTICE 'A1-A7 PASSED; % run(s) marked purged, matching the doomed set exactly', v_n;
END $$;
-- ===========================================================================
-- APPLIED 2026-09-12 03:42:52 UTC (2026-09-11 10:42 PM CT) -- version 20260912034252
--
-- A1-A7 all passed. 729 runs stamped, matching the doomed set exactly; A7's pin
-- held on re-measurement 60 hours after the cutoff was computed.
--
-- DEVIATION, declared per APPLYING.md step 4: the 42-line header above was
-- condensed to 16 lines at the apply call. The EXECUTABLE SQL was submitted
-- unedited, and that is proven rather than claimed -- both stored bodies digest
-- byte-identical to this file:
--     $procedure$ ottoq_retention_purge_runs  md5 b786dbd09548e39f5f35abe22dd467bb  5900 chars
--     $function$  ottoq_kpi_five              md5 281ff76cc7182d277ceffab41b84cdee  1930 chars
-- against live pg_proc.prosrc. Note this is the RAW digest, comments included --
-- scripts/exec-digest.py's comment-stripped digest cannot see a dropped in-body
-- comment, which is exactly how 0252 was applied with four comment lines missing
-- from a stored body before the repair. Verify stored bodies raw.
-- ===========================================================================
