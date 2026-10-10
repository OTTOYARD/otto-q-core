-- migration-version: PENDING
-- migration-name:    the_nightly_run_purge_runs_again_and_never_takes_what_the_learning_reads
--
-- 0645  **The nightly run purge runs again, keeps a week, and no longer deletes anything the learning reads.**
--       (Chase, 2026-10-09 afternoon CT: clear stale run data to free storage and speed the system up for the
--       investor and OEM showcase -- "If it even closely resembles production data or something that pertains to
--       active runs or intelligence, do not delete" -- and then: "Be extremely cautious and test when needed.")
--
-- == S1 WHY (db/checks/0437) =========================================================================================
--
--   otto-q-core is 23 GB and 22 GB of it is class-'engine' run data, every row from a run started since 09-29.
--   Nothing has cleared a finished run since 09-19:
--     (a) cron 625 skips every night. The 0269 round guard reads any ACTIVE cron job whose command names the
--         certification pair as a scheduled round, and the recert runner (cron 746, every minute since
--         2026-09-20) names it, so the guard has been true on every call since -- the latch db/checks/0204 warned
--         of ("a future rename must preserve them"), arriving through a different job. Its in-flight probe could
--         not see that runner's pairs either (G194: the pair name sits past pg_stat_activity's 1 kB).
--     (b) the twin's start door stopped purging: otto-twin-control moved to ottoq_operator_start_run to stay
--         inside the PostgREST timeout, and that door does not call ottoq_purge_prior_runs.
--     (c) when 625 did run (09-15..09-17) the server's 2-minute statement_timeout cancelled it at exactly 2:00;
--         its 300-second budget never fit.
--   And simply unlatching (a) would have been wrong. Its allow-list holds ottoq_events at a 48-hour keep, and the
--   nightly fault model reads charge.session_faulted events over 21 days (ottoq_charge_fault_params): 1,558 of the
--   2,572 faulted charges in its window still have theirs, and a 48-hour run purge would take most of the rest.
--
-- == S2 WHAT THIS CHANGES ============================================================================================
--
--   (a) The round guard ignores the recert runner, matched by its advisory-lock key as
--       ottoq_certification_rig_matches matches it. Every other active pair or battery job, and every r<N>_ round
--       job near its fire time, still skips the purge exactly as before.
--   (b) The in-flight probe is ottoq_certification_in_flight(false) (0513), at the start AND before every batch:
--       a pair, an A/B pair or the recert runner that starts mid-purge stops it, and the next call resumes.
--   (c) A run is doomed only when it ENDED before the cut (not merely started), is neither running nor paused,
--       and -- if it carries charge orders, which the hindsight grader and the return model read -- ended before
--       the new engine_rows_charge_orders keep (21 days, the window crons 786/789/790 fit over).
--   (d) ottoq_events leaves the allow-list. The six that remain are 0250's seeds that nothing the learning,
--       grading, self-review or experiments run reads (measured by per-transaction access counters,
--       db/checks/0437 S3). Events keep their own 7-day wall-clock worker (cron 11), unchanged here.
--   (e) The engine_rows keep goes from 48 hours to 7 days, so the OEM 7-day and 24-hour views never lose a row
--       they show: no run writes a rule evaluation after it ends (measured), and doomed means ended > 7 days ago.
--   (f) Cron 625 runs hourly 04:17-11:17 UTC (11:17 PM - 6:17 AM CDT) at a 100-second budget, under the
--       2-minute statement_timeout and fast enough for the ~1.1M rows a day these six tables take on.
--   Unchanged: production_live and running runs are never doomed; a run must be archived; the 0251 stamp, both
--   0250 guards and the registry refusal; ottoq_sim_runs is never deleted.
--
-- == S3 forces_recert FALSE; forces_dial_restart FALSE ===============================================================
--
--   No tick path, no decide path, no frame. The runs this makes purgeable hold no live-state booking and no
--   live-state leg (measured 0 and 0), which are the only foreign rows the boot fingerprint counts, so the canon
--   cannot rebase on a purge (G46, db/checks/0191) -- V5 re-measures that at apply time and refuses if it is not 0.

BEGIN;

-- -- P0: nothing in flight (0513's probe) --
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0645 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- -- P1: the world this file was written against --
DO $premises$
DECLARE v_allow text;
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure))
     <> '890d2de189d638c1622a53efc863fb66' THEN
    RAISE EXCEPTION '0645 P1: ottoq_retention_purge_runs is not the definition this file was written against';
  END IF;
  SELECT string_agg(table_name, ',' ORDER BY table_name) INTO v_allow FROM public.ottoq_retention_engine_allowlist;
  IF v_allow IS DISTINCT FROM 'ottoq_bay_binding_witness,ottoq_comms_messages,ottoq_events,ottoq_itinerary_legs,ottoq_rule_evaluations,ottoq_stall_bookings,ottoq_variability_cards' THEN
    RAISE EXCEPTION '0645 P1: the allow-list is not the seven 0250 tables: %', v_allow;
  END IF;
  IF (SELECT keep_interval FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled)
     IS DISTINCT FROM interval '48 hours' THEN
    RAISE EXCEPTION '0645 P1: the engine_rows keep is not 48 hours';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows_charge_orders') THEN
    RAISE EXCEPTION '0645 P1: engine_rows_charge_orders exists already';
  END IF;
  IF (SELECT md5(command) || '/' || schedule FROM cron.job WHERE jobid = 625 AND jobname = 'ottoq-run-purge-nightly')
     IS DISTINCT FROM '0b6d2378bc93dfa3813c01ac93a25784/0 9 * * *' THEN
    RAISE EXCEPTION '0645 P1: cron 625 is not the job this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_certification_in_flight(boolean)') IS NULL THEN
    RAISE EXCEPTION '0645 P1: ottoq_certification_in_flight(boolean) is missing';
  END IF;
END $premises$;

-- -- the old body and every config value this file changes, for the rollback at the foot --
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0645_pre', 'function', 'public', 'ottoq_retention_purge_runs', s.d, md5(s.d)
  FROM (SELECT pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure) AS d) s
UNION ALL
SELECT '0645_pre', 'config_row', 'public', 'ottoq_retention_engine_allowlist.ottoq_events', s.d, md5(s.d)
  FROM (SELECT row_to_json(a)::text AS d FROM public.ottoq_retention_engine_allowlist a WHERE a.table_name = 'ottoq_events') s
UNION ALL
SELECT '0645_pre', 'config_row', 'public', 'ottoq_retention_policy.engine_rows', s.d, md5(s.d)
  FROM (SELECT row_to_json(p)::text AS d FROM public.ottoq_retention_policy p WHERE p.policy_key = 'engine_rows') s
UNION ALL
SELECT '0645_pre', 'cron_job', 'cron', 'job 625', s.d, md5(s.d)
  FROM (SELECT row_to_json(j)::text AS d FROM (SELECT jobid, jobname, schedule, command, active FROM cron.job WHERE jobid = 625) j) s;

-- -- the procedure: five edits to 0294's body and nothing else (diff in db/checks/0437 S4) --
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_runs(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_dry_run boolean DEFAULT false)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep    interval;
  v_keep_orders interval;   -- 0645
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
                         OR j.command ILIKE '%ottoq_cert_battery_step%')
                       -- 0645: the recert runner (cron 746) is always active and names the pair, so this clause
                       -- read it as a scheduled round on every call from 2026-09-20 and the purge never ran. It is
                       -- matched by its advisory-lock key, as ottoq_certification_rig_matches does; its pairs are
                       -- caught when they actually run, by the in-flight probe below.
                       AND j.command NOT ILIKE '%ottoq_recert_runner%')
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

  -- 0645: the house's certification probe (0513) in place of a pair-name match, which could not see the recert
  -- runner (G194: its pair name sits past pg_stat_activity's 1 kB). Pairs, A/B pairs and the runner; dial pairs
  -- and sweep arms were never part of this guard and are not now.
  v_pairs := public.ottoq_certification_in_flight(false);
  IF v_pairs > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: % certification pair(s) in flight - skipped', v_pairs;
    RETURN;
  END IF;

  SELECT keep_interval INTO v_keep
    FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
  v_keep := COALESCE(v_keep, p_keep);
  v_cut  := now() - v_keep;
  -- 0645: a run carrying charge orders keeps every row for the nightly fits' window. The hindsight grader and
  -- ottoq_charge_order_regrade refuse a run once it is stamped, and the return model learns from those grades.
  SELECT keep_interval INTO v_keep_orders
    FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows_charge_orders' AND enabled;
  v_keep_orders := GREATEST(COALESCE(v_keep_orders, interval '21 days'), v_keep);

  SELECT array_agg(sr.sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs sr
   WHERE sr.status NOT IN ('running', 'paused')                        -- 0645: a paused run is not finished
     AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < v_cut
     AND COALESCE(sr.ended_at, sr.started_at) < v_cut                  -- 0645: ENDED before the cut
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id)
     AND (COALESCE(sr.ended_at, sr.started_at) < now() - v_keep_orders
          OR NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_snapshots s WHERE s.sim_run_id = sr.sim_run_id));

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

  <<tables>>
  FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      -- 0645: a certification that starts mid-purge stops it; committed batches stay and the next call resumes.
      EXIT tables WHEN NOT p_dry_run AND public.ottoq_certification_in_flight(false) > 0;

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

COMMENT ON PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean) IS
'0247 created it, 0250 gave it the allow-list, 0251 the purged_at stamp, 0269 the round guard, 0294 the array loop. '
'0645: the round guard no longer reads the always-on recert runner as a scheduled round; the in-flight probe is '
'ottoq_certification_in_flight(false), at the start and before every batch; and a run is doomed only when it ENDED '
'before the engine_rows keep (7 days), is neither running nor paused, is not production_live, is archived, and -- if '
'it carries charge orders -- ended before engine_rows_charge_orders (21 days, the nightly fits'' window). Deletes '
'child rows across ottoq_retention_engine_allowlist only (ottoq_events left it in 0645: the fault model reads it) and '
'never ottoq_sim_runs itself, so validation_notes and every certification pair survive. Refuses on a blocking '
'run-scope defect, on an allow-list wider than class=engine, and on an allow-listed parent of a NO ACTION/RESTRICT FK.';

-- -- ottoq_events leaves the allow-list (the row is in ottoq_schema_snapshots under 0645_pre) --
DO $allow$
DECLARE n int;
BEGIN
  DELETE FROM public.ottoq_retention_engine_allowlist WHERE table_name = 'ottoq_events';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION '0645: expected to take exactly ottoq_events off the allow-list, took %', n;
  END IF;
END $allow$;

-- -- the keeps --
UPDATE public.ottoq_retention_policy
   SET keep_interval = interval '7 days',
       notes = notes || ' 0645: 48 hours -> 7 days, so the OEM 7-day and 24-hour views never lose a row they show.',
       updated_at = now()
 WHERE policy_key = 'engine_rows';

INSERT INTO public.ottoq_retention_policy (policy_key, enabled, keep_interval, day_aligned, notes)
VALUES ('engine_rows_charge_orders', true, interval '21 days', false,
  '0645: a run carrying charge orders keeps all its engine rows until this long after it ended -- the window the '
  'nightly fits read (crons 786, 789, 790). The hindsight grader and ottoq_charge_order_regrade refuse a run once '
  'ottoq_retention_purge_runs stamps it, and the return model learns from those grades. Never shorter than engine_rows.');

-- -- cron 625: under the 2-minute statement_timeout, and often enough to keep up --
SELECT cron.alter_job(625,
         schedule := '17 4-11 * * *',
         command  := 'CALL public.ottoq_retention_purge_runs(100, 2000, ''7 days'', false);');

-- This file's own classification goes in before the verifications (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0645_the_nightly_run_purge_runs_again_and_never_takes_what_the_learning_reads', false, false,
  'The nightly run purge (cron 625) had been latched off since 2026-09-20 by the always-on recert runner, and its '
  'allow-list would have deleted ottoq_events, which the fault model reads. The round guard ignores the runner; the '
  'in-flight probe is ottoq_certification_in_flight(false) at the start and before every batch; a run is doomed only '
  'when it ended more than 7 days ago (21 if it carries charge orders); ottoq_events leaves the allow-list; cron 625 '
  'runs hourly 04:17-11:17 UTC at 100 s. No tick path, decide path or frame, and the purgeable runs hold no '
  'live-state booking or leg, so the canon''s foreign-residue counts cannot move. FALSE/FALSE.',
  now())
ON CONFLICT (name) DO NOTHING;

-- V1. The body is the one this file wrote, and 0294's A1 still holds.
DO $verify_body$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p
   WHERE p.oid = 'public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure;
  IF md5(v_src) <> 'aeb90b727d4e61b4fdef931b305a51be' THEN
    RAISE EXCEPTION '0645 V1 FAILED: the stored body is not the body this file wrote (md5 %)', md5(v_src);
  END IF;
  IF position('FOR v_reg IN' in v_src) > 0
     OR (SELECT count(*) FROM regexp_matches(v_src, 'FOR\s+\w+\s+IN\s+SELECT', 'g')) > 0
     OR position('FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP' in v_src) = 0
     OR position('      COMMIT;' in v_src) = 0 THEN
    RAISE EXCEPTION '0645 V1 FAILED: 0294''s A1 no longer holds (cursor loop, integer loop or in-loop COMMIT)';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'public\.ottoq_certification_in_flight\(false\)', 'g')) <> 2 THEN
    RAISE EXCEPTION '0645 V1 FAILED: the certification probe is not at the start and before every batch';
  END IF;
  RAISE NOTICE '0645 V1: body as written; 0294 A1 holds; the probe guards the start and every batch';
END $verify_body$;

-- V2. The latch is gone: the round guard, as the body now writes it, matches no cron job.
DO $verify_latch$
DECLARE v_old text; v_new text;
BEGIN
  SELECT string_agg(j.jobid::text, ',') INTO v_old FROM cron.job j
   WHERE j.active AND (j.command ILIKE '%ottoq_determinism_pair%' OR j.command ILIKE '%ottoq_cert_battery_step%');
  SELECT string_agg(j.jobid::text, ',') INTO v_new FROM cron.job j
   WHERE (j.active AND (j.command ILIKE '%ottoq_determinism_pair%' OR j.command ILIKE '%ottoq_cert_battery_step%')
                   AND j.command NOT ILIKE '%ottoq_recert_runner%')
      OR (j.jobname ~ '^r[0-9]+_' AND
          CASE WHEN j.schedule ~ '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ \*$'
               THEN make_timestamptz(extract(year from now())::int,
                                     split_part(j.schedule,' ',4)::int, split_part(j.schedule,' ',3)::int,
                                     split_part(j.schedule,' ',2)::int, split_part(j.schedule,' ',1)::int, 0, 'UTC')
                    BETWEEN now() - interval '3 hours' AND now() + interval '3 hours'
               ELSE true END);
  IF v_new IS NOT NULL THEN
    RAISE EXCEPTION '0645 V2 FAILED: the round guard still matches cron job(s) %', v_new;
  END IF;
  RAISE NOTICE '0645 V2: the old clause matched cron job(s) %; the guard matches none', COALESCE(v_old, 'none');
END $verify_latch$;

-- V3. A certification in flight still stops it before it deletes or stamps anything. A body that went on would
-- reach its COMMIT, which raises inside this transaction, so a clean return is the proof.
DO $verify_skip$
DECLARE v_msg text; v_before int; v_after int;
BEGIN
  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE EXCEPTION '0645 V3: the retention lock is held elsewhere, so the guard cannot be exercised now; apply later';
  END IF;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
  SELECT count(*) INTO v_before FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL;
  PERFORM set_config('ottoq.simulate_certification_in_flight', 'on', true);
  BEGIN
    CALL public.ottoq_retention_purge_runs(5, 10, interval '7 days', false);
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  PERFORM set_config('ottoq.simulate_certification_in_flight', 'off', true);
  SELECT count(*) INTO v_after FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL;
  IF v_msg IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION '0645 V3 FAILED: with a certification in flight the purge went on: %', v_msg;
  END IF;
  IF v_after <> v_before THEN
    RAISE EXCEPTION '0645 V3 FAILED: a run was stamped (% -> %)', v_before, v_after;
  END IF;
  RAISE NOTICE '0645 V3: with a certification in flight the purge skips before it deletes or stamps anything';
END $verify_skip$;

-- V4. The configuration is what S2 says.
DO $verify_config$
DECLARE v_allow text; v_job record;
BEGIN
  SELECT string_agg(table_name, ',' ORDER BY table_name) INTO v_allow FROM public.ottoq_retention_engine_allowlist;
  IF v_allow IS DISTINCT FROM 'ottoq_bay_binding_witness,ottoq_comms_messages,ottoq_itinerary_legs,ottoq_rule_evaluations,ottoq_stall_bookings,ottoq_variability_cards' THEN
    RAISE EXCEPTION '0645 V4 FAILED: the allow-list is %', v_allow;
  END IF;
  IF (SELECT keep_interval FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled)
       IS DISTINCT FROM interval '7 days'
     OR (SELECT keep_interval FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows_charge_orders' AND enabled)
       IS DISTINCT FROM interval '21 days' THEN
    RAISE EXCEPTION '0645 V4 FAILED: the keeps are not 7 and 21 days';
  END IF;
  SELECT jobname, schedule, command, active INTO v_job FROM cron.job WHERE jobid = 625;
  IF v_job.schedule IS DISTINCT FROM '17 4-11 * * *'
     OR v_job.command IS DISTINCT FROM 'CALL public.ottoq_retention_purge_runs(100, 2000, ''7 days'', false);'
     OR NOT v_job.active THEN
    RAISE EXCEPTION '0645 V4 FAILED: cron 625 is % / % / %', v_job.schedule, v_job.command, v_job.active;
  END IF;
  IF v_job.jobname ~ '^r[0-9]+_' OR v_job.command ILIKE '%ottoq_cert%' OR v_job.command ILIKE '%pair%' THEN
    RAISE EXCEPTION '0645 V4 FAILED: cron 625 would trip its own guard (db/checks/0204)';
  END IF;
  RAISE NOTICE '0645 V4: six tables allow-listed; keep 7 days (21 with charge orders); cron 625 hourly 04:17-11:17 UTC at 100 s';
END $verify_config$;

-- V5. What is now purgeable, and the canon condition S3 rests on, measured at apply time.
DO $verify_canon$
DECLARE v_doomed uuid[]; v_live_bk int; v_live_lg int; v_orders int;
BEGIN
  SELECT array_agg(sr.sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs sr
   WHERE sr.status NOT IN ('running', 'paused')
     AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < now() - interval '7 days'
     AND COALESCE(sr.ended_at, sr.started_at) < now() - interval '7 days'
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id)
     AND (COALESCE(sr.ended_at, sr.started_at) < now() - interval '21 days'
          OR NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_snapshots s WHERE s.sim_run_id = sr.sim_run_id));
  SELECT count(*) INTO v_live_bk FROM public.ottoq_stall_bookings
   WHERE sim_run_id = ANY(v_doomed) AND state IN ('held', 'active', 'interrupted');
  SELECT count(*) INTO v_live_lg FROM public.ottoq_itinerary_legs
   WHERE sim_run_id = ANY(v_doomed) AND status IN ('planned', 'active', 'in_progress');
  SELECT count(*) INTO v_orders FROM public.ottoq_charge_order_snapshots WHERE sim_run_id = ANY(v_doomed);
  IF v_live_bk > 0 OR v_live_lg > 0 THEN
    RAISE EXCEPTION '0645 V5 FAILED: purgeable runs hold % live-state booking(s) and % live-state leg(s); a purge '
                    'would move the canon''s foreign-residue counts, so forces_recert FALSE would be wrong',
                    v_live_bk, v_live_lg;
  END IF;
  RAISE NOTICE '0645 V5: % run(s) purgeable; 0 live-state bookings, 0 live-state legs, % charge-order snapshot(s) among them',
               COALESCE(cardinality(v_doomed), 0), v_orders;
END $verify_canon$;

-- Rollback (one transaction):
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0645_pre' AND object_name = 'ottoq_retention_purge_runs';
--   INSERT INTO ottoq_retention_engine_allowlist (table_name, added_at, note)
--     SELECT d->>'table_name', (d->>'added_at')::timestamptz, d->>'note'
--       FROM (SELECT definition::jsonb AS d FROM ottoq_schema_snapshots
--              WHERE label = '0645_pre' AND object_name = 'ottoq_retention_engine_allowlist.ottoq_events') x;
--   UPDATE ottoq_retention_policy SET keep_interval = interval '48 hours' WHERE policy_key = 'engine_rows';
--   UPDATE ottoq_retention_policy SET enabled = false WHERE policy_key = 'engine_rows_charge_orders';
--   SELECT cron.alter_job(625, schedule := '0 9 * * *',
--            command := 'CALL public.ottoq_retention_purge_runs(300, 2000, ''48 hours'', false);');
--   Rows already purged do not come back from a rollback; they come back only from a backup.
COMMIT;
