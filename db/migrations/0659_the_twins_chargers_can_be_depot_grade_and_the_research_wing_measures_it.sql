-- migration-version: 20261010110931
-- migration-name:    the_twins_chargers_can_be_depot_grade_and_the_research_wing_measures_it
--
-- 0659  **The twin's chargers can be depot-grade, up more than 97% of the time, and the research wing measures what
--        that changes before it becomes the base case.** (Part A of the twin data contract review, 2026-10-08. Chase,
--        2026-10-09 CT: depot-grade charger faults as the base, today's as the stress case, an evidence regime, and a
--        before/after pair.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   A charger fault in the twin is a fitted model (public.ottoq_twin_deal_fault_card, feed plan charger_fault_repair
--   v3): a per-session fault chance (base 0.065) scaled by each charger's own MTBF from the charger_reliability corpus
--   (days_between_faults) and by heat, and a repair time from the corpus's repair_days. The plan already declares two
--   depot discounts over the public-network data: a session fails 4x less often than the corpus's 0.20, and a repair
--   takes 2% of the corpus's truck-roll days (its provenance, depot_grade_fault_discount and depot_staffed_factor).
--
--   Measured 2026-10-10 on the twin depot, 60 runs of the last 7 days, each 4 to 24 sim-hours, every fault's own
--   repair minutes against 45 chargers over each run's sim span (db/checks/0432 (5)): 1,254 faults in 16,519 sessions
--   (7.6%), mean repair 104 minutes, median 61; **charger uptime 93.7% pooled, 89.0% at the 10th-percentile run, 86.9%
--   at the worst**. A public charger built with federal money must be up more than 97% of the time (23 CFR
--   680.116(b), "an average annual uptime of greater than 97%", https://www.law.cornell.edu/cfr/text/23/680.116, read
--   2026-10-10). A fleet's own maintained depot is held to at least that floor here: depot-grade means more than 97%.
--   No depot-grade fault dataset is public, so the depot-grade profile is calibrated to that target on the twin's own
--   measurement, not fitted, and says so.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) A dial, twin_charger_fault_regime: 0 (unset everywhere, as today) = the fault profile above, kept as the stress
--       case; 1 = depot-grade. A person's dial, never the agent's.
--   (b) A feed plan, charger_fault_depot_grade v1: session_fault_p_scale 0.40. Charger time lost scales with the
--       number of faults, and the per-session chance is the lever that moves it without touching the corpus's shape:
--       6.3% lost x 0.40 = 2.5%, about 97.5% uptime, with room for the summer heat the scenario starts in. Repairs keep
--       today's depot-staffed times, which the plan already declares 50x faster than the corpus's truck rolls.
--   (c) public.ottoq_twin_deal_fault_card reads the dial: at 1 it scales the session fault chance by the plan's scale
--       before the plan's clamps, and its card records regime depot_grade and the scale. At 0 nothing it computes
--       changes, and its card is byte for byte what it was (V1).
--   (d) The research wing's before/after pair, registered as a dial experiment (as 0656): control 0, treatment 1,
--       busy_day at the twin depot, 90 ticks of 6 sim-minutes from 8:00 AM CT; primary deployed_car_hours, higher.
--
--   After the pair, a person makes depot-grade the base (a global row of the dial at 1) in a file that records the
--   change in ottoq_evidence_regimes, since the futures learn the fault rate from what the twin shows them (G364).
--   That file forces a recertification; this one does not.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ════════════════════════════════════════════════════════════
--
--   The dial is set nowhere, and at 0 the fault card computes and records exactly what it did (V1 compares the card of
--   one real session before and after the patch, byte for byte). The new plan row is read only at 1, and no
--   fingerprint reads ottoq_feed_plans (ottoq_calibration_fingerprint reads the corpus only).
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0659_pre'; set the feed plan
--   charger_fault_depot_grade v1 to superseded; mark the experiment created_by '0659' abandoned with a verdict whose
--   outcome is 'withdrawn'; leave the catalogued dial (nothing reads it once the function is restored).

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0659 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0658_the_public_key_reads_only_what_a_cockpit_shows') THEN
    RAISE EXCEPTION '0659 P1: 0658 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_twin_deal_fault_card(uuid,uuid,numeric,numeric,timestamptz,integer,bigint)'::regprocedure))
       <> '149ad615ecfe8949758eab7884a8c357' THEN
    RAISE EXCEPTION '0659 P1: public.ottoq_twin_deal_fault_card is not the definition this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_charger_fault_regime')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_charger_fault_regime')
     OR EXISTS (SELECT 1 FROM public.ottoq_dial_experiments WHERE param_key = 'twin_charger_fault_regime') THEN
    RAISE EXCEPTION '0659 P1: twin_charger_fault_regime exists already';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_feed_plans WHERE var_key = 'charger_fault_depot_grade') THEN
    RAISE EXCEPTION '0659 P1: a charger_fault_depot_grade feed plan exists already';
  END IF;
  IF (SELECT plan ->> 'base_session_fault_p' FROM public.ottoq_feed_plans
       WHERE var_key = 'charger_fault_repair' AND status = 'active' ORDER BY version DESC LIMIT 1) IS DISTINCT FROM '0.065' THEN
    RAISE EXCEPTION '0659 P1: the active charger_fault_repair plan is not the v3 this file measured (base 0.065)';
  END IF;
  -- no "no live run" premise: with the dial set nowhere a live run deals the same cards before and after (V1)
END $premises$;

-- ── snapshot: the definition as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0659_pre', 'function', 'public', 'ottoq_twin_deal_fault_card(uuid,uuid,numeric,numeric,timestamptz,integer,bigint)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('public.ottoq_twin_deal_fault_card(uuid,uuid,numeric,numeric,timestamptz,integer,bigint)'::regprocedure) AS def) d;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('twin_charger_fault_regime',
        '0659: how often the twin''s chargers fault. 0 (unset, as before) = the fault profile of feed plan '
        'charger_fault_repair, kept as the stress case (measured 93.7% charger uptime on the twin depot, 2026-10-10). '
        '1 = depot-grade: the session fault chance scaled by feed plan charger_fault_depot_grade so a port is up more '
        'than 97% of the time, the federal floor for a public charger (23 CFR 680.116(b)). A person''s dial, never the '
        'agent''s.',
        0, 0, 1, 'public.ottoq_twin_deal_fault_card (0659)', false);

-- ── (b) the depot-grade plan ──
INSERT INTO public.ottoq_feed_plans (var_key, version, status, method, plan, provenance, authored_by, rationale)
VALUES ('charger_fault_depot_grade', 1, 'active', 'policy',
        jsonb_build_object('session_fault_p_scale', 0.40, 'target_port_uptime_pct', 97, 'applies_to', 'charger_fault_repair'),
        jsonb_build_object(
          'source_type', 'target_calibrated',
          'standard', jsonb_build_object(
            'citation', '23 CFR 680.116(b): each charging port must have an average annual uptime of greater than 97%',
            'url', 'https://www.law.cornell.edu/cfr/text/23/680.116', 'read', '2026-10-10',
            'note', 'eCFR refused an automated read on 2026-10-10; the Cornell LII copy was read'),
          'measured_before', jsonb_build_object(
            'depot', '11111111-1111-1111-1111-111111111111', 'measured', '2026-10-10', 'runs', 60,
            'faults', 1254, 'sessions', 16519, 'mean_repair_min', 103.5, 'median_repair_min', 61.0,
            'uptime_pooled', 0.9370, 'uptime_p10_run', 0.8900, 'uptime_worst_run', 0.8693,
            'method', 'db/checks/0432 (5): sum of each fault''s repair minutes against 45 chargers over each run''s sim span'),
          'declared_assumptions', jsonb_build_array(jsonb_build_object(
            'name', 'session_fault_p_scale', 'value', 0.40,
            'why', 'charger time lost scales with the number of faults; 6.3% lost x 0.40 = 2.5%, about 97.5% uptime, '
                   'margin for summer heat. No depot-grade fault dataset is public, so this is calibrated to the '
                   'standard on the twin''s own measurement, not fitted. Repairs keep the depot-staffed times '
                   'charger_fault_repair already declares.'))),
        '0659',
        'Depot-grade chargers as the twin''s base case once a before/after pair has measured them (Chase, 2026-10-09).');

-- ── (c) the fault card reads the dial ──
DO $p_card$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_twin_deal_fault_card(uuid,uuid,numeric,numeric,timestamptz,integer,bigint)'::regprocedure);
  a text[] := ARRAY[
$a01$  v_scope text;   /* 0058: run-stable draw scope; session_id stays the ledger key */
$a01$,
$a02$  v_p := v_base_fault * v_mult * (1 + v_heat * 1.5) * v_hazard;
$a02$,
$a03$    'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'charger_fault_repair.v1' END);
$a03$];
  b text[] := ARRAY[
$b01$  v_scope text;   /* 0058: run-stable draw scope; session_id stays the ledger key */
  v_depot jsonb;  /* 0659: the depot-grade plan, read only when the run's dial asks for it */
$b01$,
$b02$  v_p := v_base_fault * v_mult * (1 + v_heat * 1.5) * v_hazard;
  /* 0659: depot-grade chargers (twin_charger_fault_regime 1) fault less often, scaled so a port is up more than 97%
     of the time (23 CFR 680.116(b)); the plan's clamps below still apply. Unset (0), nothing here changes. */
  IF ottoq_policy_get(p_run_id, 'twin_charger_fault_regime', 0) >= 1 THEN
    v_depot := ottoq_feed_plan('charger_fault_depot_grade');
    v_p := v_p * COALESCE((v_depot->>'session_fault_p_scale')::numeric, 1);
  END IF;
$b02$,
$b03$    'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'charger_fault_repair.v1' END)
    || CASE WHEN v_depot IS NULL THEN '{}'::jsonb
            ELSE jsonb_build_object('regime', 'depot_grade', 'session_fault_p_scale', (v_depot->>'session_fault_p_scale')::numeric) END;
$b03$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '149ad615ecfe8949758eab7884a8c357' THEN
    RAISE EXCEPTION '0659: the fault card is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0659: anchor % of the fault card occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '8a5c3867256504ea2dcbe693e0be07d4' THEN
    RAISE EXCEPTION '0659: the fault card, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_twin_deal_fault_card(uuid,uuid,numeric,numeric,timestamptz,integer,bigint)'::regprocedure))
       <> '8a5c3867256504ea2dcbe693e0be07d4' THEN
    RAISE EXCEPTION '0659: the fault card did not read back as written';
  END IF;
END $p_card$;

-- ── (d) the research wing's before/after pair ──
INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES
 ('0659', '11111111-1111-1111-1111-111111111111', 'twin_charger_fault_regime', 0, 1,
  '{}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher',
  6, 12, 0.05, 2, 0.5, 0.2,
  'A measurement before a base case changes (0659 §2). With twin_charger_fault_regime at 1 the twin''s chargers fault '
  '0.40 as often, depot-grade: up more than 97% of the time where today''s profile measured 93.7%. The pair shows how '
  'much of the depot''s day a charger fault costs today: fleet hours, turnaround, the wait for a charger, energy. The '
  'base case is changed by a person as a certified change whatever the arms show, with an evidence regime recorded; no '
  'verdict here is a recommendation. Nothing changes a charge target or a service (rule 9). Arms at 6 sim-minutes a '
  'tick from 8:00 AM CT for 90 ticks, the shipped defaults in both.',
  'active', 6, NULL);

-- ── V1: one real session's fault card, before and after, and at the depot-grade dial (each in a rolled-back block) ──
CREATE TEMP TABLE p0659 (phase text PRIMARY KEY, meta jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0659_card(p_phase text, p_dial numeric) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  c record; v_meta jsonb; v_msg text;
BEGIN
  -- a session of a stopped twin run whose card did not hit a clamp, so a scale shows
  SELECT vc.sim_run_id, vc.scope_instance::uuid AS session_id, vc.drawn_at_clock, vc.drawn_at_tick,
         (vc.meta ->> 'soc_start')::numeric AS soc_start
    INTO c
    FROM public.ottoq_variability_cards vc
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = vc.sim_run_id
    JOIN public.ocpp_sessions s ON s.id = vc.scope_instance::uuid
   WHERE vc.var_key = 'charger_fault' AND r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status <> 'running'
     AND (vc.meta ->> 'plan') = 'charger_fault_repair.v1'
     AND (vc.meta ->> 'session_fault_p')::numeric BETWEEN 0.02 AND 0.5
   ORDER BY vc.drawn_at_clock DESC, vc.scope_instance LIMIT 1;
  IF c.session_id IS NULL THEN RAISE EXCEPTION '0659 V1: no twin session with an unclamped fault card'; END IF;
  BEGIN
    DELETE FROM public.ottoq_variability_cards
     WHERE sim_run_id = c.sim_run_id AND var_key = 'charger_fault' AND scope_instance = c.session_id::text;
    IF p_dial IS NOT NULL THEN
      INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
      VALUES ('run', c.sim_run_id, 'twin_charger_fault_regime', p_dial, '0659_probe', now());
    END IF;
    v_meta := public.ottoq_twin_deal_fault_card(c.sim_run_id, c.session_id, c.soc_start, 100, c.drawn_at_clock,
                (c.drawn_at_clock::date - DATE '2020-01-01'), c.drawn_at_tick);
    RAISE EXCEPTION '0659 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0659 PROBED' THEN RAISE EXCEPTION '0659 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0659 VALUES (p_phase, v_meta);
END $fn$;

DO $v1$
DECLARE
  v_b jsonb; v_a jsonb; v_d jsonb;
BEGIN
  -- the card the patched function deals with the dial unset, at 0 and at 1, for the same session and inputs
  PERFORM pg_temp.p0659_card('after_unset', NULL);
  PERFORM pg_temp.p0659_card('after_zero', 0);
  PERFORM pg_temp.p0659_card('after_depot', 1);
  -- and the card the function dealt before this file, as kept in the snapshot, run under its old name
  EXECUTE replace((SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0659_pre'),
                  'FUNCTION public.ottoq_twin_deal_fault_card(', 'FUNCTION pg_temp.ottoq_twin_deal_fault_card_0659_pre(');
  DECLARE c record; v_msg text;
  BEGIN
    SELECT vc.sim_run_id, vc.scope_instance::uuid AS session_id, vc.drawn_at_clock, vc.drawn_at_tick,
           (vc.meta ->> 'soc_start')::numeric AS soc_start
      INTO c
      FROM public.ottoq_variability_cards vc
      JOIN public.ottoq_sim_runs r ON r.sim_run_id = vc.sim_run_id
      JOIN public.ocpp_sessions s ON s.id = vc.scope_instance::uuid
     WHERE vc.var_key = 'charger_fault' AND r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status <> 'running'
       AND (vc.meta ->> 'plan') = 'charger_fault_repair.v1'
       AND (vc.meta ->> 'session_fault_p')::numeric BETWEEN 0.02 AND 0.5
     ORDER BY vc.drawn_at_clock DESC, vc.scope_instance LIMIT 1;
    BEGIN
      DELETE FROM public.ottoq_variability_cards
       WHERE sim_run_id = c.sim_run_id AND var_key = 'charger_fault' AND scope_instance = c.session_id::text;
      v_b := pg_temp.ottoq_twin_deal_fault_card_0659_pre(c.sim_run_id, c.session_id, c.soc_start, 100, c.drawn_at_clock,
               (c.drawn_at_clock::date - DATE '2020-01-01'), c.drawn_at_tick);
      RAISE EXCEPTION '0659 PROBED';
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
    END;
    IF v_msg IS DISTINCT FROM '0659 PROBED' THEN RAISE EXCEPTION '0659 probe before failed: %', v_msg; END IF;
  END;
  SELECT meta INTO v_a FROM p0659 WHERE phase = 'after_unset';
  SELECT meta INTO v_d FROM p0659 WHERE phase = 'after_depot';
  IF v_a IS DISTINCT FROM v_b OR (SELECT meta FROM p0659 WHERE phase = 'after_zero') IS DISTINCT FROM v_b THEN
    RAISE EXCEPTION '0659 V1 FAILED: with the dial unset or at 0 the card moved: before % after %', v_b, v_a;
  END IF;
  IF v_d ->> 'regime' IS DISTINCT FROM 'depot_grade'
     OR abs((v_d ->> 'session_fault_p')::numeric - round((v_b ->> 'session_fault_p')::numeric * 0.40, 4)) > 0.0001 THEN
    RAISE EXCEPTION '0659 V1 FAILED: at the depot-grade dial the card is %, from %', v_d, v_b;
  END IF;
  RAISE NOTICE '0659 V1 PASSED: one session''s card is byte for byte the same unset and at 0 (session_fault_p %), and at 1 it is % with regime depot_grade; all rolled back',
    v_b ->> 'session_fault_p', v_d ->> 'session_fault_p';
END $v1$;

-- ── V2: the definition as written, the dial set nowhere, the plan and the experiment as written ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_deal_fault_card(uuid,uuid,numeric,numeric,timestamptz,integer,bigint)'::regprocedure))
       <> '8a5c3867256504ea2dcbe693e0be07d4' THEN
    RAISE EXCEPTION '0659 V2 FAILED: the fault card is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_charger_fault_regime') THEN
    RAISE EXCEPTION '0659 V2 FAILED: the dial is set somewhere';
  END IF;
  IF (SELECT (plan ->> 'session_fault_p_scale')::numeric FROM public.ottoq_feed_plans
       WHERE var_key = 'charger_fault_depot_grade' AND status = 'active') IS DISTINCT FROM 0.40 THEN
    RAISE EXCEPTION '0659 V2 FAILED: the depot-grade plan is not as written';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c USING (param_key)
                  WHERE e.created_by = '0659' AND e.status = 'active' AND e.param_key = 'twin_charger_fault_regime'
                    AND e.control_value BETWEEN c.min_value AND c.max_value
                    AND e.treatment_value BETWEEN c.min_value AND c.max_value) THEN
    RAISE EXCEPTION '0659 V2 FAILED: the experiment is not active with its dial in range';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_pair_ledger WHERE metrics_a ? 'deployed_car_hours') THEN
    RAISE EXCEPTION '0659 V2 FAILED: no arm has ever carried the primary metric deployed_car_hours';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0659_the_twins_chargers_can_be_depot_grade_and_the_research_wing_measures_it', false, false,
  'Part A (charger faults): the dial twin_charger_fault_regime (0 = today''s profile, the stress case; 1 = depot-grade, '
  'up more than 97% of the time, 23 CFR 680.116(b)), the feed plan charger_fault_depot_grade (session fault chance '
  'x 0.40), the fault card reading the dial, and the before/after pair registered. The dial is set nowhere and the card '
  'is byte for byte the same at 0 (V1): FALSE/FALSE. Making depot-grade the base is a later file, with an evidence regime.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 11:09:31 UTC (6:09 AM CT), version 20261010110931 ═════════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 9eeaa49; the ledger's stored statement is that file byte for
--   byte (md5 62c011d5a6b21320e5a23c9936dcf55f, 20,650 characters, 21,449 bytes). P1, V1, V2 passed in the apply's
--   transaction. Read after: the fault card's definition md5 8a5c3867256504ea2dcbe693e0be07d4 as written; the dial
--   twin_charger_fault_regime is set nowhere (0 rows); experiment 34696196-c36a-4186-b893-f7437e2f793d active, 0 -> 1;
--   lineage FALSE/FALSE (read 11:09:44 UTC).
