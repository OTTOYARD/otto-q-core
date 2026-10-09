-- migration-version: PENDING
-- migration-name:    the_wall_clock_retention_never_takes_a_production_runs_shield_log
--
-- 0646  **The nightly wall-clock retention (cron 11) never deletes a production or running run's rule evaluations.**
--       (Chase, 2026-10-09: "If it even closely resembles production data ... do not delete.")
--
-- == S1 WHY (db/checks/0429 S6) ======================================================================================
--
--   ottoq_retention_purge_worker walks three tables by age. Its events walk has always spared running and
--   production_live runs (v_live, computed at step 4). Its rule-evaluation walk never did: it deletes every row
--   with evaluated_at older than the 7-day cut, whoever owns it. Today the only production run with rule
--   evaluations is c4ee1572 (2026-10-09, 877 rows); the walk would take them on or after 10-17, the first night its
--   90-second budget reaches that phase (it spent the whole budget on events on 10-08 and 10-09).
--
-- == S2 WHAT THIS CHANGES ============================================================================================
--
--   One predicate in the rule-evaluation walk: AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live))), the
--   events walk's own words. Nothing else: the events walk, the anchors, the incident reports, the budget and the
--   policy are byte-identical (V asserts the whole body by md5, so a stray edit cannot hide). House rule 3 holds:
--   this file reads and writes nothing in ottoq_events.
--   Rows with no run (sim_run_id IS NULL) are still taken at 7 days, exactly as the events walk takes them; whether
--   production retention should be longer is a decision recorded in db/checks/0429, not made here.
--
-- == S3 forces_recert FALSE; forces_dial_restart FALSE ===============================================================
--
--   A retention job that deletes less. No tick path, decide path or frame.

BEGIN;

-- -- P0: nothing in flight --
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0646 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- -- P1: the definition this file was written against --
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_retention_purge_worker(integer,integer,interval,text[])'::regprocedure))
     <> 'dff3b880934e2b84d07f771118a3e884' THEN
    RAISE EXCEPTION '0646 P1: ottoq_retention_purge_worker is not the definition this file was written against';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0646_pre', 'function', 'public', 'ottoq_retention_purge_worker', s.d, md5(s.d)
  FROM (SELECT pg_get_functiondef('public.ottoq_retention_purge_worker(integer,integer,interval,text[])'::regprocedure) AS d) s;

-- -- the procedure: one predicate added to the rule-evaluation walk --
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_tables text[] DEFAULT ARRAY['ottoq_events'::text])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep      interval;
  v_aligned   boolean;
  v_cut       timestamptz;
  v_t0        timestamptz := clock_timestamp();
  v_n         bigint;
  v_total     bigint := 0;
  v_from      timestamptz;
  v_batch_ts  timestamptz;
  v_drained   boolean := false;
  v_live      uuid[];
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and this procedure commits per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  -- (2) policy wins over the caller's argument; fall back to it if no row.
  SELECT keep_interval, day_aligned INTO v_keep, v_aligned
    FROM public.ottoq_retention_policy WHERE policy_key = 'events' AND enabled;
  v_keep    := COALESCE(v_keep, p_keep);
  v_aligned := COALESCE(v_aligned, true);

  -- (3) day-aligned cut: delete only COMPLETE days older than the window.
  v_cut := now() - v_keep;
  IF v_aligned THEN
    v_cut := date_trunc('day', v_cut AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  END IF;

  -- (4) runs whose data may never be touched.
  SELECT COALESCE(array_agg(sim_run_id), '{}'::uuid[]) INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status = 'running' OR COALESCE(run_by, '') = 'production_live';

  RAISE NOTICE 'retention purge: keep %, cut %, % protected run(s)',
               v_keep, v_cut, cardinality(v_live);

  -- ---------------------------------------------------------------------------
  -- EVENTS: oldest-first walk ordered by occurred_at — THE SAME COLUMN THE DELETE
  -- IS PREDICATED ON.
  --
  -- 0006 walked this table in event_seq order and stopped when a batch deleted
  -- nothing and its newest timestamp was inside the keep window. That stopping rule
  -- is an inference: "seq order is time order". It is false here -- occurred_at is
  -- the SIM clock and runs start at a random time of day, so a run whose clock sits
  -- behind the previous one writes old-timestamped rows at high event_seq. Measured
  -- 2026-08-05: 18 inversions in 23,697 adjacent pairs. Demonstrated end-to-end: with
  -- a 30-day-old row present and the real 7-day policy, the old worker processed one
  -- window, deleted 0, exited, and left the old row in place.
  --
  -- Ordering by occurred_at removes the inference entirely. There is nothing to
  -- guess: the loop ends when there are no rows older than the cut, which is the
  -- definition of finished rather than a proxy for it. It also needs no cursor --
  -- deleted rows are gone, so the next call naturally resumes at the oldest
  -- survivor. A pass cut short by the time budget costs nothing but time.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_events' = ANY (p_tables) THEN
    v_from := '-infinity'::timestamptz;   -- start at the left edge of the index

    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

      -- STEP 1 — pick this window's UPPER TIMESTAMP by reading exactly
      -- p_micro_batch index entries. This is a bounded, ordered slice of
      -- ottoq_events_occurred_at_retention_idx: O(batch), never O(heap).
      SELECT max(w.occurred_at) INTO v_batch_ts
        FROM (SELECT e.occurred_at
                FROM public.ottoq_events e
               WHERE e.occurred_at >= v_from
                 AND e.occurred_at <  v_cut
               ORDER BY e.occurred_at
               LIMIT p_micro_batch) w;

      -- No row at all older than the cut. That is not an inference about ordering --
      -- there is simply nothing left. THE ONLY EXIT THAT MEANS "DONE".
      IF v_batch_ts IS NULL THEN
        v_drained := true;
        COMMIT;
        EXIT;
      END IF;

      -- STEP 2 — delete the whole CLOSED TIMESTAMP RANGE [v_from, v_batch_ts].
      -- The window is a range of TIME, not a count of rows, and that is deliberate:
      -- it guarantees every row sharing v_batch_ts is inside this delete even if the
      -- LIMIT above cut the group in half. Without that, advancing the watermark past
      -- v_batch_ts could step over a deletable row that happened to share a
      -- microsecond with p_micro_batch protected ones. Many events DO share one
      -- occurred_at here -- it is the sim clock, and a tick writes 60-120 events at
      -- the same value -- so this is a real case, not a theoretical one.
      -- The window is therefore at most p_micro_batch plus the tail of one timestamp
      -- group; a group is bounded by one tick's event count, well under the batch.
      DELETE FROM public.ottoq_events e
       WHERE e.occurred_at >= v_from
         AND e.occurred_at <= v_batch_ts
         AND e.occurred_at <  v_cut
         AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- STEP 3 — advance. Everything at or below v_batch_ts and older than the cut
      -- has now been deleted or is protected, so stepping one microsecond past it
      -- (timestamptz resolution) cannot skip anything. v_from strictly increases
      -- every iteration, so the walk always terminates.
      v_from := v_batch_ts + interval '1 microsecond';

      -- Observability only. cursor_block is a bigint that nothing reads back to make
      -- a decision; it now carries the walk's time watermark as epoch seconds so a
      -- human can see where the pass got to. Never dropped, never repurposed away.
      UPDATE public.ottoq_retention_state
         SET cursor_block = floor(extract(epoch FROM v_from))::bigint,
             pass_deleted = pass_deleted + v_n,
             updated_at   = now()
       WHERE table_name = 'ottoq_events';
      IF NOT FOUND THEN
        INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
        VALUES ('ottoq_events', floor(extract(epoch FROM v_from))::bigint, v_n, now())
        ON CONFLICT (table_name) DO NOTHING;
      END IF;

      COMMIT;  -- each window's work is permanent regardless of later failures
    END LOOP;

    -- End-of-pass housekeeping, moved here from 0006's early exit. It now fires only
    -- when the backlog is GENUINELY drained; the old placement could unschedule the
    -- backlog job while old rows remained, which is the whole bug in miniature.
    IF v_drained THEN
      PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
      UPDATE public.ottoq_retention_state
         SET pass_deleted = 0, updated_at = now() WHERE table_name = 'ottoq_events';
      COMMIT;
    ELSE
      RAISE NOTICE 'retention purge: events pass stopped on the % s budget with work remaining; the next call resumes at the oldest survivor.', p_time_budget_s;
    END IF;

    -- Anchors follow their day. Because the cut is day-aligned, every event that
    -- could have folded onto one of these anchors has already gone.
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_event_state_anchor
     WHERE anchor_day < (v_cut AT TIME ZONE 'UTC')::date
       AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live)));
    COMMIT;
  END IF;

  -- ---------------------------------------------------------------------------
  -- The two small tables. Same batching, same budget, unchanged from 0006 -- both
  -- already walk by their own timestamp column, so neither had the defect.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_rule_evaluations' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
        SELECT evaluation_id FROM public.ottoq_rule_evaluations
         WHERE evaluated_at < v_cut
           -- 0646: the protection the events walk above has always had. A production or running run's
           -- shield log is never taken by age.
           AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live)))
         LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  IF 'ottoq_incident_reports' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
        SELECT incident_report_id FROM public.ottoq_incident_reports
         WHERE triggered_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0646_the_wall_clock_retention_never_takes_a_production_runs_shield_log', false, false,
  'ottoq_retention_purge_worker''s rule-evaluation walk takes rows older than its cut whoever owns them; its events '
  'walk has always spared running and production_live runs. The same predicate is added to the rule-evaluation walk '
  'and nothing else changes. A retention job that deletes less: no tick path, decide path or frame. FALSE/FALSE.',
  now())
ON CONFLICT (name) DO NOTHING;

-- V. The stored body is exactly the one this file wrote, so the events walk is byte-identical.
DO $verify_body$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p
   WHERE p.oid = 'public.ottoq_retention_purge_worker(integer,integer,interval,text[])'::regprocedure;
  IF md5(v_src) <> 'be62c5615ad6186e9c0949615cd206f4' THEN
    RAISE EXCEPTION '0646 V FAILED: the stored body is not the body this file wrote (md5 %)', md5(v_src);
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'sim_run_id IS NULL OR NOT \(sim_run_id = ANY \(v_live\)\)', 'g')) <> 2 THEN
    RAISE EXCEPTION '0646 V FAILED: the production predicate is not on both the anchors and the rule-evaluation walk';
  END IF;
  RAISE NOTICE '0646 V: body as written; the rule-evaluation walk now spares running and production_live runs';
END $verify_body$;

-- Rollback: EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0646_pre' AND object_name = 'ottoq_retention_purge_worker'.
COMMIT;
