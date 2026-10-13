-- 0442  **The agent was consulted on every beat, and its value could not be measured.** The premises of
--        db/migrations/0705 (the wake gate), and where its results are. Read-only.
--
--        0705's header and its live lineage note (classified 2026-10-13) cite this file. It was named then and written
--        later the same day, at 19:40-19:45 UTC (2:40-2:45 PM CT), from the study's stored results. The measurements of
--        the gate itself are in db/checks/0440 §5-§10; this file keeps the premises and points there.
--
-- ══ §0 A LABEL CORRECTED ══
--
--   0705's header and its lineage note name the study's findings "AG-1 cadence, AV-1 value". The study's AG-1 is a
--   different finding: ottoq-ottocommand is a public, self-declared-role LLM whose writes bypass rule 10 (taken up by
--   0702, PR #241). The cadence findings are AG-7 (the twin measures the agent at a staleness production will not
--   have), AG-12 (the agent layer's cost and coverage are not observable) and AG-16 ("every third tick" is wrong under
--   load); the value findings are AV-1 and AG-2 (the disposer cannot tell a winning order from a losing one). The
--   lineage row is permanent and keeps the old label; this file is the correction.
--
-- ══ §1 WHAT THE STUDY MEASURED (its agent lanes, 2026-10-13 morning) ══
--
--   - The agent is latency-bound in the twin: a pass took a mean 37.8 s (p95 68 s that day) against a solver that
--     answers in 17 ms; passes landed every 8-8.5 ticks, each on a board 6.4-6.7 ticks old (AG-7, AG-16).
--   - Every lever was nearly constant: readiness_first on 1,610 of 1,611 passes; 416 orders since the check landed,
--     83% the kernel's own, 7 taken (AG-5, AV-5).
--   - AV-1: on 70 hindsight-graded decisions over 7 runs the check agreed with hindsight 35 times; mean p_win 0.547 for
--     orders that won against 0.557 for orders that lost; Brier 0.298 against 0.248 for the base rate. The 7 taken
--     orders summed to 0 extra on-time cars and +538 late-minutes. (G389 extended; G427.)
--   - So consulting the model on every beat bought nothing measurable, at about 25,800 prompt tokens and a median
--     59.5 s a consult. 0705 consults it on a change that matters and runs CP-SAT alone otherwise; 0711 added
--     hysteresis after the shadow gate woke on 66 of 79 recorded passes.
--
-- ══ §2 WHAT THE GATE DID (db/checks/0440 §7, §9, §10) ══
--
--   Shadow, 176b2912: 75 of 79 passes would have woken under 0705's rules; replayed under 0711's, 25.
--   On, 57188f55: 21 of 288 passes consulted the model (heartbeat 12, scout 5, charger 2, contract wait 2, first 1;
--   one heartbeat landed 41 s after the stop), 267 ran CP-SAT alone at a mean 2,055 ms, 0 passes overlapped, model
--   tokens fell 71% (1,985,250 to 576,986), and the kernel enacted 22
--   CP-SAT proposals against 0 on the shadow run (one pair under live playback: a lead, G432).

-- (1) consults and solver-only passes, by run, from the evidence (survives the purge)
SELECT left(sim_run_id::text, 8) AS run, consulted, outcome_class, count(*) AS passes,
       round(avg(total_ms)) AS mean_ms,
       sum(COALESCE((usage ->> 'prompt_tokens')::bigint, 0) + COALESCE((usage ->> 'completion_tokens')::bigint, 0)) AS tokens
  FROM public.ottoq_agent_pass_evidence
 GROUP BY 1, 2, 3 ORDER BY 1, 2 DESC, 4 DESC;

-- (2) why each consult woke, by run
SELECT left(sim_run_id::text, 8) AS run, r.reason, count(*) AS consults
  FROM public.ottoq_agent_pass_evidence e,
       LATERAL jsonb_array_elements_text(COALESCE(e.wake -> 'reasons', '[]'::jsonb)) AS r(reason)
 WHERE e.consulted
 GROUP BY 1, 2 ORDER BY 1, 3 DESC;
