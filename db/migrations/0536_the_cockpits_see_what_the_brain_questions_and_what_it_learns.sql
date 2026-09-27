-- migration-version: 20260927180246
-- migration-name:    the_cockpits_see_what_the_brain_questions_and_what_it_learns
--
-- 0536  **The second loop, made visible. The challenger's questions and grades, and the learner's experiments and
--       verdicts, get their own read contracts for the cockpits. The challenger's flags and grades join the live decision
--       stream beside the engine's decisions.**
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-09-27: "Make sure any of the additions from a Challenger or optimization standpoint are visible both in
--   the twin and pulse app UI's. I just want to make sure visually we are still seeing what decisions are being made
--   and there is a transparency layer to our brain and how the engine fires."
--   Everything 0532-0535 added lives only in tables:
--     - the challenger's questions, its open episodes, its hindsight grades (`ottoq_challenger_findings`);
--     - the learner's pairs, the read witness, the verdict and the promoter (`ottoq_dial_*`).
--   The cockpits read through anon RPCs (`ottoq_intelligence_stack`, `ottoq_activity_feed`), and the ledgers are closed
--   to anon (0532 REVOKE). Nothing a viewer can open shows any of it.
--
-- ══ §2 WHAT THIS ADDS (read-only; no table, no tick path) ═════════════════════════════════════════════════════════════
--
--   (a) `ottoq_challenger_board(run)`: one call for the cockpit, about one run (with none named: the live operator or
--       production run, else the most recent one). It returns:
--         - the three questions in words, each with its lever;
--         - this run's episodes, open and graded by grade;
--         - each question's record across every run at the depot: confirmed of graded, the hit rate;
--         - the open episodes and the recent graded ones, in the evidence's own names (stall codes, car names);
--         - whether the scanner is on. It never changes the engine, and the board says so.
--   (b) `ottoq_learning_board()`: every experiment active or ended in the last week. For each:
--         - its dial, control and treatment, and its primary;
--         - pairs recorded, counted, invalid and stale;
--         - the verdict: the runner's own function, called and not recomputed, for an active experiment; the stored one
--           for an ended experiment;
--         - the read witness (0533), crashed pairs (0535) and the last pair (primary, arms moved, an arm's error);
--         - run_after (0534).
--       Beside the experiments: the night window's own cron jobs, and the last ten promotions.
--   (c) `ottoq_activity_feed_v2(...)`: every row of `ottoq_activity_feed`, unchanged, plus the challenger's rows in the
--       same shape:
--         - a flag at an episode's first sight (standing while open);
--         - a grade at its close.
--       They carry action `challenger_flag` / `challenger_grade`, engine `challenger Q1/Q2/Q3`, the stall as target, the
--       claim as reason and no decision_seq. They are not decisions and the engine never acted on them; the rationale
--       says `changes_the_engine: false`. The feed a cockpit already polls can switch to v2 and change nothing else.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   Three new read-only functions; nothing on a tick path, in a pair or in the canon.

BEGIN;

-- ── P2: the contracts these read, as measured ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_challenger_board(uuid)') IS NOT NULL
     OR to_regprocedure('public.ottoq_learning_board()') IS NOT NULL
     OR to_regprocedure('public.ottoq_activity_feed_v2(uuid,integer,uuid,boolean,integer)') IS NOT NULL THEN
    RAISE EXCEPTION '0536 P2: a board or the feed already exists';
  END IF;
  IF pg_get_function_result('public.ottoq_activity_feed(uuid,integer,uuid,boolean,integer)'::regprocedure)
     <> 'TABLE(occurred_at timestamp with time zone, vehicle_id uuid, display_name text, action text, engine text, target text, outcome text, rationale jsonb, reason text, decision_seq bigint, tick_seq bigint, held_ticks integer, last_at timestamp with time zone, standing boolean)' THEN
    RAISE EXCEPTION '0536 P2: the activity feed''s row is not the shape measured';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_dial_experiments' AND column_name = 'run_after')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_dial_pair_ledger' AND column_name = 'dial_read_a') THEN
    RAISE EXCEPTION '0536 P2: 0533 and 0534 must be applied first';
  END IF;
END $premises$;

-- ── (a), (b), (c) ──
CREATE FUNCTION public.ottoq_challenger_board(p_sim_run_id uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  /* The cockpit's read of the challenger (0532): the questions it asks of a live run, what it has open right now, what
     it graded, and each question's record across every run it has asked it of. Read-only. With no run named, the live
     operator or production run, else the most recent one. */
  WITH r AS (
    SELECT s.sim_run_id, s.status, s.run_by, s.depot_id, s.sim_clock_start, s.sim_clock_current, s.started_at, s.ended_at
      FROM public.ottoq_sim_runs s
     WHERE s.sim_run_id = COALESCE(p_sim_run_id,
             (SELECT s2.sim_run_id FROM public.ottoq_sim_runs s2
               WHERE s2.run_by IN ('operator_demo', 'production_live')
               ORDER BY (s2.status IN ('running', 'paused')) DESC, s2.started_at DESC LIMIT 1))),
  q(ord, code, tag, asks, lever) AS (VALUES
    (1, 'charging_above_floor_while_cars_wait', 'Q1',
        'A fast charger is still filling a car that is already above the deploy floor while other cars wait for a charger.',
        'No verb in the engine yet (a charge is not ended early). Tested as a dial: dcfc_target_soc_day, experiment 08262943.'),
    (2, 'charger_offerable_while_cars_wait', 'Q2',
        'A charger is free by every gate (pointer, calendar, session, charger state) while a car has waited five minutes or more.',
        'A missed assignment. Graded before it earns a proposer seat.'),
    (3, 'charger_faulted_while_cars_wait', 'Q3',
        'A charger is faulted while cars wait for a charger.',
        'Capacity lost to faults; the fault''s duration is the grade.')),
  f AS (SELECT fx.* FROM public.ottoq_challenger_findings fx WHERE fx.sim_run_id = (SELECT sim_run_id FROM r))
  SELECT jsonb_build_object(
    'contract', 'ottoq_challenger_board/0536',
    'run', (SELECT jsonb_build_object('sim_run_id', r.sim_run_id, 'status', r.status, 'run_by', r.run_by,
                                      'sim_clock', r.sim_clock_current, 'sim_start', r.sim_clock_start,
                                      'started_at', r.started_at, 'ended_at', r.ended_at) FROM r),
    'scanner', jsonb_build_object(
       'job', 'challenger_scan', 'cadence', 'every minute, live operator and production runs',
       'active', (SELECT j.active FROM cron.job j WHERE j.jobname = 'challenger_scan'),
       'changes_the_engine', false),
    'questions', (SELECT jsonb_agg(jsonb_build_object(
        'code', q.code, 'tag', q.tag, 'asks', q.asks, 'lever', q.lever,
        'run', (SELECT jsonb_build_object(
                  'episodes', count(*), 'open', count(*) FILTER (WHERE f.status = 'open'),
                  'confirmed', count(*) FILTER (WHERE f.grade = 'confirmed'),
                  'refuted', count(*) FILTER (WHERE f.grade = 'refuted'),
                  'inconclusive', count(*) FILTER (WHERE f.grade = 'inconclusive'),
                  'claimed_saving_min', round(COALESCE(sum((f.realized->>'saving_min')::numeric), 0), 1))
                  FROM f WHERE f.question = q.code),
        'lifetime', (SELECT jsonb_build_object(
                  'runs', count(DISTINCT a.sim_run_id), 'episodes', count(*),
                  'graded', count(*) FILTER (WHERE a.grade IS NOT NULL),
                  'confirmed', count(*) FILTER (WHERE a.grade = 'confirmed'),
                  'refuted', count(*) FILTER (WHERE a.grade = 'refuted'),
                  'hit_rate', round(count(*) FILTER (WHERE a.grade = 'confirmed')::numeric
                                    / NULLIF(count(*) FILTER (WHERE a.grade IN ('confirmed', 'refuted')), 0), 3))
                  FROM public.ottoq_challenger_findings a
                 WHERE a.question = q.code AND a.depot_id = COALESCE((SELECT depot_id FROM r), a.depot_id)))
      ORDER BY q.ord) FROM q),
    'open', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'last_seen_sim') DESC) FROM (
        SELECT jsonb_build_object(
                 'finding_id', f.finding_id, 'tag', q.tag, 'question', f.question,
                 'stall', f.evidence->>'stall', 'car', f.evidence->>'car', 'car_soc', f.evidence->'car_soc',
                 'cars_waiting', f.evidence->'cars_waiting', 'longest_wait_min', f.evidence->'longest_wait_min',
                 'peak', f.peak, 'claim', f.counterfactual->>'claim', 'beneficiary', f.counterfactual->>'beneficiary',
                 'first_seen_sim', f.first_seen_sim, 'last_seen_sim', f.last_seen_sim, 'scans_seen', f.scans_seen) AS x
          FROM f JOIN q ON q.code = f.question
         WHERE f.status = 'open' ORDER BY f.last_seen_sim DESC LIMIT 25) z), '[]'::jsonb),
    'graded', COALESCE((SELECT jsonb_agg(x ORDER BY (x->>'closed_sim') DESC) FROM (
        SELECT jsonb_build_object(
                 'finding_id', f.finding_id, 'tag', q.tag, 'question', f.question, 'grade', f.grade,
                 'stall', f.evidence->>'stall', 'car', f.evidence->>'car',
                 'claim', f.counterfactual->>'claim', 'beneficiary', f.counterfactual->>'beneficiary',
                 'realized', f.realized, 'first_seen_sim', f.first_seen_sim, 'closed_sim', f.closed_sim,
                 'scans_seen', f.scans_seen) AS x
          FROM f JOIN q ON q.code = f.question
         WHERE f.status = 'closed' ORDER BY f.closed_sim DESC NULLS LAST LIMIT 25) z), '[]'::jsonb))
$function$;

CREATE FUNCTION public.ottoq_learning_board()
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
/* The cockpit's read of the learner (0439 onward): every dial experiment that is active or ended in the last week, its
   pairs, the arms' read witness (0533), its verdict as the runner will judge it, the night window, and the promotions.
   Read-only: the verdict is ottoq_dial_experiment_verdict's own, called, never recomputed here. */
DECLARE
  v_floor timestamptz := public.ottoq_dial_pair_floor();
  v_exps jsonb := '[]'::jsonb; x record; v jsonb; v_last jsonb;
BEGIN
  FOR x IN SELECT e.* FROM public.ottoq_dial_experiments e
            WHERE e.status = 'active' OR e.concluded_at >= now() - interval '7 days'
            ORDER BY (e.status = 'active') DESC, e.created_at DESC LOOP
    -- an active experiment is judged now, as the runner will judge it; an ended one shows the verdict it ended on
    v := CASE WHEN x.status = 'active' THEN public.ottoq_dial_experiment_verdict(x.experiment_id)
              ELSE COALESCE(x.verdict, '{}'::jsonb) END;
    SELECT jsonb_build_object('pair_id', l.pair_id, 'ran_at', l.ran_at, 'complete', l.complete,
                              'world_identical', l.world_identical, 'both_paid_shield', l.both_paid_shield,
                              'moved', l.moved, 'dial_read_control', l.dial_read_a, 'dial_read_treatment', l.dial_read_b,
                              'control', l.metrics_a->x.primary_metric, 'treatment', l.metrics_b->x.primary_metric,
                              'wall_s', l.wall_s,
                              'arm_error', COALESCE(l.metrics_b->'arm_error'->>'error', l.metrics_a->'arm_error'->>'error'))
      INTO v_last
      FROM public.ottoq_dial_pair_ledger l
     WHERE l.experiment_id = x.experiment_id ORDER BY l.pair_id DESC LIMIT 1;
    v_exps := v_exps || jsonb_build_array(jsonb_build_object(
      'experiment_id', x.experiment_id, 'param_key', x.param_key, 'control', x.control_value, 'treatment', x.treatment_value,
      'scenario', x.scenario, 'ticks', x.ticks, 'sim_min_per_tick', x.sim_min_per_tick,
      'primary_metric', x.primary_metric, 'primary_better', x.primary_better,
      'first_look_pairs', x.first_look_pairs, 'final_look_pairs', x.final_look_pairs,
      'status', x.status, 'run_after', x.run_after, 'created_at', x.created_at, 'concluded_at', x.concluded_at,
      'hypothesis', x.hypothesis,
      'pairs', v->'pairs', 'outcome', v->>'outcome', 'terminal', (v->>'terminal')::boolean, 'why', v->>'why',
      'primary', v->'primary', 'dial_reads', v->'dial_reads', 'breached', v->'guardrails'->'breached',
      'promotion', x.verdict->'promotion', 'last_pair', v_last));
  END LOOP;

  RETURN jsonb_build_object(
    'contract', 'ottoq_learning_board/0536',
    'dial_floor', v_floor,
    'runner', jsonb_build_object(
      'enabled', COALESCE(public.ottoq_policy_get(NULL, 'dial_experiment_runner_enabled', 0), 0) >= 1,
      'cadence', 'one pair per call, every 10 minutes, only between runs and with the canon certified',
      'window_jobs', COALESCE((SELECT jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule_utc', j.schedule, 'active', j.active)
                                                ORDER BY j.jobname)
                                 FROM cron.job j WHERE j.jobname LIKE 'ottoq_dial_window_%'), '[]'::jsonb)),
    'experiments', v_exps,
    'promotions', COALESCE((SELECT jsonb_agg(p ORDER BY (p->>'promotion_id')::bigint DESC) FROM (
        SELECT jsonb_build_object('promotion_id', pl.promotion_id, 'param_key', pl.param_key, 'from', pl.from_value,
                                  'to', pl.to_value, 'outcome', pl.outcome, 'reason', pl.reason,
                                  'experiment_id', pl.experiment_id, 'at', pl.decided_at) AS p
          FROM public.ottoq_dial_promotion_ledger pl ORDER BY pl.promotion_id DESC LIMIT 10) z), '[]'::jsonb));
END
$function$;

CREATE FUNCTION public.ottoq_activity_feed_v2(p_sim_run_id uuid, p_limit integer DEFAULT 200, p_vehicle_id uuid DEFAULT NULL::uuid,
                                              p_changes_only boolean DEFAULT false, p_window_ticks integer DEFAULT 240)
 RETURNS TABLE(occurred_at timestamp with time zone, vehicle_id uuid, display_name text, action text, engine text, target text,
               outcome text, rationale jsonb, reason text, decision_seq bigint, tick_seq bigint, held_ticks integer,
               last_at timestamp with time zone, standing boolean)
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  /* The decision stream with the challenger in it. Every row of ottoq_activity_feed, unchanged, and beside them one row
     when the challenger flags an episode (at its first sight; standing while it is open) and one when it grades it (at
     its close). A challenger row has no decision_seq: it is not a decision, the engine never acted on it, and the
     stream says so. Newest first, the limit applying to each half. */
  SELECT * FROM public.ottoq_activity_feed(p_sim_run_id, p_limit, p_vehicle_id, p_changes_only, p_window_ticks)
  UNION ALL
  SELECT * FROM (
    SELECT c.*
      FROM (
        SELECT f.first_seen_sim AS occurred_at,
               COALESCE(NULLIF(f.evidence->>'car_id', '')::uuid, NULLIF(f.counterfactual->>'beneficiary_id', '')::uuid) AS vehicle_id,
               COALESCE(f.evidence->>'car', f.counterfactual->>'beneficiary', 'OTTO-Q CHALLENGER') AS display_name,
               'challenger_flag'::text AS action,
               'challenger ' || CASE f.question WHEN 'charging_above_floor_while_cars_wait' THEN 'Q1'
                                                WHEN 'charger_offerable_while_cars_wait' THEN 'Q2' ELSE 'Q3' END AS engine,
               f.evidence->>'stall' AS target,
               CASE WHEN f.status = 'open' THEN 'flagged' ELSE COALESCE(f.grade, 'closed') END AS outcome,
               jsonb_strip_nulls(jsonb_build_object(
                 'question', f.question, 'claim', f.counterfactual->>'claim', 'beneficiary', f.counterfactual->>'beneficiary',
                 'beneficiary_waited_min', f.counterfactual->'beneficiary_waited_min',
                 'cars_waiting', f.evidence->'cars_waiting', 'waiting_below_floor', f.evidence->'waiting_below_floor',
                 'longest_wait_min', f.evidence->'longest_wait_min', 'car_soc', f.evidence->'car_soc',
                 'deploy_floor', f.evidence->'deploy_floor', 'stall_type', f.evidence->>'stall_type',
                 'fault_code', f.evidence->>'fault_code', 'peak', f.peak, 'scans_seen', f.scans_seen,
                 'status', f.status, 'grade', f.grade, 'finding_id', f.finding_id,
                 'changes_the_engine', false)) AS rationale,
               f.counterfactual->>'claim' AS reason,
               NULL::bigint AS decision_seq, NULL::bigint AS tick_seq,
               f.scans_seen AS held_ticks, f.last_seen_sim AS last_at, (f.status = 'open') AS standing
          FROM public.ottoq_challenger_findings f
         WHERE f.sim_run_id = p_sim_run_id
        UNION ALL
        SELECT f.closed_sim,
               COALESCE(NULLIF(f.evidence->>'car_id', '')::uuid, NULLIF(f.counterfactual->>'beneficiary_id', '')::uuid),
               COALESCE(f.evidence->>'car', f.counterfactual->>'beneficiary', 'OTTO-Q CHALLENGER'),
               'challenger_grade',
               'challenger ' || CASE f.question WHEN 'charging_above_floor_while_cars_wait' THEN 'Q1'
                                                WHEN 'charger_offerable_while_cars_wait' THEN 'Q2' ELSE 'Q3' END,
               f.evidence->>'stall',
               f.grade,
               jsonb_strip_nulls(jsonb_build_object(
                 'question', f.question, 'claim', f.counterfactual->>'claim', 'beneficiary', f.counterfactual->>'beneficiary',
                 'realized', f.realized, 'grade', f.grade, 'scans_seen', f.scans_seen, 'finding_id', f.finding_id,
                 'first_seen', f.first_seen_sim, 'changes_the_engine', false)),
               f.counterfactual->>'claim',
               NULL::bigint, NULL::bigint, f.scans_seen, f.closed_sim, false
          FROM public.ottoq_challenger_findings f
         WHERE f.sim_run_id = p_sim_run_id AND f.status = 'closed' AND f.closed_sim IS NOT NULL) c
     WHERE p_vehicle_id IS NULL OR c.vehicle_id = p_vehicle_id
     ORDER BY c.occurred_at DESC
     LIMIT GREATEST(COALESCE(p_limit, 200), 1)) ch
$function$;

GRANT EXECUTE ON FUNCTION public.ottoq_challenger_board(uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_learning_board() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_activity_feed_v2(uuid, integer, uuid, boolean, integer) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_challenger_board(uuid) IS
  '0536. The cockpit''s read of the challenger (0532): its questions in words, this run''s episodes open and graded, each '
  'question''s record across runs, the open episodes and the recent grades. Read-only; the challenger never changes the engine.';
COMMENT ON FUNCTION public.ottoq_learning_board() IS
  '0536. The cockpit''s read of the learner: each dial experiment active or ended this week, its pairs, the read witness, '
  'crashed pairs, the verdict (the runner''s own for an active one, the stored one for an ended one), the night window''s '
  'cron jobs and the last promotions. Read-only.';
COMMENT ON FUNCTION public.ottoq_activity_feed_v2(uuid, integer, uuid, boolean, integer) IS
  '0536. ottoq_activity_feed''s rows, unchanged, plus the challenger''s flags and grades in the same shape (action '
  'challenger_flag / challenger_grade, no decision_seq, rationale.changes_the_engine = false).';

DO $verify$
BEGIN
  -- V1: the three are read-only (STABLE) and executable by the cockpits' role
  IF EXISTS (SELECT 1 FROM pg_proc p
              WHERE p.oid IN ('public.ottoq_challenger_board(uuid)'::regprocedure, 'public.ottoq_learning_board()'::regprocedure,
                              'public.ottoq_activity_feed_v2(uuid,integer,uuid,boolean,integer)'::regprocedure)
                AND (p.provolatile <> 's' OR NOT has_function_privilege('anon', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION '0536 V1: a board or the feed is not STABLE and open to the cockpits';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0536_the_cockpits_see_what_the_brain_questions_and_what_it_learns', false, false,
  'Three read-only cockpit contracts: ottoq_challenger_board, ottoq_learning_board, ottoq_activity_feed_v2 (the feed plus '
  'the challenger''s flags and grades). No table, no tick path.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back.
--   (a) The challenger board, with no run named, names the most recent operator run and its three questions in order.
--       On a planted open episode and a planted graded one, it counts one open and one confirmed, and lists each once
--       in its own section.
--   (b) The feed v2 returns the base feed's rows unchanged, plus one flag row per episode and one grade row per closed
--       one, with no decision_seq.
--   (c) The learning board lists every active experiment, each with a verdict outcome, and names the window's jobs.
DO $v3$
DECLARE
  v_msg text; b jsonb; b2 jsonb; l jsonb; v_run uuid; v_base int; v_v2 int; v_flags int; v_grades int; v_active int;
BEGIN
  BEGIN
    b := public.ottoq_challenger_board(NULL);
    v_run := (b->'run'->>'sim_run_id')::uuid;
    IF v_run IS NULL OR jsonb_array_length(b->'questions') <> 3 OR b->'questions'->0->>'tag' <> 'Q1' OR b->'questions'->2->>'tag' <> 'Q3' THEN
      RAISE EXCEPTION '0536 V3 FAILED (a): run %, questions %', v_run, b->'questions';
    END IF;
    INSERT INTO public.ottoq_challenger_findings (sim_run_id, depot_id, question, entity_type, entity_id, episode_key,
                                                  first_seen_sim, last_seen_sim, evidence, counterfactual, scan_version)
    VALUES (v_run, '11111111-1111-1111-1111-111111111111', 'charger_offerable_while_cars_wait', 'stall', gen_random_uuid(), 'v3-open',
            '2026-09-01 14:00:00+00', '2026-09-01 14:02:00+00',
            '{"stall": "NASH-L2-01", "cars_waiting": 3, "longest_wait_min": 12}'::jsonb,
            '{"claim": "a free charger and a waiting car: a missed assignment", "beneficiary": "Tesla-AV-041"}'::jsonb, '0536_v3');
    INSERT INTO public.ottoq_challenger_findings (sim_run_id, depot_id, question, entity_type, entity_id, episode_key,
                                                  first_seen_sim, last_seen_sim, evidence, counterfactual, scan_version,
                                                  status, closed_sim, grade, realized)
    VALUES (v_run, '11111111-1111-1111-1111-111111111111', 'charging_above_floor_while_cars_wait', 'charge_session', gen_random_uuid(), 'v3-closed',
            '2026-09-01 15:00:00+00', '2026-09-01 15:20:00+00',
            '{"stall": "NASH-DC-03", "car": "Waymo-AV-012", "car_soc": 86, "cars_waiting": 5}'::jsonb,
            '{"claim": "ending this charge now hands the DCFC to the longest-waiting car", "beneficiary": "Tesla-AV-041"}'::jsonb, '0536_v3',
            'closed', '2026-09-01 15:21:00+00', 'confirmed', '{"saving_min": 20}'::jsonb);
    b2 := public.ottoq_challenger_board(v_run);
    IF (b2->'questions'->1->'run'->>'open')::int <> 1 OR (b2->'questions'->0->'run'->>'confirmed')::int <> 1
       OR jsonb_array_length(b2->'open') <> 1 OR jsonb_array_length(b2->'graded') <> 1
       OR b2->'open'->0->>'stall' <> 'NASH-L2-01' OR b2->'graded'->0->>'grade' <> 'confirmed' THEN
      RAISE EXCEPTION '0536 V3 FAILED (a): the planted episodes read %', left(b2::text, 1500);
    END IF;

    -- (b) the feed
    SELECT count(*) INTO v_base FROM public.ottoq_activity_feed(v_run, 200, NULL, true, 240);
    SELECT count(*), count(*) FILTER (WHERE action = 'challenger_flag'), count(*) FILTER (WHERE action = 'challenger_grade')
      INTO v_v2, v_flags, v_grades
      FROM public.ottoq_activity_feed_v2(v_run, 200, NULL, true, 240);
    IF v_v2 <> v_base + 3 OR v_flags <> 2 OR v_grades <> 1
       OR EXISTS (SELECT 1 FROM public.ottoq_activity_feed_v2(v_run, 200, NULL, true, 240) WHERE action LIKE 'challenger%' AND decision_seq IS NOT NULL) THEN
      RAISE EXCEPTION '0536 V3 FAILED (b): base % rows, v2 % (flags %, grades %)', v_base, v_v2, v_flags, v_grades;
    END IF;

    -- (c) the learning board
    l := public.ottoq_learning_board();
    SELECT count(*) INTO v_active FROM public.ottoq_dial_experiments WHERE status = 'active';
    IF (SELECT count(*) FROM jsonb_array_elements(l->'experiments') e WHERE e->>'status' = 'active') <> v_active
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(l->'experiments') e WHERE e->>'status' = 'active' AND e->>'outcome' IS NULL)
       OR jsonb_array_length(l->'runner'->'window_jobs') = 0 THEN
      RAISE EXCEPTION '0536 V3 FAILED (c): % active of %, window %', (SELECT count(*) FROM jsonb_array_elements(l->'experiments') e WHERE e->>'status' = 'active'),
        v_active, l->'runner';
    END IF;

    RAISE EXCEPTION '0536 V3 PASSED: the board names run % with Q1-Q3 and counts the planted open and confirmed episodes once each; the feed adds 2 flags and 1 grade to its % base rows; the learning board lists all % active experiments with a verdict',
      left(v_run::text, 8), v_base, v_active;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0536 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0536 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: DROP FUNCTION public.ottoq_challenger_board(uuid), public.ottoq_learning_board(),
--   public.ottoq_activity_feed_v2(uuid, integer, uuid, boolean, integer).
COMMIT;
