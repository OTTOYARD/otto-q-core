-- tests/fixtures/agent_actor_registry_stub.sql -- what 0702 reads and patches that tests/fixtures/agent_production_arm_stub.sql
-- (0629's stub) does not carry, as the live database held it on 2026-10-13: the AI.001 evaluator and the FR1 benchmark
-- procedure (pg_get_functiondef's output, byte for byte, so 0702's md5 premises pass against them), the rule-result type
-- the evaluator returns, the AI.001 rule row, the two catalog rows 0702's probes write (deploy_peak_fraction,
-- energy_mpc_follow), a slice of the shield's policy_write log, and the two settings an unnamed or chat-seat writer left
-- (the 2026-07-15 'ottocommand' rows). Loaded AFTER 0629's stub and 0629 itself, which together reproduce the live
-- setter, clamp, predicate, refusal and production_start byte for byte (tests/test_agent_actor_registry_sql.py proves it).
-- Then the table 0716 guards, as live has it (columns, defaults, constraints; read 2026-10-13 19:04:15 UTC), with the
-- twin's plans in the shape live holds them (charger_fault_repair v1 superseded by the sourced dossier, v4 active by the
-- feed agent), so that db/migrations/0716 itself can be loaded next: it creates the promote door (the predicate's sixth
-- caller), its trigger and its evidence table exactly as live holds them (the test proves the md5s), and its own V
-- block needs an active plan to try to retire. And the read-only diagnostic role as live has it (a member of
-- pg_read_all_data that bypasses row security), so 0702's grant to it is exercised.
SET check_function_bodies = off;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_read_only_user') THEN
    CREATE ROLE supabase_read_only_user NOLOGIN BYPASSRLS;
    GRANT pg_read_all_data TO supabase_read_only_user;
  END IF;
END $roles$;

CREATE TABLE public.ottoq_run_scope_registry (table_schema text, table_name text, column_name text, class text, note text);
CREATE TABLE public.ottoq_feed_plans (
  plan_id     uuid NOT NULL DEFAULT gen_random_uuid(),
  var_key     text NOT NULL,
  version     integer NOT NULL,
  status      text NOT NULL DEFAULT 'active'::text,
  method      text NOT NULL,
  plan        jsonb NOT NULL,
  provenance  jsonb NOT NULL,
  authored_by text NOT NULL,
  rationale   text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_feed_plans_pkey PRIMARY KEY (plan_id),
  CONSTRAINT ottoq_feed_plans_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'superseded'::text]))),
  CONSTRAINT ottoq_feed_plans_var_key_version_key UNIQUE (var_key, version));
INSERT INTO public.ottoq_feed_plans (plan_id, var_key, version, status, method, plan, provenance, authored_by, rationale) VALUES
  ('ef4eac4a-d017-42ce-9b98-99112df8dcd7', 'charger_fault_repair', 1, 'superseded', 'quantile_grid',
   '{"base_session_fault_p": 0.05}', '{}', 'dossier_v1', 'sourced'),
  ('0dd38d00-710e-4825-aa71-cc61561ab7fd', 'charger_fault_repair', 4, 'active', 'quantile_grid',
   '{"base_session_fault_p": 0.055}', '{}', 'nemotron-3-ultra', 'fitted to the twin''s own rate'),
  (gen_random_uuid(), 'ambient_temp_c', 1, 'active', 'profile', '{}', '{}', 'dossier_v1', 'sourced');

CREATE TYPE public.ottoq_rule_result AS (passed boolean, reason text, severity_override text, payload jsonb,
                                         suggested_action text);

CREATE TABLE public.ottoq_rules (rule_code text, version integer, status text, default_parameters jsonb,
                                 evaluator_function text);
INSERT INTO public.ottoq_rules VALUES
  ('AI.001.agent_dial_within_envelope', 1, 'active', '{"agent_actors": ["ottoq_prime"]}',
   'ottoq_rule_eval_agent_dial_envelope');

CREATE TABLE public.ottoq_rule_evaluations (evaluation_seq bigserial PRIMARY KEY, evaluated_at timestamptz DEFAULT now(),
                                            rule_code text, action_context text, context jsonb, sim_run_id uuid);
INSERT INTO public.ottoq_rule_evaluations (evaluated_at, rule_code, action_context, context) VALUES
  (now() - interval '2 days', 'AI.001.agent_dial_within_envelope', 'policy_write', '{"by": "auto:operator_demo"}'),
  (now() - interval '2 days', 'AI.001.agent_dial_within_envelope', 'policy_write', '{"by": "scenario_loader"}'),
  (now() - interval '1 day',  'AI.001.agent_dial_within_envelope', 'policy_write', '{"by": "sweep_window_cron:close"}'),
  (now() - interval '1 day',  'AI.001.agent_dial_within_envelope', 'policy_write', '{"by": "ottoq_prime"}'),
  (now() - interval '40 days', 'AI.001.agent_dial_within_envelope', 'policy_write', '{"by": "outside_the_window"}');

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, agent_writable, agent_min_value, agent_max_value, agent_max_drift_pct)
VALUES
  ('deploy_peak_fraction', NULL, 0.90, 0.30, 1.00, false, 0.5, 1.0, NULL),
  ('energy_mpc_follow', NULL, 0, 0, 1, false, NULL, NULL, NULL);

-- the live 'ottocommand' rows: one written by the FR1 procedure through the setter's default p_by (its run no longer
-- exists), one at the benchmark depot; and a person's UI write at the twin depot
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('run', 'f1000002-0000-4000-8000-000000000001', 'energy_mpc_follow', 1, 'ottocommand', '2026-07-15 05:20:18+00'),
       ('depot', '22222222-2222-2222-2222-222222222222', 'energy_reserve_shave', 0, 'ottocommand', '2026-07-15 14:26:04+00'),
       ('depot', '11111111-1111-1111-1111-111111111111', 'energy_demand_factor_peak', 0.53, 'orchestra_ui',
        '2026-07-20 15:51:37+00');

-- ── live: ottoq_rule_eval_agent_dial_envelope (7af6e2b7) ──
CREATE OR REPLACE FUNCTION public.ottoq_rule_eval_agent_dial_envelope(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_key      text;
  v_by       text;
  v_req      numeric;
  v_actors   text[];
  v_writable boolean;
  v_lo       numeric;
  v_hi       numeric;
  v_found    boolean := false;
  v_payload  jsonb;
BEGIN
  v_key := NULLIF(p_context ->> 'param_key', '');
  v_by  := COALESCE(p_context ->> 'by', '');
  BEGIN
    v_req := (p_context ->> 'requested')::numeric;
  EXCEPTION WHEN OTHERS THEN
    v_req := NULL;
  END;

  -- Parameterizable like every other rule's thresholds, so a second agent
  -- identity is a data change rather than a migration.
  v_actors := COALESCE(
    NULLIF(ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'agent_actors')), '{}'),
    ARRAY['ottoq_prime']);

  -- A malformed probe is not a violation. ottoq_policy_set refuses a NULL value
  -- and an unknown param on its own, with its own error codes; this rule must
  -- not double-report those as an envelope breach.
  IF v_key IS NULL OR v_req IS NULL THEN
    RETURN ROW(TRUE, 'no dial write to judge', NULL,
      jsonb_build_object('source','policy_write','judged',false,
                         'why','param_key or requested absent'),
      NULL)::public.ottoq_rule_result;
  END IF;

  IF NOT public.ottoq_is_agent_actor(v_by, v_actors) THEN  -- 0414: prefix-aware, so ottoq_prime:promoter is judged
    RETURN ROW(TRUE, format('actor %s is not an agent', v_by), NULL,
      jsonb_build_object('source','policy_write','judged',false,
                         'param_key',v_key,'by',v_by,'requested',v_req),
      NULL)::public.ottoq_rule_result;
  END IF;

  -- From here the actor IS an agent, and every branch below is a verdict.
  SELECT c.agent_writable, c.agent_min_value, c.agent_max_value, true
    INTO v_writable, v_lo, v_hi, v_found
    FROM public.ottoq_policy_param_catalog c
   WHERE c.param_key = v_key;

  v_payload := jsonb_build_object(
    'source','policy_write','judged',true,
    'param_key',v_key,'by',v_by,'requested',v_req,
    'agent_lo',v_lo,'agent_hi',v_hi,
    'agent_writable',COALESCE(v_writable,false));

  IF NOT v_found THEN
    RETURN ROW(FALSE, format('agent wrote an uncatalogued dial: %s', v_key), 'critical',
      v_payload, 'catalog_the_dial_or_remove_it_from_the_agent')::public.ottoq_rule_result;
  END IF;

  IF NOT v_writable THEN
    RETURN ROW(FALSE, format('dial %s is not agent-writable', v_key), 'critical',
      v_payload, 'set_agent_writable_or_block_the_actor')::public.ottoq_rule_result;
  END IF;

  IF v_lo IS NOT NULL AND v_req < v_lo THEN
    RETURN ROW(FALSE, format('%s = %s is below the agent floor %s', v_key, v_req, v_lo),
      'critical', v_payload, 'clamp_to_agent_envelope')::public.ottoq_rule_result;
  END IF;

  IF v_hi IS NOT NULL AND v_req > v_hi THEN
    RETURN ROW(FALSE, format('%s = %s is above the agent ceiling %s', v_key, v_req, v_hi),
      'critical', v_payload, 'clamp_to_agent_envelope')::public.ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE, format('%s = %s within agent envelope [%s, %s]', v_key, v_req, v_lo, v_hi),
    NULL, v_payload, NULL)::public.ottoq_rule_result;
END;
$function$
;

-- ── live: ottoq_fr1_cert_arm (2c7b9c06). Never executed here: it resets the benchmark depot. Its source is what 0702
--    patches. ──
CREATE OR REPLACE PROCEDURE public.ottoq_fr1_cert_arm(IN p_run uuid, IN p_seed bigint, IN p_ab_group uuid, IN p_ticks integer, IN p_start timestamp with time zone, IN p_mpc boolean DEFAULT false)
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $procedure$
DECLARE i int; v_wseed bigint; v_deploy_n int; v_total int;
        d uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  PERFORM ottoq_benchmark_reset(d, 30, 80);
  UPDATE ottoq_bess_units SET current_soc_pct=90.0, current_soc_kwh=capacity_kwh*0.90, current_temperature_c=25.0,
         current_power_kw=0 WHERE depot_id=d;
  v_wseed := abs(hashtextextended(p_seed::text || p_ab_group::text || 'wave', 17));
  SELECT count(*) INTO v_total FROM vehicles WHERE home_depot_id=d AND category='autonomous';
  v_deploy_n := FLOOR(v_total * 0.85);
  UPDATE vehicles SET current_soc = 90 + ottoq_sim_seeded_random(v_wseed,'soc:'||id::text)*8,
                      target_soc = 90, current_state='staged_for_departure', current_stall_id=NULL, last_state_change=p_start
   WHERE home_depot_id=d AND category='autonomous';
  INSERT INTO ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, sim_clock_start, sim_clock_current, sim_clock_end,
    depot_id, time_scale, tick_interval_seconds, status, policy, run_by, tick_count, random_seed, ab_group_id,
    started_at, last_tick_at, next_tick_due_at)
  VALUES (p_run, 'ef24648f-eaf6-4686-bd07-1e018a8224ab','normal_day', p_start, p_start, p_start + interval '24 hours',
    d, 60, 30, 'running', 'otto_q', 'benchmark', 0, p_seed, p_ab_group, p_start, p_start, p_start);
  IF p_mpc THEN PERFORM ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1); END IF;
  WITH picked AS (
    SELECT v.id, v.fleet_operator_id, v.current_soc FROM vehicles v
    WHERE v.home_depot_id=d AND v.category='autonomous'
    ORDER BY ottoq_sim_seeded_random(v_wseed, 'pick:'||v.id::text) LIMIT v_deploy_n)
  INSERT INTO ottoq_vehicle_dispatches (dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status)
  SELECT gen_random_uuid(), p.id, p_run, p.fleet_operator_id, p_start,
         p_start + ((360 + ottoq_sim_seeded_random(v_wseed,'ret:'||p.id::text)*240) || ' minutes')::interval,
         420, p.current_soc, 'active' FROM picked p;
  UPDATE vehicles SET current_state='deployed', last_state_change=p_start
   WHERE id IN (SELECT vehicle_id FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_run AND status='active');
  FOR i IN 1..p_ticks LOOP
    PERFORM ottoq_sim_advance_and_snapshot(p_run);
    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> 'running';
  END LOOP;
  PERFORM ottoq_score_run(p_run);
  UPDATE ottoq_sim_runs SET status='aborted' WHERE sim_run_id=p_run;
END $procedure$
;

SET check_function_bodies = on;
