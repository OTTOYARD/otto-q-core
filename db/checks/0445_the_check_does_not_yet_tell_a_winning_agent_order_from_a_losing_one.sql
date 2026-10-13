-- 0445  **The check does not yet tell a winning agent order from a losing one, and now that is one call.** What
--        db/migrations/0708 (ottoq_disposer_discrimination) reads, and how to read it. Read-only. Finding G427.
--
--        Measured 2026-10-13 on the twin depot, every graded decision since grading began (2026-10-08); the function's
--        own query read now() = 19:50:18 UTC (2:50 PM CT).
--
-- ══ §1 THE CORPUS AND THE ANSWER (reproduce: (1), (2)) ══
--
--   Decided grades: missed_win 42, right_refusal 42, right_take 3, wrong_take 3, neutral_take 2 (the ties, left out);
--   one more graded by 19:50. Won 46, lost 45.
--     AUC 0.5336, standard error 0.0607 (Hanley & McNeil), 95% interval [0.4146, 0.6525]: does not discriminate.
--     Brier 0.2756 against 0.2500 for the base rate: the check's p_win is a worse forecast than the base rate.
--     Mean p_win 0.533 for orders that won, 0.515 for orders that lost.
--     10 runs, 6 distinct (scenario, seed) keys.
--   This is G389's 18 decisions and the study's AV-1's 70, extended and made reproducible: the same answer each time,
--   now from one call with its denominator stated. Of the 90 it had judged at the first read it took 6 (3 won, 3 lost)
--   and refused 84, so the kernel's order stood; refusing is the safe default, and it is why no agent's order should be
--   taken on the check's word yet.
--
-- ══ §2 WHAT THE NUMBER CANNOT SAY ══
--
--   Decisions within one run share its world and each other's futures, so the interval, which assumes independent
--   decisions, is optimistic; 6 keys is the honest count of independent worlds behind it. And won/lost is the grader's
--   simulated hindsight (the study's AV-8), not the world's. docs/AGENT_ARCHITECTURE.md's promotion gate asks for the
--   interval to exclude 0.5 on graded decisions, read beside the key count; neither is met.

-- (1) the corpus by outcome
SELECT outcome, taken, count(*) AS n, round(avg(p_win), 3) AS mean_p_win
  FROM public.ottoq_charge_order_grades
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND decision
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- (2) the answer, all time and the last 7 days
SELECT public.ottoq_disposer_discrimination('11111111-1111-1111-1111-111111111111', '-infinity', 'infinity') AS all_time,
       public.ottoq_disposer_discrimination('11111111-1111-1111-1111-111111111111', now() - interval '7 days', now()) AS last_7_days;
