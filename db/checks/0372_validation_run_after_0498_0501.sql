-- 0372  **Validation run after 0498-0501: each fix's prediction, read live.**
--
--       One busy_day run on the twin depot (`11111111-…`), started from the twin cockpit's Control tab at 8x, with
--       0498-0501 in force and the canon re-certified under them first. Every query takes the run as a psql variable:
--
--           \set run '<sim_run_id>'
--
--       The predictions were written, and committed, before the run was started. Results are recorded under each
--       query. BEFORE is validation run `394e1e83` (0486-0494 in force, 0495-0497 applied after its stop), read in 0368,
--       0369 and here (§5) before this run's start purged it. §2(b) and §5 were added from what the canon under 0500
--       (0370 §3) and a second look at G232 showed, also before the start.

-- ══ §1 G229 (0498, 0499): NO CHARGE REFUSED FOR A PROMISED CHARGER ═══════════════════════════════════════════════
--
--   PREDICTED: no `begin_charge` of the charge step's own is refused at the gate, from any proposer. Under 0494 the
--   per-car proposer asks the gate, under 0495 the greedy optimizer does, and under 0498-0499 CP-SAT's frame and the
--   selector do, so every source of the 24 refusals on 394e1e83 now asks the gate's question first.

\echo '=== 0372 §1(a) — refused begin_charge of the charge step''s own, by the proposal it came from ==='
SELECT COALESCE(src.engine, '(no matching decision)') AS engine, count(*) AS refused
  FROM public.ottoq_vehicle_commands c
  LEFT JOIN LATERAL (
    SELECT COALESCE(d.proposed_action->>'l2_engine', d.proposed_action->'rationale'->>'optimizer', 'per_car_proposer') AS engine
      FROM public.ottoq_decisions d
     WHERE d.sim_run_id = c.sim_run_id AND d.entity_id = c.vehicle_id AND d.sim_clock = c.issued_at
       AND d.resolved_action_context = 'stall_assignment' AND d.proposed_action->>'stall_id' = c.payload->>'stall_id'
     LIMIT 1) src ON true
 WHERE c.sim_run_id = :'run' AND c.command_type = 'begin_charge' AND c.status = 'refused'
   AND c.confirmed_by = 'otto_q_preflight' AND NOT (c.payload ? 'reroute_reason')
 GROUP BY 1 ORDER BY 2 DESC;
-- BEFORE 394e1e83: greedy_constrained 21, forward_lex 3, per-car 0 (24 of 119).
-- READ: pending.

\echo '=== 0372 §1(b) — the frame''s calendar fact, over the run''s snapshots ==='
SELECT count(*) AS snapshots,
       count(*) FILTER (WHERE s.frame->'selector'->>'facts_version' = '4') AS facts_v4,
       max((SELECT count(*) FROM jsonb_array_elements(s.frame->'stalls') st WHERE st->>'calendar_held_by' IS NOT NULL)) AS max_calendar_held,
       max((SELECT count(*) FROM jsonb_array_elements(s.frame->'stalls') st
             WHERE st->>'calendar_held_by' IS NOT NULL AND st->>'vehicle_id' IS NULL AND st->>'type' IN ('dcfc','l2'))) AS max_promised_empty_chargers
  FROM public.ottoq_decision_snapshots s WHERE s.sim_run_id = :'run';
-- PREDICTED: every snapshot at facts_version 4, and at busy times chargers the calendar holds while their pointer is
--   empty (the case 0498 stops CP-SAT offering).
-- READ: pending.

\echo '=== 0372 §1(c) — CP-SAT''s proposals on the run, by how they were disposed ==='
SELECT p.status, COALESCE(p.disposition_reason, '-') AS reason, count(*)
  FROM public.ottoq_external_proposals p
 WHERE p.sim_run_id = :'run' AND p.source = 'forward_lex' AND p.action_context = 'stall_assignment'
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- BEFORE 394e1e83: refused / proposer_abstained 119, superseded / entity_decided_by_other_proposal 24, refused /
--   stall_occupied 8, refused / stall_reserved 8. (The 3 gate refusals of §1(a) are commands, not proposal statuses.)
-- PREDICTED: none of CP-SAT's proposals is for a charger another car's live booking covers, since 0498 marks those
--   not offerable in the frame it plans on, so none reaches the gate to be refused there (that is §1(a)). How the rest
--   are disposed is read here, not predicted.
-- READ: pending.

-- ══ §2 G228 (0500): A PARKED CAR KEEPS ITS HOLD ═══════════════════════════════════════════════════════════════════
--
--   PREDICTED: at every live reading, every car waiting at the gate (`arrived_at_gate`) and parked in staging is on the
--   calendar (0370 §1), except a car whose renewal would have overlapped another booking on its stall. Rows for other
--   states are context: a car staged for departure or holding after its charge sits on a booking of another purpose,
--   which 0500 does not renew.

\echo '=== 0372 §2 — cars parked in staging by state, and how many a live booking of their own covers (read live) ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
p AS (
  SELECT v.id, v.current_state::text AS st, s.id AS stall
    FROM public.vehicles v
    JOIN public.stalls s ON s.id = v.current_stall_id AND s.current_vehicle_id = v.id
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'staging')
SELECT p.st, count(*) AS parked,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_stall_bookings b, r
          WHERE b.sim_run_id = r.run AND b.stall_id = p.stall AND b.vehicle_id = p.id
            AND b.state IN ('held','active') AND b.during @> r.t)) AS on_the_calendar
  FROM p GROUP BY 1 ORDER BY 2 DESC;
-- BEFORE 394e1e83: at sim 10:37 AM 42 cars at the gate parked in staging, 4 on the calendar; at 11:50 AM 35, 2.
-- READ: pending.

\echo '=== 0372 §2(b) — the other side of the renewal: parking holds still live on a staging stall their car has left ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run')
SELECT b.purpose, count(*) AS holds_after_departure,
       round(sum(EXTRACT(epoch FROM upper(b.during) - r.t) / 60)::numeric) AS stall_minutes_left,
       round(max(EXTRACT(epoch FROM upper(b.during) - r.t) / 60)::numeric, 1) AS max_minutes_left
  FROM public.ottoq_stall_bookings b
  JOIN r ON b.sim_run_id = r.run
  JOIN public.stalls s ON s.id = b.stall_id AND s.stall_type::text = 'staging'
  JOIN public.vehicles v ON v.id = b.vehicle_id
 WHERE b.state = 'active' AND b.purpose IN ('temp_hold','perimeter_hold') AND b.during @> r.t
   AND s.current_vehicle_id IS DISTINCT FROM b.vehicle_id AND v.current_stall_id IS DISTINCT FROM b.stall_id
 GROUP BY 1 ORDER BY 1;
-- WHY: 0500 moves the calendar's error rather than removing all of it. A renewed hold covers the clock plus 15
--   minutes, and nothing ends it when its car leaves (the reservation reclaimer's orphan class skips a stall with a
--   live hold, and the closer waits for the window), so a stall a waiting car has just left stays held for up to one
--   renewal. That is G195's staging half, whose remedy (the departure sweep, `space_departure_release_enabled`, off)
--   is unchanged. Found in the canon under 0500 (0370 §3).
-- PREDICTED: temp holds after departure each with at most 15 minutes left (17 for a hold never renewed), a handful at
--   a time, against 30-40 parked cars on the calendar in §2; perimeter holds are G195's older half, with hours left.
-- BEFORE: no live reading (the stop relabels live bookings); on `317d4331` 0357 §5 counted 10 staging holds (213
--   stall-minutes) held for cars elsewhere at 9:10 AM sim.
-- READ: pending.

-- ══ §3 G233 (0501): THE WAIT FOR A CHARGER, BESIDE KPI 5 ═════════════════════════════════════════════════════════

\echo '=== 0372 §3 — the companion, and KPI 5 beside it ==='
SELECT public.ottoq_kpi_charge_wait(:'run') AS charge_wait,
       public.ottoq_kpi_five(:'run')->>'p95_time_to_service_min' AS kpi5_p95_min;
-- BEFORE 394e1e83: 135 visits owing a charge, 92 charged (p50 16.2, p95 154.4 minutes), 42 waiting at the stop, p95
--   floor 198.2; KPI 5 p95 0.7.
-- READ: pending. The cockpit's KPI tab shows it under the five (ottoyarddepot-sim#110).

-- ══ §4 WHAT 0486-0495 ALREADY HELD, STILL HOLDING ═════════════════════════════════════════════════════════════════

\echo '=== 0372 §4 — ticks lost, and gate moves outside the tick ==='
SELECT count(*) AS failed_ticks FROM public.ottoq_events e
 WHERE e.sim_run_id = :'run' AND e.event_type = 'sim_tick_failed';
-- BEFORE 394e1e83: 0.
-- READ: pending.

-- ══ §5 G232 (OPEN): WHERE AN INTERIOR INSPECTION IS ACTUALLY DONE ═══════════════════════════════════════════════════
--
--   The catalog puts `interior_inspection` in the `cabin` lane, "cheap tech-pool lane at the charge stall", and derive
--   writes it `concurrency='cabin', at_charge_stall=true`, so the plan draws it inside the charge. G232 is the plan's
--   time for it passing long before it runs. This asks where it ran: the car's state and stall at the atom's start
--   (from the latest `vehicle.state_changed` at or before it), and whether a charging session covered the start.

\echo '=== 0372 §5 — done interior inspections by where the car was when each started ==='
WITH a AS (
  SELECT vn.vehicle_id, (x.a->>'started_at')::timestamptz AS st
    FROM public.ottoq_visit_needs vn, LATERAL jsonb_array_elements(vn.atoms) x(a)
   WHERE vn.sim_run_id = :'run' AND x.a->>'svc' = 'interior_inspection' AND x.a->>'status' = 'done'),
b AS (
  SELECT a.*,
         EXISTS (SELECT 1 FROM public.ocpp_sessions o WHERE o.sim_run_id = :'run' AND o.vehicle_id = a.vehicle_id
                   AND o.started_at <= a.st AND COALESCE(o.ended_at, 'infinity') > a.st) AS charging,
         (SELECT e.payload->'diff'->'current_state'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = :'run' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.sim_clock_at <= a.st AND e.payload->'diff' ? 'current_state'
           ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS state_at_start,
         (SELECT e.payload->'diff'->'current_stall_id'->>'to' FROM public.ottoq_events e
           WHERE e.sim_run_id = :'run' AND e.entity_id = a.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.sim_clock_at <= a.st AND e.payload->'diff' ? 'current_stall_id'
           ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS stall_at_start
    FROM a)
SELECT b.charging, b.state_at_start, COALESCE(s.stall_type::text, '(none)') AS stall_type, COALESCE(s.zone, '-') AS zone,
       count(*) AS atoms
  FROM b LEFT JOIN public.stalls s ON s.id::text = b.stall_at_start
 GROUP BY 1, 2, 3, 4 ORDER BY 5 DESC;
-- BEFORE 394e1e83 (read at 22:00 UTC, before this run's start purged it): 127 done, 5 open at the stop. 12 started at
--   a charger (charging_l2 7, charging_dcfc 5). 97 started while the car was still `arrived_at_gate` in a staging stall:
--   41 in the `arrival_inspection` zone (the seam's lane), and 56 in staging_south 31, staging_east 12, staging_buffer
--   9, staging_north 3 and staging_west 1, the zones the congestion fallback parks a car waiting for a charger in. The
--   other 18 were at `charge_complete_holding` 5, `staged_for_departure` 5 and `staged_awaiting_service` 5, in a
--   detail bay 2, and at the gate with no stall 1.
--   So execution inspects a waiting car while it waits (a technician walks to it), and the plan draws the inspection
--   inside a charge that starts an hour or more later. The plan's time is what is wrong, and the cockpits show it.
-- READ: pending. No fix is in force for G232; this is its second reading.
