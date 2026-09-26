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
--   The rolled-back probe (0493's body without P0, then the tail below, in one transaction ending in RAISE) on the
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
-- READ: pending the sweep that started at 1:38 PM CT.

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
-- READ: pending.
