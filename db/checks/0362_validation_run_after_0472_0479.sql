-- 0362  **Validation run after 0472-0479: each fix's prediction, read live.**
--
--       One busy_day run on the twin depot (`11111111-…`), started from the twin cockpit's Control tab at 8x, with
--       0472-0479 in force and energy_reserve_shave promoted to 1 at the depot. Every query takes the run as a psql
--       variable:
--
--           \set run '<sim_run_id>'
--
--       Results are recorded under each query when the run is read.

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

-- ══ §2 G207 (0473): THE SEAM SERVES ONLY INTERIOR INSPECTIONS ═════════════════════════════════════════════════════

\echo '=== 0362 §2 — inspection-lane bookings by the atom of the leg they served ==='
SELECT COALESCE(l.payload->>'atom', l.leg_type, '(none)') AS leg_atom, count(*) AS bookings
  FROM public.ottoq_stall_bookings b
  LEFT JOIN public.ottoq_itinerary_legs l ON l.leg_id = b.leg_id
 WHERE b.sim_run_id = :'run' AND b.purpose = 'inspect'
 GROUP BY 1 ORDER BY 2 DESC;
-- PREDICTED: no readiness_check leg served by the seam.

-- ══ §3 G209 (0474): A CAR MOVED OFF A FAULTED CHARGER GETS A STEP ═════════════════════════════════════════════════

\echo '=== 0362 §3 — cars staged_awaiting_service at the end with no svc_step ==='
SELECT v.display_name, v.current_state, v.config->>'svc_step' AS step, v.last_state_change
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
   AND v.current_state = 'staged_awaiting_service' AND NULLIF(v.config->>'svc_step', '') IS NULL;
-- PREDICTED: none that got there through a charger fault.

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

-- ══ §5 G206 (0476): EVERY NO-CHARGE INTAKE IS BOOKED ════════════════════════════════════════════════════════════════

\echo '=== 0362 §5 — no-charge gate intakes enacted with and without a booking ==='
SELECT count(*) AS intakes,
       count(*) FILTER (WHERE NULLIF(d.enacted_action->>'booking_id', '') IS NULL) AS without_booking
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = :'run' AND d.resolved_action_context = 'gate_intake_no_charge';
-- PREDICTED: 0 without a booking (3 of 46 on 49c45bd4).

-- ══ §6 G211 (0477) AND THE PROMOTION: THE BATTERY'S DAY PLAN, WITHOUT ITS SOLVE TIME ════════════════════════════════

\echo '=== 0362 §6 — energy commands carrying the day plan, and any carrying solve_ms ==='
SELECT count(*) AS commands,
       count(*) FILTER (WHERE c.reason::jsonb ? 'day_plan') AS with_day_plan,
       count(*) FILTER (WHERE (c.reason::jsonb -> 'day_plan') ? 'solve_ms') AS with_solve_ms,
       public.ottoq_policy_get(:'run'::uuid, 'energy_reserve_shave', -1) AS reserve_shave_read_by_run
  FROM public.ottoq_energy_commands c WHERE c.sim_run_id = :'run';
-- PREDICTED: the run reads energy_reserve_shave 1 (unless the agent set it at run scope), some commands carry the
-- day plan, none carries solve_ms.

-- ══ §7 G214 (0479): THE RUN'S SOLAR STARTS ON ITS OWN PANELS ═══════════════════════════════════════════════════════

\echo '=== 0362 §7 — each canopy''s first and last recorded soiling on the run ==='
SELECT o.canopy_code,
       (array_agg(o.soiling_factor ORDER BY o.sim_clock_at))[1] AS first_soiling,
       (array_agg(o.soiling_factor ORDER BY o.sim_clock_at DESC))[1] AS last_soiling,
       count(*) AS rows
  FROM public.ottoq_solar_output o WHERE o.sim_run_id = :'run' GROUP BY 1 ORDER BY 1;
-- PREDICTED: every canopy's first recorded soiling derives from 0.85 (0.85 itself on a dry first tick, or 0.88 after
-- one rainy tick), whatever the depot row held when the run started.
