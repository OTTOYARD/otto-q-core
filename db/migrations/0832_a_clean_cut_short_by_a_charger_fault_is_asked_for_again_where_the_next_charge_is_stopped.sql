-- migration-version: 20261114034649
-- migration-name:    0832_a_clean_cut_short_by_a_charger_fault_is_asked_for_again_where_the_next_charge_is_stopped
--
-- 0832  **An arm clean cut short by a charger fault is asked for again where the car's next charge is stopped.**
--
-- WHY. Run 1902d13b (0831's check), read at tick 349: of 88 charged visits of the three kinds cleaned after their
--   charge, 87 were cleaned by the arm and 1 was not. That car (d9d2a011): the arm started in the last minutes of the
--   charge, the charger faulted, the car left the post and the routine was cancelled as interrupted (0764, 0792).
--   0767 has the starter decide such a routine again at the car's next post, and the tick step offers a CHARGING car
--   for it. But a car cleaned after its charge is started where its charge is stopped (0830), through
--   public.ottoq_awaits_arm_after_charge, and that test read the earlier decision and the cancelled atom as "the arm
--   has decided", so the stop would not have asked. (On that visit there was no second stop to ask at: this file
--   closes the hole in the test; it does not show that visit would have been cleaned.)
--
-- WHAT THIS DOES. The test takes 0767's case as still waiting: a recorded 'cleaned' whose routine atom is cancelled
--   and interrupted is not a decision, and only arm work in progress or done counts as arm work. Nothing else changes.
--
-- CHECKS. P0 no certification in flight. P2 once. V the function runs for every car of the twin depot.
-- CLASSIFICATION. forces_recert TRUE, forces_dial_restart FALSE.
-- ROLLBACK: EXECUTE the definition of public.ottoq_awaits_arm_after_charge in db/migrations/0828 as CREATE OR REPLACE;
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0832_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';
DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0832 P0: a certification is in flight'; END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_awaits_arm_after_charge(uuid)'))
     IS DISTINCT FROM '48ae178c82465eb8d3bfc994d04a6bf8' THEN RAISE EXCEPTION '0832 P1: not the body this file was written against'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0832_%') THEN RAISE EXCEPTION '0832 P2: already applied'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_awaits_arm_after_charge(p_vehicle uuid)
 RETURNS boolean LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0828, 0832: a car whose port profile says clean_after_charge (0827), whose charge has ended, that still stands on its
     fast-charger post under its demate tether, and whose open visit has no arm work and no arm decision yet. False
     with cabin_robot_after_charge or stall_cabin_robot off, and where the post's charger is Faulted (0792). */
  SELECT EXISTS (
    SELECT 1
      FROM public.vehicles v
      JOIN public.stalls s ON s.id = v.robotic_tether_stall_id AND s.stall_type::text = 'dcfc'
      JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
     WHERE v.id = p_vehicle
       AND v.current_state::text = 'charge_complete_holding'
       AND v.robotic_tether_until IS NOT NULL
       AND v.current_stall_id = v.robotic_tether_stall_id
       AND COALESCE(v.robotic_tether_direction, 'demate') = 'demate'
       AND COALESCE((public.ottoq_vehicle_port_profile(v.id)).clean_after_charge, false)
       AND COALESCE(public.ottoq_policy_get(vn.sim_run_id, 'cabin_robot_after_charge', 0), 0) >= 1
       AND COALESCE(public.ottoq_policy_get(vn.sim_run_id, 'stall_cabin_robot', 0), 0) >= 1
       AND jsonb_typeof(vn.atoms) = 'array'
       -- 0832: a routine the arm began whose car left the post before the arm was home (a charger fault; 0764 cancels
       -- it, 0767 has it decided again) is not a decision taken, and its cancelled atom is not arm work
       AND (NOT (COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine')
            OR (vn.meta -> 'arm_routine' ->> 'outcome' = 'cleaned'
                AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) r
                             WHERE r->>'svc' = 'interior_tidy' AND COALESCE((r->>'arm_routine')::boolean, false)
                               AND r->>'status' = 'cancelled' AND r ? 'interrupted')))
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                        WHERE a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' IN ('in_progress', 'done'))
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) t
                        WHERE t->>'svc' = 'interior_tidy' AND t->>'status' IN ('in_progress', 'done'))
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers fc
                        WHERE fc.charger_id = s.ocpp_charger_id AND fc.station_state = 'Faulted'));
$function$;

DO $v$
DECLARE n int;
BEGIN
  SELECT count(*) FILTER (WHERE public.ottoq_awaits_arm_after_charge(v.id) IS NOT NULL) INTO n
    FROM public.vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111';
  IF n = 0 THEN RAISE EXCEPTION '0832 V: the test ran for no car'; END IF;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0832_a_clean_cut_short_by_a_charger_fault_is_asked_for_again_where_the_next_charge_is_stopped', true, false, 'ottoq_awaits_arm_after_charge takes 0767''s interrupted routine as still waiting.', now());
COMMIT;

-- APPLIED 2026-11-14 at 03:46:49 UTC (2026-11-13, 9:46 PM CT), ledger 20261114034649, through apply_migration, on the
--   first send. Run 1902d13b was live, at tick 359 just after. Stored md5(prosrc): 22cfe07415cc29b7cfe6186ff8062863.
--   Not seen on a run: no car has yet had a routine cut short by a fault and then a second stop on the same visit.
