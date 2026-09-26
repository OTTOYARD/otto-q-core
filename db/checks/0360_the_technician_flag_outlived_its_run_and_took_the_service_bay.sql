-- 0360  **The deploy gate's technician flag outlived the run that raised it: 44 of 116 cars entered validation run
--       49c45bd4 already flagged, and every flagged car the service bay seated was one of them.** FINDINGS G208, and
--       in §4-§5 G206 (re-read) and G210.
--
--       Read from `49c45bd4-4daa-4323-b9d8-451ab1628a30`'s signed event stream, decisions, commands and bookings after
--       its stop (busy_day, twin depot `11111111-…`, sim 8:00-11:47 AM CT), on 2026-09-26 between 07:59 and 08:25 UTC
--       (2:59-3:25 AM CT). G208 is fixed by `db/migrations/0475`, G206 by `db/migrations/0476`; G210 is open.
--
--       Every query takes the run as a psql variable:
--
--           \set run '<sim_run_id>'

\set run '49c45bd4-4daa-4323-b9d8-451ab1628a30'

-- ══ §1 WHO WRITES THE FLAG, AND WHO CLEARS IT ══════════════════════════════════════════════════════════════════════

\echo '=== 0360 §1 — every function that raises flagged_issue (expect one: the deploy gate) ==='
SELECT n.nspname || '.' || p.proname AS fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog','information_schema')
   AND p.prosrc ~ $x$'flagged_issue',\s*true$x$;
-- twin.ottoq_sim_advance_service_flow, alone: the deploy gate's patience escalation (45 sim-min held) sets
-- flagged_issue true, flagged_issue_type deploy_gate_stuck, "so a technician sees it". No code outside the database
-- writes the flag (the repos were searched). Its readers send a flagged car to the service bay: a wash or detail exit
-- hands it need_service on the flag alone, and 0468's need-gate keeps a flagged need_service car for its technician
-- seat. Nothing clears it: the service-bay exit leaves it, twin.ottoq_sim_seed_fleet strips flagged_issue_type and
-- keeps flagged_issue, and only the certification reset's whitelist (ottoq_tick_invariance_reset_fleet) drops it.

\echo '=== 0360 §1b — the twin depot now ==='
SELECT v.config->>'flagged_issue' AS flag, v.config->>'flagged_issue_type' AS ftype, count(*) AS cars
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous' AND v.config ? 'flagged_issue'
 GROUP BY 1, 2;
-- true · deploy_gate_stuck · 49

-- ══ §2 THE RUN STARTED WITH 44 FLAGS IT DID NOT RAISE ═════════════════════════════════════════════════════════════

\echo '=== 0360 §2 — flagged before the run touched the car, against flagged on the run ==='
WITH ev AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at, e.event_seq,
         e.payload #> '{diff,config,to}' AS cfg_to, e.payload #> '{diff,config,from}' AS cfg_from
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed' AND e.payload #> '{diff,config}' IS NOT NULL),
firstcfg AS (SELECT DISTINCT ON (vehicle_id) vehicle_id, sim_clock_at, cfg_to, cfg_from FROM ev ORDER BY vehicle_id, event_seq),
flagged_at AS (SELECT vehicle_id, min(sim_clock_at) AS first_flag_sim FROM ev WHERE (cfg_to->>'flagged_issue')::boolean GROUP BY 1)
SELECT
  (SELECT count(*) FROM firstcfg) AS cars,
  (SELECT count(*) FROM firstcfg WHERE (cfg_from->>'flagged_issue')::boolean) AS flagged_before_first_change,
  (SELECT count(*) FROM flagged_at) AS ever_flagged_on_run,
  (SELECT count(*) FROM flagged_at f JOIN firstcfg c USING (vehicle_id)
    WHERE NOT COALESCE((c.cfg_from->>'flagged_issue')::boolean, false)) AS flagged_during_run,
  (SELECT min(sim_clock_at) FROM firstcfg) AS first_change_sim;
-- 116 cars · 44 flagged before their first change (all deploy_gate_stuck) · 46 ever flagged · 2 flagged on the run ·
-- first change at 13:00:00 UTC sim, the seed: it keeps the flag and strips the type, so the run sees 44 flags with
-- no type at all.

-- ══ §3 THE SERVICE BAY'S SEATS ══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0360 §3 — every service-bay seat on the run, its length, its credit, and whose flag it was ==='
WITH tr AS (
  SELECT e.entity_id AS vid, e.sim_clock_at, e.event_seq,
         e.payload #>> '{diff,current_state,from}' AS s_from, e.payload #>> '{diff,current_state,to}' AS s_to
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed' AND e.payload #> '{diff,current_state}' IS NOT NULL),
seats AS (
  SELECT t.vid, t.sim_clock_at AS seated_at,
         (SELECT min(t2.sim_clock_at) FROM tr t2 WHERE t2.vid = t.vid AND t2.s_from = 'in_service_bay' AND t2.event_seq > t.event_seq) AS left_at
    FROM tr t WHERE t.s_to = 'in_service_bay'),
ex AS (
  SELECT e.entity_id AS vid, e.sim_clock_at, jsonb_array_length(COALESCE(e.payload->'credited','[]'::jsonb)) AS n_credit
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'twin.service_completed' AND e.payload->>'from' = 'in_service_bay'),
cfg AS (
  SELECT DISTINCT ON (e.entity_id) e.entity_id AS vid, e.payload #> '{diff,config,from}' AS cfg_from
    FROM public.ottoq_events e
   WHERE e.sim_run_id = :'run' AND e.event_type = 'vehicle.state_changed' AND e.payload #> '{diff,config}' IS NOT NULL
   ORDER BY e.entity_id, e.event_seq)
SELECT v.display_name, s.seated_at, round(EXTRACT(epoch FROM (s.left_at - s.seated_at))/60.0, 1) AS seat_min,
       (SELECT ex.n_credit FROM ex WHERE ex.vid = s.vid
         AND ex.sim_clock_at BETWEEN s.left_at - interval '1 minute' AND s.left_at + interval '1 minute' LIMIT 1) AS credited,
       COALESCE((c.cfg_from->>'flagged_issue')::boolean, false) AS flagged_before_run
  FROM seats s JOIN public.vehicles v ON v.id = s.vid LEFT JOIN cfg c ON c.vid = s.vid
 ORDER BY s.seated_at;
-- Waymo-AV-012   8:03 AM  44.1 min  credited 0  flagged before the run
-- Waymo-AV-040   8:03 AM  44.4      0            flagged before the run
-- Tesla-AV-047   8:57 AM  52.0      0            flagged before the run
-- Tesla-AV-041   9:29 AM  39.5      1            flagged before the run
-- Zoox-AV-074    9:50 AM  95.1      1            -
-- Waymo-AV-037  10:28 AM  37.9      0            flagged before the run
-- Zoox-AV-093   11:06 AM  33.5      1            -
-- Zoox-AV-092   11:09 AM  25.0      0            -  (0359 §5a)
-- Waymo-003     11:34 AM  13.5+     seated at the stop, flagged before the run
-- Zoox-AV-078   11:39 AM   8.0+     seated at the stop, flagged before the run
--
-- 10 seats, 7 flagged, all 7 flags carried in from earlier runs. The four flagged seats that credited nothing held the
-- bay for 178 of the 393 seat-minutes it gave on the run. The first two took both stalls 3 sim-minutes in: the seed's
-- boot cohort writes need_service, 0468 sends an unflagged cohort car with no service-bay work to the deploy gate, and
-- keeps a flagged one for its technician seat.

-- ══ §4 G206: THE INTAKE COLLIDED WITH THE CAR'S OWN HOLD ═══════════════════════════════════════════════════════════

\echo '=== 0360 §4 — every intake enacted with no booking, and what its picked stall already held ==='
WITH intakes AS (
  SELECT d.entity_id AS vid, d.sim_clock AS at, (d.enacted_action->>'stall_id')::uuid AS stall
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = :'run' AND d.resolved_action_context = 'gate_intake_no_charge'
     AND NULLIF(d.enacted_action->>'booking_id', '') IS NULL)
SELECT v.display_name AS intake_car, s.stall_code, i.at AS picked_at,
       (SELECT jsonb_agg(jsonb_build_object('same_car', b.vehicle_id = i.vid, 'purpose', b.purpose, 'state', b.state,
                'from', lower(b.during), 'to', upper(b.during), 'reason', b.release_reason) ORDER BY lower(b.during))
          FROM public.ottoq_stall_bookings b
         WHERE b.sim_run_id = :'run' AND b.stall_id = i.stall
           AND b.during && tstzrange(i.at, i.at + interval '1 minute')) AS overlapping_at_pick
  FROM intakes i JOIN public.vehicles v ON v.id = i.vid JOIN public.stalls s ON s.id = i.stall
 ORDER BY i.at;
-- Tesla-AV-067  S025  10:01:58 AM CT sim   its own temp_hold 9:45-10:05 (closed window_elapsed_occupied)
-- Tesla-AV-044  S013  10:07:10 AM          its own temp_hold 9:58-10:08 (closed vehicle_moved_to_next_leg)
-- Zoox-AV-093   E020  11:47:48 AM          its own perimeter_hold 11:00-1:00 PM (released run_stopped)
--
-- 3 of 3 are the car's own booking. The intake's pick asks ottoq_validate_assignment, which exempts the car's own
-- booking, and then books with a bare ottoq.ottoq_book_stall, whose per-stall EXCLUDE (held, active, done,
-- interrupted) does not. The insert fails, ottoq_book_stall returns NULL, and the intake goes on with its command
-- already emitted. 0359 §4 read these as "a later booking on the stall overlapped"; that was wrong. Fixed by 0476.

-- ══ §5 OTHER SAME-TICK DOUBLE SENDS (G210, OPEN) ═══════════════════════════════════════════════════════════════════

\echo '=== 0360 §5 — cars sent to two stalls in one tick, by the two commands reasons ==='
WITH c AS (
  SELECT vc.vehicle_id, vc.issued_at, vc.status, COALESCE(vc.payload->>'reason', '(none)') AS reason
    FROM public.ottoq_vehicle_commands vc
   WHERE vc.sim_run_id = :'run' AND vc.payload ? 'stall_id'),
multi AS (
  SELECT vehicle_id, issued_at, array_agg(reason || ':' || status ORDER BY reason) AS pair
    FROM c GROUP BY 1, 2 HAVING count(*) > 1)
SELECT pair, count(*) AS ticks FROM multi GROUP BY 1 ORDER BY 2 DESC;
-- gate_intake:refused + inspect_seam_interior_inspection:executed   16  (G204, fixed by 0472)
-- gate_intake:executed + inspect_seam_interior_inspection:refused   12  (G204, fixed by 0472)
-- (none):refused + gate_intake:executed                              3
-- (none) + (none)                                                    5
-- (none):refused + inspect_seam_interior_inspection:executed         2
--
-- The reason-less commands are the appointment planner's `stage` and `proceed_to_stall` (they carry a `plan` and an
-- `appointment`) and the charge path's `begin_charge`; most were refused `target_occupied`. 10 ticks on the run. Not
-- traced further here.

-- ══ §6 0475, BEFORE AND AFTER, ON A ROLLED-BACK PROBE ═════════════════════════════════════════════════════════════
--
--   On the stopped run 49c45bd4, 2026-09-26 at 11:20 UTC (6:20 AM CT), in one transaction undone by a final RAISE:
--   the lowest-id untethered car of the twin depot put in the first service bay, its seat over (service_ends_at a
--   minute past), carrying flagged_issue true and flagged_issue_type deploy_gate_stuck, as an earlier run leaves it.
--   (A) one pass of twin.ottoq_sim_advance_service_flow on the tick's search_path; (B) twin.ottoq_sim_seed_fleet
--   (depot, 42, 8), the scenario runner's seed. Each under the old bodies, then under 0475's.
--
--                            before 0475                          after 0475
--   (A) the car              staged_for_departure, step ready     staged_for_departure, step ready
--       flagged_issue        true                                 (absent)
--       flagged_issue_type   deploy_gate_stuck                    (absent)
--       twin.service_completed  credited [], suppressed_n 4       the same, and flag_cleared: deploy_gate_stuck
--   (B) after the seed       116 cars, 33 flagged, 0 typed        116 cars, 0 flagged, 0 typed
--
--   Both predictions hold. The exit clears the flag the seat answered and names it on the event; the seed no longer
--   hands a run the previous runs' flags (the 33 are §1b's 32 plus the probe's car, each stripped of its type).
--   The first attempt timed out at 60 s: its "latest event" read scanned ottoq_events by run and car (23 s cold).
--   The second took the global max(event_seq) instead, which the primary key answers at once.

-- ══ §7 0476, BEFORE AND AFTER, ON A ROLLED-BACK PROBE ═════════════════════════════════════════════════════════════
--
--   The same run, 11:21 UTC: the same car put at the gate (arrived_at_gate, no step) with an open visit owing only
--   an interior inspection, so the intake's (3b) cursor serves it; the stall the intake picks first computed by the
--   intake's own query; and the car's own temp_hold booked on that stall from five sim-minutes before the clock to
--   fifteen after, as a hold path leaves it. One public.ottoq_decide_tick under each body:
--
--                            before 0476                          after 0476
--   intake decision          on the picked stall, booking (none)  on the picked stall, booking 87e2fd5d…
--   staging booking on it    0                                    1
--   the car's own hold       held                                 superseded (superseded_by_enacted_decision)
--   gate_intake commands     1                                    1
--
--   Before: the car is sent and nothing is booked, which is §4's three incidents exactly. After: the intake is
--   booked on the stall it picked, and the car's own hold gives way to it through the seam.
--
--   A first attempt that also set the stall's reserved_by to the car found nothing to fix: the intake's cursor
--   skips a stall whose pointer is held, by anyone, so it picked another stall and booked it, before and after. The
--   collision needs the calendar hold without the pointer, which is how all three incidents' stalls stood.
