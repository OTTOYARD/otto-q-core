-- tests/fixtures/agent_production_arm_stub.sql -- the five bodies 0629 patches, as the live database held them on 2026-10-09
-- (pg_get_functiondef's output, byte for byte, so 0629's md5 premises pass against them), the setter's helpers as live
-- (ottoq_is_agent_actor, ottoq_dial_clamp, ottoq_policy_get, ottoq_apply_ops_action), stand-ins for what they call that
-- 0629 does not touch, and the minimal tables they read. Loaded by tests/test_agent_production_arm_sql.py.
SET check_function_bodies = off;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

CREATE TABLE public.depots (id uuid PRIMARY KEY, feed_mode text);
CREATE TABLE public.ottoq_scenarios (scenario_id uuid PRIMARY KEY, scenario_code text UNIQUE);
CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, scenario_id uuid, scenario_code text, started_at timestamptz, ended_at timestamptz,
  next_tick_due_at timestamptz, sim_clock_start timestamptz, sim_clock_current timestamptz, sim_clock_end timestamptz,
  time_scale numeric, tick_interval_seconds integer, tick_count integer DEFAULT 0, depot_id uuid, random_seed bigint,
  status text, run_by text, policy text, demo_speed_x numeric, payload jsonb);
CREATE TABLE public.ottoq_policy_param_catalog (
  param_key text PRIMARY KEY, description text, default_value numeric, min_value numeric, max_value numeric,
  affects text, min_exclusive numeric, max_exclusive numeric, agent_writable boolean, agent_min_value numeric,
  agent_max_value numeric, agent_max_drift_pct numeric);
CREATE TABLE public.ottoq_policy_params (
  scope_type text NOT NULL, scope_id uuid NOT NULL, param_key text NOT NULL, param_value numeric NOT NULL,
  updated_by text, updated_at timestamptz DEFAULT now(), PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_schema_snapshots (
  snapshot_id bigserial PRIMARY KEY, taken_at timestamptz DEFAULT now(), label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text);
CREATE TABLE public.ottoq_cert_lineage (
  name text PRIMARY KEY, forces_recert boolean, note text, classified_at timestamptz, forces_dial_restart boolean);
CREATE TABLE public.ottoq_proposer_precedence (source text PRIMARY KEY, rank integer, holds_tick boolean);
CREATE TABLE public.ottoq_proposer_fire_log (sim_run_id uuid, declared_source text);
CREATE TABLE public.ottoq_decisions (sim_run_id uuid, resolved_action_context text, enacted_action jsonb, tick_seq bigint);
CREATE TABLE public.event_stub (id bigserial PRIMARY KEY, event_type text, payload jsonb, sim_run_id uuid, data_source text);

-- stand-ins for what the bodies call and 0629 does not touch
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_scheduled boolean DEFAULT true) RETURNS integer
  LANGUAGE sql AS $stub$ SELECT 0 $stub$;
CREATE FUNCTION public.ottoq_shield_probe(p_action_context text, p_entity_type text, p_entity_id uuid, p_context jsonb)
  RETURNS TABLE(would_block integer) LANGUAGE sql AS $stub$ SELECT 0 $stub$;
CREATE FUNCTION public.ottoq_record_event(p_actor_type text, p_actor_id text, p_event_type text, p_entity_type text,
                                          p_payload jsonb, p_severity text, p_ingest_source text, p_data_source text,
                                          p_sim_run_id uuid) RETURNS uuid
  LANGUAGE plpgsql AS $stub$
BEGIN
  INSERT INTO public.event_stub(event_type, payload, sim_run_id, data_source)
  VALUES (p_event_type, p_payload, p_sim_run_id, p_data_source);
  RETURN gen_random_uuid();
END $stub$;

-- ── live: ottoq_is_agent_actor (c28f0d8a) ──
CREATE OR REPLACE FUNCTION public.ottoq_is_agent_actor(p_by text, p_actors text[] DEFAULT NULL::text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM unnest(COALESCE(p_actors, ARRAY['ottoq_prime'])) AS a(actor)
     WHERE COALESCE(p_by,'') = a.actor OR COALESCE(p_by,'') LIKE a.actor || ':%'
  );
$function$
;

-- ── live: ottoq_dial_clamp (f44f34e2) ──
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
$function$
;

-- ── live: ottoq_policy_get (72b658f3) ──
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
$function$
;

-- ── live: ottoq_policy_set (70238f33) ──
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
$function$
;

-- ── live: ottoq_apply_ops_action (a3caae97) ──
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
$function$
;

-- ── live: ottoq_agentic_arm (9509e976): 0615's body ──
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arm(p_sim_run_id uuid, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run_by text; v_found boolean; v_k record; v_r jsonb;
  v_receipts jsonb := '[]'::jsonb;
BEGIN
  IF p_sim_run_id IS NULL OR NULLIF(p_by,'') IS NULL THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: sim_run_id and by are both required'
      USING ERRCODE = '22023';
  END IF;

  SELECT r.run_by, true INTO v_run_by, v_found
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_found, false) THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: run % does not exist', p_sim_run_id
      USING ERRCODE = '22023';
  END IF;

  --: THE CANON GUARD. 0265: with the key absent the frame is byte-identical to
  --: its pre-0265 output, "which is what every certification arm sees." Arming
  --: a certification arm would change the frame under the canon. Refused here
  --: rather than left to the operator, which is the whole point of the file.
  IF v_run_by = 'cert_harness' THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: run % is a certification arm (run_by=cert_harness). '
                    'Arming it would change the frame the canon was measured against. '
                    'A proposer reaches a certification by record-and-replay (0237/0239), '
                    'never by being armed into one.', p_sim_run_id
      USING ERRCODE = '42501';
  END IF;

  FOR v_k IN
    SELECT * FROM (VALUES
      ('agent_solver_chain_enabled',     1::numeric),
      ('cuopt_propose_enabled',          1::numeric),
      ('orchestrator_agent_enabled',     1::numeric),
      ('proposer_frame_facts',           1::numeric),
      ('proposer_hold_enabled',          1::numeric),
      ('cuopt_first_refusal_max_defers', 6::numeric),
      ('prearrival_charge_yields_to_solver', 1::numeric),
      ('agent_review_enabled', 1::numeric),
      ('agent_board_grounding_enabled', 1::numeric),   --: 0432
      ('agent_asset_depth_enabled', 1::numeric)        --: 0432: 0350's block, never armed before
    ) AS t(param_key, value) ORDER BY 1
  LOOP
    --: ALWAYS run scope. ottoq_policy_set clamps to the catalog range and
    --: answers {"ok":false,"error":"unknown_param"} for a key it does not know
    --: WITHOUT raising (0262) -- so the receipt is read, not assumed. That
    --: unread receipt is the exact mechanism by which proposer_seat has 12 rows
    --: nobody could have written through the setter.
    v_r := public.ottoq_policy_set('run', p_sim_run_id, v_k.param_key, v_k.value, p_by);
    IF NOT COALESCE((v_r->>'ok')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: ottoq_policy_set refused % -> %', v_k.param_key, v_r
        USING ERRCODE = '22023';
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: % was clamped from % to % by the catalog range %; '
                      'an arm that silently lands on a different value is the defect this '
                      'function exists to end',
                      v_k.param_key, v_r->>'requested', v_r->>'applied', v_r->>'safe_range'
        USING ERRCODE = '22023';
    END IF;
    v_receipts := v_receipts || jsonb_build_array(v_r);
  END LOOP;

  --: 0615. THE AGENT'S CHARGE ORDER (0614), on an operator's run only: the runs the agent serves in real time.
  --: An ab_harness arm runs in one transaction, so the agent never reaches it, and its dial set stays the one before
  --: 0615. A cert_harness run never gets here: it is refused above.
  IF v_run_by = 'operator_demo' THEN
    v_r := public.ottoq_policy_set('run', p_sim_run_id, 'agent_charge_order', 1::numeric, p_by);
    IF NOT COALESCE((v_r->>'ok')::boolean, false) OR COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: agent_charge_order was not armed as asked -> %', v_r
        USING ERRCODE = '22023';
    END IF;
    v_receipts := v_receipts || jsonb_build_array(v_r);
  END IF;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,
                            'receipts', v_receipts,
                            'arming', public.ottoq_agentic_arming(p_sim_run_id));
END $function$
;

-- ── live: ottoq_agentic_arming (fe54eb23) ──
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arming(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_run_by text; v_found boolean;
  v_keys   jsonb := '[]'::jsonb;
  v_k      record;
  v_have   numeric; v_ok int := 0; v_tot int := 0;
  v_missing text[] := ARRAY[]::text[];
  -- 0349: the evidence half.
  v_primary   text;
  v_fires     int := 0;
  v_chains    int := 0;
  v_fellback  int := 0;
  v_failed    int := 0;
  v_reason    text;
  v_reachable boolean;          -- three-valued on purpose; NULL = not enough evidence
  v_min_chains constant int := 3;
  v_verdict   text;
BEGIN
  SELECT r.run_by, true INTO v_run_by, v_found
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_found, false) THEN
    RETURN jsonb_build_object('verdict','unknown_run','sim_run_id',p_sim_run_id);
  END IF;

  FOR v_k IN
    SELECT * FROM (VALUES
      ('agent_solver_chain_enabled',     1::numeric,
       '0331: one chain owns analysis -> solve -> deterministic disposal'),
      ('cuopt_propose_enabled',          1::numeric,
       '0056/0113: the solver seat and first-refusal machinery are live'),
      ('orchestrator_agent_enabled',     1::numeric,
       '0112/0113: Nemotron is allowed to analyze and hand off'),
      ('proposer_frame_facts',           1::numeric,
       '0265: the frame carries the facts the door pre-filters on'),
      ('proposer_hold_enabled',          1::numeric,
       '0259/0262: one-tick right of first refusal for a non-cuOpt proposer'),
      ('cuopt_first_refusal_max_defers', 1::numeric,
       '0152 set the global tier to 0; without a run row nothing is ever armed'),
      ('prearrival_charge_yields_to_solver', 1::numeric,
       '0339: the charge stall is not reserved before the primary proposer can see it')
    ) AS t(param_key, required, why)
    ORDER BY 1
  LOOP
    v_tot := v_tot + 1;
    --: The DEFAULT passed here is deliberately 0, not the caller default the
    --: engine's own readers use. This function asks "what is SET", and a key
    --: that resolves only through a caller's fallback is not set.
    v_have := COALESCE(public.ottoq_policy_get(p_sim_run_id, v_k.param_key, 0), 0);
    IF v_have >= v_k.required THEN
      v_ok := v_ok + 1;
    ELSE
      v_missing := v_missing || v_k.param_key;
    END IF;
    v_keys := v_keys || jsonb_build_array(jsonb_build_object(
      'param_key', v_k.param_key, 'required', v_k.required,
      'in_force', v_have, 'satisfied', v_have >= v_k.required, 'why', v_k.why));
  END LOOP;

  -- ── 0349: SEVEN SET DIALS ARE NOT A RUNNING PROPOSER ────────────────────
  -- Every dial above is a statement of INTENT read out of ottoq_policy_params.
  -- None of them observes whether the proposer they arm actually ran. Run
  -- dde654cc read "armed, 7 of 7" while ottoq_proposer_fire_log held zero rows
  -- for it and all 36 agent chains recorded
  -- fallback_reason "CP-SAT service is not configured". The dials cannot see
  -- that, because the thing that failed is an edge-function secret.
  SELECT source INTO v_primary FROM public.ottoq_proposer_precedence
   ORDER BY rank, source LIMIT 1;

  SELECT count(*) INTO v_fires
    FROM public.ottoq_proposer_fire_log f
   WHERE f.sim_run_id = p_sim_run_id
     AND (v_primary IS NULL OR f.declared_source = v_primary);

  SELECT count(*),
         count(*) FILTER (WHERE d.enacted_action->'solver_handoff'->>'status' = 'fallback'),
         count(*) FILTER (WHERE d.enacted_action->'solver_handoff'->>'status' = 'failed')
    INTO v_chains, v_fellback, v_failed
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id
     AND d.resolved_action_context = 'orchestrator_agent';

  -- The reason is the diagnosis; reachable is only the verdict. Carried verbatim
  -- so a real solver crash is never mistaken for a missing configuration.
  SELECT COALESCE(d.enacted_action->'solver_handoff'->>'fallback_reason',
                  d.enacted_action->'solver_handoff'->>'error')
    INTO v_reason
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id
     AND d.resolved_action_context = 'orchestrator_agent'
     AND COALESCE(d.enacted_action->'solver_handoff'->>'fallback_reason',
                  d.enacted_action->'solver_handoff'->>'error') IS NOT NULL
   ORDER BY d.tick_seq DESC
   LIMIT 1;

  -- Three-valued. NULL protects a run that has simply not had an agent pass yet:
  -- 0 fires / 0 chains is indistinguishable from unreachable if you count only
  -- fires, so `false` requires at least v_min_chains chains that ALL fell back.
  v_reachable := CASE
    WHEN v_fires > 0                                        THEN true
    WHEN v_chains >= v_min_chains
     AND (v_fellback + v_failed) >= v_chains                THEN false
    ELSE NULL
  END;

  v_verdict := CASE
    WHEN v_run_by = 'cert_harness'                THEN 'cert_excluded'
    WHEN v_ok = v_tot AND v_reachable IS FALSE    THEN 'armed_primary_unreachable'
    WHEN v_ok = v_tot                             THEN 'armed'
    WHEN v_ok = 0                                 THEN 'unarmed'
    ELSE 'partial' END;

  RETURN jsonb_build_object(
    'sim_run_id', p_sim_run_id,
    'run_by', v_run_by,
    'verdict', v_verdict,
    'satisfied', v_ok, 'required', v_tot,
    'missing', to_jsonb(v_missing), 'keys', v_keys,
    'primary_proposer', jsonb_build_object(
      'declared',    v_primary,
      'reachable',   v_reachable,
      'fires',       v_fires,
      'agent_chains', v_chains,
      'fell_back',   v_fellback,
      'failed',      v_failed,
      'last_reason', v_reason,
      'min_chains_to_judge', v_min_chains,
      'judged_on', 'ottoq_proposer_fire_log rows for this run from the rank-0 '
                || 'source in ottoq_proposer_precedence, against '
                || 'ottoq_decisions.enacted_action->solver_handoff->>status '
                || 'over this run''s orchestrator_agent chains'));
END $function$
;

-- ── live: ottoq_production_start (c0554484) ──
CREATE OR REPLACE FUNCTION public.ottoq_production_start(p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run uuid; v_scenario ottoq_scenarios%ROWTYPE; v_existing uuid; v_feed text; v_ps jsonb;
BEGIN
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing);
  END IF;

  SELECT * INTO v_scenario FROM ottoq_scenarios WHERE scenario_code = 'production';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'production_scenario_missing');
  END IF;

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, started_at, next_tick_due_at,
    sim_clock_start, sim_clock_current, sim_clock_end,
    time_scale, tick_interval_seconds, depot_id, random_seed,
    status, run_by, policy, demo_speed_x
  ) VALUES (
    gen_random_uuid(), v_scenario.scenario_id, 'production', now(), now(),
    now(), now(), now() + interval '100 years',
    1.0, 120, p_depot, 42,
    'running', 'production_live', 'otto_q', 1.0
  ) RETURNING sim_run_id INTO v_run;

  PERFORM set_config('ottoq.sim_run_id', v_run::text, true);

  v_ps := ottoq_policy_set('run', v_run, 'orchestrator_agent_enabled', 0, 'production_start');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'production_start: orchestrator_agent_enabled write refused: %', v_ps;
  END IF;
  v_ps := ottoq_policy_set('run', v_run, 'cuopt_propose_enabled', 0, 'production_start');
  IF NOT COALESCE((v_ps->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'production_start: cuopt_propose_enabled write refused: %', v_ps;
  END IF;

  SELECT COALESCE(d.feed_mode, 'sim') INTO v_feed FROM depots d WHERE d.id = p_depot;

  PERFORM ottoq_record_event(
    p_actor_type := 'ottoq_engine', p_actor_id := 'production_start',
    p_event_type := 'production.session_started', p_entity_type := 'sim_run',
    p_payload := jsonb_build_object('depot_id', p_depot, 'feed_mode', v_feed,
                                    'tick', 'ottoq-depot-tick */2min -> twin.ottoq_world_advance (wall-elapsed) -> decide_and_dispatch'),
    p_severity := 'info', p_ingest_source := 'engine', p_data_source := 'production',
    p_sim_run_id := v_run);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'depot_id', p_depot,
    'feed_mode', v_feed, 'run_by', 'production_live', 'policy', 'otto_q',
    'driver', 'ottoq-depot-tick cron (*/2 min) -> twin.ottoq_world_advance -> ottoq_sim_decide_and_dispatch',
    'agents', 'quiesced and VERIFIED (orchestrator_agent_enabled=0, cuopt_propose_enabled=0)');
END
$function$
;

-- ── live: ottoq_agent_board (144242b7). Never executed here: it reads the whole depot. Its source is what 0629 patches. ──
CREATE OR REPLACE FUNCTION public.ottoq_agent_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run RECORD; v_depot uuid; v_clock timestamptz; v_board jsonb;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count, scenario_code, random_seed
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.depot_id IS NULL THEN RETURN NULL; END IF;
  v_depot := v_run.depot_id; v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(
    'sim_clock', v_clock, 'tick', v_run.tick_count, 'scenario', v_run.scenario_code,
    'fleet', (SELECT jsonb_object_agg(current_state, n) FROM (
        SELECT current_state, count(*) n FROM vehicles
        WHERE home_depot_id = v_depot AND category='autonomous' GROUP BY 1) f),
    'inbound_60m', (SELECT count(*) FROM vehicles v JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
        WHERE v.home_depot_id = v_depot AND v.current_state='en_route_to_depot'
          AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval '60 minutes'),
    'needs', jsonb_build_object(
      'open_visits_by_urgency', (SELECT jsonb_object_agg(urgency, n) FROM (
          SELECT urgency, count(*) n FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status IN ('open','in_progress') GROUP BY 1) u),
      'pending_atoms', (SELECT jsonb_object_agg(svc, n) FROM (
          SELECT a->>'svc' svc, count(*) n FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
            AND COALESCE(a->>'status','pending') = 'pending' GROUP BY 1 ORDER BY n DESC LIMIT 8) p),
      'carryovers', (SELECT count(*) FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status='carried_over' AND created_at > now() - interval '1 day')),
    'flow', jsonb_build_object(
      'legs', (SELECT jsonb_object_agg(status, n) FROM (
          SELECT status, count(*) n FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id GROUP BY 1) l),
      'avg_abs_deviation_min', (SELECT round(avg(abs(deviation_s))/60.0,1) FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id AND deviation_s IS NOT NULL),
      'amendments_recent', (SELECT count(*) FROM ottoq_decisions
          WHERE sim_run_id = p_sim_run_id AND resolved_action_context='itinerary_amended'
            AND sim_clock > v_clock - interval '2 hours')),
    'energy', jsonb_build_object(
      'site', (SELECT jsonb_build_object('grid_kw', round(COALESCE(building_load_kw,0)+COALESCE(total_ev_charging_kw,0)-COALESCE(solar_generation_kw,0)),
                       'ev_kw', round(COALESCE(total_ev_charging_kw,0)), 'solar_kw', round(COALESCE(solar_generation_kw,0)))
          FROM site_energy_snapshots WHERE depot_id = v_depot AND sim_run_id = p_sim_run_id
          ORDER BY timestamp DESC LIMIT 1),
      'bess', (SELECT jsonb_build_object('soc', current_soc_pct, 'power_kw', current_power_kw)
          FROM ottoq_bess_units WHERE depot_id = v_depot LIMIT 1),
      'bess_plan', (SELECT reason FROM ottoq_energy_commands
          WHERE COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
            AND depot_id = v_depot AND command_type='bess_setpoint_kw'
          ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, command_id DESC LIMIT 1),
      'forecast_charge_kw_60m', (SELECT round(COALESCE(predicted_charge_kw,0))
          FROM ottoq_predict_arrivals(v_depot, v_clock, p_sim_run_id, 60))),
    'approvals_pending', (SELECT jsonb_object_agg(approval_type, n) FROM (
        SELECT approval_type, count(*) n FROM ottoq_ops_approvals
        WHERE depot_id = v_depot AND status='pending' GROUP BY 1) a),
    'exceptions', (SELECT count(*) FROM vehicles
        WHERE home_depot_id = v_depot AND current_state IN ('tow_requested','emergency_staged')),
    'assignment_last_tick', (SELECT jsonb_object_agg(outcome_status, n) FROM (
        SELECT outcome_status, count(*) n FROM ottoq_decisions
        WHERE sim_run_id = p_sim_run_id AND tick_seq = v_run.tick_count
          AND action_context='stall_assignment' GROUP BY 1) o),
    'policy', jsonb_build_object(
      'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',  --: 0432: the dispatcher's own default
        COALESCE((SELECT (s.fleet_overrides->>'target_deployed_fraction')::numeric FROM ottoq_sim_scenarios s
                   WHERE s.scenario_code = COALESCE(v_run.scenario_code,'normal_day') LIMIT 1), 0.90)),
      'energy_demand_factor_peak', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50),
      'energy_demand_factor_expensive', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_expensive',0.35))
  ) INTO v_board;

  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_review_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('review', public.ottoq_agent_review(p_sim_run_id, 3));
  END IF;

  --: 0350. THE PER-ASSET HALF, gated and concatenated for the identical reason
  --: 0342 gated the return leg: at the default of 0 the board is byte-identical
  --: to its pre-0350 self, so no certification arm moves (A1 asserts it).
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_asset_depth_enabled',0),0) >= 1 THEN
    v_board := v_board || public.ottoq_agent_asset_depth(p_sim_run_id, v_depot, v_clock, 10, 10);
  END IF;

  --: 0432. THE GROUNDING HALF -- what is true now, the agent's own last writes and changes, the
  --: service queue, resources, energy limits, recent flow, and the work side's demand as read-only.
  --: Gated and CONCATENATED like 0342/0350: at the default of 0 the key is absent, not present-and-null.
  --: ottoq_agentic_arm sets it to 1 on every armed run.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_board_grounding_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('grounding',
                 public.ottoq_agent_board_grounding(p_sim_run_id, v_depot, v_clock));
  END IF;

  --: 0614. THE CHARGE LINE, so the agent can order it. Gated and concatenated like 0342/0350/0432: at the
  --: default of 0 the key is absent, and a baseline seat never carries it.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_charge_order',0),0) >= 1
     AND COALESCE(ottoq_policy_get(p_sim_run_id,'proposer_seat',0),0) = 0 THEN
    v_board := v_board || jsonb_build_object('charge_queue',
                 public.ottoq_agent_charge_queue_board(p_sim_run_id, v_depot, v_clock));
  END IF;

  RETURN v_board;
END; $function$
;

SET check_function_bodies = on;

-- ── the catalog rows the arm, the setter and the ops door read, with the live ranges and the live words of the six
--    descriptions 0629 rewrites ──
INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, agent_writable, agent_min_value, agent_max_value, agent_max_drift_pct)
VALUES
  ('agent_asset_depth_enabled', NULL, 0, 0, 1, false, NULL, NULL, NULL),
  ('agent_board_grounding_enabled', NULL, 0, 0, 1, false, NULL, NULL, NULL),
  ('agent_charge_order', '0614: whether OTTO-Q''s seat takes the agent''s charge order. 0 (the default) = the kernel''s own order, as before. 1 = under a live order (ottoq_agent_charge_orders, younger than agent_charge_order_ttl_ticks), the charge cursor seats immediate dispatches first, then cars waiting agent_charge_order_pin_wait_min or longer in the kernel''s order, then the cars the agent ranked (the ones named for the kind of charger now free first), then the rest in the kernel''s order; and a car named for dcfc or l2 prefers that kind. No charge is shortened and no charger idles. Set run-scoped by ottoq_agentic_arm (0615); never by the engine.', 0, 0, 1, false, NULL, NULL, NULL),
  ('agent_charge_order_ttl_ticks', '0614: how many ticks an accepted agent charge order stands without a newer one. The agent fires every third tick and its advice lands a mean of 4.2 ticks late (CLAUDE.md 2.5), so 15 bridges one or two passes the hosted model refuses; after it the kernel''s own order resumes.', 15, 3, 60, false, NULL, NULL, NULL),
  ('agent_review_enabled', 'When >= 1, ottoq_agent_board publishes a `review` key carrying what the deterministic kernel did with the agent''s last objectives -- the return leg of the agent/solver/kernel loop. 0 keeps the pre-2026-09-19 board, which reported nothing about the agent''s own outcomes. Certification arms and production runs keep 0.', 0, 0, 1, false, NULL, NULL, NULL),
  ('agent_solver_chain_enabled', NULL, 0, 0, 1, false, NULL, NULL, NULL),
  ('cuopt_first_refusal_max_defers', 'Maximum bounded deterministic beats that may yield to the active agent-selected solver before greedy fallback. 0 disables holds; agentic full mode sets 6.', 0, 0, 10, false, NULL, NULL, NULL),
  ('cuopt_propose_enabled', NULL, 0, 0, 1, false, NULL, NULL, NULL),
  ('deploy_surge_catchup', NULL, 0.35, 0.1, 1, false, 0.1, 1, 30),
  ('energy_demand_factor_expensive', NULL, 0.35, 0.2, 0.9, true, 0.2, 0.8, 30),
  ('energy_demand_factor_peak', NULL, 0.5, 0.25, 0.95, true, 0.3, 0.9, 30),
  ('energy_reserve_shave', NULL, 0, 0, 1, true, 0, 1, NULL),
  ('forecast_horizon_min', NULL, 30, 10, 90, false, 10, 90, 30),
  ('orchestrator_agent_enabled', '0112/0113: gates every Nemotron orchestrator-agent fire site for the session. 0 = deterministic core only (production_start default); 1 = agent may propose.', 1, 0, 1, false, NULL, NULL, NULL),
  ('prearrival_charge_yields_to_solver', NULL, 0, 0, 1, false, NULL, NULL, NULL),
  ('proposer_frame_facts', NULL, 0, 0, 1, false, NULL, NULL, NULL),
  ('proposer_hold_enabled', '0259/0262: second key of the one-tick hold gate in ottoq_cuopt_defer_hold. 1 = a run with cuOpt quiesced still holds an arriving vehicle out of the local cursor for one decide tick so any holds_tick proposer (ottoq_proposer_precedence) can answer; the hold releases the moment such a proposer answers and unconditionally at the next decide tick. Needs cuopt_first_refusal_max_defers >= 1 at the same scope or nothing is ever armed (0152: global tier is 0). Default 0. Certification arms set neither key.', 0, 0, 1, false, NULL, NULL, NULL);

-- ── the twin depot as 0629's V-blocks read it: one finished production session, one operator run, the 2026-09-26
--    promotion still in force at depot scope, and a person's global dial ──
INSERT INTO public.depots (id, feed_mode) VALUES ('11111111-1111-1111-1111-111111111111', 'sim');
INSERT INTO public.ottoq_scenarios (scenario_id, scenario_code)
VALUES ('5c000000-0000-0000-0000-000000000629', 'production'), ('5c000000-0000-0000-0000-000000000001', 'busy_day');
INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_code, started_at, ended_at, depot_id, status, run_by, policy, tick_count)
VALUES ('e8a0ba01-0000-0000-0000-000000000629', 'production', '2026-08-30 04:32:03+00', '2026-08-30 04:46:52+00',
        '11111111-1111-1111-1111-111111111111', 'completed', 'production_live', 'otto_q', 60),
       ('b2efcc07-0000-0000-0000-000000000629', 'busy_day', '2026-10-09 02:50:44+00', '2026-10-09 04:20:00+00',
        '11111111-1111-1111-1111-111111111111', 'completed', 'operator_demo', 'otto_q', 900);
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'energy_reserve_shave', 1, 'ottoq_prime:promoter', '2026-09-26 11:25:33+00'),
       ('global', '00000000-0000-0000-0000-000000000000', 'energy_demand_factor_expensive', 0.35, 'engineering', '2026-10-08 11:00:00+00');
