-- ---------------------------------------------------------------------------
-- 0189 — THE STANDING CHECK THAT WOULD HAVE CAUGHT G47 ON DAY ONE
--
-- G47 (db/checks/0188) was found by accident, while writing AGENT_HARNESS.md,
-- fifteen days after a CERTIFIED proposer stopped being followed -- or rather,
-- fifteen days after it started never being followed. Nothing watched for that.
-- The proposal ledger answers "did anyone propose"; nothing answered "did anyone
-- LISTEN", which is the question the whole propose/dispose thesis rests on.
--
-- Run this after every certification round and after every demo run. It is
-- read-only, it takes milliseconds, and a zero in the enacted column of a
-- proposer that is still submitting is a defect until proven otherwise.
-- ---------------------------------------------------------------------------

-- 1. PER PROPOSER: submitted, consumed, credited -- and the gap between them.
--    'consumed' counts decisions whose enacted action names this source, whatever
--    the outcome; 'credited' counts proposals the closer marked 'enacted'. A
--    proposer with consumed > 0 and credited = 0 is being asked and then overruled
--    by physical reality every single time -- exactly G47's shape.
WITH prop AS (
  SELECT source, action_context,
         count(*)                                            AS submitted,
         count(*) FILTER (WHERE status = 'enacted')           AS credited,
         count(*) FILTER (WHERE status = 'superseded')        AS superseded,
         count(*) FILTER (WHERE status = 'expired')           AS expired,
         count(*) FILTER (WHERE status = 'pending')           AS pending,
         max(created_at)                                      AS last_submitted
    FROM public.ottoq_external_proposals
   GROUP BY 1, 2
), cons AS (
  SELECT d.enacted_action->>'source'                          AS source,
         count(*)                                             AS consumed,
         count(*) FILTER (WHERE d.outcome_status = 'enacted')  AS consumed_enacted,
         count(*) FILTER (WHERE d.outcome_status = 'noop_no_candidate')
                                                              AS consumed_noop,
         count(DISTINCT d.outcome_status)                      AS distinct_outcomes
    FROM public.ottoq_decisions d
   WHERE d.enacted_action ? 'source'
   GROUP BY 1
)
SELECT p.source, p.action_context, p.submitted, p.credited,
       COALESCE(c.consumed, 0) AS consumed, COALESCE(c.consumed_noop, 0) AS consumed_noop,
       p.superseded, p.expired, p.pending,
       to_char(p.last_submitted, 'YYYY-MM-DD HH24:MI') AS last_submitted,
       CASE
         WHEN p.credited > 0                               THEN 'followed'
         WHEN COALESCE(c.consumed, 0) > 0                  THEN 'ASKED AND NEVER FOLLOWED'
         WHEN p.superseded + p.expired > 0                 THEN 'NEVER HEARD'
         WHEN p.pending > 0                                THEN 'submitted, not yet consumed'
         ELSE 'nothing to say yet'
       END AS verdict
  FROM prop p LEFT JOIN cons c ON c.source = p.source
 ORDER BY p.submitted DESC;
-- MEASURED 2026-09-13 05:12 UTC (source | submitted | credited | consumed | noop |
-- superseded | expired | pending | last | verdict):
--   greedy_constrained     | 12569 | 4153 | 85822 |   0 | 5861 | 2551 | 4  | 09-13 04:10 | followed
--   ottoq_service_priority |  2335 |    0 |   446 | 446 | 1505 |  822 | 8  | 09-13 04:10 | ASKED AND NEVER FOLLOWED
--   agent_probe            |   240 |   40 |    20 |   0 |   50 |  150 | 0  | 09-09 09:55 | followed
--   cuopt                  |   136 |   27 |    27 |   0 |   47 |   62 | 0  | 08-30 04:36 | followed
--   forward_lex            |    90 |    0 |     0 |   0 |   67 |    0 | 23 | 09-13 01:32 | NEVER HEARD
--
-- The two zeros have different causes and the verdict column is ordered to
-- separate them: service_priority is asked and loses the resource every time
-- (0188), while forward_lex is never asked at all because the selector's
-- pre-filter rejects every row it writes (0186, L-61) -- its 67 superseded rows
-- prove it was closed out without ever being consumed, which is why 'NEVER HEARD'
-- must be tested BEFORE 'submitted, not yet consumed' (23 of its rows are still
-- pending from the same run).
--
-- TWO COLUMNS THAT DO NOT RECONCILE ROW-FOR-ROW, on purpose:
--   * 'consumed' counts DECISIONS naming the source; greedy_constrained's 85,822
--     exceeds its 12,569 proposals because the local path stamps that source on
--     its own heuristic actions too, proposal or no proposal. Read 'consumed' as
--     "this name appeared in an enacted action", not as "a proposal was taken".
--   * agent_probe shows 40 credited against 20 consumed decisions: the two numbers
--     come from different ledgers (the proposal's status vs the decision's source)
--     and one decision can close more than one pending proposal for an entity.
-- Neither is a defect. Both are reasons to read the VERDICT column rather than
-- doing arithmetic across the two ledgers.

-- 2. THE STALENESS HALF: a proposer that has stopped submitting entirely.
--    cuOpt's last proposal is 2026-08-30, which is not a bug -- SOLVER_STATE.md
--    §9 established the NVIDIA endpoint has not been called since -- but it must
--    never be quoted in the present tense, and this is the query that says so.
SELECT source,
       max(created_at)::date                               AS last_submitted,
       (now()::date - max(created_at)::date)               AS days_silent,
       count(*)                                            AS lifetime_proposals
  FROM public.ottoq_external_proposals
 GROUP BY 1 ORDER BY 3 DESC;

-- 3. THE OUTCOME SPECTRUM for any source that is consumed, so "never followed"
--    always arrives with its reason attached. Parameterise the source.
SELECT d.outcome_status, count(*) AS n,
       min(d.created_at)::date AS first, max(d.created_at)::date AS last
  FROM public.ottoq_decisions d
 WHERE d.enacted_action->>'source' = 'ottoq_service_priority'   -- <- the source under test
 GROUP BY 1 ORDER BY n DESC;
-- MEASURED: noop_no_candidate | 446 | 2026-08-29 | 2026-09-13. One outcome, every time.

-- ---------------------------------------------------------------------------
-- THE RULE THIS FILE EXISTS TO ENFORCE
--
-- "Agents propose, the solver disposes" is two claims, and the ledger only ever
-- proved the first one. A proposer that submits and is never followed is not
-- propose/dispose -- it is a proposer talking to itself, and it will keep looking
-- healthy in every count we publish (proposals, fires, sources, uptime) while
-- influencing nothing.
--
-- So: after every round and every demo, query 1 must show a non-zero 'credited'
-- for every source whose 'submitted' grew since the last run, or the difference
-- is a finding with a name. Two verdicts are legitimate and must be stated, not
-- averaged: 'NEVER HEARD' means the door took it and the selector refused it;
-- 'ASKED AND NEVER FOLLOWED' means the selector returned it and physical reality
-- overruled it. They have different fixes (0263 for the first, 0264 and 0188's
-- candidates for the second) and conflating them wasted the first live D3 run.
-- ---------------------------------------------------------------------------
