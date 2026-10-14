-- tests/fixtures/blackbox_rpc_grants_stub.sql: the two Black Box export functions 0720 closes, in miniature.
--
-- What it reproduces from the live engine (read 2026-10-14 from 14:49:46 UTC, db/migrations/0720 §1):
--   * public.ottoq_run_blackbox(uuid) and public.ottoq_run_blackbox_meta(uuid) with their LIVE definitions, byte for
--     byte (decoded from base64 of pg_get_functiondef; md5 4f96d37ef15bcf3fac9a79023f99c729 and
--     06ec6069b1f08a5ce51a18e2e2764123), and their LIVE ACLs, both
--     {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres};
--   * the relations their bodies read, cut down to the columns they name plus a few: ottoq_sim_runs, one run-scoped
--     table (ottoq_decisions), vehicles, stalls, ocpp_sessions; one stopped run at the twin depot with rows in each;
--   * ottoq_blackbox_latest_run() with its live ACL (anon may execute it), which 0720 leaves alone;
--   * the bookkeeping 0720 writes (ottoq_schema_snapshots, ottoq_cert_lineage) and a settable in-flight probe.
-- Loads on a plain PostgreSQL 16 or 17 as a superuser named postgres.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- the engine's bookkeeping, as the migrations use it
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(), label text NOT NULL,
  object_kind text NOT NULL, schema_name text NOT NULL, object_name text NOT NULL, definition text NOT NULL,
  def_md5 text NOT NULL);
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean NOT NULL, forces_dial_restart boolean, note text NOT NULL,
  classified_at timestamptz NOT NULL);
CREATE TABLE public.stub_in_flight (n integer NOT NULL DEFAULT 0);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT true)
RETURNS integer LANGUAGE sql STABLE AS $f$ SELECT n FROM public.stub_in_flight LIMIT 1 $f$;

-- what the two bodies read. The browser roles hold no table privilege here, as live (0658 took them): whatever a
-- caller gets, it gets through the SECURITY DEFINER functions.
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, depot_id uuid NOT NULL, run_by text NOT NULL, status text NOT NULL,
  scenario_code text, started_at timestamptz NOT NULL, ended_at timestamptz, tick_count integer, demo_speed_x numeric);
CREATE TABLE public.ottoq_decisions (
  decision_id bigserial PRIMARY KEY, sim_run_id uuid NOT NULL, vehicle_id uuid, decision_kind text NOT NULL);
CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, name text NOT NULL, owning_sim_run_id uuid, current_depot_id uuid);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid NOT NULL, stall_type text NOT NULL);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY, depot_id uuid NOT NULL, started_at timestamptz NOT NULL);
REVOKE ALL ON public.ottoq_sim_runs, public.ottoq_decisions, public.vehicles, public.stalls, public.ocpp_sessions
  FROM PUBLIC, anon, authenticated;

INSERT INTO public.ottoq_sim_runs VALUES
  ('d0000000-0000-4000-8000-000000000720', '11111111-1111-1111-1111-111111111111', 'operator_demo', 'completed',
   'busy_day', '2026-10-13 14:00:00+00', '2026-10-13 20:00:00+00', 720, 1);
INSERT INTO public.ottoq_decisions (sim_run_id, vehicle_id, decision_kind) VALUES
  ('d0000000-0000-4000-8000-000000000720', 'c0000000-0000-4000-8000-000000000001', 'stall_assignment'),
  ('d0000000-0000-4000-8000-000000000720', 'c0000000-0000-4000-8000-000000000002', 'charge_start');
INSERT INTO public.vehicles VALUES
  ('c0000000-0000-4000-8000-000000000001', 'Waymo-AV-001', NULL, '11111111-1111-1111-1111-111111111111'),
  ('c0000000-0000-4000-8000-000000000002', 'Zoox-AV-002', NULL, '11111111-1111-1111-1111-111111111111');
INSERT INTO public.stalls VALUES
  ('5a000000-0000-4000-8000-000000000001', '11111111-1111-1111-1111-111111111111', 'dcfc');
INSERT INTO public.ocpp_sessions VALUES
  ('0c000000-0000-4000-8000-000000000001', '11111111-1111-1111-1111-111111111111', '2026-10-13 15:00:00+00');

-- ── public.ottoq_run_blackbox(uuid), byte for byte as live (pg_get_functiondef md5 4f96d37ef15bcf3fac9a79023f99c729) ──
CREATE OR REPLACE FUNCTION public.ottoq_run_blackbox(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_meta jsonb; v_code jsonb; v_data jsonb := '{}'::jsonb; v_tbl text; v_rows jsonb; v_depot uuid;
BEGIN
  PERFORM set_config('statement_timeout', '150000', true);  -- export can take a moment to assemble; give it room
  SELECT to_jsonb(r), r.depot_id INTO v_meta, v_depot FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_meta IS NULL THEN RETURN jsonb_build_object('error','run not found','sim_run_id',p_sim_run_id); END IF;

  SELECT jsonb_object_agg(proname, pg_get_functiondef(oid)) INTO v_code
  FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)';

  FOR v_tbl IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='sim_run_id' AND table_name LIKE 'ottoq%'
     ORDER BY table_name
  LOOP
    BEGIN
      EXECUTE format('SELECT jsonb_agg(to_jsonb(t)) FROM (SELECT * FROM public.%I WHERE sim_run_id=$1 LIMIT 200000) t', v_tbl)
        INTO v_rows USING p_sim_run_id;
      v_data := v_data || jsonb_build_object(v_tbl, COALESCE(v_rows, '[]'::jsonb));
    EXCEPTION WHEN OTHERS THEN
      v_data := v_data || jsonb_build_object(v_tbl, jsonb_build_object('_export_error', SQLERRM));
    END;
  END LOOP;

  v_data := v_data || jsonb_build_object('vehicles',
    COALESCE((SELECT jsonb_agg(to_jsonb(v)) FROM vehicles v WHERE v.owning_sim_run_id = p_sim_run_id OR v.current_depot_id = v_depot), '[]'::jsonb));
  v_data := v_data || jsonb_build_object('stalls',
    COALESCE((SELECT jsonb_agg(to_jsonb(s)) FROM stalls s WHERE s.depot_id = v_depot), '[]'::jsonb));
  v_data := v_data || jsonb_build_object('ocpp_sessions',
    COALESCE((SELECT jsonb_agg(to_jsonb(o)) FROM ocpp_sessions o WHERE o.depot_id = v_depot AND o.started_at >= (v_meta->>'started_at')::timestamptz), '[]'::jsonb));

  RETURN jsonb_build_object(
    'black_box_version', '1.0', 'generated_at', now(), 'sim_run_id', p_sim_run_id, 'run', v_meta,
    'edge_fn_ai_sources', jsonb_build_object('_note','AI seam code lives in the edge-function store, not pg_proc',
       'cuopt','ottoq-cuopt-propose','nemotron_conductor','ottoq-orchestrator-agent'),
    'executed_code', v_code, 'data', v_data);
END;
$function$
;

-- ── public.ottoq_run_blackbox_meta(uuid), byte for byte as live (pg_get_functiondef md5 06ec6069b1f08a5ce51a18e2e2764123) ──
CREATE OR REPLACE FUNCTION public.ottoq_run_blackbox_meta(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'black_box_version','1.0','generated_at',now(),'sim_run_id',p_sim_run_id,
    'run', (SELECT to_jsonb(r) FROM ottoq_sim_runs r WHERE r.sim_run_id=p_sim_run_id),
    'depot_id', (SELECT depot_id FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id),
    'executed_code', (SELECT jsonb_object_agg(proname, pg_get_functiondef(oid)) FROM pg_proc
       WHERE pronamespace='public'::regnamespace
         AND proname ~ '^ottoq_(sim_|decide_tick|greedy_tick|fifo_tick|manual_tick|l2_|cuopt_|energy_orchestrate|orchestrator_trigger|apply_ops_action|demo_metronome|deploy_target|policy_get|policy_set|shield|plan_visit|itin_leg|mark_visit|record_event|active_charge_cap|deploy_target_fraction|run_blackbox|sim_stop_and_reset)'),
    'data_tables', (SELECT jsonb_agg(table_name ORDER BY table_name) FROM information_schema.columns
       WHERE table_schema='public' AND column_name='sim_run_id' AND table_name LIKE 'ottoq%'),
    'edge_fn_ai_sources', jsonb_build_object('cuopt','ottoq-cuopt-propose','nemotron_conductor','ottoq-orchestrator-agent')
  );
$function$
;

-- the live ACLs: no PUBLIC, no anon; postgres, authenticated and service_role, in that order
REVOKE ALL ON FUNCTION public.ottoq_run_blackbox(uuid), public.ottoq_run_blackbox_meta(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_run_blackbox(uuid), public.ottoq_run_blackbox_meta(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_run_blackbox(uuid), public.ottoq_run_blackbox_meta(uuid) TO service_role;

-- the discovery read 0720 leaves alone, its live body and live ACL (anon may execute it)
CREATE FUNCTION public.ottoq_blackbox_latest_run()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT to_jsonb(t) FROM (
    SELECT sim_run_id,
           scenario_code,
           status,
           COALESCE(tick_count, 0)      AS tick_count,
           COALESCE(demo_speed_x, 1)    AS demo_speed_x
    FROM ottoq_sim_runs
    WHERE run_by = 'operator_demo'
    ORDER BY started_at DESC
    LIMIT 1
  ) t;
$function$;
REVOKE ALL ON FUNCTION public.ottoq_blackbox_latest_run() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_blackbox_latest_run() TO authenticated, service_role, anon;
