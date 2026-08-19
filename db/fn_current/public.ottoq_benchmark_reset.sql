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
         config=((COALESCE(config,'{}'::jsonb)-'svc_step')-'service_manifest')-'service_manifest_meta' - 'battery_soh_pct' - 'consumption_scalar' - 'charge_curve_scalar' - 'soil_rate' - 'pm_interval_km' - 'calib_interval_h' - 'service_speed_scalar' - 'wash_cadence_cycles' - 'cycles_since_wash' - 'condition_drawn_run'
   WHERE home_depot_id=p_depot AND category='autonomous';
  UPDATE ottoq_visit_needs SET status='superseded'
   WHERE depot_id=p_depot AND status IN ('open','in_progress');
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id=p_depot AND status='pending';
END $function$
;
