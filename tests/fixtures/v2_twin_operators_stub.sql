-- ============================================================================================================
-- tests/fixtures/v2_twin_operators_stub.sql
--
-- What tests/test_v2_twin_operators_sql.py adds to the STUB ENGINE (tests/fixtures/v2_door_stub_engine.sql, 0649-0651)
-- before it applies 0653. NOT the engine, NOT a migration, NEVER applied anywhere real: it refuses a database that
-- has a supabase_migrations schema.
--
--   * 0652 refuses on the stub (it patches the live walk at md5-guarded anchors), so 0653's premise row for it is
--     written here, and the walk is a STAND-IN: twin.ottoq_sim_confirm_commands with the live signature, running the
--     commands it is handed (ottoq.apply_only) in the live walk's order (issued_at, vehicle, type, stall, seq), seating
--     a car when its stall is free and refusing target_occupied when it is not. It writes the engine's rows as the live
--     walk does today, or, when stub_walk_mode.reports is on, reports to the twin's log as 0654's walk will. The live
--     walk itself is executed against 0653 inside 0653's own V1, at apply time.
--   * public.ottoq_events is a stand-in table the stub's ottoq_record_event now also writes (the stub engine's guard
--     refuses a database that has it, so it is created only after that guard has run).
--   * ottoq_policy_param_catalog, ottoq_command_actor_registry and the ottoq_command_handshake view carry the live
--     columns (read 2026-10-10) and the live view text.
-- ============================================================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'supabase_migrations') THEN
    RAISE EXCEPTION 'v2_twin_operators_stub.sql is a TEST STUB and this looks like a real engine. Refusing.';
  END IF;
END $guard$;

-- 0653's premise: 0652 is classified (it refuses here by design; see above)
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0652_the_twin_applies_the_directives_it_is_handed_and_answers_each_with_an_ack', false, false,
        'stub: 0653''s premise (0652 refuses on the stub by design)', now());

CREATE TABLE public.ottoq_policy_param_catalog (
  param_key text PRIMARY KEY, description text, default_value numeric, min_value numeric, max_value numeric, affects text,
  min_exclusive numeric, max_exclusive numeric, agent_writable boolean NOT NULL DEFAULT false, agent_min_value numeric,
  agent_max_value numeric, agent_max_drift_pct numeric);

CREATE TABLE public.ottoq_command_actor_registry (
  actor text PRIMARY KEY, kind text NOT NULL CHECK (kind = ANY (ARRAY['self'::text, 'operator'::text, 'external'::text])),
  note text, registered_at timestamptz NOT NULL DEFAULT now());
INSERT INTO public.ottoq_command_actor_registry (actor, kind, note) VALUES
  ('otto_q_preflight', 'self', 'the emitter accepting its own command pre-flight'),
  ('otto_q_preflight_refusal', 'self', 'the emitter refusing its own command pre-flight'),
  ('cockpit', 'operator', 'a human at an OTTOYARD console'),
  ('oem_fleet', 'external', 'an OEM fleet backend');

-- the live view as it stood before 0653 (pg_get_viewdef, 2026-10-10)
CREATE VIEW public.ottoq_command_handshake AS
 SELECT c.data_source,
    count(*) AS issued_total,
    count(*) FILTER (WHERE (c.delivered_at IS NOT NULL)) AS delivered,
    count(*) FILTER (WHERE (c.confirmed_by IS NOT NULL)) AS acked,
    count(*) FILTER (WHERE ((c.confirmed_by IS NOT NULL) AND (COALESCE(r.kind, 'self'::text) = 'self'::text))) AS acked_by_us,
    count(*) FILTER (WHERE (COALESCE(r.kind, 'self'::text) = 'operator'::text)) AS acked_by_operator,
    count(*) FILTER (WHERE (COALESCE(r.kind, 'self'::text) = 'external'::text)) AS acked_by_asset,
    min(c.issued_at) AS first_issued,
    max(c.issued_at) AS last_issued
   FROM (ottoq_vehicle_commands c
     LEFT JOIN ottoq_command_actor_registry r ON ((r.actor = c.confirmed_by)))
  GROUP BY c.data_source;

-- the events the isolation check reads
CREATE TABLE public.ottoq_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_type text NOT NULL, actor_type text, actor_id text,
  entity_id uuid, payload jsonb, data_source text, sim_run_id uuid, severity text);

CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  IF p_actor_type NOT IN ('fleet_operator_admin','fleet_operator_viewer','oem_dispatch_webhook','oem_admin_console','depot_tech',
     'depot_supervisor','command_center_operator','ottoq_engine','ottow_driver','ottow_dispatcher','otto_response_agent',
     'system_scheduler','external_sensor','ocpp_charger','av_vehicle','bess_controller','solar_controller','migration_script',
     'system','unknown') THEN
    RAISE EXCEPTION 'new row for relation "ottoq_events" violates check constraint "ottoq_events_actor_type_check"' USING ERRCODE = '23514';
  END IF;
  INSERT INTO public.stub_events (event_type, actor_type, actor_id, entity_id, payload, ingest_source, data_source, sim_run_id, severity)
  VALUES (p_event_type, p_actor_type, p_actor_id, p_entity_id, p_payload, p_ingest_source, p_data_source, p_sim_run_id, p_severity);
  INSERT INTO public.ottoq_events (event_id, event_type, actor_type, actor_id, entity_id, payload, data_source, sim_run_id, severity)
  VALUES (v_id, p_event_type, p_actor_type, p_actor_id, p_entity_id, p_payload, p_data_source, p_sim_run_id, p_severity);
  RETURN v_id;
END $f$;

-- the walk, as a stand-in (see the header)
CREATE TABLE public.stub_walk_mode (reports boolean NOT NULL);
INSERT INTO public.stub_walk_mode VALUES (false);

CREATE OR REPLACE FUNCTION twin.ottoq_sim_confirm_commands(p_sim_run_id uuid, p_clock timestamp with time zone)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
  v_only uuid[] := CASE WHEN current_setting('ottoq.apply_only', true) ~ '^\{[0-9a-f,-]*\}$'
                        THEN current_setting('ottoq.apply_only', true)::uuid[] END;
  v_report boolean;
  c record; v_ok boolean; n integer := 0;
BEGIN
  v_report := v_only IS NOT NULL AND (SELECT reports FROM public.stub_walk_mode LIMIT 1);
  FOR c IN SELECT cmd.* FROM public.ottoq_vehicle_commands cmd
            WHERE cmd.sim_run_id = p_sim_run_id AND cmd.status = 'issued' AND (v_only IS NULL OR cmd.command_id = ANY (v_only))
              AND (NOT v_report OR NOT EXISTS (SELECT 1 FROM twin.ottoq_twin_operator_log o
                                                WHERE o.sim_run_id = p_sim_run_id AND o.command_id = cmd.command_id
                                                  AND o.outcome IS NOT NULL))
            ORDER BY cmd.issued_at, cmd.vehicle_id, cmd.command_type, COALESCE(cmd.payload ->> 'stall_id', ''), cmd.command_seq
  LOOP
    v_ok := NOT (c.payload ? 'stall_id') OR EXISTS (
      SELECT 1 FROM public.stalls s WHERE s.id = (c.payload ->> 'stall_id')::uuid
         AND (s.current_vehicle_id IS NULL OR s.current_vehicle_id = c.vehicle_id));
    IF v_ok AND c.payload ? 'stall_id' THEN
      UPDATE public.stalls SET current_vehicle_id = NULL WHERE current_vehicle_id = c.vehicle_id AND id <> (c.payload ->> 'stall_id')::uuid;
      UPDATE public.stalls SET current_vehicle_id = c.vehicle_id WHERE id = (c.payload ->> 'stall_id')::uuid;
      UPDATE public.vehicles SET current_stall_id = (c.payload ->> 'stall_id')::uuid WHERE id = c.vehicle_id;
    END IF;
    IF v_report THEN
      INSERT INTO twin.ottoq_twin_operator_log (sim_run_id, command_id, outcome, reason_code, refusal_reason, walked_at, walks)
      VALUES (p_sim_run_id, c.command_id, CASE WHEN v_ok THEN 'executed' ELSE 'refused' END,
              CASE WHEN v_ok THEN NULL ELSE 'target_occupied' END, CASE WHEN v_ok THEN NULL ELSE 'stall_unavailable' END, p_clock, 1)
      ON CONFLICT (sim_run_id, command_id) DO UPDATE
        SET outcome = EXCLUDED.outcome, reason_code = EXCLUDED.reason_code, refusal_reason = EXCLUDED.refusal_reason,
            walked_at = EXCLUDED.walked_at, walks = twin.ottoq_twin_operator_log.walks + 1;
    ELSE
      UPDATE public.ottoq_vehicle_commands
         SET status = CASE WHEN v_ok THEN 'executed' ELSE 'refused' END, confirmed_at = p_clock,
             confirmed_by = CASE WHEN v_ok THEN 'otto_q_preflight' ELSE 'otto_q_preflight_refusal' END,
             reason_code = CASE WHEN v_ok THEN NULL ELSE 'target_occupied' END,
             executed_at = CASE WHEN v_ok THEN p_clock END,
             payload = CASE WHEN v_ok THEN payload ELSE COALESCE(payload, '{}'::jsonb) || '{"refusal_reason":"stall_unavailable"}' END
       WHERE command_id = c.command_id;
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END $f$;

-- the twin depot's newest run, completed: 0653's V1 probes on a copy of it, as it does live
INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, run_by, started_at, sim_clock_current, tick_interval_seconds, time_scale)
VALUES ('bbbbbbbb-0000-0000-0000-00000000000b', '11111111-1111-1111-1111-111111111111', 'completed', 'operator_demo',
        now(), '2026-10-09T12:00:00Z', 30, 60);
