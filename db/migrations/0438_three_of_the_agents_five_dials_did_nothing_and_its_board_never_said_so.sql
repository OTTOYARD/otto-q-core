-- migration-version: 20260923012821
-- migration-name:    three_of_the_agents_five_dials_did_nothing_and_its_board_never_said_so
--
-- 0438  **Three of the orchestrator agent's five dials did nothing, and its board never said so.** Two have no reader
--       anywhere in the engine. The other two stop mattering as soon as the agent flips the fifth, and the agent
--       flips it on every armed run. FINDINGS G174, G175. Ships with edge function v20.
--
-- ══ §1 WHAT IS WRONG ═════════════════════════════════════════════════════════
--
--   (a) NO READER (G175). A comment-stripped search of every function in public, twin and ottoq, plus every code
--       repo (otto-q-core, ottoq-intelligence, ottoyarddepot-sim), finds `deploy_surge_catchup` and
--       `forecast_horizon_min` in two places only: `ottoq_apply_ops_action`, which sets them, and the agent,
--       which asks for them. The catalog's `affects` column claims "auto_dispatch catch-up" and "predict_arrivals
--       + energy pre-position". The dispatcher paces release with `deploy_release_per_tick_cap`, and the energy
--       orchestrator calls `ottoq_predict_arrivals(..., 60)` with a literal 60.
--       On run `7a42982a` the agent drove the first from 0.455 to 1.0 and the second from 39 to 75, and v19's
--       holds refused 14 further moves on them. None of it changed anything.
--   (b) DEAD BY MODE (G174). With `energy_reserve_shave` on, `ottoq_energy_orchestrate` replaces the target built
--       from `energy_demand_factor_peak` / `_expensive` with the reserve target (the water-fill, and the day plan
--       after 0435). The factors survive only if both of those return nothing. The agent turned the switch on at
--       23:32 UTC on `7a42982a` (`ottoq_prime` holds 273 of 273 run-scope rows of it, every one 1), then wrote
--       the factors 21 times on this run, and 231 times on `0682752c`.
--   (c) THE BOARD WAS SILENT ABOUT BOTH. `ottoq_agent_board_grounding`'s actuator block publishes each dial's
--       value, envelope, writes and last change, but not whether the dial does anything.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   1. The two inert dials become `agent_writable = false`. The setter then refuses them for any agent actor
--      (0432 B), the promoter's gate 2 refuses them, and they drop out of the grounding's actuator block, which
--      lists writable dials only. Edge function v20 rejects them before the setter, with a reason, and never
--      queues them for a human.
--   2. `public.ottoq_dial_liveness(run, key)` returns `{live, why}`, and every actuator in the grounding carries
--      it. The one rule declared today is the reserve switch deadening the two factors. Every other dial
--      reads `live: true`, with a `why` saying no liveness rule is declared: an unknown is not a claim.
--   3. The energy block carries `battery_plan`: the day plan's scalar summary (0435) from the latest BESS
--      command of this run, i.e. exactly what the orchestrator acted on.
--   4. 0434's `deploy_gap_note` told the agent that `deploy_surge_catchup` "releases a share of a POSITIVE gap
--      per tick". That is G164's reading, and G175 retracts it: nothing reads the dial. The note now names what
--      does close the gap, `deploy_release_per_tick_cap`, which is not an agent dial. Found by this file's own
--      P2 at dry run, applied after 0434: the grounding had become the one other function naming the dial.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════
--
--   - Nothing in the database calls the grounding function except the agent's board. 0432 §3 applies here
--     unchanged: the agent never fires on cert runs, and `ottoq_agentic_arm` refuses them.
--   - The two catalog flags affect only agent writes, and nothing reads those dials either way.
--
-- ══ §4 WHAT THIS DOES NOT DO ═══════════════════════════════════════════════════
--
--   - The two dials are not wired to anything. Whether the agent should get a real release-pacing lever
--     (`deploy_release_per_tick_cap`) or a real DR-reserve lever (`bess_plan_dr_reserve_kwh`) is a product
--     decision. It needs the learning loop (G161) to show that a lever pays before it is handed over.
--   - Liveness rules are declared by hand, one at a time. A rule this function does not know about reads as
--     live, and says that no rule is declared.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0438 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0438 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0438 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guard (the grounding as 0433 and 0434 left it) and unique anchors ──
DO $$
DECLARE v_src text; v_n int; v_a text; v_i int := 0;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';
  IF md5(v_src) <> 'e09f7049c6d225bf60c53e5f32cc6b44' THEN
    RAISE EXCEPTION '0438 P1: ottoq_agent_board_grounding md5 is % -- apply 0433 and 0434 first, or it changed since', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
    E'               ''clamped'', COALESCE(s.clamped, 0),\n',
    E'                 FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1),\n'
  ] LOOP
    v_i := v_i + 1;
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0438 P1: grounding anchor % matched % times', v_i, v_n; END IF;
  END LOOP;
END $$;

-- ── P2: the premise, re-proved at apply time: nothing but the setter reads the two dials ──
--   The grounding is excluded from the search and checked on its own, because 0434 gave it a NOTE that names
--   deploy_surge_catchup -- in a string, not a read -- and that note asserts exactly the semantics G175 retracts
--   ("releases a share of a POSITIVE gap per tick"). (3) replaces it; V3 then re-runs the full search.
DO $$
DECLARE v_readers text; v_src text; v_note text :=
  E'      ''deploy_gap_note'', ''target minus deployed. deploy_surge_catchup releases a share of a POSITIVE gap per tick; ''\n'
  || E'                         ''at a gap of 0 or less it does nothing.'',\n';
BEGIN
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.proname NOT IN ('ottoq_apply_ops_action', 'ottoq_agent_board_grounding')
     AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '(deploy_surge_catchup|forecast_horizon_min)';
  IF v_readers IS NOT NULL THEN
    RAISE EXCEPTION '0438 P2: % now mention(s) the dials -- they may no longer be inert; re-read before applying', v_readers;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';
  IF (length(v_src) - length(replace(v_src, v_note, ''))) / length(v_note) <> 1
     OR regexp_replace(replace(v_src, v_note, ''), '--[^\n]*', '', 'g') ~ '(deploy_surge_catchup|forecast_horizon_min)' THEN
    RAISE EXCEPTION '0438 P2: the grounding names an inert dial somewhere other than 0434''s deploy_gap_note';
  END IF;
  -- and the reserve switch still overrides the factor target (the rule ottoq_dial_liveness declares)
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate'
                    AND p.prosrc LIKE '%IF ottoq_policy_get(p_sim_run_id, ''energy_reserve_shave'', 0) >= 0.5 THEN%'
                    AND p.prosrc LIKE '%v_demand_target := v_service_max * (CASE WHEN v_expensive THEN ottoq_policy_get(p_sim_run_id,''energy_demand_factor_expensive''%') THEN
    RAISE EXCEPTION '0438 P2: the orchestrator no longer has the factor target / reserve override shape the liveness rule describes';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0438_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';

-- ── (1) THE TWO INERT DIALS ──
UPDATE public.ottoq_policy_param_catalog
   SET agent_writable = false,
       description = description || ' 0438 (G175): NO ENGINE FUNCTION READS THIS DIAL; agent_writable = false.'
 WHERE param_key IN ('deploy_surge_catchup', 'forecast_horizon_min') AND agent_writable;

-- ── (2) LIVENESS ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_liveness(p_sim_run_id uuid, p_param_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  /* 0438 (G174): whether an agent dial does anything RIGHT NOW, and why not. Rules are declared one at a time
     against the source they describe (0438 P2 re-checks the one below at apply time). A dial with no declared
     rule reads live, and says that no rule is declared. */
  SELECT CASE
    WHEN p_param_key IN ('energy_demand_factor_peak', 'energy_demand_factor_expensive')
     AND public.ottoq_policy_get(p_sim_run_id, 'energy_reserve_shave', 0) >= 0.5
      THEN jsonb_build_object('live', false,
             'why', 'energy_reserve_shave is on: the battery''s reserve target (the day plan, 0435) replaces the '
                    'target this factor builds; it applies only when energy_reserve_shave is 0')
    WHEN p_param_key IN ('energy_demand_factor_peak', 'energy_demand_factor_expensive', 'energy_reserve_shave')
      THEN jsonb_build_object('live', true)
    ELSE jsonb_build_object('live', true, 'why', 'no liveness rule is declared for this dial')
  END
$function$;
REVOKE ALL ON FUNCTION public.ottoq_dial_liveness(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_dial_liveness(uuid, text) TO authenticated, service_role;

-- ── (3) THE GROUNDING CARRIES LIVENESS AND THE BATTERY'S PLAN ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';
  v_new := replace(v_def,
    E'               ''clamped'', COALESCE(s.clamped, 0),\n',
    E'               ''clamped'', COALESCE(s.clamped, 0),\n'
    || E'               ''live'', public.ottoq_dial_liveness(p_sim_run_id, c.param_key),   /* 0438 (G174) */\n');
  v_new := replace(v_new,
    E'                 FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1),\n',
    E'                 FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1),\n'
    || E'      /* 0438: the day plan''s scalars (0435) exactly as the orchestrator last acted on them; null when no plan ran */\n'
    || E'      ''battery_plan'', (SELECT ec.reason->''day_plan'' FROM ottoq_energy_commands ec\n'
    || E'                        WHERE ec.sim_run_id = p_sim_run_id AND ec.depot_id = p_depot_id\n'
    || E'                          AND ec.command_type = ''bess_setpoint_kw'' AND ec.issued_at <= p_clock\n'
    || E'                        ORDER BY ec.issued_at DESC, ec.tick_seq DESC NULLS LAST LIMIT 1),\n');
  -- 0434's note told the agent the surge dial acts on a positive gap; nothing reads that dial (G175)
  v_new := replace(v_new,
    E'      ''deploy_gap_note'', ''target minus deployed. deploy_surge_catchup releases a share of a POSITIVE gap per tick; ''\n'
    || E'                         ''at a gap of 0 or less it does nothing.'',\n',
    E'      ''deploy_gap_note'', ''target minus deployed: read-only work-side demand. The dispatcher closes a positive gap at ''\n'
    || E'                         ''deploy_release_per_tick_cap per tick, which is not an agent dial; no agent dial moves this number (0438).'',\n');
  IF v_new = v_def OR position('battery_plan' IN v_new) = 0 OR position('ottoq_dial_liveness' IN v_new) = 0
     OR position('deploy_surge_catchup releases' IN v_new) > 0 THEN
    RAISE EXCEPTION '0438 (3): a splice did not apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: the inert dials are gone from the agent's reach, and the setter refuses them ──
DO $$
DECLARE v_run uuid; v_res jsonb; v_ok boolean := false; v_msg text := '';
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('deploy_surge_catchup', 'forecast_horizon_min') AND agent_writable) THEN
    RAISE EXCEPTION '0438 V1: an inert dial is still agent-writable';
  END IF;
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1;
  BEGIN
    v_res := public.ottoq_policy_set('run', v_run, 'deploy_surge_catchup', 0.5, 'ottoq_prime');
    IF COALESCE((v_res->>'ok')::boolean, true) OR v_res->>'error' <> 'not_agent_writable' THEN
      v_msg := format(' the setter answered %s;', v_res);
    END IF;
    v_ok := (v_msg = '');
    RAISE EXCEPTION USING MESSAGE = '0438_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0438_probe_rollback' THEN RAISE; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION '0438 V1:%', v_msg; END IF;
END $$;

-- ── V2: liveness answers as declared, and the grounding carries it and the plan ──
DO $$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz; v_g jsonb; v_ok boolean := false; v_msg text := '';
BEGIN
  SELECT sim_run_id, depot_id, COALESCE(sim_clock_current, sim_clock_start) INTO v_run, v_depot, v_clock
    FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1;
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'energy_reserve_shave';
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'energy_reserve_shave', 1, '0438_probe');
    IF (public.ottoq_dial_liveness(v_run, 'energy_demand_factor_peak')->>'live')::boolean IS DISTINCT FROM false
    OR (public.ottoq_dial_liveness(v_run, 'energy_reserve_shave')->>'live')::boolean IS DISTINCT FROM true THEN
      v_msg := v_msg || ' liveness with the switch on is wrong;';
    END IF;
    UPDATE public.ottoq_policy_params SET param_value = 0
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'energy_reserve_shave';
    IF (public.ottoq_dial_liveness(v_run, 'energy_demand_factor_peak')->>'live')::boolean IS DISTINCT FROM true THEN
      v_msg := v_msg || ' liveness with the switch off is wrong;';
    END IF;
    v_g := public.ottoq_agent_board_grounding(v_run, v_depot, v_clock);
    IF NOT (v_g->'energy_limits' ? 'battery_plan') THEN v_msg := v_msg || ' no battery_plan key;'; END IF;
    IF (v_g->'actuators'->'energy_demand_factor_peak'->'live') IS NULL THEN v_msg := v_msg || ' no live on the actuators;'; END IF;
    IF v_g->'actuators' ? 'deploy_surge_catchup' OR v_g->'actuators' ? 'forecast_horizon_min' THEN
      v_msg := v_msg || ' an inert dial is still listed as an actuator;';
    END IF;
    v_ok := (v_msg = '');
    RAISE EXCEPTION USING MESSAGE = '0438_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0438_probe_rollback' THEN RAISE; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION '0438 V2:%', v_msg; END IF;
END $$;

-- ── V3: P2's premise, now with no exclusion but the setter: nothing in the engine names either dial ──
DO $$
DECLARE v_readers text;
BEGIN
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.proname <> 'ottoq_apply_ops_action'
     AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '(deploy_surge_catchup|forecast_horizon_min)';
  IF v_readers IS NOT NULL THEN
    RAISE EXCEPTION '0438 V3: % still name(s) an inert dial after the splice', v_readers;
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0438_three_of_the_agents_five_dials_did_nothing_and_its_board_never_said_so',
   false,
   'deploy_surge_catchup / forecast_horizon_min agent_writable=false (no reader, G175); grounding actuators carry '
   'ottoq_dial_liveness and energy_limits carries battery_plan (G174). Only the agent board reads the grounding.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. Deploy edge function v20 in the same window: it rejects the two dials and their ops actions
-- with a reason (INERT_KEYS / INERT_OPS in _shared/agent_dial_discipline.ts), and its prompt reads `live`.
-- Rollback: UPDATE ottoq_policy_param_catalog SET agent_writable = true WHERE param_key IN (...), and restore the
-- grounding from ottoq_schema_snapshots label '0438_pre'.
