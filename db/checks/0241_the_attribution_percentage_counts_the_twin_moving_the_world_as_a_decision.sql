-- ===========================================================================
-- 0241  "87% OF ENACTED DECISIONS CARRY NO SOURCE" IS TRUE AND MISLEADING:
--       THE DENOMINATOR COUNTS THE TWIN ADVANCING A PLAN AS A DECISION
--
-- G67 has stood as "87.1% of enacted decisions carry no source -- the
-- attribution join credits 12.9%", and I repeated it to the founder today as
-- evidence that OTTO-Q "mostly can't tell you who decided what", and that
-- attribution was therefore THE BLOCKER for the agents-propose/solver-disposes
-- claim.
--
-- That was wrong, and the error is this repo's most-convicted defect class
-- wearing yet another costume: A PERCENTAGE OVER A DENOMINATOR THAT MIXES TWO
-- DIFFERENT KINDS OF THING.
--
-- Measured on live run e02e92b4-8351-4ac2-a069-6719c3a3852a (Benchmark depot,
-- bench_busy_day, seed 606060, agentic layer ARMED, 48 ticks):
--
--   every row in ottoq_decisions                1,663    118 sourced     7.1%
--   contested decisions only                      189    118 sourced    62.4%
--     of which stall_assignment                   155    118 sourced    76.1%
--   itinerary_amended                           1,280      0 sourced     0.0%
--
-- ---------------------------------------------------------------------------
-- WHY THE DENOMINATOR IS WRONG
--
-- itinerary_amended is 1,280 of 1,663 rows -- 77% of the table, and the entire
-- reason the headline reads 7%. Its writer is
--
--     twin.ottoq_sim_advance_flow_contract        (verb: amend_plan)
--
-- a TWIN function. That is the simulator advancing an itinerary as sim time
-- passes. There is no alternative it was chosen over and no proposer that could
-- have proposed it; asking which agent is responsible for it is a category
-- error. It is the world moving, recorded in a table called "decisions".
--
-- Strip it and the picture inverts: on stall_assignment -- the ONE context
-- where a proposer genuinely competes with the kernel for an outcome -- 118 of
-- 155 decisions name their source. 76%, not 13%.
--
-- ---------------------------------------------------------------------------
-- WHAT SURVIVES OF G67, because it is not nothing
--
-- Two genuine orchestration contexts are 0% attributed on this run:
--     bess_dispatch    24 rows, 0 sourced   (verb set_bess)
--     redeployment     10 rows, 0 sourced   (verbs deploy, hold_in_staging)
-- and 37 of 155 stall_assignments still carry no source.
--
-- So the real gap is ~71 unattributed contested decisions, not ~1,545. That is
-- a fixable seam, not a foundational hole. G67's REMEDY was right; its
-- MEASUREMENT chose a denominator that made a modest seam look like a collapse.
--
-- ---------------------------------------------------------------------------
-- THE CONSEQUENCE, which is why this file exists rather than a code change
--
-- I told the founder attribution was the blocker for proving the agentic layer,
-- and recommended going after it before getting a proposer running. On these
-- numbers that priority is backwards. The stall-assignment path -- the one a
-- proposer would contest -- ALREADY records who won 76% of the time. What is
-- missing from run e02e92b4 is not the ability to attribute a proposal; it is
-- THAT NO PROPOSAL WAS EVER MADE:
--
--     ottoq_external_proposals for this run    0 rows
--     ottoq_cuopt_deferrals for this run       0 rows
--
-- The run was correctly armed -- ottoq_agentic_arm returned verdict "armed",
-- 3 of 3 dials in force -- but arming opens a door and does not make anyone
-- walk through it. cuOpt reaches an external endpoint and has not called since
-- 2026-08-30; the CP-SAT bridge is a dispatched job. Point a proposer at a live
-- armed run and the existing 76% attribution is enough to SEE it win or lose.
--
-- Fix the denominator (below), then get a proposer running. In that order, and
-- neither one is the migration I was about to write.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- §A  THE HEADLINE AND THE THREE DENOMINATORS, side by side.
--     Substitute any run id; the shape holds.
-- ---------------------------------------------------------------------------
WITH R AS (SELECT 'e02e92b4-8351-4ac2-a069-6719c3a3852a'::uuid AS id)
SELECT COALESCE(d.resolved_action_context, d.action_context) AS context,
       count(*)                                              AS rows,
       count(*) FILTER (WHERE d.enacted_action ? 'source')    AS sourced,
       round(100.0 * count(*) FILTER (WHERE d.enacted_action ? 'source')
             / NULLIF(count(*),0), 1)                         AS pct,
       COALESCE(string_agg(DISTINCT d.enacted_action->>'verb', ','), '(none)') AS verbs
  FROM public.ottoq_decisions d, R
 WHERE d.sim_run_id = R.id
 GROUP BY 1 ORDER BY 2 DESC;
-- MEASURED at 48 ticks:
--   itinerary_amended     1280   0    0.0%  amend_plan            <- twin, not a decision
--   stall_assignment       155 118   76.1%  assign_stall, hold_no_space
--   task_start             129   0    0.0%  promote_ready, skip_wash
--   bay_reconcile           51   0    0.0%  bind_bay_occupant, displace_and_bind
--   bess_dispatch           24   0    0.0%  set_bess              <- genuine gap
--   triage_verdict          11   0    0.0%  triage_clear/confirm/escalate
--   redeployment            10   0    0.0%  deploy, hold_in_staging  <- genuine gap
--   gate_intake_no_charge    3   0    0.0%  gate_intake

-- ---------------------------------------------------------------------------
-- §B  WHO WRITES WHAT. Eight functions INSERT into ottoq_decisions; four never
--     set a source key at all, and ottoq_decide_tick sets one at 4 of its 13
--     enacted_action sites. Same N-writers-one-labeller shape as db/checks/0240
--     found for the ETA -- a third instance in one day.
-- ---------------------------------------------------------------------------
SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc ~ '''source''')                                                   AS sets_source,
       (length(p.prosrc)-length(replace(p.prosrc,'enacted_action','')))
         / length('enacted_action')                                                AS enacted_sites,
       (length(p.prosrc)-length(replace(p.prosrc,'''source''','')))
         / length('''source''')                                                    AS source_sites
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND p.prosrc ~* 'INSERT\s+INTO\s+(public\.)?ottoq_decisions'
 ORDER BY 2, 1;
-- MEASURED: no source at all -- ottoq.ottoq_bind_unbooked_bay_occupants,
--   public.ottoq_shield_and_log, twin.ottoq_sim_advance_flow_contract,
--   twin.ottoq_sim_advance_visit_atoms.
-- Sets it -- ottoq.ottoq_enact_inspection_seam, ottoq.ottoq_reoptimize_reservation_book,
--   public.ottoq_decide_tick (4 of 13 sites), public.ottoq_fn_backup_enact_cuopt_batch.

-- ---------------------------------------------------------------------------
-- §C  THE FIX, in the order the measurement actually supports
--
--  1. SEPARATE THE TWO KINDS OF ROW rather than raising a percentage. A
--     contested decision (the kernel chose X over Y, and a proposer could have
--     argued) is a different object from a world-advance record. Today one
--     table holds both and every ratio over it is ambiguous. Options, cheapest
--     first: a `decision_kind` column with a CHECK, or a view
--     ottoq_contested_decisions that the attribution metric reads instead of
--     the raw table. The view costs nothing and cannot break a writer.
--
--  2. THEN close the real seam -- bess_dispatch, redeployment, and the 37
--     unsourced stall_assignments -- which is ~71 rows on this run, not 1,545.
--
--  3. And do NOT "fix" itinerary_amended by stamping a source on it. Inventing
--     an attribution for a row nothing proposed is the 0322 lesson from the
--     other side: a populated field that says something untrue is worse than an
--     empty one that says what it is.
--
--  NOT APPLIED. Round 43 is certifying 0313-0319 and any migration moves the
--  recert floor past every pair already banked. This file is the measurement;
--  the change belongs in the window after the round, behind 0320-0322.
-- ---------------------------------------------------------------------------
