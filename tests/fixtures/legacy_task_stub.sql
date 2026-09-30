-- Stub engine for 0603 (tests/test_legacy_task_sql.py). HW.005's evaluator is the live body, byte for byte (prosrc md5
-- e744b5be3b873f4758a186f9b320f032); schedule_tasks carries the columns it and 0603 read, with the four orphaned rows as
-- measured on 2026-09-30 and completed rows around them. The table's state-change trigger is a stub that records the
-- run context and actor it was written under, which is what 0603 sets.

CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE TYPE public.task_status AS ENUM ('pending','vehicle_en_route','in_progress','completed','skipped','exception','cancelled');
CREATE TYPE public.ottoq_rule_result AS (passed boolean, reason text, severity_override text, payload jsonb, suggested_action text);
CREATE TABLE public.schedule_tasks (
  id uuid PRIMARY KEY, vehicle_id uuid NOT NULL, depot_id uuid, service_code text, status public.task_status NOT NULL,
  actual_start timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  notes text);
INSERT INTO public.schedule_tasks (id, vehicle_id, depot_id, service_code, status, created_at, updated_at) VALUES
  ('54031064-b05a-41ab-917b-4134862778cc', '229f655b-803c-47c0-95fd-ca8adb9d8ef0', '11111111-1111-1111-1111-111111111111',
   'exterior_wash', 'in_progress', '2026-06-04 18:03:26.642115+00', '2026-06-04 18:03:26.642115+00'),
  ('9c8bd438-e8c1-4579-ae81-05594d16c432', '229f655b-803c-47c0-95fd-ca8adb9d8ef0', '11111111-1111-1111-1111-111111111111',
   'inspection', 'in_progress', '2026-06-04 18:03:26.642115+00', '2026-06-18 03:58:58.554204+00'),
  ('cdffb3c8-22e0-41d9-ac80-f896c1ecf978', '675dfb5c-66ec-466b-b0bf-d2bd9d519538', '11111111-1111-1111-1111-111111111111',
   'exterior_wash', 'in_progress', '2026-06-04 18:03:26.642115+00', '2026-06-04 18:03:26.642115+00'),
  ('1415d036-749b-4e0b-89e7-0692559ae0eb', 'a1111111-0001-0001-0001-000000000001', '11111111-1111-1111-1111-111111111111',
   'inspection', 'in_progress', '2026-06-04 18:03:26.642115+00', '2026-06-18 04:07:40.920806+00'),
  ('00000000-0000-0000-0000-00000000c001', '229f655b-803c-47c0-95fd-ca8adb9d8ef0', '11111111-1111-1111-1111-111111111111',
   'charge', 'completed', '2026-06-04 18:03:26.642115+00', '2026-06-18 04:07:40.920806+00');

CREATE TABLE public.stub_task_events (task_id uuid, run_ctx text, actor_type text, actor_id text, new_status text);
CREATE FUNCTION public.stub_task_state_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.stub_task_events VALUES (NEW.id, current_setting('ottoq.sim_run_id', true),
    current_setting('ottoq.actor_type', true), current_setting('ottoq.actor_id', true), NEW.status::text);
  RETURN NEW;
END $$;
CREATE TRIGGER trg_ottoq_schedule_tasks_state_change AFTER UPDATE ON public.schedule_tasks
  FOR EACH ROW EXECUTE FUNCTION public.stub_task_state_change();
CREATE FUNCTION public.update_timestamp() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER trg_schedule_tasks_updated BEFORE UPDATE ON public.schedule_tasks FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text, classified_at timestamptz);
CREATE TABLE public.stub_in_flight (n int NOT NULL);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) RETURNS integer
  LANGUAGE sql STABLE AS $$ SELECT n FROM public.stub_in_flight $$;

-- the live HW.005 evaluator, byte for byte
CREATE FUNCTION public.ottoq_eval_hw_005_vehicle_one_task(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_vehicle_id   UUID;
  v_active_count INTEGER;
  v_active_ids   UUID[];
BEGIN
  v_vehicle_id := COALESCE(NULLIF(p_context ->> 'vehicle_id','')::UUID, CASE WHEN p_entity_type='vehicle' THEN p_entity_id END);
  IF v_vehicle_id IS NULL THEN
    RETURN ROW(TRUE, 'no vehicle context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  SELECT count(*), array_agg(id) INTO v_active_count, v_active_ids
    FROM schedule_tasks
   WHERE vehicle_id = v_vehicle_id
     AND status IN ('in_progress','vehicle_en_route');   -- H4: real enum values

  IF COALESCE(v_active_count,0) > 1 THEN
    RETURN ROW(FALSE, format('vehicle has %s simultaneously active tasks', v_active_count),
      'critical', jsonb_build_object('vehicle_id', v_vehicle_id, 'active_count', v_active_count, 'active_task_ids', to_jsonb(v_active_ids)),
      'serialize_tasks')::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, format('vehicle has %s active task(s)', COALESCE(v_active_count,0)),
    NULL, jsonb_build_object('active_count', COALESCE(v_active_count,0)), NULL)::ottoq_rule_result;
END;
$function$;
