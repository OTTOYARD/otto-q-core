-- tests/fixtures/arrival_forecast_stub.sql -- for tests/test_board_reads_without_writing_sql.py (0766). Loaded over
-- tests/fixtures/agent_scouts_wake_stub.sql with 0703, 0704 and 0709 applied, which leave public.ottoq_agent_board byte
-- for byte the live board (pg_get_functiondef md5 d130f89abfff0e93aac5416b3f4d98aa, read 2026-10-24 03:59 UTC, 10:59 PM
-- CT on 10-23). This file adds what 0766 changes and what its formula and its write reach:
--   - public.ottoq_predict_arrivals byte for byte the live one (pg_get_functiondef md5 b9e952538e34007310156ccf7f6979f4,
--     read 2026-10-24 04:13 UTC as base64 and decoded here), replacing the stub's one-column stand-in;
--   - the columns its formula reads, and public.ottoq_default_target_soc as live has it (its source, read the same day);
--   - an event writer with the live public.ottoq_record_event's argument list that does to the run's row what the live
--     one does: it inserts the event with the run's id into public.ottoq_events, whose key references ottoq_sim_runs
--     (fk_ottoq_events_sim_run, NOT VALID, as on live), so the insert's key check takes the run's row FOR KEY SHARE
--     until its transaction ends. Signing, hashing and the rest of the live writer are not what 0766 is about.

DROP FUNCTION public.ottoq_predict_arrivals(uuid, timestamptz, uuid, integer);

ALTER TABLE public.vehicles ADD COLUMN target_soc numeric, ADD COLUMN inlet_max_kw numeric,
  ADD COLUMN battery_capacity_kwh numeric;
ALTER TABLE public.ottoq_vehicle_dispatches ADD COLUMN status text;

CREATE FUNCTION public.ottoq_default_target_soc() RETURNS numeric LANGUAGE sql STABLE AS $f$
  -- THE one answer to "how full is full". Every fallback in the codebase points
  -- here. Takes no run id on purpose: this is the fleet-wide default, and a run or
  -- depot that wants something else sets vehicles.target_soc or the visit's
  -- target_soc, both of which win over this.
  SELECT public.ottoq_policy_get(NULL, 'vehicle_target_soc_default', 100);
$f$;

CREATE TABLE public.ottoq_events (event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_seq bigserial,
  occurred_at timestamptz DEFAULT clock_timestamp(), actor_type text, actor_id text, event_type text, entity_type text,
  entity_id uuid, depot_id uuid, payload jsonb, severity text, ingest_source text, data_source text, sim_run_id uuid);
ALTER TABLE public.ottoq_events ADD CONSTRAINT fk_ottoq_events_sim_run FOREIGN KEY (sim_run_id)
  REFERENCES public.ottoq_sim_runs (sim_run_id) NOT VALID;

CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text,
  p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text,
  p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid,
  p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb,
  p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid,
  p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid,
  p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer,
  p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text,
  p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE sql VOLATILE AS $f$
  INSERT INTO public.ottoq_events (actor_type, actor_id, event_type, entity_type, entity_id, depot_id, payload, severity,
                                   ingest_source, data_source, sim_run_id)
  VALUES (p_actor_type, p_actor_id, p_event_type, p_entity_type, p_entity_id, p_depot_id, p_payload, p_severity,
          p_ingest_source, p_data_source, p_sim_run_id)
  RETURNING event_id
$f$;

-- ── live: public.ottoq_predict_arrivals, byte for byte ──
CREATE OR REPLACE FUNCTION public.ottoq_predict_arrivals(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid, p_horizon_min integer DEFAULT 30)
 RETURNS TABLE(incoming_count integer, charge_needed_count integer, predicted_charge_kw numeric, predicted_charge_kwh numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_in_count int; v_chg_count int; v_kw numeric; v_kwh numeric;
BEGIN
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1),
    COALESCE(SUM(CASE WHEN v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 1
              THEN LEAST(COALESCE(v.inlet_max_kw,150), 250)
                   * CASE WHEN v.current_soc < 35 THEN 0.90 WHEN v.current_soc < 55 THEN 0.80
                          WHEN v.current_soc < 75 THEN 0.50 ELSE 0.25 END
              ELSE 0 END), 0),
    COALESCE(SUM(GREATEST(0, (COALESCE(v.target_soc, public.ottoq_default_target_soc()) - v.current_soc)/100.0 * COALESCE(v.battery_capacity_kwh,75))), 0)
  INTO v_in_count, v_chg_count, v_kw, v_kwh
  FROM ottoq_vehicle_dispatches d
  JOIN vehicles v ON v.id = d.vehicle_id
  WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning')
    AND d.scheduled_return_at IS NOT NULL
    AND d.scheduled_return_at <= p_sim_clock + (p_horizon_min || ' minutes')::interval
    AND d.scheduled_return_at >  p_sim_clock - INTERVAL '5 minutes';

  IF v_in_count > 0 THEN
    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='arrival_forecaster',
      p_event_type:='ottoq.arrival_forecast', p_entity_type:='depot', p_entity_id:=p_depot_id,
      p_depot_id:=p_depot_id,
      p_payload:=jsonb_build_object('horizon_min', p_horizon_min, 'incoming_count', v_in_count,
        'charge_needed_count', v_chg_count, 'predicted_charge_kw', ROUND(v_kw,0),
        'predicted_charge_kwh', ROUND(v_kwh,0)),
      p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
  END IF;

  incoming_count := v_in_count; charge_needed_count := v_chg_count;
  predicted_charge_kw := ROUND(v_kw,0); predicted_charge_kwh := ROUND(v_kwh,0);
  RETURN NEXT;
END;
$function$
;
