-- 0367  **0493: the charge step never read the emission gate's answer, the gate intake took a car the charge step had
--       just sent to a charger, and a car on a charger kept its hold on another.**
--
--       Three findings from tracing G210 on the canon under 0492 (verdicts 375-383) and operator run 461c79fa:
--         G226  (3)'s begin_charge refused at the emission gate was logged enacted, and its booking superseded the
--               booking that had refused it (0493 a)
--         G210  what remained of it: (3) charged at the visit target minus 1, where the deriver and (3b) did not (0493 b)
--         G195  in part: a car put on a charger kept its forward charge booking on another (0493 c)
--       Read-only queries below. Times are UTC in the data and CT (CDT, UTC-5) in the prose.

-- ══ §1 G226: THE CHARGE STEP NEVER READ THE EMISSION GATE'S ANSWER ═════════════════════════════════════════════
--
--   `ottoq_decide_tick` (3) reserves the proposal's charger and emits `begin_charge` with PERFORM, then claims the kW,
--   starts the concurrent atoms, plans the itinerary, calls `ottoq.ottoq_record_enacted_booking` and logs `enacted`.
--   `ottoq.ottoq_emit_vehicle_command` refuses, pre-flight, whatever `ottoq_validate_assignment` refuses, and records the
--   refusal (`confirmed_by = 'otto_q_preflight'`). The reservation pointer and the calendar are separate gates (CLAUDE.md
--   Part 3), so a charger with no reservation can still hold another car's booking.

\echo '=== 0367 §1(a) — (3)''s own begin_charge, refused at the emission gate, per arm ==='
WITH runs AS (
  SELECT v.verdict_id::text AS label, v.ticks, a.arm, a.run
    FROM public.ottoq_determinism_verdict_ledger v
    CROSS JOIN LATERAL (VALUES ('A', v.arm_a_run), ('B', v.arm_b_run)) a(arm, run)
   WHERE v.verdict_id BETWEEN 375 AND 383
  UNION ALL
  SELECT 'op:' || left(r.sim_run_id::text, 8), NULL, '-', r.sim_run_id FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id::text LIKE '461c79fa%'
)
SELECT r.label, r.ticks, r.arm,
       count(*) AS decide_begin_charge,
       count(*) FILTER (WHERE c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused') AS refused_at_gate,
       count(*) FILTER (WHERE c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused'
                          AND EXISTS (SELECT 1 FROM public.ottoq_decisions d
                                       WHERE d.sim_run_id = c.sim_run_id AND d.entity_id = c.vehicle_id AND d.sim_clock = c.issued_at
                                         AND d.resolved_action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
                                         AND d.enacted_action->>'stall_id' = c.payload->>'stall_id')) AS logged_enacted
  FROM runs r JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.run
 WHERE c.command_type = 'begin_charge' AND NOT (c.payload ? 'reroute_reason')
 GROUP BY 1, 2, 3 ORDER BY 1, 3;
-- READ (2026-09-26, 18:15 UTC), arms A and B identical on every column:
--   6 ticks: 375 1 of 3, 376 0 of 2 | 12 ticks: 377 22 of 116, 378 21 of 121, 379 30 of 128, 380 19 of 114
--   24 ticks: 381 22 of 130, 382 31 of 141 | 48 ticks: 383 57 of 217 | 461c79fa: 5 of 75.
--   logged_enacted equals refused_at_gate on every row. Every refusal reads `target_occupied`, `calendar booking held
--   by <car>`.

\echo '=== 0367 §1(b) — what the refused decision did to the booking that refused it (verdict 383 arm A, 461c79fa) ==='
WITH runs AS (
  SELECT '383A' AS label, arm_a_run AS run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 383
  UNION ALL SELECT '461c79fa', sim_run_id FROM public.ottoq_sim_runs WHERE sim_run_id::text LIKE '461c79fa%'
), blk AS (
  SELECT r.label, c.sim_run_id, c.vehicle_id, c.issued_at, (c.payload->>'stall_id')::uuid AS stall,
         (regexp_match(c.reason_detail, 'held by ([0-9a-f-]{36})'))[1]::uuid AS blocker
    FROM runs r JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.run
   WHERE c.command_type = 'begin_charge' AND c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused'
     AND NOT (c.payload ? 'reroute_reason') AND c.reason_detail LIKE 'calendar booking held by %'
)
SELECT b.label, count(*) AS refused,
       count(*) FILTER (WHERE bb.state = 'superseded' AND bb.released_at = b.issued_at
                          AND bb.release_reason = 'superseded_by_enacted_decision') AS blocker_superseded_that_instant,
       count(*) FILTER (WHERE mb.booking_id IS NOT NULL) AS refused_car_booked_on_the_charger
  FROM blk b
  LEFT JOIN LATERAL (SELECT * FROM public.ottoq_stall_bookings x
                      WHERE x.sim_run_id = b.sim_run_id AND x.stall_id = b.stall AND x.vehicle_id = b.blocker
                        AND x.during @> b.issued_at ORDER BY lower(x.during) DESC LIMIT 1) bb ON true
  LEFT JOIN LATERAL (SELECT * FROM public.ottoq_stall_bookings y
                      WHERE y.sim_run_id = b.sim_run_id AND y.stall_id = b.stall AND y.vehicle_id = b.vehicle_id
                        AND lower(y.during) = b.issued_at LIMIT 1) mb ON true
 GROUP BY 1 ORDER BY 1;
-- READ: 383A 57 refused, 55 blockers superseded that instant, 54 refused cars booked on the charger they were refused.
--   461c79fa 5, 5, 5. The blocker almost never came for that charger afterwards (1 of 57, 0 of 5), because the blocking
--   booking was itself a phantom (§3).
--
--   The rolled-back probe (0493's body without P0, then the tail at the end of §3, in one transaction ending in RAISE) on the
--   stopped run 461c79fa, whose 116 cars were all offline with no live booking. Car A at the gate at 5% holds a
--   reservation on L2 s1, and car B holds s1 on the calendar from 5 minutes before the run's clock. Same tail against
--   the live body first:
--     OLD  A: decision enacted/assign_stall | cmd refused/target_occupied | B's booking superseded/superseded_by_enacted_decision
--          | A booked on s1 1 | s1 reserved by A.  A's reroute: issued to l2
--     NEW  A: decision deferred_stale_entity/charger_refused/target_occupied | cmd refused/target_occupied | B's booking
--          held | A booked on s1 0 | s1 reserved by nobody.  A's reroute: issued to l2
--   The reactor still puts A on another L2 in the same pass.

-- ══ §2 G210: WHAT REMAINED OF IT ═══════════════════════════════════════════════════════════════════════════════
--
--   A tick that sent one car to two different stalls, from two decide-path writers. On the canon under 0492 the only
--   such pair left was (3)'s begin_charge with (3b)'s gate intake. Every other two-stall tick was a refusal and its
--   reroute in the same pass (the reactor working).

\echo '=== 0367 §2 — (3) and (3b) on the same car in the same tick, and where the car stood ==='
WITH runs AS (
  SELECT v.verdict_id AS vid, v.arm_a_run AS run FROM public.ottoq_determinism_verdict_ledger v WHERE v.verdict_id BETWEEN 375 AND 383
  UNION ALL SELECT 0, sim_run_id FROM public.ottoq_sim_runs WHERE sim_run_id::text LIKE '461c79fa%'
)
SELECT r.vid, left(c.vehicle_id::text, 8) AS car, to_char(c.issued_at, 'HH24:MI') AS tick,
       jsonb_path_query_first(d.context_frame, '$.current_soc') AS soc,
       (SELECT vn.target_soc FROM public.ottoq_visit_needs vn WHERE vn.sim_run_id = c.sim_run_id AND vn.vehicle_id = c.vehicle_id
         ORDER BY vn.created_at DESC LIMIT 1) AS visit_target,
       EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands n WHERE n.sim_run_id = c.sim_run_id AND n.vehicle_id = c.vehicle_id
                 AND n.command_type = 'begin_charge' AND n.issued_at > c.issued_at
                 AND n.issued_at <= c.issued_at + interval '3 hours') AS charged_within_3h
  FROM runs r
  JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.run
  LEFT JOIN public.ottoq_decisions d ON d.sim_run_id = c.sim_run_id AND d.entity_id = c.vehicle_id AND d.sim_clock = c.issued_at
                                    AND d.resolved_action_context = 'stall_assignment' AND d.proposed_action ? 'stall_id'
 WHERE c.command_type = 'begin_charge' AND c.confirmed_by = 'otto_q_preflight_supersede'
   AND EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands i WHERE i.sim_run_id = c.sim_run_id AND i.vehicle_id = c.vehicle_id
                 AND i.issued_at = c.issued_at AND i.payload->>'reason' = 'gate_intake')
 ORDER BY 1, 3;
-- READ: on the canon, 1-2 pairs an arm (377 1, 378 2, 379 1, 380 1, 381 2, 382 1, 383 2), every car at 84% against an
--   immediate-dispatch visit target of 85 with no charge atom, and none charged within three hours. The door
--   (`twin.ottoq_sim_confirm_commands`) kept the intake: on a tie of issued_at it orders by command type, and
--   'proceed_to_stall' sorts after 'begin_charge'. On 461c79fa the one pair was a car at 60% against 85 whose visit had
--   been derived from 97% with no charge (G219, before 0486).
--
--   The same probe: car G at the gate at 84 with an immediate-dispatch visit targeting 85 and no charge atom, and car H
--   at 50 with the same visit (the re-assessment is not run in the probe, which isolates the intake guard).
--     OLD  G: begin_charge:issued + proceed_to_stall:issued:gate_intake | H: begin_charge:issued + proceed_to_stall:issued:gate_intake
--     NEW  G: proceed_to_stall:issued:gate_intake                       | H: begin_charge:issued

-- ══ §3 G195, IN PART: THE BOOKINGS THAT REFUSED (3) ═════════════════════════════════════════════════════════════

\echo '=== 0367 §3 — who held the booking that refused (3), and where that car had gone ==='
WITH runs AS (
  SELECT '383A' AS label, arm_a_run AS run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 383
  UNION ALL SELECT '461c79fa', sim_run_id FROM public.ottoq_sim_runs WHERE sim_run_id::text LIKE '461c79fa%'
), blk AS (
  SELECT r.label, c.sim_run_id, c.issued_at, (c.payload->>'stall_id')::uuid AS stall,
         (regexp_match(c.reason_detail, 'held by ([0-9a-f-]{36})'))[1]::uuid AS blocker
    FROM runs r JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.run
   WHERE c.command_type = 'begin_charge' AND c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused'
     AND NOT (c.payload ? 'reroute_reason') AND c.reason_detail LIKE 'calendar booking held by %'
), bb AS (
  SELECT b.*, x.booked_by, x.purpose
    FROM blk b
    JOIN LATERAL (SELECT x.booked_by, x.purpose FROM public.ottoq_stall_bookings x
                   WHERE x.sim_run_id = b.sim_run_id AND x.stall_id = b.stall AND x.vehicle_id = b.blocker
                     AND x.during && tstzrange(b.issued_at, b.issued_at + interval '1 minute')
                   ORDER BY lower(x.during) DESC LIMIT 1) x ON true
)
SELECT label, booked_by, purpose,
       COALESCE((SELECT CASE WHEN o.payload ? 'reroute_reason' THEN 'charging elsewhere by a reroute on '
                             ELSE 'charging elsewhere by (3) on ' END
                        || (SELECT s.stall_type::text FROM public.stalls s WHERE s.id = (o.payload->>'stall_id')::uuid)
                   FROM public.ottoq_vehicle_commands o
                  WHERE o.sim_run_id = bb.sim_run_id AND o.vehicle_id = bb.blocker AND o.command_type = 'begin_charge'
                    AND o.status = 'executed' AND o.issued_at <= bb.issued_at AND o.payload->>'stall_id' <> bb.stall::text
                  ORDER BY o.issued_at DESC, o.command_seq DESC LIMIT 1), 'not charging anywhere') AS blocker_was,
       count(*)
  FROM bb GROUP BY 1, 2, 3, 4 ORDER BY 1, 5 DESC;
-- READ, 383A (57): booked_by `otto_q_enacted` 22, of which 21 carry an earlier (3) begin_charge refused at the gate
--   (§1) at the booking's start and 1 has no command there. booked_by `otto_q` 35, the itinerary's
--   forward charge bookings ("NASH-L2-STALL-18 charge_l2 13:17-13:50 to satisfy ..."): 22 for a car (3) had put on the
--   other type (13 L2 held while on a DCFC, 9 DCFC held while on an L2), 5 for a car a reroute had put on a charger,
--   8 for a car not charging anywhere. 461c79fa (5): all `otto_q` L2 bookings, 4 held while the car was on a DCFC.
--   `ottoq_record_enacted_booking` released only same-purpose siblings, and the reactor's reroute released none.
--
--   The same probe: car K holds a forward charge_dcfc booking and is put on an L2 through the enacted-booking seam, car
--   R holds a forward charge_l2 booking and its refused DCFC begin_charge is rerouted.
--     OLD  K: held | R: forward held, reroute issued to dcfc
--     NEW  K: superseded/superseded_by_enacted_other_charger | R: forward superseded/superseded_by_reroute, reroute issued
--
--   The probe behind §1-§3, verbatim (cars a, b, g, h, k, r are the depot's first six autonomous vehicles by id):
--   DO $probe$
--   DECLARE
--     v_run uuid := '461c79fa-6f85-467f-b90a-92b33d40728d';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_clock timestamptz;
--     v_cars uuid[];
--     a uuid; b uuid; g uuid; h uuid; k uuid; r uuid;
--     s1 uuid; s5 uuid; f uuid; d1 uuid; d2 uuid;
--     v_bk_b uuid; v_bk_k uuid; v_bk_r uuid;
--     r_k text; r_r text; r_a text; r_a2 text; r_g text; r_h text; r_body text;
--   BEGIN
--     SELECT sim_clock_current INTO v_clock FROM ottoq_sim_runs WHERE sim_run_id = v_run;
--     SELECT array_agg(id ORDER BY id) INTO v_cars
--       FROM (SELECT id FROM vehicles WHERE home_depot_id = v_depot AND category = 'autonomous' ORDER BY id LIMIT 6) x;
--     a := v_cars[1]; b := v_cars[2]; g := v_cars[3]; h := v_cars[4]; k := v_cars[5]; r := v_cars[6];
--     r_body := CASE WHEN position('0493 (G226)' IN pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) > 0
--                    THEN 'NEW' ELSE 'OLD' END;
--
--     -- every charger at the depot answering and available, every charge stall free
--     UPDATE ottoq_ocpp_chargers c SET station_state = 'Available', last_heartbeat_at = v_clock
--       FROM stalls s WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = v_depot;
--     UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
--      WHERE depot_id = v_depot AND stall_type IN ('l2','dcfc');
--     SELECT s.id INTO s1 FROM stalls s WHERE s.depot_id = v_depot AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
--     SELECT s.id INTO s5 FROM stalls s WHERE s.depot_id = v_depot AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id OFFSET 1 LIMIT 1;
--     SELECT s.id INTO f  FROM stalls s WHERE s.depot_id = v_depot AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id OFFSET 2 LIMIT 1;
--     SELECT s.id INTO d1 FROM stalls s WHERE s.depot_id = v_depot AND s.stall_type = 'dcfc' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
--     SELECT s.id INTO d2 FROM stalls s WHERE s.depot_id = v_depot AND s.stall_type = 'dcfc' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id OFFSET 1 LIMIT 1;
--
--     -- K: a forward DCFC booking, then the car is put on an L2 through the enacted-booking seam
--     v_bk_k := ottoq.ottoq_book_stall(v_run, d1, k, 'charge_dcfc', v_clock + interval '10 minutes', v_clock + interval '40 minutes', NULL, NULL, 'otto_q');
--     PERFORM ottoq.ottoq_record_enacted_booking(v_run, s5, k, v_clock, NULL, v_clock, v_clock + interval '30 minutes', NULL, 'probe0493');
--     SELECT state || '/' || COALESCE(release_reason, '-') INTO r_k FROM ottoq_stall_bookings WHERE booking_id = v_bk_k;
--
--     -- R: a forward L2 booking and a refused begin_charge to a DCFC, then the reactor
--     UPDATE vehicles SET current_state = 'staged_awaiting_service', current_stall_id = NULL, current_soc = 99.5 WHERE id = r;
--     v_bk_r := ottoq.ottoq_book_stall(v_run, f, r, 'charge_l2', v_clock + interval '10 minutes', v_clock + interval '40 minutes', NULL, NULL, 'otto_q');
--     INSERT INTO ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at,
--                                        status, reason_code, reason_detail, confirmed_at, confirmed_by)
--     VALUES (v_run, v_depot, r, 'begin_charge', jsonb_build_object('stall_id', d2, 'stall_type', 'dcfc', 'new_state', 'charging_dcfc'),
--             v_clock, 'refused', 'target_occupied', 'probe0493', v_clock, 'otto_q_preflight');
--     PERFORM ottoq.ottoq_react_to_refusals(v_run, v_depot, v_clock);
--     SELECT 'forward ' || (SELECT state || '/' || COALESCE(release_reason, '-') FROM ottoq_stall_bookings WHERE booking_id = v_bk_r)
--            || ' | reroute ' || COALESCE((SELECT c.status || ' to ' || (SELECT stall_type::text FROM stalls WHERE id = (c.payload->>'stall_id')::uuid)
--                                            FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.vehicle_id = r AND c.payload ? 'reroute_reason'), 'none')
--       INTO r_r;
--
--     -- A: at the gate, its reservation on L2 s1 honoured, while B holds s1 on the calendar
--     UPDATE vehicles SET current_state = 'arrived_at_gate', current_stall_id = NULL, current_soc = 5 WHERE id = a;
--     UPDATE stalls SET reserved_by = a, reserved_at = v_clock, reservation_expires_at = v_clock + interval '1 hour' WHERE id = s1;
--     v_bk_b := ottoq.ottoq_book_stall(v_run, s1, b, 'charge_l2', v_clock - interval '5 minutes', v_clock + interval '30 minutes', NULL, NULL, 'otto_q');
--
--     -- G: at the gate at 84 against an immediate-dispatch target of 85, no charge in its visit
--     UPDATE vehicles SET current_state = 'arrived_at_gate', current_stall_id = NULL, current_soc = 84 WHERE id = g;
--     INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency, target_soc, atoms, status)
--     VALUES (g, v_run, v_depot, v_clock, 'probe0493-g', 'M_pass_through_or_P_triage', 'immediate_dispatch', 85, '[]'::jsonb, 'open');
--     -- H: at the gate at 50 with no charge in its visit (the re-assessment is not run here, so this isolates the guard)
--     UPDATE vehicles SET current_state = 'arrived_at_gate', current_stall_id = NULL, current_soc = 50 WHERE id = h;
--     INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency, target_soc, atoms, status)
--     VALUES (h, v_run, v_depot, v_clock, 'probe0493-h', 'M_pass_through_or_P_triage', 'immediate_dispatch', 85, '[]'::jsonb, 'open');
--
--     PERFORM public.ottoq_decide_tick(v_run);
--
--     SELECT 'decision ' || COALESCE((SELECT d.outcome_status || '/' || COALESCE(d.enacted_action->>'verb', '-') || '/' || COALESCE(d.enacted_action->>'reason', '-')
--                                     FROM ottoq_decisions d WHERE d.sim_run_id = v_run AND d.entity_id = a AND d.sim_clock = v_clock
--                                       AND d.resolved_action_context = 'stall_assignment' LIMIT 1), 'none')
--         || ' | cmd ' || COALESCE((SELECT c.status || '/' || COALESCE(c.reason_code, '-') FROM ottoq_vehicle_commands c
--                                    WHERE c.sim_run_id = v_run AND c.vehicle_id = a AND c.command_type = 'begin_charge' AND NOT (c.payload ? 'reroute_reason') LIMIT 1), 'none')
--         || ' | B''s booking ' || COALESCE((SELECT state || '/' || COALESCE(release_reason, '-') FROM ottoq_stall_bookings WHERE booking_id = v_bk_b), 'missing')
--         || ' | A booked on s1 ' || (SELECT count(*) FROM ottoq_stall_bookings WHERE sim_run_id = v_run AND stall_id = s1 AND vehicle_id = a AND state IN ('held','active'))
--         || ' | s1 reserved by ' || (SELECT CASE WHEN reserved_by = a THEN 'A' WHEN reserved_by IS NULL THEN 'nobody' ELSE 'another car' END FROM stalls WHERE id = s1)
--       INTO r_a;
--     PERFORM ottoq.ottoq_react_to_refusals(v_run, v_depot, v_clock);
--     SELECT COALESCE((SELECT c.status || ' to ' || (SELECT stall_type::text FROM stalls WHERE id = (c.payload->>'stall_id')::uuid)
--                        FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.vehicle_id = a AND c.payload ? 'reroute_reason'), 'none')
--       INTO r_a2;
--
--     SELECT string_agg(c.command_type || ':' || c.status || ':' || COALESCE(c.payload->>'reason', '-'), ' + ' ORDER BY c.command_seq)
--       INTO r_g FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.vehicle_id = g AND c.issued_at = v_clock AND c.payload ? 'stall_id';
--     SELECT string_agg(c.command_type || ':' || c.status || ':' || COALESCE(c.payload->>'reason', '-'), ' + ' ORDER BY c.command_seq)
--       INTO r_h FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.vehicle_id = h AND c.issued_at = v_clock AND c.payload ? 'stall_id';
--
--     RAISE EXCEPTION E'PROBE0493 body=% clock=%\n K (forward DCFC, put on L2): %\n R (forward L2, rerouted): %\n A (reserved L2 booked by B): %\n A reroute: %\n G (84 vs 85, no charge atom): %\n H (50, no charge atom): %',
--       r_body, v_clock, r_k, r_r, r_a, r_a2, COALESCE(r_g, 'no stall command'), COALESCE(r_h, 'no stall command');
--   END $probe$;

-- ══ §4 NOT CHANGED BY 0493 ═════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The 8 forward bookings on 383A whose car had not charged anywhere may be the car's real plan.
--   (b) The appointment planner's pre-arrival commands (`plan` in the payload) meet the same gate. On 383A, 55 were
--   refused `target_occupied` at the emission gate (52 proceed_to_stall, 3 stage) and 24 of those were rerouted; 21 of
--   the 24 reroutes were then refused `vehicle_state_incompatible` (`otto_q_preflight_refusal`) because the car was still
--   on the road, and 3 expired at the run's end. A further 53 of the planner's proceed_to_stall were refused
--   `vehicle_state_incompatible` outright. Each reroute booked a charger for 60 minutes. The sibling release now retires
--   such a booking when the car takes another charger, but a planner that commands a car still on the road is its own
--   question, not this migration's.

\echo '=== 0367 §4 — the appointment planner''s commands and their reroutes (verdict 383 arm A) ==='
SELECT (c.payload ? 'reroute_reason') AS is_reroute, c.command_type, c.status, c.reason_code, c.confirmed_by, count(*),
       count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted') AS rerouted
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = (SELECT arm_a_run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 383)
   AND (c.payload ? 'plan' OR (c.payload ? 'reroute_reason' AND c.command_type = 'proceed_to_stall'))
 GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 6 DESC;
-- READ: planner: stage executed 54 | proceed_to_stall refused vehicle_state_incompatible otto_q_preflight_refusal 53 |
--   proceed_to_stall refused target_occupied otto_q_preflight 52 (24 rerouted) | proceed_to_stall expired 5 |
--   proceed_to_stall refused target_occupied otto_q_preflight_refusal 3 | stage refused target_occupied otto_q_preflight 3.
--   Reroutes: refused vehicle_state_incompatible otto_q_preflight_refusal 21, expired run_ended 3.

-- ══ §5 0493 APPLIED, AND THE CANON UNDER IT ════════════════════════════════════════════════════════════════════
--
--   0493 = 20260926183701 (1:37 PM CT), stored statement md5 d08912fd..., equal to the file's body. forces_recert TRUE.

\echo '=== 0367 §5(a) — the canon ==='
SELECT c.scenario, c.seed, c.ticks, c.verdict_id, c.certified_at, c.outcome, c.equal, c.disagreeing_atoms, c.status
  FROM public.ottoq_determinism_canon c
 WHERE c.enabled
 ORDER BY c.certified_at;
-- READ (19:06 UTC): all nine columns current under 0493, every one `passed` with no disagreeing atom, first attempt
--   each: verdicts 384-392, pairs started 18:38-18:56 UTC (1:38-1:56 PM CT).

\echo '=== 0367 §5(b) — §1(a) and the two-writer pairs on the arms certified under 0493 ==='
WITH runs AS (
  SELECT v.verdict_id, v.ticks, a.arm, a.run
    FROM public.ottoq_determinism_verdict_ledger v
    CROSS JOIN LATERAL (VALUES ('A', v.arm_a_run), ('B', v.arm_b_run)) a(arm, run)
   WHERE v.certified_at > '2026-09-26 18:37:01+00'
)
SELECT r.verdict_id, r.ticks, r.arm,
       count(*) FILTER (WHERE c.command_type = 'begin_charge' AND NOT (c.payload ? 'reroute_reason')) AS decide_begin_charge,
       count(*) FILTER (WHERE c.command_type = 'begin_charge' AND NOT (c.payload ? 'reroute_reason')
                          AND c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused') AS refused_at_gate,
       (SELECT count(*) FROM public.ottoq_decisions d WHERE d.sim_run_id = r.run AND d.resolved_action_context = 'stall_assignment'
           AND d.enacted_action->>'verb' = 'charger_refused') AS logged_charger_refused,
       count(*) FILTER (WHERE c.command_type = 'begin_charge' AND c.confirmed_by = 'otto_q_preflight_supersede'
                          AND EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands i WHERE i.sim_run_id = c.sim_run_id
                                        AND i.vehicle_id = c.vehicle_id AND i.issued_at = c.issued_at
                                        AND i.payload->>'reason' = 'gate_intake')) AS charge_and_intake_pairs
  FROM runs r JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.run
 GROUP BY 1, 2, 3, r.run ORDER BY 1, 3;
-- READ (19:06 UTC, all nine columns, arms A and B identical), (3)'s begin_charge issued / refused at
--   the gate, before under 0492 -> after under 0493, and cars charged in the arm:
--     grid_smoke/239001/6    3/1 -> 3/0      cars 2 -> 2    charge bookings   7 -> 6
--     grid_smoke/424242/6    2/0 -> 2/0      cars 2 -> 2    charge bookings   6 -> 6
--     busy_day/171717/12   116/22 -> 160/70  cars 88 -> 87  charge bookings 161 -> 118
--     busy_day/314159/12   121/21 -> 223/131 cars 92 -> 90  charge bookings 176 -> 129
--     busy_day/424242/12   128/30 -> 172/78  cars 96 -> 93  charge bookings 189 -> 136
--     normal_day/171717/12 114/19 -> 117/27  cars 88 -> 87  charge bookings 149 -> 120
--     busy_day/171717/24   130/22 -> 171/70  cars 90 -> 89  charge bookings 184 -> 139
--     busy_day/424242/24   141/31 -> 185/80  cars 98 -> 96  charge bookings 210 -> 157
--     busy_day/171717/48   217/57 -> 248/76  cars 110 -> 110 charge bookings 370 -> 260
--   charge_and_intake_pairs 0 on every arm; every refusal logged `charger_refused`, none `enacted`. 11-14 charge
--   holds released across types per 12-tick arm.
--   THE REFUSALS ROSE, and §6 is why. Every refusal on busy_day/171717/12 landed on one of 6 chargers, 22 of them on
--   one L2 in the 04:00 tick. The booking there belonged to a car whose planned charge began at 03:35 and which took
--   that L2 at 04:00: the calendar was right each time. Under 0492 the first car refused stole it; under 0493 the
--   reservation is released and the proposer offers the same charger to the next car.

-- ══ §6 G226, THE SECOND HALF: THE PROPOSER OFFERED A PROMISED CHARGER TO EVERY CAR (0494) ═══════════════════════
--
--   `public.ottoq_l2_propose_stall_assignment` (through `ottoq_honour_reservation_proposal`) builds its candidates from
--   the pointer and the charger's state only. A charger promised to an arriving car (the itinerary's forward booking for
--   its charge leg) looks free, so under 0493 each car in the cursor was offered it and refused in turn (§5(b)). 0494
--   adds the gate's own check to the candidate filter: `ottoq.ottoq_validate_assignment(car, stall, 'begin_charge',
--   clock, run)`, the call the emission gate makes next (0467 did the same for the gate intake).

\echo '=== 0367 §6(a) — refusals per charger per tick under 0493 (verdict 386 arm A) ==='
SELECT left((c.payload->>'stall_id'), 8) AS stall, to_char(c.issued_at, 'HH24:MI') AS tick, count(*) AS cars_refused
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = (SELECT arm_a_run FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 386)
   AND c.command_type = 'begin_charge' AND NOT (c.payload ? 'reroute_reason')
   AND c.confirmed_by = 'otto_q_preflight' AND c.status = 'refused'
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- READ: f99a8657 04:00 22, c1808c59 04:30 19, fbb3a3df 05:00 11, 254d40a1 04:30 11 and 04:00 5, and two chargers once.
--   f99a8657's booking was charge_l2 [03:35-04:25) for car 30892fc2, placed by the itinerary for its charge leg; the car
--   was staged at 03:30 and took that L2 at 04:00.
--
--   The rolled-back probe (0494's body without P0, then the tail below, in one transaction ending in RAISE) on the
--   stopped run 461c79fa, made the depot's running run for the transaction (the proposer finds its run by status).
--   Car A at the gate at 50% asks the proposer for a charger, car B then books that L2, and A asks again. Then three
--   more cars at the gate at 51-53% go through one decide tick. The same tail against the live body (0493) first:
--     OLD  proposer: c957b07b (l2), then c957b07b again after B booked it, the gate says ok=false
--          decide tick: begin_charge issued 0, refused at the gate 3, offered the promised L2 3
--     NEW  proposer: c957b07b (l2), then fbb3a3df (l2), the gate says ok=true
--          decide tick: begin_charge issued 3, refused at the gate 0, offered the promised L2 0
--   0494 = 20260926190651 (2:06 PM CT), stored statement md5 cb966902..., equal to the file's body. The tail, verbatim:
--   DO $probe$
--   DECLARE
--     v_run uuid := '461c79fa-6f85-467f-b90a-92b33d40728d';
--     v_depot uuid := '11111111-1111-1111-1111-111111111111';
--     v_clock timestamptz;
--     v_cars uuid[];
--     a uuid; b uuid;
--     v_ctx jsonb; p1 jsonb; p2 jsonb; v_s1 uuid; v_ok text;
--     r_body text; r_tick text;
--   BEGIN
--     SELECT sim_clock_current INTO v_clock FROM ottoq_sim_runs WHERE sim_run_id = v_run;
--     -- the proposer finds its run by status, so the stopped run is made the depot's running run for this transaction
--     UPDATE ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
--     SELECT array_agg(id ORDER BY id) INTO v_cars
--       FROM (SELECT id FROM vehicles WHERE home_depot_id = v_depot AND category = 'autonomous' ORDER BY id LIMIT 5) x;
--     a := v_cars[1]; b := v_cars[2];
--     r_body := CASE WHEN position('0494 (G226)' IN pg_get_functiondef('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure)) > 0
--                    THEN 'NEW' ELSE 'OLD' END;
--
--     UPDATE ottoq_ocpp_chargers c SET station_state = 'Available', last_heartbeat_at = v_clock
--       FROM stalls s WHERE s.ocpp_charger_id = c.charger_id AND s.depot_id = v_depot;
--     UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
--      WHERE depot_id = v_depot AND stall_type IN ('l2','dcfc');
--
--     -- 1. the proposer alone: the charger it offers, then the same question after another car books that charger
--     UPDATE vehicles SET current_state = 'arrived_at_gate', current_stall_id = NULL, current_soc = 50 WHERE id = a;
--     v_ctx := jsonb_build_object('current_soc', 50, 'now_ts', v_clock);
--     p1 := public.ottoq_l2_propose_stall_assignment(a, v_depot, v_ctx);
--     v_s1 := (p1->>'stall_id')::uuid;
--     PERFORM ottoq.ottoq_book_stall(v_run, v_s1, b, 'charge_l2', v_clock - interval '25 minutes', v_clock + interval '30 minutes', NULL, NULL, 'otto_q');
--     p2 := public.ottoq_l2_propose_stall_assignment(a, v_depot, v_ctx);
--     v_ok := COALESCE(ottoq.ottoq_validate_assignment(a, (p2->>'stall_id')::uuid, 'begin_charge', v_clock, v_run)->>'ok', 'n/a');
--
--     -- 2. the decide tick: three cars at the gate that want an L2, the first-choice L2 promised to B
--     UPDATE vehicles SET current_state = 'arrived_at_gate', current_stall_id = NULL, current_soc = 50 + i
--       FROM generate_series(1, 3) i WHERE vehicles.id = v_cars[i + 2];
--     PERFORM public.ottoq_decide_tick(v_run);
--     SELECT 'begin_charge issued ' || count(*) FILTER (WHERE c.status = 'issued')
--            || ', refused at the gate ' || count(*) FILTER (WHERE c.status = 'refused' AND c.confirmed_by = 'otto_q_preflight')
--            || ', offered the promised L2 ' || count(*) FILTER (WHERE (c.payload->>'stall_id')::uuid = v_s1)
--       INTO r_tick
--       FROM ottoq_vehicle_commands c
--      WHERE c.sim_run_id = v_run AND c.command_type = 'begin_charge' AND c.issued_at = v_clock
--        AND c.vehicle_id = ANY (v_cars[3:5]) AND NOT (c.payload ? 'reroute_reason');
--
--     RAISE EXCEPTION E'PROBE0494 body=% clock=%\n proposer, free depot: % (%)\n proposer, that L2 booked by B: % (%), gate says ok=%\n decide tick, three cars at the gate: %',
--       r_body, v_clock, left(p1->>'stall_id', 8), p1->>'stall_type', left(p2->>'stall_id', 8), p2->>'stall_type', v_ok, r_tick;
--   END $probe$;

-- ══ §7 THE CANON UNDER 0494 ════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0367 §7 — (3)''s begin_charge issued / refused at the gate, and cars charged, under 0493 and under 0494 ==='
WITH cols AS (
  SELECT v.scenario, v.seed, v.ticks, v.verdict_id, v.arm_a_run AS run,
         CASE WHEN v.verdict_id BETWEEN 384 AND 392 THEN '0493' ELSE '0494' END AS body
    FROM public.ottoq_determinism_verdict_ledger v
   WHERE v.verdict_id BETWEEN 384 AND 392 OR v.certified_at > '2026-09-26 19:06:51+00'
)
SELECT c.scenario || '/' || c.seed || '/' || c.ticks AS col, c.body, c.verdict_id,
       count(*) FILTER (WHERE x.command_type = 'begin_charge' AND NOT (x.payload ? 'reroute_reason')) AS issued,
       count(*) FILTER (WHERE x.command_type = 'begin_charge' AND NOT (x.payload ? 'reroute_reason')
                          AND x.confirmed_by = 'otto_q_preflight' AND x.status = 'refused') AS refused_at_gate,
       count(DISTINCT x.vehicle_id) FILTER (WHERE x.command_type = 'begin_charge' AND x.status = 'executed') AS cars_charged
  FROM cols c JOIN public.ottoq_vehicle_commands x ON x.sim_run_id = c.run
 GROUP BY 1, 2, 3 ORDER BY 1, 2;
-- READ: pending the sweep that started at 2:07 PM CT.

