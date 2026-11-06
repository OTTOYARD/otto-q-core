-- lab/research/p2_capacity/whatif_dayplan_on_charger.sql -- LAB ONLY, a what-if on one lab day's replica (capacity_day.py
-- --lab-sql). The battery day plan's EV forecast without the cars coming home charged from their arrival whether or not a
-- post is free (ottoq_forecast_ev_known_kw loop 2): the day plan reads only the cars on a charger now (loop 1, verbatim),
-- beside its post-aware queue term (ottoq_forecast_ev_queue_kw, which already queues the cars coming home onto the posts)
-- and the last hour's draw, max of the three as before. Graded on two whole lab days (forecast_grade.py, 2026-11-06):
-- the next half hour's forecast off by +1,228 and +1,210 kW on average as the day plan reads it, +314 and +354 this way.
CREATE OR REPLACE FUNCTION public.ottoq_forecast_ev_on_charger_kw(p_sim_run_id uuid, p_depot_id uuid,
    p_sim_clock timestamp with time zone, p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_load numeric[]; h int; r RECORD;
  v_rate numeric; v_dur_min numeric;
BEGIN
  v_load := array_fill(0::numeric, ARRAY[p_horizon_ticks]);
  -- ottoq_forecast_ev_known_kw's loop (1), verbatim: currently-active charging sessions, held at their rate until done
  FOR r IN
    SELECT ottoq_sim_compute_charge_rate(
             p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
             p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
             p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
             p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text) AS rate,
           GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0*COALESCE(v.battery_capacity_kwh,75)) AS kwh
    FROM ocpp_sessions s JOIN stalls st ON st.id=s.stall_id
    JOIN ottoq_ocpp_chargers ch ON ch.charger_id=st.ocpp_charger_id
    JOIN vehicles v ON v.id=s.vehicle_id
    WHERE s.status='active' AND s.sim_run_id=p_sim_run_id
    ORDER BY st.id
  LOOP
    v_rate := GREATEST(r.rate, 1); v_dur_min := r.kwh / v_rate * 60.0;
    FOR h IN 1..p_horizon_ticks LOOP
      IF (h-1)*p_tick_min < v_dur_min THEN v_load[h] := v_load[h] + v_rate; END IF;
    END LOOP;
  END LOOP;
  RETURN v_load;
END;
$function$;

DO $whatif$
DECLARE
  c_old text := 'v_known := public.ottoq_forecast_ev_known_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30, 30);';
  c_new text := 'v_known := public.ottoq_forecast_ev_on_charger_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30);   -- lab what-if: the cars on a charger now';
  v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamptz,numeric)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN
    RAISE EXCEPTION 'whatif_dayplan_on_charger: the anchor matches % times, not 1', n;
  END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $whatif$;
