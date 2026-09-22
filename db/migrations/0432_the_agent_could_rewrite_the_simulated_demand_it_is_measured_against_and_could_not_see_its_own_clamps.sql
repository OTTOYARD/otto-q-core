-- migration-version: PENDING
-- migration-name:    the_agent_could_rewrite_the_simulated_demand_it_is_measured_against_and_could_not_see_its_own_clamps
--
-- 0432  **The orchestrator agent stops setting the work side's demand, the catalog's `agent_writable` flag
--       starts meaning something, the ops path stops reporting refusals as successes, and every armed run's
--       board gains a grounding block that says what is true now -- plus the per-asset view 0350 built and
--       nothing ever switched on.** Evidence: `db/checks/0352`. Edge function v19 ships with this file.
--
-- ══ §1 WHAT 0352 MEASURED ON RUN 0682752c, AND WHAT PRE-FLIGHT ADDED ═════════
--
--   * The board showed `deploy_peak_fraction = 0.90`; the dispatcher was using the busy_day scenario's
--     `target_deployed_fraction = 0.45`. At tick 1 the agent made "the smallest effective change" -- to
--     **0.95**, doubling the peak deployment target -- then walked it down and asked for 0.35-0.45 on **96 of
--     106** writes, every one clamped to the agent floor 0.50. The scenario's own value was unreachable and
--     the agent was never told it had been clamped.
--   * On the two energy dials, **71% and 68%** of the agent's changes reversed its previous change.
--   * `deploy_peak_fraction` is the work side's demand -- how much of the fleet the dispatcher deploys each
--     hour. CLAUDE.md rule 6 allows no work-side features. An agent that can move demand can make any KPI of
--     the run it is judged on look however it likes.
--   * **It has done so on every run it touched it on.** `ottoq_policy_params` holds 312 rows of this dial,
--     every one `scope_type='run'`, every one `updated_by='ottoq_prime'`, values 0.50-1.00. No operator,
--     scenario or promoter row exists. So every agentic run's KPIs were measured against a demand curve the
--     agent chose.
--   * `ottoq_dial_clamp` SELECTs `agent_writable` into `v_writable` and never uses the variable, and
--     `ottoq_apply_ops_action` returns `applied` whatever the setter answered.
--   * `AI.001.agent_dial_within_envelope` -- the `policy_write` rule -- already DETECTS an agent write to a
--     non-writable dial (critical, remedy `set_agent_writable_or_block_the_actor`). It is `log_only` and the
--     setter's probe is error-swallowed by design ("a reporting probe must never be able to refuse"), so the
--     detection has had no actuator. This file supplies the remedy the rule already names; it does not add a
--     second detector.
--   * Every non-cert run is armed at start (`twin.ottoq_sim_start_run`, `public.ottoq_sim_run_scenario` ->
--     `ottoq_agentic_arm`), and the arm sets eight dials. `agent_asset_depth_enabled` is not one of them:
--     0350's per-asset block has exactly ONE run-scoped row in its life (`claude_0350_demo`). The agent has
--     reasoned about 116 vehicles from counts on every demo run since 2026-09-19 while the summary built for
--     it sat behind a dial nobody turned. Measured on 0682752c: 30 ms, 3,136 bytes.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   (A) `deploy_peak_fraction` -> `agent_writable = false`. Operators and scenarios may still set it; the
--       agent may not. `deploy_surge_catchup` stays writable: it is the depot's RELEASE RATE against the
--       demand, not the demand. By the promoter's own gate 2 (`gate2_dial_is_not_agent_writable`) the
--       learning loop stops being able to promote it too -- it could otherwise learn a demand reduction as a
--       "better policy", which is the same gaming by a slower route.
--   (B) `public.ottoq_policy_set` refuses an agent actor (`ottoq_is_agent_actor`) on any dial whose catalog
--       row says `agent_writable = false`, returning `{ok:false, error:'not_agent_writable'}` -- the refusal
--       shape the edge function already records since G65. It refuses AFTER the `policy_write` probe, so
--       AI.001 still logs the attempt. Non-agent writers are untouched; the envelope clamp is unchanged.
--   (C) `public.ottoq_apply_ops_action` reads the setter's answer: `status:'refused'` with the reason when the
--       setter refuses, and `status:'no_change'` (no write) when the action would set the value already in
--       force. The three actions, their clamps and the approval queue are unchanged.
--   (D) `public.ottoq_agent_board_grounding(run, depot, clock)`: effective values read the way each consumer
--       reads them; every agent actuator with its envelope, write/clamp counts, the agent's last write and its
--       last CHANGE (from, to, direction, minutes ago); a queue that separates vehicles WAITING for service
--       from readiness checks that are merely not due yet; pointer-level resource counts labelled as such;
--       energy limits including an active DR call; the last 30 sim-minutes of flow instead of run-cumulative
--       counters; and the work side's demand as read-only information. ~3 KB, ~0.1 s.
--   (E) The board's `policy.deploy_peak_fraction` reads with the dispatcher's own default (the scenario's
--       `target_deployed_fraction`), so it stops disagreeing with the engine; and the board concatenates
--       `grounding` when run-scoped `agent_board_grounding_enabled >= 1` (catalog default 0, so an unarmed
--       board is byte-identical to its pre-0432 self apart from that one corrected value).
--   (F) Two catalogued dials: `agent_board_grounding_enabled` (0/1, default 0) and
--       `agent_dial_reversal_dwell_min` (default 30), which edge function v19 enforces.
--   (G) `ottoq_agentic_arm` also sets `agent_board_grounding_enabled = 1` and `agent_asset_depth_enabled = 1`,
--       so every armed run's agent sees both. The cert guard (42501) is untouched.
--
-- ══ §3 WHY `forces_recert` IS FALSE ══════════════════════════════════════════
--
-- Nothing a certification pair runs can observe any of this, and P3 asserts the premises rather than
-- arguing them: `ottoq_agent_board` and `ottoq_apply_ops_action` have no caller in the database (only the
-- agent edge function calls them, and 0105 keeps the agent from firing on `cert_harness` runs); the arm
-- refuses a `cert_harness` run by raising and both of its callers skip it for one, so no cert arm carries the
-- new dials; and (B) changes the setter's answer only for agent actors, which never write dials inside a
-- pair. (E)'s corrected `policy` value changes the board for every run, and no atom reads the board.
--
-- ══ §4 WHAT IS DELIBERATELY NOT DONE ════════════════════════════════════════
--
--   1. **The consumers still disagree on `deploy_peak_fraction`'s default** when nothing overrides it: the
--      dispatcher uses the scenario's value or 0.90, `ottoq_decide_tick` the scenario's value or 0.55, and
--      `twin.ottoq_sim_advance_service_flow`'s deploy-pressure check a fixed 0.90. On busy_day the first two
--      agree (0.45) and service_flow does not. The agent's tick-1 write used to paper over that; it no longer
--      will. Filed, not changed here -- it is an engine change and needs its own recert.
--   2. **No DR or BESS change.** The grounding block reports that battery discharge does not raise the DR
--      cap in the current gate; it does not change the gate (task #18).
--   3. **`vehicle_need_profile` is shared across runs, not run-scoped.** `ottoq_run_boot_draw` re-seeds it
--      per run, so a certification sweep that runs during a demo run overwrites the demo's deadlines with the
--      canon's sim date (measured now: 107 of 116 twin profiles carry `next_deploy_at` on 2026-09-01, the
--      canon start). The asset block is right during a live run and wrong after a sweep. Filed.
--   4. **AI.001 stays `log_only`.** It is the detector; the setter is the actuator for the one branch whose
--      remedy is to block. Its envelope branch keeps its own remedy, the clamp.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0432 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0432 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0432 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guards on the four functions this file changes ──
DO $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT p.proname, md5(p.prosrc) AS m FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN ('ottoq_policy_set','ottoq_apply_ops_action','ottoq_agent_board','ottoq_agentic_arm')
  LOOP
    v_n := v_n + 1;
    IF (r.proname = 'ottoq_policy_set'       AND r.m <> '5bebd8cb960d197b12111c4819fe399e')
    OR (r.proname = 'ottoq_apply_ops_action' AND r.m <> '6696c70de0bc107ffcff233847806bb8')
    OR (r.proname = 'ottoq_agent_board'      AND r.m <> 'ce1815bc65193cb1bb6b9ba8d90d002f')
    OR (r.proname = 'ottoq_agentic_arm'      AND r.m <> 'f7e248be9539a94656b08dcfba2d0311') THEN
      RAISE EXCEPTION '0432 P1: % prosrc md5 is % -- it changed since 0352 read it', r.proname, r.m;
    END IF;
  END LOOP;
  IF v_n <> 4 THEN RAISE EXCEPTION '0432 P1: expected 4 functions (one overload each), found %', v_n; END IF;
END $$;

-- ── P2: every anchor occurs exactly once ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  v_a := 'INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0432 P2: setter INSERT anchor matched % times', v_n; END IF;
  IF position('PERFORM 1 FROM public.ottoq_shield_probe(' in v_src) = 0
     OR position('PERFORM 1 FROM public.ottoq_shield_probe(' in v_src) > position(v_a in v_src) THEN
    RAISE EXCEPTION '0432 P2: the setter''s policy_write probe no longer precedes its INSERT -- the refusal '
                    'would bypass the ledger';
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board';
  v_a := E'\n  RETURN v_board;\n';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0432 P2: board RETURN anchor matched % times', v_n; END IF;
  v_a := $a$'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90),$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0432 P2: board policy anchor matched % times', v_n; END IF;
  IF position('scenario_code' in v_src) = 0 THEN
    RAISE EXCEPTION '0432 P2: the board no longer selects scenario_code into v_run -- (E) would not resolve';
  END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agentic_arm';
  v_a := $a$('agent_review_enabled', 1::numeric)$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0432 P2: arm VALUES anchor matched % times', v_n; END IF;
END $$;

-- ── P3: THE PREMISES OF forces_recert = FALSE, AND OF (A) ──
DO $$
DECLARE v_n int; v_names text; v_src text;
BEGIN
  -- the board and the ops action are called from outside the database only
  SELECT count(*), string_agg(n.nspname || '.' || p.proname, ', ') INTO v_n, v_names
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.proname NOT IN ('ottoq_agent_board','ottoq_apply_ops_action')
     AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '(ottoq_agent_board|ottoq_apply_ops_action)\s*\(';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0432 P3: the board or the ops action has an in-database caller (%) -- forces_recert '
                    'FALSE would be unfounded', v_names;
  END IF;

  -- the arm refuses a certification arm, and both of its callers skip one
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agentic_arm';
  IF regexp_replace(v_src, '--[^\n]*', '', 'g') !~ $re$IF\s+v_run_by\s*=\s*'cert_harness'\s+THEN$re$
     OR position('42501' in v_src) = 0 THEN
    RAISE EXCEPTION '0432 P3: ottoq_agentic_arm no longer refuses a cert_harness run -- (G) would reach the canon';
  END IF;
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE (n.nspname, p.proname) IN (('twin','ottoq_sim_start_run'), ('public','ottoq_sim_run_scenario'))
     AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g')
         ~ $re$IF\s+COALESCE\(p_run_by,\s*''\)\s*<>\s*'cert_harness'\s+THEN\s+BEGIN\s+PERFORM\s+public\.ottoq_agentic_arm\($re$;
  IF v_n <> 2 THEN RAISE EXCEPTION '0432 P3: % of the arm''s 2 callers still skip cert_harness', v_n; END IF;

  -- the orchestrator fire gate still excludes cert runs (0105)
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_decide_and_dispatch'
     AND p.prosrc ~ $re$NOT IN \('benchmark', 'cert_harness'\)$re$;
  IF v_n <> 1 THEN RAISE EXCEPTION '0432 P3: 0105''s cert quiesce is gone from ottoq_sim_decide_and_dispatch'; END IF;

  -- nothing agent-written on this dial outlives the change: no global/depot row, none on a live run
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params pp
    LEFT JOIN public.ottoq_sim_runs r ON pp.scope_type = 'run' AND r.sim_run_id = pp.scope_id
   WHERE pp.param_key = 'deploy_peak_fraction' AND public.ottoq_is_agent_actor(pp.updated_by)
     AND (pp.scope_type <> 'run' OR r.status IN ('running','paused'));
  IF v_n <> 0 THEN RAISE EXCEPTION '0432 P3: % agent-written deploy_peak_fraction rows would outlive (A)', v_n; END IF;

  -- no dial currently in force was written by an agent onto a key that is ALREADY non-writable
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params pp JOIN public.ottoq_policy_param_catalog c USING (param_key)
   WHERE public.ottoq_is_agent_actor(pp.updated_by) AND NOT COALESCE(c.agent_writable, false);
  IF v_n <> 0 THEN RAISE EXCEPTION '0432 P3: % agent-written rows already sit on non-writable dials', v_n; END IF;

  -- (A) reaches the learning loop through the promoter's own gate, not through anything added here
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_promote_dials'
     AND p.prosrc ~ $re$IF NOT COALESCE\(r\.agent_writable,\s*false\) THEN\s+v_outcome := 'refused'; v_reason := 'gate2_dial_is_not_agent_writable'$re$;
  IF v_n <> 1 THEN RAISE EXCEPTION '0432 P3: ottoq_promote_dials no longer gates on agent_writable'; END IF;
END $$;

-- ── P4: the premises -- deploy_peak_fraction is still agent-writable, the depth dial exists ──
DO $$
BEGIN
  IF NOT (SELECT agent_writable FROM public.ottoq_policy_param_catalog WHERE param_key = 'deploy_peak_fraction') THEN
    RAISE WARNING '0432 P4: deploy_peak_fraction is already not agent-writable; (A) is a no-op';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'agent_asset_depth_enabled' AND min_value = 0 AND max_value = 1) THEN
    RAISE EXCEPTION '0432 P4: agent_asset_depth_enabled is not catalogued as 0..1 -- (G) would be refused or clamped';
  END IF;
END $$;

-- ── SNAPSHOT BEFORE REPLACING ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0432_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_policy_set','ottoq_apply_ops_action','ottoq_agent_board','ottoq_agentic_arm');

-- ── (A) + (F): THE CATALOG ──
UPDATE public.ottoq_policy_param_catalog
   SET agent_writable = false,
       description = description || ' 0432: NOT an agent actuator. This is the work side''s demand -- how much of '
                     'the fleet the dispatcher deploys each hour -- and CLAUDE.md rule 6 allows no work-side '
                     'features. On run 0682752c the agent, shown 0.90 while the engine used the scenario''s 0.45, '
                     'set it to 0.95 at tick 1; all 312 stored rows of this dial were written by the agent '
                     '(db/checks/0352). Operators and scenarios may still set it; the promoter''s gate 2 now refuses it.'
 WHERE param_key = 'deploy_peak_fraction';

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('agent_board_grounding_enabled',
        '0432: when >= 1, public.ottoq_agent_board carries a grounding block (effective values, the agent''s own '
        'last writes and changes, a service queue, resources, energy limits, recent flow, work-side demand as '
        'read-only). ottoq_agentic_arm sets 1 on every armed run; the catalog default 0 keeps an unarmed board '
        'free of the key.', 0, 0, 1, 'ottoq_agent_board -> ottoq-orchestrator-agent prompt', false),
       ('agent_dial_reversal_dwell_min',
        '0432: sim-minutes after the agent CHANGES a dial during which edge function v19 holds a change to the '
        'same dial in the OPPOSITE direction (db/checks/0352: 71% and 68% of energy-dial changes reversed the '
        'previous one). Published on the board as grounding.stability.reversal_dwell_min. 0 disables the hold.',
        30, 0, 240, 'edge:ottoq-orchestrator-agent', false)
ON CONFLICT (param_key) DO NOTHING;

-- ── (B): THE SETTER REFUSES AN AGENT ON A NON-WRITABLE DIAL ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_anchor text; v_insert text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  v_def := pg_get_functiondef(v_oid);
  v_anchor := 'INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)';
  v_insert := $ins$-- 0432: agent_writable IS A GUARD, NOT A LABEL. ottoq_dial_clamp reads the flag into a variable and
  -- never uses it, and a non-writable dial's NULL agent bounds let an agent write straight through
  -- (db/checks/0352 section 5a). AI.001 at the probe above already DETECTS this case and names the remedy
  -- set_agent_writable_or_block_the_actor; this is that remedy. The probe has logged the attempt.
  IF public.ottoq_is_agent_actor(p_by)
     AND NOT COALESCE((SELECT c.agent_writable FROM ottoq_policy_param_catalog c
                        WHERE c.param_key = p_param_key), false) THEN
    RETURN jsonb_build_object('ok',false,'error','not_agent_writable','param',p_param_key,'by',p_by,
                              'detail','this dial is not an agent actuator (ottoq_policy_param_catalog.agent_writable)');
  END IF;

$ins$;
  IF (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 THEN
    RAISE EXCEPTION '0432 (B): anchor not unique in the definition';
  END IF;
  v_new := replace(v_def, v_anchor, v_insert || v_anchor);
  IF length(v_new) - length(v_def) <> length(v_insert) THEN
    RAISE EXCEPTION '0432 (B): byte delta % <> %', length(v_new) - length(v_def), length(v_insert);
  END IF;
  EXECUTE v_new;
END $$;

-- ── (C): THE OPS PATH REPORTS THE SETTER'S ANSWER ──
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
    -- OUT OF WHITELIST → human approval queue (Pulse), not a silent drop.
    INSERT INTO ottoq_ops_approvals (approval_type, sim_run_id, depot_id, status, priority, payload, requested_at, expires_at)
    VALUES ('nemotron_ops_action', p_sim_run_id, p_depot_id, 'pending',
            COALESCE(NULLIF(p_args->>'priority',''), 'normal'),
            jsonb_build_object('action', p_action, 'args', p_args, 'by', p_by, 'reason','not in auto-exec whitelist'),
            now(), now() + interval '30 minutes');
    RETURN jsonb_build_object('status','queued_for_approval','action',p_action);
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

-- ── (D): THE GROUNDING FUNCTION ──
CREATE OR REPLACE FUNCTION public.ottoq_agent_board_grounding(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
-- 0432 (db/checks/0352). The half of the agent's board that says what is TRUE NOW, as the engine sees it.
-- Every number here is read the way the engine's own consumer reads it: the deploy target with the
-- dispatcher's scenario default, fleet and deployed count exactly as twin.ottoq_sim_auto_dispatch_tick
-- counts them, the charge cap through ottoq_effective_charge_cap_kw, a DR call with the cap function's own
-- predicate, the technician pool the way ottoq_start_concurrent_atoms subtracts it.
-- Stall counts are POINTER counts and are labelled so: a stall is offerable only where the pointer, the
-- calendar and (for charge stalls) the charger agree, and this does not claim the other two.
-- Actuator history reads BOTH of the agent's write paths (set_policy entries carry key/value; ops_action
-- entries carry param/to) and a change's `from` comes from the entry when v19 logged it, else from the
-- previous write -- so the last CHANGE survives resends, which is what the reversal dwell needs.
DECLARE
  v_zero constant uuid := '00000000-0000-0000-0000-000000000000';
  v_scn text; v_target_pct numeric; v_mult numeric; v_hour int; v_peak numeric;
  v_fleet int; v_deployed int;
BEGIN
  SELECT r.scenario_code INTO v_scn FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  SELECT (s.fleet_overrides->>'target_deployed_fraction')::numeric,
         COALESCE((s.fleet_overrides->>'dispatch_rate_multiplier')::numeric, 1.0)
    INTO v_target_pct, v_mult
    FROM ottoq_sim_scenarios s WHERE s.scenario_code = COALESCE(v_scn, 'normal_day') LIMIT 1;
  v_mult := COALESCE(v_mult, 1.0);
  v_hour := EXTRACT(HOUR FROM p_clock AT TIME ZONE 'America/Chicago')::int;
  v_peak := ottoq_policy_get(p_sim_run_id, 'deploy_peak_fraction', COALESCE(v_target_pct, 0.90));
  SELECT count(*) INTO v_fleet FROM vehicles WHERE home_depot_id = p_depot_id AND category = 'autonomous';
  SELECT count(*) INTO v_deployed FROM ottoq_vehicle_dispatches
   WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning');

  RETURN jsonb_build_object(
    'note', 'What is true now, read the way the engine reads it. Prefer these values over policy/needs/flow. '
            'readiness_check is the LAST atom of every visit, so a pending one on a vehicle still in service '
            'is not backlog; queue.waiting_for_service is the backlog. Stall counts are pointer counts.',

    'queue', (
      SELECT jsonb_build_object(
               'waiting_for_service', jsonb_build_object(
                   'vehicles', count(*) FILTER (WHERE q.waiting),
                   'p50_min_since_arrival', round((percentile_cont(0.5) WITHIN GROUP (ORDER BY q.wait_min)
                                                   FILTER (WHERE q.waiting))::numeric, 1),
                   'max_min_since_arrival', round((max(q.wait_min) FILTER (WHERE q.waiting))::numeric, 1)),
               'exit_checks_due', count(*) FILTER (WHERE q.exit_due),
               'readiness_checks_not_yet_due', count(*) FILTER (WHERE q.readiness_pending AND NOT q.exit_due),
               'vehicles_being_served', count(*) FILTER (WHERE q.in_service))
        FROM (SELECT extract(epoch FROM (p_clock - vn.arrived_at)) / 60.0 AS wait_min,
                     (v.current_state IN ('staged_awaiting_service','arrived_at_gate','charge_complete_holding')
                      AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                   WHERE COALESCE((a->>'must_do')::boolean, false)
                                     AND a->>'svc' <> 'readiness_check'
                                     AND COALESCE(a->>'status','pending') = 'pending')
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'status' = 'in_progress')) AS waiting,
                     (v.current_state = 'staged_for_departure'
                      AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                   WHERE a->>'svc' = 'readiness_check'
                                     AND COALESCE(a->>'status','pending') = 'pending')) AS exit_due,
                     EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                              WHERE a->>'svc' = 'readiness_check'
                                AND COALESCE(a->>'status','pending') = 'pending') AS readiness_pending,
                     (v.current_state IN ('charging_dcfc','charging_l2')
                      OR EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                  WHERE a->>'status' = 'in_progress')) AS in_service
                FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
               WHERE vn.depot_id = p_depot_id
                 AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                 AND vn.status IN ('open','in_progress')) q),

    'resources', (
      SELECT jsonb_object_agg(r.kind, r.detail) FROM (
        SELECT s.stall_type::text AS kind,
               jsonb_build_object(
                 'total', count(*),
                 'occupied', count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL),
                 'faulted_charger', count(*) FILTER (WHERE s.stall_type::text IN ('dcfc','l2')
                                                       AND ch.station_state = 'Faulted'),
                 'out_of_service', count(*) FILTER (WHERE s.status::text IN ('maintenance','closed')),
                 'free_by_pointer', count(*) FILTER (
                     WHERE s.current_vehicle_id IS NULL
                       AND s.status::text NOT IN ('maintenance','closed')
                       AND NOT (s.stall_type::text IN ('dcfc','l2') AND COALESCE(ch.station_state,'') = 'Faulted')
                       AND (s.reserved_by IS NULL OR COALESCE(s.reservation_expires_at, p_clock) <= p_clock))) AS detail
          FROM stalls s LEFT JOIN ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
         WHERE s.depot_id = p_depot_id
         GROUP BY s.stall_type
        UNION ALL
        SELECT 'general_tech',
               jsonb_build_object(
                 'total', ottoq_depot_staffing_count(p_depot_id, 'general_tech'),
                 'busy', (SELECT count(*) FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
                           WHERE vn2.depot_id = p_depot_id AND vn2.status = 'in_progress'
                             AND COALESCE(vn2.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                             AND a2->>'status' = 'in_progress' AND a2->>'concurrency' IN ('cabin','exterior')))) r),

    'energy_limits', jsonb_build_object(
      'effective_charge_cap_kw', round(public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_clock)),
      'service_max_kw', (SELECT d.service_max_kw FROM depots d WHERE d.id = p_depot_id),
      'dr_call', (SELECT jsonb_build_object('program', c.program, 'reason', c.reason,
                                            'cap_kw', round(c.required_load_cap_kw),
                                            'minutes_left', round(extract(epoch FROM (c.expires_at - p_clock)) / 60.0))
                    FROM ottoq_dr_calls c
                   WHERE c.depot_id = p_depot_id AND c.call_status IN ('active','issued') AND c.expires_at > p_clock
                     AND COALESCE(c.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
                   ORDER BY c.required_load_cap_kw ASC, c.dr_call_id LIMIT 1),
      'site_now', (SELECT jsonb_build_object('ev_kw', round(e.total_ev_charging_kw), 'grid_import_kw', round(e.grid_import_kw),
                                             'bess_kw', round(e.bess_output_kw), 'tariff', e.current_tariff_label)
                     FROM site_energy_snapshots e
                    WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id
                    ORDER BY e.timestamp DESC LIMIT 1),
      'bess', (SELECT jsonb_build_object('soc_pct', round(b.current_soc_pct, 1),
                                         'usable_kwh_above_floor',
                                           round(GREATEST(0, b.capacity_kwh * (b.current_soc_pct - COALESCE(b.soc_min_floor_pct, 10)) / 100.0)))
                 FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1),
      'note', 'While a DR call is active, new charges are admitted only while committed EV kW stays under the '
              'call''s cap; battery discharge does not raise that cap in the current gate.'),

    'flow_last_30m', jsonb_build_object(
      'legs_done', (SELECT count(*) FROM ottoq_itinerary_legs l WHERE l.sim_run_id = p_sim_run_id AND l.status = 'done'
                      AND l.actual_end_sim > p_clock - interval '30 minutes' AND l.actual_end_sim <= p_clock),
      'legs_skipped', (SELECT count(*) FROM ottoq_itinerary_legs l WHERE l.sim_run_id = p_sim_run_id AND l.status = 'skipped'
                         AND l.planned_end_sim > p_clock - interval '30 minutes' AND l.planned_end_sim <= p_clock),
      'mean_abs_deviation_min', (SELECT round(avg(abs(l.deviation_s)) / 60.0, 1) FROM ottoq_itinerary_legs l
                                  WHERE l.sim_run_id = p_sim_run_id AND l.deviation_s IS NOT NULL
                                    AND l.actual_end_sim > p_clock - interval '30 minutes' AND l.actual_end_sim <= p_clock),
      'departures', (SELECT count(*) FROM ottoq_vehicle_dispatches d WHERE d.sim_run_id = p_sim_run_id
                       AND d.dispatched_at > p_clock - interval '30 minutes' AND d.dispatched_at <= p_clock),
      'arrivals', (SELECT count(*) FROM ottoq_visit_needs vn WHERE vn.sim_run_id = p_sim_run_id AND vn.depot_id = p_depot_id
                     AND vn.arrived_at > p_clock - interval '30 minutes' AND vn.arrived_at <= p_clock)),

    'work_side_demand', jsonb_build_object(
      'read_only', true,
      'note', 'How much of the fleet the work side wants deployed now. It is the demand you are measured '
              'against, not an actuator; no action can change it.',
      'deploy_peak_fraction_effective', v_peak,
      'deploy_target_now', FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, v_peak) * v_mult),
      'deployed_now', v_deployed,
      'fleet', v_fleet),

    'stability', jsonb_build_object(
      'reversal_dwell_min', ottoq_policy_get(p_sim_run_id, 'agent_dial_reversal_dwell_min', 30),
      'rule', 'A dial whose last_change is younger than reversal_dwell_min sim-minutes may move again only in '
              'the same direction. A write to the value already in force is not a move.'),

    'actuators', (
      WITH w AS (
        SELECT CASE WHEN a->>'type' = 'set_policy' THEN a->>'key' ELSE a->>'param' END AS key,
               d.tick_seq, d.decision_seq, d.sim_clock,
               NULLIF(a->>'requested','')::numeric AS requested,
               NULLIF(CASE WHEN a->>'type' = 'set_policy' THEN a->>'value' ELSE a->>'to' END, '')::numeric AS applied,
               NULLIF(a->>'from','')::numeric AS from_logged,
               CASE WHEN a->>'type' = 'set_policy' THEN COALESCE(a->>'limited_by','none')
                    WHEN COALESCE((a->>'clamped')::boolean, false) THEN 'catalog'
                    ELSE 'none' END AS limited_by
          FROM ottoq_decisions d, jsonb_array_elements(COALESCE(d.enacted_action->'applied','[]'::jsonb)) a
         WHERE d.sim_run_id = p_sim_run_id AND d.resolved_action_context = 'orchestrator_agent'
           AND a->>'type' IN ('set_policy','ops_action')),
      h AS (
        SELECT w.*,
               COALESCE(w.from_logged,
                        lag(w.applied) OVER (PARTITION BY w.key ORDER BY w.tick_seq, w.decision_seq)) AS from_value,
               row_number() OVER (PARTITION BY w.key ORDER BY w.tick_seq DESC, w.decision_seq DESC) AS rn
          FROM w WHERE w.key IS NOT NULL AND w.applied IS NOT NULL),
      s AS (
        SELECT h.key, count(*) AS writes, count(*) FILTER (WHERE h.limited_by <> 'none') AS clamped
          FROM h GROUP BY h.key),
      lc AS (
        SELECT DISTINCT ON (h.key) h.key, h.tick_seq, h.sim_clock, h.from_value, h.applied
          FROM h WHERE h.from_value IS NOT NULL AND h.applied <> h.from_value
         ORDER BY h.key, h.tick_seq DESC, h.decision_seq DESC)
      SELECT jsonb_object_agg(c.param_key, jsonb_build_object(
               'value', round(ottoq_policy_get(p_sim_run_id, c.param_key, c.default_value), 4),
               'agent_min', COALESCE(c.agent_min_value, c.min_value),
               'agent_max', COALESCE(c.agent_max_value, c.max_value),
               'writes', COALESCE(s.writes, 0),
               'clamped', COALESCE(s.clamped, 0),
               'last_write', (SELECT jsonb_build_object('tick', h1.tick_seq, 'requested', h1.requested,
                                                        'applied', h1.applied, 'limited_by', h1.limited_by,
                                                        'min_ago', round(extract(epoch FROM (p_clock - h1.sim_clock)) / 60.0, 1))
                                FROM h h1 WHERE h1.key = c.param_key AND h1.rn = 1),
               'last_change', (SELECT jsonb_build_object('tick', lc.tick_seq, 'from', lc.from_value, 'to', lc.applied,
                                                         'direction', CASE WHEN lc.applied > lc.from_value THEN 'up' ELSE 'down' END,
                                                         'min_ago', round(extract(epoch FROM (p_clock - lc.sim_clock)) / 60.0, 1))
                                 FROM lc WHERE lc.key = c.param_key)))
        FROM ottoq_policy_param_catalog c
        LEFT JOIN s ON s.key = c.param_key
       WHERE c.agent_writable)
  );
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_board_grounding(uuid, uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_board_grounding(uuid, uuid, timestamptz) TO authenticated, service_role;

-- ── (E): THE BOARD -- the corrected default, and the grounding half ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_a1 text; v_r1 text; v_a2 text; v_r2 text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board';
  v_def := pg_get_functiondef(v_oid);

  v_a1 := $a$'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90),$a$;
  v_r1 := $r$'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',  --: 0432: the dispatcher's own default
        COALESCE((SELECT (s.fleet_overrides->>'target_deployed_fraction')::numeric FROM ottoq_sim_scenarios s
                   WHERE s.scenario_code = COALESCE(v_run.scenario_code,'normal_day') LIMIT 1), 0.90)),$r$;
  v_a2 := E'\n  RETURN v_board;\n';
  v_r2 := E'\n  --: 0432. THE GROUNDING HALF -- what is true now, the agent''s own last writes and changes, the\n'
       || E'  --: service queue, resources, energy limits, recent flow, and the work side''s demand as read-only.\n'
       || E'  --: Gated and CONCATENATED like 0342/0350: at the default of 0 the key is absent, not present-and-null.\n'
       || E'  --: ottoq_agentic_arm sets it to 1 on every armed run.\n'
       || E'  IF COALESCE(ottoq_policy_get(p_sim_run_id,''agent_board_grounding_enabled'',0),0) >= 1 THEN\n'
       || E'    v_board := v_board || jsonb_build_object(''grounding'',\n'
       || E'                 public.ottoq_agent_board_grounding(p_sim_run_id, v_depot, v_clock));\n'
       || E'  END IF;\n'
       || v_a2;

  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1
  OR (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '0432 (E): an anchor is not unique in the definition';
  END IF;
  v_new := replace(replace(v_def, v_a1, v_r1), v_a2, v_r2);
  IF length(v_new) - length(v_def) <> (length(v_r1) - length(v_a1)) + (length(v_r2) - length(v_a2)) THEN
    RAISE EXCEPTION '0432 (E): byte delta % <> %', length(v_new) - length(v_def),
                    (length(v_r1) - length(v_a1)) + (length(v_r2) - length(v_a2));
  END IF;
  EXECUTE v_new;
END $$;

-- ── (G): THE ARM SWITCHES BOTH HALVES ON ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_a text; v_r text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agentic_arm';
  v_def := pg_get_functiondef(v_oid);
  v_a := $a$('agent_review_enabled', 1::numeric)$a$;
  v_r := $r$('agent_review_enabled', 1::numeric),
      ('agent_board_grounding_enabled', 1::numeric),   --: 0432
      ('agent_asset_depth_enabled', 1::numeric)        --: 0432: 0350's block, never armed before$r$;
  IF (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 THEN
    RAISE EXCEPTION '0432 (G): anchor not unique in the definition';
  END IF;
  v_new := replace(v_def, v_a, v_r);
  IF length(v_new) - length(v_def) <> length(v_r) - length(v_a) THEN
    RAISE EXCEPTION '0432 (G): byte delta % <> %', length(v_new) - length(v_def), length(v_r) - length(v_a);
  END IF;
  EXECUTE v_new;
END $$;

-- ── V1: THE SETTER -- an agent is refused on the demand, still served on its actuators, an operator is
--        untouched, and AI.001 logged the refused attempt as the violation it detects ──
DO $v1$
DECLARE
  v_fake constant uuid := '00000000-0000-0000-0000-0000000004a2';
  r_agent jsonb; r_ok jsonb; r_op jsonb; v_ai int; v_ai_reason text;
BEGIN
  BEGIN
    r_agent := public.ottoq_policy_set('run', v_fake, 'deploy_peak_fraction', 0.95, 'ottoq_prime');
    r_ok    := public.ottoq_policy_set('run', v_fake, 'energy_demand_factor_peak', 0.6, 'ottoq_prime');
    r_op    := public.ottoq_policy_set('run', v_fake, 'deploy_peak_fraction', 0.45, 'operator_0432_verify');
    SELECT count(*), max(e.reason) INTO v_ai, v_ai_reason
      FROM public.ottoq_rule_evaluations e
     WHERE e.action_context = 'policy_write' AND e.rule_code = 'AI.001.agent_dial_within_envelope'
       AND e.context->>'scope_id' = v_fake::text AND e.context->>'param_key' = 'deploy_peak_fraction'
       AND e.context->>'by' = 'ottoq_prime' AND NOT e.passed;
    RAISE EXCEPTION USING MESSAGE = '0432_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0432_probe_rollback' THEN RAISE; END IF;
  END;
  IF COALESCE(r_agent->>'ok','') <> 'false' OR COALESCE(r_agent->>'error','') <> 'not_agent_writable' THEN
    RAISE EXCEPTION '0432 V1: an agent write to deploy_peak_fraction was not refused: %', r_agent;
  END IF;
  IF COALESCE(r_ok->>'ok','') <> 'true' OR (r_ok->>'applied')::numeric <> 0.6 THEN
    RAISE EXCEPTION '0432 V1: an agent write to a writable dial no longer lands: %', r_ok;
  END IF;
  IF COALESCE(r_op->>'ok','') <> 'true' OR (r_op->>'applied')::numeric <> 0.45 THEN
    RAISE EXCEPTION '0432 V1: an operator can no longer set the scenario''s own demand: %', r_op;
  END IF;
  IF v_ai <> 1 OR v_ai_reason NOT ILIKE '%not agent-writable%' THEN
    RAISE EXCEPTION '0432 V1: AI.001 did not log the refused attempt (% rows, reason %)', v_ai, v_ai_reason;
  END IF;
END $v1$;

-- ── V2: THE OPS PATH -- applied, no_change and refused each come back as what they are ──
DO $v2$
DECLARE
  v_fake constant uuid := '00000000-0000-0000-0000-0000000004a2';
  v_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  r_applied jsonb; r_same jsonb; r_refused jsonb;
BEGIN
  BEGIN
    -- pin each starting value at run scope, so no global row can make a move a no-op by accident
    PERFORM public.ottoq_policy_set('run', v_fake, 'forecast_horizon_min', 30, 'operator_0432_verify');
    PERFORM public.ottoq_policy_set('run', v_fake, 'energy_reserve_shave', 1, 'operator_0432_verify');
    PERFORM public.ottoq_policy_set('run', v_fake, 'deploy_surge_catchup', 0.35, 'operator_0432_verify');
    r_applied := public.ottoq_apply_ops_action(v_fake, v_depot, 'extend_forecast_horizon', '{}'::jsonb, 'ottoq_prime');
    r_same    := public.ottoq_apply_ops_action(v_fake, v_depot, 'enable_energy_reserve', '{}'::jsonb, 'ottoq_prime');
    UPDATE public.ottoq_policy_param_catalog SET agent_writable = false WHERE param_key = 'deploy_surge_catchup';
    r_refused := public.ottoq_apply_ops_action(v_fake, v_depot, 'raise_deploy_surge', '{}'::jsonb, 'ottoq_prime');
    RAISE EXCEPTION USING MESSAGE = '0432_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0432_probe_rollback' THEN RAISE; END IF;
  END;
  IF COALESCE(r_applied->>'status','') <> 'applied' OR (r_applied->>'to')::numeric <= (r_applied->>'from')::numeric THEN
    RAISE EXCEPTION '0432 V2: extend_forecast_horizon did not apply a longer horizon: %', r_applied;
  END IF;
  IF COALESCE(r_same->>'status','') <> 'no_change' THEN
    RAISE EXCEPTION '0432 V2: enabling a reserve that is already on did not report no_change: %', r_same;
  END IF;
  IF COALESCE(r_refused->>'status','') <> 'refused' OR COALESCE(r_refused->>'reason','') <> 'not_agent_writable' THEN
    RAISE EXCEPTION '0432 V2: a setter refusal still reads as something else on the ops path: %', r_refused;
  END IF;
  IF (SELECT agent_writable FROM public.ottoq_policy_param_catalog WHERE param_key = 'deploy_surge_catchup') IS NOT TRUE THEN
    RAISE EXCEPTION '0432 V2: the probe''s catalog edit escaped its rollback';
  END IF;
END $v2$;

-- ── V3: THE GROUNDING BLOCK on the newest completed twin demo run -- shape, bounds, and the demand is
--        not offered as an actuator ──
DO $v3$
DECLARE v_run uuid; v_clock timestamptz; v jsonb; t0 timestamptz; v_ms int; k text;
BEGIN
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by NOT IN ('cert_harness','benchmark')
     AND tick_count > 50
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0432 V3: no twin demo run to probe; skipped'; RETURN; END IF;
  t0 := clock_timestamp();
  v := public.ottoq_agent_board_grounding(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
  v_ms := (extract(epoch FROM clock_timestamp() - t0) * 1000)::int;
  FOREACH k IN ARRAY ARRAY['note','queue','resources','energy_limits','flow_last_30m','work_side_demand','stability','actuators'] LOOP
    IF NOT v ? k THEN RAISE EXCEPTION '0432 V3: grounding lacks %', k; END IF;
  END LOOP;
  IF v->'actuators' ? 'deploy_peak_fraction' THEN
    RAISE EXCEPTION '0432 V3: the work side''s demand is still offered to the agent as an actuator';
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(v->'actuators')) <>
     (SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE agent_writable) THEN
    RAISE EXCEPTION '0432 V3: actuators do not match the catalog''s agent_writable set';
  END IF;
  IF (v->'work_side_demand'->>'read_only')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '0432 V3: work_side_demand is not marked read-only';
  END IF;
  IF length(v::text) > 8192 THEN RAISE EXCEPTION '0432 V3: grounding is % bytes -- over the 8 KB budget', length(v::text); END IF;
  IF v_ms > 2000 THEN RAISE EXCEPTION '0432 V3: grounding took % ms on run %', v_ms, v_run; END IF;
  RAISE NOTICE '0432 V3: run % grounding % bytes in % ms', v_run, length(v::text), v_ms;
END $v3$;

-- ── V4: THE BOARD -- off means absent; on means present and agreeing with the engine; and with the
--        agent's own write removed, `policy` reads the scenario's demand, not 0.90 ──
DO $v4$
DECLARE
  v_run uuid; v_scn text; v_scn_pct numeric;
  b_off jsonb; b_on jsonb; b_clean jsonb;
BEGIN
  SELECT sim_run_id, scenario_code INTO v_run, v_scn FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by NOT IN ('cert_harness','benchmark')
     AND tick_count > 50
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0432 V4: no twin demo run to probe; skipped'; RETURN; END IF;
  SELECT (fleet_overrides->>'target_deployed_fraction')::numeric INTO v_scn_pct
    FROM public.ottoq_sim_scenarios WHERE scenario_code = COALESCE(v_scn, 'normal_day') LIMIT 1;
  BEGIN
    DELETE FROM public.ottoq_policy_params
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'agent_board_grounding_enabled';
    b_off := public.ottoq_agent_board(v_run);
    PERFORM public.ottoq_policy_set('run', v_run, 'agent_board_grounding_enabled', 1, 'operator_0432_verify');
    b_on := public.ottoq_agent_board(v_run);
    DELETE FROM public.ottoq_policy_params
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'deploy_peak_fraction';
    b_clean := public.ottoq_agent_board(v_run);
    RAISE EXCEPTION USING MESSAGE = '0432_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0432_probe_rollback' THEN RAISE; END IF;
  END;
  IF b_off ? 'grounding' THEN RAISE EXCEPTION '0432 V4: the gate leaks -- grounding present with the dial off'; END IF;
  IF NOT b_on ? 'grounding' THEN RAISE EXCEPTION '0432 V4: grounding absent with the dial on'; END IF;
  IF (b_on->'policy'->>'deploy_peak_fraction')::numeric
     IS DISTINCT FROM (b_on->'grounding'->'work_side_demand'->>'deploy_peak_fraction_effective')::numeric THEN
    RAISE EXCEPTION '0432 V4: the board''s policy and its grounding disagree on the demand (% vs %)',
      b_on->'policy'->>'deploy_peak_fraction', b_on->'grounding'->'work_side_demand'->>'deploy_peak_fraction_effective';
  END IF;
  IF v_scn_pct IS NOT NULL
     AND (b_clean->'policy'->>'deploy_peak_fraction')::numeric IS DISTINCT FROM v_scn_pct THEN
    RAISE EXCEPTION '0432 V4: with no override the board reads % where the dispatcher reads the scenario''s %',
      b_clean->'policy'->>'deploy_peak_fraction', v_scn_pct;
  END IF;
END $v4$;

-- ── V5: THE ARM -- an armed run now carries both halves, unclamped ──
DO $v5$
DECLARE v_run uuid; v_arm jsonb; v_board jsonb; v_keys text[];
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by NOT IN ('cert_harness','benchmark')
     AND tick_count > 50
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0432 V5: no twin demo run to probe; skipped'; RETURN; END IF;
  BEGIN
    v_arm := public.ottoq_agentic_arm(v_run, 'operator_0432_verify');
    v_board := public.ottoq_agent_board(v_run);
    RAISE EXCEPTION USING MESSAGE = '0432_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0432_probe_rollback' THEN RAISE; END IF;
  END;
  SELECT array_agg(r->>'param' ORDER BY r->>'param') INTO v_keys
    FROM jsonb_array_elements(v_arm->'receipts') r
   WHERE r->>'param' IN ('agent_board_grounding_enabled','agent_asset_depth_enabled')
     AND (r->>'applied')::numeric = 1 AND NOT COALESCE((r->>'clamped')::boolean, false);
  IF v_keys IS DISTINCT FROM ARRAY['agent_asset_depth_enabled','agent_board_grounding_enabled'] THEN
    RAISE EXCEPTION '0432 V5: the arm did not set both halves (got %)', v_keys;
  END IF;
  IF NOT (v_board ? 'grounding' AND v_board ? 'assets' AND v_board ? 'telemetry') THEN
    RAISE EXCEPTION '0432 V5: an armed board lacks grounding/assets/telemetry';
  END IF;
  RAISE NOTICE '0432 V5: armed board % bytes', length(v_board::text);
END $v5$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0432_the_agent_could_rewrite_the_simulated_demand_it_is_measured_against_and_could_not_see_its_own_clamps',
  false,
  'db/checks/0352: on run 0682752c the agent''s board showed deploy_peak_fraction 0.90 while the dispatcher used '
  'busy_day''s 0.45; the agent set 0.95 at tick 1, then asked for 0.35-0.45 on 96 of 106 writes, all clamped to '
  'the 0.50 agent floor, and 71%/68% of its energy-dial changes reversed the previous change. All 312 stored rows '
  'of that dial were agent-written. deploy_peak_fraction is the work side''s demand (rule 6), so it becomes '
  'agent_writable=false (the promoter''s gate 2 then refuses it too); ottoq_policy_set refuses an agent on any '
  'non-writable dial after the policy_write probe (the remedy AI.001 already names); ottoq_apply_ops_action '
  'reports refused/no_change instead of applied; ottoq_agent_board_grounding adds effective values, actuator '
  'envelopes with the agent''s last write and last change, a queue that separates waiting vehicles from '
  'not-yet-due readiness checks, pointer-level resources, energy limits with the DR call, 30-minute flow and '
  'read-only work-side demand; the board''s policy value uses the dispatcher''s default; and ottoq_agentic_arm '
  'now arms grounding and 0350''s asset depth (one run-scoped row in its life before this). FALSE: the board '
  'and the ops action have no in-database caller, 0105 keeps the agent off cert_harness runs, the arm refuses '
  'them by raising, and (B) changes only agent actors'' writes; no atom reads the board.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` FALSE -- no sweep follows. Deploy edge function v19 in the same sitting: until it lands,
-- v18 still offers deploy_peak_fraction as a KNOB, the setter now refuses it, and v18 records that refusal
-- honestly (G65) -- so the gap between apply and deploy costs a rejected action per agent pass, not a
-- wrong write.
--
-- On the first fresh armed run:
--
--   -- no agent write to the demand
--   SELECT count(*) FROM public.ottoq_policy_params
--    WHERE scope_type = 'run' AND scope_id = '<run>' AND param_key = 'deploy_peak_fraction'
--      AND public.ottoq_is_agent_actor(updated_by);                                   -- EXPECT 0
--   -- the agent reads what it now sees
--   SELECT public.ottoq_agent_board('<run>') ? 'grounding', public.ottoq_agent_board('<run>') ? 'assets';  -- t, t
--   -- dither and resend: rerun db/checks/0352 section 3 on <run>; reversals and unchanged_resend should fall.
--
-- Rollback, per piece: (A) `UPDATE ottoq_policy_param_catalog SET agent_writable = true WHERE param_key =
-- 'deploy_peak_fraction'` (B/C/E/G) restore from `ottoq_schema_snapshots` label '0432_pre'. The grounding
-- block alone: `SELECT ottoq_policy_set('global', NULL, 'agent_board_grounding_enabled', 0, 'operator')` does
-- NOT turn it off on an armed run (run scope wins); set it per run instead.
