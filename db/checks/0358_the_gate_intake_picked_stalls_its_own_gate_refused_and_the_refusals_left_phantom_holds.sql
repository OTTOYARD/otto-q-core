-- 0358  **The gate intake picked staging stalls its own command gate refused, and every refusal left a phantom hold
--       on a second stall.** FINDINGS G199 (G197's second half, and a source of G195's calendar leak).
--
--       §1 is measured on validation run `317d4331-747a-4fd4-ab69-41ec78c5be98` (busy_day, twin depot `11111111-…`,
--       sim 8:00 AM-12:34 PM CT, 275 sim-min; stopped 04:48 UTC on 2026-09-26), read after the stop and before any purge. The run is
--       engine-class data and the next demo start deletes it; the numbers below are the record.
--       §2 is the rolled-back before/after probe of migration 0467 on the same run. §3-§5 are G201 and G200 and the
--       probe of 0468/0469; §6-§7 are G203 (staging holds booked on stalls promised to another car) and the probe of
--       0471, all on the same run.
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

\echo '=== 0358 §1f — every hold that expired unused, by who made it (what G195 is left with after 0467) ==='
SELECT s.stall_type::text AS stype, COALESCE(b.booked_by,'-') AS booked_by, b.purpose, count(*) AS n,
       round(sum(extract(epoch FROM (COALESCE(b.released_at, upper(b.during)) - lower(b.during)))/60)) AS stall_min
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id = :'run' AND b.state = 'released' AND b.release_reason ILIKE '%window_elapsed%'
 GROUP BY 1,2,3 ORDER BY stall_min DESC;
-- staging / otto_q_reaction / temp_hold   69 / 4,182 stall-min   (of which the gate intake's superseded reroutes: 49 / 2,775)
-- staging / otto_q          / temp_hold   98 / 1,827
-- l2      / otto_q          / charge_l2   15 /   795
-- then perimeter_hold 1 / 120, inspect 8 / 32, wash 2 / 21. After 0467 the reactor line should lose the intake's
-- share; the rest is G195's residual and the next thing to measure on a live run.

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

-- ══ §3 G201: THE SERVICE BAY ADMITTED ON THE STEP ALONE, AND THE BOOT COHORT SAT 40 MINUTES FOR NOTHING ══════════

\echo '=== 0358 §3a — the boot cohort: seeded need_service, no visit, and what the service bay credited ==='
WITH boot AS (
  SELECT e.entity_id AS vehicle_id, e.payload->'diff'->'current_state'->>'to' AS boot_state
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'from' = 'offline'
     AND e.sim_clock_at = (SELECT sim_clock_start FROM public.ottoq_sim_runs WHERE sim_run_id = :'run')
     AND e.payload->'diff'->'config'->'to'->>'svc_step' = 'need_service'),
seat AS (
  SELECT b.vehicle_id, b.boot_state,
         (SELECT e.payload->'credited' FROM public.ottoq_events e
           WHERE e.sim_run_id = :'run' AND e.entity_id = b.vehicle_id AND e.event_type = 'twin.service_completed'
           ORDER BY e.sim_clock_at LIMIT 1) AS first_exit_credited,
         EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                  WHERE vn.sim_run_id = :'run' AND vn.vehicle_id = b.vehicle_id
                    AND vn.arrived_at <= (SELECT sim_clock_start FROM public.ottoq_sim_runs WHERE sim_run_id = :'run') + interval '1 minute') AS had_boot_visit
    FROM boot b)
SELECT boot_state, count(*) AS cars, count(*) FILTER (WHERE had_boot_visit) AS with_boot_visit,
       count(first_exit_credited) AS bay_exits,
       count(*) FILTER (WHERE jsonb_array_length(COALESCE(first_exit_credited, '[1]'::jsonb)) = 0) AS exits_crediting_nothing
  FROM seat GROUP BY 1;
-- staged_awaiting_service 9 cars / 0 with a visit / 5 bay exits / 4 crediting nothing; charge_complete_holding 1 / 0 / 0.
-- Tesla-AV-070 and Zoox-AV-078 (0357's examples): offline -> staged_awaiting_service at 8:00:00 with need_service,
-- in_service_bay 8:06:27 to 8:46:28, `credited: []`, then ready and deployed. No command for either before 8:50: the
-- seat is the service flow's own STEP 2, whose service cursor reads only `staged_awaiting_service` + `need_service`.
-- The wash cursor above it is need-gated ("M1_need_gated_wash"); the service cursor never was.
-- These 4 are half of G196b's 8 empty service-bay exits. Fixed by 0468.

-- ══ §4 G200: A STAGE COMMAND EVERY TICK THAT THE DOOR EXECUTED AS NOTHING ════════════════════════════════════════

\echo '=== 0358 §4 — stage commands by shape ==='
SELECT c.status::text AS status, c.payload ? 'stall_id' AS has_stall,
       left((c.payload - 'refused_at_clock' - 'reaction' - 'stall_id' - 'reroute_after' - 'booking_id')::text, 60) AS shape,
       count(*) AS n, count(DISTINCT c.vehicle_id) AS cars
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'stage'
 GROUP BY 1,2,3 ORDER BY n DESC LIMIT 5;
-- executed / no stall / {"ready": true} / 7,686 / 74 cars (up to 262 for one car over 574 ticks). Emitted by
-- ottoq_decide_tick (5) for every promote_ready verdict; twin.ottoq_sim_confirm_commands maps `stage` to no
-- transition, so each is a command row and a door pass that changes nothing. Removed by 0469.

-- ══ §5 0468 AND 0469, BEFORE AND AFTER, IN TICK ORDER, ON ONE ROLLED-BACK TRANSACTION ═══════════════════════════
--
--   Run on 2026-09-26 at 05:58 UTC (12:58 AM CT), after 0467's recert (9/9 passed), as one transaction that raised
--   at its end: both files' P2, patch and V-blocks, bracketed by the same setup on the stopped run 317d4331, and
--   called in the order `ottoq_sim_advance_tick` calls them: the service flow (world step) first, then the decide
--   tick. Four cars, each `staged_awaiting_service`:
--     A  `need_service`, SoC 90, no visit, no flag            (the boot cohort's shape)
--     B  `need_service`, open must-do `mechanical_pm`          (real service-bay work: the control)
--     C  `need_charge`, SoC 40, no visit                        (reaches the sequencer's promote_ready)
--     D  `need_service`, no visit, `flagged_issue` tech_flag    (the technician path, which must keep its seat)
--
--                       old bodies                                       new bodies (0468 + 0469)
--     A                 stays need_service; decide emits enter_wash      need_deploy -> released by the gate in the
--                       and stage {ready: true}                          same pass: staged_for_departure / ready
--     B                 in_service_bay / servicing                       in_service_bay / servicing
--     C                 stage {ready: true}; decision promote_ready      no command; decision promote_ready kept
--     D                 in_service_bay / servicing                       in_service_bay / servicing
--     stage {ready}     2                                                0
--
--   A first run in the reverse order (decide tick first) had the sequencer admit A on its step alone: the decide
--   path's `ottoq_l2_propose_service` admits on `svc_step = 'need_service' OR` open service-bay work. It is not
--   patched: in a real tick the world step, and 0468 inside it, runs first. The first draft of 0468 had no flag
--   exemption; the service flow's own STEP 1 sends flagged cars from the wash and detail bays to the service bay on
--   the flag alone, so the exemption was added before apply and D is its proof.

-- ══ §6 G203: THE STAGING HOLD BOOKED STALLS PROMISED TO ANOTHER CAR, AND KEPT EVERY BOOKING IT COULD NOT USE ══════
--
--   §1f counted 98 `otto_q` `temp_hold` bookings that expired unused. This splits them by what the stall's pointer
--   said just before each booking, rebuilt from the stall's own `stall.state_changed` diffs (they carry
--   `reserved_by`, `reservation_expires_at` and `current_vehicle_id`). Measured 2026-09-26 06:25 UTC, run still intact.

\echo '=== 0358 §6a — otto_q temp_hold bookings by outcome ==='
WITH b AS (
  SELECT b.* FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = :'run' AND b.purpose = 'temp_hold' AND b.booked_by = 'otto_q')
SELECT b.state, b.release_reason,
       EXISTS (SELECT 1 FROM public.ottoq_events e
                WHERE e.sim_run_id = b.sim_run_id AND e.entity_id = b.vehicle_id
                  AND e.event_type = 'vehicle.state_changed'
                  AND e.payload->'diff'->'current_stall_id'->>'to' = b.stall_id::text) AS car_ever_on,
       count(*) AS n
  FROM b GROUP BY 1,2,3 ORDER BY n DESC;
-- 290 bookings. done/window_elapsed_occupied/on 176 · released/window_elapsed/NEVER ON 58 · released/window_elapsed/
-- on 40 · done/vehicle_moved_to_next_leg 9 · released/run_stopped 7. The 58 are the orphans; 50 were windows that
-- started the tick they were booked, the other 8 a mean 36 s later.

\echo '=== 0358 §6b — the 58 orphans by the stall pointer just before booking ==='
WITH o AS (
  SELECT b.booking_id, b.stall_id, b.vehicle_id, lower(b.during) AS t0, upper(b.during) AS t1, s.staging_role
    FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id = :'run' AND b.purpose = 'temp_hold' AND b.booked_by = 'otto_q'
     AND b.state = 'released' AND b.release_reason = 'window_elapsed'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_events e
                      WHERE e.sim_run_id = b.sim_run_id AND e.entity_id = b.vehicle_id
                        AND e.event_type = 'vehicle.state_changed'
                        AND e.payload->'diff'->'current_stall_id'->>'to' = b.stall_id::text)),
st AS (
  SELECT o.*,
    (SELECT e.payload->'diff'->'reserved_by'->>'to' FROM public.ottoq_events e
      WHERE e.sim_run_id = :'run' AND e.entity_id = o.stall_id AND e.event_type = 'stall.state_changed'
        AND e.payload->'diff' ? 'reserved_by' AND e.sim_clock_at < o.t0
      ORDER BY e.sim_clock_at DESC, e.occurred_at DESC LIMIT 1) AS rsv_before,
    (SELECT (e.payload->'diff'->'reservation_expires_at'->>'to')::timestamptz FROM public.ottoq_events e
      WHERE e.sim_run_id = :'run' AND e.entity_id = o.stall_id AND e.event_type = 'stall.state_changed'
        AND e.payload->'diff' ? 'reservation_expires_at' AND e.sim_clock_at < o.t0
      ORDER BY e.sim_clock_at DESC, e.occurred_at DESC LIMIT 1) AS rsv_exp_before,
    (SELECT e.payload->'diff'->'current_vehicle_id'->>'to' FROM public.ottoq_events e
      WHERE e.sim_run_id = :'run' AND e.entity_id = o.stall_id AND e.event_type = 'stall.state_changed'
        AND e.payload->'diff' ? 'current_vehicle_id' AND e.sim_clock_at < o.t0
      ORDER BY e.sim_clock_at DESC, e.occurred_at DESC LIMIT 1) AS cur_before
  FROM o)
SELECT CASE WHEN cur_before IS NOT NULL THEN 'car on the stall'
            WHEN rsv_before IS NOT NULL AND rsv_before <> vehicle_id::text
                 AND (rsv_exp_before IS NULL OR rsv_exp_before > t0) THEN 'live reservation by another car'
            WHEN rsv_before = vehicle_id::text THEN 'reserved by the same car'
            ELSE 'free' END AS pointer_at_booking,
       staging_role, count(*) AS n, round(avg(extract(epoch FROM t1 - t0) / 60)) AS avg_window_min
  FROM st GROUP BY 1, 2 ORDER BY n DESC;
-- live reservation by another car  temp 23 (20 min) + long 11 (23 min) = 34
-- car on the stall                 temp 15 (16 min) + long  3 (9 min)  = 18
-- free                             temp  3 + long 3                    =  6
--
-- The booking's candidate source, ottoq.ottoq_stall_free_between, reads the calendar, stall status, charger health
-- and (behind calendar_occupancy_guard, on) the car on the stall. It never reads `reserved_by`, so a reservation
-- that outlived its booking (the refusal reactor reserves 3,600 s beside a 60-minute booking; a superseded command
-- releases the booking and not the pointer) left a stall that looked free and could not be reserved. The two
-- callers, ottoq_decide_tick (3) when the charge proposer abstains and ottoq.ottoq_place_unplaced_vehicles, then
-- called ottoq_reserve_stall, were refused, and did nothing with the booking they had just made. The car-on-stall
-- cases pass the occupancy guard because it trusts the car's planned leg end. `arm.move_refused` fired 0 times on
-- this run, so the third failure branch (the arm) is not a source here. Fixed by 0471.

-- ══ §7 0471, BEFORE AND AFTER, ON TWO ROLLED-BACK TRANSACTIONS ═════════════════════════════════════════════════════
--
--   Run on 2026-09-26 at 06:33-06:37 UTC (1:33-1:37 AM CT), after 0470 and with no pair or run live, as transactions
--   that raised at their end: 0471's P0, P2, patches and V-blocks, bracketed by the same scenarios on the stopped run
--   317d4331 (sim clock 12:34 PM CT). The car is the depot's lowest id (so `p_max => 1` places it and only it); its
--   disposition is `redeploy`, a 20-minute temp hold, and the stall its hold books today is called S.
--
--   ottoq_place_unplaced_vehicles(run, depot, clock, 1)       old bodies                   new bodies (0471)
--     S free (control)                                          placed on S                  placed on S
--     S reserved by another car to clock+15 min                 not placed; S held, orphan   placed on the next stall
--     another car on S, occupancy guard off for the run *       not placed; S held, orphan   not placed; S released
--                                                                                            reserve_refused_place_unplaced
--   ottoq_decide_tick(run), the car low at the gate with an open charge visit, every charge stall in maintenance,
--   ottoq_reserve_stall stubbed to refuse **
--     disposition temp_stage_await_resource                     hold held, orphan            hold released
--                                                                                            reserve_refused_decide_tick
--
--   *  The guard trusts the car's plan; turning it off for the run stands in for its plan-ended blind spot.
--   ** A first attempt with the same car and no open visit read `redeploy`, which books no hold, so the branch was
--      not reached; the open charge visit is what puts a car on it (ottoq.ottoq_arrival_disposition).
