-- 0363  **Validation run after 0483-0484: a recalled car keeps its charge until it arrives, and a finished charge frees
--       its charger.**
--
--       One busy_day run on the twin depot (`11111111-…`), started from the twin cockpit's Control tab at 8x, with
--       0472-0484 in force: `461c79fa-6f85-467f-b90a-92b33d40728d`, seed 5753109525808485125, started 8:48:49 AM CT
--       (13:48:49 UTC), stopped from the cockpit at 9:10:44 AM CT after 324 ticks (sim 8:00 AM-10:54:57 AM). It followed
--       the recert sweep that passed 9 of 9 under 0483 and 0484 (verdicts 338-346). Every query takes the run as a psql
--       variable:
--
--           \set run '<sim_run_id>'
--
--       The predictions were written before the run was started. Results are recorded under each query.

-- ══ §1 G216 (0483): NO CHARGE CLOSED AWAY FROM THE DEPOT ═══════════════════════════════════════════════════════════

\echo '=== 0363 §1 — closed charge atoms by closer and by the car''s state when they closed ==='
WITH atoms AS (
  SELECT vn.vehicle_id, COALESCE((a->>'done_at')::timestamptz, (a->>'closed_at')::timestamptz) AS closed_at,
         COALESCE((a->>'must_do')::boolean, false) AS must_do, COALESCE(a->>'closed_by', 'flow_contract') AS closer
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'charge' AND a->>'status' = 'done')
SELECT closer,
       COALESCE((SELECT e.payload#>>'{diff,current_state,to}' FROM public.ottoq_events e
                  WHERE e.sim_run_id = :'run' AND e.entity_id = atoms.vehicle_id AND e.event_type = 'vehicle.state_changed'
                    AND e.payload#>'{diff,current_state}' IS NOT NULL AND e.sim_clock_at <= atoms.closed_at
                  ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1), '(none)') AS state_at_close,
       must_do, count(*) AS atoms
  FROM atoms GROUP BY 1, 2, 3 ORDER BY 4 DESC;
-- PREDICTED: no row with state_at_close en_route_to_depot, deployed, offline or tow_requested (10 en route and 1
-- deployed on 3dbe16db).
-- READ 461c79fa (whole run): 23 charge atoms closed, none while the car was en route, offline or tow_requested.
--   By closer: ottoq_satisfied 11, the flow contract 6 (the query's label for a closure with no closed_by),
--   session_completed 6. By state: charging_dcfc 6, staged_awaiting_service 7, staged_for_departure 6,
--   in_detail_bay 3, deployed 1.
-- The one `deployed` row is Waymo-AV-025's opportunistic top-up (must_do false), closed at sim 10:09:59 AM, the same
-- sim instant the car deployed from staged_for_departure: the closure and the deploy share a timestamp, and this query
-- takes the latest state at or before it. The state strictly before was staged_for_departure, so the car was at the
-- depot. 3dbe16db's one `deployed` row is the same thing (1225f10e at 11:53:40 AM); 0483's header and FINDINGS G216 are
-- corrected to say so. Verdict: 0483 holds. 0 of 23 closures were off-site, against 10 of 56 on 3dbe16db.

-- ══ §2 G216 at the gate: NO CAR TAKEN IN AS "NO CHARGE" WHILE THE CHARGE PATH SENDS IT TO A CHARGER ═════════════════

\echo '=== 0363 §2 — ticks in which one car got two stall commands, by the two commands ==='
WITH c AS (
  SELECT vc.vehicle_id, vc.issued_at, vc.status, vc.command_type, COALESCE(vc.payload->>'reason', '(none)') AS reason
    FROM public.ottoq_vehicle_commands vc
   WHERE vc.sim_run_id = :'run' AND vc.payload ? 'stall_id'),
multi AS (SELECT vehicle_id, issued_at, array_agg(command_type || ':' || reason || ':' || status ORDER BY command_type, reason, status) AS pair
            FROM c GROUP BY 1, 2 HAVING count(*) > 1)
SELECT pair, count(*) AS ticks FROM multi GROUP BY 1 ORDER BY 2 DESC;
-- PREDICTED: no {begin_charge, proceed_to_stall:gate_intake} pair (4 on 3dbe16db). A refusal and its reroute in one tick
-- may remain, and so may the appointment planner's double (G210).
-- READ 461c79fa (whole run): 4 ticks, one of each:
--   {begin_charge executed, begin_charge refused}      a refusal (target_occupied: the calendar held the stall for
--                                                       03726c33) and the door's reroute to another L2, one tick
--   {begin_charge refused, proceed_to_stall:gate_intake executed}   Waymo-AV-031 at sim 8:13:15 AM, see §4
--   {enter_wash:needs_card_detail refused, proceed_to_stall executed}
--   {stage executed, stage refused}
-- The intake-and-charge pair is NOT a G216 car: its visit had no charge atom at all, derived at 8:00 from the 97% the
-- car was carrying en route, and it reached the gate at 60%. That is §4's mechanism, the second cause of G210's pair.
-- 0483 removed the first (a charge closed en route); nothing yet removes the second.

-- ══ §3 G217 (0484): A FINISHED CHARGE FREES ITS CHARGER ═════════════════════════════════════════════════════════════

\echo '=== 0363 §3 — minutes each ended session''s charger stayed reserved by, and booked for, the car that had finished ==='
WITH sess AS (
  SELECT os.id, os.vehicle_id, os.stall_id, s.stall_type, os.ended_at, os.stopped_reason
    FROM public.ocpp_sessions os JOIN public.stalls s ON s.id = os.stall_id
   WHERE os.sim_run_id = :'run' AND os.ended_at IS NOT NULL),
res AS (
  SELECT e.entity_id AS stall_id, e.sim_clock_at, e.event_seq,
         e.payload#>>'{diff,reserved_by,from}' AS r_from, e.payload#>>'{diff,reserved_by,to}' AS r_to
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'stall.state_changed' AND e.payload#>'{diff,reserved_by}' IS NOT NULL
     AND e.entity_id IN (SELECT stall_id FROM sess)),
x AS (
  SELECT s.*,
         (SELECT r.r_to FROM res r WHERE r.stall_id = s.stall_id AND r.sim_clock_at <= s.ended_at
           ORDER BY r.sim_clock_at DESC, r.event_seq DESC LIMIT 1) = s.vehicle_id::text AS reserved_at_end,
         (SELECT min(r.sim_clock_at) FROM res r WHERE r.stall_id = s.stall_id AND r.sim_clock_at > s.ended_at
             AND r.r_from = s.vehicle_id::text) AS unreserved_at,
         (SELECT b.state || '/' || COALESCE(b.release_reason, '-') FROM public.ottoq_stall_bookings b
           WHERE b.sim_run_id = :'run' AND b.stall_id = s.stall_id AND b.vehicle_id = s.vehicle_id
             AND b.purpose IN ('charge_dcfc','charge_l2') AND lower(b.during) <= s.ended_at
           ORDER BY lower(b.during) DESC LIMIT 1) AS booking_after,
         (SELECT LEAST(COALESCE(b.released_at, upper(b.during)), upper(b.during))
            FROM public.ottoq_stall_bookings b
           WHERE b.sim_run_id = :'run' AND b.stall_id = s.stall_id AND b.vehicle_id = s.vehicle_id
             AND b.purpose IN ('charge_dcfc','charge_l2') AND lower(b.during) <= s.ended_at AND upper(b.during) > s.ended_at
           ORDER BY lower(b.during) DESC LIMIT 1) AS booking_end
    FROM sess s)
SELECT stall_type, split_part(stopped_reason, '.', 1) AS stop, count(*) AS sessions,
       count(*) FILTER (WHERE reserved_at_end) AS reserved_at_end,
       round(sum(EXTRACT(EPOCH FROM (unreserved_at - ended_at)) / 60) FILTER (WHERE reserved_at_end)) AS reserved_min_after,
       count(booking_end) AS booked_past_end,
       round(sum(GREATEST(0, EXTRACT(EPOCH FROM (booking_end - ended_at))) / 60), 1) AS booked_min_after,
       jsonb_object_agg(COALESCE(booking_after, 'none'), 1) AS booking_kinds
  FROM x GROUP BY 1, 2 ORDER BY 1, 2;
-- PREDICTED: reserved_at_end can stay counted (the reservation is cleared inside the same stop, after the session ends,
-- so the last reserved_by change at or before ended_at can still name the car), but reserved_min_after about 0, and
-- booked_min_after under a minute in total (a latched DCFC's 11.5 s demate). On 3dbe16db: 290 DCFC reserved-minutes and
-- 130 booked-minutes after the end, 16 and 75 on L2. Charge bookings end charge_session_completed / _faulted.
-- READ 461c79fa (whole run; the 33 `sim_reset` rows are the stop ending every open session and are left out):
--   stall  stop                           sessions  reserved_at_end  reserved_min  booked_past_end  booked_min
--   dcfc   completed                            20                0             -                7         1.3
--   dcfc   fault                                 1                0             -                0         0.0
--   l2     completed                             9                0             -                0         0.0
--   l2     fault                                 5                0             -                1        14.3
--   l2     vehicle_departed_orphan_sweep         2                2           134                2       133.5
-- DCFC: 0 reserved-minutes and 1.3 booked-minutes after 21 sessions, the demates of 7 latched plugs (0484's
-- `charge_session_completed`), against 290 and 130 on 3dbe16db. L2 completed and faulted: 0 reserved-minutes, and one
-- booking past its end, which is 0484's residual. Waymo-AV-029's session faulted 20 s after it started (sim 8:07:39 AM),
-- before the tick promoted its booking from held to active. 0484 closes only `active` bookings, so this `held` one
-- ran to its window: released window_elapsed at 8:22:10 AM, 14.3 minutes after the car left. One row in 35.
-- The two orphan-swept rows are not a leak. They are G220: `ottoq_reconcile_charger_states` stamps `ended_at = now()`,
-- the real clock (14:01:02 and 14:09:39 UTC). The exception handler had already trimmed and interrupted each booking
-- at the right sim moment: Zoox-AV-076 at 9:37:35 AM (swept 9:38:03), Waymo-AV-039 at 10:46:34 AM (swept 10:47:00).
-- This query's arithmetic against a real-clock `ended_at` produces the 134 minutes.
-- Also seen live, in PULSE at sim 10:17 AM: Zoox-AV-094 held two staging reservations (STG-E020, STG-E022) while it
-- was assigned L2-09. By 10:51 AM it held only L2-09 (one reservation, one active booking). This was transient and was
-- not traced.

-- ══ §4 G219: THE TWIN LANDS THE busy_day ARRIVAL DRAIN AT THE GATE ═════════════════════════════════════════════════
--
--   Found reading §2's one intake-and-charge pair on this run (Waymo-AV-031, sim 8:13:15 AM): its visit had no charge
--   atom at all. It was derived at 8:00 while the car was en route, from the 97% it was carrying, and the car reached
--   the gate at 60%. `twin.ottoq_sim_advance_deployed_telemetry` sets the gate SoC as
--       ottoq_apply_profile(run, 'soc_on_arrival', soc, soc) - ottoq_twin_arrival_soc_drain(run, clock)
--   and busy_day's variability template is `soc_on_arrival {shift -30, ceiling 78}` ("arrival SoC is shifted down so
--   charger demand is real"), with the climate drain about 3 points more. The catalog declares the knob applied in
--   `ottoq_sim_dispatch_vehicle`; it has been applied at the gate since the baseline (0009). So the whole shift lands
--   in one step at the gate, and every reading before it (deployed telemetry, the recall, the visit, the day plan's
--   EV forecast, the dispatch ledger) is about 33 points high.

\echo '=== 0363 §4a — the dispatch ledger''s SoC at return against the SoC the car reached the gate with ==='
SELECT count(*) AS completed_dispatches, round(avg(d.soc_at_return_pct)) AS avg_ledger_soc_at_return,
       round(avg(g.gate_soc)) AS avg_gate_soc, round(avg(d.soc_at_return_pct - g.gate_soc), 1) AS avg_gap,
       round(min(d.soc_at_return_pct - g.gate_soc), 1) AS min_gap, round(max(d.soc_at_return_pct - g.gate_soc), 1) AS max_gap
  FROM public.ottoq_vehicle_dispatches d
  CROSS JOIN LATERAL (SELECT (e.payload#>>'{diff,current_soc,to}')::numeric AS gate_soc FROM public.ottoq_events e
                        WHERE e.sim_run_id = d.sim_run_id AND e.entity_id = d.vehicle_id AND e.event_type = 'vehicle.state_changed'
                          AND e.payload#>>'{diff,current_state,to}' = 'arrived_at_gate' AND e.sim_clock_at = d.actual_return_at
                        LIMIT 1) g
 WHERE d.sim_run_id = :'run' AND d.status = 'completed';
-- READ 461c79fa at tick 140 (sim 9:09 AM): 47 completed dispatches, ledger 84% against gate 50%, gap 33.4 points
-- (32.9 to 33.8). Whole run: 88 dispatches, ledger 79% against gate 46%, gap 33.4 (32.9 to 33.8). The ceiling never binds at the gate (a car returning at 100 is shifted to 70). Contrast, same query
-- over the six latest cert_harness busy_day arms: 916 dispatches, gap 0.45 to 0.50 (the climate drain alone).

\echo '=== 0363 §4b — visits derived at the recall with no charge, against the SoC the car reached the gate with ==='
WITH r AS (SELECT sim_run_id, sim_clock_start, sim_clock_current FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
v AS (
  SELECT r.sim_run_id, r.sim_clock_current AS run_end, vn.vehicle_id, vn.target_soc,
         (vn.meta->>'soc_at_arrival')::numeric AS soc_meta, (vn.meta->>'sla_floor')::numeric AS floor,
         (SELECT e.sim_clock_at FROM public.ottoq_events e
           WHERE e.sim_run_id = r.sim_run_id AND e.entity_id = vn.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload#>>'{diff,current_state,to}' = 'arrived_at_gate' AND e.sim_clock_at >= vn.arrived_at
           ORDER BY e.sim_clock_at LIMIT 1) AS gate_at
    FROM r JOIN public.ottoq_visit_needs vn ON vn.sim_run_id = r.sim_run_id
   WHERE vn.arrived_at > r.sim_clock_start          -- opened at a recall, while the car was en route
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge')),
x AS (
  SELECT v.*,
         (SELECT (e.payload#>>'{diff,current_soc,to}')::numeric FROM public.ottoq_events e
           WHERE e.sim_run_id = v.sim_run_id AND e.entity_id = v.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload#>>'{diff,current_state,to}' = 'arrived_at_gate' AND e.sim_clock_at = v.gate_at LIMIT 1) AS gate_soc,
         EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc
                  WHERE vc.sim_run_id = v.sim_run_id AND vc.vehicle_id = v.vehicle_id AND vc.payload->>'reason' = 'gate_intake'
                    AND vc.status = 'executed' AND vc.issued_at >= v.gate_at) AS taken_in_as_no_charge,
         (SELECT min(os.started_at) FROM public.ocpp_sessions os
           WHERE os.sim_run_id = v.sim_run_id AND os.vehicle_id = v.vehicle_id AND os.started_at >= v.gate_at) AS first_charge_at
    FROM v WHERE gate_at IS NOT NULL)
SELECT count(*) AS no_charge_visits_met_gate, count(*) FILTER (WHERE gate_soc < target_soc) AS below_target,
       count(*) FILTER (WHERE gate_soc < floor) AS below_sla_floor, round(avg(soc_meta)) AS avg_soc_derived_from,
       round(avg(gate_soc)) AS avg_gate_soc, count(*) FILTER (WHERE taken_in_as_no_charge) AS taken_in_as_no_charge,
       count(*) FILTER (WHERE first_charge_at IS NOT NULL) AS charged_later,
       round(avg(EXTRACT(EPOCH FROM (first_charge_at - gate_at)) / 60)) AS avg_min_gate_to_charge
  FROM x;
-- READ 3dbe16db (whole run): 39 such visits met the gate, 39 below their target and 39 below the SLA floor; derived from
-- an average 90%, at the gate 46%. 33 were taken in by the gate intake as needing no charge. 16 charged before the stop
-- (a mean 16 minutes after the gate); the other 23 waited a mean 119 minutes to the stop, held by the deploy gate
-- (none deployed below the floor: the 8 that deployed left at 90%).
-- READ 461c79fa (whole run, sim 8:00-10:55 AM): 13 such visits met the gate. All 13 were below their target and below the
-- floor, derived from 89% and at the gate at 52%. 10 were taken in as needing no charge, and 9 charged a mean 17 minutes
-- after the gate.

\echo '=== 0363 §4c — which harnesses run busy_day with busy_day''s variability template (twin depot, last 3 days) ==='
SELECT r.scenario_code, r.run_by, vp.knobs->'soc_on_arrival' AS soc_on_arrival, vp.knobs->'_global' AS global, count(*) AS runs
  FROM public.ottoq_sim_runs r LEFT JOIN public.ottoq_variability_profiles vp ON vp.sim_run_id = r.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.started_at > now() - interval '3 days'
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2;
-- READ 2026-09-26 14:00 UTC: operator_demo busy_day 5 runs, all soc_on_arrival {shift -30, ceiling 78} and global
-- spread_mult 1.4; cert_harness busy_day 192, ab_harness busy_day 22 and cert_harness normal_day 18, all with no
-- profile row. `ottoq_variability_instantiate` has one caller, `ottoq_sim_run_scenario`, the operator's starter.
-- normal_day's template is empty, so it loses nothing. busy_day's is not: the canon certifies, and the dial
-- experiments learn on, a busy_day with no arrival shift and no widened spread, not the busy_day the operator runs.
-- The template's `_rates` are lost with it: dtc 7, incident 0.4, idle_fraction 1.9 and trip_duration 0.3, read through
-- `ottoq_profile_rate_mult`, which returns 1 for a run with no profile row. Its `arrival` 2 is read by no database
-- function: a comment-stripped search of every function finds 'arrival' only as a webhook and CRN stream name, and
-- no `ottoq_profile_rate_mult` call passes a variable. The otto-twin-control edge function does not read it either,
-- so the cockpit's "Arrival / dispatch rate +2.0x" moves nothing.
