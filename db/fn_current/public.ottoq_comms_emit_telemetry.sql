CREATE OR REPLACE FUNCTION public.ottoq_comms_emit_telemetry(p_run uuid, p_vehicle uuid, p_clock timestamp with time zone, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_speed_mps numeric DEFAULT NULL::numeric, p_heading numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v RECORD; v_dropout numeric; v_dropped boolean; v_payload jsonb; v_msg_id uuid; v_seed bigint;
BEGIN
  SELECT current_soc, current_state, battery_capacity_kwh INTO v FROM vehicles WHERE id=p_vehicle;
  v_seed := abs(hashtextextended(p_run::text||p_vehicle::text||p_clock::text,7));
  v_dropout := 0.01 * COALESCE(ottoq_profile_rate_mult(p_run,'telemetry_dropout'),1);  -- comms-loss variable
  v_dropped := ottoq_sim_seeded_random(v_seed,'drop') < v_dropout;
  v_payload := jsonb_build_object(
    'bsm_core', jsonb_build_object(
      'msgCnt', (EXTRACT(EPOCH FROM p_clock)::bigint % 128),
      'secMark', (EXTRACT(SECOND FROM p_clock)*1000)::int,
      'position', jsonb_build_object('lat',p_lat,'long',p_lng,'elev_m',180),
      'speed_mps', ROUND(COALESCE(p_speed_mps,0)::numeric,2),
      'heading_deg', ROUND(COALESCE(p_heading,0)::numeric,1),
      'accelSet', jsonb_build_object('long_mps2',0,'lat_mps2',0,'vert_g',1.0,'yaw_degps',0),
      'brakes', 'unavailable', 'size', jsonb_build_object('width_cm',200,'length_cm',490)),
    'ev_ext', jsonb_build_object('soc_pct', v.current_soc,
      'usable_kwh', ROUND((COALESCE(v.battery_capacity_kwh,75)*COALESCE(v.current_soc,0)/100.0)::numeric,1)),
    'av_ext', jsonb_build_object('autonomy_level',4,'ads_engaged',true,'mission_state',v.current_state::text));
  INSERT INTO ottoq_comms_messages(sim_run_id,vehicle_id,direction,topic,msg_type,qos,header,payload,status,latency_ms,sim_clock_at)
  VALUES (p_run,p_vehicle,'uplink','fleet/'||p_vehicle::text||'/telemetry/bsm','telemetry',1,
    ottoq_comms_envelope(p_vehicle,'telemetry',NULL,p_clock), v_payload,
    CASE WHEN v_dropped THEN 'dropped' ELSE 'delivered' END,
    CASE WHEN v_dropped THEN NULL ELSE (40 + (v_seed % 80))::int END, p_clock)
  RETURNING msg_id INTO v_msg_id;
  RETURN v_msg_id;
END $function$
;
