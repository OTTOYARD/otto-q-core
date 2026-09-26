-- 0357  **The bay fix held on a live run, and the same run showed three ways a waiting car is never moved.**
--
--       Validation run `317d4331-747a-4fd4-ab69-41ec78c5be98` (busy_day, twin depot `11111111-…`, speed 8x), started
--       through the twin cockpit's own Control tab (ottoyarddepot-sim#110: scenario picker -> Start -> 8x) at 04:14:11
--       UTC on 2026-09-26 (11:14 PM CT on 09-25), sim start 8:00 AM CT. Measured live between 04:16 and 04:45 UTC
--       (sim 8:18-11:35 AM CT). Engine: 0458 and 0459 (applied 03:32 UTC) and 0462 (04:08 UTC) live; recert 9/9 passed.
--
--       Every query takes the run as a psql variable and re-runs on any live run:
--
--           \set run '<sim_run_id>'
--
--       What each section answers:
--         §1  G191: did the bay door stop seating cars for no time (0458)?        yes
--         §2  G196: a completed charge below its visit's target never closed, and the car looped the service bay
--         §3  G196b: the deploy gate sends every kind of open work to the service bay
--         §4  G197: the command door drops the step a gate-intake command carries, and the car is stranded
--         §5  G195: bookings left active after the car departed (the departure sweep is off)
--         §6  the depot at 11:35 AM sim, and the five KPIs
--         §7  the Events feed (0462) and the three cockpits, live
--
--       This run is engine-class data and the next demo start purges it; the evidence ledgers do not hold these
--       rows. The numbers below are the record.

\set run '317d4331-747a-4fd4-ab69-41ec78c5be98'

-- ══ §1 G191 IS FIXED ON LIVE DATA (0458) ═════════════════════════════════════════════════════════════════════════

\echo '=== 0357 §1a — every bay visit that finished, by how it ended ==='
SELECT b.purpose, b.state, COALESCE(b.release_reason,'(none)') AS release_reason, count(*) AS n,
       count(DISTINCT b.vehicle_id) AS vehicles,
       round(avg(extract(epoch FROM (COALESCE(b.released_at, upper(b.during)) - lower(b.during))) / 60)::numeric, 2) AS avg_min,
       round(min(extract(epoch FROM (COALESCE(b.released_at, upper(b.during)) - lower(b.during))) / 60)::numeric, 2) AS min_min
  FROM public.ottoq_stall_bookings b
 WHERE b.sim_run_id = :'run' AND b.purpose IN ('wash','detail','service') AND b.state IN ('done','interrupted')
 GROUP BY 1,2,3 ORDER BY 1,2;
-- sim 11:33 AM CT: detail done 5 (avg 24.47 min, min 21.75), service done 4 (39.06, min 26.82), wash done 1 (10.28),
-- all `bay_exit_transition`. INTERRUPTED: 0. On 736406cf all 598 needs-card washes were `interrupted` at 0.95 min of 9.

\echo '=== 0357 §1b — the loop signatures ==='
SELECT e.event_type, count(*) AS n, count(DISTINCT e.entity_id) AS entities
  FROM public.ottoq_events e
 WHERE e.sim_run_id = :'run'
   AND e.event_type IN ('ottoq.booking_interrupted','ottoq.replan_escalated','ottoq.visit_reopened','sim_tick_failed')
 GROUP BY 1 ORDER BY 1;
-- sim 9:15 AM CT: no rows. 736406cf had 459 `replan_escalated` for one car.

\echo '=== 0357 §1c — a seated need is credited on exit ==='
SELECT e.payload->>'from' AS bay, e.payload->'credited' AS credited, count(*) AS n
  FROM public.ottoq_events e
 WHERE e.sim_run_id = :'run' AND e.event_type = 'twin.service_completed'
 GROUP BY 1,2 ORDER BY 1, n DESC;
-- Every wash and detail exit credited the need it was seated for (exterior_wash; interior_deep_clean) and none was a
-- null-timer exit (`self_healed` false throughout). The exits that credited nothing are all SERVICE BAY exits: §3.

-- ══ §2 G196: A CHARGE THAT COMPLETED BELOW ITS VISIT'S TARGET NEVER CLOSED ═══════════════════════════════════════

\echo '=== 0357 §2a — completed sessions against their visit target, and the atoms left open ==='
SELECT count(*) AS completed_sessions,
       count(*) FILTER (WHERE os.soc_end < COALESCE(vn.target_soc, v.target_soc, public.ottoq_default_target_soc())) AS ended_below_visit_target,
       count(*) FILTER (WHERE os.soc_end < COALESCE(vn.target_soc, v.target_soc, public.ottoq_default_target_soc()) AND s.stall_type = 'dcfc') AS of_which_dcfc,
       count(*) FILTER (WHERE os.soc_end < COALESCE(vn.target_soc, v.target_soc, public.ottoq_default_target_soc())
                          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','open') <> 'done')) AS atom_still_open
  FROM public.ocpp_sessions os
  JOIN public.vehicles v ON v.id = os.vehicle_id
  JOIN public.stalls s ON s.id = os.stall_id
  JOIN LATERAL (SELECT vn.* FROM public.ottoq_visit_needs vn
                 WHERE vn.sim_run_id = os.sim_run_id AND vn.vehicle_id = os.vehicle_id AND vn.arrived_at <= os.started_at
                 ORDER BY vn.arrived_at DESC LIMIT 1) vn ON true
 WHERE os.sim_run_id = :'run' AND os.stopped_reason = 'completed';
-- sim 10:05 AM CT: 16 completed / 4 below target / 4 DCFC / 1 atom still open (Waymo-006).
-- Waymo-006: DCFC-STALL-02, 19% -> 90%, `completed` at 8:35:31. Visit, vehicle and default targets all 100, so the atom
-- (`est_min` 96, must_do) stayed open. The flow itself had moved on (charge_complete_holding -> need_deploy).

\echo '=== 0357 §2b — Waymo-006 through the service bay ==='
SELECT to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago','HH24:MI:SS') AS sim_ct,
       (e.payload->'diff'->'current_state'->>'from') || ' -> ' || (e.payload->'diff'->'current_state'->>'to') AS transition,
       e.payload->'diff'->'config'->'to'->'deploy_gate'->>'reason' AS gate, e.payload->'diff'->'config'->'to'->'deploy_gate'->'missing' AS missing
  FROM public.ottoq_events e
 WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_state'
   AND e.entity_id = (SELECT id FROM public.vehicles WHERE display_name = 'Waymo-006' AND home_depot_id = '11111111-1111-1111-1111-111111111111')
 ORDER BY e.sim_clock_at, e.event_seq;
-- Seated in the service bay 8:46:28-9:19:31, again from 9:56:12, again from 11:13 AM: three seats by 11:35 AM, each
-- crediting nothing, each stamped `must_do_work_open` with `missing: [software_update]` (the needs card's list; the
-- atom holding the gate was the charge).
-- FIX: 0463 closes a charge atom when that visit's own session ended `completed` and none is open. Proven on a
-- rolled-back probe at sim 10:58 AM: the old closer closes 0 visits, the new one 2 (both `session_completed`), a second
-- call 0; Waymo-006's atom reads done / closed_soc 90 / closed_vs_target 100 / closed_session_ended_at 8:35:31.

-- ══ §3 G196b: THE DEPLOY GATE SENDS EVERY KIND OF OPEN WORK TO THE SERVICE BAY ═══════════════════════════════════

\echo '=== 0357 §3a — every service-bay seat, what the gate said, and what the bay could credit ==='
SELECT v.display_name, to_char(e.sim_clock_at AT TIME ZONE 'America/Chicago','HH24:MI') AS seated_ct,
       e.payload->'diff'->'config'->'to'->'deploy_gate'->>'reason' AS gate_reason,
       e.payload->'diff'->'config'->'to'->'deploy_gate'->'missing' AS gate_missing,
       (SELECT x.payload->'credited' FROM public.ottoq_events x
         WHERE x.sim_run_id = e.sim_run_id AND x.entity_id = e.entity_id AND x.event_type = 'twin.service_completed'
           AND x.payload->>'from' = 'in_service_bay' AND x.sim_clock_at > e.sim_clock_at
         ORDER BY x.sim_clock_at LIMIT 1) AS credited_on_exit
  FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id
 WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed'
   AND e.payload->'diff'->'current_state'->>'to' = 'in_service_bay'
 ORDER BY e.sim_clock_at;
-- sim 11:37 AM CT: 14 seats, 11 exited, 8 of the 11 credited NOTHING, on the depot's scarcest bay (2 stalls, ~40 min
-- a seat). The three that credited something did so for service-bay work (sensor_calibration, mechanical_pm x2).
-- The rest: a charge (Waymo-006 x3), detail and wash work (Tesla-RT-002 `interior_deep_clean`, Tesla-AV-042
-- `exterior_wash, interior_deep_clean`, Zoox-AV-077 and Waymo-AV-030 `missing: []` with interior_deep_clean open),
-- and two seats straight from boot.
-- CAUSE: `twin.ottoq_sim_advance_service_flow`'s deploy gate sets `v_remedy := need_service` whenever SoC is ready
-- and ANY must-do atom is open, whatever its lane, and `need_service` admits to the service bay only. Its
-- `missing` is the needs card's `must_do_now`, not the atoms that hold it, so two stamps read "must-do work open,
-- missing: nothing". `service_cadence_policy.lane` already says which work the service bay can do.

-- ══ §4 G197: THE COMMAND DOOR DROPS THE STEP, AND A GATE INTAKE IS NEVER MOVED AGAIN ═════════════════════════════

\echo '=== 0357 §4a — waiting cars with no step ==='
SELECT v.display_name, v.current_soc, to_char(v.last_state_change AT TIME ZONE 'America/Chicago','HH24:MI') AS since_ct,
       (SELECT string_agg(a->>'svc' || '=' || COALESCE(a->>'status','pending'), ',')
          FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
         WHERE vn.sim_run_id = :'run' AND vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
           AND COALESCE((a->>'must_do')::boolean,false)) AS must_atoms
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
   AND v.current_state = 'staged_awaiting_service' AND v.config->>'svc_step' IS NULL
 ORDER BY v.last_state_change;
-- sim 11:35 AM CT: 16 cars, 15 of them for over an hour, most since 8:31-8:46 AM, at 53-58% SoC against the 80%
-- ready floor, most with every must-do atom done and no open booking. Nothing in the service flow reads a car
-- with no step: every cursor keys on svc_step, the deploy gate on 'need_deploy'.

\echo '=== 0357 §4b — the gate intake asked for a step; the door never applied it ==='
SELECT c.command_type, c.payload ? 'svc_step' AS has_step, c.payload->>'svc_step' AS step, c.status::text AS status, count(*) AS n
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'proceed_to_stall' AND c.payload->>'new_state' = 'staged_awaiting_service'
 GROUP BY 1,2,3,4 ORDER BY n DESC;
-- `ottoq_decide_tick` (3b) stages a no-charge arrival with `svc_step: need_deploy` in the command (94 such commands,
-- 21 executed). `twin.ottoq_sim_confirm_commands` applies `new_state` (0039 completion) and never `svc_step`: its only
-- step write is 0458's bay contract. Of the run's 41 gate intakes, 0 had got back out by 11:35 AM sim.
-- The stranded sweeper (`twin.recharge_stranded`, a re-queue, per G87) requires an OPEN charge atom, and a gate-intake
-- visit was derived with none, so it never reaches them either.

-- ══ §5 G195: BOOKINGS LEFT ACTIVE AFTER THE CAR DEPARTED ═════════════════════════════════════════════════════════

\echo '=== 0357 §5 — active bookings whose car has left, and what the departure sweep would free ==='
WITH clk AS (SELECT ((public.ottoq_twin_snapshot(:'run'::uuid))->'run'->>'sim_clock')::timestamptz AS t)
SELECT s.stall_type, b.purpose, count(*) AS would_release,
       round(sum(extract(epoch FROM upper(b.during) - c.t) / 60)::numeric, 0) AS stall_minutes_freed,
       public.ottoq_policy_get(:'run'::uuid, 'space_departure_release_enabled', 0) AS dial_now
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
  JOIN public.vehicles v ON v.id = b.vehicle_id
 CROSS JOIN clk c
 WHERE b.sim_run_id = :'run' AND s.depot_id = '11111111-1111-1111-1111-111111111111'
   AND s.stall_type IN ('dcfc','l2','staging') AND b.state = 'active' AND b.during @> c.t
   AND v.current_stall_id IS NOT NULL AND v.current_stall_id <> b.stall_id
   AND s.current_vehicle_id IS DISTINCT FROM b.vehicle_id
   AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os WHERE os.sim_run_id = b.sim_run_id AND os.stall_id = b.stall_id
                                                         AND os.vehicle_id = b.vehicle_id AND os.ended_at IS NULL)
 GROUP BY 1,2 ORDER BY 1,2;
-- sim ~9:10 AM CT, dial 0: 1 DCFC (103 stall-min, Waymo-006's charger, while DCFC read 0 free), 1 L2 (9), 1 inspect
-- (3), 1 perimeter_hold (68), 10 temp_hold (213). The sweep exists (`ottoq_release_departed_spaces` sweep 1, two
-- witnesses plus no open OCPP session; 0330 records it fired harmlessly) and is off by default. Promote it through a
-- paired dial experiment, not mid-run. 11 vehicles held more than one active booking at that moment; the cockpits'
-- "N with two active stall reservations at once" is this, read from the other side.

-- ══ §6 THE DEPOT AT 11:35 AM SIM, AND THE FIVE KPIs ══════════════════════════════════════════════════════════════

\echo '=== 0357 §6a — where the fleet is ==='
SELECT v.current_state::text AS state, COALESCE(v.config->>'svc_step','(none)') AS step, count(*) AS vehicles,
       round(avg(v.current_soc)) AS avg_soc
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
 GROUP BY 1,2 ORDER BY vehicles DESC;
-- 11:35 AM CT: deployed 2, staged_awaiting_service 79 (about 40 waiting for a charger with L2 and DCFC ~90% occupied,
-- 16 with no step), the rest charging, at the gate, or in bays.

\echo '=== 0357 §6b — the five KPIs for this run ==='
SELECT public.ottoq_kpi_five(:'run'::uuid);
-- 11:35 AM CT: asset_hours 109.36 (2026-09-25), turns/point/day 2.37, peak_site_kw 883.2 (demand 982.3),
-- touch_events_per_turn 0.000, p50/p95 time to service 0.3 / 12.7 min, returns_unserved 7.

-- ══ §7 THE EVENTS FEED (0462) AND THE THREE COCKPITS, LIVE ═══════════════════════════════════════════════════════

\echo '=== 0357 §7 — the Events feed on the live run ==='
SELECT to_char(f.sim_at AT TIME ZONE 'America/Chicago','HH24:MI') AS sim_ct, f.event_type, f.severity, f.entity_name,
       f.repeats, f.standing, f.clipped
  FROM public.ottoq_run_event_feed(:'run'::uuid, 40, 120) f;
-- Sim time in CT, no audit rows, repeats collapsed into one standing row each (arrival forecast x114, staging
-- overflow x39 at 8:33 AM), names resolved. Reads measured on the live run: event feed 17 ms, decisions feed 31 ms,
-- depot cards 27-47 ms (206 KB), snapshot 52 ms (123 KB).
-- Cockpits (headless Chromium, 2D and 3D): the twin's Events, Intelligence and KPI tabs render the run; PULSE and
-- OrchestrAV (stacked PRs on Hermes's live-panel branches) word every decision with the twin's decisionText.ts on
-- their Overview, feed and vehicle cards. OrchestrAV fetches a 3D model from a `vehicle-renders` bucket that does not
-- exist on this project (HTTP 400, VehicleShowroom3D.tsx carries a TODO saying so); unrelated to the live panels.
