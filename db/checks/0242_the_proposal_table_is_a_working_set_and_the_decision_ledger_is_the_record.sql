-- ============================================================================
-- 0242 — THE PROPOSAL TABLE IS A WORKING SET, AND THE DECISION LEDGER IS THE
--        RECORD. COUNT PROPOSER INFLUENCE FROM ottoq_decisions.l2_engine.
-- ============================================================================
-- Measured 2026-09-14 against run e02e92b4-8351-4ac2-a069-6719c3a3852a
-- (busy_day, 48 ticks, flagship depot, started by otto_twin through the
-- ordinary twin entry point -- i.e. the path the UI uses).
--
-- WHY THIS EXISTS. Reading that run I found 5 rows in ottoq_external_proposals
-- and 22 decisions crediting l2_engine='greedy_constrained'. Twenty-two
-- decisions attributed to five proposals reads as an attribution defect of the
-- exact class this project keeps convicting -- a label and the thing it names
-- written by different mechanisms (0240 ETA, 0241 decisions, 0318).
--
-- IT IS NOT ONE. I read the assignment before believing the count, per 0235.
-- ottoq_l2_optimize_assignments opens with:
--
--     DELETE FROM ottoq_external_proposals
--      WHERE sim_run_id = p_sim_run_id
--        AND source = 'greedy_constrained'
--        AND action_context = 'stall_assignment';
--
-- and ottoq_l2_propose_seat does the same for its own source, with the comment
-- "fresh start each tick, exactly as greedy_constrained does for its own rows."
-- The table is a per-tick working set BY DESIGN: the proposer re-proposes from
-- current state every tick and must not accumulate stale offers. The 5 rows are
-- tick 48's proposals. They are not the run's proposals.
--
-- THE MEASUREMENT THAT SETTLES IT (lifetime, pg_stat_user_tables):
--   n_tup_ins  340,690
--   n_tup_del  332,028      -- 97.5% of everything ever proposed is gone
--   live rows   16,005
--
-- SO THIS IS THE cuOpt LEDGER PROBLEM AGAIN, IN A SECOND TABLE. CLAUDE.md rule
-- 6 already carries the correction for cuopt_invocation_log: a table that looks
-- like a ledger, is named like a ledger, and is actually run-scoped working data
-- cannot answer "how many." The difference is that cuopt_invocation_log was
-- purged by a mechanism its own COMMENT denied; ottoq_external_proposals deletes
-- its own rows deliberately, one statement into the proposer, and says so. The
-- design is right. Only the arithmetic done on top of it is wrong.
--
-- WHAT MAY BE SAID. The durable record of proposer influence is
-- ottoq_decisions.l2_engine -- written once per decision, never deleted inside
-- a run, and already inside the certified substrate.
--
--   DO NOT SAY: "the proposer produced N proposals" sourced from
--               ottoq_external_proposals. That number is a snapshot of the last
--               tick and shrinks to near zero the moment a run ends.
--   SAY:        "N of M enacted decisions in run <id> credit proposer <source>,"
--               sourced from ottoq_decisions.
--
-- FOR THIS RUN, the honest sentence: of 122 stall_assignment decisions,
-- 22 (18.0%) credit greedy_constrained, 60 (49.2%) reservation_honoured and
-- 40 (32.8%) deterministic_v1. Proposer credit first appears at tick 24 and
-- runs to tick 48 across 10 distinct ticks -- the proposer has nothing to
-- propose until vehicles have arrived, which is the expected shape, not a
-- starved layer.
--
-- A NOTE ON h_prop. The certification hashes this working set. That remains
-- correct for its purpose -- two arms must agree tick by tick on what was
-- proposed -- and is unaffected by anything above. h_prop proves the proposals
-- MATCHED; it was never a count and must not be quoted as one.
-- ============================================================================

-- A1. The working-set churn. Expect n_tup_del within a few percent of n_tup_ins.
SELECT 'A1 churn' AS assertion,
       n_tup_ins, n_tup_del,
       round(100.0 * n_tup_del / NULLIF(n_tup_ins,0), 1) AS pct_deleted,
       n_live_tup
  FROM pg_stat_user_tables
 WHERE relname = 'ottoq_external_proposals';

-- A2. The DELETE is really there, in both proposers. Expect 2 rows.
SELECT 'A2 self-delete' AS assertion, p.proname
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_l2_optimize_assignments','ottoq_l2_propose_seat')
   AND p.prosrc ~* 'DELETE\s+FROM\s+ottoq_external_proposals'
 ORDER BY p.proname;

-- A3. The durable record. Run this for any run id; it is the quotable shape.
SELECT 'A3 attribution' AS assertion,
       d.action_context,
       COALESCE(d.l2_engine,'(null)') AS l2_engine,
       count(*) AS n,
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (PARTITION BY d.action_context),0), 1) AS pct_of_context
  FROM ottoq_decisions d
 WHERE d.sim_run_id = 'e02e92b4-8351-4ac2-a069-6719c3a3852a'::uuid
   AND d.action_context = 'stall_assignment'
 GROUP BY d.action_context, d.l2_engine
 ORDER BY n DESC;

-- A4. Proposer credit over the run's timeline -- the shape, not just the total.
SELECT 'A4 timeline' AS assertion,
       count(DISTINCT d.tick_seq) AS ticks_with_credit,
       count(*)                   AS proposer_sourced_decisions,
       min(d.tick_seq)            AS first_tick,
       max(d.tick_seq)            AS last_tick
  FROM ottoq_decisions d
 WHERE d.sim_run_id = 'e02e92b4-8351-4ac2-a069-6719c3a3852a'::uuid
   AND d.l2_engine = 'greedy_constrained';
