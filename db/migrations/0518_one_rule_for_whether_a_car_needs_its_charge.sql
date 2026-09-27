-- migration-version: 20260927074142
-- migration-name:    one_rule_for_whether_a_car_needs_its_charge
--
-- 0518  **G244: three parts of the engine answer "does this car still need a charge", and the flow contract used a
--       looser rule than the other two, so a car between them got a charge need, had it closed as satisfied, and was
--       sent to charge anyway. The flow contract now closes at the rule the others use, and says who closed it.**
--       `db/checks/0377` §4(a), §4(a2); `db/checks/0387`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq.ottoq_derive_visit_needs` (`IF v_soc < v_visit_target - 1`) and `ottoq.ottoq_reassess_charge_needs`
--   (`current_soc < target - 1`) give a car a charge need below 1 point under its target, and 0493 (G210) aligned the
--   charge cursor in `ottoq_decide_tick` to the same rule. `twin.ottoq_sim_advance_flow_contract` closes a visit's
--   charge step for any car not charging and not en route at `target - 2` or above. A car in [target - 2, target - 1)
--   therefore has a need the deriver writes and the flow contract closes, and the cursor charges it regardless. On
--   validation run caf85837: Zoox-AV-076 at 83% against 85% -- closed 8:45:09, booked an L2 24 seconds later, charged
--   83 -> 90% for 36 minutes; Zoox-AV-072 at 88% against 90% -- closed 8:05:22, booked 8:05:44. 0511's hold keys on the
--   charge step, so both cars' cabin work started in the gate's queue instead of at the charger, and neither step said
--   who had closed it. The full-day run 4bc19d29 did it twice more by 8:24 AM (Zoox-AV-099 at 88 against 90, Waymo-AV-034
--   at 83 against 85), each plugged in under a minute after its step was closed (`db/checks/0387` §1).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The flow contract closes the step at `target - 1`: satisfied exactly when the deriver and the cursor would not
--       ask for a charge, so the gap is empty. A car at 84% against 85% is still closed; at 83% it keeps its need.
--   (2) The step it closes is stamped `closed_by = 'flow_contract_near_target'` with `closed_at`, `closed_soc` and
--       `closed_vs_target`, the way `ottoq_close_satisfied_charge_needs` stamps its own, so the next audit of who closed
--       a charge, and how far from its target, reads the step instead of reconstructing the SoC from the event stream.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The flow contract runs in every certified arm, and a car in the gap now keeps its charge step open until its
--   session closes it: decisions, commands, bookings, sessions and records can move on any busy column. Applied with no
--   run live, then the canon sweep reads what moved. Measured on the night's two operator runs, the change touches 6 of
--   their 54 flow-contract closes, the ones with the car at [target - 2, target - 1): 4 were charged within a minute
--   anyway; of the other 2, one charged 81 minutes later and one (98 against 100, after a charger fault) not before its
--   run stopped. Those now keep the step, and the deploy gate's remedy for an open charge step is `need_charge` (0464),
--   not the service bay (`db/checks/0387` §1).

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0518 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure);
  -- the rule this aligns to, in all three places that ask it: the deriver, the reassessment and the cursor (0493)
  IF position('IF v_soc < v_visit_target - 1 THEN' IN (SELECT prosrc FROM pg_proc WHERE oid =
       'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure)) = 0
     OR position('AND v.current_soc < COALESCE(n.target_soc, v.target_soc, public.ottoq_default_target_soc()) - 1'
                 IN (SELECT prosrc FROM pg_proc WHERE oid = 'ottoq.ottoq_reassess_charge_needs(uuid,timestamptz)'::regprocedure)) = 0
     OR position('-- 0493 (G210): the deriver''s charge rule, below the visit target minus 1'
                 IN (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0518 P2: the deriver, the reassessment or the cursor no longer asks for a charge below target - 1';
  END IF;
  -- the flow contract still closes at target - 2, through the shared marker
  IF position('AND v.current_soc >= COALESCE((a->>''target_soc'')::numeric, public.ottoq_default_target_soc()) - 2' IN v_def) = 0
     OR position('PERFORM ottoq_mark_visit_atoms_done(v_rec.vehicle_id, ARRAY[''charge''], p_clock);' IN v_def) = 0 THEN
    RAISE EXCEPTION '0518 P2: the flow contract is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0518_pre', 'function', 'twin', 'ottoq_sim_advance_flow_contract',
       pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure),
       md5(pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure));

DO $patch$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$       AND v.current_soc >= COALESCE((a->>'target_soc')::numeric, public.ottoq_default_target_soc()) - 2$o1$,
          $n1$       -- 0518 (G244): the rule the need deriver and the charge cursor use -- a charge is needed below target - 1
       -- (ottoq_derive_visit_needs, ottoq_reassess_charge_needs, 0493/G210). At target - 2 a car between the two rules had
       -- its need closed here and was then sent to charge by the cursor anyway.
       AND v.current_soc >= COALESCE((a->>'target_soc')::numeric, public.ottoq_default_target_soc()) - 1$n1$],
    ARRAY[$o2$    PERFORM ottoq_mark_visit_atoms_done(v_rec.vehicle_id, ARRAY['charge'], p_clock);$o2$,
          $n2$    PERFORM ottoq_mark_visit_atoms_done(v_rec.vehicle_id, ARRAY['charge'], p_clock);
    -- 0518 (G244): say who closed it, at what SoC and against what target, as ottoq_close_satisfied_charge_needs does
    UPDATE ottoq_visit_needs vn
       SET atoms = (SELECT jsonb_agg(CASE WHEN e.a->>'svc' = 'charge' AND e.a->>'status' = 'done'
                                            AND NOT (e.a ? 'closed_by') AND (e.a->>'done_at')::timestamptz = p_clock
                                          THEN e.a || jsonb_build_object('closed_by', 'flow_contract_near_target',
                                                                         'closed_at', p_clock,
                                                                         'closed_soc', (SELECT v.current_soc FROM vehicles v
                                                                                         WHERE v.id = v_rec.vehicle_id),
                                                                         'closed_vs_target', COALESCE((e.a->>'target_soc')::numeric,
                                                                                               public.ottoq_default_target_soc()))
                                          ELSE e.a END ORDER BY e.ord)
                      FROM jsonb_array_elements(vn.atoms) WITH ORDINALITY e(a, ord))
     WHERE vn.vehicle_id = v_rec.vehicle_id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open','in_progress')
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x
                    WHERE x->>'svc' = 'charge' AND x->>'status' = 'done' AND NOT (x ? 'closed_by')
                      AND (x->>'done_at')::timestamptz = p_clock);$n2$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0518: flow-contract patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

DO $verify$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure);
  -- V1: the rule once, no target - 2 left, the stamp once, still SECURITY DEFINER
  IF position('public.ottoq_default_target_soc()) - 1' IN v_def) = 0
     OR position('public.ottoq_default_target_soc()) - 2' IN v_def) > 0
     OR (length(v_def) - length(replace(v_def, 'flow_contract_near_target', ''))) / length('flow_contract_near_target') <> 1
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure) THEN
    RAISE EXCEPTION '0518 V1: the patched flow contract is not as intended';
  END IF;
END $verify$;

-- V3: rolled back. On the newest finished operator run -- marked running inside the test, because the shared marker
--     `ottoq_mark_visit_atoms_done` finds only the depot's running run's visits, so this needs no other run live -- at a
--     clock past its end, with one car planted at the gate against an open visit whose charge step targets 85: (a) at 83,
--     inside the old gap, the step stays open; (b) at 84 it closes, stamped `flow_contract_near_target` with its SoC (84)
--     and target (85); (c) the stamp names the tick's clock.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_car uuid; v_end timestamptz; v_visit uuid; v_atom jsonb; v_state text; v_soc numeric;
BEGIN
  BEGIN
    SELECT sr.sim_run_id, sr.sim_clock_current INTO v_run, v_end FROM public.ottoq_sim_runs sr
     WHERE sr.run_by = 'operator_demo' AND sr.status = 'completed' ORDER BY sr.started_at DESC LIMIT 1;
    -- a car not in any open visit of that run, parked in a state the flow contract judges
    SELECT v.id INTO v_car FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn WHERE vn.vehicle_id = v.id AND vn.sim_run_id = v_run
                          AND vn.status IN ('open','in_progress'))
     ORDER BY v.id LIMIT 1;
    IF v_run IS NULL OR v_car IS NULL THEN RAISE EXCEPTION '0518 V3 FAILED: nothing to plant on'; END IF;
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
      RAISE EXCEPTION '0518 V3 FAILED: a run is live; the shared marker would look at it, not at the planted visit';
    END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    SELECT current_state::text, current_soc INTO v_state, v_soc FROM public.vehicles WHERE id = v_car;
    UPDATE public.vehicles SET current_state = 'arrived_at_gate', current_soc = 83 WHERE id = v_car;
    v_visit := gen_random_uuid();
    INSERT INTO public.ottoq_visit_needs (visit_id, visit_key, vehicle_id, depot_id, sim_run_id, status, arrived_at, target_soc, atoms)
    VALUES (v_visit, v_car::text || ':0518v3', v_car, '11111111-1111-1111-1111-111111111111', v_run, 'open',
            v_end + interval '2 hours', 85,
            jsonb_build_array(jsonb_build_object('svc', 'charge', 'status', 'pending', 'must_do', true, 'target_soc', 85,
                                                 'concurrency', 'anchor')));
    -- (a) 83 against 85: needed by the deriver's rule, so the flow contract must leave it
    PERFORM twin.ottoq_sim_advance_flow_contract(v_run, v_end + interval '2 hours');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a WHERE vn.visit_id = v_visit;
    IF v_atom->>'status' <> 'pending' THEN
      RAISE EXCEPTION '0518 V3 FAILED (a): a car at 83%% against 85%% had its charge step closed: %', v_atom;
    END IF;
    -- (b) 84 against 85: not needed by that rule, so the flow contract closes it and says so
    UPDATE public.vehicles SET current_soc = 84 WHERE id = v_car;
    PERFORM twin.ottoq_sim_advance_flow_contract(v_run, v_end + interval '2 hours 1 minute');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a WHERE vn.visit_id = v_visit;
    IF v_atom->>'status' <> 'done' OR v_atom->>'closed_by' IS DISTINCT FROM 'flow_contract_near_target'
       OR (v_atom->>'closed_soc')::numeric IS DISTINCT FROM 84 OR (v_atom->>'closed_vs_target')::numeric IS DISTINCT FROM 85 THEN
      RAISE EXCEPTION '0518 V3 FAILED (b): a car at 84%% against 85%% was not closed and stamped: %', v_atom;
    END IF;
    -- (c) the stamp names the clock it closed at
    IF (v_atom->>'closed_at')::timestamptz <> v_end + interval '2 hours 1 minute'
       OR (v_atom->>'done_at')::timestamptz <> v_end + interval '2 hours 1 minute' THEN
      RAISE EXCEPTION '0518 V3 FAILED (c): the close does not name its clock: %', v_atom;
    END IF;
    RAISE EXCEPTION '0518 V3 PASSED: at 83%% against 85%% the step stays open; at 84%% it closes, stamped flow_contract_near_target at the tick''s clock';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0518 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0518 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore twin.ottoq_sim_advance_flow_contract from `0518_pre` (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0518_one_rule_for_whether_a_car_needs_its_charge', true,
  'G244: the flow contract closes a charge step at target - 1, the rule the need deriver and the charge cursor use, '
  'instead of target - 2, and stamps closed_by. It runs in every certified arm; a car in the old gap now keeps its step '
  'open until its session closes it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
