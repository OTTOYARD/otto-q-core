-- 0251  THE LOOP CLOSES END TO END: 17 AGENT CHAINS -> 17 NVIDIA CALLS ->
--       24 PROPOSALS -> 3 CHAINS WITH AN ENACTED PROPOSAL. THE REVIEW THAT IS
--       SUPPOSED TO REPORT THAT SAYS "solver_returned_nothing".
--
-- Chase's governing requirement is one sentence: "validation that the
-- functionality between OTTO-Q and its agent and deterministic layers are fully
-- functioning and visible in OTTO-Twin when a simulation is started." 0342 built
-- the return leg (`ottoq_agent_review`). This file runs it on a live run and
-- checks its answer against the ledgers underneath it.
--
-- Live run a51acc84-9981-475d-9649-ed788bdd4227, busy_day, twin depot
-- 11111111-… (rule 8), wall start 2026-09-19 21:55 UTC, tick ~457.
--
-- ══ 1. THE LOOP DOES CLOSE, AND IT IS TRACEABLE PER CHAIN ══════════════════
--
-- 0331 stamps an `agent_solver_chain_id` on the agent's decision and the same id
-- into the proposal JSON at `proposal->'agent_handoff'->>'chain_id'`. Joined on
-- it, on this run:
--
--   agent chains that reached a proposal        17
--   of those, chain id matches an agent decision 17 of 17   <- linkage is sound
--   chains with at least one ENACTED proposal    3 of 17
--   NVIDIA calls (http_status 200)              17, ticks 29-339
--   proposals returned                          24
--   proposals carrying the chain id             24 of 45
--
-- The 17 NVIDIA calls and the 24 proposals agree exactly with the 24 stamped
-- rows, so the chain is not inferred — it is the producer's own key, end to end,
-- agent -> solver -> kernel. **That is the loop Chase asked to see, and it
-- works.** It is not a claim about quality (G71); it is a claim about linkage.
--
-- ══ 2. BUT THE REVIEW REPORTS THE OPPOSITE, AND THE CAUSE IS ITS WINDOW ═════
--
-- `SELECT public.ottoq_agent_review(<run>, 3)` returns, right now:
--
--   verdict            : solver_returned_nothing
--   totals.enacted     : 0
--   per-chain linkage  : none, none, none
--   per-chain kernel   : null, null, null
--
-- Each of those three per-chain readings is CORRECT: the function examines the
-- last 3 nemotron chains, which sit at ticks 423 / 425 / 427, and the most
-- recent stamped proposal on this run is at tick **339**. Those chains genuinely
-- have no proposals, and `linkage: 'none'` is 0342 being honest rather than
-- reporting zeros that read as refusals — exactly as its comment says.
--
-- **The defect is the verdict, not the linkage.** `solver_returned_nothing` is
-- one of six machine-actionable words and it carries no window qualifier, so a
-- 3-chain sample is published in the vocabulary of a run-level finding. On this
-- run the true run-level statement is the opposite: 3 of 17 chains had a
-- proposal enacted. An auditor reading the review would conclude the solver is
-- dead on a run where it placed 17 calls and got 3 chains enacted.
--
-- (And this paragraph first said FOUR. I read "enacted > 0" off a 17-row listing
-- by eye instead of aggregating it; Q1 returns 3. Left noted rather than silently
-- corrected, in a file whose subject is a count reported without its query.)
--
-- Two things would fix it and they are different sizes: name the window in the
-- verdict (`solver_returned_nothing_in_last_N_chains`), or have the verdict
-- consider the run and the window separately. Neither is done here — this file
-- measures; tracked as G73.
--
-- ══ 3. AND WHY THE SOLVER WENT QUIET AT TICK 339 — SAME FINDING AS 0250, ════
--      FROM THE OTHER SIDE
--
-- `cuopt_invocation_log` on this run, by stage and abstention:
--
--   stage  abstained_reason                 n    ticks      proposals
--   edge   (none, http 200)               17    29-339     24
--   edge   no_free_stalls_demand_present  70    36-416      0
--   sql_gate delegated_to_agent_chain    243     0-451      -
--   sql_gate first_refusal_arm           111     0-399      -
--   sql_gate sql_gate_no_candidates       30    14-450      -
--
-- cuOpt has not called NVIDIA since tick 339 because it is **abstaining at the
-- edge with `no_free_stalls_demand_present`** — 70 times, out to tick 416. It is
-- declining to solve an assignment problem with demand and no supply.
--
-- That is 0250's stall saturation confirmed independently from the solver side:
-- l2 87% occupied, dcfc 80%, 5 free charge stalls of 40 against 120 vehicles.
-- **cuOpt is not broken and it is not being ignored; it is correctly refusing a
-- problem with no feasible action, and the kernel refuses the few it does make
-- for `stall_occupied` on the same two stall types.** Three independent
-- instruments — stall census, proposal dispositions, solver abstentions — agree.
-- The binding constraint on this depot is charging capacity.
--
-- Congestion corroborates it in the event stream: `twin.staging_overflow` 420,
-- `twin.recharge_stranded` 404, `ottoq.refusal_escalated` 526 on this run.
--
-- ══ 4. A CORRECTION TO G72, WHICH I OVERSTATED YESTERDAY ═══════════════════
--
-- G72 says the enactment rate "is not measurable from any durable table." Too
-- strong, in the direction that understates us. WITHIN a run it IS measurable,
-- by the chain id stamped into the proposal JSON — section 1 measures it. What
-- G72 got right and this does not change:
--   * ACROSS runs it is still lost: `ottoq_external_proposals` is class `engine`
--     and the demo-run purge takes it.
--   * `ottoq_proposer_fire_log` still has **0** columns matching `%enact%` and
--     still holds only `forward_lex` rows — 112 of 112, never one cuOpt row — so
--     it is not the instrument, and the "it went dark" reading of it was also
--     wrong: it never logged this path at all.
-- So the honest scope is: **enactment is traceable within a live run and not
-- after it.** G72 is amended rather than withdrawn.
--
-- ══ 5. TWO READINGS I ALMOST PUBLISHED FROM THIS RUN, BOTH WRONG ═══════════
--
-- Recorded because the trap is reusable and rule 7 names it exactly: *"never
-- restate a stored UTC timestamp as though it were"* something else.
--
--   (a) "The fleet is frozen — no vehicle has changed state in 457 ticks."
--   (b) "Every run inherits the previous run's wreckage — `ottoq_start_demo_run`
--        never resets `vehicles`, and all 120 vehicles' state predates the run."
--
-- Both came from one comparison: `vehicles.last_state_change < ottoq_sim_runs
-- .started_at`. **`last_state_change` is on the SIM clock; `started_at` is wall
-- clock.** This run's wall start is 21:55 UTC and its `sim_clock_start` is
-- 13:48, so every sim-clock stamp is "before" the wall start by construction and
-- the comparison can only ever return 120 of 120. The decisive witness:
-- `max(last_state_change)` = **2026-09-19 18:32:54.146016**, identical to
-- `sim_clock_current` to the microsecond. Measured against the right clock,
-- **116 of 120 vehicles changed state within this run's sim window**, and the
-- event stream carries **11,196 `vehicle.state_changed`** rows — whose payload
-- diffs show `updated_at` moving on wall time and `last_state_change` moving on
-- sim time in the same row, which is the mechanism in one object.
--
-- (b) was doubly wrong: `ottoq_start_demo_run` genuinely never updates
-- `vehicles` — `prosrc` does not match `update.*vehicles` at all — so the
-- premise was true and the conclusion still false, because the state it was
-- said to leave stale is in fact being rewritten 11,196 times by the tick path.
-- A true premise is not a finding.
--
-- Q6 is the comparison done correctly, kept so the trap is a test rather than a
-- paragraph. Nothing in this file changes engine state.
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  the loop, per chain, joined on the producer's own key. This is section 1.
WITH r AS (
  SELECT sim_run_id, tick_count FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
),
pc AS (
  SELECT p.proposal->'agent_handoff'->>'chain_id' AS chain_id,
         max(p.tick_seq)                          AS last_tick,
         count(*)                                 AS proposals,
         count(*) FILTER (WHERE p.status = 'enacted') AS enacted
    FROM public.ottoq_external_proposals p
    JOIN r ON r.sim_run_id = p.sim_run_id
   WHERE p.proposal->'agent_handoff' ? 'chain_id'
   GROUP BY 1
),
ac AS (
  SELECT COALESCE(d.proposed_action->>'agent_solver_chain_id',
                  d.context_frame->>'agent_solver_chain_id') AS chain_id,
         max(d.tick_seq) AS agent_tick
    FROM public.ottoq_decisions d
    JOIN r ON r.sim_run_id = d.sim_run_id
   WHERE d.l2_engine = 'nemotron'
   GROUP BY 1
)
SELECT (SELECT tick_count FROM r)                              AS now_tick,
       count(*)                                                AS chains_reaching_a_proposal,
       count(*) FILTER (WHERE ac.chain_id IS NOT NULL)          AS chains_linked_to_an_agent_decision,
       count(*) FILTER (WHERE pc.enacted > 0)                   AS chains_with_an_enacted_proposal,
       sum(pc.proposals)                                        AS proposals_stamped,
       max(pc.last_tick)                                        AS last_proposal_tick
  FROM pc LEFT JOIN ac ON ac.chain_id = pc.chain_id;

-- Q2  the assertion behind "linkage is sound": every stamped chain resolves to
--     a real agent decision. A stamp that resolves to nothing would be worse
--     than no stamp.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
),
pc AS (
  SELECT DISTINCT p.proposal->'agent_handoff'->>'chain_id' AS chain_id
    FROM public.ottoq_external_proposals p JOIN r ON r.sim_run_id = p.sim_run_id
   WHERE p.proposal->'agent_handoff' ? 'chain_id'
)
SELECT count(*) AS stamped_chains,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_decisions d, r
          WHERE d.sim_run_id = r.sim_run_id AND d.l2_engine = 'nemotron'
            AND COALESCE(d.proposed_action->>'agent_solver_chain_id',
                         d.context_frame->>'agent_solver_chain_id') = pc.chain_id))
         AS resolve_to_an_agent_decision,
       count(*) = count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_decisions d, r
          WHERE d.sim_run_id = r.sim_run_id AND d.l2_engine = 'nemotron'
            AND COALESCE(d.proposed_action->>'agent_solver_chain_id',
                         d.context_frame->>'agent_solver_chain_id') = pc.chain_id))
         AS every_stamp_resolves
  FROM pc;

-- Q3  the review's own answer, beside the run-level truth Q1 computes. Section 2
--     is the gap between these two rows.
SELECT (public.ottoq_agent_review(
          (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE status='running' ORDER BY started_at DESC LIMIT 1), 3))
         ->> 'verdict'                                        AS review_verdict,
       (public.ottoq_agent_review(
          (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE status='running' ORDER BY started_at DESC LIMIT 1), 3))
         -> 'totals' ->> 'enacted'                            AS review_enacted,
       (public.ottoq_agent_review(
          (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE status='running' ORDER BY started_at DESC LIMIT 1), 3))
         ->> 'since_tick'                                     AS review_window_from;

-- Q4  section 3: why the solver went quiet. The abstention reason is the finding.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
)
SELECT c.stage, c.abstained_reason, c.http_status,
       count(*)              AS n,
       min(c.tick_seq)       AS first_tick,
       max(c.tick_seq)       AS last_tick,
       sum(c.proposals_out)  AS proposals_out
  FROM public.cuopt_invocation_log c JOIN r ON r.sim_run_id = c.sim_run_id
 GROUP BY 1,2,3
 ORDER BY last_tick DESC;

-- Q5  section 4: the fire log is not the instrument, and never was. 0 enactment
--     columns, and one declared_source for its whole life.
SELECT count(*)                                   AS rows,
       count(DISTINCT declared_source)            AS distinct_sources,
       string_agg(DISTINCT declared_source, ', ')  AS sources,
       (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='public' AND table_name='ottoq_proposer_fire_log'
           AND column_name ILIKE '%enact%')        AS enactment_columns
  FROM public.ottoq_proposer_fire_log;

-- Q6  section 5: THE CLOCK TRAP, as a test rather than a warning. The wrong
--     comparison must return every vehicle; the right one must not, and the max
--     stamp must equal the sim clock.
WITH r AS (
  SELECT started_at, sim_clock_start, sim_clock_current
    FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
),
v AS (
  SELECT last_state_change FROM public.vehicles
   WHERE home_depot_id = '11111111-1111-1111-1111-111111111111'
)
SELECT (SELECT count(*) FROM v)                                        AS vehicles,
       (SELECT count(*) FROM v, r WHERE v.last_state_change < r.started_at)
                                                                       AS wrong_clock_says_stale,
       (SELECT count(*) FROM v, r WHERE v.last_state_change >= r.sim_clock_start)
                                                                       AS right_clock_says_active,
       (SELECT max(last_state_change) FROM v)                          AS max_stamp,
       (SELECT sim_clock_current FROM r)                               AS sim_clock_current,
       (SELECT max(last_state_change) FROM v) = (SELECT sim_clock_current FROM r)
                                                                       AS stamp_is_the_sim_clock,
       (SELECT count(*) FROM v, r WHERE v.last_state_change < r.started_at)
         = (SELECT count(*) FROM v)                                    AS wrong_clock_condemns_everything;
