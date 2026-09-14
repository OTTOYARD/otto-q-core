-- migration-version: PENDING
-- migration-name:    0284_a_hold_whose_outcome_is_invisible_can_only_be_argued_about
--
-- 0284  THE RIGHT OF FIRST REFUSAL GETS AN OUTCOME LEDGER
--
-- G54, step 1 of 2. This file adds TWO READ-ONLY VIEWS AND NOTHING ELSE. It
-- changes no function, arms nothing, and tunes nothing -- deliberately, and the
-- order is the whole argument: a hold whose outcome is recorded can be tuned by
-- measurement; a hold whose outcome is invisible can only be argued about.
--
-- ---------------------------------------------------------------------------
-- WHAT IS MISSING TODAY
--
-- ottoq_cuopt_first_refusal_arm holds a gate vehicle out of the local decide
-- cursor for exactly one tick so an optimizer's answer is not pre-empted by the
-- stall it was solving for. Its guards are careful: a Zone A/outside-the-walls
-- check, a starvation bound (never re-arm 'armed' or 'spent'; never more than
-- cuopt_first_refusal_max_defers per run), an off switch at cap 0, and a
-- fail-OPEN handler so a ledger hiccup can never change assignment.
--
-- cuopt_log_gate records what was HELD -- {armed, offered, tick, max_defers}.
-- NOTHING ANYWHERE RECORDS WHETHER THE ANSWER ARRIVED. Until this file,
-- "held for an answer that never came" was not a countable event, which is why
-- 0219 had to hand-write the join to find 25 of them on a single run.
--
-- ---------------------------------------------------------------------------
-- THE PREDICATE, AND WHY IT IS COPIED RATHER THAN INVENTED
--
-- ottoq_cuopt_defer_hold releases the hold when a pending proposal exists for
-- the vehicle whose source declares holds_tick:
--
--   AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
--                     WHERE pp.holds_tick)
--
-- The view uses that same subquery, live, so the two can never drift: add a
-- proposer to the precedence table and both the engine and this instrument
-- start counting it the same tick. P2 pins the fact that defer_hold still
-- decides the question this way.
--
-- AND THE WINDOW IS THE SPENT TICK, NOT THE ARM TICK. Read off the two
-- functions rather than assumed:
--
--   ottoq_cuopt_defer_roll  step 2: 'armed' -> 'spent' at the current tick
--                           step 1: 'spent' with spent_at_tick < tick -> 'clear'
--   ottoq_cuopt_defer_hold  returns TRUE only while state='spent'
--                           AND spent_at_tick = p_tick
--
-- So a hold binds during exactly one tick -- the one it was spent in -- and an
-- answer counts if it had landed by then (proposals carry tick_seq since 0236).
-- 0219 first measured this over the wider window [armed, armed+1] and got the
-- same 25-of-25; the narrower window is the correct one and is pinned in P3.
--
-- ---------------------------------------------------------------------------
-- WHAT THE INSTRUMENT ALREADY SAYS, BEFORE ANY TUNING
--
--   run_by                  runs    holds   answered
--   cert_harness             437   29,598          0    <- all pre-quiesce
--   claude_v2_validation       1       50          0
--   operator_demo              1       43          0
--   proposer_demo              1       32         25    <- the control
--   proposer_facts_probe       1       28          0
--   proposer_live              1       25          0    <- today, armed
--   production_live            1       21          0
--
-- TWO READINGS THAT MUST NOT BE CONFLATED.
--
-- 1. The cert_harness row is HISTORY, NOT A LIVE DEFECT, and it vindicates
--    0152 rather than indicting it. Holds on certification runs per day:
--      08-30  10,644 · 08-31  8,510 · 09-01  7,620 · 09-02  1,368
--      09-03 onward: ZERO, across 622 certification runs since.
--    0152 set the global tier of cuopt_first_refusal_max_defers to 0 and the
--    arm returns before doing anything without an explicit run row. It works.
--
-- 2. proposer_demo answered 25 of 32, WHICH IS WHY THIS VIEW IS AN INSTRUMENT
--    AND NOT A ZERO MACHINE. An outcome column that could only ever read
--    'unanswered' would prove nothing about the holds it reported -- the same
--    objection G25/G28 raised against calling a column green when the
--    comparison was narrower than the enforcement. A3 asserts that control
--    case, so this file fails if the predicate is vacuous.
--
-- ---------------------------------------------------------------------------
-- NOT DONE HERE, ON PURPOSE
--
-- No liveness check. The obvious next move is to refuse to arm when no
-- proposer has fired for this run recently (ottoq_proposer_fire_log.fired_at
-- has been one row per fire since 0260), and it is deliberately NOT in this
-- file: it needs a staleness dial, that dial needs a range READ OFF its
-- consumer the way 0282/0283 read theirs, and the right consumer to read is a
-- tuning decision that should be made against this view's numbers rather than
-- ahead of them.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0284 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0284 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0284 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0284 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P1. THE ARM STILL EXISTS AND STILL HAS NO LIVENESS CHECK -------------------
-- The file's premise. If somebody adds one, this instrument still works but its
-- framing is stale, so the file refuses and the note gets rewritten.
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0284 P1: ottoq_cuopt_first_refusal_arm does not exist';
  END IF;
  IF position('ottoq_proposer_fire_log' in v_src) > 0 THEN
    RAISE EXCEPTION '0284 P1: the arm now consults the fire log -- a liveness check '
                    'has been added since this file was written; re-read it';
  END IF;
  IF position('cuopt_first_refusal_max_defers' in v_src) = 0 THEN
    RAISE EXCEPTION '0284 P1: the arm no longer reads its own cap; the cert-quiesce '
                    'argument in this file rests on that read';
  END IF;
  RAISE NOTICE '0284 P1: the arm exists, reads its cap, and has no liveness check';
END $p1$;

-- P2. THE VIEW'S "ANSWERED" PREDICATE IS THE ENGINE'S ------------------------
DO $p2$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_defer_hold';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0284 P2: ottoq_cuopt_defer_hold does not exist';
  END IF;
  IF position('FROM public.ottoq_proposer_precedence pp' in v_src) = 0
     OR position('pp.holds_tick' in v_src) = 0 THEN
    RAISE EXCEPTION '0284 P2: defer_hold no longer decides "answered" from '
                    'ottoq_proposer_precedence.holds_tick; the view would measure '
                    'something the engine does not do';
  END IF;
  RAISE NOTICE '0284 P2: view and engine read the same holds_tick source set';
END $p2$;

-- P3. THE BINDING TICK IS STILL THE SPENT TICK -------------------------------
DO $p3$
DECLARE v_hold text; v_roll text;
BEGIN
  SELECT p.prosrc INTO v_hold FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_defer_hold';
  SELECT p.prosrc INTO v_roll FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_defer_roll';
  IF v_roll IS NULL THEN
    RAISE EXCEPTION '0284 P3: ottoq_cuopt_defer_roll does not exist';
  END IF;
  IF position('d.spent_at_tick = p_tick' in v_hold) = 0 THEN
    RAISE EXCEPTION '0284 P3: the hold no longer binds on spent_at_tick = tick; '
                    'the view''s window is derived from that and must be re-read';
  END IF;
  IF position('spent_at_tick < p_tick' in v_roll) = 0 THEN
    RAISE EXCEPTION '0284 P3: roll no longer releases on spent_at_tick < tick; '
                    'the one-tick lifetime this view assumes is gone';
  END IF;
  RAISE NOTICE '0284 P3: a hold still binds for exactly the tick it was spent in';
END $p3$;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.ottoq_first_refusal_outcomes AS
SELECT d.sim_run_id,
       r.run_by,
       r.started_at                                   AS run_started_at,
       d.vehicle_id,
       d.state,
       d.armed_at_tick,
       d.spent_at_tick,
       d.cleared_at_tick,
       d.defer_count,
       a.source                                       AS answer_source,
       a.status                                       AS answer_status,
       a.tick_seq                                     AS answer_tick,
       (a.source IS NOT NULL)                         AS answered,
       CASE WHEN d.spent_at_tick IS NULL          THEN 'never_bound'
            WHEN a.source IS NULL                 THEN 'unanswered'
            WHEN a.status = 'enacted'             THEN 'answered_enacted'
            ELSE                                       'answered_not_enacted'
       END                                            AS outcome
  FROM public.ottoq_cuopt_deferrals d
  --: LEFT, not inner. There are no orphaned deferral rows today (29,797 of
  --: 29,797 have a run), but ottoq-run-purge-nightly deletes runs and an inner
  --: join would silently drop those holds from every count here -- an
  --: instrument that quietly shrinks as history is purged is worse than none.
  --: An orphan keeps its row with run_by NULL.
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
  --: LATERAL with LIMIT 1, never a plain join: a vehicle can carry several
  --: proposals and this view must stay one row per HOLD. Ordered by the
  --: precedence table's own rank so the answer reported is the one the engine
  --: would have preferred, then by the latest landing tick.
  LEFT JOIN LATERAL (
    SELECT p.source, p.status, p.tick_seq
      FROM public.ottoq_external_proposals p
      JOIN public.ottoq_proposer_precedence pp ON pp.source = p.source AND pp.holds_tick
     WHERE p.sim_run_id     = d.sim_run_id
       AND p.entity_id      = d.vehicle_id
       AND p.entity_type    = 'vehicle'
       AND p.action_context = 'stall_assignment'
       AND d.spent_at_tick IS NOT NULL
       AND p.tick_seq      <= d.spent_at_tick
     ORDER BY pp.rank, p.tick_seq DESC
     LIMIT 1) a ON true;

COMMENT ON VIEW public.ottoq_first_refusal_outcomes IS
'0284/G54. One row per first-refusal hold, with the outcome the engine never recorded: '
'did an answer arrive before the hold bound. answered/outcome use ottoq_cuopt_defer_hold''s '
'own predicate (a proposal from a source whose ottoq_proposer_precedence row declares '
'holds_tick) over ottoq_cuopt_defer_roll''s own window (the tick the row was SPENT in, the '
'only tick it binds). Read-only and derived, so it covers every historical run, not just '
'runs since the instrument existed. Adds no liveness check and changes no behaviour: this '
'is the measurement that a liveness change should be tuned against, not the change.';

CREATE OR REPLACE VIEW public.ottoq_first_refusal_summary AS
SELECT sim_run_id, run_by, run_started_at,
       count(*)                                                  AS holds,
       count(*) FILTER (WHERE outcome = 'answered_enacted')       AS answered_enacted,
       count(*) FILTER (WHERE outcome = 'answered_not_enacted')   AS answered_not_enacted,
       count(*) FILTER (WHERE outcome = 'unanswered')             AS unanswered,
       count(*) FILTER (WHERE outcome = 'never_bound')            AS never_bound,
       min(armed_at_tick)                                        AS first_armed_tick,
       max(armed_at_tick)                                        AS last_armed_tick,
       round(100.0 * count(*) FILTER (WHERE answered) / NULLIF(count(*),0), 1)
                                                                 AS answered_pct
  FROM public.ottoq_first_refusal_outcomes
 GROUP BY 1,2,3;

COMMENT ON VIEW public.ottoq_first_refusal_summary IS
'0284/G54. Per-run rollup of ottoq_first_refusal_outcomes. unanswered is the cost line: '
'vehicles held out of the local decide cursor for a tick, waiting for an answer that never '
'came. answered_pct is the number a liveness change has to move.';

-- ---------------------------------------------------------------------------
-- A1. ONE ROW PER HOLD -- the LATERAL must not fan out.
DO $a1$
DECLARE v_holds bigint; v_rows bigint;
BEGIN
  SELECT count(*) INTO v_holds FROM public.ottoq_cuopt_deferrals;
  SELECT count(*) INTO v_rows  FROM public.ottoq_first_refusal_outcomes;
  IF v_rows <> v_holds THEN
    RAISE EXCEPTION 'A1 FAILED: % view rows for % deferral rows -- the proposal join '
                    'is fanning out and every count downstream would be inflated',
                    v_rows, v_holds;
  END IF;
  RAISE NOTICE 'A1 OK: % rows, exactly one per hold', v_rows;
END $a1$;

-- A1b. AN ORPHANED HOLD STILL COUNTS.
-- The LEFT JOIN above is the reason A1 can compare against the whole table;
-- this asserts the property directly rather than relying on there being no
-- orphans today, because the nightly purge can create one at any time.
DO $a1b$
DECLARE v_orphans bigint; v_in_view bigint;
BEGIN
  SELECT count(*) INTO v_orphans FROM public.ottoq_cuopt_deferrals d
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = d.sim_run_id);
  SELECT count(*) INTO v_in_view FROM public.ottoq_first_refusal_outcomes WHERE run_by IS NULL;
  IF v_in_view <> v_orphans THEN
    RAISE EXCEPTION 'A1b FAILED: % orphaned hold(s) in the ledger but % in the view -- '
                    'a purged run must not erase the holds it armed', v_orphans, v_in_view;
  END IF;
  RAISE NOTICE 'A1b OK: % orphaned hold(s), all still counted', v_orphans;
END $a1b$;

-- A2. EVERY ROW HAS EXACTLY ONE OUTCOME, AND THE VOCABULARY IS TOTAL.
DO $a2$
DECLARE v_bad bigint;
BEGIN
  SELECT count(*) INTO v_bad FROM public.ottoq_first_refusal_outcomes
   WHERE outcome NOT IN ('never_bound','unanswered','answered_enacted','answered_not_enacted')
      OR outcome IS NULL
      OR (answered AND outcome = 'unanswered')
      OR (NOT answered AND outcome LIKE 'answered%');
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: % row(s) carry an outcome that disagrees with '
                    'answered, or no outcome at all', v_bad;
  END IF;
  RAISE NOTICE 'A2 OK: the outcome vocabulary is total and agrees with answered';
END $a2$;

-- A3. THE CONTROL: THE INSTRUMENT CAN SAY 'ANSWERED'.
-- An outcome column that could only ever read 'unanswered' would prove nothing
-- about the holds it reported. proposer_demo's run is the case where the
-- proposer really did answer, and it must come back non-zero.
DO $a3$
DECLARE v_answered bigint; v_holds bigint;
BEGIN
  SELECT COALESCE(sum(holds),0), COALESCE(sum(answered_enacted + answered_not_enacted),0)
    INTO v_holds, v_answered
    FROM public.ottoq_first_refusal_summary WHERE run_by = 'proposer_demo';
  IF v_holds = 0 THEN
    RAISE EXCEPTION 'A3 FAILED: no proposer_demo holds to use as a control; this file '
                    'cannot show the predicate is non-vacuous and must be re-thought';
  END IF;
  IF v_answered = 0 THEN
    RAISE EXCEPTION 'A3 FAILED: the control run reports 0 answered of % holds -- the '
                    'predicate is vacuous and the instrument is a zero machine', v_holds;
  END IF;
  RAISE NOTICE 'A3 OK: control run answers % of % holds', v_answered, v_holds;
END $a3$;

-- A4. THE CERT QUIESCE IS INTACT -- 0152 still holds and this file says so.
DO $a4$
DECLARE v_recent bigint;
BEGIN
  SELECT count(*) INTO v_recent FROM public.ottoq_first_refusal_outcomes
   WHERE run_by = 'cert_harness' AND run_started_at > timestamptz '2026-09-03';
  IF v_recent > 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % first-refusal hold(s) on certification runs since '
                    '2026-09-03; the quiesce this file credits 0152 with is broken', v_recent;
  END IF;
  RAISE NOTICE 'A4 OK: no certification run has armed a hold since 2026-09-03';
END $a4$;

-- A5. TODAY'S ARMED RUN READS THE WAY 0219 MEASURED IT BY HAND.
-- The instrument has to reproduce the hand-written join that found the defect,
-- or it is measuring something else.
DO $a5$
DECLARE v_holds bigint; v_unanswered bigint;
BEGIN
  SELECT holds, unanswered INTO v_holds, v_unanswered
    FROM public.ottoq_first_refusal_summary
   WHERE sim_run_id = '97769e7e-cd44-4789-b272-f696c60c2a66'::uuid;
  IF v_holds IS NULL THEN
    RAISE NOTICE 'A5 SKIPPED: run 97769e7e is no longer present (purged); nothing to '
                 'reproduce, and that is not a failure of the view';
  ELSIF v_holds <> 25 OR v_unanswered <> 25 THEN
    RAISE EXCEPTION 'A5 FAILED: run 97769e7e reads % holds / % unanswered; 0219 '
                    'measured 25 and 25 by hand', v_holds, v_unanswered;
  ELSE
    RAISE NOTICE 'A5 OK: run 97769e7e reads 25 holds, 25 unanswered -- 0219 reproduced';
  END IF;
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0284_a_hold_whose_outcome_is_invisible_can_only_be_argued_about', false,
 'Two read-only views, no function replaced and no behaviour changed. ottoq_first_refusal_outcomes gives every first-refusal hold the outcome the engine never recorded -- answered / unanswered / enacted -- using ottoq_cuopt_defer_hold''s own predicate (a proposal from a source whose ottoq_proposer_precedence row declares holds_tick, read live so the two cannot drift) over ottoq_cuopt_defer_roll''s own window (the tick the row was SPENT in, the only tick it binds). ottoq_first_refusal_summary rolls it up per run. Because it is derived it covers every historical run. Baseline at apply: proposer_live 25 holds / 0 answered (today, the first armed run), proposer_demo 32 / 25 answered (the control that proves the predicate is not vacuous, asserted in A3), cert_harness 29,598 / 0 but all before 2026-09-03 -- holds on certification runs went 10,644 / 8,510 / 7,620 / 1,368 / 0 over 08-30..09-03 and have been zero across 622 certification runs since, which vindicates 0152''s quiesce rather than indicting it (A4 asserts it is still intact). forces_recert=false: nothing but two views is created, no engine function is touched, and no certification arm reads either. G54 step 2, the liveness check on ottoq_cuopt_first_refusal_arm, is deliberately NOT in this file -- it needs a staleness dial whose range must be read off a consumer, and the consumer to read is a tuning decision to make against these numbers rather than ahead of them.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
