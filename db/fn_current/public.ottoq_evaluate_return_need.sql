-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 0c463ada1588296a31ec1761d16a83d4
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric DEFAULT 30, p_soc_pct numeric DEFAULT NULL::numeric)
 RETURNS TABLE(should_return boolean, return_trigger text, urgency text, rung smallint, is_deferrable boolean, lead_ticks smallint, projected_eta_min numeric, evidence jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_v RECORD; v_pkt RECORD; v_w RECORD;
  v_soc numeric; v_reserve numeric; v_floor numeric; v_eta_min numeric;
  v_hour int; v_depot uuid;
  v_burn_per_min numeric; v_burn_guard numeric; v_reserve_margin numeric;
  v_dtc_debt int; v_comms_stale int; v_wait_cap int; v_backstop_ticks int;
  v_wash_soil numeric; v_sensor_soil numeric; v_pm_km numeric; v_calib_h numeric;
  v_free_chargers int; v_inbound int; v_wait_ticks int; v_max_wait_min numeric;
  v_in_window boolean; v_slot int; v_slot_open boolean; v_holdout boolean;
  v_wave_start int; v_wave_end int; v_wave_bands int; v_hours_in int;
  v_pkt_age_min numeric; v_has_service_need boolean; v_overnight_need boolean;
  v_ev jsonb;
  v_rf RECORD;   -- 0018
BEGIN
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_evaluate_return_need requires a run scope';
  END IF;

  SELECT d.dispatch_id, d.scheduled_return_at, d.dispatched_at, v.home_depot_id, v.config,
         v.current_soc, v.min_soc_threshold
    INTO v_v
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
   WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = p_sim_run_id AND d.status = 'active'
   ORDER BY d.dispatched_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean,
                        NULL::smallint, NULL::numeric,
                        jsonb_build_object('reason','no active dispatch in run');
    RETURN;
  END IF;
  v_depot := v_v.home_depot_id;

  SELECT tp.soc_pct, tp.sim_clock_at
    INTO v_pkt
    FROM ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at <= p_sim_clock_now AND tp.soc_pct IS NOT NULL
   ORDER BY tp.sim_clock_at DESC, tp.packet_seq DESC LIMIT 1;

  SELECT w.worst_open_dtc_rank, w.open_dtc_count, w.soil_index,
         w.drive_km_total, w.km_at_last_pm, w.drive_hours_total,
         w.hours_at_last_calibration, w.calibrated_at
    INTO v_w
    FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  v_soc     := COALESCE(p_soc_pct, v_pkt.soc_pct, v_v.current_soc);
  v_reserve := ottoq_effective_reserve_soc(p_vehicle_id, p_sim_clock_now);
  v_floor   := ottoq_effective_deploy_floor_at(p_vehicle_id, p_sim_clock_now);
  v_eta_min := ottoq_return_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id);
  v_hour    := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_burn_per_min   := ottoq_policy_get(p_sim_run_id,'p99_burn_pct_per_min',0.25);
  v_reserve_margin := ottoq_policy_get(p_sim_run_id,'reserve_margin_pct',15);
  v_dtc_debt       := ottoq_policy_get(p_sim_run_id,'dtc_debt_threshold',3)::int;
  v_comms_stale    := ottoq_policy_get(p_sim_run_id,'comms_stale_ticks',3)::int;
  v_wait_cap       := ottoq_policy_get(p_sim_run_id,'contention_wait_cap_min',
                        ottoq_policy_get(p_sim_run_id,'contention_wait_cap_ticks',4) * 30)::int;
  v_backstop_ticks := ottoq_policy_get(p_sim_run_id,'timer_backstop_min',
                        ottoq_policy_get(p_sim_run_id,'timer_backstop_ticks',48) * 30)::int;
  v_wash_soil      := ottoq_policy_get(p_sim_run_id,'wash_soil_threshold',0.50);
  v_sensor_soil    := ottoq_policy_get(p_sim_run_id,'sensor_soil_threshold',0.35);
  v_pm_km          := COALESCE((v_v.config->>'pm_interval_km')::numeric, ottoq_policy_get(p_sim_run_id,'pm_interval_km',8000));
  v_calib_h        := COALESCE((v_v.config->>'calib_interval_h')::numeric, ottoq_policy_get(p_sim_run_id,'calib_interval_h',250));

  v_burn_guard := v_burn_per_min * (v_eta_min + p_horizon_min);

  SELECT count(*) INTO v_free_chargers FROM stalls s
   WHERE s.depot_id = v_depot AND s.stall_kind = 'charging'
     AND s.status = 'available' AND s.current_vehicle_id IS NULL;
  SELECT count(*) INTO v_inbound FROM vehicles vv
   WHERE vv.home_depot_id = v_depot AND vv.category='autonomous'
     AND vv.current_state IN ('en_route_to_depot','arrived_at_gate');

  v_wait_ticks := CASE WHEN v_free_chargers >= v_inbound + 1 THEN 0
         ELSE CEIL((v_inbound + 1 - v_free_chargers)/GREATEST(v_free_chargers,1)::numeric) END;
  v_max_wait_min := COALESCE((SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
     JOIN vehicles vv ON vv.id=p_vehicle_id AND vv.fleet_operator_id=s.fleet_operator_id
     WHERE s.status='active' ORDER BY s.version DESC LIMIT 1), 30);

  v_pkt_age_min := CASE WHEN v_pkt.sim_clock_at IS NULL THEN NULL
                        ELSE EXTRACT(EPOCH FROM (p_sim_clock_now - v_pkt.sim_clock_at))/60.0 END;

  v_has_service_need := COALESCE(v_w.soil_index,0) >= v_sensor_soil
     OR COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
     OR (COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3));
  v_overnight_need := v_has_service_need OR v_soc < v_floor;

  -- 0018: the rider flag, read (never drawn) from the run-start draw. Read-only on
  -- the hot path. NULL-safe: a vehicle with no flag row simply has no flag.
  --
  -- ═════════ 0019: READ THE LIFECYCLE, NOT THE DRAW ═════════
  -- 0018 read public.vehicle_need_profile.rider_flag_pending, which is written ONCE
  -- at run start and never cleared. That made the rung re-triggerable: one raise
  -- recalled the same vehicle twice over 16 sim-hours before it was served.
  -- public.ottoq_rider_cleaning_flags.status is the lifecycle -- pending -> recalled
  -- (a visit has taken the atom) -> served -- so reading it makes the rung fire
  -- exactly once per raise. Ownership of the work does not lapse at that moment: it
  -- transfers to the must_do atom on the visit, which the ALWAYS HOLD clauses in
  -- ottoq_decide_tick (2) and ottoq.ottoq_plan_dispatch_tick already enforce.
  -- Shape kept identical so the rung below is unchanged.
  SELECT (f.status = 'pending')  AS rider_flag_pending,
         f.flag_kind             AS rider_flag_kind,
         f.raised_at_sim_clock   AS rider_flag_due_at
    INTO v_rf
    FROM public.ottoq_rider_cleaning_flags f
   WHERE f.vehicle_id = p_vehicle_id
     AND f.sim_run_id = p_sim_run_id;

  v_ev := jsonb_build_object(
    'soc', v_soc, 'reserve', v_reserve, 'deploy_floor', v_floor, 'target_absent_from_loop', true,
    'burn_guard', round(v_burn_guard,2), 'reserve_margin', v_reserve_margin,
    'eta_min', v_eta_min, 'free_chargers', v_free_chargers, 'inbound', v_inbound,
    'wait_ticks', v_wait_ticks, 'reserved_by_bias', 'supply overcounted (reserved_by not consulted)',
    'worst_dtc_rank', v_w.worst_open_dtc_rank, 'soil', v_w.soil_index, 'hour_local', v_hour);

  IF v_soc <= v_reserve + v_burn_guard THEN
    RETURN QUERY SELECT true,'critical_reserve','critical',0::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 0 THEN
    RETURN QUERY SELECT true,'fault_safety_critical','critical',1::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 1 OR COALESCE(v_w.open_dtc_count,0) >= v_dtc_debt THEN
    RETURN QUERY SELECT true,'fault_major','urgent',2::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF v_soc <= v_reserve + v_reserve_margin THEN
    RETURN QUERY SELECT true,'low_soc_reserve','urgent',3::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  -- ===== 0018: RIDER-FLAGGED CLEANING RECALL =====
  -- Below safety and reserve, above everything routine, and NOT behind the
  -- contention gate. is_deferrable = false, lead_ticks = 0: the vehicle turns for
  -- the depot on this tick.
  IF COALESCE(v_rf.rider_flag_pending, false)
     AND v_rf.rider_flag_due_at IS NOT NULL
     AND p_sim_clock_now >= v_rf.rider_flag_due_at THEN
    RETURN QUERY SELECT true,'rider_flag_cleaning','urgent',4::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object(
                          'rider_flag_kind', COALESCE(v_rf.rider_flag_kind,'interior'),
                          'rider_flag_raised_at', v_rf.rider_flag_due_at,
                          'why', 'A ridehail rider reported a '
                                 || COALESCE(v_rf.rider_flag_kind,'interior')
                                 || ' cleanliness issue. Recalled to depot now rather '
                                 || 'than at its next natural return.'); RETURN;
  END IF;

  IF (v_pkt_age_min IS NULL
        AND EXTRACT(EPOCH FROM (p_sim_clock_now - v_v.dispatched_at))/60.0 >= v_comms_stale * p_horizon_min)
     OR (v_pkt_age_min IS NOT NULL AND v_pkt_age_min >= v_comms_stale * p_horizon_min) THEN
    RETURN QUERY SELECT true,'comms_stale','urgent',8::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object('pkt_age_min', v_pkt_age_min); RETURN;
  END IF;
  IF v_v.scheduled_return_at IS NOT NULL
     AND p_sim_clock_now >= v_v.scheduled_return_at + (v_backstop_ticks || ' minutes')::interval THEN
    RETURN QUERY SELECT true,'timer_backstop','anomaly',9::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  IF LEAST(v_wait_ticks * 30.0, v_wait_cap) <= v_max_wait_min THEN
    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN
      RETURN QUERY SELECT true,'service_interval_due','routine',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    IF COALESCE(v_w.soil_index,0) >= v_sensor_soil THEN
      RETURN QUERY SELECT true,'sensor_soil','routine',5::smallint,true,1::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    -- NIGHT WAVES. Window and band count are policy, not literals.
    v_wave_start := ottoq_policy_get(p_sim_run_id, 'night_wave_start_hour', 23)::int;
    v_wave_end   := ottoq_policy_get(p_sim_run_id, 'night_wave_end_hour',    6)::int;
    v_wave_bands := GREATEST(1, ottoq_policy_get(p_sim_run_id, 'night_wave_bands', 3)::int);
    v_in_window := CASE WHEN v_wave_start <= v_wave_end
                        THEN v_hour >= v_wave_start AND v_hour < v_wave_end
                        ELSE v_hour >= v_wave_start OR  v_hour < v_wave_end END;
    -- EMPTIEST FIRST. width_bucket puts the lowest SoC in band 1, and band N
    -- is not released until N-1 hours into the window, so the emptiest cars
    -- turn for the depot first and the fullest wait.
    v_slot      := LEAST(v_wave_bands, width_bucket(v_soc, 0, 100, v_wave_bands));
    -- ELAPSED HOURS ACROSS THE MIDNIGHT WRAP. The previous form ORed in a bare
    -- (v_hour < end), which threw every band open the moment the hour wrapped
    -- past midnight -- one staggered hour and then a flood, not a wave.
    v_hours_in  := CASE WHEN v_hour >= v_wave_start THEN v_hour - v_wave_start
                        ELSE v_hour + 24 - v_wave_start END;
    v_slot_open := v_in_window AND v_hours_in >= v_slot - 1;
    v_holdout := ottoq_is_overnight_holdout(p_vehicle_id, p_sim_run_id, p_sim_clock_now, ottoq_policy_get(p_sim_run_id, 'overnight_holdout_pct', 1)::int);
    IF v_in_window AND v_slot_open AND v_overnight_need AND (NOT v_holdout OR (v_hour >= 3 AND v_hour < 22)) THEN
      RETURN QUERY SELECT true,'overnight_prestage','scheduled',6::smallint,true,1::smallint,v_eta_min,
                          v_ev || jsonb_build_object('slot', v_slot); RETURN;
    END IF;
    IF (COALESCE(v_w.soil_index,0) >= v_wash_soil
        OR COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3))
       AND (v_hour < 7 OR v_hour >= 21) THEN
      RETURN QUERY SELECT true,'wash_cadence','routine',7::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean, NULL::smallint, NULL::numeric,
                      v_ev || jsonb_build_object('decision','no need; stay deployed');
END;
$function$

