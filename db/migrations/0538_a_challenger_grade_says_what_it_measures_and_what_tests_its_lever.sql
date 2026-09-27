-- migration-version: 20260927210230
-- migration-name:    a_challenger_grade_says_what_it_measures_and_what_tests_its_lever
--
-- 0538  **Each challenger question says what its grade measures, and carries the paired tests of its lever with their
--       results so far.**
--
-- ══ §1 WHY (G264, db/checks/0400 §2(b) and §3) ════════════════════════════════════════════════════════════════════════
--
--   On the challenger's first live day (`ad106e55`) Q1 confirmed 42 of 42 listed questions, and at 8x it could not have
--   graded one otherwise. Q1's grade is the lesser of the minutes the car charged on after the question was raised and the
--   minutes the longest waiter waited on, confirmed at 5. A listed question was seen by two scans, 7.5-24 sim-minutes
--   apart, so every listed car had charged on at least 9.5 minutes, and the grade falls under 5 only if the longest
--   waiter plugged in within 5 minutes: none of the 42 did. On a day when cars wait in every minute the grade records
--   that a car kept charging while the queue kept waiting. That is true, and it is local.
--
--   The cockpits read it as more than that. The board's lifetime line gives Q1 `hit_rate` 1, which the twin and PULSE
--   render as `right 42 of 42 graded (100%)`, and a confirmed grade as `a real gain missed`. The paired test of the
--   same lever (`dcfc_target_soc_day` 90 against 85, experiment 08262943, pair 102) lost the day on its first seed:
--   unmet demand 336.3 against 352.4 car-hours. The board carried the lever as a sentence naming that experiment and
--   nothing of how it was going, so a cockpit could not put the two side by side.
--
-- ══ §2 WHAT THIS CHANGES (read-only; the ledger, the scan and the grades are untouched) ════════════════════════════════
--
--   `ottoq_challenger_board`, per question:
--     (a) `grade_scope`: `local` for Q1, whose grade reads one charger and one waiting car; `fact` for Q2 and Q3, whose
--         grade is the thing itself (a charger free across two scans; a fault 30 minutes long while cars waited);
--     (b) `grade_means`: what a confirmed grade says, in a sentence the cockpits show beside the record;
--     (c) `lever_tests`: every dial experiment on the question's lever dials (Q1: `dcfc_target_soc_day` and
--         `dcfc_target_soc_night`; Q2 and Q3 have none), with the learning board's own status, outcome, `why` and
--         `run_after`, and the tally over the pairs the decision rule counts (`ottoq_dial_counted_pairs` since the dial
--         floor): how many, in how many the treatment did better and worse on the primary, and the two arms' means.
--     The Q1 lever sentence stops naming one experiment: `lever_tests` names them all.
--   The contract becomes `ottoq_challenger_board/0538`. Every earlier key is unchanged, so a cockpit that does not read
--   the new ones renders as before.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   One read-only function, not on a tick path and not read by a dial arm. It reads the learning board and the counted
--   pairs; it writes nothing. Tonight's dial window is unaffected.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0538 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the board is 0537's, and what it will read exists, as measured (2026-09-27 21:05 UTC) ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_challenger_board(uuid)'::regprocedure)
       <> 'dcf6a100968635a7c2262a92edacae5f' THEN
    RAISE EXCEPTION '0538 P2: ottoq_challenger_board is not 0537''s';
  END IF;
  IF to_regprocedure('public.ottoq_learning_board()') IS NULL
     OR to_regprocedure('public.ottoq_dial_counted_pairs(uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_dial_pair_floor()') IS NULL THEN
    RAISE EXCEPTION '0538 P2: the learning board, the counted pairs or the dial floor is missing';
  END IF;
  IF (SELECT pg_get_function_result('public.ottoq_dial_counted_pairs(uuid,timestamp with time zone)'::regprocedure))
       <> 'TABLE(k bigint, pair_id bigint, seed bigint, differs boolean, a jsonb, b jsonb)' THEN
    RAISE EXCEPTION '0538 P2: ottoq_dial_counted_pairs does not return (k, pair_id, seed, differs, a, b)';
  END IF;
END $premises$;

-- ── (a)-(c): each patch must match exactly once ──
DO $patch$
DECLARE
  v_def text;
  n int;
  p text[];
  r text[];
  i int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_challenger_board(uuid)'::regprocedure);
  p := ARRAY[
    $a1$/* 0537: an episode is a question once a second scan still sees it;$a1$,
    $a2$  q(ord, code, tag, asks, lever) AS (VALUES$a2$,
    $a3$        'No verb in the engine yet (a charge is not ended early). Tested as a dial: dcfc_target_soc_day, experiment 08262943.'),$a3$,
    $a4$        'A missed assignment. Graded before it earns a proposer seat.'),$a4$,
    $a5$        'Capacity lost to faults; the fault''s duration is the grade.')),$a5$,
    $a6$        'code', q.code, 'tag', q.tag, 'asks', q.asks, 'lever', q.lever,$a6$,
    $a7$    'contract', 'ottoq_challenger_board/0537',$a7$];
  r := ARRAY[
    $b1$/* 0538: each question says what its grade measures (grade_scope, grade_means) and carries the paired tests of its
     lever with their results so far (lever_tests). 0537: an episode is a question once a second scan still sees it;$b1$,
    $b2$  q(ord, code, tag, asks, lever, grade_scope, grade_means, lever_params) AS (VALUES$b2$,
    $b3$        'No verb in the engine yet (a charge is not ended early). Tested as dials: the fast-charge ceilings by day and by night.',
        'local',
        'A confirmed grade says the car charged on and the longest waiter waited on, 5 minutes or more each after the question was raised. It does not say that ending the charge would have helped the day: the paired tests of the lever answer that.',
        ARRAY['dcfc_target_soc_day', 'dcfc_target_soc_night']),$b3$,
    $b4$        'A missed assignment. Graded before it earns a proposer seat.',
        'fact',
        'A confirmed grade says a charger stayed free by every gate across two scans while the longest waiter waited 5 more minutes: a missed assignment.',
        ARRAY[]::text[]),$b4$,
    $b5$        'Capacity lost to faults; the fault''s duration is the grade.',
        'fact',
        'A confirmed grade says the fault lasted 30 minutes or more while cars waited: charger capacity lost.',
        ARRAY[]::text[])),
  lb AS (SELECT COALESCE(public.ottoq_learning_board()->'experiments', '[]'::jsonb) AS ex,
                public.ottoq_dial_pair_floor() AS dial_floor),$b5$,
    $b6$        'code', q.code, 'tag', q.tag, 'asks', q.asks, 'lever', q.lever,
        'grade_scope', q.grade_scope, 'grade_means', q.grade_means,
        'lever_tests', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'experiment_id', e->>'experiment_id', 'param_key', e->>'param_key',
                  'control', e->'control', 'treatment', e->'treatment',
                  'status', e->>'status', 'outcome', e->>'outcome', 'why', e->>'why', 'run_after', e->'run_after',
                  'primary_metric', e->>'primary_metric', 'primary_better', e->>'primary_better',
                  'first_look_pairs', e->'first_look_pairs',
                  'counted', t.counted, 'treatment_better', t.better, 'treatment_worse', t.worse,
                  'control_mean', t.mean_a, 'treatment_mean', t.mean_b)
                  ORDER BY (e->>'status' = 'active') DESC, e->>'created_at' DESC), '[]'::jsonb)
                  FROM lb CROSS JOIN LATERAL jsonb_array_elements(lb.ex) e
                  CROSS JOIN LATERAL (
                    SELECT count(*) AS counted, count(*) FILTER (WHERE d.gain > 0) AS better,
                           count(*) FILTER (WHERE d.gain < 0) AS worse,
                           round(avg(d.pa), 1) AS mean_a, round(avg(d.pb), 1) AS mean_b
                      FROM (SELECT (c.a->>(e->>'primary_metric'))::numeric AS pa,
                                   (c.b->>(e->>'primary_metric'))::numeric AS pb,
                                   CASE WHEN e->>'primary_better' = 'lower' THEN -1 ELSE 1 END
                                     * ((c.b->>(e->>'primary_metric'))::numeric - (c.a->>(e->>'primary_metric'))::numeric) AS gain
                              FROM public.ottoq_dial_counted_pairs((e->>'experiment_id')::uuid, lb.dial_floor) c) d) t
                 WHERE e->>'param_key' = ANY(q.lever_params)),$b6$,
    $b7$    'contract', 'ottoq_challenger_board/0538',$b7$];
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_def) - length(replace(v_def, p[i], ''))) / length(p[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0538 patch (a%): % matches, expected 1', i, n; END IF;
    v_def := replace(v_def, p[i], r[i]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

COMMENT ON FUNCTION public.ottoq_challenger_board(uuid) IS
  '0536, 0537, 0538. The cockpit''s read of the challenger (0532): its questions in words, this run''s questions open and '
  'graded, each question''s record across runs, and its one-scan sightings (transient, pending) counted apart. A question '
  'is an episode a second scan still saw. Each question says what its grade measures (grade_scope local or fact, '
  'grade_means) and carries the paired tests of its lever with the pairs counted so far (lever_tests). Read-only; the '
  'challenger never changes the engine.';

DO $verify$
DECLARE v_board text;
BEGIN
  -- V1 (comment-stripped): the new keys are built, the tally reads the counted pairs, the contract moved, and the read
  -- stays STABLE and open to the cockpits
  v_board := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_challenger_board(uuid)'::regprocedure),
                                           '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF position('''grade_scope''' IN v_board) = 0 OR position('''grade_means''' IN v_board) = 0
     OR position('''lever_tests''' IN v_board) = 0 OR position('public.ottoq_dial_counted_pairs(' IN v_board) = 0
     OR position('public.ottoq_learning_board()' IN v_board) = 0
     OR position('ottoq_challenger_board/0538' IN v_board) = 0 OR position('s.scans_seen >= 2' IN v_board) = 0 THEN
    RAISE EXCEPTION '0538 V1: the board does not build the new keys, or lost 0537''s rule';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.ottoq_challenger_board(uuid)'::regprocedure
                AND (p.provolatile <> 's' OR NOT has_function_privilege('anon', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION '0538 V1: the board is not STABLE and open to the cockpits';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0538_a_challenger_grade_says_what_it_measures_and_what_tests_its_lever', false, false,
  'One read-only cockpit contract (ottoq_challenger_board) says what each challenger grade measures and carries the '
  'paired tests of its lever with their counted pairs. No table, no tick path, no dial arm.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest operator run, against a direct count in the same statement (the runner can add pairs):
--   Q1 is `local` and its lever tests are exactly the experiments on the two ceilings, each with the counted pairs and
--   the treatment's better/worse tally ottoq_dial_counted_pairs gives directly; Q2 and Q3 are `fact` with no lever
--   tests; every question says what its grade means; 0537's keys are still there.
DO $v3$
DECLARE
  v_msg text; b jsonb; q1 jsonb; q2 jsonb; q3 jsonb; v_expect jsonb; v_got jsonb; v_floor timestamptz;
BEGIN
  BEGIN
    SELECT public.ottoq_challenger_board(NULL), public.ottoq_dial_pair_floor(),
           (SELECT COALESCE(jsonb_object_agg(x.experiment_id::text, jsonb_build_object(
                     'counted', (SELECT count(*) FROM public.ottoq_dial_counted_pairs(x.experiment_id, public.ottoq_dial_pair_floor())),
                     'worse', (SELECT count(*) FROM public.ottoq_dial_counted_pairs(x.experiment_id, public.ottoq_dial_pair_floor()) c
                                WHERE CASE WHEN x.primary_better = 'lower' THEN -1 ELSE 1 END
                                        * ((c.b->>x.primary_metric)::numeric - (c.a->>x.primary_metric)::numeric) < 0))),
                     '{}'::jsonb)
              FROM public.ottoq_dial_experiments x
             WHERE x.param_key IN ('dcfc_target_soc_day', 'dcfc_target_soc_night'))
      INTO b, v_floor, v_expect;
    q1 := b->'questions'->0;
    q2 := b->'questions'->1;
    q3 := b->'questions'->2;
    SELECT COALESCE(jsonb_object_agg(t->>'experiment_id', jsonb_build_object('counted', (t->>'counted')::int,
                                                                           'worse', (t->>'treatment_worse')::int)), '{}'::jsonb)
      INTO v_got FROM jsonb_array_elements(q1->'lever_tests') t;
    IF b->>'contract' <> 'ottoq_challenger_board/0538'
       OR q1->>'code' <> 'charging_above_floor_while_cars_wait' OR q1->>'grade_scope' <> 'local'
       OR q2->>'grade_scope' <> 'fact' OR q3->>'grade_scope' <> 'fact'
       OR COALESCE(length(q1->>'grade_means'), 0) < 40 OR COALESCE(length(q2->>'grade_means'), 0) < 40
       OR COALESCE(length(q3->>'grade_means'), 0) < 40
       OR jsonb_array_length(q2->'lever_tests') <> 0 OR jsonb_array_length(q3->'lever_tests') <> 0
       OR v_got <> v_expect OR NOT (v_expect ? '08262943-e487-4a24-9ddb-0686737bcf98')
       OR (v_got->'08262943-e487-4a24-9ddb-0686737bcf98'->>'counted')::int < 1
       OR q1->'sightings' IS NULL OR q1->'lifetime' IS NULL OR q1->'run' IS NULL THEN
      RAISE EXCEPTION '0538 V3 FAILED: expected lever tests %, got %; board %', v_expect, v_got, left(b::text, 1500);
    END IF;
    RAISE EXCEPTION '0538 V3 PASSED: Q1 local with lever tests % (floor %), Q2 and Q3 fact with none, each says what its grade means',
      v_got, v_floor;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0538 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0538 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: re-run 0537's CREATE FUNCTION body for ottoq_challenger_board(uuid) as CREATE OR REPLACE, and
-- DELETE FROM ottoq_cert_lineage WHERE name = '0538_a_challenger_grade_says_what_it_measures_and_what_tests_its_lever'.

COMMIT;
