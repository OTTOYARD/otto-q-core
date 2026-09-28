-- ============================================================================================================
-- tests/fixtures/agent_gateway_stub_engine.sql
--
-- A STUB ENGINE for exercising db/migrations/0550 (and 0551) on a throwaway PostgreSQL. NOT the engine, NOT a
-- migration, NEVER applied anywhere real: the guard below refuses to run on a database that has ottoq_events or a
-- supabase_migrations schema. Loaded by tests/test_agent_gateway_sql.py into a database it creates and drops.
--
-- WHAT IS REAL IN HERE AND WHAT IS NOT, because a stub that pretends is worse than none:
--   * COPIED VERBATIM from the live catalog (gxdrcyphqjzjsuhxuqtg, read-only, 2026-09-28 ~05:00 UTC), and the test
--     asserts each one's md5(pg_get_functiondef()) against the md5 read from the live catalog the same night:
--       public.ottoq_hw_recall_vehicle          1460f1126e0e1faacf4cb3e68376da79   (the recall door)
--       public.ottoq_apply_ops_action           3ca7589f04aa9c1b76e38030c6952ca4   (the ops-action door)
--       public.ottoq_policy_set                 cabe39cc8e194ddf8e81f84b91181884   (what the ops door calls)
--       public.ottoq_dial_clamp                 b32246daf49a45430a2b59ea9f2bd3b3
--       public.ottoq_is_agent_actor             f349c63ad2c48b7756633024d6da263b
--       public.ottoq_policy_get                 60514764c4250d201c1ad0079f189584
--       ottoq.ottoq_stall_free_between          f5c4526d8243fe0ff3c192b65e9ef962   (gates two and three)
--       public.ottoq_twin_run_context           44b3bf3fc4a335c1b0226ae87cf62ae8
--       public.ottoq_vehicle_card               bbb2937f6fb4b9a7ab8383bb749f58a7
--       public.ottoq_check_run_scope_registry   4d0011f6bfd5d7448273ccd7c6bcc5dc
--   * STUBBED, with the live signature and the fields the gateway reads: ottoq_depot_cards (the live body joins a
--     dozen engine tables; this returns contract 1.4's shape from a stub_cards table), ottoq_activity_feed (returns
--     rows from stub_activity), ottoq_record_event (a no-op), auth.uid() (reads request.jwt.claim.sub, as
--     Supabase's does). Tables carry only the columns something here reads.
--   * The roles anon / authenticated / service_role and Supabase's default privileges on schema public are
--     reproduced, so a REVOKE that "removes nothing" would be caught here as it would be in production.
-- ============================================================================================================

DO $guard$
BEGIN
  IF to_regclass('public.ottoq_events') IS NOT NULL OR EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'supabase_migrations') THEN
    RAISE EXCEPTION 'agent_gateway_stub_engine.sql is a TEST STUB and this looks like a real engine. Refusing.';
  END IF;
END $guard$;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $roles$;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA public, extensions, ottoq, twin, auth TO anon, authenticated, service_role;

-- Supabase's default privileges on public (measured on the live project 2026-09-28): new tables readable by anon and
-- authenticated, everything for service_role; new functions executable by all three; sequences usable by all three.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, REFERENCES, TRIGGER ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $f$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.sub', true), ''),
                  (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$f$;

-- ── enums (live labels, 2026-09-28) ──
CREATE TYPE public.staff_role AS ENUM ('charging_tech','cleaning_tech','maintenance_tech','yard_supervisor','ops_manager','retail_concierge');
CREATE TYPE public.stall_type AS ENUM ('dcfc','l2','wash_bay','detail_bay','service_bay','staging','parking','safety');
CREATE TYPE public.vehicle_state AS ENUM ('offline','deployed','en_route_to_depot','arrived_at_gate','staged_awaiting_service',
  'charging_dcfc','charging_l2','charge_complete_holding','in_wash_bay','in_detail_bay','in_service_bay',
  'service_complete_holding','staged_for_departure','en_route_to_deployment','emergency_staged','tow_requested','out_of_service');

-- ── tables: only the columns something here reads ──
CREATE TABLE public.depots (id uuid PRIMARY KEY, name text NOT NULL);
CREATE TABLE public.fleet_operators (id uuid PRIMARY KEY, name text NOT NULL, is_active boolean NOT NULL DEFAULT true, auth_user_id uuid);
CREATE TABLE public.staff_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), auth_user_id uuid, depot_id uuid NOT NULL, first_name text NOT NULL,
  last_name text NOT NULL, display_name text, role public.staff_role NOT NULL, is_active boolean NOT NULL DEFAULT true);
CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, fleet_operator_id uuid, home_depot_id uuid NOT NULL, current_depot_id uuid, category text NOT NULL DEFAULT 'autonomous',
  make text, model text, display_name text, target_soc integer NOT NULL DEFAULT 90, current_soc integer,
  current_state public.vehicle_state NOT NULL DEFAULT 'staged_awaiting_service', current_stall_id uuid, is_active boolean NOT NULL DEFAULT true);
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, depot_id uuid, station_state text NOT NULL);
CREATE TABLE public.stalls (
  id uuid PRIMARY KEY, depot_id uuid NOT NULL, stall_code text NOT NULL, stall_type public.stall_type NOT NULL, status text NOT NULL,
  current_vehicle_id uuid, reserved_by uuid, ocpp_charger_id uuid, staging_role text, zone text, distance_from_entrance integer);
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, depot_id uuid, scenario_code text NOT NULL DEFAULT 'busy_day', status text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(), sim_clock_current timestamptz NOT NULL, tick_count integer NOT NULL DEFAULT 0,
  random_seed bigint NOT NULL DEFAULT 424242, policy text NOT NULL DEFAULT 'otto_q', demo_speed_x numeric NOT NULL DEFAULT 8, run_by text);
CREATE TABLE public.ottoq_stall_bookings (
  booking_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid NOT NULL REFERENCES public.ottoq_sim_runs(sim_run_id),
  stall_id uuid NOT NULL, vehicle_id uuid NOT NULL, state text NOT NULL, during tstzrange NOT NULL);
CREATE TABLE public.ottoq_itinerary_legs (
  leg_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id),
  vehicle_id uuid, to_stall_id uuid, status text, planned_end_sim timestamptz);
CREATE TABLE public.ottoq_vehicle_commands (
  command_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id), depot_id uuid,
  vehicle_id uuid NOT NULL, command_type text NOT NULL, payload jsonb, issued_at timestamptz NOT NULL, issued_by text NOT NULL DEFAULT 'decide_tick',
  status text NOT NULL DEFAULT 'issued', created_at timestamptz NOT NULL DEFAULT now(),
  command_seq bigint GENERATED BY DEFAULT AS IDENTITY, data_source text NOT NULL DEFAULT 'twin');
CREATE TABLE public.ottoq_deploy_log (sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id), policy text);
CREATE TABLE public.ottoq_policy_param_catalog (
  param_key text PRIMARY KEY, description text, default_value numeric, min_value numeric, max_value numeric, affects text,
  min_exclusive numeric, max_exclusive numeric, agent_writable boolean, agent_min_value numeric, agent_max_value numeric,
  agent_max_drift_pct numeric);
CREATE TABLE public.ottoq_policy_params (
  scope_type text NOT NULL, scope_id uuid NOT NULL, param_key text NOT NULL, param_value numeric NOT NULL,
  updated_by text DEFAULT 'system', updated_at timestamptz DEFAULT now(), PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_run_scope_registry (
  table_schema text NOT NULL, table_name text NOT NULL, column_name text NOT NULL,
  class text NOT NULL CHECK (class = ANY (ARRAY['engine'::text, 'stamp'::text, 'evidence'::text, 'run_ledger'::text])),
  note text, registered_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (table_schema, table_name, column_name));
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL, classified_at timestamptz NOT NULL, forces_dial_restart boolean);
-- stub sources for the two stubbed reads
CREATE TABLE public.stub_cards (vehicle_id uuid PRIMARY KEY, card jsonb, last_decision jsonb);
CREATE TABLE public.stub_activity (
  sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id), occurred_at timestamptz, vehicle_id uuid, display_name text,
  action text, engine text, target text, outcome text, rationale jsonb, reason text, decision_seq bigint, tick_seq bigint,
  held_ticks integer, last_at timestamptz, standing boolean);

-- the run-scoped stub tables are registered as the engine registers its own, so the registry guard is clean before
-- 0550 touches it and "clean afterwards" means something
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
  ('public','ottoq_sim_runs','sim_run_id','run_ledger','stub'),
  ('public','ottoq_stall_bookings','sim_run_id','engine','stub'),
  ('public','ottoq_itinerary_legs','sim_run_id','engine','stub'),
  ('public','ottoq_vehicle_commands','sim_run_id','engine','stub'),
  ('public','ottoq_deploy_log','sim_run_id','engine','stub'),
  ('public','stub_activity','sim_run_id','engine','stub');

-- ── STUB: ottoq_record_event (live signature; records nothing) ──
CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS uuid LANGUAGE sql AS $f$ SELECT gen_random_uuid() $f$;

-- ── STUB: ottoq_depot_cards (live signature and contract 1.4 shape; cards come from stub_cards) ──
CREATE OR REPLACE FUNCTION public.ottoq_depot_cards(p_depot_id uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $f$
WITH run AS (
  SELECT sim_run_id, sim_clock_current, status AS run_status FROM ottoq_sim_runs
   WHERE depot_id = p_depot_id AND status IN ('running','paused') ORDER BY started_at DESC LIMIT 1),
veh AS (
  SELECT v.*, f.name AS operator_name FROM vehicles v LEFT JOIN fleet_operators f ON f.id = v.fleet_operator_id
   WHERE v.current_depot_id = p_depot_id AND (p_fleet_operator_id IS NULL OR v.fleet_operator_id = p_fleet_operator_id))
SELECT jsonb_build_object(
  'endpoint', 'ottoq.depot_cards', 'contract_version', '1.4', 'depot_id', p_depot_id, 'fleet_operator_id', p_fleet_operator_id,
  'sim_run_id', (SELECT sim_run_id FROM run), 'run_status', (SELECT run_status FROM run), 'sim_clock', (SELECT sim_clock_current FROM run),
  'vehicles', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'vehicle_id', vh.id, 'display_name', vh.display_name, 'oem', vh.make, 'model', vh.model,
      'operator', jsonb_build_object('id', vh.fleet_operator_id, 'name', vh.operator_name),
      'state', vh.current_state::text, 'soc', vh.current_soc, 'target_soc', vh.target_soc,
      'stall', CASE WHEN vh.current_stall_id IS NULL THEN NULL ELSE (
         SELECT jsonb_build_object('id', st.id, 'code', st.stall_code, 'kind', st.stall_type::text) FROM stalls st WHERE st.id = vh.current_stall_id) END,
      'reservations', '[]'::jsonb,
      'last_decision', sc.last_decision,
      'card', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN NULL ELSE sc.card END) ORDER BY vh.display_name)
      FROM veh vh LEFT JOIN stub_cards sc ON sc.vehicle_id = vh.id), '[]'::jsonb),
  'reservation_ledger', '{}'::jsonb)
$f$;

-- ── STUB: ottoq_activity_feed (live signature and columns; rows from stub_activity) ──
CREATE OR REPLACE FUNCTION public.ottoq_activity_feed(p_sim_run_id uuid, p_limit integer DEFAULT 200, p_vehicle_id uuid DEFAULT NULL::uuid, p_changes_only boolean DEFAULT false, p_window_ticks integer DEFAULT 240)
 RETURNS TABLE(occurred_at timestamp with time zone, vehicle_id uuid, display_name text, action text, engine text, target text, outcome text, rationale jsonb, reason text, decision_seq bigint, tick_seq bigint, held_ticks integer, last_at timestamp with time zone, standing boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $f$
  SELECT a.occurred_at, a.vehicle_id, a.display_name, a.action, a.engine, a.target, a.outcome, a.rationale, a.reason,
         a.decision_seq, a.tick_seq, a.held_ticks, a.last_at, a.standing
    FROM public.stub_activity a
   WHERE a.sim_run_id = p_sim_run_id AND (p_vehicle_id IS NULL OR a.vehicle_id = p_vehicle_id)
   ORDER BY a.occurred_at DESC
   LIMIT p_limit
$f$;

-- ═════════════ VERBATIM COPIES (bodies exactly as pg_get_functiondef printed them, 2026-09-28) ═════════════

CREATE OR REPLACE FUNCTION public.ottoq_is_agent_actor(p_by text, p_actors text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_actors, ARRAY['ottoq_prime'])) AS a(actor)
     WHERE COALESCE(p_by,'') = a.actor OR COALESCE(p_by,'') LIKE a.actor || ':%'
  );
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_dial_clamp(p_param_key text, p_requested numeric, p_by text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_min numeric; v_max numeric;
  v_alo numeric; v_ahi numeric; v_writable boolean;
  v_out numeric;
BEGIN
  SELECT c.min_value, c.max_value, c.agent_min_value, c.agent_max_value, c.agent_writable
    INTO v_min, v_max, v_alo, v_ahi, v_writable
    FROM public.ottoq_policy_param_catalog c WHERE c.param_key = p_param_key;
  v_out := GREATEST(v_min, LEAST(v_max, p_requested));
  IF public.ottoq_is_agent_actor(p_by) THEN
    v_out := GREATEST(v_alo, LEAST(v_ahi, v_out));
  END IF;
  RETURN v_out;
END
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v numeric; v_depot uuid; v_seen text;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN
    -- 0533 (G258): the read witness. A dial pair asks, after each arm, whether the arm read its own run-scoped value of
    -- the dial at all: a dial nothing reads at run scope cannot make two arms differ. One entry per run and key, in a
    -- transaction-local setting, so it costs nothing outside the run tier and leaves with the transaction.
    v_seen := COALESCE(current_setting('ottoq.run_scope_reads', true), '');
    IF strpos(v_seen, ',' || p_sim_run_id::text || ':' || p_param_key || ',') = 0 THEN
      PERFORM set_config('ottoq.run_scope_reads',
                         CASE WHEN v_seen = '' THEN ',' ELSE v_seen END || p_sim_run_id::text || ':' || p_param_key || ',', true);
    END IF;
    RETURN v;
  END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params
     WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  -- global tier: sentinel, not NULL (scope_id is in the primary key)
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid
     AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_policy_set(p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric, p_by text DEFAULT 'ottocommand'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_min numeric; v_max numeric; v_final numeric; v_minx numeric; v_maxx numeric;
BEGIN
  IF p_scope_type = 'sim_run' THEN p_scope_type := 'run'; END IF;
  IF p_scope_type NOT IN ('global','depot','run') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_scope_type','scope_type',p_scope_type,
                              'allowed',jsonb_build_array('global','depot','run'));
  END IF;

  -- Global rows key on the sentinel. A caller passing NULL for a global write used to hit
  -- the NOT NULL on a primary-key column; it now lands where ottoq_policy_get reads.
  IF p_scope_type = 'global' THEN
    p_scope_id := '00000000-0000-0000-0000-000000000000'::uuid;
  ELSIF p_scope_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','scope_id_required','scope_type',p_scope_type);
  END IF;

  -- 0306: A NULL VALUE IS A MALFORMED CALL, NOT A VALUE OUT OF RANGE.
  -- It is refused HERE, with the other argument validations and BEFORE the
  -- catalog lookup: it needs no catalog row to diagnose, it is the cheaper
  -- check, and a caller that passed NULL has a bug to fix whether or not the
  -- key is also wrong.
  --
  -- Measured before this guard existed: GREATEST/LEAST IGNORE NULLS, so
  -- GREATEST(v_min, LEAST(v_max, NULL)) is v_max -- a NULL input silently wrote
  -- the dial's MAXIMUM and returned ok:true. Worse, the field that should have
  -- warned was itself NULL-poisoned: `v_final <> p_param_value` is NULL, not
  -- true, so the response said clamped:null and a caller testing !clamped read
  -- it as "taken verbatim". On the seven dials 0304 catalogued NULL/NULL it
  -- failed the other way, raising a raw 23502 out of the INSERT instead of
  -- returning the refusal JSON every other path returns.
  --
  -- The clamp below KEEPS its NULL-ignoring behaviour on the BOUNDS -- that is
  -- what makes an unbounded catalog row mean "admit, clamp nothing" -- it just
  -- can no longer be reached with a NULL input.
  IF p_param_value IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','null_value','param',p_param_key,
                              'detail','param_value must not be NULL; it is not treated as '
                                       '"no change" and was previously clamped to the '
                                       'parameter maximum');
  END IF;

  SELECT min_value, max_value, min_exclusive, max_exclusive
    INTO v_min, v_max, v_minx, v_maxx
    FROM ottoq_policy_param_catalog WHERE param_key = p_param_key;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','unknown_param','param',p_param_key); END IF;
  v_final := public.ottoq_dial_clamp(p_param_key, p_param_value, p_by);  -- 0414: engine bounds, plus the agent envelope when p_by is an agent

  -- 0303 (G61): an EXCLUSIVE bound cannot be clamped -- there is no smallest
  -- numeric greater than x, and any epsilon would be invented. It is a validity
  -- constraint, so it REFUSES. Both columns are NULL for every dial whose floor
  -- is expressible inclusively, and a NULL bound skips this branch entirely, so
  -- the clamp above is untouched for all 148 keys catalogued before this file.
  IF (v_minx IS NOT NULL AND v_final <= v_minx)
     OR (v_maxx IS NOT NULL AND v_final >= v_maxx) THEN
    RETURN jsonb_build_object('ok',false,'error','outside_exclusive_bound','param',p_param_key,
                              'requested',p_param_value,'after_inclusive_clamp',v_final,
                              'exclusive_range',jsonb_build_array(v_minx,v_maxx));
  END IF;

    -- 0353: THE SHIELD LEARNS THAT DIAL WRITES EXIST.
  -- Probed HERE -- after every argument validation, after the catalog lookup,
  -- and BEFORE the clamped value is written -- so the rule judges what the
  -- caller ASKED for. A rule that only ever sees a post-clamp value can never
  -- fail, which is the vacuous-assertion class this repo has shipped twice.
  --
  -- entity_id is the scope id ONLY for non-run scopes. For scope_type='run' it
  -- would be the sim_run_id, which differs between the two arms of a
  -- determinism pair and IS digested by ottoq_hash_rule_evaluations; the run
  -- rides in the context column instead, which that hash does not read.
  --
  -- Error-swallowed on purpose: a reporting probe must never be able to refuse
  -- a write ottoq_policy_set would otherwise have accepted. The rule is
  -- registered log_only so it cannot block; this is the second belt.
  BEGIN
    PERFORM 1 FROM public.ottoq_shield_probe(
      p_action_context := 'policy_write',
      p_entity_type    := 'policy_param',
      p_entity_id      := CASE WHEN p_scope_type = 'run' THEN NULL ELSE p_scope_id END,
      p_context        := jsonb_build_object(
                            'param_key',  p_param_key,
                            'requested',  p_param_value,
                            'by',         p_by,
                            'scope_type', p_scope_type,
                            'scope_id',   p_scope_id));
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

-- 0432: agent_writable IS A GUARD, NOT A LABEL. ottoq_dial_clamp reads the flag into a variable and
  -- never uses it, and a non-writable dial's NULL agent bounds let an agent write straight through
  -- (db/checks/0352 section 5a). AI.001 at the probe above already DETECTS this case and names the remedy
  -- set_agent_writable_or_block_the_actor; this is that remedy. The probe has logged the attempt.
  IF public.ottoq_is_agent_actor(p_by)
     AND NOT COALESCE((SELECT c.agent_writable FROM ottoq_policy_param_catalog c
                        WHERE c.param_key = p_param_key), false) THEN
    RETURN jsonb_build_object('ok',false,'error','not_agent_writable','param',p_param_key,'by',p_by,
                              'detail','this dial is not an agent actuator (ottoq_policy_param_catalog.agent_writable)');
  END IF;

INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)
    VALUES (p_scope_type, p_scope_id, p_param_key, v_final, p_by)
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_at = now(),
         -- 0478 (G213): the row names who set it last, not who created it
         updated_by = EXCLUDED.updated_by;
  RETURN jsonb_build_object('ok',true,'param',p_param_key,'requested',p_param_value,'applied',v_final,
                            'clamped', v_final <> p_param_value,'safe_range',jsonb_build_array(v_min,v_max),
                            'exclusive_range',jsonb_build_array(v_minx,v_maxx),
                            'scope_type',p_scope_type);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_apply_ops_action(p_sim_run_id uuid, p_depot_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb, p_by text DEFAULT 'ottoq_prime'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_val numeric; v_cur numeric; v_param text; v_res jsonb;
BEGIN
  IF p_action = 'raise_deploy_surge' THEN
    -- clear a deploy backlog faster (AM commute / post-wave). Clamp 0.10–1.00, ≤+40%/move.
    v_param := 'deploy_surge_catchup';
    v_cur := ottoq_policy_get(p_sim_run_id, v_param, 0.35);
    v_val := LEAST(1.00, GREATEST(0.10, LEAST(v_cur * 1.40, COALESCE((p_args->>'value')::numeric, v_cur * 1.30))));

  ELSIF p_action = 'extend_forecast_horizon' THEN
    -- look further ahead to pre-position BESS/staging for an inbound wave. Clamp 10–90 min.
    v_param := 'forecast_horizon_min';
    v_cur := ottoq_policy_get(p_sim_run_id, v_param, 30);
    v_val := LEAST(90, GREATEST(10, COALESCE((p_args->>'value')::numeric, v_cur + 15)));

  ELSIF p_action = 'enable_energy_reserve' THEN
    -- switch energy shaving to the causal water-fill reserve target (BESS + timing only).
    v_param := 'energy_reserve_shave';
    v_cur := ottoq_policy_get(p_sim_run_id, v_param, 0);
    v_val := 1;

  ELSE
    -- 0491 (G222): OUT OF WHITELIST IS REFUSED, AND SAYS SO. This used to queue a nemotron_ops_action approval,
    -- which the approvals table's check constraint rejects and which nothing would ever execute.
    RETURN jsonb_build_object('status','refused','action',p_action,'reason','not in the auto-exec whitelist',
                              'whitelist', jsonb_build_array('raise_deploy_surge','extend_forecast_horizon',
                                                             'enable_energy_reserve'));
  END IF;

  -- 0432: A MOVE TO THE VALUE ALREADY IN FORCE IS NOT A MOVE. enable_energy_reserve with the reserve on, or
  -- raise_deploy_surge at the ceiling, used to rewrite the same value and report it applied -- and count it
  -- against the agent's three moves (db/checks/0352 section 3: 92 of 106 writes to one dial were resends).
  IF v_cur IS NOT DISTINCT FROM v_val THEN
    RETURN jsonb_build_object('status','no_change','action',p_action,'param',v_param,'value',v_cur);
  END IF;

  -- 0432: THE SETTER'S ANSWER IS THE ANSWER. This used to PERFORM ottoq_policy_set and return 'applied'
  -- whatever it said -- G65's defect in the ops path (db/checks/0352 section 5b). A refusal is now a refusal.
  v_res := ottoq_policy_set('run', p_sim_run_id, v_param, v_val, p_by);
  IF NOT COALESCE((v_res->>'ok')::boolean, false) THEN
    RETURN jsonb_build_object('status','refused','action',p_action,'param',v_param,'from',v_cur,
                              'requested',v_val,'reason',COALESCE(v_res->>'error','setter returned no ok field'),
                              'setter',v_res);
  END IF;
  RETURN jsonb_build_object('status','applied','action',p_action,'param',v_param,'from',v_cur,
                            'to',COALESCE((v_res->>'applied')::numeric, v_val),'requested',v_val,
                            'clamped',COALESCE((v_res->>'clamped')::boolean, false));
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_hw_recall_vehicle(p_vehicle_id uuid, p_reason text DEFAULT NULL::text, p_actor text DEFAULT 'cockpit'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh    vehicles%ROWTYPE;
  v_run    uuid;
  v_cmd    uuid;
  v_open   int;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_not_found');
  END IF;
  IF NOT v_veh.is_active THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_inactive');
  END IF;

  -- Already home, or already on the way. Recalling again would queue a command
  -- the vehicle can only ignore, and leave it sitting 'issued' forever.
  IF v_veh.current_state IN ('en_route_to_depot','charging_l2','charging_dcfc',
                             'charge_complete_holding','arrived_at_gate') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_returning_or_home',
                              'state', v_veh.current_state::text);
  END IF;

  -- Do not stack recalls. One unexecuted begin_charge is enough.
  SELECT count(*) INTO v_open FROM ottoq_vehicle_commands
   WHERE vehicle_id = p_vehicle_id AND command_type = 'begin_charge' AND status = 'issued';
  IF v_open > 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'recall_already_pending', 'pending', v_open);
  END IF;

  SELECT sim_run_id INTO v_run FROM ottoq_sim_runs
   WHERE depot_id = v_veh.home_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;

  INSERT INTO ottoq_vehicle_commands (
    vehicle_id, depot_id, sim_run_id, command_type, payload,
    issued_at, issued_by, status
  ) VALUES (
    p_vehicle_id, v_veh.home_depot_id, v_run, 'begin_charge',
    jsonb_build_object('source', 'cockpit_recall', 'reason', p_reason, 'actor', p_actor),
    now(), 'cockpit_recall', 'issued'
  ) RETURNING command_id INTO v_cmd;

  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'operator', p_actor_id := p_actor,
      p_event_type := 'vehicle.recall_requested', p_entity_type := 'vehicle',
      p_entity_id := p_vehicle_id, p_depot_id := v_veh.home_depot_id,
      p_payload := jsonb_build_object('command_id', v_cmd, 'reason', p_reason,
                                      'soc_at_request', v_veh.current_soc),
      p_severity := 'info', p_ingest_source := 'production',
      p_data_source := 'production', p_sim_run_id := v_run);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('ok', true, 'command_id', v_cmd,
                            'vehicle', v_veh.display_name,
                            'live_run', v_run,
                            'note', CASE WHEN v_run IS NULL
                                    THEN 'queued, but no live run is armed for this depot'
                                    ELSE 'queued' END);
END;
$function$;

CREATE OR REPLACE FUNCTION ottoq.ottoq_stall_free_between(p_sim_run_id uuid, p_depot_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_stall_type text DEFAULT NULL::text, p_staging_role text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_zones text[] DEFAULT NULL::text[])
 RETURNS TABLE(stall_id uuid, stall_code text, stall_type text, staging_role text, zone text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH g AS MATERIALIZED (
    SELECT
      (public.ottoq_policy_get(p_sim_run_id, 'calendar_occupancy_guard', 0) >= 1) AS guard_on,
      GREATEST(public.ottoq_policy_get(p_sim_run_id, 'occupied_stall_horizon_min',     45), 1) AS horizon_min,
      GREATEST(public.ottoq_policy_get(p_sim_run_id, 'occupied_stall_horizon_max_min', 240), 1) AS horizon_max_min,
      COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                 WHERE r.sim_run_id = p_sim_run_id), p_from) AS now_sim
  )
  SELECT s.id, s.stall_code, s.stall_type::text, s.staging_role, s.zone
  FROM public.stalls s CROSS JOIN g
  WHERE s.depot_id = p_depot_id
    AND s.status NOT IN ('maintenance','closed')
    AND (p_stall_type   IS NULL OR s.stall_type::text = p_stall_type)
    AND (p_staging_role IS NULL OR s.staging_role     = p_staging_role)
    AND (p_zones        IS NULL OR s.zone             = ANY (p_zones))
    -- ══════════════════ 0372 (G88): CHARGER HEALTH IS THE THIRD GATE ══════════════════
    -- A charge stall whose OCPP charger reports 'Faulted' cannot charge, so offering it
    -- is never correct -- and this function is the SHARED candidate source for every
    -- proposer and for ottoq.ottoq_react_to_refusals' reroute walk. Before this it
    -- checked the stall's own `status` and the calendar and not the charger, so a
    -- faulted-charger stall read as available: CP-SAT declined a frame where our own
    -- pointer census said 4 charge stalls were free, and all four were the faulted ones
    -- (db/checks/0264 §2). The only two routines that DID check are
    -- ottoq_l2_optimize_assignments and ottoq_replan_after_charger_fault, and the
    -- second is reachable only from a human-reported fault.
    -- Scoped to charge types on purpose: a staging stall has no charger to fault, and a
    -- wash or service bay is gated by its own status. Heartbeat freshness is NOT checked
    -- here even though HW.002 requires it, because that needs a staleness threshold this
    -- function has no business choosing; every charger on the twin depot currently
    -- reports a heartbeat, so the omission changes nothing today and is named rather
    -- than hidden.
    AND NOT (
          s.stall_type::text IN ('dcfc','l2')
      AND EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers ch
                   WHERE ch.charger_id   = s.ocpp_charger_id
                     AND ch.station_state = 'Faulted')
    )
    -- ══════════════════ CALENDAR READ — MUST MATCH THE CONSTRAINT ══════════════════
    -- 2026-08-03 (P1): state set aligned to ottoq_stall_bookings_no_overlap_v3:
    -- held / active / done / interrupted. Any divergence between what the picker
    -- treats as busy and what the database refuses to double-book turns straight back
    -- into silent oversubscription (the 2026-08-02 finding: picker read held/active,
    -- which had been emptied every tick, so 22 vehicles were booked into ONE bay).
    -- 'done' and 'interrupted' are REAL past occupancy. Both are safe to include only
    -- because every close path TRUNCATES `during` to the true end of occupancy --
    -- verified 2026-08-03: 40 of 40 interrupted rows have upper(during) <= released_at,
    -- phantom tail 0.00 min -- so neither can block a window the vehicle did not use.
    -- 'released' / 'superseded' mean the occupancy never happened and remain invisible.
    AND NOT EXISTS (
      SELECT 1 FROM public.ottoq_stall_bookings b
      WHERE b.stall_id   = s.id
        AND b.sim_run_id = p_sim_run_id
        AND b.state IN ('held','active','done','interrupted')
        AND b.during && tstzrange(p_from, p_to, '[)')
    )
    -- ============================ OCCUPANCY GUARD ============================
    AND (
      NOT g.guard_on
      OR s.current_vehicle_id IS NULL
      OR NOT (
           tstzrange(
             g.now_sim,
             GREATEST(
               g.now_sim + interval '1 second',
               LEAST(
                 COALESCE(
                   (SELECT min(l.planned_end_sim)
                      FROM public.ottoq_itinerary_legs l
                     WHERE l.sim_run_id       = p_sim_run_id
                       AND l.vehicle_id       = s.current_vehicle_id
                       AND l.to_stall_id      = s.id
                       AND l.status IN ('planned','active','in_progress')
                       AND l.planned_end_sim  > g.now_sim),
                   g.now_sim + make_interval(mins => g.horizon_min::int)),
                 g.now_sim + make_interval(mins => g.horizon_max_min::int))
             ), '[)')
           && tstzrange(p_from, p_to, '[)')
         )
    )
  ORDER BY s.distance_from_entrance NULLS LAST, s.stall_code
  LIMIT GREATEST(p_limit, 1)
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_twin_run_context(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(
    (SELECT jsonb_build_object(
       'sim_run_id',  r.sim_run_id,
       'depot_id',    r.depot_id,
       'depot_name',  d.name,
       'scenario',    r.scenario_code,
       'status',      r.status,
       'seed',        r.random_seed::text,
       'stall_count', (SELECT count(*) FROM stalls s WHERE s.depot_id = r.depot_id),
       'fleet_count', (SELECT count(*) FROM vehicles v
                        WHERE v.category = 'autonomous' AND v.home_depot_id = r.depot_id),
       -- what the run was configured to use
       'policy_configured', r.policy,
       -- what actually made the decisions. NULL when no decision was logged —
       -- an unrun policy is not a policy in force.
       'policy_observed', (
         SELECT dl.policy FROM ottoq_deploy_log dl
          WHERE dl.sim_run_id = r.sim_run_id AND dl.policy IS NOT NULL
          GROUP BY dl.policy ORDER BY count(*) DESC LIMIT 1),
       'policy_decisions', (
         SELECT count(*) FROM ottoq_deploy_log dl WHERE dl.sim_run_id = r.sim_run_id),
       -- distinct policies seen; more than one means the run switched mid-flight
       'policy_variants', (
         SELECT jsonb_object_agg(policy, n) FROM (
           SELECT policy, count(*) n FROM ottoq_deploy_log
            WHERE sim_run_id = r.sim_run_id AND policy IS NOT NULL
            GROUP BY policy) s),
       'policy_matches_config', (
         SELECT CASE
           WHEN r.policy IS NULL THEN NULL
           WHEN count(*) FILTER (WHERE dl.policy IS NOT NULL) = 0 THEN NULL
           ELSE bool_and(dl.policy = r.policy) FILTER (WHERE dl.policy IS NOT NULL)
         END
         FROM ottoq_deploy_log dl WHERE dl.sim_run_id = r.sim_run_id))
       FROM ottoq_sim_runs r
       LEFT JOIN depots d ON d.id = r.depot_id
      WHERE r.sim_run_id = p_sim_run_id),
    jsonb_build_object('error', 'sim_run not found'));
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_vehicle_card(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'endpoint','ottoq.vehicle_card','contract_version','1.0',
    'vehicle', (SELECT st FROM jsonb_array_elements(
        public.ottoq_depot_cards((SELECT current_depot_id FROM vehicles WHERE id = p_vehicle_id))->'vehicles') st
      WHERE (st->>'vehicle_id')::uuid = p_vehicle_id LIMIT 1)
  );
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_check_run_scope_registry()
 RETURNS TABLE(table_schema text, table_name text, column_name text, problem text, severity text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- (a) a run-scoped column that nobody has classified
  --
  --     WIDENED 0408. This read IN ('public','proof_0015') and therefore could never see the
  --     `twin` or `ottoq` schemas. It returned clean while twin.arm_cycles (54,098 rows) and
  --     twin.arm_registrations (28,841) sat unclassified, which meant the purge never touched
  --     them and they accumulated ~1,400 runs of orphans -- 97% of their rows. db/checks/0316
  --     then read that accumulation as one run's activity. The gate whose entire job is to
  --     notice an unclassified run-scoped table could not look where two of them were.
  --
  --     Severity stays 'warn': the purge raises on 'block' only, so this can report an
  --     unclassified table on every run start without ever refusing one.
  SELECT c.table_schema::text, c.table_name::text, c.column_name::text,
         'unregistered run-scoped column'::text, 'warn'::text
    FROM information_schema.columns c
    JOIN pg_class rc ON rc.relname = c.table_name
    JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
   WHERE rc.relkind = 'r'
     AND c.table_schema IN ('public','ottoq','twin','proof_0015')
     AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_schema = c.table_schema
                        AND g.table_name   = c.table_name
                        AND g.column_name  = c.column_name)
  UNION ALL
  -- (b1) EXISTENCE. Unchanged, over EVERY engine/stamp row. to_regclass (not a
  --      ::regclass cast) is deliberate: the cast RAISES on a dropped table, and
  --      the purge calls this guard, so one dropped scratch table would have made
  --      every run start fail.
  SELECT g.table_schema, g.table_name, g.column_name,
         'registered engine/stamp table no longer exists',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NULL
  UNION ALL
  -- (b2) THE FK REQUIREMENT, narrowed by 0344 to rows whose column is an actual
  --      run-scoping key -- the same four names (a) watches.
  --
  --      WHY. The registry is per-COLUMN; this check was per-TABLE. So
  --      ottoq_proposer_fire_log.tick_seq, class 'stamp', demanded an FK to
  --      ottoq_sim_runs -- while the same table's sim_run_id is class 'evidence'
  --      and must OUTLIVE the run. 0267 satisfied the demand by adding the FK,
  --      and that FK then made ottoq_purge_prior_runs step (5) raise 23503,
  --      which made ottoq_start_demo_run raise, which broke the Twin's start
  --      door. The table was required to block the purge it was registered to
  --      survive.
  --
  --      tick_seq is an integer tick counter. It is not a key into
  --      ottoq_sim_runs and no FK on it could exist -- the registry's own note
  --      says "Provenance, not a scoping key; sim_run_id is." Orphaning is
  --      impossible through a column that does not reference the parent, so no
  --      protection is lost. This considers strictly FEWER rows than before, so
  --      it cannot invent a block; 0344 A5 asserts ottoq_external_proposals is
  --      still required to keep its FK by its own engine-class row.
  SELECT g.table_schema, g.table_name, g.column_name,
         'engine/stamp run-key column''s table has no FK to ottoq_sim_runs',
         'block'
    FROM public.ottoq_run_scope_registry g
   WHERE g.class IN ('engine','stamp')
     AND g.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
     AND to_regclass(g.table_schema||'.'||g.table_name) IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint k
        WHERE k.contype = 'f'
          AND k.conrelid = to_regclass(g.table_schema||'.'||g.table_name)
          AND k.confrelid = 'public.ottoq_sim_runs'::regclass)
  UNION ALL
  -- (c) any FK to the run table that has become CASCADE
  SELECT n.nspname::text, c.relname::text, 'sim_run_id'::text,
         'FK to ottoq_sim_runs is ON DELETE CASCADE — history can be silently erased',
         'block'
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE k.contype = 'f'
     AND k.confrelid = 'public.ottoq_sim_runs'::regclass
     AND k.confdeltype = 'c'
  UNION ALL
  -- (d) ADDED 0348. An engine-class table whose append-only DELETE guard never
  --     learned the purge's arming protocol. The registry says the rows must not
  --     outlive their run; the guard says they can never be deleted. Both cannot
  --     be true, and the loser is every simulation start.
  --
  --     ottoq_recall_refusals was exactly this: class 'engine', guard raising
  --     unconditionally, six rows, and ottoq_start_demo_run could not complete.
  --     Its FK then made ottoq_recall_decisions undeletable too -- one guard,
  --     two survivors.
  --
  --     TEXTUAL, on the COMMENT-STRIPPED body, and that is stated because it
  --     matters: prosrc carries comments, and this repo has twice been fooled by
  --     matching them (0346 A1a, 0220's LIMIT 1 count). Precision measured on the
  --     live catalog rather than assumed: flags 1 of 4, the right one.
  --
  --     engine + DELETE only. The stamp/UPDATE mirror is real but unlistable
  --     this way -- `vehicles` carries six UPDATE triggers that are loggers and
  --     workers, not guards, and none honours the flag because none needs to.
  --     Flagging those would put six false blocks on the purge's own
  --     precondition. Named, not silently included.
  SELECT DISTINCT
         g.table_schema, g.table_name, g.column_name,
         'engine table''s append-only DELETE guard ('||p.proname||
           ') does not honour set_config(''ottoq.retention'') — the purge cannot clear it',
         'block'
    FROM public.ottoq_run_scope_registry g
    JOIN pg_class c   ON c.oid = to_regclass(g.table_schema||'.'||g.table_name)
    JOIN pg_trigger t ON t.tgrelid = c.oid AND NOT t.tgisinternal AND (t.tgtype & 8) > 0
    JOIN pg_proc p    ON p.oid = t.tgfoid
   WHERE g.class = 'engine'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g') ILIKE '%RAISE EXCEPTION%'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^'||chr(10)||']*', '', 'g') NOT ILIKE '%ottoq.retention%';
$function$;

-- The live doors are SECURITY DEFINER and closed to anon (0405 left the recall door anon-denied on purpose).
REVOKE ALL ON FUNCTION public.ottoq_hw_recall_vehicle(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_apply_ops_action(uuid, uuid, text, jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION ottoq.ottoq_stall_free_between(uuid, uuid, timestamptz, timestamptz, text, text, integer, text[]) FROM PUBLIC, anon, authenticated;

-- ═════════════ SEED: one twin depot, one other depot, three operators, a live run ═════════════
-- The SIM clock is 2026-09-27 12:00 UTC; the real clock is whenever the test runs. The two are far apart on purpose,
-- so a calendar read against now() would give a different answer from one against the sim clock.
INSERT INTO public.depots (id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'OTTOYARD Nashville Flagship'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'Some other depot');
INSERT INTO public.fleet_operators (id, name) VALUES
  ('22222222-2222-2222-2222-222222222222', 'Waymo Nashville'),
  ('33333333-3333-3333-3333-333333333333', 'Tesla Robotaxi TN'),
  ('44444444-4444-4444-4444-444444444444', 'Zoox Southeast');
INSERT INTO public.staff_users (auth_user_id, depot_id, first_name, last_name, display_name, role) VALUES
  ('a0000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'Jessica', 'Lee',    NULL,          'yard_supervisor'),
  ('b0000000-0000-0000-0000-00000000000b', '11111111-1111-1111-1111-111111111111', 'Mike',    'Torres', 'Mike T.',     'ops_manager'),
  ('c0000000-0000-0000-0000-00000000000c', '11111111-1111-1111-1111-111111111111', 'Carlos',  'Rivera', NULL,          'charging_tech'),
  ('d0000000-0000-0000-0000-00000000000d', 'aaaaaaaa-0000-0000-0000-000000000002', 'Dana',    'Other',  NULL,          'ops_manager');
INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_current, tick_count, run_by) VALUES
  ('5e5e5e5e-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'running', now() - interval '1 hour',
   '2026-09-27 12:00:00+00', 300, 'operator_demo');
INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, make, model, display_name, current_soc, current_state, is_active) VALUES
  ('ee000000-0000-0000-0000-0000000000a1', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Jaguar', 'I-PACE', 'Waymo-AV-001', 41, 'deployed', true),
  ('ee000000-0000-0000-0000-0000000000a2', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Jaguar', 'I-PACE', 'Waymo-AV-002', 77, 'charging_dcfc', true),
  ('ee000000-0000-0000-0000-0000000000b1', '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Tesla', 'Model Y', 'Tesla-AV-001', 35, 'deployed', true),
  ('ee000000-0000-0000-0000-0000000000c1', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Zoox', 'Robotaxi', 'Zoox-AV-001', 64, 'staged_awaiting_service', true),
  ('ee000000-0000-0000-0000-0000000000a9', '22222222-2222-2222-2222-222222222222', 'aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000002', 'Jaguar', 'I-PACE', 'Waymo-AV-900', 50, 'deployed', true);
INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, station_state) VALUES
  ('c4000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Available'),
  ('c4000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Faulted'),
  ('c4000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Occupied'),
  ('c4000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Available'),
  ('c4000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Available');
INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, status, current_vehicle_id, reserved_by, ocpp_charger_id, zone, distance_from_entrance) VALUES
  -- free by every gate
  ('57000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'DCFC-01', 'dcfc', 'available', NULL, NULL, 'c4000000-0000-0000-0000-000000000001', 'north', 10),
  -- pointer clear, charger FAULTED: not offerable
  ('57000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'DCFC-02', 'dcfc', 'available', NULL, NULL, 'c4000000-0000-0000-0000-000000000002', 'north', 11),
  -- occupied
  ('57000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'DCFC-03', 'dcfc', 'occupied', 'ee000000-0000-0000-0000-0000000000a2', NULL, 'c4000000-0000-0000-0000-000000000003', 'north', 12),
  -- pointer clear, calendar booked in the SIM window: not offerable
  ('57000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'L2-01', 'l2', 'available', NULL, NULL, 'c4000000-0000-0000-0000-000000000004', 'east', 20),
  -- pointer clear, booked only in the REAL-clock window: offerable (the calendar is read in sim time)
  ('57000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'L2-02', 'l2', 'available', NULL, NULL, 'c4000000-0000-0000-0000-000000000005', 'east', 21),
  -- pointer says available but reserved_by is set: not offerable (the gate ottoq_stall_free_between does not read)
  ('57000000-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'STG-01', 'staging', 'available', NULL, 'ee000000-0000-0000-0000-0000000000c1', NULL, 'south', 30),
  ('57000000-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 'STG-02', 'staging', 'available', NULL, NULL, NULL, 'south', 31),
  ('57000000-0000-0000-0000-000000000008', '11111111-1111-1111-1111-111111111111', 'WASH-01', 'wash_bay', 'occupied', 'ee000000-0000-0000-0000-0000000000c1', NULL, NULL, 'west', 40);
UPDATE public.vehicles SET current_stall_id = '57000000-0000-0000-0000-000000000003' WHERE id = 'ee000000-0000-0000-0000-0000000000a2';
INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, state, during) VALUES
  ('5e5e5e5e-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000004', 'ee000000-0000-0000-0000-0000000000b1', 'held',
   tstzrange('2026-09-27 11:50:00+00', '2026-09-27 12:20:00+00', '[)')),
  ('5e5e5e5e-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000005', 'ee000000-0000-0000-0000-0000000000b1', 'held',
   tstzrange(now() - interval '10 minutes', now() + interval '10 minutes', '[)'));
INSERT INTO public.ottoq_policy_param_catalog (param_key, default_value, min_value, max_value, agent_writable, agent_min_value, agent_max_value) VALUES
  ('deploy_surge_catchup', 0.35, 0.10, 1.00, false, 0.1, 1.0),
  ('forecast_horizon_min', 30, 10, 90, false, 10, 90),
  ('energy_reserve_shave', 0, 0, 1, true, 0, 1);
INSERT INTO public.stub_cards (vehicle_id, card, last_decision) VALUES
  ('ee000000-0000-0000-0000-0000000000a1', '{"urgency":"normal","dispatch_due_at":"2026-09-27T13:00:00+00:00","needs":[{"svc":"charge","status":"pending"}],"steps":[],"current_step":null,"next_step":{"leg_type":"transit","atom":null,"planned_start":"2026-09-27T12:30:00+00:00"}}',
   '{"at":"2026-09-27T11:58:00+00:00","action":"deploy","verb":"deploy","outcome":"enacted","engine":"otto_q","rationale":{"why":"on mission"}}'),
  ('ee000000-0000-0000-0000-0000000000a2', '{"urgency":"high","dispatch_due_at":"2026-09-27T12:40:00+00:00","needs":[{"svc":"charge","status":"in_progress"},{"svc":"exterior_wash","status":"done"}],"steps":[],"current_step":{"leg_type":"charge_dcfc","atom":"charge","expected_end":"2026-09-27T12:25:00+00:00","progress_pct":61},"next_step":null}',
   '{"at":"2026-09-27T11:40:00+00:00","action":"stall_assignment","verb":"assign_stall","outcome":"enacted","engine":"otto_q","rationale":{"why":"lowest SoC, DCFC free"}}'),
  ('ee000000-0000-0000-0000-0000000000b1', '{"urgency":"normal","needs":[],"steps":[],"current_step":null,"next_step":null}', NULL),
  ('ee000000-0000-0000-0000-0000000000c1', '{"urgency":"low","needs":[{"svc":"exterior_wash","status":"in_progress"}],"steps":[],"current_step":null,"next_step":null}', NULL);
INSERT INTO public.stub_activity (sim_run_id, occurred_at, vehicle_id, display_name, action, engine, target, outcome, rationale, reason, decision_seq, tick_seq, held_ticks, last_at, standing) VALUES
  ('5e5e5e5e-0000-0000-0000-000000000001', '2026-09-27 11:40:00+00', 'ee000000-0000-0000-0000-0000000000a2', 'Waymo-AV-002', 'stall_assignment', 'otto_q', 'DCFC-03', 'enacted', '{"why":"lowest SoC"}', NULL, 101, 280, 1, NULL, false),
  ('5e5e5e5e-0000-0000-0000-000000000001', '2026-09-27 11:45:00+00', 'ee000000-0000-0000-0000-0000000000b1', 'Tesla-AV-001', 'deploy', 'otto_q', NULL, 'enacted', NULL, NULL, 102, 285, 1, NULL, false),
  ('5e5e5e5e-0000-0000-0000-000000000001', '2026-09-27 11:50:00+00', 'ee000000-0000-0000-0000-0000000000c1', 'Zoox-AV-001', 'task_start', 'otto_q', 'WASH-01', 'enacted', NULL, NULL, 103, 290, 1, NULL, false),
  ('5e5e5e5e-0000-0000-0000-000000000001', '2026-09-27 11:58:00+00', 'ee000000-0000-0000-0000-0000000000a1', 'Waymo-AV-001', 'deploy', 'otto_q', NULL, 'enacted', NULL, NULL, 104, 298, 1, NULL, false);
