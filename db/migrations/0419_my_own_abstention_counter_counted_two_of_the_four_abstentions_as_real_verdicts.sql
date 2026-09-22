-- migration-version: PENDING
-- migration-name:    my_own_abstention_counter_counted_two_of_the_four_abstentions_as_real_verdicts
--
-- 0419  **`0418` shipped `ottoq_assert_task_completion_coverage()` two hours ago to stop abstentions
--       being counted as protection. Exercising the probe shows it counts two of the four observed
--       abstentions as REAL VERDICTS — it matches only `'insufficient context%'`, and two of the five
--       rules abstain in different words.**
--
--       The function whose entire purpose is to prevent over-counting was over-counting. Found by
--       running the thing rather than reading it, which is the only reason it was found at all.
--
--       Also records what the exercise proved and what it stopped me building. `forces_recert` **FALSE**.
--
-- ══ §1 THE DEFECT, MEASURED ═══════════════════════════════════════════════════
--
-- The five codes at `task_completion` abstain in four different phrasings, each written independently in
-- its own evaluator:
--
--     rule       abstention reason                                    0418 counted it as
--     --------   --------------------------------------------------  ------------------
--     HW.006     'insufficient context for presence verification'     abstention   ✓
--     TW.002     'insufficient context'                               abstention   ✓
--     SLA.003    'missing context'                                    **REAL VERDICT**  ✗
--     SM.002     'no transition context'                              **REAL VERDICT**  ✗
--
-- So `0418`'s `real_verdicts` was inflated and its `VACUOUS` verdict — which fires only when *every*
-- evaluation abstained — could never trigger for SLA.003 or SM.002 no matter how completely they
-- abstained. **A rule that abstains on every single call would have read "clean on real verdicts".**
-- That is `G120`'s defect class (*a rule reads green because it was never asked*) reproduced inside the
-- instrument built to detect `G120`.
--
-- **The fix, and its honest limit.** The predicate becomes `passed AND reason ILIKE '%context%'`, which
-- catches all four observed phrasings and matches none of the real verdicts seen
-- (`'SOC fresh: 232 seconds old'`, `'SOC sensor stale: 300 seconds old (threshold 300)'`,
-- `'system state mismatch: stall does not record this vehicle as present'`). **It is a heuristic over
-- free text and this migration says so rather than implying precision it does not have** — a sixth
-- evaluator could abstain in words containing no "context" at all. The durable fix is a structured
-- abstention signal on `ottoq_rule_result` rather than a phrase match, and that is a change to the rule
-- result type used by every evaluator in the engine; it is named here as the right fix and deliberately
-- not made at 03:00 CT. `v_abstention_is_heuristic` is returned as a column so no reader can mistake the
-- one for the other.
--
-- ══ §2 WHAT THE EXERCISE PROVED, WHICH IS WHY `0418` WAS WORTH BUILDING ═══════
--
-- Run against live in-progress atoms (writes rolled back), the probe returns real, discriminating
-- verdicts rather than a wall of abstentions:
--
--   - **`HW.006` FIRED, exactly as `G121` predicted.** `passed=false`, `would_block=true`, reason
--     *"system state mismatch: stall does not record this vehicle as present"* — on an atom whose stall
--     the probe resolved through `need_atom`. **The defect `0326` §2 found by hand is detected
--     automatically by the rule written for it, on live data.** That is the whole case for wiring it.
--   - **`HW.003.sensor_liveness` FIRED TOO, and nobody predicted this one.** `safety_critical`,
--     `enforcement='block'`, reason *"SOC sensor stale: 300 seconds old (threshold 300)"*. HW.003 is
--     evaluated today at `task_start` and `redeployment` only — so a vehicle whose SOC sensor goes stale
--     **during** the work is never checked, which is exactly the gap `0326` §6(b) named (*"the engine
--     checks sensor liveness before work begins and never after it ends"*). Here is that gap producing a
--     real failure the moment it is looked at.
--
-- **AND THIS SHARPENS WHY THE PROBE MUST STAY ADVISORY.** `HW.003` and `HW.006` are both
-- `enforcement='block'`. Blocking a *completion* is incoherent: the work is already done, and refusing to
-- record it does not undo it — it strands the atom `in_progress` forever, which is the wedge `0326` §7
-- worried about arriving by a different road. `ottoq_shield_probe` does not block (it returns
-- `would_block` and leaves enforcement to the caller), so the wiring must read the verdict and **never
-- act on `would_block`**. Recorded here because the wiring migration is the one that could get it wrong.
--
-- ══ §3 THE ENRICHMENT I ALMOST MADE, AND THE VOCABULARY MISMATCH THAT STOPPED IT ═
--
-- `SM.002` abstains for want of `from_state`/`to_state`, and at atom completion the transition looks
-- obviously supplyable: `in_progress` → `done`. **Supplying it would have manufactured a false failure.**
-- `SM.002` delegates to `ottoq_eval_sm_transition_validity('task', …)`, which looks the pair up in
-- `ottoq_state_transitions` and returns `FALSE, 'invalid transition for task: … → …'`, severity
-- `critical`, when it is not declared. Measured, the declared task terminal is **`completed`**:
--
--     task: in_progress -> completed | failed | flagged | skipped      (and 10 more)
--
-- **The atom vocabulary says `done`; the declared task vocabulary says `completed`.** (`cancelled`
-- happens to match; the terminal word does not.) So the "obvious" enrichment would have produced a
-- `critical` failure on every single completion — an invented defect, from a word.
--
-- **And the deeper reason not to map `done`→`completed` in the probe:** an atom is a jsonb element of
-- `ottoq_visit_needs.atoms`, not a row of whatever table `entity_kind='task'` describes. Translating one
-- vocabulary into the other inside a probe would assert an identity nothing in the schema declares —
-- the invented-bound mistake `0413` §5, `0414` §3 and `0326` §7 all refused. **`SM.002` therefore keeps
-- abstaining, honestly counted as an abstention by §1's fix.** Whether the atom lifecycle should be
-- declared in `ottoq_state_transitions` at all is a real question and belongs with `0412`'s work on that
-- table, not here.
--
-- `SLA.003` is left abstaining for the same kind of reason: it requires a `schedule_id` AND a
-- `fleet_operator_id`, and `visit_id` is not a `vehicle_schedules.id`. Passing one because it is the id
-- nearest to hand would evaluate a real rule against the wrong row.
--
-- ══ §4 forces_recert FALSE ════════════════════════════════════════════════════
--
-- Replaces one function that nothing calls, adds no probe, wires nothing, and changes no row on any run.
-- V3 re-asserts `0418`'s premise that nothing in the engine calls either function.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n int;
BEGIN
  -- P1. 0418 is applied and the function to correct exists.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('ottoq_probe_task_completion','ottoq_assert_task_completion_coverage');
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0419 P1: 0418''s two functions are not both present (found %) -- apply 0418 first', v_n;
  END IF;

  -- P2. THE DEFECT IS REAL, asserted from the evaluators' own source rather than from my notes: at least
  --     two of the five codes abstain in words that 'insufficient context%' cannot match.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('ottoq_eval_sla_003_max_visit_duration','ottoq_eval_sm_transition_validity')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
         ~ '''(missing context|no transition context)''';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0419 P2: expected both SLA.003 and SM.002 to abstain in words outside '
                    '"insufficient context" (found %) -- re-derive §1 before changing the predicate', v_n;
  END IF;

  -- P3. THE VOCABULARY MISMATCH OF §3 IS REAL: the declared task terminal is `completed`, and `done` --
  --     the word atoms use -- is not a declared task target at all. If this ever changes, §3's reasoning
  --     for leaving SM.002 abstaining is void and should be revisited.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='task' AND to_state='done' AND status='active';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0419 P3: `done` is now a declared task transition target. §3 argued SM.002 must keep '
                    'abstaining BECAUSE it is not -- re-read §3 before applying';
  END IF;

  RAISE NOTICE '0419 preflight: 0418 present, two abstention phrasings unmatched, `done` still undeclared';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE FIX. Same shape as 0418's, with a predicate that catches the family and a
-- column that admits it is a heuristic.
-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE cannot change a function's return type, and this adds the
-- `abstention_is_heuristic` column. The DROP is safe for exactly the reason V3 asserts: nothing in the
-- engine calls this function.
DROP FUNCTION IF EXISTS public.ottoq_assert_task_completion_coverage();

CREATE FUNCTION public.ottoq_assert_task_completion_coverage()
RETURNS TABLE(rule_code text, evaluations bigint, real_verdicts bigint,
              abstentions bigint, failed bigint, would_have_blocked bigint,
              abstention_is_heuristic boolean, verdict text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
  --: An abstention is a PASS whose reason talks about context. 0418 matched only
  --: 'insufficient context%' and so scored SLA.003's 'missing context' and SM.002's
  --: 'no transition context' as real verdicts -- the exact over-counting this function exists to
  --: prevent. The predicate below catches all four observed phrasings and none of the observed real
  --: verdicts, but it IS a phrase match over free text: a sixth evaluator could abstain in words
  --: containing no "context" at all. abstention_is_heuristic says so in the result rather than in a
  --: comment nobody reads. The durable fix is a structured abstention flag on ottoq_rule_result.
  SELECT e.rule_code,
         count(*)                                                                  AS evaluations,
         count(*) FILTER (WHERE NOT (e.passed AND e.reason ILIKE '%context%'))      AS real_verdicts,
         count(*) FILTER (WHERE      e.passed AND e.reason ILIKE '%context%')       AS abstentions,
         count(*) FILTER (WHERE NOT e.passed)                                       AS failed,
         count(*) FILTER (WHERE NOT e.passed AND r.enforcement = 'block')           AS would_have_blocked,
         true                                                                       AS abstention_is_heuristic,
         CASE
           WHEN count(*) = 0 THEN 'NEVER PROBED'
           WHEN count(*) FILTER (WHERE e.passed AND e.reason ILIKE '%context%') = count(*)
             THEN 'VACUOUS: every evaluation abstained -- this rule is not protecting anything'
           WHEN count(*) FILTER (WHERE NOT e.passed) > 0
             THEN 'FIRING: real failures present'
           ELSE 'clean on real verdicts'
         END                                                                        AS verdict
    FROM public.ottoq_rule_evaluations e
    LEFT JOIN public.ottoq_rules r ON r.rule_code = e.rule_code AND r.status='active'
   WHERE e.action_context = 'task_completion'
   GROUP BY e.rule_code
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_task_completion_coverage() IS
'db/migrations/0418 §2, corrected by 0419 §1. Separates real verdicts from abstentions at '
'task_completion so an abstention is never counted as protection. 0418 matched only '
'''insufficient context%'' and therefore scored SLA.003''s ''missing context'' and SM.002''s ''no '
'transition context'' as REAL VERDICTS -- G120''s defect class inside the instrument built to detect '
'G120. The predicate is now "a PASS whose reason mentions context", which catches all four observed '
'phrasings and no observed real verdict, but it is a phrase match over free text and '
'abstention_is_heuristic says so in every row. The durable fix is a structured abstention signal on '
'ottoq_rule_result, which is a change to every evaluator in the engine. VACUOUS is the verdict to '
'watch. No rows means never probed, not clean.';

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0419_my_own_abstention_counter_counted_two_of_the_four_abstentions_as_real_verdicts',
  false,
  'Corrects ottoq_assert_task_completion_coverage, shipped by 0418, whose abstention predicate matched '
  'only ''insufficient context%'' and so counted SLA.003''s ''missing context'' and SM.002''s ''no '
  'transition context'' as real verdicts -- over-counting protection in the one function built to '
  'prevent it, and making its VACUOUS verdict unreachable for those two codes. New predicate: a PASS '
  'whose reason mentions context, with an abstention_is_heuristic column admitting it is a phrase match. '
  'FALSE because the function is read-only reporting, nothing in the engine calls it (V3), and no probe '
  'is wired -- task_completion still has zero evaluations on every run.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n     int;
  v_real  int;
  v_abst  int;
BEGIN
  -- V1. The corrected function exists, carries the new column, and is selectable.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_assert_task_completion_coverage'
     AND pg_get_function_result(p.oid) LIKE '%abstention_is_heuristic%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0419 V1: the corrected function (with abstention_is_heuristic) is not present';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_assert_task_completion_coverage();
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0419 V1: task_completion has % coverage rows; the probe is still unwired so it '
                    'must have none', v_n;
  END IF;

  -- V2. THE FIX WORKS ON THE ACTUAL PHRASINGS. Proven against the four observed abstention reasons and
  --     the three observed real verdicts, as literals -- so this assertion holds with no rows in the
  --     table and would catch a predicate that silently stopped matching.
  SELECT count(*) FILTER (WHERE NOT (passed AND reason ILIKE '%context%')),
         count(*) FILTER (WHERE      passed AND reason ILIKE '%context%')
    INTO v_real, v_abst
    FROM (VALUES
      (true,  'insufficient context for presence verification'),          -- HW.006  abstain
      (true,  'insufficient context'),                                    -- TW.002  abstain
      (true,  'missing context'),                                         -- SLA.003 abstain, 0418 missed
      (true,  'no transition context'),                                   -- SM.002  abstain, 0418 missed
      (true,  'SOC fresh: 232 seconds old'),                              -- HW.003  real
      (false, 'SOC sensor stale: 300 seconds old (threshold 300)'),        -- HW.003  real
      (false, 'system state mismatch: stall does not record this vehicle as present') -- HW.006 real
    ) AS t(passed, reason);
  IF v_abst <> 4 OR v_real <> 3 THEN
    RAISE EXCEPTION '0419 V2: the predicate classifies % abstentions and % real verdicts on the seven '
                    'observed phrasings; expected 4 and 3', v_abst, v_real;
  END IF;

  -- V2b. AND THE OLD PREDICATE FAILS THAT SAME TABLE -- the regression this migration exists for.
  SELECT count(*) FILTER (WHERE reason LIKE 'insufficient context%') INTO v_abst
    FROM (VALUES
      (true,  'insufficient context for presence verification'),
      (true,  'insufficient context'),
      (true,  'missing context'),
      (true,  'no transition context')
    ) AS t(passed, reason);
  IF v_abst <> 2 THEN
    RAISE EXCEPTION '0419 V2b: expected 0418''s predicate to catch only 2 of the 4 abstentions, it '
                    'caught % -- §1''s premise is wrong', v_abst;
  END IF;
  RAISE NOTICE '0419 V2: new predicate 4 abstentions / 3 real verdicts; 0418''s caught 2 of 4';

  -- V3. 0418's forces_recert=FALSE premise still holds: nothing in the engine calls either function.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog','information_schema')
     AND p.proname NOT IN ('ottoq_probe_task_completion','ottoq_assert_task_completion_coverage')
     AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
         ~ '(ottoq_probe_task_completion|ottoq_assert_task_completion_coverage)';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0419 V3: % caller(s) appeared; reclassify forces_recert', v_n;
  END IF;

  RAISE NOTICE '0419 verify: predicate corrected and proven on the observed phrasings, regression '
               'demonstrated against 0418''s, accounting still empty, nothing wired';
END $post$;

COMMIT;
