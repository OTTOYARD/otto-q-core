-- 0358  **The gate intake picked staging stalls its own command gate refused, and every refusal left a phantom hold
--       on a second stall.** FINDINGS G199 (G197's second half, and a source of G195's calendar leak).
--
--       §1 is measured on validation run `317d4331-747a-4fd4-ab69-41ec78c5be98` (busy_day, twin depot `11111111-…`,
--       sim 8:00 AM-12:34 PM CT, 275 sim-min; stopped 04:48 UTC on 2026-09-26), read after the stop and before any purge. The run is
--       engine-class data and the next demo start deletes it; the numbers below are the record.
--       §2 is the rolled-back before/after probe of migration 0467 on the same run.
--
--       Every query takes the run as a psql variable:
--
--           \set run '<sim_run_id>'

\set run '317d4331-747a-4fd4-ab69-41ec78c5be98'

-- ══ §1 THE INTAKE ASKED THE POINTER; THE GATE ASKED THE CALENDAR ═════════════════════════════════════════════════

\echo '=== 0358 §1a — gate intakes, what they said, and what happened to their commands ==='
WITH d AS (
  SELECT d.entity_id AS vehicle_id, d.sim_clock, (d.enacted_action->>'stall_id')::uuid AS stall_id,
         NULLIF(d.enacted_action->>'booking_id','')::uuid AS booking_id, d.outcome_status
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = :'run' AND d.resolved_action_context = 'gate_intake_no_charge')
SELECT count(*) AS intake_decisions, count(DISTINCT vehicle_id) AS vehicles,
       count(*) FILTER (WHERE outcome_status = 'enacted') AS logged_enacted,
       count(*) FILTER (WHERE booking_id IS NULL) AS no_staging_booking,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands c
                                       WHERE c.sim_run_id = :'run' AND c.vehicle_id = d.vehicle_id
                                         AND c.command_type = 'proceed_to_stall' AND c.issued_at = d.sim_clock
                                         AND (c.payload->>'stall_id')::uuid = d.stall_id AND c.payload ? 'new_state'
                                         AND c.status = 'refused' AND c.confirmed_by = 'otto_q_preflight')) AS refused_before_the_twin
  FROM d;
-- 61 intakes / 47 cars / 61 logged `enacted` / 51 without a staging booking / 51 refused pre-flight.
-- The 51 without a booking are the 51 refused: `ottoq_book_stall` meets the same live booking the gate did.

\echo '=== 0358 §1b — why the gate refused them ==='
SELECT c.reason_code::text AS code,
       left(regexp_replace(c.reason_detail, '[0-9a-f]{8}-[0-9a-f-]{27}', '<car>', 'g'), 60) AS detail,
       count(*) AS n, count(DISTINCT c.vehicle_id) AS cars, count(DISTINCT c.payload->>'stall_id') AS stalls
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'proceed_to_stall'
   AND c.payload->>'new_state' = 'staged_awaiting_service' AND c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused'
 GROUP BY 1,2 ORDER BY n DESC;
-- target_occupied / "calendar booking held by <car>" / 51 / 41 cars / 14 stalls. Every one is the calendar branch of
-- `ottoq_validate_assignment`: the intake's pick had already required the pointer free, so the pointer and
-- reservation branches cannot fire here.

\echo '=== 0358 §1c — two commands per intake, and what the reactor did with each ==='
SELECT c.payload ? 'new_state' AS carries_step, c.status::text AS status, COALESCE(c.reason_code::text,'') AS code,
       c.confirmed_by, count(*) AS n
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'proceed_to_stall'
   AND (c.payload->>'new_state' = 'staged_awaiting_service' OR c.payload->>'reason' = 'gate_intake')
   AND NOT c.payload ? 'reroute_after'
 GROUP BY 1,2,3,4 ORDER BY 1 DESC, n DESC;
-- Each intake emits `proceed_to_stall` twice to one stall: with `new_state`+`svc_step`, then with only
-- `reason: gate_intake`. 51 + 51 refused pre-flight. When both are accepted the door retires the second as
-- `duplicate_reissue_of_in_flight_command` (15).

\echo '=== 0358 §1d — the reroutes, and the holds they left behind ==='
WITH rr AS (
  SELECT c.command_id, c.vehicle_id, c.issued_at, (c.payload->>'stall_id')::uuid AS stall_id, c.status::text AS st,
         c.reason_code::text AS rc, (c.payload->>'reroute_after')::uuid AS parent
    FROM public.ottoq_vehicle_commands c
   WHERE c.sim_run_id = :'run' AND c.payload ? 'reroute_after')
SELECT rr.st, COALESCE(rr.rc,'') AS code, (p.payload ? 'new_state') AS parent_carried_step, count(*) AS reroutes,
       count(b.booking_id) AS with_booking,
       round(sum(extract(epoch FROM (COALESCE(b.released_at, upper(b.during)) - lower(b.during)))/60)::numeric) AS booked_stall_min,
       string_agg(DISTINCT b.state || '/' || COALESCE(b.release_reason,'-'), ', ') AS how_the_booking_ended
  FROM rr
  JOIN public.ottoq_vehicle_commands p ON p.command_id = rr.parent
  LEFT JOIN public.ottoq_stall_bookings b
         ON b.sim_run_id = :'run' AND b.vehicle_id = rr.vehicle_id AND b.stall_id = rr.stall_id
        AND b.booked_by IN ('otto_q_reaction','otto_q_reaction_last_resort') AND lower(b.during) = rr.issued_at
 WHERE p.command_type = 'proceed_to_stall'
   AND (p.payload->>'reason' = 'gate_intake' OR p.payload->>'new_state' = 'staged_awaiting_service')
 GROUP BY 1,2,3 ORDER BY 4 DESC;
-- All 102 refused intake commands were rerouted, each to its own stall with an hour's reservation and a 60-minute
-- `temp_hold` booking. The two reroutes of one intake are two stall commands for one car, and the door keeps the
-- newest by (issued_at, command_type, stall_id DESC, command_seq): by stall id. 70 were retired `superseded`
-- (36 without the step, 34 WITH it), and 49 of those had booked: released only by `window_elapsed` or the stop,
-- 2,775 stall-minutes on staging, ~56 min each. 32 executed (17 carrying the step, 15 not).
-- 2,775 stall-minutes is about a tenth of the 101 intake staging stalls x 275 sim-minutes, held for cars that were
-- elsewhere.

\echo '=== 0358 §1e — where a refused intake car went next ==='
WITH r AS (
  SELECT DISTINCT ON (c.vehicle_id) c.vehicle_id, c.issued_at AS refused_at
    FROM public.ottoq_vehicle_commands c
   WHERE c.sim_run_id = :'run' AND c.command_type = 'proceed_to_stall' AND c.payload ? 'new_state'
     AND c.reason_code = 'target_occupied' AND c.confirmed_by = 'otto_q_preflight'
   ORDER BY c.vehicle_id, c.issued_at)
SELECT t.tr AS first_move_off_the_gate, count(*) AS cars
  FROM r
  LEFT JOIN LATERAL (
      SELECT (e.payload->'diff'->'current_state'->>'from') || ' -> ' || (e.payload->'diff'->'current_state'->>'to') AS tr
        FROM public.ottoq_events e
       WHERE e.sim_run_id = :'run' AND e.entity_id = r.vehicle_id AND e.event_type = 'vehicle.state_changed'
         AND e.payload->'diff' ? 'current_state' AND e.payload->'diff'->'current_state'->>'from' = 'arrived_at_gate'
         AND e.sim_clock_at >= r.refused_at
       ORDER BY e.sim_clock_at, e.event_id LIMIT 1) t ON true
 GROUP BY 1 ORDER BY 2 DESC;
-- 32 of 41 left the gate for staging, 9 for a charger. A car whose surviving reroute was the step-less one kept
-- `arrived_at_gate` on a staging stall: the (3b) cursor requires `current_stall_id IS NULL`, so it never saw the car
-- again, and the car moved only when another path (the inspection seam, a charge) took it.

-- ══ §2 THE FIX, BEFORE AND AFTER, ON ONE ROLLED-BACK TRANSACTION (0467) ══════════════════════════════════════════
--
--   Run on 2026-09-26 at 05:24 UTC (12:24 AM CT), after the 0463-0465 recert (9/9 passed) and before 0467 applied,
--   as one transaction that raised at its end: the migration's own P2, patch and V-blocks, bracketed by the same
--   setup on the stopped run 317d4331 (all 116 twin cars offline, no open visits, no live bookings). One car
--   (d0887837) at the gate with an open no-charge visit; the first stall of the intake's own order (ddedafd3) held
--   on the calendar by another car (b2222222-…-05) from 5 minutes before the clock to 55 after. Then one
--   `public.ottoq_decide_tick(317d4331)` on the old body (undone by a caught exception), the patch, and one on the new.
--
--                       old body                                          new body (0467)
--     commands          2 to ddedafd3, both REFUSED pre-flight:           1 to 72a4c5cf, ISSUED, carrying
--                       target_occupied "calendar booking held by        svc_step need_deploy, reason gate_intake
--                       b2222222-…"; one step-less                        and new_state
--     decision          gate_intake_no_charge ENACTED, no booking         gate_intake_no_charge enacted, booked
--     reservation       the refused stall, for this car                   the issued stall
--     staging booking   0                                                 1
--
--   The probe script is the migration's blocks between two copies of the setup; it is not committed because it
--   writes to a stopped run's rows (it cannot run on a live one without racing the metronome).
