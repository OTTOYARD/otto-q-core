-- 0362  **Validation run after 0472-0479: each fix's prediction, read live.**
--
--       One busy_day run on the twin depot (`11111111-…`), started from the twin cockpit's Control tab at 8x, with
--       0472-0479 in force and energy_reserve_shave promoted to 1 at the depot. Every query takes the run as a psql
--       variable:
--
--           \set run '<sim_run_id>'
--
--       Results are recorded under each query when the run is read.
--
--       THE RUN: `3dbe16db-1711-42c2-8646-58166c6cc38e`, busy_day at the twin depot, started from the cockpit's Control
--       tab at 12:32:59 UTC (7:32 AM CT) at 8x and stopped from it at 13:10:11 UTC (8:10 AM CT): 556 ticks, sim 8:00 AM to
--       12:57 PM. 0472-0482 in force, energy_reserve_shave 1 at the depot. The twin 2D/3D, PULSE (8081/live-harness)
--       and OrchestrAV (8082/live-harness) read it live at sim 8:32 AM and again at 12:34 PM: 110-112 cars moving, none
--       stuck, stopped or reversing, both cockpits on the same run, tick and sim clock. By noon the depot was saturated:
--       70 waiting, 38 charging (DCFC 9/10, L2 29/30), 4 deployed.

-- ══ §1 G204 (0472): NO CAR SENT TO TWO STALLS IN ONE TICK BY THE SEAM AND THE INTAKE ═══════════════════════════════

\echo '=== 0362 §1 — ticks in which one car got two stall commands, by the two commands'' reasons ==='
WITH c AS (
  SELECT vc.vehicle_id, vc.issued_at, vc.status, COALESCE(vc.payload->>'reason', '(none)') AS reason
    FROM public.ottoq_vehicle_commands vc
   WHERE vc.sim_run_id = :'run' AND vc.payload ? 'stall_id'),
multi AS (SELECT vehicle_id, issued_at, array_agg(reason || ':' || status ORDER BY reason) AS pair
            FROM c GROUP BY 1, 2 HAVING count(*) > 1)
SELECT pair, count(*) AS ticks FROM multi GROUP BY 1 ORDER BY 2 DESC;
-- PREDICTED: no pair of gate_intake with inspect_seam_*. (G210's reason-less pairs are open and may remain.)
-- READ: 0 seam-and-intake pairs (28 on 49c45bd4). Seven ticks with two stall commands for one car, none of them G204's:
--   {begin_charge:(none):refused, proceed_to_stall:gate_intake:executed}      4   the charge path and the gate intake
--                                                                                 on the same arriving car. All four are
--                                                                                 G216's cars (§9), fixed by 0483.
--   {begin_charge:(none):executed, begin_charge:(none):refused}               2   a refusal and the reactor's reroute in
--                                                                                 one tick, which is the reactor working
--   {proceed_to_stall:(none):refused, proceed_to_stall:(none):refused}        1   the appointment planner twice (G210)

-- ══ §2 G207 (0473): THE SEAM SERVES ONLY INTERIOR INSPECTIONS ═════════════════════════════════════════════════════

\echo '=== 0362 §2 — inspection-lane bookings by the atom of the leg they served ==='
SELECT COALESCE(l.duration_basis->>'atom', l.leg_type, '(none)') AS leg_atom, count(*) AS bookings
  FROM public.ottoq_stall_bookings b
  LEFT JOIN public.ottoq_itinerary_legs l ON l.leg_id = b.leg_id
 WHERE b.sim_run_id = :'run' AND b.purpose = 'inspect'
 GROUP BY 1 ORDER BY 2 DESC;
-- PREDICTED: no readiness_check leg served by the seam.
-- READ: 73 inspection-lane bookings, all interior_inspection, none readiness_check (59 of 128 on 49c45bd4).

-- ══ §3 G209 (0474): A CAR MOVED OFF A FAULTED CHARGER GETS A STEP ═════════════════════════════════════════════════

\echo '=== 0362 §3 — cars staged_awaiting_service at the end with no svc_step ==='
SELECT v.display_name, v.current_state, v.config->>'svc_step' AS step, v.last_state_change
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
   AND v.current_state = 'staged_awaiting_service' AND NULLIF(v.config->>'svc_step', '') IS NULL;
-- PREDICTED: none that got there through a charger fault.
-- READ (live, sim 12:49 PM, before the stop): one car, Zoox-AV-073, and not through a fault: it arrived at 8:56 AM at
-- 47% and (3)'s no-candidate branch staged it in a hold whose proceed_to_stall carries no svc_step. It waited for a charger
-- in (3)'s staged branch, on a day when chargers were full. The five charger faults of the run, from their events:
--   fault.ground_fault_safety      not requeued (SoC near target): charge_complete_holding, svc_step need_deploy
--   fault.station_hardware  x2     requeued: staged_awaiting_service, need_deploy
--   fault.session_aborted_other x2 requeued: staged_awaiting_service, need_deploy and need_charge
-- So no car moved off a faulted charger was left without a step (2 on 49c45bd4). 0474 holds.

-- ══ §4 G208 (0475): THE TECHNICIAN FLAG STARTS CLEAR AND IS CLEARED BY ITS SEAT ═════════════════════════════════════

\echo '=== 0362 §4 — flags carried in, raised on the run, and cleared by a service-bay exit ==='
WITH ev AS (
  SELECT e.entity_id, e.sim_clock_at, e.event_seq,
         e.payload #> '{diff,config,to}' AS cfg_to, e.payload #> '{diff,config,from}' AS cfg_from
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed' AND e.payload #> '{diff,config}' IS NOT NULL),
firstcfg AS (SELECT DISTINCT ON (entity_id) entity_id, cfg_from FROM ev ORDER BY entity_id, event_seq)
SELECT (SELECT count(*) FROM firstcfg WHERE (cfg_from->>'flagged_issue')::boolean) AS flagged_before_first_change,
       (SELECT count(DISTINCT entity_id) FROM ev WHERE (cfg_to->>'flagged_issue')::boolean) AS flagged_on_run,
       (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id = :'run' AND e.event_type = 'twin.service_completed'
           AND e.payload ? 'flag_cleared' AND e.payload->>'flag_cleared' IS NOT NULL) AS seats_that_cleared_a_flag;
-- PREDICTED: 0 flagged before the first change (was 44 of 116 on 49c45bd4).
-- READ: the query above reads 42, and it reads the wrong side of the diff. All 42 first config diffs are the seed at
-- 13:00:00 sim, and each one's `to` clears the flag, so the 42 were carried in from the last run and the seed stripped
-- them: 0475's seed half works. The corrected count, flagged after the seed, is below and reads 0. Three cars were
-- flagged during the run (Tesla-AV-056, Waymo-AV-003, Zoox-AV-076), all `deploy_gate_stuck`, the deploy gate's 45-minute
-- patience expiring on a day cars queued hours for chargers. None took a service-bay seat after being flagged, so none was
-- cleared (28 twin.service_completed, 0 flag_cleared), and Zoox-AV-076 deployed flagged. The seat clears a flag, and a
-- stuck-at-the-gate flag is not a seat's to clear (G218).
WITH first_cfg AS (
  SELECT DISTINCT ON (e.entity_id) e.entity_id, e.payload #> '{diff,config,to}' AS cfg_to
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed' AND e.payload #> '{diff,config}' IS NOT NULL
   ORDER BY e.entity_id, e.event_seq)
SELECT count(*) FILTER (WHERE (cfg_to->>'flagged_issue')::boolean) AS flagged_after_the_seed, count(*) AS cars
  FROM first_cfg;

-- ══ §5 G206 (0476): EVERY NO-CHARGE INTAKE IS BOOKED ════════════════════════════════════════════════════════════════

\echo '=== 0362 §5 — no-charge gate intakes enacted with and without a booking ==='
SELECT count(*) AS intakes,
       count(*) FILTER (WHERE NULLIF(d.enacted_action->>'booking_id', '') IS NULL) AS without_booking
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = :'run' AND d.resolved_action_context = 'gate_intake_no_charge';
-- PREDICTED: 0 without a booking (3 of 46 on 49c45bd4).
-- READ: 48 intakes, 0 without a booking.

-- ══ §6 G211 (0477) AND THE PROMOTION: THE BATTERY'S DAY PLAN, WITHOUT ITS SOLVE TIME ════════════════════════════════

\echo '=== 0362 §6 — energy commands carrying the day plan, and any carrying solve_ms ==='
SELECT count(*) AS commands,
       count(*) FILTER (WHERE c.reason::jsonb ? 'day_plan') AS with_day_plan,
       count(*) FILTER (WHERE (c.reason::jsonb -> 'day_plan') ? 'solve_ms') AS with_solve_ms,
       public.ottoq_policy_get(:'run'::uuid, 'energy_reserve_shave', -1) AS reserve_shave_read_by_run
  FROM public.ottoq_energy_commands c WHERE c.sim_run_id = :'run';
-- PREDICTED: the run reads energy_reserve_shave 1 (unless the agent set it at run scope), some commands carry the
-- day plan, none carries solve_ms.
-- READ: 1,112 commands, 556 with the day plan, 0 with solve_ms. The run reads energy_reserve_shave 1.

-- ══ §7 G214 (0479): THE RUN'S SOLAR STARTS ON ITS OWN PANELS ═══════════════════════════════════════════════════════

\echo '=== 0362 §7 — each canopy''s first and last recorded soiling on the run ==='
SELECT o.canopy_code,
       (array_agg(o.soiling_factor ORDER BY o.sim_clock_at))[1] AS first_soiling,
       (array_agg(o.soiling_factor ORDER BY o.sim_clock_at DESC))[1] AS last_soiling,
       count(*) AS rows
  FROM public.ottoq_solar_output o WHERE o.sim_run_id = :'run' GROUP BY 1 ORDER BY 1;
-- PREDICTED: every canopy's first recorded soiling derives from 0.85 (0.85 itself on a dry first tick, or 0.88 after
-- one rainy tick), whatever the depot row held when the run started.
-- READ: 0.79 on every canopy on all 556 rows. 0.79 is 0.85 through the run's variability profile (`_global.spread_mult`
-- 1.4: 1 + (0.85 - 1) x 1.4), applied after the floor, so the first recorded soiling does derive from 0.85 as predicted.
-- It never moved because the profile is applied to the soiling state itself, which is G215 (open, latent on this run: it
-- did not rain). The shared canopy rows read 0.85 at the start, so this run cannot tell 0479 from the old body. §10 of
-- 0361 is where 0479 was shown to matter.

-- ══ §8 G195: BOOKINGS STILL ACTIVE FOR A CAR THAT IS NOT ON THE STALL (READ WHILE THE RUN IS LIVE) ═══════════════════

\echo '=== 0362 §8 — active bookings whose car is elsewhere, by stall type and purpose, with stall-minutes left ==='
WITH clk AS (SELECT sim_clock_current AS t FROM public.ottoq_sim_runs WHERE sim_run_id = :'run')
SELECT s.stall_type, b.purpose, count(*) AS leaked,
       round(sum(GREATEST(0, EXTRACT(EPOCH FROM (upper(b.during) - clk.t)) / 60.0))) AS stall_minutes_left
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
  JOIN public.vehicles v ON v.id = b.vehicle_id
  CROSS JOIN clk
 WHERE b.sim_run_id = :'run' AND b.state = 'active' AND v.current_stall_id IS DISTINCT FROM b.stall_id
 GROUP BY 1, 2 ORDER BY 3 DESC;
-- 317d4331 at ~9:10 AM sim: 1 DCFC (103 stall-minutes left), 1 L2, 1 inspection, 1 perimeter hold, 10 staging holds
-- (213 stall-minutes). 0467 and 0471 removed two of its sources since; the sweep that releases the rest
-- (space_departure_release_enabled) is off. If this reads zero, there is nothing left for a dial experiment to test.
-- READ, live:
--   sim 8:22 AM   38 leaked, all staging holds: 12 cars already deployed, 22 now on a charger, 1 en route.
--   sim 8:30 AM   23 leaked, every one a staging stall with no occupant still reserved to its car, which was charging
--                 (15 L2, 8 DCFC): 305 stall-minutes left. Staging 113: pointer-free 40, calendar-free 80, free on both
--                 40. Every pointer-free stall was also calendar-free, so the leak did not bind.
--   sim 9:02 AM   5 staging, 188 stall-minutes. Staging free on both: 67.
--   sim 10:06 AM  1 staging, 1 L2 (L2-05, 73 minutes left, its charger Faulted under the car), 1 DCFC (DCFC-01, 8 left).
--   sim 12:49 PM  1 staging, 1 perimeter hold (26 stall-minutes).
-- The staging half of G195 never bound on this run: staging kept 40-76 stalls free on both gates all day. The charger
-- half did, and it is G217 (§10): the car's reservation of the charger, backed by its own active booking, outlived the
-- session. The 38 at 8:22 are mostly G216's detour (the intake's hold, left active while the car went to its charger).
-- NOTE: `twin.staging_overflow` is not a staging-capacity signal. Its payload counts cars queued beyond the service
-- lanes' capacity (svc_cap 2, wash_cap 3, deploy_cap 20); it fired 46 times by 8:44 AM while 40 staging stalls were free.

-- ══ §9 G216: A RECALLED CAR'S CHARGE CLOSED BEFORE IT ARRIVED (found on this run) ═════════════════════════════════

\echo '=== 0362 §9 — closed charge atoms by the car''s state when they were closed, and what the en-route ones arrived with ==='
WITH atoms AS (
  SELECT vn.vehicle_id, COALESCE((a->>'done_at')::timestamptz, (a->>'closed_at')::timestamptz) AS closed_at,
         (a->>'target_soc')::numeric AS target, COALESCE((a->>'must_do')::boolean, false) AS must_do,
         COALESCE(a->>'closed_by', 'flow_contract') AS closer
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'charge' AND a->>'status' = 'done'),
ev AS (SELECT e.entity_id, e.sim_clock_at, e.event_seq, e.payload#>>'{diff,current_state,to}' AS st,
              (e.payload#>>'{diff,current_soc,to}')::numeric AS soc
         FROM public.ottoq_events e
        WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed'
          AND e.entity_id IN (SELECT vehicle_id FROM atoms)),
x AS (
  SELECT a.*,
         (SELECT st FROM ev WHERE ev.entity_id = a.vehicle_id AND st IS NOT NULL AND ev.sim_clock_at <= a.closed_at
           ORDER BY sim_clock_at DESC, event_seq DESC LIMIT 1) AS state_at_close,
         (SELECT soc FROM ev WHERE ev.entity_id = a.vehicle_id AND soc IS NOT NULL AND ev.sim_clock_at <= a.closed_at
           ORDER BY sim_clock_at DESC, event_seq DESC LIMIT 1) AS soc_at_close,
         (SELECT min(sim_clock_at) FROM ev WHERE ev.entity_id = a.vehicle_id AND st = 'arrived_at_gate' AND ev.sim_clock_at > a.closed_at) AS arrived_at
    FROM atoms a)
SELECT closer, COALESCE(state_at_close, '(no state event yet)') AS state_at_close, must_do, count(*) AS atoms,
       min(soc_at_close) AS min_soc_at_close, max(soc_at_close) AS max_soc_at_close,
       -- the SoC on the arrival event itself: a telemetry event at the same sim instant can sort ahead of it
       min((SELECT soc FROM ev WHERE ev.entity_id = x.vehicle_id AND st = 'arrived_at_gate' AND ev.sim_clock_at = x.arrived_at
             ORDER BY event_seq LIMIT 1)) AS min_soc_at_arrival,
       max((SELECT soc FROM ev WHERE ev.entity_id = x.vehicle_id AND st = 'arrived_at_gate' AND ev.sim_clock_at = x.arrived_at
             ORDER BY event_seq LIMIT 1)) AS max_soc_at_arrival
  FROM x GROUP BY 1, 2, 3 ORDER BY 4 DESC;
-- READ on 3dbe16db (sim 8:00 AM-12:57 PM): 56 charge atoms closed. The flow contract closed 17: 10 while the car was
-- en_route_to_depot (all must_do, at 87-96%, arriving at 44-54%), 1 while it was deployed, 6 at the depot.
-- ottoq_satisfied closed 35 and session_completed 3, all at the depot. (A first read of this query took the SoC from the
-- first event at or after the arrival instant, and a telemetry event at that instant sorted ahead of the arrival: it
-- read Zoox-AV-073 as arriving at 87% when it arrived at 47%. The query now reads the arrival event's own SoC.)
-- What followed at the gate, for the first three (7ec698b8, 1225f10e, 380f0f38), from their commands:
--   an appointment reserved a charger while the car was inbound (its proceed_to_stall refused: the car was not there),
--   the charge atom closed on the SoC the car left with, the car reached the gate at 44-54%, and in one tick (3) sent it
--   to that charger while (3b), seeing a closed charge, staged it need_deploy as "no charge needed". The door kept the
--   intake. The next tick (3)'s staged branch sent it to the same charger, and the intake's staging hold stayed active
--   while it charged. 7ec698b8 deployed at 90% against an 80% floor, so the deploy SoC held.
-- Probe before apply (rolled back, on this run at sim 13:09:27): 7ec698b8 en route at 95% with a pending must-do charge
-- to 90%, a control car staged at 95% with the same atom. One flow pass:
--   live body   en-route car done      staged control done
--   0483        en-route car pending   staged control done
-- 0483's prediction for the next run: no row with state_at_close en_route_to_depot (or deployed, offline, tow_requested).

-- ══ §10 G217: A FINISHED CHARGE KEPT ITS CHARGER (found on this run) ═══════════════════════════════════════════════

\echo '=== 0362 §10 — minutes each ended session''s charger stayed reserved by, and booked for, the car that had finished ==='
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
         (SELECT LEAST(COALESCE(b.released_at, upper(b.during)), upper(b.during))
            FROM public.ottoq_stall_bookings b
           WHERE b.sim_run_id = :'run' AND b.stall_id = s.stall_id AND b.vehicle_id = s.vehicle_id
             AND b.purpose IN ('charge_dcfc','charge_l2') AND lower(b.during) <= s.ended_at AND upper(b.during) > s.ended_at
           ORDER BY lower(b.during) DESC LIMIT 1) AS booking_end
    FROM sess s)
SELECT stall_type, split_part(stopped_reason, '.', 1) AS stop, count(*) AS sessions,
       count(*) FILTER (WHERE reserved_at_end) AS reserved_at_end,
       round(sum(EXTRACT(EPOCH FROM (unreserved_at - ended_at)) / 60) FILTER (WHERE reserved_at_end)) AS reserved_min_after,
       round(max(EXTRACT(EPOCH FROM (unreserved_at - ended_at)) / 60) FILTER (WHERE reserved_at_end), 1) AS max_reserved_min,
       count(booking_end) AS booked_at_end,
       round(sum(GREATEST(0, EXTRACT(EPOCH FROM (booking_end - ended_at))) / 60)) AS booked_min_after
  FROM x GROUP BY 1, 2 ORDER BY 1, 2;
-- READ on 3dbe16db (sessions ended by 12:57 PM sim; a reservation still held at the stop counts to the stop):
--   stall  stop        sessions  reserved_at_end  reserved_min_after (max)  booked_at_end  booked_min_after (max)
--   dcfc   completed      38          38              215 (31.8)                 14             57 (30.0)
--   dcfc   fault           2           2               75 (51.6)                  2             73 (51.6)
--   l2     completed      23           7                3 (0.4)                   3              5 (4.6)
--   l2     fault           3           2               13 (12.6)                  3             70 (49.9)
-- 290 DCFC-minutes held by a car that had finished or faulted, about a tenth of the ten DCFCs' 2,970 on the run, while
-- the stall assignment abstained 3,033 times on no_compatible_available_stall (8:26 AM to 12:56 PM). The reclaimer frees a
-- reservation whose holder sits in another stall only when no held or active booking backs it, and the finished
-- session's own booking was that backing. DCFC-01: ab7adca4 completed at 10:03:14 at 90%, its booking ran to 10:14:31
-- (released window_elapsed_occupied), and the next car plugged in at 10:16:37.
-- Probe before apply (rolled back, on this run): DCFC-01's session rebuilt as it was at 10:03:14 and stopped:
--   live body            booking active to 10:14:31, reservation still ab7adca4's, the car the (tethered) occupant
--   0484, completed      booking done to 10:03:26.3 (the arm's 11.5 s demate), charge_session_completed, reservation
--                        cleared, the car still the tethered occupant
--   0484, faulted        booking interrupted to 10:03:14.8, charge_session_faulted, reservation cleared, the car
--                        requeued to staging
-- A first draft closed the completed session's booking as `interrupted`, because it finished under 80% of its planned
-- window. A charge that reached its target early is not an interruption, and interrupted rows feed the interruption
-- counts, so only a faulted or cancelled session can be interrupted. The probe above is of the corrected body.
-- 0484's prediction for the next run: reserved_at_end 0 and booked_min_after 0, bar a latched DCFC's demate seconds.

-- ══ §11 WHERE THE TICK'S TIME GOES (task 61) ════════════════════════════════════════════════════════════════════════
--
-- `ALTER ROLE postgres SET track_functions = 'pl'` from about 12:05 UTC to 13:10:44 UTC, so every pg_cron session
-- counted. Captures at 12:31:18 and 13:10:39 UTC bracket the run (db/evidence/r362_fn_before.md, r362_fn_after.md), and
-- `python3 scripts/fn-delta.py db/evidence/r362_fn_before.md db/evidence/r362_fn_after.md` gives the delta
-- (db/evidence/r362_fn_delta.md): 254 functions moved, 14.48M calls, 1,863.8 s of self time. 1,074.7 s of that is the
-- metronome's own pacing wait, so the tick path's compute was about 789 s over 557 world ticks and 278 decide ticks,
-- about 1.4 s a world tick. The largest self times:
--   public.ottoq_computed_eta_minutes          27,987 calls   83.2 s   3.0 ms a call, the single largest cost
--   public.ottoq_decide_tick (own body)            278        58.9 s   212 ms a decide tick
--   ottoq.ottoq_find_and_book_stall             36,524        56.0 s
--   ottoq.ottoq_enact_inspection_seam              278        55.3 s   199 ms a decide tick
--   public.ottoq_evaluate_rule_core            103,510        52.5 s   the L1 shield
--   public.ottoq_sim_compute_charge_rate     5,616,259        38.0 s   about 10,000 calls a tick
--   twin.ottoq_sim_advance_service_flow            559        37.5 s
--   public.cuopt_log_gate                          389        24.8 s   64 ms a call, for a logging gate
--   public.ottoq_vehicles_state_change         105,077        22.8 s
--   public.ottoq_policy_get                    406,606        21.6 s
--   public.ottoq_record_event                   22,465        21.2 s
--   twin.ottoq_sim_seeded_random             6,061,876        13.1 s   about 10,900 calls a tick
-- The charge-rate function and the seeded draw run about ten thousand times a tick for about forty charging cars, so the
-- charge integration steps per car are the call-count hot spot. The ETA function, the seam and cuopt_log_gate are the
-- per-call ones. Named here, not changed.

-- ══ §12 G218: THE DEPOT RELEASES A CAR ITS OWN RECALL POLICY CALLS STRAIGHT BACK ════════════════════════════════════

\echo '=== 0362 §12 — each deployment by the trigger of the next recall, and how soon it came ==='
WITH dep AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS deployed_at
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed'
     AND e.payload#>>'{diff,current_state,to}' = 'deployed'
     AND e.sim_clock_at > (SELECT sim_clock_start FROM public.ottoq_sim_runs WHERE sim_run_id = :'run') + interval '30 seconds'),
nxt AS (
  SELECT d.*, r.decided_at_sim AS recalled_at, r.return_trigger
    FROM dep d
    LEFT JOIN LATERAL (SELECT r.decided_at_sim, r.return_trigger FROM public.ottoq_recall_decisions r
                        WHERE r.sim_run_id = :'run' AND r.vehicle_id = d.vehicle_id AND r.should_return
                          AND r.decided_at_sim >= d.deployed_at ORDER BY r.decided_at_sim LIMIT 1) r ON true)
SELECT return_trigger, count(*) AS deployments,
       count(*) FILTER (WHERE recalled_at - deployed_at < interval '10 minutes') AS recalled_within_10_min,
       round(avg(EXTRACT(EPOCH FROM (recalled_at - deployed_at)) / 60) FILTER (WHERE recalled_at IS NOT NULL), 1) AS avg_min
  FROM nxt GROUP BY 1 ORDER BY 2 DESC;
-- READ on 3dbe16db: 108 deployments after the boot. service_interval_due 93 (28 recalled within 10 minutes, mean 57.5
-- minutes), sensor_soil 6, comms_stale 3 (all 3 within 10 minutes, mean 1.9), low_soc_reserve 2, no recall 4.
-- 90 of the 116 cars were recalled for service_interval_due (116 such recalls, 24 cars twice or three times), and 9 cars
-- left the service bay all run. Zoox-AV-076 deployed at 90% at 12:42:06 PM and was recalled at 12:42:41 for
-- service_interval_due, reached the gate at 12:44:54 and asked for a service-bay seat (hold_no_bay, bay full).
-- The recall policy in force (naive_threshold_v1) calls a car back when its service interval is due. At the depot that
-- service is not must_do: on the visits those recalls opened, mechanical_pm 32 atoms, all must_do false, 27 still
-- pending at the stop; sensor_calibration 7, must_do false, 5 pending; only fault_repair (4) was must_do. So the deploy
-- gate releases the car after its charge without the service, the interval is still due, and the recall fires again on
-- the next evaluation. `interval_scheduled_v1` (0448, G181) was built for this and is
-- parked ("twin runs and dial experiments only, until a human marks it active"): no recall below
-- recall_interval_hard_overdue_mult x the interval, and above it a non-deferrable recall whose visit makes the service
-- must_do. G212 could not test it because no car reaches an interval in 48 canon ticks. On a full day 90 of 116 do.
