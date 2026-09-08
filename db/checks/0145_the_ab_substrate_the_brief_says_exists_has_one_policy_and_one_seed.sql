-- 0145  The A/B substrate CLAUDE.md C5 says to "wrap, don't rebuild" has never
--       run a comparison. And the thing that replaces it already exists, under
--       another name: the determinism pair IS a common-random-numbers engine.
--
-- STATUS: FINDING + architecture note. No migration applied. Filed before any
-- Part B work so the plan rests on what is there rather than what the brief says.
--
-- =========================================================================
-- Q1. WHAT CLAUDE.md C5 CLAIMS, AND WHAT IS ACTUALLY IN THE TABLE
-- =========================================================================
--
-- C5, verbatim: "ottoq_ab_runs already pairs OTTO-Q vs FIFO vs greedy under
-- common random numbers, keyed by seed -- wrap, don't rebuild."
--
-- Measured 2026-09-08:
--
--   rows ................. 68
--   distinct policies .... 1     ('otto_q')
--   distinct seeds ....... 1
--   distinct groups ...... 31    -- groups of ONE
--   scored_at span ....... 2026-08-19 .. 2026-08-24  (silent 15 days)
--
-- There is no FIFO arm, no greedy arm, and no second seed. **No comparison has
-- ever been run.** The 31 "A/B groups" each contain a single row, so nothing in
-- this table is paired against anything.
--
-- This is not a criticism of the schema, which is good -- ab_group_id, seed,
-- policy, scenario_code, ticks, plus 20 outcome columns including
-- fleet_ready_pct, throughput_per_hr, median_turnaround_min, energy_peak_kw,
-- safety_violations. It is a correction to a **capability claim**. The table is
-- a well-shaped empty instrument, and CLAUDE.md describes it as a working one.
--
-- Same class as the correction Part 3 already carries about its own counts:
-- "Reasoning from a stale ground-truth line is how that happened."
SELECT policy, count(*) AS rows, count(DISTINCT ab_group_id) AS groups,
       count(DISTINCT seed) AS seeds, min(scored_at)::date AS first_scored,
       max(scored_at)::date AS last_scored
  FROM public.ottoq_ab_runs
 GROUP BY policy ORDER BY rows DESC;

-- And nothing writes it. There is no scoring function in the database at all:
SELECT count(*) AS ab_scoring_functions
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND p.prosrc LIKE '%ottoq_ab_runs%';

-- Nor does any sim run carry a group:
SELECT count(*) FILTER (WHERE ab_group_id IS NOT NULL) AS runs_with_ab_group,
       count(DISTINCT policy)                          AS distinct_policies
  FROM public.ottoq_sim_runs;

-- =========================================================================
-- Q2. THE THING THAT REPLACES IT ALREADY EXISTS AND IS CALLED SOMETHING ELSE
-- =========================================================================
--
-- A valid A/B under common random numbers requires: two arms, identical world,
-- identical stochastic draws, one variable changed, outcomes compared.
--
-- `ottoq_determinism_pair(p_seed, p_ticks, p_scenario, p_depot, p_sim_start,
-- p_arm_budget_s)` already delivers **every one of those but the last two**:
--
--   * two arms, run back to back inside ONE transaction
--   * identical seed, scenario, depot and sim clock start
--   * a shared seeded RNG (twin.ottoq_sim_seeded_random) so the draws match
--   * fourteen hash atoms proving the arms were byte-identical
--
-- **That is a common-random-numbers engine.** It was built to prove the arms are
-- the SAME; an A/B is the same rig with the policy freed and the arms EXPECTED
-- to differ. The week of determinism work built the statistical spine of Part B
-- without naming it.
--
-- What it does not yet do, and this is the whole gap:
--   1. it takes no `p_policy` -- both arms run 'otto_q' (confirmed: the
--      signature has six parameters and none of them is policy);
--   2. it writes no `ottoq_ab_runs` row.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname = 'ottoq_determinism_pair';

-- =========================================================================
-- Q3. THE CONSEQUENCE FOR PART B, AND THE TRAP IN IT
-- =========================================================================
--
-- Part B's first deliverable is NOT "wire the CP-SAT proposer". It is **make the
-- pair rig take a policy and score both arms**, because until that exists no
-- proposer claim -- cuOpt, CP-SAT, or the local path -- can carry a run ID, and
-- `CLAUDE.md` rule 6 forbids the claim without one.
--
-- **THE TRAP, named before it is walked into.** Under CRN with a varied policy,
-- the two arms diverge by construction, and once they diverge the seeded RNG is
-- consumed at different rates. Draw N in arm A and draw N in arm B stop
-- describing the same event. That is the classic CRN failure and it silently
-- destroys the pairing that makes the comparison low-variance.
--
-- The standard remedy is to stream-separate the randomness: one substream per
-- source of variation (arrivals, service durations, faults, weather), each
-- indexed by ENTITY and SIM TIME rather than by call order, so arm B draws the
-- same arrival time for vehicle V at tick T no matter how many draws the policy
-- made before it. Whether twin.ottoq_sim_seeded_random is already indexed that
-- way, or is a bare call-ordered sequence, is **not established here** and is the
-- first thing to measure -- it decides whether the A/B needs a new RNG or just a
-- new parameter.
--
-- NOT ESTABLISHED, and not to be implied:
--   * that any proposer improves any KPI. Still zero A/B pairs, as SOLVER_STATE
--     §9 said and §10 repeated.
--   * that the 20 outcome columns in ottoq_ab_runs are the right five KPIs.
--     CLAUDE.md 2.9 names five canonical KPIs; this table has twenty columns and
--     the overlap has not been checked.

-- =========================================================================
-- Q4. THE CRN TRAP Q3 NAMED DOES NOT EXIST HERE — MEASURED, NOT ASSUMED
-- =========================================================================
--
-- Q3 named the classic failure: under CRN with a varied policy, the arms
-- diverge, consume the random stream at different rates, and draw N stops
-- meaning the same thing in each arm. Checked, and **it cannot happen in this
-- engine.**
--
--   twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text)
--     v_hash := abs(hashtextextended(p_seed::text || ':' || p_salt, p_seed));
--     RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
--
-- **There is no state.** No sequence, no cursor, no consumption. The value is a
-- pure function of (seed, salt) — a counter-based / hash-indexed generator, the
-- same family as Philox and the modern best practice for reproducible
-- simulation. Two arms making different numbers of draws still get identical
-- values for identical keys, because there is no "next" to fall out of step.
--
-- And the keys are content-addressed, not order-addressed. Sampled across the
-- engine: 'pick:'||vehicle_id, 'soc:'||id, 'ret:'||id, 'btemp:'||vehicle_id,
-- 'precip_day:'||day, 'veh_soh:'||id, 'veh_cons:'||id.
--
-- The strongest case is the telemetry path, whose entropy key is:
--
--   COALESCE((SELECT random_seed FROM ottoq_sim_runs WHERE sim_run_id = p_run),
--            p_run::text)                        -- the SEED, not the run id
--   || p_vehicle::text                           -- the entity
--   || twin.ottoq_sim_clock_salt(p_run, p_clock) -- seconds since THIS run's
--                                                -- own sim_clock_start
--
-- `ottoq_sim_clock_salt`'s own comment: *"pure function of (run, sim clock),
-- identical across same-seed runs regardless of the wall clock at start."*
--
-- So the key is **(seed, entity, sim-time)** — never the run uuid, never the wall
-- clock. Two arms of a policy comparison sharing a seed draw the same value for
-- the same vehicle at the same sim second **whatever the policy did in between.**
--
-- **CRN survives policy variation by construction. Part B needs no new RNG.**
-- That property was installed by migration 0052 ("run-relative salt, never run
-- uuid + absolute clock") for a different reason, and it is what makes the A/B
-- possible now.
--
-- A HYPOTHESIS FORMED AND REJECTED, recorded because it was wrong. The salt in
-- `ottoq_comms_emit_telemetry` is the bare constant `'drop'`, which looked like a
-- welded coin — one draw, identical for the whole run, the same defect class as
-- the RNG canary that was blind past the first asset. It is not. The variation
-- lives in `v_seed`, not the salt, and `v_seed` carries seed + vehicle + sim
-- time. Reading the surrounding 560 characters rather than the matched fragment
-- is what showed it.
--
-- =========================================================================
-- WHAT PART B ACTUALLY NEEDS, now that the substrate is known
-- =========================================================================
--
--   1. `p_policy` on the pair rig, and both arms scored into ottoq_ab_runs.
--      NOT a new RNG (Q4), NOT a new pairing mechanism (Q2), NOT a new metrics
--      table (the 20 columns already exist).
--   2. A verdict that inverts: the determinism pair PASSES when the arms are
--      identical; the A/B pair passes when the arms are identical **on the
--      world** (same arrivals, same faults, same weather) and differ **only on
--      what the policy decided**. That distinction needs its own assertion, and
--      it is the one thing here that has no precedent in the existing rig.
--   3. Reconciliation of ottoq_ab_runs' 20 outcome columns against CLAUDE.md
--      2.9's five canonical KPIs. Not yet done, named in Q1.
