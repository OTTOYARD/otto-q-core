-- migration-version: 20260927230859
-- migration-name:    a_car_charging_to_its_target_is_never_a_question
--
-- 0541  **The challenger's first question is retired: a car charging to its own target is never a question.**
--
-- ══ §1 WHY (CLAUDE.md rule 9; G265) ═══════════════════════════════════════════════════════════════════════════════════
--
--   Q1 (`charging_above_floor_while_cars_wait`, 0532) raised an episode for every fast charge still filling a car above
--   the deploy floor while cars waited. Its counterfactual, as the scan writes it: "ending this charge now hands the DCFC
--   to the longest-waiting car". That is the lever rule 9 forbids: a charge ends short only on a charger fault or a
--   vehicle emergency, never to move another car. G265 lists retiring the lever first.
--
--   After 0539 every car charges to 100%, so nearly every fast charge on a busy day passes the deploy floor while cars
--   wait. Q1 would flag most of them, and the cockpits would show each as a question the engine should answer. The
--   next validation run would fill the challenger's panel with a question whose only answer is "no".
--
--   What Q1 measured stays: a car waiting while every charger finishes a full charge is a CAPACITY signal (G257). The
--   report's `taper_tax` and the KPIs keep it. The answers rule 9 names are more chargers, fewer charger faults, a
--   charger freed the moment its car is done, and better ordering of who is served next.
--
-- ══ §2 WHAT THIS CHANGES (the challenger only: read-only to the engine) ══════════════════════════════════════════════
--
--   (a) `ottoq_challenger_scan` no longer opens a Q1 episode. Q2 and Q3 are unchanged, and the ledger keeps every Q1
--       episode already graded, as evidence.
--   (b) `ottoq_challenger_board` keeps Q1 in its list, so its past record stays readable, but says it is retired. It has
--       no lever and no lever tests: its two ceiling dials were retired by 0539 and their experiments abandoned. The
--       cockpits render the board's own sentences (asks, lever, grade_means), so they follow with no release.
--   (c) `ottoq_challenger_report`'s lever sentence stops naming the abandoned experiment.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   The challenger runs on its own cron (765) over live operator and production runs only. No certification or dial
--   arm runs it, and it writes only its own ledger.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0541 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the three functions are the ones measured (2026-09-27 22:45 UTC) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_challenger_scan(uuid)',   'aa95692e9df82945f09c37ea6c3be80b'),
      ('public.ottoq_challenger_board(uuid)',  '15f430fb9d1448bebed381b5a5c249b8'),
      ('public.ottoq_challenger_report(uuid)', 'bc4a41fa9f80bf4852f01cbb514dd198')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0541 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0541_pre', 'function', 'public', f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('ottoq_challenger_scan',   'public.ottoq_challenger_scan(uuid)'),
               ('ottoq_challenger_board',  'public.ottoq_challenger_board(uuid)'),
               ('ottoq_challenger_report', 'public.ottoq_challenger_report(uuid)')) AS f(obj, sig);

-- ── (a)-(c): each anchor must match exactly once ──
DO $patch$
DECLARE
  r record; v_def text; v_cur text := ''; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- (a) the scan opens no Q1 episode
    (1, 'public.ottoq_challenger_scan(uuid)', 're',
     $a$    -- Q1: a DCFC charging a car at or above the deploy floor while cars wait\n.*?      v_q1 := v_q1 \+ 1;\n    END LOOP;\n$a$,
     $b$    -- 0541 (CLAUDE.md rule 9): Q1 is retired. It opened an episode for every fast charge still filling a car above the
    -- deploy floor while cars waited, as if ending that charge were a decision the engine missed. A car charging to its
    -- target is never a question: a charge ends short only on a charger fault or a vehicle emergency. The wait it
    -- measured is a capacity signal, kept in the report's taper_tax and the KPIs. v_q1 stays 0.
$b$, 1),
    -- (b) the board says Q1 is retired, with no lever
    (2, 'public.ottoq_challenger_board(uuid)', 'lit',
     $a$'A fast charger is still filling a car that is already above the deploy floor while other cars wait for a charger.',$a$,
     $b$'Retired 2026-09-27 (rule 9). It asked whether a fast charger was still filling a car above the deploy floor while other cars waited. A car charging to its own target is never a question, so no new episode is raised.',$b$, 1),
    (3, 'public.ottoq_challenger_board(uuid)', 'lit',
     $a$'No verb in the engine yet (a charge is not ended early). Tested as dials: the fast-charge ceilings by day and by night.',$a$,
     $b$'None. Ending a charge early is never a lever (rule 9). Cars waiting while chargers finish full charges is a capacity signal: more chargers, fewer faults, a charger freed the moment its car is done, better ordering of who is served next.',$b$, 1),
    (4, 'public.ottoq_challenger_board(uuid)', 'lit',
     $a$'A confirmed grade says the car charged on and the longest waiter waited on, 5 minutes or more each after the question was raised. It does not say that ending the charge would have helped the day: the paired tests of the lever answer that.',$a$,
     $b$'Its earlier grades say only that the car charged on while the longest waiter waited on. They never meant the charge should have ended.',$b$, 1),
    (5, 'public.ottoq_challenger_board(uuid)', 'lit',
     $a$ARRAY['dcfc_target_soc_day', 'dcfc_target_soc_night']),$a$,
     $b$ARRAY[]::text[]),  -- 0541: its two ceiling dials were retired by 0539 and their experiments abandoned (G265)$b$, 1),
    -- (c) the report names no lever for Q1
    (6, 'public.ottoq_challenger_report(uuid)', 're',
     $a$    'lever', 'Q1 has no verb in the engine \(a charge cannot be ended early\); its lever is the dial experiment '\n\s+'08262943 \(dcfc_target_soc_day 90 against 85, primary unmet_demand_car_hours\) and, next, a queue-aware '\n\s+'charge target\. No question is a proposer yet: each earns a seat once its hit rate and grades are measured\.'\)$a$,
     $b$    -- 0541 (CLAUDE.md rule 9): Q1 is retired and has no lever. This named the dial experiment that tested stopping
    -- fast charges at 85%, abandoned under rule 9.
    'lever', 'Q1 is retired (rule 9): ending a charge early is never a lever. The taper tax above is a capacity signal: '
             'cars waiting while chargers finish full charges calls for more chargers, fewer faults and better ordering. '
             'No question is a proposer yet: each earns a seat once its hit rate and grades are measured.')$b$, 1)
  ) AS t(k, sig, kind, anchor, repl, times)
  ORDER BY sig, k LOOP
    IF r.sig <> v_cur THEN
      IF v_cur <> '' THEN EXECUTE v_def; END IF;
      v_cur := r.sig;
      v_def := pg_get_functiondef(r.sig::regprocedure);
    END IF;
    IF r.kind = 'lit' THEN
      n := (length(v_def) - length(replace(v_def, r.anchor, ''))) / length(r.anchor);
      IF n <> r.times THEN RAISE EXCEPTION '0541 patch %: the anchor matches % times in %, not %', r.k, n, r.sig, r.times; END IF;
      v_def := replace(v_def, r.anchor, r.repl);
    ELSE
      n := (SELECT count(*) FROM regexp_matches(v_def, r.anchor, 'g'));
      IF n <> r.times THEN RAISE EXCEPTION '0541 patch %: the pattern matches % times in %, not %', r.k, n, r.sig, r.times; END IF;
      v_def := regexp_replace(v_def, r.anchor, r.repl);
    END IF;
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ── V1 (comment-stripped) ──
DO $verify$
DECLARE v_scan text; v_board text; v_report text;
BEGIN
  v_scan := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_challenger_scan(uuid)'::regprocedure),
                                          '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_board := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_challenger_board(uuid)'::regprocedure),
                                           '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_report := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_challenger_report(uuid)'::regprocedure),
                                            '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF position('charging_above_floor_while_cars_wait' IN v_scan) > 0
     OR position('charger_offerable_while_cars_wait' IN v_scan) = 0 OR position('charger_faulted_while_cars_wait' IN v_scan) = 0 THEN
    RAISE EXCEPTION '0541 V1: the scan still opens Q1 episodes, or lost Q2 or Q3';
  END IF;
  IF position('dcfc_target_soc' IN v_board) > 0 OR position('Retired 2026-09-27 (rule 9)' IN v_board) = 0
     OR position('ottoq_challenger_board/0538' IN v_board) = 0 OR position('s.scans_seen >= 2' IN v_board) = 0 THEN
    RAISE EXCEPTION '0541 V1: the board does not say Q1 is retired, or lost 0537/0538''s keys';
  END IF;
  IF position('08262943' IN v_report) > 0 OR position('Q1 is retired (rule 9)' IN v_report) = 0 THEN
    RAISE EXCEPTION '0541 V1: the report still names the abandoned experiment as Q1''s lever';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid IN ('public.ottoq_challenger_board(uuid)'::regprocedure,
                                                      'public.ottoq_challenger_report(uuid)'::regprocedure)
                AND p.provolatile <> 's') THEN
    RAISE EXCEPTION '0541 V1: a cockpit read is no longer STABLE';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0541_a_car_charging_to_its_target_is_never_a_question', false, false,
  'Rule 9: the challenger''s Q1 (a fast charger filling a car above the deploy floor while cars wait) is retired; the scan '
  'opens no Q1 episode and the board and report say so. The challenger runs on its own cron over live operator and '
  'production runs only; no certification or dial arm runs it.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest operator run (ad106e55): the board lists Q1 retired, with no lever tests and its past
-- record intact; Q2 and Q3 are as they were; the report's lever is the retired sentence.
DO $v3$
DECLARE v_msg text; b jsonb; q1 jsonb; q2 jsonb; q3 jsonb; rep jsonb;
BEGIN
  BEGIN
    b := public.ottoq_challenger_board(NULL);
    SELECT e INTO q1 FROM jsonb_array_elements(b->'questions') e WHERE e->>'code' = 'charging_above_floor_while_cars_wait';
    SELECT e INTO q2 FROM jsonb_array_elements(b->'questions') e WHERE e->>'code' = 'charger_offerable_while_cars_wait';
    SELECT e INTO q3 FROM jsonb_array_elements(b->'questions') e WHERE e->>'code' = 'charger_faulted_while_cars_wait';
    IF q1 IS NULL OR q1->>'asks' NOT LIKE 'Retired 2026-09-27 (rule 9)%' OR q1->>'lever' NOT LIKE 'None. Ending a charge early%'
       OR jsonb_array_length(COALESCE(q1->'lever_tests', '[]'::jsonb)) <> 0 THEN
      RAISE EXCEPTION '0541 V3 FAILED: Q1 reads % / % with % lever tests', q1->>'asks', q1->>'lever', q1->'lever_tests';
    END IF;
    IF q2->>'grade_scope' IS DISTINCT FROM 'fact' OR q3->>'grade_scope' IS DISTINCT FROM 'fact'
       OR jsonb_array_length(COALESCE(q2->'lever_tests', '[]'::jsonb)) <> 0 THEN
      RAISE EXCEPTION '0541 V3 FAILED: Q2 or Q3 changed: % / %', q2->>'grade_scope', q3->>'grade_scope';
    END IF;
    rep := public.ottoq_challenger_report((b->'run'->>'sim_run_id')::uuid);
    IF rep->>'lever' NOT LIKE 'Q1 is retired (rule 9)%' THEN
      RAISE EXCEPTION '0541 V3 FAILED: the report''s lever reads %', rep->>'lever';
    END IF;
    RAISE EXCEPTION '0541 V3 PASSED: on run %, Q1 reads "%" with no lever tests; Q2 and Q3 are unchanged; the report says "%"',
      b->'run'->>'sim_run_id', left(q1->>'asks', 60), left(rep->>'lever', 60);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0541 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0541 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the three `definition`s in ottoq_schema_snapshots WHERE label = '0541_pre' as they are.
COMMIT;
