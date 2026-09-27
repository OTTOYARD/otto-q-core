-- migration-version: 20260927151819
-- migration-name:    a_guardrail_that_moves_off_zero_is_judged_and_the_verdict_names_the_unmeasured
--
-- 0529  **G254: the dial verdict skipped any guardrail whose control arm read 0 -- it divided each change by the
--       control's value through NULLIF -- so a treatment that took a KPI from 0 to anything could never breach on it,
--       and every G240 pair left KPI 4 unjudged. A move off zero now counts as a full change in its direction; the
--       verdict lists every guardrail with the pairs it was measured on and names the ones measured on none; and
--       each arm reports the wait for a charger (0501) beside KPI 5.** `db/checks/0396`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_dial_experiment_verdict` (0439) judges each reward KPI by its mean relative change over the look's pairs,
--   `dir * (b - a) / NULLIF(abs(a), 0)`. When the control reads 0 the change is NULL, `avg` skips it, and the KPI
--   cannot breach whatever the treatment does. Before 0528, KPI 4 read 0 in both arms of every G240 pair -- the twin's
--   technicians were invisible to it -- so it guarded nothing; after 0528 it reads about 1 touch per car, but any
--   small-count KPI can sit at 0 in a control arm, and the verdict would say nothing about it and show nothing either:
--   a guardrail judged on no pair appeared, at best, as `pairs: 0` beside the others.
--   Planted in V3 below: six pairs in which the treatment wins its primary 6 of 6 and takes touches per turn from 0 to
--   0.5. The pre-0529 rule concludes `treatment_wins` -- a promotion; this one concludes `guardrail_breach`.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) A guardrail's change on a pair is 0 when the arms are equal, `dir * sign(b)` -- a full 100% in its direction --
--       when the control is 0 and the treatment is not, and the relative change otherwise, as before.
--   (b) Every weight key appears in `guardrails.kpis` with `pairs` (the pairs where both arms carry a number),
--       `pairs_from_zero` and `measured`; `guardrails.unmeasured` names the keys measured on no pair of the look. An
--       unmeasured guardrail does not hold the verdict -- a KPI can be legitimately empty for a scenario -- it is
--       named, so a promotion never claims a protection it did not have.
--   (c) `ottoq_dial_arm_metrics` adds the arm's wait for a charger from `ottoq_kpi_charge_wait` (0501):
--       `charge_wait_p50_min`, `charge_wait_p95_min`, `charge_wait_p95_floor_min`, `charges_waiting_at_horizon`,
--       `visits_owing_a_charge`. KPI 5 keeps its definition (CLAUDE.md 2.9) and on a day with a software release its
--       first op is the update at the gate (0396 §3); the charger queue is the depot's binding constraint on a busy day
--       and now travels with every pair. It is reported, not a guardrail: making it one is a reward-weights decision.
--   The primary metric's arithmetic is untouched.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   Neither function is on the certified path. The verdict is a read over stored pairs and the arm metrics only gain
--   keys, so no arm can change and a pair counted before this file compares with one after: FALSE, and the dial floor
--   stays at 0528's apply.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0529 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_ver text; v_met text;
BEGIN
  v_ver := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  v_met := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  IF position('0529' IN v_ver) > 0 OR position('0529' IN v_met) > 0 THEN
    RAISE EXCEPTION '0529 P2: already applied';
  END IF;
  -- each text this file patches occurs exactly once
  IF (length(v_ver) - length(replace(v_ver, 'kk.dir * ((q.b->>kk.key)::numeric - (q.a->>kk.key)::numeric) / NULLIF(abs((q.a->>kk.key)::numeric), 0) AS rel', '')))
       / length('kk.dir * ((q.b->>kk.key)::numeric - (q.a->>kk.key)::numeric) / NULLIF(abs((q.a->>kk.key)::numeric), 0) AS rel') <> 1
     OR (length(v_ver) - length(replace(v_ver, 's AS (SELECT ch.key, avg(ch.rel) AS m, count(ch.rel) AS n FROM ch GROUP BY ch.key)', '')))
       / length('s AS (SELECT ch.key, avg(ch.rel) AS m, count(ch.rel) AS n FROM ch GROUP BY ch.key)') <> 1
     OR (length(v_ver) - length(replace(v_ver, '''pairs'', s.n,', ''))) / length('''pairs'', s.n,') <> 1
     OR (length(v_ver) - length(replace(v_ver, '''kpis'', v_guard, ''breached'', v_breach),', '')))
       / length('''kpis'', v_guard, ''breached'', v_breach),') <> 1
     OR (length(v_met) - length(replace(v_met, '''charge_overrun_p50_min'',  round(v_bk_p50, 1));', '')))
       / length('''charge_overrun_p50_min'',  round(v_bk_p50, 1));') <> 1 THEN
    RAISE EXCEPTION '0529 P2: the verdict or the arm metrics are not as this file expects';
  END IF;
  -- the companion the arm metrics will call exists, and neither function is on the certified path
  IF to_regprocedure('public.ottoq_kpi_charge_wait(uuid)') IS NULL THEN
    RAISE EXCEPTION '0529 P2: ottoq_kpi_charge_wait (0501) is missing';
  END IF;
  IF pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure)
       ~* 'ottoq_dial_(experiment_verdict|arm_metrics)' THEN
    RAISE EXCEPTION '0529 P2: the determinism pair calls the verdict or the arm metrics';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0529_pre', 'function', 'public', 'ottoq_dial_experiment_verdict',
       pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure))
UNION ALL
SELECT '0529_pre', 'function', 'public', 'ottoq_dial_arm_metrics',
       pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure));

-- ── the verdict: a move off zero is judged, and every guardrail says what it was measured on ──
DO $patch_verdict$
DECLARE
  v_def text;
  v_old1 text := $o$kk.dir * ((q.b->>kk.key)::numeric - (q.a->>kk.key)::numeric) / NULLIF(abs((q.a->>kk.key)::numeric), 0) AS rel$o$;
  v_new1 text := $n$-- 0529 (G254): a move off zero is a full change in its direction; it was NULL and skipped
                  CASE WHEN (q.b->>kk.key)::numeric = (q.a->>kk.key)::numeric THEN 0
                       WHEN (q.a->>kk.key)::numeric = 0 THEN kk.dir * sign((q.b->>kk.key)::numeric)
                       ELSE kk.dir * ((q.b->>kk.key)::numeric - (q.a->>kk.key)::numeric) / abs((q.a->>kk.key)::numeric) END AS rel,
                  (q.a->>kk.key)::numeric = 0 AND (q.b->>kk.key)::numeric <> 0 AS from_zero$n$;
  v_old2 text := $o$s AS (SELECT ch.key, avg(ch.rel) AS m, count(ch.rel) AS n FROM ch GROUP BY ch.key)$o$;
  v_new2 text := $n$-- 0529 (G254): every weight key, measured or not
    s AS (SELECT kk.key, avg(ch.rel) AS m, count(ch.rel) AS n, count(*) FILTER (WHERE ch.from_zero) AS nz
            FROM kk LEFT JOIN ch ON ch.key = kk.key GROUP BY kk.key)$n$;
  v_old3 text := $o$'pairs', s.n,$o$;
  v_new3 text := $n$'pairs', s.n, 'pairs_from_zero', s.nz, 'measured', s.n > 0,$n$;
  v_old4 text := $o$'kpis', v_guard, 'breached', v_breach),$o$;
  v_new4 text := $n$'kpis', v_guard, 'breached', v_breach,
                                     -- 0529 (G254): the guardrails measured on no pair of the look, named
                                     'unmeasured', COALESCE((SELECT jsonb_agg(g.k ORDER BY g.k) FROM jsonb_each(v_guard) AS g(k, v)
                                                              WHERE (g.v->>'measured')::boolean IS FALSE), '[]'::jsonb)),$n$;
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  IF n <> 1 THEN RAISE EXCEPTION '0529: verdict patch 1 matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n <> 1 THEN RAISE EXCEPTION '0529: verdict patch 2 matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old3, ''))) / length(v_old3);
  IF n <> 1 THEN RAISE EXCEPTION '0529: verdict patch 3 matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old4, ''))) / length(v_old4);
  IF n <> 1 THEN RAISE EXCEPTION '0529: verdict patch 4 matched % times, not once', n; END IF;
  EXECUTE replace(replace(replace(replace(v_def, v_old1, v_new1), v_old2, v_new2), v_old3, v_new3), v_old4, v_new4);
END $patch_verdict$;

-- ── the arm metrics: the wait for a charger travels with every pair ──
DO $patch_metrics$
DECLARE
  v_def text;
  v_old text := $o$'charge_overrun_p50_min',  round(v_bk_p50, 1));$o$;
  v_new text := $n$'charge_overrun_p50_min',  round(v_bk_p50, 1))
    -- 0529 (G254): the wait for a charger (0501), beside KPI 5 and reported with every arm; not a guardrail
    || (SELECT jsonb_build_object(
          'charge_wait_p50_min',        cw->'p50_wait_min',
          'charge_wait_p95_min',        cw->'p95_wait_min',
          'charge_wait_p95_floor_min',  cw->'p95_wait_floor_min',
          'charges_waiting_at_horizon', cw->'waiting_at_horizon',
          'visits_owing_a_charge',      cw->'visits_owing_a_charge')
          FROM (SELECT public.ottoq_kpi_charge_wait(p_run) AS cw) z);$n$;
  n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0529: metrics patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_metrics$;

DO $verify$
DECLARE v_ver text; v_met text;
BEGIN
  v_ver := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  v_met := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  -- V1: the verdict judges a move off zero, reports every key and names the unmeasured; the old division is gone;
  --     the arm metrics carry the charge wait
  IF position('NULLIF(abs((q.a->>kk.key)::numeric), 0)' IN v_ver) > 0
     OR position('kk.dir * sign((q.b->>kk.key)::numeric)' IN v_ver) = 0
     OR position('FROM kk LEFT JOIN ch ON ch.key = kk.key' IN v_ver) = 0
     OR position('''pairs_from_zero'', s.nz' IN v_ver) = 0
     OR position('''unmeasured''' IN v_ver) = 0
     OR position('''charge_wait_p95_min''' IN v_met) = 0
     OR position('public.ottoq_kpi_charge_wait(p_run)' IN v_met) = 0 THEN
    RAISE EXCEPTION '0529 V1: the verdict or the arm metrics are not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule): no arm can change.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0529_a_guardrail_that_moves_off_zero_is_judged_and_the_verdict_names_the_unmeasured', false, false,
  'The dial verdict (a read over stored pairs) judges a guardrail that moves off zero and names the unmeasured ones; '
  'the dial arm metrics gain the charge-wait keys (G254). Neither is on the certified path and no arm can change, so '
  'a pair counted before it compares with one after.', now())
ON CONFLICT (name) DO NOTHING;

-- V3: rolled back. (a) Planted: an abandoned experiment and six pairs in which the treatment wins its primary 6 of 6
--     and takes touches per turn from 0 to 0.5, with p95_time_to_service_min absent. The pre-0529 guardrail arithmetic,
--     run inline on the same pairs, judges touches on no pair; the verdict now concludes guardrail_breach on
--     touches_events_per_turn, from zero on 6 pairs, and names p95_time_to_service_min unmeasured. (b) The arm metrics
--     of G240's pair 76 carry the charge wait 0501 reads for them: p95 72 and 78 minutes.
DO $v3$
DECLARE
  v_msg text; v_exp uuid := gen_random_uuid(); v_v jsonb; v_old_pairs bigint; v_ma jsonb; v_mb jsonb; v_k int;
BEGIN
  BEGIN
    INSERT INTO public.ottoq_dial_experiments
           (experiment_id, created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks,
            sim_start, primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct,
            min_effect_pct, guardrail_alpha, hypothesis, status, sim_min_per_tick)
    SELECT v_exp, '0529_v3', x.depot_id, x.param_key, 0, 1, '{}'::jsonb, x.scenario, x.ticks, x.sim_start,
           'v3_primary', 'higher', 6, 12, 0.05, 2, 0, 0.1, '0529 V3: planted, rolled back', 'abandoned', x.sim_min_per_tick
      FROM public.ottoq_dial_experiments x WHERE x.experiment_id = '143a11c7-6740-4624-b747-e145f3533e60';
    FOR v_k IN 1..6 LOOP
      INSERT INTO public.ottoq_dial_pair_ledger
             (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete, world_identical,
              both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
      VALUES (v_exp, v_k, '0529_v3', now(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), true, true, true, true,
              '["h_evt"]'::jsonb,
              jsonb_build_object('v3_primary', 1, 'touch_events_per_turn', 0, 'asset_hours_available_per_day', 100,
                                 'service_point_turns_per_point_per_day', 2, 'peak_site_kw', 500),
              jsonb_build_object('v3_primary', 2, 'touch_events_per_turn', 0.5, 'asset_hours_available_per_day', 100,
                                 'service_point_turns_per_point_per_day', 2, 'peak_site_kw', 500),
              '{}'::jsonb, 0);
    END LOOP;
    -- the pre-0529 arithmetic on the same pairs: the move from zero is NULL, so the KPI is judged on no pair
    SELECT count(-1 * ((l.metrics_b->>'touch_events_per_turn')::numeric - (l.metrics_a->>'touch_events_per_turn')::numeric)
                 / NULLIF(abs((l.metrics_a->>'touch_events_per_turn')::numeric), 0))
      INTO v_old_pairs FROM public.ottoq_dial_pair_ledger l WHERE l.experiment_id = v_exp;
    v_v := public.ottoq_dial_experiment_verdict(v_exp);
    IF v_old_pairs <> 0
       OR v_v->>'outcome' IS DISTINCT FROM 'guardrail_breach'
       OR v_v->'guardrails'->'breached' IS DISTINCT FROM '["touch_events_per_turn"]'::jsonb
       OR (v_v->'guardrails'->'kpis'->'touch_events_per_turn'->>'mean_change_pct')::numeric <> -100
       OR (v_v->'guardrails'->'kpis'->'touch_events_per_turn'->>'pairs_from_zero')::int <> 6
       OR v_v->'guardrails'->'unmeasured' IS DISTINCT FROM '["p95_time_to_service_min"]'::jsonb
       OR (v_v->'guardrails'->'kpis'->'p95_time_to_service_min'->>'pairs')::int <> 0
       OR (v_v->'guardrails'->'kpis'->'asset_hours_available_per_day'->>'mean_change_pct')::numeric <> 0 THEN
      RAISE EXCEPTION '0529 V3 FAILED (a): the old rule judged touches on % pairs; the verdict read %', v_old_pairs, v_v;
    END IF;
    -- (b) the arm metrics carry the charge wait
    SELECT public.ottoq_dial_arm_metrics(p.run_a, x.depot_id, NULL), public.ottoq_dial_arm_metrics(p.run_b, x.depot_id, NULL)
      INTO v_ma, v_mb
      FROM public.ottoq_dial_pair_ledger p JOIN public.ottoq_dial_experiments x ON x.experiment_id = p.experiment_id
     WHERE p.pair_id = 76;
    IF (v_ma->>'charge_wait_p95_min')::numeric <> 72 OR (v_mb->>'charge_wait_p95_min')::numeric <> 78
       OR (v_ma->>'visits_owing_a_charge')::int <> 92 THEN
      RAISE EXCEPTION '0529 V3 FAILED (b): pair 76''s arms read % and %', v_ma->'charge_wait_p95_min', v_mb->'charge_wait_p95_min';
    END IF;
    RAISE EXCEPTION '0529 V3 PASSED: the old rule judged touches 0 -> 0.5 on % of 6 pairs; now % (%), from zero on 6, unmeasured %; pair 76 charge wait p95 % / %',
      v_old_pairs, v_v->>'outcome', v_v->'guardrails'->'breached', v_v->'guardrails'->'unmeasured',
      v_ma->'charge_wait_p95_min', v_mb->'charge_wait_p95_min';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0529 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0529 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0529_pre' as is (both are
--   CREATE OR REPLACE FUNCTION with unchanged signatures).
COMMIT;
