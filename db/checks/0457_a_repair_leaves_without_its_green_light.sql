-- 0457  **A fault repair's technician green-light is required by one dispatch door, asked for by nothing, and skipped
--        by the other doors, so a repaired car leaves without one.** -> G467, fixed under a dial by db/migrations/0753.
--        Found while reading who answers a green-light in production (G465). §1-§4 read-only, against
--        gxdrcyphqjzjsuhxuqtg, 2026-10-18 between 1:03 and 1:30 AM CT (06:03 and 06:30 UTC), bounded by clock reads,
--        inside the sweep window (catalog reads and one small table read). §5 counts the cars on the twin depot's runs,
--        read after the window closed, at 7:04 AM CT on 2026-10-18. Every claim names its query.
--
-- ══ §1 THE REQUIREMENT (reproduce: (1)) ═══════════════════════════════════════════════════════════════════════════════
--
--   Two functions write requires_tech_greenlight true on an atom, (1): ottoq.ottoq_derive_visit_needs, on every
--   fault_repair it derives ('must_do' true, 'deferrable' false, a service-bay atom), and
--   twin.ottoq_sim_advance_visit_atoms, on the cosmetic_repair a triaged cosmetic flag escalates to. Both are bay work,
--   done in the service bay and credited at its exit by STEP 1 of the service flow.
--
-- ══ §2 WHO WAITS FOR IT (reproduce: (2), (4)) ═════════════════════════════════════════════════════════════════════════
--
--   Three functions read the flag, (2). ottoq.ottoq_arrival_disposition stages a flagged arrival on a technician hold; it
--   is not a departure door. public.ottoq_decide_tick's redeployment cursor holds a car in staged_for_departure whose
--   open visit carries such an atom until a tech_greenlight approval, approved and created since the visit opened,
--   exists. twin.ottoq_sim_advance_visit_atoms raises a green-light after a timed completion of work done in place, in
--   its sim-only branch; no green-light atom is work done in place, so it never raises one for a repair.
--   Every other door tests public.ottoq_departure_clear (md5 ac79f1b4), the one departure test 0543 made rule 9's, and
--   none of it, nor any of them, names a green-light, (4): ottoq.ottoq_plan_dispatch_tick (the deploy planner, whose
--   release list twin.ottoq_sim_auto_dispatch_tick departs), twin.ottoq_sim_dispatch_vehicle (the twin's dispatcher),
--   public.ottoq_refuse_unfinished_departure (0544, the trigger that refuses a dispatch row), the departure recheck and
--   the v2 operator door's departure report.
--
-- ══ §3 WHO ASKS FOR IT (reproduce: (3)) ═══════════════════════════════════════════════════════════════════════════════
--
--   Nothing, after a bay repair. ottoq.ottoq_stage_advance_approval inserts a tech_greenlight and has no caller in the
--   database, (3). The ops approvals table held 25,564 indepot_reassign questions, 1 opportunistic_charge and no
--   tech_greenlight at all when read at 1:30 AM CT.
--
-- ══ §4 WHAT FOLLOWS ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The decide's door can never let a repaired car go, since nothing it waits for is ever written; the planner's door,
--   which does not wait, always does. So the requirement the derive writes on every repair is not enforced anywhere: a
--   car leaves its repair with no technician having signed it off. In production that is a car back on the road after
--   a fault repair nobody green-lit; in the twin, every fault-repaired car has left this way. Rule 9 is about work open
--   on the car; the repair is done, so the departure test is right by its own terms. What is missing is the sign-off the
--   plan itself asks for.
--
-- ══ §5 THE CARS (after the window; reproduce: (5)) ══════════════════════════════════════════════════════════════════
--
--   Counted 2026-10-18 at 7:04 AM CT (12:04:25 UTC by the query's clock), after the window, (5): the twin depot's 24
--   completed runs since 2026-10-16 derived 106 fault repairs, 103 of them carrying requires_tech_greenlight; 54 were
--   done, every one of them flagged.
--                       runs with a repair   repairs done   left after it   by the decide's door   by the planner   still in
--     busy day                   6                32              32                  0                  32            0
--     normal day                17                22              20                  0                  20            2
--   The 52 that left did so a median 36 minutes after the repair (busy day 9, normal day 270; 5 to 445), and not one had
--   a tech_greenlight approved since its visit opened: the ops approvals table holds no tech_greenlight at all, on any
--   run. So every repaired car in the twin left by the deploy planner's release, the door that does not wait, and none by
--   the decide's, the door that waits for a green-light nothing writes (§4). The door was read as an enacted redeployment
--   'deploy' for the car in the tick it left (4,316 of the runs' 5,614 dispatches have one; none of the 52 does).
--   And rule 9 held: the 52 repairs not done (46 never started, 3 open, 3 pending without the flag) are all in visits
--   superseded at their run's end, and none of those cars left during the visit.
--
-- ══ §6 THE FIX (0753) ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Dial repair_needs_its_green_light (default 0). A repair that needs a green-light asks for one when it is done (a
--   trigger on the visit's atoms, so every door that marks it done asks: the bay exit and the production seam alike);
--   the one departure test holds the car until one approved since its visit opened exists, so every door holds it
--   alike; a declined green-light re-opens the repair. At a twin-fed depot the twin's technician answers on its own
--   delay and draw; at a real one a person does (0751). Executed on the scratch PostgreSQL against the live departure
--   test, atom marker and scan (tests/test_repair_green_light_sql.py, 8 tests).
--   APPLIED 2026-10-18 at 6:27 AM CT (ledger 20261018112725), after its dry run on live at 6:26, whose V3 put a probe run
--   at the twin depot inside a block rolled back by its own raise. Its arms are repairgl_busy_2026_10_18: a new in-tick
--   control, dcfc10.otto_q.answer_in_tick on the busy day, and the repair cell against it (db/checks/0451 §15), in the
--   window that opens at 11:00 PM CT on 2026-10-20 by 0451 §15's schedule. They read what §5 counts, with the dial:
--   every repaired car held until its technician answers, by whichever door, and the minutes that costs.

-- (1) who writes the requirement
SELECT n.nspname || '.' || p.proname AS fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ $$'requires_tech_greenlight',\s*true$$
 ORDER BY 1;

-- (2) who reads it, and whether each also tests the one departure test
SELECT n.nspname || '.' || p.proname AS fn, p.prosrc ~ 'ottoq_departure_clear' AS tests_departure_clear
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ $$requires_tech_greenlight'\)::boolean$$
 ORDER BY 1;

-- (3) who asks, and what the table holds
SELECT 'callers of ottoq_stage_advance_approval' AS k, count(*)::text AS v
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_stage_advance_approval'
   AND p.proname <> 'ottoq_stage_advance_approval'
UNION ALL
SELECT 'approvals: ' || approval_type, count(*)::text FROM public.ottoq_ops_approvals GROUP BY approval_type;

-- (4) the departure test's callers, and whether any names a green-light
SELECT n.nspname || '.' || p.proname AS fn, p.prosrc ~ 'tech_greenlight' AS names_a_green_light
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_departure_clear\('
   AND p.proname <> 'ottoq_departure_clear'
 ORDER BY 1;

-- (5) the cars (G467): each fault repair done on the twin depot's completed runs since 2026-10-16, the car's next
--     departure after it, the door it left by (an enacted redeployment deploy for the car in that tick, else the deploy
--     planner's release), how long after the repair it left, and whether a tech_greenlight approved since its visit
--     opened existed. Window functions and joins only; run after the sweep window.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND status = 'completed'),
ev AS (
  SELECT vn.sim_run_id, vn.vehicle_id, 'repair'::text AS kind, 0 AS ko, (a->>'done_at')::timestamptz AS t, vn.visit_id, vn.arrived_at AS opened_at
    FROM ottoq_visit_needs vn JOIN runs USING (sim_run_id), jsonb_array_elements(vn.atoms) a
   WHERE a->>'svc' = 'fault_repair' AND a->>'status' = 'done'
  UNION ALL
  SELECT d.sim_run_id, d.vehicle_id, 'dispatch', 1, d.dispatched_at, NULL::uuid, NULL::timestamptz
    FROM ottoq_vehicle_dispatches d JOIN runs USING (sim_run_id)),
rp AS (
  SELECT * FROM (
    SELECT ev.*, min(t) FILTER (WHERE kind = 'dispatch')
                   OVER (PARTITION BY sim_run_id, vehicle_id ORDER BY t, ko ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS left_at
      FROM ev) x
   WHERE kind = 'repair'),
dep AS (SELECT dc.sim_run_id, (dc.proposed_action->>'vehicle_id')::uuid AS vehicle_id, (dc.context_frame->>'now_ts')::timestamptz AS tick
          FROM ottoq_decisions dc JOIN runs USING (sim_run_id)
         WHERE dc.action_context = 'redeployment' AND dc.outcome_status = 'enacted' AND dc.proposed_action->>'verb' = 'deploy'),
gl AS (SELECT o.sim_run_id, o.vehicle_id, o.requested_at FROM public.ottoq_ops_approvals o JOIN runs USING (sim_run_id)
        WHERE o.approval_type = 'tech_greenlight' AND o.status = 'approved'),
j AS (
  SELECT rp.sim_run_id, rp.vehicle_id, rp.visit_id, rp.t, rp.left_at, r.scenario_code,
         count(dep.tick) > 0 AS by_decide, count(gl.requested_at) > 0 AS green_lit
    FROM rp JOIN runs r USING (sim_run_id)
    LEFT JOIN dep ON dep.sim_run_id = rp.sim_run_id AND dep.vehicle_id = rp.vehicle_id
                 AND dep.tick BETWEEN rp.left_at - interval '5 minutes' AND rp.left_at
    LEFT JOIN gl ON gl.sim_run_id = rp.sim_run_id AND gl.vehicle_id = rp.vehicle_id AND gl.requested_at >= rp.opened_at
   GROUP BY 1, 2, 3, 4, 5, 6)
SELECT scenario_code, count(DISTINCT sim_run_id) AS runs_with_repairs, count(*) AS repairs_done, count(left_at) AS left_after_repair,
       count(*) FILTER (WHERE left_at IS NOT NULL AND by_decide) AS by_decide_door,
       count(*) FILTER (WHERE left_at IS NOT NULL AND NOT by_decide) AS by_planner_release,
       count(*) FILTER (WHERE left_at IS NULL) AS still_in_depot_at_run_end,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM left_at - t) / 60)::numeric, 0) AS left_after_median_min,
       round(min(extract(epoch FROM left_at - t) / 60)::numeric, 0) AS left_after_min_min,
       round(max(extract(epoch FROM left_at - t) / 60)::numeric, 0) AS left_after_max_min,
       count(*) FILTER (WHERE left_at IS NOT NULL AND green_lit) AS left_with_greenlight
  FROM j GROUP BY ROLLUP (scenario_code) ORDER BY 1 NULLS LAST;
