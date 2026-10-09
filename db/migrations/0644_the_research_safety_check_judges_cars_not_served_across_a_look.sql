-- migration-version: PENDING
-- migration-name:    the_research_safety_check_judges_cars_not_served_across_a_look
--
-- 0644  **The research wing's vehicle-first check judges returned cars left without service across a look's pairs, not
--        on one pair.** (G392; Chase, 2026-10-09, midday CT: "You can change the research safety check if needed for
--        this. Keep it concise as possible".)
--
-- ══ §1 WHY (db/checks/0428 §4) ═════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_dial_experiment_verdict ended an experiment as a safety regression the first time any one counted pair left
--   more returns_unserved under the treatment. On a change to the charge order that count swings by more than a dozen
--   cars between seeds (a4c7b7d0 read -5, -17, +3 and was concluded on the third; 143a11c7 on its first counted pair,
--   +18), so the check could not tell an effect from a seed. And returns_unserved counts a returned car whose first
--   operation was due before the day's end and never started; one planned past the end is counted apart as deferred,
--   so an order that plans sooner moves cars from deferred to unserved without serving one fewer (0642's minutes
--   order: +13 by the old check, +3 counted plainly).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) ottoq_dial_arm_metrics records returns_not_served: returned cars with no operation started by the arm's end
--       (returns_unserved plus returns_deferred_beyond_horizon, both from the KPI's own audit).
--   (b) ottoq_dial_experiment_verdict judges it at each look, over the look's pairs, with the one-sided exact sign test
--       its refusals guardrail already uses, at guardrail_alpha (0.20): a safety regression when the treatment leaves
--       more cars without service in significantly more pairs than fewer. At 6 pairs that is 5 or more of 6 non-tied
--       (p = 0.109); at 12, 8 or more of 12 (p = 0.194). A pair is read on returns_not_served when both arms carry it,
--       else on returns_unserved (pairs recorded before this file), by the new ottoq_dial_not_served_delta.
--   (c) Unchanged: an unprevented safety-critical failure on any counted pair still ends an experiment at once; it is
--       now checked first. pairs_more_unserved is still reported.
--   On any outcome but a win the promoter writes no dial, and promotion is off (0540): this changes what the research
--   wing concludes, never a setting in production.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   Neither function is on a tick path, and an arm runs exactly as before; it records one more number about itself.
--   Pairs already counted keep counting, each read on the count it was recorded with.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0644 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: the definitions this file was written against ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure)) <> 'bf849eb6309f6c7f145efad535793ea7' THEN
    RAISE EXCEPTION '0644 P1: ottoq_dial_experiment_verdict is not the definition this file was written against';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure)) <> '87d1914f7193f55fdc34c6ac6d9a5733' THEN
    RAISE EXCEPTION '0644 P1: ottoq_dial_arm_metrics is not the definition this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_dial_not_served_delta(jsonb,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0644 P1: ottoq_dial_not_served_delta exists already';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0644_pre', 'function', 'public', f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('ottoq_dial_experiment_verdict', 'public.ottoq_dial_experiment_verdict(uuid)'),
               ('ottoq_dial_arm_metrics',        'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)')) AS f(obj, sig);

-- ── one pair's difference in returned cars without service ──
CREATE OR REPLACE FUNCTION public.ottoq_dial_not_served_delta(p_a jsonb, p_b jsonb)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $fn$
  /* 0644 (G392): treatment minus control in returned cars with no operation started by the arm's end. A pair recorded
     before 0644 carries only returns_unserved and is read on it. */
  SELECT CASE WHEN jsonb_typeof(p_a -> 'returns_not_served') = 'number' AND jsonb_typeof(p_b -> 'returns_not_served') = 'number'
              THEN (p_b ->> 'returns_not_served')::numeric - (p_a ->> 'returns_not_served')::numeric
              ELSE COALESCE((p_b ->> 'returns_unserved')::numeric, 0) - COALESCE((p_a ->> 'returns_unserved')::numeric, 0) END
$fn$;

-- ── (a) an arm records its returned cars without service ──
DO $arm$
DECLARE v_def text; v_old text; v_new text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  v_old := $o$    'returns_unserved',                      NULLIF(v_kpi->>'returns_unserved', '')::numeric,
$o$;
  v_new := v_old || $n$    -- 0644 (G392): returned cars with no operation started by the arm's end, unserved plus deferred past it
    'returns_not_served',                    NULLIF(v_kpi->>'returns_unserved', '')::numeric
                                             + NULLIF(v_kpi #>> '{audit,p95_time_to_service_min,returns_deferred_beyond_horizon}', '')::numeric,
$n$;
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0644 (a): the arm metrics patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $arm$;

-- ── (b) the verdict judges it at the look, after the unprevented check ──
DO $verdict$
DECLARE
  v_def text; v_new text; n int; i int;
  p text[][] := ARRAY[
    ARRAY[$a1$  v_unserved_worse int := 0; v_crit_a numeric := 0; v_crit_b numeric := 0;
$a1$,
          $b1$  v_unserved_worse int := 0; v_crit_a numeric := 0; v_crit_b numeric := 0;
  v_ns_more int := 0; v_ns_fewer int := 0; v_p_ns numeric; v_ns_read jsonb;   -- 0644 (G392)
$b1$],
    ARRAY[$a2$  -- SAFETY, over EVERY counted pair and not only the look's, so it can stop the experiment early. Only an
  -- UNPREVENTED safety-critical failure is an unsafe outcome; a refused one is shield reliance (a guardrail below).
  SELECT count(*),
         count(*) FILTER (WHERE COALESCE((c.b->>'returns_unserved')::numeric, 0) > COALESCE((c.a->>'returns_unserved')::numeric, 0)),
$a2$,
          $b2$  -- SAFETY. An UNPREVENTED safety-critical failure, over EVERY counted pair, stops the experiment early; a refused
  -- one is shield reliance (a guardrail below). 0644 (G392): returned cars left without service are judged at the
  -- look, below, and not on one pair; pairs_more_unserved is reported, not decided on.
  SELECT count(*),
         count(*) FILTER (WHERE public.ottoq_dial_not_served_delta(c.a, c.b) > 0),
$b2$],
    ARRAY[$a3$      v_breach := v_breach || to_jsonb('safety_critical_refused'::text);
    END IF;
  END IF;
$a3$,
          $b3$      v_breach := v_breach || to_jsonb('safety_critical_refused'::text);
    END IF;

    -- 0644 (G392): VEHICLE FIRST over the look's pairs: returned cars with no operation started by the arm's end,
    -- one-sided sign test at guardrail_alpha, as the refusals above
    SELECT count(*) FILTER (WHERE z.d > 0), count(*) FILTER (WHERE z.d < 0),
           jsonb_build_object('returns_not_served', count(*) FILTER (WHERE z.plain),
                              'returns_unserved',   count(*) FILTER (WHERE NOT z.plain))
      INTO v_ns_more, v_ns_fewer, v_ns_read
      FROM (SELECT public.ottoq_dial_not_served_delta(q.a, q.b) AS d,
                   COALESCE(jsonb_typeof(q.a->'returns_not_served') = 'number'
                            AND jsonb_typeof(q.b->'returns_not_served') = 'number', false) AS plain
              FROM public.ottoq_dial_counted_pairs(p_experiment_id, v_floor) q WHERE q.k <= v_look) z;
    v_p_ns := public.ottoq_binom_upper_tail(v_ns_more + v_ns_fewer, v_ns_more);
  END IF;
$b3$],
    ARRAY[$a4$  IF v_unserved_worse > 0 THEN
    v_outcome := 'safety_regression';
    v_why := format('%s counted pair(s) leave more returns unserved under the treatment; vehicle-first is inviolable', v_unserved_worse);
  ELSIF v_crit_b > v_crit_a THEN
    v_outcome := 'safety_regression';
    v_why := format('the treatment totals %s unprevented safety-critical failures against the control''s %s', v_crit_b, v_crit_a);
$a4$,
          $b4$  IF v_crit_b > v_crit_a THEN
    v_outcome := 'safety_regression';
    v_why := format('the treatment totals %s unprevented safety-critical failures against the control''s %s', v_crit_b, v_crit_a);
  ELSIF v_look IS NOT NULL AND v_ns_more > 0 AND v_p_ns <= x.guardrail_alpha THEN
    -- 0644 (G392)
    v_outcome := 'safety_regression';
    v_why := format('over the %s pairs of the look the treatment leaves more returned cars without service in %s and fewer in %s (p = %s <= %s); vehicle-first is inviolable',
                    v_look, v_ns_more, v_ns_fewer, round(v_p_ns, 5), x.guardrail_alpha);
$b4$],
    ARRAY[$a5$                                 'unprevented_control', v_crit_a, 'unprevented_treatment', v_crit_b),
$a5$,
          $b5$                                 'unprevented_control', v_crit_a, 'unprevented_treatment', v_crit_b,
                                 -- 0644 (G392): the vehicle-first test at the look
                                 'not_served', jsonb_build_object('look', v_look, 'pairs_more', v_ns_more, 'pairs_fewer', v_ns_fewer,
                                                                  'p', round(v_p_ns, 6), 'alpha', x.guardrail_alpha, 'read_on', v_ns_read)),
$b5$]];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  v_new := v_def;
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_new) - length(replace(v_new, p[i][1], ''))) / length(p[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0644 (b): verdict patch % matched % times, not once', i, n; END IF;
    v_new := replace(v_new, p[i][1], p[i][2]);
  END LOOP;
  EXECUTE v_new;
END $verdict$;

-- ═══ verification ════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_verdict text; v_arm text; v_x jsonb; v_y jsonb;
BEGIN
  -- V1: read with comments stripped
  v_verdict := regexp_replace(pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure), '--[^\n]*', '', 'g');
  v_arm     := regexp_replace(pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure), '--[^\n]*', '', 'g');
  IF position('IF v_unserved_worse > 0 THEN' IN v_verdict) > 0
     OR position('ELSIF v_look IS NOT NULL AND v_ns_more > 0 AND v_p_ns <= x.guardrail_alpha THEN' IN v_verdict) = 0
     OR position('IF v_crit_b > v_crit_a THEN' IN v_verdict) > position('ELSIF v_look IS NOT NULL AND v_ns_more > 0' IN v_verdict)
     OR position('public.ottoq_dial_not_served_delta(q.a, q.b)' IN v_verdict) = 0
     OR position('''returns_not_served''' IN v_arm) = 0 THEN
    RAISE EXCEPTION '0644 V1: the definitions are not as this file intends';
  END IF;
  -- 0428's pair 120 counted plainly (+3), and a pair recorded before 0644 read on returns_unserved (+13)
  IF public.ottoq_dial_not_served_delta('{"returns_unserved": 29, "returns_not_served": 48}', '{"returns_unserved": 42, "returns_not_served": 51}') <> 3
     OR public.ottoq_dial_not_served_delta('{"returns_unserved": 29}', '{"returns_unserved": 42, "returns_not_served": 51}') <> 13
     OR public.ottoq_dial_not_served_delta('{}', '{}') <> 0 THEN
    RAISE EXCEPTION '0644 V1: ottoq_dial_not_served_delta does not read a pair as intended';
  END IF;
  -- V2: 0643's two experiments, one pair each, collect again instead of ending on that pair
  IF (SELECT count(*) FROM public.ottoq_dial_experiments
       WHERE experiment_id IN ('f2120031-04a2-4b14-adb9-4aaa61767dd8', '04e101de-0e5e-4150-927c-8e5b5e912b4e')) = 2 THEN
    v_x := public.ottoq_dial_experiment_verdict('f2120031-04a2-4b14-adb9-4aaa61767dd8');
    v_y := public.ottoq_dial_experiment_verdict('04e101de-0e5e-4150-927c-8e5b5e912b4e');
    IF v_x->>'outcome' IS DISTINCT FROM 'collecting' OR v_y->>'outcome' IS DISTINCT FROM 'collecting'
       OR (v_x->>'terminal')::boolean OR (v_y->>'terminal')::boolean THEN
      RAISE EXCEPTION '0644 V2: 0643''s experiments read % and %, not collecting', v_x->>'outcome', v_y->>'outcome';
    END IF;
    RAISE NOTICE '0644 V2: 0643''s experiments read % (%) and % (%)', v_x->>'outcome', v_x->>'why', v_y->>'outcome', v_y->>'why';
  END IF;
END $verify$;

-- V2b: an arm's returns_not_served is the KPI's own count, on the latest pair arm still on record
DO $v2b$
DECLARE v_run uuid; v_depot uuid; v_m jsonb; v_view numeric;
BEGIN
  SELECT l.run_b, x.depot_id INTO v_run, v_depot
    FROM public.ottoq_dial_pair_ledger l
    JOIN public.ottoq_dial_experiments x ON x.experiment_id = l.experiment_id
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.run_b
   WHERE r.purged_at IS NULL
   ORDER BY l.ran_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE NOTICE '0644 V2b: no pair arm on record to read'; RETURN; END IF;
  v_m := public.ottoq_dial_arm_metrics(v_run, v_depot, NULL);
  SELECT v.returns_unserved + v.returns_deferred_beyond_horizon INTO v_view
    FROM public.ottoq_kpi_p95_time_to_service v WHERE v.sim_run_id = v_run;
  IF (v_m->>'returns_not_served')::numeric IS DISTINCT FROM v_view THEN
    RAISE EXCEPTION '0644 V2b: arm % records % returned cars without service, the KPI counts %', v_run, v_m->>'returns_not_served', v_view;
  END IF;
  RAISE NOTICE '0644 V2b: arm % records % returned cars without service, as the KPI counts', v_run, v_view;
END $v2b$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0644_the_research_safety_check_judges_cars_not_served_across_a_look', false, false,
  'G392: ottoq_dial_arm_metrics records returns_not_served (unserved plus deferred past the arm''s end); '
  'ottoq_dial_experiment_verdict judges it at each look over the look''s pairs (one-sided sign test at guardrail_alpha) '
  'instead of ending an experiment on any one pair with more returns_unserved. Research instrument only: no tick path, '
  'and an arm runs as before. FALSE/FALSE.',
  now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back. Three planted experiments at the twin depot, the primary tied in every pair:
--   (A) one pair recorded before 0644, the treatment 3 worse on returns_unserved: collecting (the old check ended here);
--       five more pairs counted plainly (-5, -17, +1, 0, -2): 2 worse and 3 better at the look, collecting.
--   (B) six pairs, the treatment worse in five (+4, +2, +6, +1, +3, -1): safety_regression, p = 7/64.
--   (C) one pair with an unprevented safety-critical failure in the treatment: safety_regression at once.
DO $v3$
DECLARE
  v_msg text; v_depot uuid := '11111111-1111-1111-1111-111111111111'; v_floor timestamptz := public.ottoq_dial_pair_floor();
  v_a uuid; v_b uuid; v_c uuid; v1 jsonb; v6 jsonb; vb jsonb; vc jsonb; i int;
  d_a int[] := ARRAY[-5, -17, 1, 0, -2];
  d_b int[] := ARRAY[4, 2, 6, 1, 3, -1];
BEGIN
  BEGIN
    INSERT INTO public.ottoq_dial_experiments (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks,
                                               sim_start, primary_metric, primary_better, hypothesis, sim_min_per_tick)
    VALUES ('0644_v3', v_depot, 'charge_kind_match', 0, 1, 'busy_day', 90, '2026-09-01 13:00:00+00',
            'deployed_car_hours', 'higher', '0644 V3 plant A', 6)
    RETURNING experiment_id INTO v_a;
    INSERT INTO public.ottoq_dial_experiments (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks,
                                               sim_start, primary_metric, primary_better, hypothesis, sim_min_per_tick)
    VALUES ('0644_v3', v_depot, 'charge_window_calibration_id', 0, 6, 'busy_day', 90, '2026-09-01 13:00:00+00',
            'deployed_car_hours', 'higher', '0644 V3 plant B', 6)
    RETURNING experiment_id INTO v_b;
    INSERT INTO public.ottoq_dial_experiments (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks,
                                               sim_start, primary_metric, primary_better, hypothesis, sim_min_per_tick)
    VALUES ('0644_v3', v_depot, 'recall_implementation_id', 1, 3, 'busy_day', 90, '2026-09-01 13:00:00+00',
            'deployed_car_hours', 'higher', '0644 V3 plant C', 6)
    RETURNING experiment_id INTO v_c;

    -- (A)
    INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                               world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
    VALUES (v_a, 1, '0644_v3', v_floor + interval '1 second', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
            true, true, true, true, '[]'::jsonb,
            '{"deployed_car_hours": 100, "returns_unserved": 24}'::jsonb,
            '{"deployed_car_hours": 100, "returns_unserved": 27}'::jsonb, '{}'::jsonb, 0);
    v1 := public.ottoq_dial_experiment_verdict(v_a);
    FOR i IN 1 .. 5 LOOP
      INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                                 world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
      VALUES (v_a, 1 + i, '0644_v3', v_floor + make_interval(secs => 1 + i), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
              true, true, true, true, '[]'::jsonb,
              jsonb_build_object('deployed_car_hours', 100, 'returns_unserved', 30, 'returns_not_served', 40),
              jsonb_build_object('deployed_car_hours', 100, 'returns_unserved', 30, 'returns_not_served', 40 + d_a[i]), '{}'::jsonb, 0);
    END LOOP;
    v6 := public.ottoq_dial_experiment_verdict(v_a);

    -- (B)
    FOR i IN 1 .. 6 LOOP
      INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                                 world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
      VALUES (v_b, i, '0644_v3', v_floor + make_interval(secs => i), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
              true, true, true, true, '[]'::jsonb,
              jsonb_build_object('deployed_car_hours', 100, 'returns_unserved', 30, 'returns_not_served', 40),
              jsonb_build_object('deployed_car_hours', 100, 'returns_unserved', 30, 'returns_not_served', 40 + d_b[i]), '{}'::jsonb, 0);
    END LOOP;
    vb := public.ottoq_dial_experiment_verdict(v_b);

    -- (C)
    INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                               world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
    VALUES (v_c, 1, '0644_v3', v_floor + interval '1 second', gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
            true, true, true, true, '[]'::jsonb,
            '{"deployed_car_hours": 100, "returns_not_served": 40, "safety_critical_unprevented": 0}'::jsonb,
            '{"deployed_car_hours": 100, "returns_not_served": 40, "safety_critical_unprevented": 1}'::jsonb, '{}'::jsonb, 0);
    vc := public.ottoq_dial_experiment_verdict(v_c);

    IF v1->>'outcome' IS DISTINCT FROM 'collecting' OR (v1->>'terminal')::boolean
       OR (v1 #>> '{safety,pairs_more_unserved}')::int IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION '0644 V3 FAILED (A, one pair): % (terminal %): %', v1->>'outcome', v1->>'terminal', v1->>'why';
    END IF;
    IF v6->>'outcome' IS DISTINCT FROM 'collecting' OR (v6->>'terminal')::boolean
       OR (v6 #>> '{safety,not_served,pairs_more}')::int IS DISTINCT FROM 2
       OR (v6 #>> '{safety,not_served,pairs_fewer}')::int IS DISTINCT FROM 3
       OR (v6 #>> '{safety,not_served,read_on,returns_not_served}')::int IS DISTINCT FROM 5
       OR (v6 #>> '{safety,not_served,read_on,returns_unserved}')::int IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION '0644 V3 FAILED (A, six pairs): % (terminal %): % / %', v6->>'outcome', v6->>'terminal', v6->>'why', v6->'safety';
    END IF;
    IF vb->>'outcome' IS DISTINCT FROM 'safety_regression' OR NOT COALESCE((vb->>'terminal')::boolean, false)
       OR (vb #>> '{safety,not_served,p}')::numeric IS DISTINCT FROM 0.109375 THEN
      RAISE EXCEPTION '0644 V3 FAILED (B): % (terminal %): % / %', vb->>'outcome', vb->>'terminal', vb->>'why', vb->'safety';
    END IF;
    IF vc->>'outcome' IS DISTINCT FROM 'safety_regression' OR NOT COALESCE((vc->>'terminal')::boolean, false)
       OR position('unprevented' IN vc->>'why') = 0 THEN
      RAISE EXCEPTION '0644 V3 FAILED (C): % (terminal %): %', vc->>'outcome', vc->>'terminal', vc->>'why';
    END IF;

    RAISE EXCEPTION '0644 V3 PASSED: one pair 3 worse is %; at the look 2 worse and 3 better is %; 5 of 6 worse is % (p = %); an unprevented failure is %',
      v1->>'outcome', v6->>'outcome', vb->>'outcome', vb #>> '{safety,not_served,p}', vc->>'outcome';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0644 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0644 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the two definitions in ottoq_schema_snapshots WHERE label = '0644_pre' as they are;
-- ottoq_dial_not_served_delta is then unread and can stay.
COMMIT;
