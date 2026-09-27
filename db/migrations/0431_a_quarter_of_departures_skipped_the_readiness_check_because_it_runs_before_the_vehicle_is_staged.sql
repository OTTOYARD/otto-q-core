-- migration-version: 20260922224038
-- migration-name:    a_quarter_of_departures_skipped_the_readiness_check_because_it_runs_before_the_vehicle_is_staged
--
-- 0431  **The dispatcher holds a staged vehicle until its readiness check is done.** `db/checks/0351`
--       measured 24 of 93 and 26 of 106 post-visit departures (25.8%, 24.5%, two busy_day seeds) leaving
--       the depot with `readiness_check` never performed, and every other must-do atom on those visits done.
--
-- ══ §1 THE MECHANISM, WHICH IS ORDER, NOT LOGIC ═════════════════════════════
--
-- `readiness_check` is `must_do`, not deferrable, and completed in exactly one place:
-- `twin.ottoq_sim_advance_visit_atoms`, only while the vehicle is `staged_for_departure`. The dispatcher's
-- must-do hold in `ottoq.ottoq_plan_dispatch_tick('deploy_plan')` exempts it — correctly in intent, because
-- the check is supposed to happen in the departure lane. But in `twin.ottoq_world_advance` the atom step is
-- call 1 of 27, service flow stages the vehicle at call 15, and dispatch is call 27. A vehicle whose last
-- service finishes during a tick is staged and deployed before the one step that performs its check has
-- ever seen it staged. **All 23 staged departures without a check spent 0 ticks staged; the 69 with one
-- spent 1.06** (`0351` §3). The only writer of `current_state='deployed'` on the live path is
-- `twin.ottoq_sim_dispatch_vehicle`, whose only caller is `twin.ottoq_sim_auto_dispatch_tick`, whose
-- candidates are this plan's `release` list — so this is the one place to hold.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
-- One clause, spliced after the existing must-do hold: a vehicle in `staged_for_departure` whose open visit
-- still has a `pending` readiness check is not a dispatch candidate. The check completes at call 1 of the
-- next tick and the vehicle is released at call 27 of it — **one tick of dwell for the quarter of
-- departures that were being staged and released at once, and nothing for the rest, which already waited.**
--
-- **It cannot strand a vehicle, and that is asserted rather than argued (P3):** the hold's predicate is the
-- completion loop's own selection — `status='pending'`, visit `open`/`in_progress`, the run's depot, the
-- `0124` run idiom — and that loop has no `LIMIT`. Anything this clause holds, the next tick's first call
-- completes.
--
-- Off-switch: `dispatch_holds_for_readiness_check`, catalogued here, default **1**, `[0,1]`, **not**
-- `agent_writable`. `0` restores the pre-0431 release exactly; it takes effect on the next tick.
--
-- And a standing instrument, `public.ottoq_assert_departure_readiness(run)`: `0351` §1 as a function — the
-- post-visit departures that left without a done check. **Expected empty** on every run after this one.
--
-- ══ §3 WHAT IS DELIBERATELY NOT DONE ════════════════════════════════════════
--
--   1. **`staged_awaiting_service -> deployed`** (1 of 93 on `0682752c`) is a dispatcher candidate state in
--      which the check can never run. Holding it here would strand it. Fixing it means letting the check run
--      there, which means enforcing `predecessors=['*']` — which no function reads today. Separate change;
--      the instrument above will count it.
--   2. **The check is not given a real 3-minute duration.** It completes instantly with a leg backdated 3
--      minutes, as it always has; this file changes whether it happens, not how long it takes.
--   3. **`ottoq_decide_tick`'s DEPLOY-READINESS section carries the same exemption and is not touched.** It
--      does not deploy — it writes decisions, and a command it emits is confirmed at call 5 of the next tick,
--      after call 1 has run the check.
--
-- `forces_recert` **TRUE**: dispatch timing moves, so commands, decisions, events and end state can move.
--
-- ══ §4 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight (0221's three checks; pg_stat_activity is the only authority on a pair) ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0431 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0431 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0431 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
  RAISE NOTICE '0431 P0: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- ── P1: md5 guard -- the dispatcher is the one this file was written against ──
DO $$
DECLARE v_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  IF v_md5 IS DISTINCT FROM '80ce225852c3fa6f37dd7968b884937b' THEN
    RAISE EXCEPTION '0431 P1: ottoq.ottoq_plan_dispatch_tick prosrc md5 is % -- it changed since 0351 read it; '
                    're-read before splicing', v_md5;
  END IF;
END $$;

-- ── P2: the anchor (end of the existing must-do hold) occurs exactly once ──
DO $$
DECLARE v_src text; v_anchor text; v_hits int;
BEGIN
  v_anchor := E'AND COALESCE(a->>''status'',''pending'') NOT IN (''done'',''cancelled'')))\n';
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  v_hits := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN RAISE EXCEPTION '0431 P2: anchor matched % times, expected 1', v_hits; END IF;
  IF position('<> ''readiness_check''' in v_src) = 0 THEN
    RAISE EXCEPTION '0431 P2: the readiness exemption is gone -- somebody already changed this hold';
  END IF;
END $$;

-- ── P3: THE ASSERTION THE HOLD RESTS ON. Whatever the clause holds, the next tick's first call completes:
--        the completion branch and the completion loop's selection must both still read exactly this way. ──
DO $$
DECLARE v_src text; v_pos int; v_seg text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_visit_atoms';
  IF v_src NOT LIKE '%ELSIF v_a->>''svc'' = ''readiness_check'' AND COALESCE(v_a->>''status'',''pending'') = ''pending''%'
     OR v_src NOT LIKE '%AND v_rec.current_state = ''staged_for_departure'' THEN%' THEN
    RAISE EXCEPTION '0431 P3: the readiness completion branch changed -- the hold could strand a vehicle';
  END IF;
  IF v_src NOT LIKE '%OR (v.current_state = ''staged_for_departure''%WHERE a->>''svc'' = ''readiness_check'' AND COALESCE(a->>''status'',''pending'') = ''pending'')))%' THEN
    RAISE EXCEPTION '0431 P3: the completion loop no longer selects staged vehicles with a pending check';
  END IF;
  -- From that loop's staged clause to its LOOP keyword: no LIMIT, or a held vehicle could starve. (A
  -- whole-body regex is not enough -- the FIRST loop in this function does carry LIMIT 30.)
  v_pos := position('OR (v.current_state = ''staged_for_departure''' in v_src);
  v_seg := substr(v_src, v_pos, position('LOOP' in substr(v_src, v_pos)));
  IF v_seg = '' OR v_seg ILIKE '%LIMIT%' THEN
    RAISE EXCEPTION '0431 P3: the completion loop carries a LIMIT (or could not be isolated) -- a held '
                    'vehicle could starve';
  END IF;
END $$;

-- ── P4: the order that makes this necessary -- the check runs before dispatch in the world advance ──
DO $$
DECLARE v_src text; v_atoms int; v_disp int;
BEGIN
  SELECT regexp_replace(p.prosrc, '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_world_advance';
  v_atoms := position('ottoq_sim_advance_visit_atoms(' in v_src);
  v_disp  := position('ottoq_sim_decide_and_dispatch(' in v_src);
  IF v_atoms = 0 OR v_disp = 0 OR v_atoms > v_disp THEN
    RAISE EXCEPTION '0431 P4: expected visit atoms (%) before decide-and-dispatch (%) in the world advance',
                    v_atoms, v_disp;
  END IF;
  RAISE NOTICE '0431 P4: visit atoms at %, decide-and-dispatch at % -- the check runs first', v_atoms, v_disp;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0431_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';

-- ── THE DIAL, BEFORE THE CODE THAT READS IT ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('dispatch_holds_for_readiness_check',
        '0431: when >= 1, ottoq.ottoq_plan_dispatch_tick(''deploy_plan'') does not release a vehicle in '
        'staged_for_departure whose open visit still has a pending readiness_check. The check is completed by '
        'twin.ottoq_sim_advance_visit_atoms at the start of the next tick, so the cost is one tick of dwell for '
        'vehicles staged and released in the same tick (db/checks/0351: 24.5% and 25.8% of post-visit '
        'departures left without the check). 0 restores the pre-0431 release; takes effect next tick.',
        1, 0, 1, 'ottoq.ottoq_plan_dispatch_tick', false)
ON CONFLICT (param_key) DO NOTHING;

-- ── THE EDIT -- surgical splice, asserted by byte delta ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  v_def := pg_get_functiondef(v_oid);
  v_anchor := E'AND COALESCE(a->>''status'',''pending'') NOT IN (''done'',''cancelled'')))\n';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0431: anchor matched % times in the definition, expected 1', v_hits;
  END IF;

  v_insert := $ins$           -- 0431: THE READINESS CHECK IS NOT OPTIONAL ON THE WAY OUT. The clause above
           -- exempts readiness_check because the check happens IN staged_for_departure -- but the step
           -- that performs it (twin.ottoq_sim_advance_visit_atoms) runs FIRST in the tick and this plan
           -- runs LAST, so a vehicle staged during this tick could leave before the check ever saw it:
           -- 24.5% and 25.8% of post-visit departures on two busy_day runs (db/checks/0351). Hold a
           -- staged vehicle until its check is done; it completes at the start of the next tick. The
           -- predicate mirrors that step's own selection (pending, open/in_progress visit, this depot,
           -- 0124 run idiom), so the hold can never strand a vehicle.
           -- Off-switch: dispatch_holds_for_readiness_check (default 1).
           AND NOT (v.current_state = 'staged_for_departure'
                AND (SELECT public.ottoq_policy_get(p_sim_run_id, 'dispatch_holds_for_readiness_check', 1)) >= 1
                AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                             WHERE vn.vehicle_id = v.id AND vn.depot_id = p_depot_id
                               AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                 = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                               AND vn.status IN ('open','in_progress')
                               AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                            WHERE a->>'svc' = 'readiness_check'
                                              AND COALESCE(a->>'status','pending') = 'pending')))
$ins$;

  v_new := replace(v_def, v_anchor, v_anchor || v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) THEN
    RAISE EXCEPTION '0431: byte delta % <> expected % -- refusing a substitution that did more than one '
                    'replacement', length(v_new) - length(v_def), length(v_insert);
  END IF;
  EXECUTE v_new;
  RAISE NOTICE '0431: readiness hold spliced into ottoq.ottoq_plan_dispatch_tick, +% chars', length(v_insert);
END $$;

-- ── THE INSTRUMENT: 0351 §1 as a standing function. Expected empty after this file. ──
CREATE OR REPLACE FUNCTION public.ottoq_assert_departure_readiness(p_sim_run_id uuid)
RETURNS TABLE(dispatch_id uuid, vehicle_id uuid, dispatched_at timestamptz, visit_id uuid,
              readiness_status text, readiness_done_at timestamptz)
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  -- 0431 (db/checks/0351). Every POST-VISIT departure of the run whose readiness_check was not done by the
  -- moment the vehicle was dispatched. A post-visit departure is a dispatch preceded by a visit of that
  -- vehicle in the same run; its visit is the latest to arrive at or before the dispatch. Prime deployments
  -- (no prior visit) are excluded by the join. Both columns compared are SIM clock (0351 §5).
  SELECT d.dispatch_id, d.vehicle_id, d.dispatched_at, vv.visit_id, r.status, r.done_at
    FROM public.ottoq_vehicle_dispatches d
    JOIN LATERAL (SELECT vn.visit_id, vn.atoms FROM public.ottoq_visit_needs vn
                   WHERE vn.vehicle_id = d.vehicle_id AND vn.sim_run_id = d.sim_run_id
                     AND vn.arrived_at <= d.dispatched_at
                   ORDER BY vn.arrived_at DESC LIMIT 1) vv ON true
    JOIN LATERAL (SELECT COALESCE(a->>'status','pending') AS status, (a->>'done_at')::timestamptz AS done_at
                    FROM jsonb_array_elements(vv.atoms) a WHERE a->>'svc' = 'readiness_check' LIMIT 1) r ON true
   WHERE d.sim_run_id = p_sim_run_id
     AND NOT (r.status = 'done' AND r.done_at <= d.dispatched_at)
   ORDER BY d.dispatched_at, d.dispatch_id;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_departure_readiness(uuid) IS
  '0431 / db/checks/0351: post-visit departures that left without a done readiness_check. Expected EMPTY '
  'on every run after 0431 (it read 24 of 93 and 26 of 106 before). A non-empty result names each '
  'departure; one leaving from staged_awaiting_service is the known residual 0431 section 3 describes.';

-- House convention (0406): a new function in public does not inherit the default anon grant.
REVOKE ALL ON FUNCTION public.ottoq_assert_departure_readiness(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_assert_departure_readiness(uuid) TO authenticated, service_role;

-- ── V1: the clause is in, the dial reads back on, and it is not agent-writable ──
DO $$
DECLARE v_src text; v_md5 text; v_agent boolean;
BEGIN
  SELECT p.prosrc, md5(p.prosrc) INTO v_src, v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  IF v_md5 = '80ce225852c3fa6f37dd7968b884937b' THEN RAISE EXCEPTION '0431 V1: the body did not change'; END IF;
  IF v_src NOT LIKE '%dispatch_holds_for_readiness_check%' OR v_src NOT LIKE '%0431: THE READINESS CHECK%' THEN
    RAISE EXCEPTION '0431 V1: the hold is not in the dispatcher';
  END IF;
  -- the original exemption must survive: this file adds a hold, it does not rewrite the old one
  IF position('<> ''readiness_check''' in v_src) = 0 THEN
    RAISE EXCEPTION '0431 V1: the original must-do hold was altered';
  END IF;
  SELECT agent_writable INTO v_agent FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'dispatch_holds_for_readiness_check';
  IF v_agent IS DISTINCT FROM false THEN RAISE EXCEPTION '0431 V1: the dial is missing or agent-writable'; END IF;
  IF public.ottoq_policy_get(NULL::uuid, 'dispatch_holds_for_readiness_check', 1) < 1 THEN
    RAISE EXCEPTION '0431 V1: the dial does not read back on for a run with no override';
  END IF;
  RAISE NOTICE '0431 V1: hold present, original exemption intact, dial on and not agent-writable';
END $$;

-- ── V2: EXECUTED, not just parsed. deploy_plan is read-only (every callee is STABLE/IMMUTABLE and writes
--        nothing -- checked by hand for 0351), so run it against the newest twin-depot run with a real budget
--        and require a plan back. This resolves every new reference: v, vn, p_depot_id, p_sim_run_id. ──
DO $$
DECLARE v_run uuid; v_clock timestamptz; v_plan jsonb;
BEGIN
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1;
  v_plan := ottoq.ottoq_plan_dispatch_tick('deploy_plan', v_run, '11111111-1111-1111-1111-111111111111'::uuid,
                                           COALESCE(v_clock, now()), NULL, 0, 20);
  IF v_plan->>'phase' IS DISTINCT FROM 'deploy_plan' OR v_plan->'release' IS NULL THEN
    RAISE EXCEPTION '0431 V2: deploy_plan did not return a plan: %', v_plan;
  END IF;
  RAISE NOTICE '0431 V2: deploy_plan executed against run %, released % of budget 20, cap %',
               v_run, jsonb_array_length(v_plan->'release'), v_plan->>'cap';
END $$;

-- ── V3: the instrument reproduces 0351 §1 on the run that measured it, if its rows still exist ──
DO $$
DECLARE v_n int; v_disp int;
BEGIN
  SELECT count(*) INTO v_disp FROM public.ottoq_vehicle_dispatches
   WHERE sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0';
  IF v_disp = 0 THEN
    RAISE NOTICE '0431 V3: run 0682752c has been purged -- instrument not cross-checked against 0351';
    RETURN;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_assert_departure_readiness('0682752c-7082-4ece-97df-152a67f463f0');
  IF v_n <> 24 THEN
    RAISE EXCEPTION '0431 V3: the instrument reads % departures without a check on 0682752c; 0351 measured 24', v_n;
  END IF;
  RAISE NOTICE '0431 V3: instrument reproduces 0351 -- 24 departures without a check on 0682752c';
END $$;

-- ── LINEAGE. In the file and inside the transaction. ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0431_a_quarter_of_departures_skipped_the_readiness_check_because_it_runs_before_the_vehicle_is_staged',
  true,
  'db/checks/0351: 24 of 93 (0682752c) and 26 of 106 (6a8a7029) post-visit departures left with '
  'readiness_check never done, every other must-do atom done. Cause is ORDER inside one tick: '
  'twin.ottoq_world_advance runs the visit-atom step (the only completer of readiness_check, and only for '
  'staged_for_departure) at call 1, stages vehicles at call 15, and dispatches at call 27, while '
  'ottoq.ottoq_plan_dispatch_tick exempts readiness_check from its must-do hold. All 23 staged departures '
  'without a check spent 0 ticks staged; the 69 with one spent 1.06. This splices ONE clause after the '
  'existing hold: a staged_for_departure vehicle whose open visit has a pending readiness_check is not '
  'released; the next tick''s call 1 completes it. The predicate mirrors the completion loop''s own selection '
  '(pending, open/in_progress, depot, 0124 idiom) and P3 asserts that loop still selects exactly that with no '
  'LIMIT, so the hold cannot strand a vehicle. Dial dispatch_holds_for_readiness_check, default 1, not '
  'agent_writable; 0 restores the prior release. Adds public.ottoq_assert_departure_readiness(run), expected '
  'empty. NOT done: staged_awaiting_service departures (1 of 93) where the check cannot run; no real 3-minute '
  'duration; decide_tick''s DEPLOY-READINESS exemption (it does not deploy). TRUE because dispatch timing '
  'moves and commands, decisions, events and end state are atoms.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §5 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` TRUE — let the recert runner resweep before quoting any determinism claim.
--
-- Then, on the first fresh run after the apply:
--
--   SELECT count(*) FROM public.ottoq_assert_departure_readiness('<run>');       -- EXPECT 0 (or the
--                                                                               --  staged_awaiting_service residual)
--   -- and the cost, which should be about one tick for about a quarter of departures:
--   --   rerun db/checks/0351 §3 on <run>: the `false` row should be gone, and the `true` row's
--   --   staged_and_deployed_same_tick should be 0.
--
-- If departures stall instead — vehicles piling up in staged_for_departure — the P3 premise has broken:
--
--   SELECT public.ottoq_policy_set('global', NULL, 'dispatch_holds_for_readiness_check', 0, 'operator');
--
-- restores the old release on the next tick. Then find out why the check stopped completing.
