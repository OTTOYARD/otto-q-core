-- migration-version: 20260820020000
-- migration-name:    twin_holdout_and_comms_run_relative_salts
-- 0052 — C7 FOLLOW-UP #6, found by re-certification #6 (post-0051 arms
-- eb5a5d37 vs 1a576926: 8/20 identical, first divergence sim-min 270 — the
-- exact tick the sim clock crosses 22:00 America/Chicago and the overnight
-- recall window opens). The tick-9 frame diff is a single swap: a DIFFERENT
-- deployed vehicle was recalled in each run. The recall cursor itself is
-- already run-stable (ORDER BY current_soc, id); its ELIGIBILITY filter is
-- not:
--
--   (1) public.ottoq_is_overnight_holdout hashed p_run::text — the
--       per-run-random sim_run_id (the 0047 salt class). Two same-seed runs
--       get different holdout sets by construction, so the overnight recall
--       (both call sites: ottoq_plan_dispatch_tick 'recall' and
--       ottoq_evaluate_return_need rung 6) excludes different vehicles.
--       Fixed: the run's random_seed selects the holdout set, falling back
--       to the old p_run::text only when the run row is unknown. The
--       night-anchored Chicago date term is kept verbatim (same-night arms
--       agree on it; the straddle caveat is documented in TWIN_CORE.md).
--   (2) public.ottoq_comms_emit_telemetry salted its dropout/latency draw
--       with p_run::text plus the ABSOLUTE clock (the 0045+0047 classes,
--       both at once). Same treatment: run seed + vehicle + run-relative
--       clock salt. Caught by the same sweep; comms staleness feeds the
--       rung-8 recall decision, so this is decision-path-reachable.
--
-- Bodies otherwise byte-identical to the 2026-08-19 captures in
-- db/fn_current/ (md5 19d11e7d… / a6137098… verified against production).

CREATE OR REPLACE FUNCTION public.ottoq_is_overnight_holdout(p_vehicle uuid, p_run uuid, p_clock timestamp with time zone, p_pct integer DEFAULT 1)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT (abs(hashtextextended(
     -- 0052: the SEED selects the holdout set, never the per-run-random
     -- sim_run_id; unknown-run callers keep the old behavior verbatim.
     p_vehicle::text || ':' ||
     COALESCE((SELECT r.random_seed::text FROM public.ottoq_sim_runs r
                WHERE r.sim_run_id = p_run), p_run::text) || ':' ||
     (((p_clock AT TIME ZONE 'America/Chicago') - interval '5 hours')::date)::text, 7)) % 100)
   < GREATEST(1, COALESCE(p_pct,1));
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_comms_emit_telemetry(p_run uuid, p_vehicle uuid, p_clock timestamp with time zone, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_speed_mps numeric DEFAULT NULL::numeric, p_heading numeric DEFAULT NULL::numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v RECORD; v_dropout numeric; v_dropped boolean; v_payload jsonb; v_msg_id uuid; v_seed bigint;
BEGIN
  SELECT current_soc, current_state, battery_capacity_kwh INTO v FROM vehicles WHERE id=p_vehicle;
  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_run), p_run::text)||p_vehicle::text||twin.ottoq_sim_clock_salt(p_run, p_clock),7));   -- 0052: run-relative salt, never run uuid + absolute clock
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
