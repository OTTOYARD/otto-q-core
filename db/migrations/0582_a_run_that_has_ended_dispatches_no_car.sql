-- migration-version: PENDING
-- migration-name:    a_run_that_has_ended_dispatches_no_car
--
-- 0582  **A run that has ended dispatches no car.** On a test day's last tick the twin decided and dispatched after the
--       run had closed every car's open work, so a car could leave with services unfinished. (G303, CLAUDE.md rule 9)
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Every tick driver runs the world step and then `ottoq_sim_decide_and_dispatch`: `ottoq_sim_advance_tick` (every
--   harness arm: determinism and dial pairs, sweep arms), `ottoq_demo_metronome` (every demo, on alternate beats),
--   `twin.ottoq_world_advance`, `ottoq_api_otto_q_decide` and a probe. On a run's last tick the world step reaches the sim
--   clock's end and writes status 'completed' partway through (0103 says so in `ottoq_sim_advance_tick`). The AFTER UPDATE
--   trigger `ottoq_sim_runs_close_needs` fires on that write and `ottoq_close_run_needs` marks every open visit
--   'superseded'. Then decide runs, and `public.ottoq_departure_clear`, the one departure test every door uses (0543),
--   reads only 'open' and 'in_progress' visits: it finds nothing open on any car and passes every car at its charge
--   target. Night 2, arm 25 (273fb34d, OTTO-Q, 10 fast chargers): Waymo cadd7c81 went charging_l2 -> charge_complete_holding
--   -> staged_for_departure -> deployed at 11:00 sim, with a software update in progress and item retrieval and a
--   readiness check never started, all must-do (db/checks/0414 §4; 1 of 1,040 departures that night). Rule 9: no car
--   leaves with a service still needed, ever.
--
--   A depot that runs around the clock has no last tick, so production never reaches this. The twin does at the end of
--   every test day and every demo, and its scorecard counts the car as a rule-9 breach.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_sim_decide_and_dispatch` only, one guard right after it reads the run: a run whose status is 'completed',
--   'failed' or 'aborted' returns (0, 0) and decides nothing. Those are exactly the statuses on which the trigger closes
--   the run's needs (P1 reads them from the trigger), so the guard is the same line: once the needs are closed, nothing
--   dispatches against them. It sits in the one function every driver calls, so the demo metronome is covered as well as
--   the harness. 'initializing', 'running' and 'paused' are unchanged. The world step, the departure test and the
--   finalizer are unchanged. (`ottoq_sim_advance_tick`'s 0103 comment, that decide "may have issued commands
--   post-completion", describes the behaviour before this file.)
--
--   What moves: the last tick of a run that reaches its clock's end no longer reclaims reservations, plans, assigns,
--   dispatches or records its `twin.sim_tick_advanced` debug event (every reader of that event excludes it). So a test
--   day's last tick sends no car out, and every departure a scorecard counts was decided while the run was live.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the function is the body measured on 2026-10-02 (md5 pinned), the anchor occurs exactly
--   once, the close-needs trigger fires on exactly completed/failed/aborted, and this has not been applied. The function
--   goes to `ottoq_schema_snapshots` as '0582_pre'.
--   V1: the new body is the old body plus the guard and nothing else. V2: executed on the most recent run of each ended
--   status there is: it returns (0, 0) and writes nothing (its events and its row are unchanged).
--   tests/test_run_end_dispatch_sql.py executes the function as the catalog held it: before this, an ended run goes on
--   into the decide path; after it, an ended run stops at the guard and a running, paused or initializing one does not.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: the last tick of any run that reaches its clock's end changes, and a
--   sweep arm's day ends exactly there (night 2's arm 25 is one).
--
-- ROLLBACK: re-create public.ottoq_sim_decide_and_dispatch from its '0582_pre' snapshot; DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0582_a_run_that_has_ended_dispatches_no_car'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0582 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the body measured, the anchor once, the trigger's statuses, not yet applied ──
DO $premises$
DECLARE v_src text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0582_a_run_that_has_ended_dispatches_no_car') THEN
    RAISE EXCEPTION '0582 P1: already applied';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure;
  IF md5(v_src) IS DISTINCT FROM '700e3e44b85a853d7d551a45d0d2d52b' THEN
    RAISE EXCEPTION '0582 P1: ottoq_sim_decide_and_dispatch is not the function measured on 2026-10-02';
  END IF;
  IF (length(v_src) - length(replace(v_src,
        'IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;', '')))
     / length('IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;') <> 1 THEN
    RAISE EXCEPTION '0582 P1: the anchor does not occur exactly once';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t
                  WHERE t.tgrelid = 'public.ottoq_sim_runs'::regclass AND t.tgname = 'ottoq_sim_runs_close_needs'
                    AND pg_get_triggerdef(t.oid) LIKE
                        '%(new.status = ANY (ARRAY[''completed''::text, ''failed''::text, ''aborted''::text]))%') THEN
    RAISE EXCEPTION '0582 P1: the close-needs trigger does not fire on exactly completed, failed and aborted';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0582_pre', 'function', 'public', 'ottoq_sim_decide_and_dispatch', d, md5(d)
  FROM (SELECT pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure) AS d) z;

-- ── the guard, right after the run is read ──
DO $patch$
DECLARE
  c_anchor constant text := 'IF NOT FOUND THEN out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN; END IF;';
  c_guard  constant text := $g$
  -- ════════════════════════════════════════════════════════════════════════
  -- 0582 (G303): A RUN THAT HAS ENDED DISPATCHES NO CAR. On a run's last tick
  -- the world step writes status 'completed', and ottoq_sim_runs_close_needs
  -- supersedes every open visit before this runs, so the departure test found
  -- nothing open and passed cars with work unfinished (night 2, arm 25: a car
  -- left mid software update). These are the trigger's own statuses: once a
  -- run's needs are closed, nothing is decided or dispatched against them.
  -- ════════════════════════════════════════════════════════════════════════
  IF v_run.status IN ('completed', 'failed', 'aborted') THEN
    out_dispatched:=0; out_charge_assigned:=0; RETURN NEXT; RETURN;
  END IF;$g$;
BEGIN
  EXECUTE replace(pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure),
                  c_anchor, c_anchor || c_guard);
  PERFORM set_config('ottoq.m0582_guard', c_guard, true);   -- for V1, this transaction only
END $patch$;

-- ── V1: the old body plus the guard, once, and nothing else ──
DO $v1$
DECLARE
  v_old   text := (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0582_pre'
                    ORDER BY snapshot_id DESC LIMIT 1);
  v_new   text := pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure);
  v_guard text := current_setting('ottoq.m0582_guard', true);
BEGIN
  IF COALESCE(v_guard, '') = ''
     OR length(v_new) - length(replace(v_new, v_guard, '')) <> length(v_guard)
     OR replace(v_new, v_guard, '') IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION '0582 V1: the function is not the measured body plus the guard, once';
  END IF;
END $v1$;

-- ── V2: an ended run of each status there is returns (0, 0) and writes nothing ──
DO $v2$
DECLARE r record; v_out record; v_row_before jsonb; v_ev_before bigint; v_ev_after bigint; v_n int := 0;
  c_events constant boolean := to_regclass('public.ottoq_events') IS NOT NULL;
BEGIN
  FOR r IN SELECT DISTINCT ON (status) sim_run_id, status FROM public.ottoq_sim_runs
            WHERE status IN ('completed', 'failed', 'aborted')
            ORDER BY status, ended_at DESC NULLS LAST, sim_run_id LOOP
    v_row_before := (SELECT to_jsonb(x) FROM public.ottoq_sim_runs x WHERE x.sim_run_id = r.sim_run_id);
    IF c_events THEN
      EXECUTE 'SELECT count(*) FROM public.ottoq_events WHERE sim_run_id = $1' INTO v_ev_before USING r.sim_run_id;
    END IF;
    SELECT * INTO v_out FROM public.ottoq_sim_decide_and_dispatch(r.sim_run_id);
    IF v_out.out_dispatched IS DISTINCT FROM 0 OR v_out.out_charge_assigned IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION '0582 V2: the % run % was decided: %', r.status, r.sim_run_id, to_jsonb(v_out);
    END IF;
    IF (SELECT to_jsonb(x) FROM public.ottoq_sim_runs x WHERE x.sim_run_id = r.sim_run_id) IS DISTINCT FROM v_row_before THEN
      RAISE EXCEPTION '0582 V2: deciding the % run % wrote its row', r.status, r.sim_run_id;
    END IF;
    IF c_events THEN
      EXECUTE 'SELECT count(*) FROM public.ottoq_events WHERE sim_run_id = $1' INTO v_ev_after USING r.sim_run_id;
      IF v_ev_after IS DISTINCT FROM v_ev_before THEN
        RAISE EXCEPTION '0582 V2: deciding the % run % recorded % event(s)', r.status, r.sim_run_id, v_ev_after - v_ev_before;
      END IF;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0582 V2: % ended run(s) decided nothing', v_n;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0582_a_run_that_has_ended_dispatches_no_car', true, true,
  'G303, rule 9. ottoq_sim_decide_and_dispatch returns (0, 0) for a run whose status is completed, failed or aborted, '
  'the statuses on which ottoq_sim_runs_close_needs supersedes its open visits. The world step completes a run partway '
  'through its last tick, so the decide that followed found no work open on any car and the departure test passed cars '
  'with services unfinished (night 2, arm 25). The last tick of every run that reaches its clock''s end changes.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
