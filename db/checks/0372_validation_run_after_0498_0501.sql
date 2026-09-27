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
-- READ (22:53 UTC, 5:53 PM CT, after the stop at sim 11:44 AM): no rows. The charge step issued 105 `begin_charge`: 103
--   executed, 2 expired at the stop (issued on the last tick, `run_ended`), 0 refused at the gate. Held.

\echo '=== 0372 §1(b) — the frame''s calendar fact, over the run''s snapshots ==='
SELECT count(*) AS snapshots,
       count(*) FILTER (WHERE s.frame->'selector'->>'facts_version' = '4') AS facts_v4,
       max((SELECT count(*) FROM jsonb_array_elements(s.frame->'stalls') st WHERE st->>'calendar_held_by' IS NOT NULL)) AS max_calendar_held,
       max((SELECT count(*) FROM jsonb_array_elements(s.frame->'stalls') st
             WHERE st->>'calendar_held_by' IS NOT NULL AND st->>'vehicle_id' IS NULL AND st->>'type' IN ('dcfc','l2'))) AS max_promised_empty_chargers
  FROM public.ottoq_decision_snapshots s WHERE s.sim_run_id = :'run';
-- PREDICTED: every snapshot at facts_version 4, and at busy times chargers the calendar holds while their pointer is
--   empty (the case 0498 stops CP-SAT offering).
-- READ: 206 snapshots, all 206 at facts_version 4. At most 117 stalls held by the calendar in one frame, and at most 2
--   chargers the calendar held with no car on them, the case 0498 takes out of CP-SAT's offer. Held.

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
-- READ: 199 proposals: refused / proposer_abstained 150, superseded / entity_decided_by_other_proposal 31, refused /
--   stall_reserved 10, refused / stall_occupied 5, enacted / enacted_by_kernel 2, superseded / newer_proposal_same_entity
--   1. The prediction is tested by the next query, each proposal against a frame.

\echo '=== 0372 §1(c), second query (added after the stop): each stall proposal against the decide frame at its tick ==='
WITH p AS (
  SELECT p.status, p.disposition_reason, p.tick_seq, p.entity_id AS car, p.proposal->>'stall_id' AS stall_id,
         (p.proposal->'rationale'->>'planned_start_min')::numeric AS start_min
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = :'run' AND p.source = 'forward_lex' AND p.action_context = 'stall_assignment'
     AND p.proposal ? 'stall_id'),
f AS (
  SELECT p.*, y.st AS entry
    FROM p
    LEFT JOIN public.ottoq_decision_snapshots s ON s.sim_run_id = :'run' AND s.tick_seq = p.tick_seq
    LEFT JOIN LATERAL (SELECT x FROM jsonb_array_elements(s.frame->'stalls') x WHERE x->>'id' = p.stall_id LIMIT 1) y(st)
      ON true)
SELECT CASE WHEN entry IS NULL THEN 'no snapshot at its tick'
            WHEN entry->>'calendar_held_by' IS NOT NULL AND entry->>'calendar_held_by' <> car::text
              THEN 'held by another car''s booking'
            WHEN entry->>'offerable' = 'false' AND entry->>'reservation_live' = 'true' AND entry->>'vehicle_id' IS NULL
              THEN 'empty, another car''s live reservation'
            WHEN entry->>'offerable' = 'false' THEN 'not offerable, other'
            ELSE 'offerable' END AS frame_said,
       (start_min > 0) AS later_slot, status || ' / ' || COALESCE(disposition_reason, '-') AS outcome, count(*)
  FROM f GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ: 18 of the 199 name a stall, and 11 of those have a decide snapshot at their tick. That snapshot is the frame of
--   the tick that disposes the proposal: CP-SAT solves a tick earlier (the ledger's call at tick 207 is the proposals
--   tagged 208) on a frame the edge function builds. Held by another car's booking: 0. The prediction held.
--   5 read offerable=false for an empty DCFC under another car's live reservation with no booking, and each of the 3
--   chargers' `reservation_expires_at` carries the disposing tick's clock to the microsecond (.726544 at tick 208,
--   .294464 at 270): the per-car path reserved the charger between CP-SAT's solve and the disposal, and the kernel
--   refused the proposal `stall_reserved`. The forward proposer does read `offerable` (`stall_is_free`), so this is the
--   race and not a blind spot. The other 6 were offerable: 5 refused `stall_occupied` in the same race, 1 enacted. The 7
--   without a snapshot: stall_reserved 5, enacted 1, superseded 1. 394e1e83 had the race too (occupied 8, reserved 8);
--   what 0498 removed, a charger the calendar had promised, did not recur.

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
-- READ, live (parked / on the calendar):
--     sim  8:28 AM, tick  50   at the gate  1/1    staged for departure 31/31
--          9:31 AM,      170   at the gate 18/18   awaiting service  6/6    for departure 2/2
--          9:48 AM,      201   at the gate 29/27   awaiting service  9/9    for departure 1/1
--         10:52 AM,      318   at the gate 44/44   awaiting service 21/21   for departure 1/1
--         11:21 AM,      370   at the gate 45/45   awaiting service 20/20   for departure 1/1
--         11:40 AM,      406   at the gate 43/43   awaiting service 23/23   for departure 1/1
--   Held at five readings of six. The two at 9:48 were not on a parking hold: 72ccc3d4 on NASH-STG-I007 and 7a138260 on
--   NASH-STG-I009 sat in the inspection lane 26 sim-seconds after their 4-minute `inspect` booking (readiness_check)
--   ended, and moved on at 9:50 to E022 and E021. Over the run 54 of 66 inspect bookings in staging ended with the car
--   still on the stall, for a p50 of 0.63 minutes (max 1.99, 38.9 stall-minutes in all): the car waits for the next
--   decide tick to move it. That is a service booking's tail, which 0500 does not renew and this check did not predict.

\echo '=== 0372 §2, second query (added after the stop) — how long a car stays on after its inspect booking in staging ends ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
b AS (
  SELECT b.vehicle_id, b.stall_id, lower(b.during) AS lo, upper(b.during) AS hi
    FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.run
    JOIN public.stalls s ON s.id = b.stall_id AND s.stall_type::text = 'staging'
   WHERE b.purpose = 'inspect' AND upper(b.during) <= r.t),
x AS (
  SELECT b.*, (SELECT min(e.sim_clock_at) FROM public.ottoq_events e, r
                WHERE e.sim_run_id = r.run AND e.entity_id = b.vehicle_id AND e.event_type = 'vehicle.state_changed'
                  AND e.payload->'diff'->'current_stall_id'->>'from' = b.stall_id::text AND e.sim_clock_at >= b.lo) AS left_at
    FROM b)
SELECT count(*) AS ended, count(*) FILTER (WHERE left_at > hi) AS car_still_on_at_the_end,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM left_at - hi) / 60)
              FILTER (WHERE left_at > hi))::numeric, 2) AS p50_min_past_end,
       round((max(EXTRACT(epoch FROM left_at - hi) / 60) FILTER (WHERE left_at > hi))::numeric, 2) AS max_min_past_end,
       round((sum(EXTRACT(epoch FROM left_at - hi) / 60) FILTER (WHERE left_at > hi))::numeric, 1) AS stall_minutes
  FROM x;
-- READ (after the stop): 66 ended, 54 with the car still on the stall, p50 0.63 minutes past the end, max 1.99, 38.9
--   stall-minutes.

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
-- READ, live, as written: sim 8:28 AM 15 temp holds after departure (188 stall-minutes, max 28.5 minutes left); 9:31
--   AM 11 (max 13) and 1 perimeter hold (57). The 8:28 reading broke the prediction's 15 minutes, and not through the
--   renewal: this run books temp holds for 30 minutes, not 12-17, so a car leaving inside its first window leaves up
--   to 30 behind. §2(c) separates the two.

-- §2(c), ADDED AFTER THE START (22:31 UTC, run at sim 8:35 AM): §2(b)'s prediction assumed a parking hold is booked for
--   12-17 minutes, as on 394e1e83. On this run temp holds are booked for 30 (one perimeter hold for 120), so a car that
--   leaves inside its ORIGINAL window leaves up to 30 minutes behind, which is G195 as it stood before 0500. The part
--   0500 owns is the renewed holds. `why` records each hold's booked window ("temp_hold 13:33-14:03", to the minute),
--   so a renewed hold is one whose window now ends more than a minute after that.
\echo '=== 0372 §2(c) — §2(b) split by renewed and as booked, and every parking hold of the run so far ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
h AS (
  SELECT b.*, r.t,
         (date_trunc('day', lower(b.during)) + (substring(b.why from '\d\d:\d\d-(\d\d:\d\d)'))::time) AS booked_end
    FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.run
   WHERE b.purpose IN ('temp_hold','perimeter_hold'))
SELECT 'after departure' AS what, h.purpose, (upper(h.during) > h.booked_end + interval '1 minute') AS renewed,
       count(*) AS holds, round(sum(EXTRACT(epoch FROM upper(h.during) - h.t) / 60)::numeric) AS stall_min_left,
       round(max(EXTRACT(epoch FROM upper(h.during) - h.t) / 60)::numeric, 1) AS max_min_left
  FROM h JOIN public.stalls s ON s.id = h.stall_id AND s.stall_type::text = 'staging'
  JOIN public.vehicles v ON v.id = h.vehicle_id
 WHERE h.state = 'active' AND h.during @> h.t
   AND s.current_vehicle_id IS DISTINCT FROM h.vehicle_id AND v.current_stall_id IS DISTINCT FROM h.stall_id
 GROUP BY 1, 2, 3
UNION ALL
SELECT 'all holds so far', h.purpose, (upper(h.during) > h.booked_end + interval '1 minute'), count(*), NULL, NULL
  FROM h GROUP BY 1, 2, 3
 ORDER BY 1, 2, 3;
-- A first cut compared the window's end, which carries seconds, with the `why` end, which does not: all 92 holds
--   read renewed. The one-minute tolerance is what separates them.
-- READ, live (holds still live after their car left; as booked / renewed by 0500):
--     sim  8:35 AM   temp as booked 14 (64 stall-min, max 20.6 left)   renewed 5 (28, max 5.6)    perimeter 1 (112)
--          9:31 AM   temp as booked 10 (95, max 13.0)                  renewed 1 (max 11.1)       perimeter 1 (57)
--          9:48 AM   temp as booked  2 (13, max 11.5)                  renewed 0                  perimeter 1 (39.9)
--         10:52 AM   temp as booked  2 (8, max 5.4)                    renewed 1 (8, max 8.5)
--         11:21 AM   temp as booked  2 (14, max 13.2)                  renewed 1 (13, max 13.2)   perimeter 1 (81.2)
--         11:40 AM   temp as booked  2 (43, max 26.0)                  renewed 2 (18, max 9.5)    perimeter 1 (62.5)
--   Every renewed hold had at most 13.2 minutes left after its car left, inside the 15 predicted. Parking holds by 11:40
--   AM: temp 145 as booked + 118 renewed, perimeter 10.
--   Over the whole run (read after the stop, from each hold's car's departure event): renewed temp holds outlived their
--   car 53 times, 409 stall-minutes, p50 7.8, max 14.4; temp holds as booked 118 times, 1,836 stall-minutes, p50 14.1,
--   max 33.1; perimeter holds 6 times, 631 stall-minutes, p50 118.5. So 0500's share is 409 of 2,876 stall-minutes, and
--   G195's staging half (as-booked windows and perimeter holds) is the rest: about 11% of the 25,425 staging
--   stall-minutes the run had (113 stalls x 225 sim-minutes). Staging never filled on this run (64 of 113 in use at
--   10:31 AM), so this cost calendar truth rather than a car's place.

\echo '=== 0372 §2(c), second query (added after the stop) — parking holds that outlived their car, over the whole run ==='
WITH r AS (SELECT sim_run_id AS run, sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
h AS (
  SELECT b.*, (date_trunc('day', lower(b.during)) + (substring(b.why from '\d\d:\d\d-(\d\d:\d\d)'))::time) AS booked_end
    FROM public.ottoq_stall_bookings b JOIN r ON b.sim_run_id = r.run
   WHERE b.purpose IN ('temp_hold','perimeter_hold')),
x AS (
  SELECT h.*, (upper(h.during) > h.booked_end + interval '1 minute') AS renewed,
         (SELECT min(e.sim_clock_at) FROM public.ottoq_events e, r
           WHERE e.sim_run_id = r.run AND e.entity_id = h.vehicle_id AND e.event_type = 'vehicle.state_changed'
             AND e.payload->'diff'->'current_stall_id'->>'from' = h.stall_id::text
             AND e.sim_clock_at > lower(h.during)) AS left_at
    FROM h),
y AS (
  SELECT x.*, EXTRACT(epoch FROM LEAST(upper(during), COALESCE(released_at, 'infinity'::timestamptz), (SELECT t FROM r))
                                 - left_at) / 60 AS m
    FROM x WHERE left_at < upper(during) AND left_at < COALESCE(released_at, 'infinity'::timestamptz))
SELECT x.purpose, x.renewed, count(*) AS holds,
       (SELECT count(*) FROM y WHERE y.purpose = x.purpose AND y.renewed = x.renewed) AS outlived_their_car,
       (SELECT round(sum(m)::numeric) FROM y WHERE y.purpose = x.purpose AND y.renewed = x.renewed) AS stall_min_after_car_left,
       (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY m))::numeric, 1) FROM y
         WHERE y.purpose = x.purpose AND y.renewed = x.renewed) AS p50_min,
       (SELECT round(max(m)::numeric, 1) FROM y WHERE y.purpose = x.purpose AND y.renewed = x.renewed) AS max_min
  FROM x GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (after the stop): perimeter_hold as booked 10 holds, 6 outlived their car, 631 stall-minutes, p50 118.5, max
--   119.6; temp_hold as booked 148, 118, 1,836, p50 14.1, max 33.1; temp_hold renewed 118, 53, 409, p50 7.8, max 14.4.
--   The figures quoted in the READ above.

-- ══ §3 G233 (0501): THE WAIT FOR A CHARGER, BESIDE KPI 5 ═════════════════════════════════════════════════════════

\echo '=== 0372 §3 — the companion, and KPI 5 beside it ==='
SELECT public.ottoq_kpi_charge_wait(:'run') AS charge_wait,
       public.ottoq_kpi_five(:'run')->>'p95_time_to_service_min' AS kpi5_p95_min;
-- BEFORE 394e1e83: 135 visits owing a charge, 92 charged (p50 16.2, p95 154.4 minutes), 42 waiting at the stop, p95
--   floor 198.2; KPI 5 p95 0.7.
-- READ at the stop (sim 11:44 AM, tick 412): 139 visits owing a charge, 92 charged (p50 8.4, p95 98.5, max 175.1
--   minutes), 47 still waiting (p50 117.2, max 224.8 so far), none closed without a session; p95 floor 156.2. KPI 5 p95
--   27.6 (p50 0.4; 113 returns measured, 16 unserved).
--   Live (visits / waiting / floor / KPI 5): 9:31 AM 80/23/49.6/6.4; 9:48 AM 101/38/58.9/7.0; 10:52 AM 130/48/119.0/9.0;
--   11:21 AM 135/48/146.9/20.1; 11:40 AM 139/48/155.8/27.6.
--   KPI 5 read 27.6 against 0.7 on 394e1e83, and it is the need mix, not a change in the queue: 8 returns on this run had
--   the charge itself as their first operation and so waited for it (6 over 30 minutes, the L2 ones 75.8 on average),
--   while a car with a cabin, inspect or digital task starts that at once. The same queue moves KPI 5 or not; the
--   companion counts every car owing a charge. Every charger that could charge was charging: at 10:43 AM the 4 with no
--   session were all OCPP `Faulted` (DCFC-03 since 8:14 AM, L2-09 8:49, L2-31 9:38, L2-14 9:56).
--   The cockpits show it under the five (§7).

\echo '=== 0372 §3, second query (added after the stop) — KPI 5 by the first operation after each return ==='
WITH pairs AS (
  SELECT d.actual_return_at,
         (SELECT l.leg_type FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id AND l.leg_type <> ALL (ARRAY['taxi','stage'])
             AND l.actual_start_sim >= d.actual_return_at ORDER BY l.actual_start_sim LIMIT 1) AS first_leg,
         (SELECT min(l.actual_start_sim) FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id AND l.leg_type <> ALL (ARRAY['taxi','stage'])
             AND l.actual_start_sim >= d.actual_return_at) AS first_op
    FROM public.ottoq_vehicle_dispatches d JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
   WHERE d.sim_run_id = :'run' AND d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock_current)
SELECT CASE WHEN first_op IS NULL THEN 'none' WHEN EXTRACT(epoch FROM first_op - actual_return_at) / 60 < 2 THEN 'a <2 min'
            WHEN EXTRACT(epoch FROM first_op - actual_return_at) / 60 < 10 THEN 'b 2-10'
            WHEN EXTRACT(epoch FROM first_op - actual_return_at) / 60 < 30 THEN 'c 10-30' ELSE 'd 30+' END AS band,
       first_leg, count(*) AS returns,
       round(avg(EXTRACT(epoch FROM first_op - actual_return_at) / 60)::numeric, 1) AS avg_min
  FROM pairs GROUP BY 1, 2 ORDER BY 1, 3 DESC;
-- READ (after the stop): under 2 minutes 97 (inspect 51, charge_l2 23, charge_dcfc 6, interior_tidy 6, the rest 11);
--   2-10 minutes 8; 10-30 minutes 2 (charge_l2 25.6, charge_dcfc 11.9); 30+ minutes 6, all charges (charge_l2 5 at
--   75.8 on average, charge_dcfc 1 at 33.5); none 19.

-- ══ §4 WHAT 0486-0495 ALREADY HELD, STILL HOLDING ═════════════════════════════════════════════════════════════════

\echo '=== 0372 §4 — ticks lost, and gate moves outside the tick ==='
SELECT count(*) AS failed_ticks FROM public.ottoq_events e
 WHERE e.sim_run_id = :'run' AND e.event_type = 'sim_tick_failed';
-- BEFORE 394e1e83: 0.
-- READ: 0, at every live reading and at the stop.

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
-- READ (no fix is in force for G232; this is its second reading): 98 done. 10 started at a charger (charging_l2 5,
--   charging_dcfc 5). 81 started while the car was `arrived_at_gate` in a staging stall: 14 in the arrival_inspection
--   zone and 67 in the zones a car waiting for a charger is parked in (staging_south 29, staging_east 14, staging_buffer
--   14, staging_north 5, staging_west 5). The other 7: staged for departure 4, awaiting service 2, in a service bay 1.
--   The same shape as 394e1e83 (12 of 127 at a charger).
--   Against the plan, by the query below (itinerary `inspect` legs split by the atom each serves; a first cut here
--   counted every `inspect` leg, the end-of-visit readiness check included, and read "34 of 103, p50 21.4 late"):
--   interior inspections that started, 89: the 24 planned inside their car's charge window started a p50 of 37.8
--   minutes late (13 of them 30+, p95 106.0), the 65 planned outside it a p50 of 3.0 minutes early (7 of them 30+
--   late). Readiness checks that started: 14, 3 of them 30+ late. (0368 §12's "30 of 109, p95 33" on 394e1e83 came from
--   a query not kept in that file, so the two are not the same count.) G232 stands: inspections run where the car
--   waits, and the plan dates them inside a charge that starts late.
-- CORRECTION (0374, read on b0fdc92b before it was purged): the last sentence is wrong. The lateness above is the
--   leg's record, not the inspection. Matched to their atoms, the inspections started on plan (a median 0.0 minutes
--   late). `ottoq_close_atom_leg` looked for a leg of type `interior_inspection`, which does not exist (the leg is
--   `inspect`, tagged with its atom), so no inspection ever closed its own leg. 26 of the 91 done interior legs were
--   closed by the car's readiness check hours later, and those are the late ones: the 25 the lane never booked read a
--   median 67.1 minutes late, while their inspections started a median 0.0. The other 65 were closed by the
--   inspection lane's booking. Fixed by 0504.

\echo '=== 0372 §5, second query (added after the stop) — inspect legs by the atom they serve, planned inside a charge or not ==='
WITH i AS (
  SELECT l.*, l.duration_basis->>'atom' AS atom,
         EXTRACT(epoch FROM l.actual_start_sim - l.planned_start_sim) / 60 AS late_min,
         EXISTS (SELECT 1 FROM public.ottoq_itinerary_legs c
                  WHERE c.sim_run_id = l.sim_run_id AND c.itinerary_id = l.itinerary_id
                    AND c.leg_type IN ('charge_dcfc','charge_l2')
                    AND l.planned_start_sim >= c.planned_start_sim AND l.planned_start_sim < c.planned_end_sim) AS inside_charge
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect')
SELECT atom, inside_charge, count(*) AS legs, count(*) FILTER (WHERE actual_start_sim IS NOT NULL) AS started,
       count(*) FILTER (WHERE late_min >= 30) AS late_30_plus,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY late_min))::numeric, 1) AS p50_late_min,
       round((percentile_cont(0.95) WITHIN GROUP (ORDER BY late_min))::numeric, 1) AS p95_late_min
  FROM i GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: interior_inspection outside a charge 92 legs, 65 started, 7 late 30+, p50 -3.0, p95 111.8; inside a charge 43
--   legs, 24 started, 13 late 30+, p50 37.8, p95 106.0; readiness_check outside 83 legs, 4 started, 0 late, inside 59
--   legs, 10 started, 3 late 30+. Most readiness checks had not started when the run stopped.
-- CORRECTION (0374): false. 43 readiness checks were done. Their legs record 14, because 26 of the 43 closed an
--   interior inspection's leg instead and 3 found no open inspect leg. A leg counts what was recorded, not what was
--   performed.

-- ══ §6 SEEN ON THE RUN, NOT PREDICTED: THE REACTOR'S PARKING HOLDS (G235) ══════════════════════════════════════════
--
--   Found tracing staging stalls reserved for cars sitting elsewhere (sim 10:09 AM: 9 of them). Most were the charge
--   step's short hold "until a charger frees", released within a decide tick once the car went to charge. The ones that
--   stayed were holds the refusal reactor booked.

\echo '=== 0372 §6(a) — the refusal reactor''s parking holds, and whether their car ever came ==='
SELECT b.booked_by, b.state || ' / ' || COALESCE(b.release_reason, '-') AS closed,
       (SELECT e.payload->'diff'->'current_state'->>'to' FROM public.ottoq_events e
         WHERE e.sim_run_id = b.sim_run_id AND e.entity_id = b.vehicle_id AND e.event_type = 'vehicle.state_changed'
           AND e.payload->'diff' ? 'current_state' AND e.sim_clock_at <= b.booked_at_sim
         ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1) AS car_state_at_booking,
       EXISTS (SELECT 1 FROM public.ottoq_events e
                WHERE e.sim_run_id = b.sim_run_id AND e.entity_id = b.vehicle_id AND e.event_type = 'vehicle.state_changed'
                  AND e.payload->'diff'->'current_stall_id'->>'to' = b.stall_id::text
                  AND e.sim_clock_at >= lower(b.during) - interval '1 minute' AND e.sim_clock_at < upper(b.during)) AS car_came,
       count(*) AS holds,
       round(sum(EXTRACT(epoch FROM LEAST(COALESCE(b.released_at, upper(b.during)), upper(b.during)) - lower(b.during)) / 60))
         AS stall_minutes
  FROM public.ottoq_stall_bookings b
 WHERE b.sim_run_id = :'run' AND b.booked_by LIKE 'otto_q_reaction%' AND b.purpose IN ('temp_hold','perimeter_hold')
 GROUP BY 1, 2, 3, 4 ORDER BY 5 DESC;
-- READ: 7 holds, all `otto_q_reaction`, all booked while the car was `en_route_to_depot`, and the car came to none:
--   4 closed `window_elapsed` after their full 60 minutes, 3 at the stop; 322 stall-minutes. Each follows the same
--   refusal: the recall's appointment (`stage`, `appointment: true`) was refused `target_occupied`, and
--   `ottoq.ottoq_react_to_refusals` rerouted it with an hour's reservation and a 60-minute `temp_hold` on a free stall.
--   The car arrived 1-2 minutes later and was placed by the inspection seam (3, on I008/I009/I012) or by the charge
--   step's parking hold (4, on S017, S027, B010, N004), and neither looks at the hold the car already has:
--   `ottoq_record_enacted_booking` releases sibling holds of the SAME purpose only (an `inspect` booking leaves a
--   `temp_hold`), and `ottoq.ottoq_book_hold_stall` releases none. Across every run started in the 8 hours before the
--   read (canon arms included), the reactor booked 192 parking holds (152 for cars en route, 40 for cars at the gate)
--   and not one was ever activated. G235.

\echo '=== 0372 §6(b) — recall appointments: did the car go to the stall it was given? ==='
SELECT c.status, c.payload ? 'reroute_reason' AS rerouted, count(*) AS appointments,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_events e
          WHERE e.sim_run_id = c.sim_run_id AND e.entity_id = c.vehicle_id AND e.event_type = 'vehicle.state_changed'
            AND e.payload->'diff'->'current_stall_id'->>'to' = c.payload->>'stall_id'
            AND e.sim_clock_at >= c.issued_at AND e.sim_clock_at < c.issued_at + interval '90 minutes')) AS car_went_there
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = :'run' AND c.command_type = 'stage' AND (c.payload->>'appointment')::boolean
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- READ: executed and not rerouted 81, the car at the appointed stall within 90 minutes in 30; rerouted 7, in 0; refused
--   7, in 1. So an appointment the gate accepts is kept about a third of the time, and the arrival flow places the car on
--   its own; an appointment the gate refuses is rerouted onto a hold that is never kept. Recorded with G235; why the
--   arrival flow does not start from the appointment is not established here.

-- ══ §7 THE COCKPITS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin cockpit (ottoyarddepot-sim#110's head on :8080), PULSE and OrchestrAV (their PR heads on :8081 and :8082,
--   each through its local live-harness page), all on this run.
--   - Started from Control at 5:24 PM CT (busy_day, 8x); stopped from Control at 5:52 PM CT (sim 11:44 AM, 412 ticks,
--     `operator_stop`). The cockpit landed on Runs with the run first: 3h 45m sim, 412 ticks, 143 dispatches, 103
--     charges, 7 faults, and seed 2489361993912108160 printed exactly (0497's text seed, live).
--   - 2D and 3D render at sim 9:13-9:22 AM and 10:31-10:39 AM. At 10:31 (t277) the 2D map read DCFC 9/10 and L2 27/30 in
--     use, staging 64/113, 63 waiting.
--   - The row 0501 added, "Wait for a charger, p95", under the five:
--       twin KPIs tab, sim 9:13 AM      45.8 min · at least: 19 still waiting, the longest 72 · p50 8.2 over 46 charged
--       PULSE Performance, ~9:00 AM     43.4 min · 19 waiting, longest 59 · p50 8.2 over 40 charged; KPI 5 1.9
--       OrchestrAV Performance, ~9:05   42.3 min · 20 waiting, longest 64 · p50 8.2 over 42 charged; KPI 5 1.8
--       twin KPIs tab, 10:31 AM         96.4 min · at least: 51 still waiting, the longest 149 · p50 8.2 over 74 charged;
--                                       KPI 5 8.1
--       PULSE and OrchestrAV, ~10:30    94.1 min · 49 waiting, longest 146 · p50 8.2 over 74 charged; KPI 5 8.3
--     Each read the same function a few sim-minutes apart, so the figures move between reads; none showed "undefined" or
--     an empty row.
--   - The Control tab's "Arrival / dispatch rate" slider still carries "engine support coming": a disabled placeholder.
