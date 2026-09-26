-- migration-version: 20260926132036
-- migration-name:    a_recalled_cars_charge_was_closed_on_the_soc_it_left_with_before_the_arrival_drain
--
-- 0483  **A recalled car's must-do charge was closed on the SoC it left with, before the arrival drain.**
--       `db/checks/0362` §9. FINDINGS G216 (and the intake-and-charge half of G210).
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run `3dbe16db` (busy_day, twin depot, sim 8:00 AM-12:57 PM): 56 charge atoms were closed, 17 of them by
--   this flow contract, and 11 of those 17 while the car was not at the depot: 10 while it was `en_route_to_depot`, all
--   `must_do`, all to a 90% target, and 1 while it was still `deployed`. The en-route cars read 87-96% when their charge
--   was closed and arrived at the gate at 44-54%, because the twin applies the trip's drain when the car reaches the
--   gate (`7ec698b8`: recalled at 8:08:45 reading 95%, charge closed at 8:09:27, arrived at 8:10:20 at 54%). The other
--   closers (`ottoq_satisfied` 35, `session_completed` 3) closed only cars at the depot.
--
--   Each of those cars then met the gate with its charge already done:
--     - the gate intake (`ottoq_decide_tick` (3b), no-charge arrivals) staged it `need_deploy` and recorded "no charge
--       needed", while the stall assignment (3), which charges any arrival below its target, sent the same car to the
--       charger its appointment had reserved, in the same tick. The door kept the intake and refused the charge. All
--       four intake-and-charge pairs of G210 on the run are these cars.
--     - the next tick (3)'s staged branch sent the car from staging to that same charger, so it charged after all,
--       one tick late, and the staging hold the intake booked stayed active while it charged (a source of G195).
--     - the visit records a charge completed before the car arrived.
--   The deploy SoC was not hurt: `7ec698b8` charged to 90% and deployed at 90% against an 80% floor, because (3) charges
--   by SoC and the deploy gate checks the floor. The cost is the detour, the leaked hold and a false record.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_flow_contract` closes a visit's open charge atom for every car that is not charging and
--   reads `current_soc >= target_soc - 2`. It does not ask where the car is. A recalled car's visit (with its must-do
--   charge, derived from the SoC it is predicted to arrive with) is opened while the car is `en_route_to_depot`, and
--   until the gate its `current_soc` is still the SoC it left with. So the first flow pass after the recall closes the
--   charge the recall was for.
--
--   `ottoq.ottoq_close_satisfied_charge_needs` has the same blind spot (it closes on `current_soc >= the visit's
--   target_soc`, in any state), but on this run all 6 of its closures were cars charging or staged for departure: the
--   recalled visits carry `target_soc` 100, above any en-route reading here. It is left as it is and named in G216.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The closure skips a car that is not at the depot: `offline`, `deployed`, `en_route_to_depot` or `tow_requested`.
--   Once the car is at the gate its SoC is the one it arrived with, and the closure runs as before. Nothing else in the
--   function moves: the late-leg amendment and the skip of deployed legs are untouched.
--
--   With the charge atom still open at the gate, the intake (3b) no longer takes the car, so (3) is the only section
--   that decides it: it goes to its charger if one is free, or to a hold through (3)'s own no-candidate branch.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The tick path: every world advance runs this function, and a canon column with a recall in it closes charge atoms
--   at a different tick.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0483 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamp with time zone)'::regprocedure))
     <> 'dabc0ee5446325ea0e6f9b23f4ca8377' THEN
    RAISE EXCEPTION '0483 P2: twin.ottoq_sim_advance_flow_contract is not the body this file patches';
  END IF;
  -- the gate intake still takes only arrivals whose charge atom is closed, so an open atom keeps the car in (3)
  IF position($x$WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))$x$
              IN pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0483 P2: the gate intake no longer reads the charge atom';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0483_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_flow_contract(uuid,timestamp with time zone)'::regprocedure;

DO $patch_closure$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamp with time zone)'::regprocedure);
  v_pat text := $p$(       AND v\.current_state NOT IN \('charging_dcfc','charging_l2'\)
)(       AND v\.current_soc >= )$p$;
  v_new text := $r$       AND v.current_state NOT IN ('charging_dcfc','charging_l2')
       -- 0483 (G216): a car still on its way in reads the SoC it left with, and the trip's drain lands at the gate.
       -- Closing on that reading closed the charge a recall was for (95% en route, 54% at the gate).
       AND v.current_state NOT IN ('offline','deployed','en_route_to_depot','tow_requested')
       AND v.current_soc >= $r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0483: the charge closure''s state filter matched % times, not once', n; END IF;
  EXECUTE regexp_replace(v_def, v_pat, v_new);
END $patch_closure$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamp with time zone)'::regprocedure);
BEGIN
  -- V1: the off-site filter sits once, in the charge closure's cursor (before the atom is marked done), and the
  -- late-leg cursor's filter is the one it was.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$AND v\.current_state NOT IN \('offline','deployed','en_route_to_depot','tow_requested'\)$x$, 'g')) <> 1
     OR position($x$NOT IN ('offline','deployed','en_route_to_depot','tow_requested')$x$ IN v_s)
        > position('ottoq_mark_visit_atoms_done' IN v_s)
     OR position($x$AND v.current_state NOT IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay')$x$ IN v_s) = 0 THEN
    RAISE EXCEPTION '0483 V1: the flow contract is not the body this file writes';
  END IF;
  -- V2: one overload, the ACL unchanged.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_flow_contract') <> 1 THEN
    RAISE EXCEPTION '0483 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_advance_flow_contract(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_advance_flow_contract(uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0483 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0483_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0483_a_recalled_cars_charge_was_closed_on_the_soc_it_left_with_before_the_arrival_drain', true,
  'Tick path: twin.ottoq_sim_advance_flow_contract no longer closes a charge atom for a car that is not at the depot '
  '(offline, deployed, en_route_to_depot, tow_requested). A recalled car keeps its charge until it arrives.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
