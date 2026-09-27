-- migration-version: 20260927194349
-- migration-name:    a_question_is_one_the_next_scan_still_sees
--
-- 0537  **The cockpits show a challenger question once a second scan still sees it. A sighting the next scan no longer
--       sees is counted, never listed.**
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The first live operator run since 0536 (`ad106e55`, started 2:14 PM CT, busy_day from 5:03 AM sim) made the
--   decision stream a third challenger rows within its first 20 sim-minutes: 61 of 222. 58 of those 61 were Q2 (a free
--   charger while a car waits), all from ONE scan, the run's first at 5:14 AM sim:
--     - that scan landed while the engine was still catching up the run's opening ticks, with the dealt cars waiting at
--       the gate and 29 chargers not yet assigned;
--     - by the next scan, 9 sim-minutes later, every one had been assigned. All 29 closed after one scan, graded
--       `refuted`.
--   A condition the next scan no longer sees was the engine's ordinary reaction time, not a missed decision. Shown, it
--   buries the decisions the stream exists to show. Counted in the record, it would open Q2's hit rate at 0 of 29 on a
--   start-up artifact.
--
--   The scan runs once a real minute, so its spacing in sim time follows playback (9 sim-minutes at 8x, 1 at 1x). Two
--   consecutive sightings mean the condition outlived at least one decide tick at any speed.
--
-- ══ §2 WHAT THIS CHANGES (read-only; the ledger and the scan are untouched) ═══════════════════════════════════════════
--
--   (a) `ottoq_challenger_board`: an episode is a question once `scans_seen >= 2`. The run's counts, the open list, the
--       graded list and each question's lifetime record count questions only. Each question gains `sightings`: how
--       many one-scan sightings closed (`transient`) and how many are waiting on their second scan (`pending`).
--   (b) `ottoq_activity_feed_v2`: a flag row and a grade row only for a question. The flag keeps its first sighting's
--       time, so it lands where the question began.
--   The ledger keeps every sighting, with the grade the close gave it: this is a read rule, so nothing is rewritten and
--   the rule can be changed later without losing evidence.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   Two read-only functions, neither on a tick path nor read by a dial arm.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0537 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the two functions are 0536's, as measured (md5 of prosrc, 2026-09-27 19:45 UTC) ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_challenger_board(uuid)'::regprocedure)
       <> '4c195033e83fa03a59aab5882c7a0bc6' THEN
    RAISE EXCEPTION '0537 P2: ottoq_challenger_board is not 0536''s';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_activity_feed_v2(uuid,integer,uuid,boolean,integer)'::regprocedure)
       <> '4977e6ad03bd3064d5bf648a118f5bb5' THEN
    RAISE EXCEPTION '0537 P2: ottoq_activity_feed_v2 is not 0536''s';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'ottoq_challenger_findings' AND column_name = 'scans_seen') THEN
    RAISE EXCEPTION '0537 P2: the ledger has no scans_seen';
  END IF;
END $premises$;

-- ── (a), (b): each patch must match exactly once ──
DO $patch$
DECLARE
  v_def text;
  n int;
  p text[];
  r text[];
  i int;
BEGIN
  -- (a) the board
  v_def := pg_get_functiondef('public.ottoq_challenger_board(uuid)'::regprocedure);
  p := ARRAY[
    $a1$/* The cockpit's read of the challenger (0532):$a1$,
    $a2$  f AS (SELECT fx.* FROM public.ottoq_challenger_findings fx WHERE fx.sim_run_id = (SELECT sim_run_id FROM r))$a2$,
    $a3$    'contract', 'ottoq_challenger_board/0536',$a3$,
    $a4$        'lifetime', (SELECT jsonb_build_object($a4$,
    $a5$WHERE a.question = q.code AND a.depot_id = COALESCE((SELECT depot_id FROM r), a.depot_id)))$a5$];
  r := ARRAY[
    $b1$/* 0537: an episode is a question once a second scan still sees it; a sighting the next scan no longer sees is
     counted under `sightings` and never listed. The cockpit's read of the challenger (0532):$b1$,
    $b2$  seen AS (SELECT fx.* FROM public.ottoq_challenger_findings fx WHERE fx.sim_run_id = (SELECT sim_run_id FROM r)),
  f AS (SELECT s.* FROM seen s WHERE s.scans_seen >= 2)$b2$,
    $b3$    'contract', 'ottoq_challenger_board/0537',$b3$,
    $b4$        'sightings', (SELECT jsonb_build_object(
                  'transient', count(*) FILTER (WHERE s.scans_seen < 2 AND s.status = 'closed'),
                  'pending', count(*) FILTER (WHERE s.scans_seen < 2 AND s.status = 'open'))
                  FROM seen s WHERE s.question = q.code),
        'lifetime', (SELECT jsonb_build_object($b4$,
    $b5$WHERE a.question = q.code AND a.scans_seen >= 2 AND a.depot_id = COALESCE((SELECT depot_id FROM r), a.depot_id)))$b5$];
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_def) - length(replace(v_def, p[i], ''))) / length(p[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0537 patch (a%): % matches, expected 1', i, n; END IF;
    v_def := replace(v_def, p[i], r[i]);
  END LOOP;
  EXECUTE v_def;

  -- (b) the feed
  v_def := pg_get_functiondef('public.ottoq_activity_feed_v2(uuid,integer,uuid,boolean,integer)'::regprocedure);
  p := ARRAY[
    $c1$     when the challenger flags an episode (at its first sight; standing while it is open) and one when it grades it (at
     its close).$c1$,
    $c2$         WHERE f.sim_run_id = p_sim_run_id
        UNION ALL$c2$,
    $c3$WHERE f.sim_run_id = p_sim_run_id AND f.status = 'closed' AND f.closed_sim IS NOT NULL) c$c3$];
  r := ARRAY[
    $d1$     when the challenger flags an episode and one when it grades it (at its close). 0537: only an episode a second
     scan still saw, a question; the flag keeps its first sighting's time.$d1$,
    $d2$         WHERE f.sim_run_id = p_sim_run_id AND f.scans_seen >= 2
        UNION ALL$d2$,
    $d3$WHERE f.sim_run_id = p_sim_run_id AND f.status = 'closed' AND f.closed_sim IS NOT NULL AND f.scans_seen >= 2) c$d3$];
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_def) - length(replace(v_def, p[i], ''))) / length(p[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0537 patch (b%): % matches, expected 1', i, n; END IF;
    v_def := replace(v_def, p[i], r[i]);
  END LOOP;
  EXECUTE v_def;
END $patch$;

COMMENT ON FUNCTION public.ottoq_challenger_board(uuid) IS
  '0536, 0537. The cockpit''s read of the challenger (0532): its questions in words, this run''s questions open and '
  'graded, each question''s record across runs, and its one-scan sightings (transient, pending) counted apart. A question '
  'is an episode a second scan still saw. Read-only; the challenger never changes the engine.';
COMMENT ON FUNCTION public.ottoq_activity_feed_v2(uuid, integer, uuid, boolean, integer) IS
  '0536, 0537. ottoq_activity_feed''s rows, unchanged, plus the challenger''s flags and grades in the same shape (action '
  'challenger_flag / challenger_grade, no decision_seq, rationale.changes_the_engine = false), for questions only: '
  'episodes a second scan still saw.';

DO $verify$
DECLARE v_board text; v_feed text;
BEGIN
  -- V1 (comment-stripped): both read the rule, the board counts sightings apart, and both stay STABLE and open
  v_board := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_challenger_board(uuid)'::regprocedure),
                                           '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  v_feed := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_activity_feed_v2(uuid,integer,uuid,boolean,integer)'::regprocedure),
                                          '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF position('s.scans_seen >= 2' IN v_board) = 0 OR position('a.scans_seen >= 2' IN v_board) = 0
     OR position('''sightings''' IN v_board) = 0 OR position('ottoq_challenger_board/0537' IN v_board) = 0 THEN
    RAISE EXCEPTION '0537 V1: the board does not read the rule';
  END IF;
  IF (length(v_feed) - length(replace(v_feed, 'f.scans_seen >= 2', ''))) / length('f.scans_seen >= 2') <> 2 THEN
    RAISE EXCEPTION '0537 V1: the feed does not filter both the flags and the grades';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE p.oid IN ('public.ottoq_challenger_board(uuid)'::regprocedure,
                              'public.ottoq_activity_feed_v2(uuid,integer,uuid,boolean,integer)'::regprocedure)
                AND (p.provolatile <> 's' OR NOT has_function_privilege('anon', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION '0537 V1: a read is not STABLE and open to the cockpits';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0537_a_question_is_one_the_next_scan_still_sees', false, false,
  'Two read-only cockpit contracts (ottoq_challenger_board, ottoq_activity_feed_v2) show a challenger episode only once '
  'a second scan still saw it; one-scan sightings are counted apart. No table, no tick path, no dial arm.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest completed twin-depot run with no challenger episodes of its own:
--   a Q2 sighting closed after one scan (refuted), a Q2 question closed after two (confirmed), a Q1 sighting still on
--   its first scan and a Q1 question open on its third. The board must count one Q2 question (confirmed, not refuted),
--   one transient and one pending, list only the two questions, and exclude the one-scan refutation from the lifetime
--   record; the feed must add exactly 2 flags and 1 grade to the base rows.
DO $v3$
DECLARE
  v_msg text; b jsonb; v_run uuid; v_base int; v_v2 int; v_flags int; v_grades int; q1 jsonb; q2 jsonb;
  v_refuted_questions int; v_refuted_all int;
BEGIN
  BEGIN
    SELECT s.sim_run_id INTO v_run FROM public.ottoq_sim_runs s
     WHERE s.status = 'completed' AND s.depot_id = '11111111-1111-1111-1111-111111111111'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_challenger_findings f WHERE f.sim_run_id = s.sim_run_id)
     ORDER BY s.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0537 V3 FAILED: no completed run to plant on'; END IF;
    INSERT INTO public.ottoq_challenger_findings (sim_run_id, depot_id, question, entity_type, entity_id, episode_key,
                                                  first_seen_sim, last_seen_sim, scans_seen, evidence, counterfactual,
                                                  scan_version, status, closed_sim, grade, realized)
    VALUES
      (v_run, '11111111-1111-1111-1111-111111111111', 'charger_offerable_while_cars_wait', 'stall', gen_random_uuid(),
       'v3-q2-transient', '2026-09-01 13:10:00+00', '2026-09-01 13:10:00+00', 1,
       '{"stall": "NASH-L2-07", "cars_waiting": 4, "longest_wait_min": 9}'::jsonb,
       '{"claim": "a free charger and a waiting car: a missed assignment"}'::jsonb, '0537_v3',
       'closed', '2026-09-01 13:19:00+00', 'refuted', '{}'::jsonb),
      (v_run, '11111111-1111-1111-1111-111111111111', 'charger_offerable_while_cars_wait', 'stall', gen_random_uuid(),
       'v3-q2-question', '2026-09-01 14:00:00+00', '2026-09-01 14:09:00+00', 2,
       '{"stall": "NASH-L2-01", "cars_waiting": 3, "longest_wait_min": 12}'::jsonb,
       '{"claim": "a free charger and a waiting car: a missed assignment"}'::jsonb, '0537_v3',
       'closed', '2026-09-01 14:18:00+00', 'confirmed', '{"free_for_min_at_least": 9}'::jsonb),
      (v_run, '11111111-1111-1111-1111-111111111111', 'charging_above_floor_while_cars_wait', 'charge_session', gen_random_uuid(),
       'v3-q1-pending', '2026-09-01 15:00:00+00', '2026-09-01 15:00:00+00', 1,
       '{"stall": "NASH-DC-05", "car": "Tesla-AV-020", "car_soc": 83, "cars_waiting": 2}'::jsonb,
       '{"claim": "ending this charge now hands the DCFC to the longest-waiting car"}'::jsonb, '0537_v3',
       'open', NULL, NULL, NULL),
      (v_run, '11111111-1111-1111-1111-111111111111', 'charging_above_floor_while_cars_wait', 'charge_session', gen_random_uuid(),
       'v3-q1-question', '2026-09-01 15:00:00+00', '2026-09-01 15:18:00+00', 3,
       '{"stall": "NASH-DC-03", "car": "Waymo-AV-012", "car_soc": 86, "cars_waiting": 5}'::jsonb,
       '{"claim": "ending this charge now hands the DCFC to the longest-waiting car"}'::jsonb, '0537_v3',
       'open', NULL, NULL, NULL);

    -- the board and the counts it must agree with, in one statement so they read one snapshot (the scanner keeps writing)
    SELECT public.ottoq_challenger_board(v_run),
           (SELECT count(*) FROM public.ottoq_challenger_findings a
             WHERE a.question = 'charger_offerable_while_cars_wait' AND a.depot_id = '11111111-1111-1111-1111-111111111111'
               AND a.grade = 'refuted' AND a.scans_seen >= 2),
           (SELECT count(*) FROM public.ottoq_challenger_findings a
             WHERE a.question = 'charger_offerable_while_cars_wait' AND a.depot_id = '11111111-1111-1111-1111-111111111111'
               AND a.grade = 'refuted')
      INTO b, v_refuted_questions, v_refuted_all;
    q1 := b->'questions'->0;
    q2 := b->'questions'->1;
    IF b->>'contract' <> 'ottoq_challenger_board/0537'
       OR (q2->'run'->>'episodes')::int <> 1 OR (q2->'run'->>'confirmed')::int <> 1 OR (q2->'run'->>'refuted')::int <> 0
       OR (q2->'sightings'->>'transient')::int <> 1 OR (q2->'sightings'->>'pending')::int <> 0
       OR (q1->'run'->>'episodes')::int <> 1 OR (q1->'run'->>'open')::int <> 1 OR (q1->'sightings'->>'pending')::int <> 1
       OR jsonb_array_length(b->'open') <> 1 OR b->'open'->0->>'stall' <> 'NASH-DC-03'
       OR jsonb_array_length(b->'graded') <> 1 OR b->'graded'->0->>'stall' <> 'NASH-L2-01'
       OR (q2->'lifetime'->>'refuted')::int <> v_refuted_questions OR v_refuted_all <= v_refuted_questions THEN
      RAISE EXCEPTION '0537 V3 FAILED (a): %', left(b::text, 2000);
    END IF;

    SELECT count(*) INTO v_base FROM public.ottoq_activity_feed(v_run, 200, NULL, true, 240);
    SELECT count(*), count(*) FILTER (WHERE action = 'challenger_flag'), count(*) FILTER (WHERE action = 'challenger_grade')
      INTO v_v2, v_flags, v_grades
      FROM public.ottoq_activity_feed_v2(v_run, 200, NULL, true, 240);
    IF v_v2 <> v_base + 3 OR v_flags <> 2 OR v_grades <> 1
       OR EXISTS (SELECT 1 FROM public.ottoq_activity_feed_v2(v_run, 200, NULL, true, 240)
                   WHERE action LIKE 'challenger%' AND target IN ('NASH-L2-07', 'NASH-DC-05')) THEN
      RAISE EXCEPTION '0537 V3 FAILED (b): base % rows, v2 % (flags %, grades %)', v_base, v_v2, v_flags, v_grades;
    END IF;

    RAISE EXCEPTION '0537 V3 PASSED: on run % the board counts 1 Q2 question (confirmed), 1 transient and 1 pending, lists only the two questions and keeps one-scan refutations out of the lifetime record (% of % refuted Q2 episodes are questions); the feed adds 2 flags and 1 grade to its % base rows',
      left(v_run::text, 8), v_refuted_questions, v_refuted_all, v_base;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0537 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0537 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: re-run 0536's CREATE FUNCTION bodies for ottoq_challenger_board(uuid) and ottoq_activity_feed_v2 as
-- CREATE OR REPLACE, and DELETE FROM ottoq_cert_lineage WHERE name = '0537_a_question_is_one_the_next_scan_still_sees'.

COMMIT;
