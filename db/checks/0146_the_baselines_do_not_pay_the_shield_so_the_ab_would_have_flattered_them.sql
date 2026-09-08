-- 0146  Every baseline policy bypasses the L1 rule shield. An A/B built on them
--       would have reported greedy beating OTTO-Q on throughput, and the reason
--       would have been that greedy checks nothing.
--
-- STATUS: FINDING, filed BEFORE the A/B rig is built. This is the trap that
-- `db/checks/0145` Q3 was written to look for and did not find; it is here
-- instead, one layer down.
--
-- =========================================================================
-- Q1. THE MEASUREMENT
-- =========================================================================
--
--   policy / path                          L1 rules   calendar   sizeof
--   -------------------------------------  ---------  ---------  ------
--   public.ottoq_decide_tick   (otto_q)      YES        YES       82,463
--   public.ottoq_fifo_tick                   no         yes        3,547
--   public.ottoq_greedy_tick                 no         no           615
--   public.ottoq_baseline_fifo               no         no         3,821
--   twin.ottoq_sim_auto_dispatch_tick        no         no         9,032   <- greedy delegates here
--   twin.ottoq_sim_auto_charge_assign_tick   no         no         3,694   <- and here
--
-- **Only OTTO-Q evaluates the 52-rule shield. Only OTTO-Q books through the
-- stall calendar.** Two of the four baselines do not touch either.
--
-- `CLAUDE.md` 2.5 calls Layer 1 "Inviolable constraints including per-OEM SLAs."
-- A baseline that does not evaluate them is not solving the same problem.
SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc LIKE '%ottoq_evaluate_rule%' OR p.prosrc LIKE '%shield_probe%'
        OR p.prosrc LIKE '%ottoq_rules%')                      AS reaches_l1_rules,
       (p.prosrc LIKE '%ottoq_book_stall%' OR p.prosrc LIKE '%find_and_book%'
        OR p.prosrc LIKE '%ottoq_reserve_stall%')              AS books_via_calendar,
       length(p.prosrc)                                        AS chars
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname='public' AND p.proname IN
          ('ottoq_decide_tick','ottoq_fifo_tick','ottoq_greedy_tick','ottoq_baseline_fifo'))
    OR (n.nspname='twin'   AND p.proname IN
          ('ottoq_sim_auto_dispatch_tick','ottoq_sim_auto_charge_assign_tick'))
 ORDER BY 1;

-- =========================================================================
-- Q2. WHAT THE NAIVE A/B WOULD HAVE REPORTED, AND WHY IT IS WORSE THAN WRONG
-- =========================================================================
--
-- `ottoq_ab_runs` carries `throughput_per_hr`, `vehicles_turned_around`,
-- `median_turnaround_min` -- and, separately, `safety_violations` and
-- `safety_critical_violations`.
--
-- Run the comparison as it stands and greedy plausibly WINS the first group,
-- because it dispatches without evaluating a single rule. The number would be
-- arithmetically correct and completely misleading: it measures the cost of
-- safety, not the value of intelligence. **That is the kind of number that ends
-- up in a deck**, and `CLAUDE.md`'s credibility rule -- no number without a run
-- ID -- does not protect against it, because the number WOULD have a run ID.
--
-- A run ID makes a number reproducible. It does not make it meaningful.
--
-- =========================================================================
-- Q3. THE ARCHITECTURAL POINT, which is bigger than this A/B
-- =========================================================================
--
-- **The L1 shield is not part of the policy. It is part of the problem
-- definition.** A policy chooses among feasible actions; the shield defines
-- which actions are feasible. Swapping the policy must not swap the constraint
-- set, exactly as swapping the policy must not swap the seed.
--
-- So the A/B has the same shape as the determinism pair, one layer up:
--
--   determinism pair   hold EVERYTHING constant, vary NOTHING, assert identical
--   A/B pair           hold WORLD + SHIELD constant, vary POLICY, compare outcomes
--
-- and the shield belongs on the "hold constant" side of that line.
--
-- =========================================================================
-- WHAT THIS REQUIRES BEFORE ANY A/B NUMBER IS QUOTED
-- =========================================================================
--
-- Three options, in order of preference:
--
--   1. **Shield the baselines.** Route every policy's proposed assignments
--      through the same L1 evaluation the decide path uses, so all arms pay the
--      same price and differ only in what they propose. Most faithful to 2.5's
--      "inviolable"; most work.
--   2. **Report safety alongside throughput, always, and refuse to publish
--      either alone.** A `throughput_per_hr` for an unshielded arm is only
--      interpretable next to its `safety_violations`. Cheap; relies on
--      discipline rather than structure, which this repo has repeatedly found
--      to be insufficient (G18, G25, G28).
--   3. **Relabel the baselines honestly** -- they are not "OTTO-Q without the
--      clever part," they are "dispatch with no safety layer." Necessary
--      regardless of 1 or 2.
--
-- NOT ESTABLISHED, and not to be implied:
--   * that greedy would in fact win on throughput. It has never been run. The
--     claim here is about what the comparison would MEAN, not what it would say.
--   * that the baselines are wrong to exist. An unshielded lower bound is a
--     legitimate reference point -- provided it is labelled as one.
--   * that `ottoq_fifo_tick`, which does book through the calendar, is affected
--     the same way as greedy, which does not. They are two different degrees of
--     bypass and Q1 keeps them separate.
--
-- A CORRECTION TO MY OWN FIRST READING, recorded because it was wrong and it
-- was the reason this check exists. I probed the baselines by counting literal
-- INSERT/UPDATE statements and concluded `ottoq_greedy_tick` "writes nothing in
-- 615 characters" -- effectively a stub. It is not a stub: it **delegates** to
-- `twin.ottoq_sim_auto_charge_assign_tick` and `twin.ottoq_sim_auto_dispatch_tick`,
-- both of which write. Counting statements in one body is not a measure of what
-- a function does. Reading the 615 characters is what corrected it, and reading
-- the two delegates is what found the real defect.

-- =====================================================================
-- AMENDED 2026-09-08 by db/checks/0148 (G31).
--
-- This check named ONE gated step and called it "the shield." It read
-- ottoq_decide_tick and did not read its caller. The guard is in
-- public.ottoq_sim_decide_and_dispatch and wraps SEVEN calls, of which
-- six are correctly gated intelligence and one --
-- ottoq.ottoq_close_satisfied_charge_needs -- is a correctness step
-- that belongs to the world, not to any policy.
--
-- The consequence reverses partly. This check said the baselines are
-- FLATTERED (they skip the shield). They are also PENALIZED (they skip
-- need closure, so they book chargers for needs that no longer exist).
-- Two contaminations, opposite signs, different magnitudes, no
-- cancellation. See 0148 §4. Fix drafted as migration 0231.
--
-- Nothing above this line is edited; it was right about what it read.
-- =====================================================================
