-- 0387  **G244: the flow contract closed a visit's charge step on a looser rule than the one the need deriver and the
--       decide path's charge cursor use, so a car between the two rules had its charge closed as done and was sent to
--       charge anyway. 0518 makes the three one rule and makes the flow contract say who closed the step.**
--
--       Written on 2026-09-27 (06:40-07:50 UTC, 1:40-2:50 AM CT). Read-only.
--
--       The three places that answer "does this car need a charge" and their rule before 0518:
--         `ottoq.ottoq_derive_visit_needs`          a charge step when SoC < visit target - 1
--         `ottoq.ottoq_reassess_charge_needs`       re-derives it when SoC < target - 1
--         `public.ottoq_decide_tick`, charge cursor  books a charger when SoC < visit target - 1 (0493, G210)
--         `twin.ottoq_sim_advance_flow_contract`    closes the step when SoC >= step target - 2 (not charging, not en route)
--       A car in [target - 2, target - 1) has a step the deriver writes and the flow contract closes, and a charger the
--       cursor books regardless.

-- ══ §1 BEFORE: WHERE THE CAR STOOD WHEN THE FLOW CONTRACT CLOSED ITS STEP ═══════════════════════════════════════

\echo '=== 0387 §1 — flow-contract closes on the night''s operator runs, by SoC against the step''s target, and whether a charge followed ==='
-- SoC at the close is read from the signed event stream (the last `current_soc` a vehicle.state_changed event carried at
-- or before the close), since the flow contract stamped nothing on the step before 0518.
WITH ca AS (
  SELECT vn.sim_run_id, vn.vehicle_id, (x->>'target_soc')::numeric AS atom_tgt, vn.target_soc AS visit_tgt,
         (x->>'done_at')::timestamptz AS done_at
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id IN ('4bc19d29-790c-4cb0-9e2e-ae090a7da57b','caf85837-8681-4afe-9744-03eecd796737')
     AND x->>'svc' = 'charge' AND x->>'status' = 'done' AND NOT (x ? 'closed_by')),
s AS (
  SELECT ca.*,
         (SELECT (e.payload->'diff'->'current_soc'->>'to')::numeric
            FROM public.ottoq_events e
           WHERE e.sim_run_id = ca.sim_run_id AND e.entity_id = ca.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_soc' AND e.sim_clock_at <= ca.done_at
           ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS soc_at_close,
         EXISTS (SELECT 1 FROM public.ocpp_sessions os WHERE os.sim_run_id = ca.sim_run_id AND os.vehicle_id = ca.vehicle_id
                   AND os.started_at >= ca.done_at AND os.started_at < ca.done_at + interval '15 minutes') AS charge_after
    FROM ca)
SELECT left(sim_run_id::text, 8) AS run,
       CASE WHEN soc_at_close IS NULL THEN 'unknown'
            WHEN soc_at_close >= atom_tgt THEN 'at or above target'
            WHEN soc_at_close >= atom_tgt - 1 THEN '[target-1, target)'
            WHEN soc_at_close >= atom_tgt - 2 THEN '[target-2, target-1)'
            ELSE 'below target-2' END AS soc_vs_step_target,
       count(*) AS closes, count(*) FILTER (WHERE charge_after) AS charge_within_15_min
  FROM s GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 07:45 UTC, both runs stopped; 4bc19d29 by the run governor at sim 5:02 PM):
--     4bc19d29  at or above target     33 closes   0 charged within 15 minutes
--               [target-1, target)      2          0
--               [target-2, target-1)    3          2
--     caf85837  at or above target     13          0
--               [target-2, target-1)    3          2
--   54 flow-contract closes on the night's two operator runs. Every close followed by a charge (4) was in the gap
--   [target - 2, target - 1), where the deriver and the cursor call a charge needed and the flow contract called it
--   done, and no close outside the gap was followed by one. 0518 changes exactly the 6 in the gap and nothing else.

\echo '=== 0387 §1(b) — the cars in the gap ==='
WITH ca AS (
  SELECT vn.sim_run_id, vn.visit_id, vn.vehicle_id, (x->>'target_soc')::numeric AS atom_tgt, vn.target_soc AS visit_tgt,
         (x->>'done_at')::timestamptz AS done_at, vn.urgency
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id IN ('4bc19d29-790c-4cb0-9e2e-ae090a7da57b','caf85837-8681-4afe-9744-03eecd796737')
     AND x->>'svc' = 'charge' AND x->>'status' = 'done' AND NOT (x ? 'closed_by')),
s AS (
  SELECT ca.*,
         (SELECT (e.payload->'diff'->'current_soc'->>'to')::numeric
            FROM public.ottoq_events e
           WHERE e.sim_run_id = ca.sim_run_id AND e.entity_id = ca.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff' ? 'current_soc' AND e.sim_clock_at <= ca.done_at
           ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS soc_at_close,
         (SELECT min(os.started_at) FROM public.ocpp_sessions os WHERE os.sim_run_id = ca.sim_run_id
             AND os.vehicle_id = ca.vehicle_id AND os.started_at >= ca.done_at) AS next_charge
    FROM ca)
SELECT left(s.sim_run_id::text, 8) AS run, v.display_name AS car, s.urgency, s.atom_tgt, s.soc_at_close,
       to_char(s.done_at AT TIME ZONE 'America/Chicago', 'HH24:MI:SS') AS closed_ct,
       to_char(s.next_charge AT TIME ZONE 'America/Chicago', 'HH24:MI:SS') AS next_charge_ct
  FROM s JOIN public.vehicles v ON v.id = s.vehicle_id
 WHERE s.soc_at_close >= s.atom_tgt - 2 AND s.soc_at_close < s.atom_tgt - 1
 ORDER BY 1, s.done_at;
-- READ (2026-09-27 07:45 UTC):
--     4bc19d29  Zoox-AV-099   standard            90  88  closed 08:11:30  charged 08:12:18
--     4bc19d29  Waymo-AV-034  immediate_dispatch  85  83  closed 08:23:48  charged 08:24:25
--     4bc19d29  Waymo-AV-037  standard            90  88  closed 13:47:51  charged 15:09:20
--     caf85837  Zoox-AV-072   standard            90  88  closed 08:05:22  charged 08:06:12
--     caf85837  Zoox-AV-076   immediate_dispatch  85  83  closed 08:45:09  charged 08:46:01
--     caf85837  Waymo-AV-029  standard           100  98  closed 09:51:16  (no later charge; the run stopped at 11:14)
--   Four plugged in under a minute after the close (37 to 52 seconds; 0377 §1 has the cursor booking 072 and 076 22 and
--   24 seconds after it). The other two sat: Waymo-AV-037 charged 81 minutes later, and Waymo-AV-029's 98% was a charge cut by a fault
--   (fault.communication_dropout at 9:50:51) with its visit asking for 100. Under 0518 all six keep the step open: the
--   four are charged as they were, now with the visit saying so, and the two are held with an open charge step, which
--   the deploy gate routes to `need_charge` (0464), not the service bay.

\echo '=== 0387 §1(c) — does the step''s own target agree with its visit''s? (the other way the two rules could part) ==='
-- The flow contract judges the step's `target_soc`, the cursor the visit's. They are written equal by the deriver but
-- can differ afterwards; if a close with the step below its visit's target were followed by a charge, one rule on the
-- offset would not be enough.
WITH ca AS (
  SELECT vn.sim_run_id, vn.vehicle_id, vn.target_soc AS visit_tgt, (x->>'target_soc')::numeric AS atom_tgt,
         (x->>'done_at')::timestamptz AS done_at, x->>'closed_by' AS closed_by
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
   WHERE vn.sim_run_id IN ('4bc19d29-790c-4cb0-9e2e-ae090a7da57b','caf85837-8681-4afe-9744-03eecd796737')
     AND x->>'svc' = 'charge' AND x->>'status' = 'done')
SELECT left(sim_run_id::text, 8) AS run, COALESCE(closed_by, '(flow contract)') AS closed_by,
       CASE WHEN atom_tgt = visit_tgt THEN 'step = visit' WHEN atom_tgt < visit_tgt THEN 'step < visit' ELSE 'step > visit' END AS targets,
       count(*) AS closed,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ocpp_sessions os
                                       WHERE os.sim_run_id = ca.sim_run_id AND os.vehicle_id = ca.vehicle_id
                                         AND os.started_at >= COALESCE(ca.done_at, 'infinity')
                                         AND os.started_at < ca.done_at + interval '15 minutes')) AS charge_after
  FROM ca GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (2026-09-27 07:45 UTC):
--     4bc19d29  (flow contract)   step < visit   1 closed   0 charged after
--                                 step = visit  37          2
--               ottoq_satisfied   step = visit  59          0
--                                 step > visit  37          0
--     caf85837  (flow contract)   step < visit   7          0
--                                 step = visit   9          2
--               ottoq_satisfied   step = visit  21          0
--                                 step > visit  13          0
--               session_completed step < visit   5          0
--                                 step = visit   1          0
--   The step's target differs from its visit's on 8 flow-contract closes (always the step lower, 90 against 100) and
--   none of those was followed by a charge; all four re-charges were steps whose target equals the visit's. So one rule
--   on the offset is the whole of G244 as observed. The other way the two rules could part -- the flow contract judging
--   the step's target, the cursor the visit's -- is real in the data (8 of 54 flow-contract closes) and has not yet
--   produced a charge; noted, not fixed.

-- ══ §2 0518 AS APPLIED ══════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0387 §2 — 0518 in the migration ledger and the flow contract it left ==='
SELECT m.version, md5(m.statements[1]) AS body_md5,
       md5(pg_get_functiondef('twin.ottoq_sim_advance_flow_contract(uuid,timestamptz)'::regprocedure)) AS flow_contract_md5,
       (SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0518_pre') AS pre_snapshots,
       (SELECT forces_recert FROM public.ottoq_cert_lineage WHERE name = '0518_one_rule_for_whether_a_car_needs_its_charge') AS forces_recert
  FROM supabase_migrations.schema_migrations m WHERE m.name = 'one_rule_for_whether_a_car_needs_its_charge';
-- READ (2026-09-27 07:43 UTC): version 20260927074142 (2:41 AM CT), body md5 2c2c260741a792908bc006ca652b47ac, the
--   file's body byte for byte; the flow contract after, 0ffac01e7e17102c01107d385b1f427d (before, 6b7467f26ff6a125ab8f8db6525d7424,
--   kept as `0518_pre`); forces_recert TRUE. Applied with no run live and no rig in flight, 54 seconds before 0519 so
--   one sweep reads both. V3 passed in the dry run and the apply, on 4bc19d29 marked running inside the test: a car
--   planted at the gate at 83% against a step targeting 85 kept its step; at 84% the step closed, stamped
--   `flow_contract_near_target` with `closed_soc` 84, `closed_vs_target` 85, and the tick's clock as both `closed_at`
--   and `done_at`.
--   Two things the review before the dry run changed: P2 now checks the exact expression in each of the three places
--   that ask the question (the first draft accepted any "- 1" in the reassessment's source), and the stamp carries the
--   SoC and target as well as the closer, so the next audit of G244's shape reads the step instead of rebuilding the
--   SoC from the signed event stream, which is what §1 had to do.

-- ══ §3 THE SWEEP ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0518 and 0519 move the recert floor together (both forces_recert TRUE).

\echo '=== 0387 §3 — the verdicts since 0518, and which digests each column moved against its last verdict before ==='
WITH v AS (
  SELECT l.verdict_id, l.scenario, l.seed, l.ticks, l.outcome, l.engine_hash, l.verdict->'arm_a' AS a,
         row_number() OVER (PARTITION BY l.scenario, l.seed, l.ticks ORDER BY l.verdict_id DESC) AS rn
    FROM public.ottoq_determinism_verdict_ledger l
   WHERE l.outcome = 'passed' AND l.verdict_id BETWEEN 457 AND 485 AND jsonb_typeof(l.verdict->'arm_a') = 'object')
SELECT c.scenario, c.seed, c.ticks, c.verdict_id AS now_v, left(c.engine_hash, 8) AS engine, p.verdict_id AS before_v,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(c.a) k
         WHERE k LIKE 'h\_%' AND c.a->>k IS DISTINCT FROM p.a->>k) AS moved_digests
  FROM v c LEFT JOIN v p ON (p.scenario, p.seed, p.ticks) = (c.scenario, c.seed, c.ticks) AND p.rn = 2
 WHERE c.rn = 1 ORDER BY c.ticks, c.scenario, c.seed;
-- READ (2026-09-27 08:15 UTC, 3:15 AM CT): all nine columns passed on the first attempt, verdicts 476-485 between 2:42
--   and 3:02:44 AM CT, every one equal and complete with no disagreeing atom. 476 (grid_smoke/239001/6) ran between the
--   two applies, on engine 45cebd01, and its column was certified again as 477 on engine 1f067bbf, which carries both;
--   477-485 are all on 1f067bbf. Nothing certified is wrong. What the digests say:
--     grid_smoke 239001/6 and 424242/6   moved nothing but h_cal
--     busy_day 171717/48 (against 475)   h_bkg h_cmd h_dec h_evt h_nrg h_prop h_rcl h_rule h_sdr -- 9 of 11
--     the other busy and normal columns  7-10 digests, h_cal among them
--   h_cal moved because the weekly refit's new priors landed between 474 and 475 (G243): every column last certified
--   before 475 moved it for that reason, not for these migrations. So the 48-tick column is the clean reading -- its
--   last verdict was already on the new priors -- and there the two rules moved 9 of 11 digests, which is what
--   forces_recert TRUE is for: a full day's bookings, commands, decisions and records are not what they were. The
--   6-tick smoke columns moved nothing of their own: in three sim-hours no car sat in the gap and no charger faulted
--   under the sensors. The other columns' movement mixes the new priors with the change and is not attributed.

-- ══ §4 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) no charge step is closed by the flow contract with the car under
--   `target - 1`: every one it closes carries `closed_by = 'flow_contract_near_target'` and a `closed_soc` at or above
--   `closed_vs_target - 1`; (b) no flow-contract close is followed by a charge within 15 minutes (4 of 54 before);
--   (c) cars in the old gap keep an open charge step until their charge's stop closes it (`ottoq_satisfied` or
--   `session_completed`); (d) with the step open, 0511's hold keeps their cabin work for the charger: no interior
--   inspection starts at the gate on a visit whose charge step is open (G244's 076 and 072); (e) not predicted, read:
--   deploy-gate overrides (`twin.deploy_gate_override`) against the night's runs, since two cars a run now wait for a
--   top-up they used to skip.
