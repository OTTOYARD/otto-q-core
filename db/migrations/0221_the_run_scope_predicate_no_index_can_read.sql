-- migration-version: 20260908111950
-- migration-name:    the_run_scope_predicate_no_index_can_read
--
-- ---------------------------------------------------------------------------
-- 0221 — the run-scope predicate no index can read. A carrier found while
--        chasing G19; worth fixing on its own terms, and NOT the drift.
--
-- HOW BIG IS IT, measured before claiming anything (db/checks/0127 Q6): both
-- forms run through plpgsql variables across all 158 flagship stalls, warmed,
-- then timed twice — 7.83 and 7.38 ms per call for the COALESCE form against
-- 0.035 and 0.025 ms for the sargable one, ~300x. An arm emits 569 vehicle
-- commands, so this is ~4.2 s per arm and ~8.4 s of an 812 s pair: ONE PERCENT.
-- To account for the pair's ~566 s of tick time the query would have to be
-- called 67 times per emitted command, and it is not.
--
-- So apply it because it is a genuine unbounded-in-history read on the hot path
-- that gets monotonically worse and costs nothing to fix — not because it will
-- move the clock. It will not, and 0127 says so before the fact rather than
-- after. G19 remains open: 1,957,327 sequential scans of ottoq_stall_bookings
-- reading 49.3 billion tuples belong to some OTHER query, and two measurements
-- are already scheduled to name it.
--
-- Convicted in db/checks/0127. ottoq.ottoq_validate_assignment is called by
-- ottoq_emit_vehicle_command on every assignment — 569 vehicle commands per
-- certification arm. Its forward-calendar conflict check scopes the run like
-- this:
--
--     AND COALESCE(b.sim_run_id,'000…000'::uuid)
--       = COALESCE(p_sim_run_id,'000…000'::uuid)
--
-- ottoq_stall_bookings_live_stall_idx is btree (sim_run_id, stall_id) WHERE
-- state IN ('held','active','done','interrupted') — an exact match for this
-- query's state set, built for exactly this lookup. COALESCE(b.sim_run_id, …)
-- is a function OF the column rather than the column, so the planner cannot use
-- the leading column at all. It enters the index on stall_id — the second
-- column — and walks every booking that stall has ever had, in every run that
-- ever ran, filtering afterwards.
--
--   COALESCE form   Index Cond: (stall_id = …)                        cost 5311.29
--   sargable form   Index Cond: ((sim_run_id = …) AND (stall_id = …))  cost    2.65
--
-- 2,004x by planner cost, ~300x on a stopwatch, and the important half is
-- neither ratio: the expensive plan's cost is a function of total history and
-- the cheap one's is not. 1,247 entries walked per call today on a typical
-- flagship stall; about 40 a week ago; more tomorrow. That is G19's SHAPE — a
-- fixed workload getting monotonically slower in calendar time — which is
-- exactly what made it tempting to call it G19's cause. It is not; see the
-- arithmetic at the top. ottoq_stall_bookings really is 53% of every disk read
-- this database has ever performed, and this query is not how most of that
-- happens.
--
-- WHY THE PREDICATE IS SHAPED THAT WAY, because it was not careless: 0123 and
-- 0124 closed the 0145 defect class by scoping reads of run-scoped tables to
-- their own run, and wrote the scope so that a NULL run id (production) matches
-- a NULL run id. Correct semantics. Unreadable by any index on the column being
-- scoped. Thirty-three functions carry it; this migration changes ONE, the one
-- measured to dominate, and the rest are swept only if this one moves the
-- clock. Two previous performance fixes measured beautifully and bought zero
-- seconds; the lesson taken is to spend a pair before generalising.
--
-- THE ROW SET IS PROVABLY IDENTICAL. Written as an explicit branch rather than
-- an OR so each arm is independently sargable:
--
--   p_sim_run_id NULL      old: COALESCE(b.sim_run_id,nil) = nil
--                               -> b.sim_run_id IS NULL OR b.sim_run_id = nil
--                          new: b.sim_run_id IS NULL
--   p_sim_run_id non-NULL  old: COALESCE(b.sim_run_id,nil) = p
--                               -> b.sim_run_id = p  (nil is not a run id)
--                          new: b.sim_run_id = p
--
-- The two differ only if some booking carries the all-zero uuid as its
-- sim_run_id. P1 asserts there are none, and none among the runs either. The
-- ORDER BY and LIMIT are untouched, so the row PICKED is the same row.
--
-- forces_recert: FALSE — and here that is a PREDICTION, not a shrug. This is a
-- decide-path function and the next round is the test: every atom on every
-- column must be unchanged. If one moves, the rewrite changed behaviour and the
-- correct response is to revert it, not to re-baseline the canon.
-- ---------------------------------------------------------------------------

BEGIN;

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- The standing constraint: never apply while a certification pair is running or
-- scheduled. Until 2026-09-08 that was enforced by the operator remembering it,
-- for three of the four migrations queued behind round 25. It is a file now.
--
-- All three checks are needed and the middle one is the load-bearing one.
-- ottoq_sim_runs cannot see an in-flight pair AT ALL: both arms run inside one
-- transaction, so their rows are uncommitted and invisible until it ends. And
-- cron.job_run_details reports an in-flight pair of this shape as
-- status='succeeded', return_message='SET', duration ~1 s, because the job
-- command is two statements and the row reflects the first (db/canons/round25.md).
-- pg_stat_activity is the only authority.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0221 P-: certification jobs are still scheduled (%) — migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0221 P-: a determinism pair is running right now';
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0221 P-: % sim run(s) are in flight', v_runs;
  END IF;

  RAISE NOTICE '0221 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0221_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_validate_assignment';

-- P0. THE BODY IS THE ONE THIS WAS WRITTEN AGAINST, AND CARRIES THE PREDICATE --
DO $p0$
DECLARE v_md5 text; v_n int;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_validate_assignment';
  IF v_md5 IS DISTINCT FROM '6515128e' THEN
    RAISE EXCEPTION '0221 P0: ottoq.ottoq_validate_assignment is %, pinned 6515128e',
                    COALESCE(v_md5, '(absent)');
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace,
       LATERAL regexp_matches(p.prosrc, 'COALESCE\(b\.sim_run_id', 'g')
   WHERE n.nspname='ottoq' AND p.proname='ottoq_validate_assignment';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0221 P0: the COALESCE(b.sim_run_id …) predicate appears % times, want 1', v_n;
  END IF;
  RAISE NOTICE '0221 P0: body 6515128e, one COALESCE(b.sim_run_id …) predicate';
END $p0$;

-- P1. THE TWO FORMS ARE EQUIVALENT ON THIS DATA -----------------------------
-- They can only differ on a booking whose sim_run_id is literally the all-zero
-- uuid, because that is the sentinel COALESCE folds NULL onto. If one exists,
-- the rewrite is NOT behaviour-preserving and must not be applied.
DO $p1$
DECLARE v_b int; v_r int;
BEGIN
  SELECT count(*) INTO v_b FROM public.ottoq_stall_bookings
   WHERE sim_run_id = '00000000-0000-0000-0000-000000000000';
  SELECT count(*) INTO v_r FROM public.ottoq_sim_runs
   WHERE sim_run_id = '00000000-0000-0000-0000-000000000000';
  IF v_b <> 0 OR v_r <> 0 THEN
    RAISE EXCEPTION '0221 P1: % booking(s) and % run(s) carry the all-zero sentinel uuid — '
                    'the COALESCE form and the branch form are NOT equivalent on this data',
                    v_b, v_r;
  END IF;
  RAISE NOTICE '0221 P1: no row carries the all-zero sentinel; the forms are equivalent';
END $p1$;

-- P2. THE INDEX THE REWRITE DEPENDS ON EXISTS AND STILL COVERS THE STATE SET --
-- If live_stall_idx were dropped or its partial predicate narrowed, the
-- sargable form would buy nothing and this migration would be theatre.
DO $p2$
DECLARE v_def text;
BEGIN
  SELECT indexdef INTO v_def FROM pg_indexes
   WHERE schemaname='public' AND tablename='ottoq_stall_bookings'
     AND indexname='ottoq_stall_bookings_live_stall_idx';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0221 P2: ottoq_stall_bookings_live_stall_idx does not exist';
  END IF;
  IF position('(sim_run_id, stall_id)' in v_def) = 0 THEN
    RAISE EXCEPTION '0221 P2: live_stall_idx is not (sim_run_id, stall_id): %', v_def;
  END IF;
  IF position('''held''' in v_def)=0 OR position('''active''' in v_def)=0
     OR position('''done''' in v_def)=0 OR position('''interrupted''' in v_def)=0 THEN
    RAISE EXCEPTION '0221 P2: live_stall_idx no longer covers the four-state set the query '
                    'uses, so it cannot serve the rewritten predicate: %', v_def;
  END IF;
  RAISE NOTICE '0221 P2: live_stall_idx present, (sim_run_id, stall_id), four-state partial';
END $p2$;

CREATE OR REPLACE FUNCTION ottoq.ottoq_validate_assignment(p_vehicle_id uuid, p_stall_id uuid, p_command_type text, p_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh RECORD; v_stall RECORD; v_charger_state text; v_cal_conflict uuid;
BEGIN
  SELECT id, current_state::text AS st, current_stall_id INTO v_veh
    FROM vehicles WHERE id = p_vehicle_id;
  IF v_veh.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','target_unknown','detail','vehicle not found');
  END IF;
  IF v_veh.st IN ('tow_requested','out_of_service') THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_unresponsive','detail','vehicle is '||v_veh.st);
  END IF;

  IF p_stall_id IS NULL THEN
    IF p_command_type IN ('proceed_to_stall','begin_charge') THEN
      RETURN jsonb_build_object('ok',false,'code','command_malformed','detail','stall_id required for '||p_command_type);
    END IF;
    RETURN jsonb_build_object('ok',true);   -- advisory command, no resource claim
  END IF;

  SELECT s.id, s.status, s.current_vehicle_id, s.reserved_by, s.reservation_expires_at,
         s.stall_type::text AS stype, s.ocpp_charger_id, s.depot_id
    INTO v_stall FROM stalls s WHERE s.id = p_stall_id;
  IF v_stall.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','target_unknown','detail','stall '||p_stall_id||' not found');
  END IF;
  IF v_veh.current_stall_id = v_stall.id THEN
    RETURN jsonb_build_object('ok',true,'already_in_place',true);
  END IF;
  IF v_stall.status IN ('maintenance','closed') THEN
    RETURN jsonb_build_object('ok',false,'code','resource_faulted','detail','stall '||v_stall.status);
  END IF;
  IF v_stall.current_vehicle_id IS NOT NULL AND v_stall.current_vehicle_id <> p_vehicle_id THEN
    RETURN jsonb_build_object('ok',false,'code','target_occupied','detail','stall occupied by '||v_stall.current_vehicle_id,'blocker_vehicle_id',v_stall.current_vehicle_id);
  END IF;
  IF v_stall.reserved_by IS NOT NULL AND v_stall.reserved_by <> p_vehicle_id
     AND COALESCE(v_stall.reservation_expires_at, p_clock) > p_clock THEN
    RETURN jsonb_build_object('ok',false,'code','target_occupied','detail','stall reserved by '||v_stall.reserved_by,'blocker_vehicle_id',v_stall.reserved_by);
  END IF;
  IF p_command_type = 'begin_charge' AND v_stall.ocpp_charger_id IS NOT NULL THEN
    SELECT c.station_state::text INTO v_charger_state
      FROM ottoq_ocpp_chargers c WHERE c.charger_id = v_stall.ocpp_charger_id;
    IF v_charger_state IS DISTINCT FROM 'Available' THEN
      RETURN jsonb_build_object('ok',false,'code','resource_faulted','detail','charger '||COALESCE(v_charger_state,'unknown'));
    END IF;
  END IF;
  -- forward calendar: an assignment must not collide with a live booking held
  -- by ANOTHER vehicle covering this moment
  --
  -- 2026-08-03 (P1): state set aligned to ottoq_stall_bookings_no_overlap_v3 and to
  -- ottoq.ottoq_stall_free_between -- held/active/done/interrupted. A validator that
  -- returns ok=true for a stall the EXCLUDE constraint would then refuse to book is
  -- the picker-vs-constraint divergence that produced the one-bay pile-up.
  -- 'done' and 'interrupted' are REAL past occupancy and every close path truncates
  -- `during` to the true end of occupancy (interrupted verified 40 of 40, phantom
  -- tail 0.00 min), so such a row can only match @> p_clock while the space is
  -- genuinely still held. 'released'/'superseded' mean the occupancy never happened
  -- and stay invisible here, so this can never make an idle stall look busy.
  -- Direction of change is STRICTLY tighter: it can only ever turn a true into a
  -- false, so it cannot create a double-booking.
  --
  --: 0221. The run scope is an explicit BRANCH, not a COALESCE over the column
  --: folded onto a sentinel uuid. Same rows -- the two forms can only differ
  --: on a booking carrying the all-zero sentinel as its run id, and there are
  --: none (P1) -- but COALESCE over the column is a function of the column, so
  --: the planner could not use the LEADING column of
  --: ottoq_stall_bookings_live_stall_idx (sim_run_id, stall_id) and entered on
  --: stall_id instead, walking every booking that stall ever had in every run
  --: that ever ran. Measured 2026-09-08: cost 5311.29 -> 2.65, 1,247 index
  --: entries walked per call -> 1, and the expensive plan's cost grows with
  --: total history while this one does not. Each branch is separately sargable;
  --: an OR would not be. See db/checks/0127.
  IF p_sim_run_id IS NULL THEN
    SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
     WHERE b.sim_run_id IS NULL AND b.stall_id = p_stall_id
       AND b.state IN ('held','active','done','interrupted')
       AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
     ORDER BY lower(b.during), b.vehicle_id, b.booking_id
     LIMIT 1;
  ELSE
    SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
     WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = p_stall_id
       AND b.state IN ('held','active','done','interrupted')
       AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
     ORDER BY lower(b.during), b.vehicle_id, b.booking_id
     LIMIT 1;
  END IF;
  IF v_cal_conflict IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','target_occupied','detail','calendar booking held by '||v_cal_conflict,'blocker_vehicle_id',v_cal_conflict);
  END IF;

  RETURN jsonb_build_object('ok',true);
END $function$;

-- A1. THE PREDICATE IS GONE AND BOTH BRANCHES ARE PRESENT -------------------
DO $a1$
DECLARE v_def text; v_flat text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_validate_assignment';
  v_flat := regexp_replace(v_def, '\s+', ' ', 'g');
  --: match the PREDICATE (column folded onto the sentinel), not the bare
  --: substring 'COALESCE(b.sim_run_id' -- an explanatory comment in this very
  --: function contained that substring, and the first draft of this assertion
  --: would have aborted the migration on its own prose. Same failure shape as
  --: 0219's whitespace bug: a guard that fires on correct input is worse than
  --: no guard, because the reflex is to weaken it.
  IF position($$COALESCE(b.sim_run_id,'00000000$$ in v_flat) <> 0
     OR position($$COALESCE(b.sim_run_id, '00000000$$ in v_flat) <> 0 THEN
    RAISE EXCEPTION '0221 A1: the COALESCE run-scope predicate is still in the body';
  END IF;
  IF position('b.sim_run_id IS NULL AND b.stall_id = p_stall_id' in v_flat) = 0 THEN
    RAISE EXCEPTION '0221 A1: the production (NULL run) branch is missing';
  END IF;
  IF position('b.sim_run_id = p_sim_run_id AND b.stall_id = p_stall_id' in v_flat) = 0 THEN
    RAISE EXCEPTION '0221 A1: the sim (non-NULL run) branch is missing';
  END IF;
  IF position('ORDER BY lower(b.during), b.vehicle_id, b.booking_id' in v_flat) = 0 THEN
    RAISE EXCEPTION '0221 A1: the total order that decides WHICH conflict is reported is gone';
  END IF;
  RAISE NOTICE '0221 A1: COALESCE gone, both branches present, order preserved';
END $a1$;

-- A2. THE PLANNER NOW USES BOTH INDEX COLUMNS -------------------------------
-- The behavioural assertion. Runs the rewritten predicate through EXPLAIN and
-- requires the leading column in the Index Cond. Against the old form this
-- fails: the plan enters on stall_id alone.
DO $a2$
DECLARE r record; v_plan text := ''; v_stall uuid; v_run uuid;
BEGIN
  SELECT id INTO v_stall FROM public.stalls
   WHERE depot_id='11111111-1111-1111-1111-111111111111' ORDER BY stall_code LIMIT 1;
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 1;
  IF v_stall IS NULL OR v_run IS NULL THEN
    RAISE NOTICE '0221 A2 SKIPPED: no flagship stall or no sim run to plan against'; RETURN;
  END IF;
  -- EXPLAIN returns one ROW PER LINE, so this loops rather than using
  -- EXECUTE ... INTO, which would capture only the first line and make the
  -- assertion fail on a correct plan.
  FOR r IN EXECUTE format(
    'EXPLAIN SELECT b.vehicle_id FROM public.ottoq_stall_bookings b '
    ' WHERE b.sim_run_id = %L AND b.stall_id = %L '
    '   AND b.state IN (''held'',''active'',''done'',''interrupted'') '
    '   AND b.vehicle_id <> %L AND b.during @> now() '
    ' ORDER BY lower(b.during), b.vehicle_id, b.booking_id LIMIT 1',
    v_run, v_stall, '00000000-0000-0000-0000-000000000001'::uuid)
  LOOP
    v_plan := v_plan || r."QUERY PLAN" || E'\n';
  END LOOP;
  IF position('live_stall_idx' in v_plan) = 0 THEN
    RAISE EXCEPTION '0221 A2: the rewritten predicate does not plan onto live_stall_idx:%',
                    E'\n'||v_plan;
  END IF;
  IF position('Index Cond: ((sim_run_id' in v_plan) = 0 THEN
    RAISE EXCEPTION '0221 A2: live_stall_idx is used but NOT on its leading column — the '
                    'predicate is still not sargable on sim_run_id:%', E'\n'||v_plan;
  END IF;
  RAISE NOTICE '0221 A2: rewritten predicate plans onto live_stall_idx, leading column in the Index Cond';
END $a2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0221_the_run_scope_predicate_no_index_can_read', FALSE,
        'G19 carrier, db/checks/0127. ottoq.ottoq_validate_assignment scoped its forward-calendar '
        'conflict lookup with COALESCE(b.sim_run_id, nil) = COALESCE(p_sim_run_id, nil) — a '
        'function of the column, so the planner could not use the leading column of '
        'ottoq_stall_bookings_live_stall_idx (sim_run_id, stall_id) and entered on stall_id, '
        'walking every booking that stall ever had across every run in history. cost 5311.29 -> '
        '2.65; 1,247 entries walked per call today, ~40 a week ago, more tomorrow — which is '
        'exactly G19''s shape. Rewritten as an explicit branch so each arm is sargable; row set '
        'provably identical (the forms differ only on the all-zero sentinel, of which P1 asserts '
        'there are none). forces_recert FALSE is a PREDICTION here, not a shrug: this is a '
        'decide-path function and every atom on every column must be unchanged next round. If '
        'one moves, revert. 32 further functions carry the same COALESCE run-scope from 0123/0124 '
        'and are deliberately NOT touched until this one is measured on a pair.',
        now());

COMMIT;
