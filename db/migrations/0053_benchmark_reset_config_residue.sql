-- migration-version: 20260820030000
-- migration-name:    benchmark_reset_config_residue
-- 0053 — C7 FOLLOW-UP #7, found by re-certification #7 (post-0052 arms
-- 483954ce vs 4b626bb7: 8/20 identical, first divergence sim-min 210 — again
-- the overnight-window tick). NOT an RNG bug this time: the event-stream diff
-- exposed CROSS-RUN STATE LEAKAGE in the cert harness's world reset.
--
-- Evidence (exact, from vehicle config payloads in ottoq_events.new_state):
-- arm A's vehicles carry config->'charge_plan'->>'planned_at' timestamps whose
-- fractional seconds (…:06.133086) are the PREVIOUS cert's arm-B sim clock
-- (run 1a576926, sim_clock_start 23:21:06.133086), and arm B's carry arm A's
-- signature (…:05.932765, run 483954ce). ottoq.ottoq_book_appointment writes
-- config->'charge_plan' during every run (the charge doctrine), and
-- public.ottoq_benchmark_reset strips 13 config keys but not this one — so
-- every arm starts with the previous run's plans, invisible to the structural
-- digest until the overnight charge-planning path reads them (tick 7 here).
--
-- Fix: extend the reset's strip list with the run-written residue keys —
--   charge_plan       (written by ottoq_book_appointment every booking)
--   deploy_gate       (written by the deploy_ready_gate during runs)
--   arm_fault_at / arm_fault_reason / arm_fault_awaiting_disposition
--                     (written by twin.ottoq_arm_emergency_release between arms)
-- The function refuses non-benchmark depots, so this touches ONLY the cert
-- world. config->'last_balance_charge_at' is also rewritten during runs
-- (balance-charge completions) but was identical across this pair; recorded
-- in TWIN_CORE.md as the next residue channel to check if re-cert #8 diverges.
-- Body otherwise byte-identical to the 2026-08-19 capture in db/fn_current/
-- (md5 a33c2f5c… verified against production).

CREATE OR REPLACE FUNCTION public.ottoq_benchmark_reset(p_depot uuid, p_arrival_soc numeric DEFAULT 30, p_target_soc numeric DEFAULT 80)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF p_depot NOT IN (SELECT id FROM depots WHERE slug LIKE 'benchmark%') THEN
    RAISE EXCEPTION 'ottoq_benchmark_reset refuses non-benchmark depot %', p_depot;  -- safety: never reset production
  END IF;
  -- self-heal zombie runs (worker death between scoring and abort)
  UPDATE ottoq_sim_runs SET status='aborted', ended_at=now(),
         notes = COALESCE(notes,'') || ' | auto-aborted by benchmark_reset (zombie heal)'
   WHERE depot_id=p_depot AND status='running';
  UPDATE stalls SET status='available', current_vehicle_id=NULL, reserved_by=NULL, reserved_at=NULL, reservation_expires_at=NULL WHERE depot_id=p_depot;
  UPDATE ottoq_ocpp_chargers SET station_state='Available', last_heartbeat_at=now(), last_fault_code=NULL WHERE depot_id=p_depot;
  UPDATE ocpp_sessions SET status='completed', ended_at=now() WHERE depot_id=p_depot AND status='active';
  UPDATE vehicles SET current_state='arrived_at_gate', current_soc=p_arrival_soc, target_soc=p_target_soc,
         current_stall_id=NULL, last_state_change=now(),
         config=((COALESCE(config,'{}'::jsonb)-'svc_step')-'service_manifest')-'service_manifest_meta' - 'battery_soh_pct' - 'consumption_scalar' - 'charge_curve_scalar' - 'soil_rate' - 'pm_interval_km' - 'calib_interval_h' - 'service_speed_scalar' - 'wash_cadence_cycles' - 'cycles_since_wash' - 'condition_drawn_run' - 'charge_plan' - 'deploy_gate' - 'arm_fault_at' - 'arm_fault_reason' - 'arm_fault_awaiting_disposition'   -- 0053: run-written residue must not leak into the next cert arm
   WHERE home_depot_id=p_depot AND category='autonomous';
  UPDATE ottoq_visit_needs SET status='superseded'
   WHERE depot_id=p_depot AND status IN ('open','in_progress');
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id=p_depot AND status='pending';
END $function$
;
