-- migration-version: 20260927230739
-- migration-name:    every_result_the_learner_reaches_is_a_recommendation_a_person_ships
--
-- 0540  **A dial experiment's win is a recommendation a person reviews and ships. The engine never applies it itself.**
--
-- ══ §1 WHY (CLAUDE.md rule 10; Chase, 2026-09-27) ═════════════════════════════════════════════════════════════════════
--
--   Rule 10: production OTTO-Q "never changes its own rules or settings"; a research result "is a recommendation that is
--   reviewed and shipped as a certified change". One open decision under it was whether to turn automatic dial
--   promotion off. Chase, 5:00 PM CT: "No input on your other three questions ... They both serve a purpose. One will be
--   actual production and one is our research fortification and data set or world benchmark for testing against. They
--   should both be leveraged accordingly." The call was left to us, and it is made here: off.
--
--   Measured before this file (2026-09-27 22:45 UTC). `dial_promotion_enabled` = 1 (global, set by 0404). The runner
--   (`ottoq_dial_experiment_runner`, cron 755) calls `ottoq_promote_dial_experiment` on every terminal verdict, and a
--   win on an agent-writable dial is ENACTED through the setter at depot scope. It happened once:
--   `energy_reserve_shave` 0 -> 1 at the twin depot on 2026-09-26 (promotions 9 and 11). Experiment `82c5568b` is active
--   tonight on that same agent-writable dial, so a win would apply itself before morning. With the switch off, the
--   promoter wrote outcome `refused` (`gate1_dial_promotion_enabled_is_off`), which reads as a rejected win rather than
--   one handed to a person.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_promote_dial_experiment`: with promotion off, a win is `recommended`, carrying the treatment value, the
--       same outcome a non-agent-writable dial's win already takes. Every other branch is unchanged: a moved incumbent
--       is still `refused`, a loss or tie still `concluded`, and with the switch on the gates run as before.
--   (b) `dial_promotion_enabled` goes to 0 (global row and catalog default), so every win from tonight is recommended.
--   `ottoq_promote_dials` (0404, no caller) already refuses at the same switch.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   The promoter runs after a verdict and no arm reads the switch, so no certified path and no pair changes.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0540 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the promoter is 0439's as measured (2026-09-27 22:45 UTC), and the switch is on ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_promote_dial_experiment(uuid,boolean)'::regprocedure)
       <> 'f972ec15d93632887c9ce31930ab4924' THEN
    RAISE EXCEPTION '0540 P2: ottoq_promote_dial_experiment is not the function measured';
  END IF;
  IF COALESCE(public.ottoq_policy_get(NULL, 'dial_promotion_enabled', 0), 0) <> 1 THEN
    RAISE EXCEPTION '0540 P2: automatic promotion is not on';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0540_pre', 'function', 'public', 'ottoq_promote_dial_experiment',
       pg_get_functiondef('public.ottoq_promote_dial_experiment(uuid,boolean)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_promote_dial_experiment(uuid,boolean)'::regprocedure));

-- ── (a) with promotion off, a win is recommended ──
DO $patch$
DECLARE v_def text; v_old text; v_new text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_promote_dial_experiment(uuid,boolean)'::regprocedure);
  v_old := $a$    v_outcome := 'refused'; v_reason := 'gate1_dial_promotion_enabled_is_off';$a$;
  v_new := $b$    -- 0540 (CLAUDE.md rule 10): with promotion off, a win is a RECOMMENDATION that a person reviews and ships as a
    -- certified change. It read 'refused', which said the win was rejected rather than handed to a person.
    v_outcome := 'recommended'; v_to := x.treatment_value;
    v_reason := 'rule_10_a_person_ships_it: automatic promotion is off, so a person reviews the win and applies it '
                || 'with ottoq_policy_set at depot scope, as a certified change';$b$;
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0540 (a): the switch-off branch matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ── (b) the switch goes off ──
DO $switch$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_policy_set('global', NULL, 'dial_promotion_enabled', 0, '0540_rule_10_a_person_ships_it');
  IF NOT COALESCE((v->>'ok')::boolean, false) OR (v->>'applied')::numeric IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION '0540 (b): the switch did not go to 0: %', v;
  END IF;
END $switch$;
UPDATE public.ottoq_policy_param_catalog
   SET default_value = 0,
       description = description || ' 0540 (CLAUDE.md rule 10): OFF, default 0. Every win is recommended and a person '
                                 || 'ships it as a certified change; the engine never applies its own result.'
 WHERE param_key = 'dial_promotion_enabled';

-- ── V1 (comment-stripped) ──
DO $verify$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_promote_dial_experiment(uuid,boolean)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF position('gate1_dial_promotion_enabled_is_off' IN v_src) > 0
     OR position($s$v_outcome := 'recommended'; v_to := x.treatment_value;$s$ IN v_src) = 0
     OR position('rule_10_a_person_ships_it' IN v_src) = 0 THEN
    RAISE EXCEPTION '0540 V1: the promoter does not recommend a win with the switch off';
  END IF;
  IF COALESCE(public.ottoq_policy_get(NULL, 'dial_promotion_enabled', 1), 1) <> 0
     OR (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'dial_promotion_enabled') <> 0 THEN
    RAISE EXCEPTION '0540 V1: automatic promotion is not off';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0540_every_result_the_learner_reaches_is_a_recommendation_a_person_ships', false, false,
  'Rule 10: automatic dial promotion is off, and with it off a win is recommended (a person ships it as a certified '
  'change) instead of refused. The promoter runs after a verdict and no arm reads the switch.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back: an experiment on an agent-writable dial (energy_reserve_shave), at a depot that does not exist, with
-- six planted pairs the treatment wins. With the switch off the promoter's dry run recommends the treatment value; with
-- it on, the same verdict is enacted. So the switch alone decides, and off means recommended.
DO $v3$
DECLARE
  v_msg text; v_x uuid; v_depot uuid := '00000000-0000-4000-8000-000000000540'; v_inc numeric; v jsonb;
  v_off jsonb; v_on jsonb;
BEGIN
  BEGIN
    SELECT COALESCE((SELECT pp.param_value FROM public.ottoq_policy_params pp
                      WHERE pp.param_key = 'energy_reserve_shave' AND pp.scope_type = 'global'),
                    (SELECT c.default_value FROM public.ottoq_policy_param_catalog c WHERE c.param_key = 'energy_reserve_shave'))
      INTO v_inc;
    INSERT INTO public.ottoq_dial_experiments
      (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks, sim_start,
       primary_metric, primary_better, hypothesis)
    VALUES ('0540_v3', v_depot, 'energy_reserve_shave', v_inc, 1 - v_inc, 'busy_day', 48, '2026-09-01 13:00:00+00',
            'site_cost_usd_per_day', 'lower', '0540 V3 probe')
    RETURNING experiment_id INTO v_x;
    INSERT INTO public.ottoq_dial_pair_ledger
      (experiment_id, seed, engine_hash, run_a, run_b, ab_group_id, complete, world_identical, both_paid_shield,
       differs, moved, metrics_a, metrics_b, delta, dial_read_a, dial_read_b)
    SELECT v_x, s, public.ottoq_engine_hash(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
           true, true, true, true, '["h_nrg"]'::jsonb,
           jsonb_build_object('site_cost_usd_per_day', 1000, 'returns_unserved', 0, 'safety_critical_unprevented', 0,
                              'safety_critical_refused', 0, 'asset_hours_available_per_day', 100,
                              'service_point_turns_per_point_per_day', 10, 'peak_site_kw', 1500,
                              'touch_events_per_turn', 1, 'p95_time_to_service_min', 30, 'unmet_demand_car_hours', 100),
           jsonb_build_object('site_cost_usd_per_day', 950 - s, 'returns_unserved', 0, 'safety_critical_unprevented', 0,
                              'safety_critical_refused', 0, 'asset_hours_available_per_day', 100,
                              'service_point_turns_per_point_per_day', 10, 'peak_site_kw', 1500,
                              'touch_events_per_turn', 1, 'p95_time_to_service_min', 30, 'unmet_demand_car_hours', 100),
           '{}'::jsonb, true, true
      FROM generate_series(1, 6) AS s;
    v := public.ottoq_dial_experiment_verdict(v_x);
    IF v->>'outcome' IS DISTINCT FROM 'treatment_wins' THEN
      RAISE EXCEPTION '0540 V3 FAILED: six planted winning pairs read % (%)', v->>'outcome', v->>'why';
    END IF;
    v_off := public.ottoq_promote_dial_experiment(v_x, true);
    PERFORM public.ottoq_policy_set('global', NULL, 'dial_promotion_enabled', 1, '0540_v3');
    v_on := public.ottoq_promote_dial_experiment(v_x, true);
    IF v_off->>'outcome' IS DISTINCT FROM 'recommended' OR (v_off->>'to')::numeric IS DISTINCT FROM 1 - v_inc
       OR v_on->>'outcome' IS DISTINCT FROM 'enacted' THEN
      RAISE EXCEPTION '0540 V3 FAILED: with the switch off the win reads % (to %, %); on, it reads % (%)',
        v_off->>'outcome', v_off->>'to', v_off->>'reason', v_on->>'outcome', v_on->>'reason';
    END IF;
    RAISE EXCEPTION '0540 V3 PASSED: a planted win on energy_reserve_shave (% -> %) is % with the switch off and % with it on',
      v_inc, 1 - v_inc, v_off->>'outcome', v_on->>'outcome';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0540 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0540 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0540_pre'; set dial_promotion_enabled back
--   to 1 (global row and catalog default) and strip the 0540 sentence from its catalog description.
COMMIT;
