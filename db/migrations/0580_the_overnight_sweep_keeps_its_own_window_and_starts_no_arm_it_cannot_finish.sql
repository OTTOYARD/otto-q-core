-- migration-version: 20261002194524
-- migration-name:    the_overnight_sweep_keeps_its_own_window_and_starts_no_arm_it_cannot_finish
--
-- 0580  **The overnight sweep keeps its own window, and starts no test day it cannot finish before the window closes.**
--       Lane A, harness only. (G304)
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0568 opens the sweep's window with one cron entry (04:00 UTC, 11 PM CDT) and closes it with another (11:00 UTC, 6 AM
--   CDT), each setting the dial `throughput_sweep_runner_enabled`, and the runner checks only that dial. But a 24-hour
--   arm holds one transaction for 96-140 minutes, and pg_cron starts no job while it runs (G141). Twice now an arm began
--   at about 10:02 UTC and ran into the day:
--     night 2 (2026-10-01): arm 28 ran 10:02-12:11 UTC. The close entry never fired; the dial was still 1 at 11:24 UTC,
--       when it was set to 0 by hand, and the next runner firing would have started another arm (db/checks/0414 §5).
--     night 3 (2026-10-02): arm 33 ran 10:02-12:16 UTC (to 7:16 AM CDT). The close entry fired 85 ms after the arm
--       committed, before the runner's next firing. That was luck, not design.
--   Each of those arms starved the depot tick, the demo metronome and the run governor for over an hour of the morning.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The runner reads the window itself. Three catalogued dials, minutes of the UTC day:
--         throughput_sweep_window_open_utc_min   240  (04:00 UTC, 11 PM CDT)
--         throughput_sweep_window_close_utc_min  660  (11:00 UTC, 6 AM CDT)
--         throughput_sweep_close_grace_min         0  minutes an arm may run past the close
--       Outside the window the runner does nothing and says so, whatever the switch reads. An open after the close wraps
--       midnight. The cron entries stay as they are: the switch is still the operator's master switch, and the runner
--       now runs only where both agree.
--   (2) It starts no arm that cannot end by the close plus the grace. The arm's length is the longest its cell has taken,
--       else the longest any arm of its sweep has taken, else the arm's own budget (ticks x 30 s, where 0568's tick loop
--       stops). Arms with an engine error are not measured: they can stop early. A refused arm is not recorded; it runs
--       first the next night. At night 2's pace (96-140 min) that is three 24-hour arms a night, not four, and none
--       past 6 AM CDT.
--   (3) Night 1's frontier sweep (`frontier_2026_09_29`, re-due since the dial floor moved on 2026-10-01) goes behind the
--       sweeps that have never run: its priority 100 becomes 200, so `charge_order_2026_09_30`, `fleet150_2026_10_01`
--       and `fleet200_2026_10_01` come first once the value sweep is done. The smoke arm (10) and the value sweep (50)
--       keep their places.
--   Under CST (from 2026-11-01) the same UTC window is 10 PM-5 AM CT, as 0568 already says; moving it is two dial writes.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the runner is the body 0568 wrote (md5 pinned), the window's cron entries are 0568's
--   04:00 and 11:00 UTC (so the dials' defaults restate them), none of the three dials exists, night 1's frontier sweep
--   is at priority 100, and this has not been applied. The runner goes to `ottoq_schema_snapshots` as '0580_pre'.
--   V1: the dials are catalogued and set to their defaults. V2: executed, and safe on the live engine because the window
--   is checked before anything else: with the switch open and the window set to have closed a minute ago, the runner
--   refuses as outside the window; with an open after the close it computes the wrap (rolled back). V3: the frontier
--   sweep is at 200 and no other sweep moved.
--   The finish check is executed by tests/test_throughput_sweep_sql.py, against arms of known length; on the live
--   engine it would need an arm to be startable, so it is not run here.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: the runner and three of its own dials. The engine and the arm are
--   unchanged, so no arm already run is moved by this.
--
-- ROLLBACK: re-create public.ottoq_throughput_sweep_runner from its '0580_pre' snapshot; DELETE FROM
--   public.ottoq_policy_params and public.ottoq_policy_param_catalog WHERE param_key IN
--   ('throughput_sweep_window_open_utc_min', 'throughput_sweep_window_close_utc_min', 'throughput_sweep_close_grace_min');
--   UPDATE public.ottoq_throughput_sweeps SET priority = 100 WHERE sweep_code = 'frontier_2026_09_29';
--   DELETE FROM public.ottoq_cert_lineage
--   WHERE name = '0580_the_overnight_sweep_keeps_its_own_window_and_starts_no_arm_it_cannot_finish'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe; since 0579 it sees a sweep arm) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0580 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0568's runner and window, no dial yet, the frontier at 100, not yet applied ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0580_the_overnight_sweep_keeps_its_own_window_and_starts_no_arm_it_cannot_finish') THEN
    RAISE EXCEPTION '0580 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_throughput_sweep_runner()'::regprocedure)
     <> '7f477c3924f9617c8515021a36223064' THEN
    RAISE EXCEPTION '0580 P1: ottoq_throughput_sweep_runner is not the body 0568 wrote';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq_sweep_window_open' AND schedule = '0 4 * * *'
                    AND command ILIKE '%''throughput_sweep_runner_enabled'', 1,%')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq_sweep_window_close' AND schedule = '0 11 * * *'
                       AND command ILIKE '%''throughput_sweep_runner_enabled'', 0,%') THEN
    RAISE EXCEPTION '0580 P1: the window''s cron entries are not 0568''s 04:00 and 11:00 UTC, which the dials restate';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('throughput_sweep_window_open_utc_min', 'throughput_sweep_window_close_utc_min',
                                  'throughput_sweep_close_grace_min')) THEN
    RAISE EXCEPTION '0580 P1: a window dial is already catalogued';
  END IF;
  IF (SELECT priority FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29') IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION '0580 P1: night 1''s frontier sweep is not at priority 100';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0580_pre', 'function', 'public', 'ottoq_throughput_sweep_runner', d, md5(d)
  FROM (SELECT pg_get_functiondef('public.ottoq_throughput_sweep_runner()'::regprocedure) AS d) z;

-- ── 1. the window's dials ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, description, affects, agent_writable)
VALUES
  ('throughput_sweep_window_open_utc_min', 0, 1439, 240,
   '0580 (G304): minute of the UTC day the overnight sweep window opens (240 = 04:00 UTC, 11 PM CDT). The runner reads it itself; the 04:00 cron entry that opens the master switch restates it. An open after the close wraps midnight.',
   'public.ottoq_throughput_sweep_runner', false),
  ('throughput_sweep_window_close_utc_min', 0, 1439, 660,
   '0580 (G304): minute of the UTC day the overnight sweep window closes (660 = 11:00 UTC, 6 AM CDT). The runner starts nothing at or after it and no arm it expects to end after it, because a running arm starves the 11:00 cron entry that closes the master switch (G141).',
   'public.ottoq_throughput_sweep_runner', false),
  ('throughput_sweep_close_grace_min', 0, 240, 0,
   '0580 (G304): minutes an arm may be expected to run past the window''s close and still be started. 0 keeps every arm inside the window.',
   'public.ottoq_throughput_sweep_runner', false);
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
VALUES ('global', '00000000-0000-0000-0000-000000000000', 'throughput_sweep_window_open_utc_min', 240, '0580'),
       ('global', '00000000-0000-0000-0000-000000000000', 'throughput_sweep_window_close_utc_min', 660, '0580'),
       ('global', '00000000-0000-0000-0000-000000000000', 'throughput_sweep_close_grace_min', 0, '0580');

-- ── 2. the runner reads the window and the pace ──
CREATE OR REPLACE FUNCTION public.ottoq_throughput_sweep_runner()
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_floor timestamptz; v_below int; t record; v_res jsonb; v_msg text; v_state text; v_detail text; v_ctx text;
  s record;
  -- 0580 (G304): the window and the pace, read here
  v_open int; v_close_min int; v_grace int; v_now_min int; v_in boolean; v_close timestamptz; v_est numeric;
  v_est_from text;
BEGIN
  IF COALESCE(public.ottoq_policy_get(NULL, 'throughput_sweep_runner_enabled', 0), 0) < 1 THEN
    RETURN jsonb_build_object('ran', false, 'why', 'throughput_sweep_runner_enabled is 0');
  END IF;
  -- 0580 (G304). The window is kept here, not only by its two cron entries. An arm holds one transaction for up to two
  -- hours and pg_cron starts no job while it runs (G141), so the close entry can fire late or never: on 2026-10-01 it
  -- never fired and the switch stayed 1 into the day. Minutes of the UTC day; open after close wraps midnight.
  v_open      := COALESCE(public.ottoq_policy_get(NULL, 'throughput_sweep_window_open_utc_min', 240), 240)::int;
  v_close_min := COALESCE(public.ottoq_policy_get(NULL, 'throughput_sweep_window_close_utc_min', 660), 660)::int;
  v_grace     := COALESCE(public.ottoq_policy_get(NULL, 'throughput_sweep_close_grace_min', 0), 0)::int;
  v_now_min   := (extract(hour FROM now() AT TIME ZONE 'UTC') * 60 + extract(minute FROM now() AT TIME ZONE 'UTC'))::int;
  v_in        := CASE WHEN v_open <= v_close_min THEN v_now_min >= v_open AND v_now_min < v_close_min
                      ELSE v_now_min >= v_open OR v_now_min < v_close_min END;
  IF NOT v_in THEN
    RETURN jsonb_build_object('ran', false, 'why', format('outside the sweep window, %s:%s-%s:%s UTC',
             lpad((v_open / 60)::text, 2, '0'), lpad((v_open % 60)::text, 2, '0'),
             lpad((v_close_min / 60)::text, 2, '0'), lpad((v_close_min % 60)::text, 2, '0')));
  END IF;
  v_close := (date_trunc('day', now() AT TIME ZONE 'UTC') + make_interval(mins => v_close_min)) AT TIME ZONE 'UTC';
  IF v_close <= now() THEN
    v_close := v_close + interval '1 day';
  END IF;
  IF NOT public.ottoq_try_world_lock() THEN
    RETURN jsonb_build_object('ran', false, 'why', 'the world lock is held (a certification, a dial pair or an arm)');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RETURN jsonb_build_object('ran', false, 'why', 'a run is live');
  END IF;
  SELECT count(*) INTO v_below FROM public.ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor;
  IF v_below > 0 THEN
    RETURN jsonb_build_object('ran', false, 'why', format('certification has priority: %s canon column(s) below the recert floor', v_below));
  END IF;

  v_floor := public.ottoq_dial_pair_floor();
  -- The next task: the due sweep of lowest priority number first, then seed by seed, cell by cell; a replicate of one of the first `replicates` primaries runs once that
  -- primary's seed is done (ord 1000 + the cell's ord puts it after the seed's cells). Anything already recorded since the
  -- floor -- complete, incomplete or failed -- is done: a failure is recorded, not retried.
  WITH active AS (
    SELECT sw.* FROM public.ottoq_throughput_sweeps sw
     WHERE sw.status = 'active' AND (sw.run_after IS NULL OR sw.run_after <= now())
  ), prim AS (
    SELECT a.sweep_id, a.priority, a.created_at, c.cell_id, sd.seed, sd.k, c.ord, false AS replicate,
           row_number() OVER (PARTITION BY a.sweep_id ORDER BY sd.k, c.ord) AS n
      FROM active a
      JOIN public.ottoq_throughput_sweep_cells c ON c.sweep_id = a.sweep_id
      CROSS JOIN LATERAL unnest(a.seeds) WITH ORDINALITY AS sd(seed, k)
  ), tasks AS (
    SELECT sweep_id, priority, created_at, cell_id, seed, k, ord, replicate FROM prim
    UNION ALL
    SELECT p.sweep_id, p.priority, p.created_at, p.cell_id, p.seed, p.k, 1000 + p.ord, true
      FROM prim p JOIN active a ON a.sweep_id = p.sweep_id
     WHERE p.n <= a.replicates
  )
  SELECT t2.* INTO t FROM tasks t2
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms x
                      WHERE x.cell_id = t2.cell_id AND x.seed = t2.seed AND x.replicate = t2.replicate AND x.ran_at >= v_floor)
     AND (NOT t2.replicate OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_arms x
                                       WHERE x.cell_id = t2.cell_id AND x.seed = t2.seed AND NOT x.replicate
                                         AND x.complete AND x.ran_at >= v_floor))
   ORDER BY t2.priority, t2.created_at, t2.sweep_id, t2.k, t2.ord
   LIMIT 1;

  IF NOT FOUND THEN
    -- nothing left: every active sweep whose tasks are all recorded is concluded
    FOR s IN SELECT sw.sweep_id, sw.sweep_code FROM public.ottoq_throughput_sweeps sw WHERE sw.status = 'active'
                AND (sw.run_after IS NULL OR sw.run_after <= now()) LOOP
      UPDATE public.ottoq_throughput_sweeps SET status = 'concluded', concluded_at = now() WHERE sweep_id = s.sweep_id;
    END LOOP;
    RETURN jsonb_build_object('ran', false, 'why', 'no active sweep has an arm left to run');
  END IF;

  -- 0580 (G304): an arm that cannot finish before the window closes is not started. Its length is the longest this cell
  -- has taken, else the longest any arm of its sweep has taken, else the arm's own budget, where its tick loop stops. An
  -- arm that failed may have stopped early, so only arms without an engine error are measured.
  SELECT e.est, e.src INTO v_est, v_est_from
    FROM (SELECT max(a.wall_s) AS est, 'this cell' AS src, 1 AS o FROM public.ottoq_throughput_sweep_arms a
           WHERE a.cell_id = t.cell_id AND a.arm_error IS NULL AND a.wall_s IS NOT NULL
          UNION ALL
          SELECT max(a.wall_s), 'this sweep', 2 FROM public.ottoq_throughput_sweep_arms a
           WHERE a.sweep_id = t.sweep_id AND a.arm_error IS NULL AND a.wall_s IS NOT NULL
          UNION ALL
          SELECT COALESCE(sw.arm_budget_s, GREATEST(240, sw.ticks * 30))::numeric, 'its budget', 3
            FROM public.ottoq_throughput_sweeps sw WHERE sw.sweep_id = t.sweep_id) e
   WHERE e.est IS NOT NULL
   ORDER BY e.o
   LIMIT 1;
  IF now() + make_interval(secs => v_est) > v_close + make_interval(mins => v_grace) THEN
    RETURN jsonb_build_object('ran', false,
             'why', format('the next arm would end after the window closes: about %s min (%s), and the window closes at %s UTC%s',
                           ceil(v_est / 60), v_est_from, to_char(v_close AT TIME ZONE 'UTC', 'HH24:MI'),
                           CASE WHEN v_grace > 0 THEN format(' with %s min of grace', v_grace) ELSE '' END),
             'cell_id', t.cell_id, 'seed', t.seed, 'replicate', t.replicate,
             'estimate_s', round(v_est), 'estimate_from', v_est_from, 'window_closes_at', v_close);
  END IF;

  BEGIN
    v_res := public.ottoq_throughput_sweep_arm(t.cell_id, t.seed, t.replicate);
  EXCEPTION WHEN OTHERS THEN
    -- The arm's subtransaction rolled back everything it did, the build-out included. Record the failure so the night
    -- moves on instead of retrying the same arm until the window closes (0535's lesson). A manual Start's cancel is
    -- query_canceled, which OTHERS does not catch: that arm rolls back whole and runs again the next night.
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE, v_detail = PG_EXCEPTION_DETAIL,
                            v_ctx = PG_EXCEPTION_CONTEXT;
    -- A contention failure is not the arm's: a deadlock, a serialization failure, a lock that was not free or a run
    -- that went live in between. Nothing is recorded, and the next firing tries the same arm again.
    IF v_state IN ('40P01', '40001', '55P03', '55006') THEN
      RETURN jsonb_build_object('ran', false, 'why', 'contention: ' || v_msg, 'sqlstate', v_state,
                                'cell_id', t.cell_id, 'seed', t.seed, 'replicate', t.replicate);
    END IF;
    INSERT INTO public.ottoq_throughput_sweep_arms
      (sweep_id, cell_id, seed, replicate, engine_hash, dial_floor, complete, arm_error)
    VALUES (t.sweep_id, t.cell_id, t.seed,
            t.replicate, public.ottoq_engine_hash(), v_floor, false,
            jsonb_build_object('error', v_msg, 'sqlstate', v_state, 'detail', v_detail, 'where', left(v_ctx, 800),
                               'stage', 'arm'));
    RETURN jsonb_build_object('ran', true, 'failed', true, 'cell_id', t.cell_id, 'seed', t.seed,
                              'replicate', t.replicate, 'error', v_msg);
  END;
  RETURN jsonb_build_object('ran', true, 'arm', v_res);
END $fn$;
COMMENT ON FUNCTION public.ottoq_throughput_sweep_runner() IS
'0568, 0580. The cron entry for throughput sweeps: at most one arm per call, only while throughput_sweep_runner_enabled is 1, the clock is inside the window (throughput_sweep_window_open_utc_min to throughput_sweep_window_close_utc_min, read here because a running arm starves the cron entry that closes it, G304), no run is live, every canon column is current and the world lock is free; and no arm whose measured length would carry it past the close plus throughput_sweep_close_grace_min. Seed by seed, cell by cell; a failed arm is recorded and not retried.';

-- ── 3. night 1's frontier goes behind the sweeps that have never run ──
UPDATE public.ottoq_throughput_sweeps SET priority = 200 WHERE sweep_code = 'frontier_2026_09_29';

-- ── V1: the dials are catalogued and set to their defaults ──
DO $v1$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog k
        JOIN public.ottoq_policy_params p ON p.param_key = k.param_key AND p.scope_type = 'global'
                                         AND p.param_value = k.default_value
       WHERE k.param_key IN ('throughput_sweep_window_open_utc_min', 'throughput_sweep_window_close_utc_min',
                             'throughput_sweep_close_grace_min')) <> 3
     OR public.ottoq_policy_get(NULL, 'throughput_sweep_window_open_utc_min', -1) <> 240
     OR public.ottoq_policy_get(NULL, 'throughput_sweep_window_close_utc_min', -1) <> 660
     OR public.ottoq_policy_get(NULL, 'throughput_sweep_close_grace_min', -1) <> 0 THEN
    RAISE EXCEPTION '0580 V1: the window dials are not catalogued and set to 240, 660 and 0';
  END IF;
END $v1$;

-- ── V2: with the switch open, a closed window refuses before anything else runs (rolled back) ──
DO $v2$
DECLARE
  v_m int := (extract(hour FROM now() AT TIME ZONE 'UTC') * 60 + extract(minute FROM now() AT TIME ZONE 'UTC'))::int;
  v_r jsonb;
BEGIN
  PERFORM public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_runner_enabled', 1, '0580 V2');
  -- a window that opened 3 hours ago and closed 1 minute ago (both before and after midnight are covered by the modulo)
  PERFORM public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_window_open_utc_min',
                                  ((v_m - 180) % 1440 + 1440) % 1440, '0580 V2');
  PERFORM public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_window_close_utc_min',
                                  ((v_m - 1) % 1440 + 1440) % 1440, '0580 V2');
  v_r := public.ottoq_throughput_sweep_runner();
  IF (v_r->>'ran')::boolean OR v_r->>'why' NOT LIKE 'outside the sweep window, %' THEN
    RAISE EXCEPTION '0580 V2: with the window closed the runner did not refuse as outside it: %', v_r;
  END IF;
  -- a window that opens in 2 minutes and closed 1 minute ago: its open is after its close, so it wraps midnight
  PERFORM public.ottoq_policy_set('global', '00000000-0000-0000-0000-000000000000'::uuid, 'throughput_sweep_window_open_utc_min',
                                  ((v_m + 2) % 1440 + 1440) % 1440, '0580 V2');
  v_r := public.ottoq_throughput_sweep_runner();
  IF (v_r->>'ran')::boolean OR v_r->>'why' NOT LIKE 'outside the sweep window, %' THEN
    RAISE EXCEPTION '0580 V2: a wrapped window that excludes now did not refuse: %', v_r;
  END IF;
  RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0580_V2_ROLLBACK';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> '0580_V2_ROLLBACK' THEN RAISE; END IF;
END $v2$;

-- ── V3: V2 left nothing behind, the frontier is at 200 and no other sweep moved ──
DO $v3$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0580 V2') THEN
    RAISE EXCEPTION '0580 V3: V2 left a dial write behind';
  END IF;
  IF public.ottoq_policy_get(NULL, 'throughput_sweep_window_open_utc_min', -1) <> 240
     OR public.ottoq_policy_get(NULL, 'throughput_sweep_window_close_utc_min', -1) <> 660 THEN
    RAISE EXCEPTION '0580 V3: V2 left the window moved';
  END IF;
  IF (SELECT priority FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'frontier_2026_09_29') <> 200 THEN
    RAISE EXCEPTION '0580 V3: night 1''s frontier is not at priority 200';
  END IF;
  RAISE NOTICE '0580 V3: sweeps in order: %',
    (SELECT string_agg(sweep_code || ' ' || priority, ', ' ORDER BY priority, created_at, sweep_id)
       FROM public.ottoq_throughput_sweeps WHERE status = 'active');
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0580_the_overnight_sweep_keeps_its_own_window_and_starts_no_arm_it_cannot_finish', false, false,
  'Lane A harness (G304). ottoq_throughput_sweep_runner reads the overnight window from three catalogued dials '
  '(04:00-11:00 UTC, grace 0) and starts no arm whose measured length would carry it past the close; a running arm '
  'starves the 11:00 cron entry that closes the master switch (G141), and on 2026-10-01 and 10-02 an arm ran to past '
  '7 AM CDT. Night 1''s frontier sweep goes to priority 200, behind the sweeps never run. The engine and the arm are '
  'unchanged.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
