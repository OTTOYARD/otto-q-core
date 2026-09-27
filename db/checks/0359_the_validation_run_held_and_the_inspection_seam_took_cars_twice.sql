-- 0359  **The validation run held every fix it was run for, and showed the inspection seam taking cars twice: once
--       from the gate intake in the same tick, and again for the readiness leg.** FINDINGS G204-G208.
--
--       Validation run `49c45bd4-4daa-4323-b9d8-451ab1628a30` (busy_day, twin depot `11111111-…`), started from the twin
--       cockpit's Control tab at 06:39:31 UTC on 2026-09-26 (1:39 AM CT) at 8x, with 0463-0471 in force (0471 applied
--       at 06:38:50, 41 seconds before the start). Read live, and after the stop and before any purge.
--
--       Every query takes the run as a psql variable:
--
--           \set run '<sim_run_id>'

\set run '49c45bd4-4daa-4323-b9d8-451ab1628a30'

-- ══ §1 WHAT THE RUN WAS FOR: 0463-0471 LIVE ══════════════════════════════════════════════════════════════════════

\echo '=== 0359 §1 — the fixes, one row ==='
WITH r AS (SELECT sim_run_id, sim_clock_current FROM public.ottoq_sim_runs WHERE sim_run_id = :'run'),
dec AS (SELECT d.* FROM public.ottoq_decisions d, r WHERE d.sim_run_id = r.sim_run_id),
cmd AS (SELECT c.* FROM public.ottoq_vehicle_commands c, r WHERE c.sim_run_id = r.sim_run_id)
SELECT jsonb_build_object(
  -- G199 / 0467: the intake picks a stall its own gate accepts, one command per intake
  'intakes', (SELECT count(*) FROM dec WHERE resolved_action_context = 'gate_intake_no_charge'),
  'intake_cmds_refused_preflight', (SELECT count(*) FROM cmd WHERE command_type = 'proceed_to_stall'
                                     AND payload->>'reason' = 'gate_intake' AND status = 'refused'
                                     AND confirmed_by = 'otto_q_preflight'),
  'intake_cmds_stepless', (SELECT count(*) FROM cmd WHERE command_type = 'proceed_to_stall'
                            AND payload->>'reason' = 'gate_intake' AND NOT payload ? 'svc_step'),
  'intake_reroutes', (SELECT count(*) FROM cmd c JOIN cmd p ON p.command_id = (c.payload->>'reroute_after')::uuid
                       WHERE p.payload->>'reason' = 'gate_intake'),
  -- G200 / 0469: no per-tick stage no-ops
  'stage_ready_cmds', (SELECT count(*) FROM cmd WHERE command_type = 'stage' AND payload->>'ready' = 'true'),
  -- G201 / 0468: the service bay seats only cars with service-bay work or a technician flag
  'service_bay_exits', (SELECT count(*) FROM public.ottoq_events e, r WHERE e.sim_run_id = r.sim_run_id
                         AND e.event_type = 'twin.service_completed' AND e.payload->>'from' = 'in_service_bay'),
  'service_bay_exits_crediting_nothing', (SELECT count(*) FROM public.ottoq_events e, r WHERE e.sim_run_id = r.sim_run_id
                         AND e.event_type = 'twin.service_completed' AND e.payload->>'from' = 'in_service_bay'
                         AND jsonb_array_length(COALESCE(e.payload->'credited', '[]'::jsonb)) = 0),
  -- G196 / 0463 and G196b / 0464
  'atoms_closed_by_session', (SELECT count(*) FROM public.ottoq_visit_needs vn, r, jsonb_array_elements(vn.atoms) a
                               WHERE vn.sim_run_id = r.sim_run_id AND a->>'closed_by' = 'session_completed'),
  'gate_stamps_missing_empty', (SELECT count(*) FROM public.ottoq_events e, r WHERE e.sim_run_id = r.sim_run_id
                         AND e.event_type = 'vehicle.state_changed'
                         AND e.payload->'diff'->'config'->'to'->'deploy_gate'->>'reason' = 'must_do_work_open'
                         AND jsonb_array_length(COALESCE(e.payload->'diff'->'config'->'to'->'deploy_gate'->'missing', '[]'::jsonb)) = 0),
  -- G203 / 0471: no staging hold kept after its reserve was refused
  'hold_orphans_expired', (SELECT count(*) FROM public.ottoq_stall_bookings b, r
                            WHERE b.sim_run_id = r.sim_run_id AND b.booked_by = 'otto_q' AND b.purpose = 'temp_hold'
                              AND b.state = 'released' AND b.release_reason = 'window_elapsed'
                              AND NOT EXISTS (SELECT 1 FROM public.ottoq_events e
                                               WHERE e.sim_run_id = b.sim_run_id AND e.entity_id = b.vehicle_id
                                                 AND e.event_type = 'vehicle.state_changed'
                                                 AND e.payload->'diff'->'current_stall_id'->>'to' = b.stall_id::text)),
  'released_by_0471', (SELECT jsonb_object_agg(release_reason, n) FROM (
                         SELECT b.release_reason, count(*) AS n FROM public.ottoq_stall_bookings b, r
                          WHERE b.sim_run_id = r.sim_run_id
                            AND b.release_reason IN ('reserve_refused_decide_tick', 'reserve_refused_place_unplaced',
                                                     'move_refused_on_arm')
                          GROUP BY 1) x)
) AS v;
-- Read after the stop (07:08 UTC, 428 ticks, sim 8:00-11:47 AM CT):
--   intakes 46 · refused pre-flight 0 · stepless 0 · rerouted 0       (317d4331: 51 of 61 refused, G199)
--   stage {ready: true} 0                                               (317d4331: 7,686, G200)
--   service-bay exits 8, crediting nothing 5: 4 technician-flagged (the path 0468 keeps) and 1 not, §5a
--   charge atoms closed by session completion 1 · empty deploy-gate stamps 0
--   otto_q temp holds 206, expired with the car never on the stall 0  (317d4331: 58, G203)
--   released by 0471: none. No reserve was refused, because 0471's booking loop no longer offers a stall another
--   car holds a live reservation on, which is where 34 of 317d4331's 58 came from.

-- ══ §2 G204: THE SEAM AND THE GATE INTAKE SENT THE SAME CAR TO TWO STALLS IN ONE TICK ══════════════════════════

\echo '=== 0359 §2 — same-tick stall commands the door superseded, and what the loser left ==='
WITH cmd AS (SELECT c.* FROM public.ottoq_vehicle_commands c WHERE c.sim_run_id = :'run'),
pairs AS (
  SELECT s.payload->>'reason' AS loser, w.payload->>'reason' AS winner, s.vehicle_id,
         (s.payload->>'stall_id')::uuid AS loser_stall, s.issued_at
    FROM cmd s JOIN cmd w ON w.vehicle_id = s.vehicle_id AND w.issued_at = s.issued_at AND w.command_id <> s.command_id
                          AND w.command_type = 'proceed_to_stall' AND w.status = 'executed'
   WHERE s.command_type = 'proceed_to_stall' AND s.status = 'refused' AND s.reason_code = 'superseded')
SELECT loser, winner, count(*) AS n,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                       WHERE b.sim_run_id = :'run' AND b.vehicle_id = pairs.vehicle_id
                                         AND b.stall_id = pairs.loser_stall
                                         AND (b.state = 'held' OR b.release_reason IN ('window_elapsed')))) AS loser_booking_left
  FROM pairs GROUP BY 1, 2 ORDER BY n DESC;
-- intake lost to the seam 16 (13 left their staging booking held or ran it out) · seam lost to the intake 12 (9 left
-- their inspect booking). Every pair shares issued_at and command_type; the door's tie-break is stall_id DESC, so the
-- winner is whichever stall uuid sorts higher. PULSE read "8 with two active stall reservations at once" at 10:25 AM,
-- and 15 cars held two live bookings at 11:41 AM. Fixed by 0472.

-- ══ §3 G207: THE READINESS LEG SERVED AS A SECOND INTERIOR INSPECTION ═════════════════════════════════════════════

\echo '=== 0359 §3 — inspect legs by atom, and how many the inspection lane served ==='
SELECT l.duration_basis->>'atom' AS atom, l.status, count(*) AS legs,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                       WHERE b.leg_id = l.leg_id AND b.purpose = 'inspect')) AS served_at_lane
  FROM public.ottoq_itinerary_legs l
 WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- interior_inspection  done 89 (63 served at the lane) · skipped 43 (6)
-- readiness_check      done 65 (57 served at the lane) · skipped 79 (2)
-- 128 lane bookings for 65 cars; 59 were readiness legs served as inspections. (`skipped` is the stop: the reset
-- skips every planned leg.) Waymo-AV-024: interior inspection 10:31-10:35 on bf082cbd, then its readiness leg, planned
-- for 3:31 AM after an overnight L2 charge, 10:35-10:38 on the same stall. Fixed by 0473.

-- ══ §4 THREE SMALLER THINGS: G205, G206, G208 ═════════════════════════════════════════════════════════════════════

\echo '=== 0359 §4 ==='
SELECT
  (SELECT count(*) FROM public.ottoq_vehicle_commands c
    WHERE c.sim_run_id = :'run' AND c.command_type = 'stage' AND c.payload->>'reason' = 'no_wash_need') AS g205_no_wash_stage_cmds,
  (SELECT count(*) FROM public.ottoq_decisions d
    WHERE d.sim_run_id = :'run' AND d.resolved_action_context = 'gate_intake_no_charge'
      AND NULLIF(d.enacted_action->>'booking_id', '') IS NULL) AS g206_intakes_without_booking,
  (SELECT count(*) FROM public.ottoq_events e JOIN public.vehicles v ON v.id = e.entity_id
    WHERE e.sim_run_id = :'run' AND e.event_type = 'twin.service_completed' AND e.payload->>'from' = 'in_service_bay'
      AND COALESCE((v.config->>'flagged_issue')::boolean, false)) AS g208_bay_exits_still_flagged_now;
-- G205 10 stage {no_wash_need} commands, 2 boot-cohort cars in the first 8 sim-minutes.
-- G206 3 of 46 intakes with no booking. First read here as a later booking on the stall overlapping the intake's
--      window; that was wrong. All three picked stalls carried the SAME car's own live hold, which the validator
--      exempts and the booking's EXCLUDE does not (0360 §4, fixed by 0476).
-- G208 5 of the 8 service-bay exits were flagged cars, and all 5 are still flagged (4 of them credited nothing).

-- ══ §5 TWO MORE, READ AT 11:41 AM BEFORE THE STOP ═══════════════════════════════════════════════════════════════
--
--   (a) Zoox-AV-092, unflagged, went from the gate to the service bay 26 s after arriving (11:08:49 -> 11:09:15) and
--       left at 11:34:16 crediting nothing, with `mechanical_pm` and `sensor_calibration` pending and not must-do. The
--       service flow's own lane is need-gated since 0468; this seat came from the decide path (5), whose
--       `ottoq_l2_propose_service` admits on open service-bay atoms whatever their must-do. Why the bay then credited
--       neither atom is not yet read. One of 8 exits.
--   (b) Waymo-AV-015 and Tesla-AV-065 went from `charging_l2` straight to `staged_awaiting_service` with no `svc_step`
--       (10:36 and 10:46) and were still stepless at 11:41: G197's shape, on the charger-fault requeue path (both
--       sessions ended `faulted`, at 91% and 86%), which 0465 did not cover. No gate reads a car with no step; the
--       charge cursor (3) does, and both visits still owed a must-do charge (target 100%), so the two waited for a
--       charger as a `need_charge` car would, but uncounted and with nothing recording why. G209, drafted as 0474;
--       §8 is its probe. (An earlier draft of this line said "L2 completion path" and, in 0474, "waited for chargers
--       they did not need". Both were wrong: the sessions faulted, and the charge was owed.)
--
-- ══ §6 THE COCKPITS ON THIS RUN ══════════════════════════════════════════════════════════════════════════════════
--
--   Twin 2D and 3D (headless, software 3D, placement only), all tabs: DCFC 10/10, L2 30/30 and staging 25/113 at
--   9:33 AM; the Runs tab listed 11 operator runs with this one first and no harness arm (0470); Events read "since
--   08:03" on the HH:MM face. The agent's card printed a cut-off 429 body ("HTTP 429: {"status":429,"title":"Too Man"),
--   now worded "model rate-limited (HTTP 429)" in all three cockpits. Start posted a resume the backend refused 409 on
--   every start; Start now adopts the running state. PULSE (tick 281) and OrchestrAV (tick 296) harnesses read this run
--   live in the same decision words.
--
--   Tick compute on this run averaged 849-1,030 ms per tick from 9 AM against 328-583 ms on 317d4331 at the same sim
--   times (`ottoq_tick_clock_log`), inside the 3.75 s budget at 8x. Different seeds and fleet mix; not attributed.

-- ══ §7 0472 AND 0473, BEFORE AND AFTER, ON ONE ROLLED-BACK TRANSACTION ═════════════════════════════════════════════
--
--   Run on 2026-09-26 at 07:38-07:40 UTC (2:38-2:40 AM CT), after the recert sweep for 0471-0473 had passed 9 of 9 and
--   with no pair or run live, as one transaction that raised at its end. On the stopped run 49c45bd4 (sim clock 11:47
--   AM CT), the depot's three lowest-id untethered cars are put at the gate, each with a fresh itinerary of two
--   `inspect` legs, the planner's pair: `interior_inspection` now and `readiness_check` four hours out. The seam then
--   runs once under each body, swapped in from `ottoq_schema_snapshots` inside a subtransaction and swapped back out.
--
--                                                              original      0472 only     applied
--                                                              (0472_pre)    (0473_pre)    (0472+0473)
--     car 1  interior leg planned; the gate intake has already   served        not served    not served
--            sent it to a staging stall this tick (G204)
--     car 2  interior leg done; readiness leg still planned      served, as    served, as    not served
--            (G207)                                              readiness     readiness
--     car 3  interior leg planned, nothing else (control)        served        served        served
--     enacted                                                    3             2             1
--
--   The applied body's md5 read 5b65d6842860c1b641bcbbbbf3a816a2 inside the transaction and after it. No probe row
--   survived (0 itineraries created by the probe, 0 decisions at its tick).
--
--   The first attempt enacted 0 under all three bodies, the control included: on a stopped run the needs card measures
--   `vehicle_need_profile.next_deploy_at` against the depot's latest run clock, so every car read overdue (-759 to
--   -1,116 minutes) and failed the seam's two window tests. The probe clears the three cars' `next_deploy_at` (NULL
--   passes both). A probe whose control is not served has shown nothing about the fix.

-- ══ §8 0474, BEFORE AND AFTER, ON ONE ROLLED-BACK TRANSACTION ════════════════════════════════════════════════════
--
--   Run on 2026-09-26 at 07:41-07:58 UTC (2:41-2:58 AM CT), with no pair or run live: 0474's P0, P2, patch and V-blocks
--   bracketed by the same scenario, on the stopped run 49c45bd4. Waymo-AV-015's faulted L2 session is reopened with the
--   car back on its charger at 86% against a 100% target, no step, and its visit reopened as it was live (charge owed,
--   must-do). `twin.ottoq_sim_stop_charge_session` is called with `fault.session_aborted_other`, then the service flow
--   runs once 30 s later on the tick's search_path. Each scenario runs twice: as the stop is, and with
--   `ottoq.ottoq_book_hold_stall` stubbed to book nothing (the staging-full branch). Each is undone in its own
--   subtransaction, the stub with it.
--
--                          after the stop                              after one service-flow pass
--     old body
--       temp stall booked  staged_awaiting_service, staging, no step   no step; no deploy_gate record
--       staging full       staged_awaiting_service, no stall, no step  no step; no deploy_gate record
--     new body (0474)
--       temp stall booked  staged_awaiting_service, staging,           need_charge; deploy_gate reason
--                          need_deploy                                 must_do_work_open, missing ['charge']
--       staging full       staged_awaiting_service, no stall,          need_charge; same
--                          need_deploy
--
--   The session reads `faulted` in all four. The stub did not outlive its subtransaction. The first attempt at the
--   service-flow pass failed on `ottoq_sim_lane_capacity(uuid, unknown, integer) does not exist`: the service flow
--   sets no search_path and resolves its callees on its callers' (`twin, ottoq, public, extensions`, both of them).
