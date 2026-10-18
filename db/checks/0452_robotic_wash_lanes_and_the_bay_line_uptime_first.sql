-- 0452  **Robotic wash lanes and the bay line uptime first: what the twin's bays did, and how the line was ordered.**
--        Chase, 2026-10-17 evening CT: the wash bays can be assumed robotic (a pull-through exterior wash; for the
--        interior, an attendant who opens the doors and a robot arm). An urgent issue brings a car home at once and is
--        fitted in around the cars that can rejoin service right away. Measured for 0746 and 0747.
--        -> G460, G461.
--        Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-17 between 7:10 and 7:37 PM CT (00:10 and 00:37 UTC Oct 18,
--        bounded by clock reads). The runs: the 11 completed runs at the twin depot since 2026-10-16 with 144 or more ticks
--        (6 normal days, 5 busy days); every number below names the query that reproduces it.
--
-- ══ §1 THE TWIN'S BAYS WORK FOR AS LONG AS THE BOOKING HAS LEFT (G460; reproduce: (1), (2)) ═══════════════════════════
--
--   Each seat's timer, from its own state-change event (the timer written as the car entered the bay, less the minute
--   it entered):
--                          seats   timer: mean / p10 / p50 / p90   end = booking end   seated after booking start
--     normal, wash bay      164         4.0 /  4.0 /  4.0 /  4.0         154                 4.9 min
--     normal, detail        220        19.1 / 16.8 / 20.0 / 20.0         197                 5.5
--     normal, service bay    85        40.8 / 35.0 / 39.0 / 50.0          81                 6.0
--     busy,   wash bay      276         4.1 /  4.0 /  4.0 /  5.0         260                 4.8
--     busy,   detail        266        19.8 / 20.0 / 20.0 / 20.0         248                 4.9
--     busy,   service bay   260        35.9 / 26.0 / 35.0 / 46.7         178                 4.3
--   The decide books a walk-in for 9 minutes (a wash) or 25 (a detail) at one tick; the twin seats the car on the next
--   tick, five sim-minutes later, and pins its timer to the booking's end (ottoq.ottoq_activate_due_bay_reservations,
--   twin.ottoq_sim_confirm_commands). The crews' own times, 9 and 25 minutes drawn 0.7-1.3x, apply to none of these seats.
--   One car read in full (run 7fe98840, car 1b9b6ea1): wash booked [11:55, 12:04) sim time at 11:55, seated 12:00, out at
--   12:04, 4 minutes.
--
-- ══ §2 THE BAY LINE IS URGENCY FIRST, AND ITS LAST TWO KEYS CARRY LITTLE (G461; reproduce: (3), (4)) ══════════════════
--
--   Decide section (4b)'s bay decisions (task_start resolved to stall_assignment, source needs_card):
--                  decisions   urgency critical   past the car's deploy time (median)   no deploy time   open_must_do_min = 0
--     busy days      3,875          2,090                2,638 (-431 min)                    901                3,554
--     normal days    1,149            264                  363 (+149 min)                    104                1,146
--   Passed over (noop_no_candidate) at the service bays: busy days mechanical_pm 1,411, fault_repair 826,
--   sensor_calibration 378; normal days 30, 67 and 18 (query (3), by need, urgency and outcome).
--
-- ══ §3 THE RECALL ALREADY BRINGS AN URGENT CAR HOME AT ONCE (reproduce: (5)) ═══════════════════════════════════════════
--
--   Both recall implementations return true, not deferrable, for a safety-critical fault (rung 1, lead 0 ticks), a major
--   fault (rung 2, lead 1), a low battery near reserve (rung 3, lead 1), a rider-flagged cleaning (rung 4, lead 0) and
--   stale comms (rung 8, lead 0). Chase's "focus on just getting the vehicle back to depot" is the recall as it stands.
--
-- ══ §4 THE DRY RUNS (rolled back by their own final RAISE; reproduce: the files) ════════════════════════════════════════
--
--   0746 alone, 2026-10-17 between 7:20 and 7:37 PM CT: every premise and check passed; the executable part read back by
--   md5(current_query()) equal to the file's (62450e75, priority 15 before the edit to 14); the gate 2 at the default and
--   NULL at 2; a wash for car 00cc3d0a on run 7fe98840 at 1 hour 1 minute in: 11.007 minutes at 1, 5.557 at 2 (the same
--   draw, 1.223); post-images: the service flow d7f2ee27, the decide b90378b7, the charge-off wash admission 7b56721a.
--   0746 and 0747 together, the same window: both executable parts read back equal to the files (0746 2627e8ba, 0747
--   796c5dfb); (4b)'s patched cursor planned (EXPLAIN) and run on run 7fe98840 with both dials on (0 candidates: no car
--   is staged at that run's end); the key over the depot's 120 cars at the run's end: 0 emergencies, 4 past the floor;
--   post-images: the decide fc843b9e, the key ec6a2dc9.
--   0747's key was then extended to the twin's two hazard classes (an HV battery thermal event or a charge-system fault
--   is an emergency; its other in-depot faults are fitted in). The new key, created as a temporary function and run with
--   the dial on busy run 96616822 at its end (rolled back), keyed the depot's 120 cars in 67 ms. The executable part is
--   now md5 298b9337 and the key's body 8d395ffe; the decide's patch, and so its post-image fc843b9e, are unchanged.

-- (1) G460: each bay seat's timer, from the seat's own state-change event.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144),
seats AS (
  SELECT r.scenario_code, e.payload->'diff'->'current_state'->>'to' AS bay,
         extract(epoch from ((e.payload->'diff'->'config'->'to'->>'service_ends_at')::timestamptz
                             - (e.payload->'diff'->'last_state_change'->>'to')::timestamptz))/60.0 AS timer_min
    FROM ottoq_events e JOIN runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay','in_detail_bay','in_service_bay')
     AND e.payload->'diff'->'config'->'to' ? 'service_ends_at')
SELECT scenario_code, bay, count(*) n,
  round(avg(timer_min)::numeric,1) mean, round(percentile_cont(0.1) within group (order by timer_min)::numeric,1) p10,
  round(percentile_cont(0.5) within group (order by timer_min)::numeric,1) p50,
  round(percentile_cont(0.9) within group (order by timer_min)::numeric,1) p90,
  count(*) FILTER (WHERE timer_min < CASE bay WHEN 'in_wash_bay' THEN 6.3 WHEN 'in_detail_bay' THEN 17.5 ELSE 28 END) below_crew_floor
FROM seats GROUP BY 1,2 ORDER BY 1,2;

-- (2) G460: each seat against the booking that covers it: does the timer end where the booking ends, and how long
--     after the booking began was the car seated.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144),
seats AS (
  SELECT r.scenario_code, e.sim_run_id, e.entity_id AS vehicle_id, e.payload->'diff'->'current_state'->>'to' AS bay,
         (e.payload->'diff'->'last_state_change'->>'to')::timestamptz AS seat_at,
         (e.payload->'diff'->'config'->'to'->>'service_ends_at')::timestamptz AS ends_at
    FROM ottoq_events e JOIN runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff'->'current_state'->>'to' IN ('in_wash_bay','in_detail_bay','in_service_bay')
     AND e.payload->'diff'->'config'->'to' ? 'service_ends_at'),
j AS (SELECT s.*, extract(epoch from s.seat_at - lower(b.during))/60.0 AS seat_after_book_lo,
             (upper(b.during) = s.ends_at) AS ends_at_booking_end
        FROM seats s LEFT JOIN LATERAL (
          SELECT b.* FROM ottoq_stall_bookings b
           WHERE b.sim_run_id = s.sim_run_id AND b.vehicle_id = s.vehicle_id AND b.purpose IN ('wash','detail','service')
             AND b.during @> s.seat_at ORDER BY lower(b.during) DESC LIMIT 1) b ON true)
SELECT scenario_code, bay, count(*) n, count(*) FILTER (WHERE ends_at_booking_end) ends_at_booking_end,
  round(avg(seat_after_book_lo)::numeric,1) mean_seat_after_booking_start
FROM j GROUP BY 1,2 ORDER BY 1,2;

-- (3) G461: decide section (4b)'s bay decisions by need, urgency and outcome.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144)
SELECT r.scenario_code, d.context_frame->>'need' need, d.context_frame->>'overall_urgency' urg, d.outcome_status, count(*) n
FROM ottoq_decisions d JOIN runs r USING (sim_run_id)
WHERE d.action_context = 'task_start' AND d.resolved_action_context = 'stall_assignment'
  AND d.proposed_action->>'source' = 'needs_card'
GROUP BY 1,2,3,4 ORDER BY 1,2,3,4;

-- (4) G461: how much the order's last two keys carry.
WITH runs AS (SELECT sim_run_id, scenario_code FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-10-16 00:00' AND tick_count >= 144)
SELECT r.scenario_code, count(*) n,
  count(*) FILTER (WHERE (d.context_frame->>'minutes_to_deploy')::numeric < 0) past_deploy,
  count(*) FILTER (WHERE d.context_frame->>'minutes_to_deploy' IS NULL) no_deploy,
  count(*) FILTER (WHERE COALESCE((d.context_frame->>'open_must_do_min')::numeric, 0) = 0) omd_zero,
  count(*) FILTER (WHERE d.context_frame->>'overall_urgency' = 'critical') critical,
  round(percentile_cont(0.5) within group (order by (d.context_frame->>'minutes_to_deploy')::numeric)::numeric, 0) med_mtd
FROM ottoq_decisions d JOIN runs r USING (sim_run_id)
WHERE d.action_context = 'task_start' AND d.resolved_action_context = 'stall_assignment'
  AND d.proposed_action->>'source' = 'needs_card'
GROUP BY 1 ORDER BY 1;

-- (5) The recall's rungs, read from the two implementations' source.
WITH src AS (SELECT p.proname, p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname IN ('ottoq_recall_naive_threshold_v1', 'ottoq_recall_interval_scheduled_v1')),
l AS (SELECT proname, t.ord AS ln, t.line FROM src, LATERAL unnest(string_to_array(src.prosrc, E'\n')) WITH ORDINALITY AS t(line, ord))
SELECT proname, ln, trim(line) FROM l WHERE line ~ 'RETURN QUERY SELECT true' ORDER BY proname, ln;
