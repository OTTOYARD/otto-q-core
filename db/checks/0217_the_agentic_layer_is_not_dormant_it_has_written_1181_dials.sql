-- 0217  THE AGENTIC LAYER IS NOT DORMANT. IT HAS WRITTEN 1,181 DIALS AND THE
--       LAST ONE LANDED THREE MINUTES AGO.
--
-- Measured 2026-09-14 ~04:24 UTC (11:24 PM CT, 2026-09-13). Read-only.
--
-- ---------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
-- db/checks/0213 recorded the standing rule: zero activations is evidence of
-- nothing until you know why. This file is the other end of the same rule --
-- the case where a layer everyone treats as dormant turns out to be the single
-- busiest writer in the policy table.
--
-- It also corrects an adversarial review that got the shape right and the
-- numbers wrong, which is exactly why an agent's report is re-measured before
-- it is believed.
--
-- ---------------------------------------------------------------------------
-- SECTION 1 -- THE WRITER IS LIVE, PROLIFIC, AND WRITING TODAY
--
--   updated_by    rows   first                    last
--   ottoq_prime  1,181   2026-07-15 17:16:01 UTC  2026-09-14 04:21:34 UTC
--
-- 1,181 policy-dial writes over two months, the most recent THREE MINUTES
-- before this measurement. cron job 10 (ottoq-depot-tick, */2 * * * *, active)
-- drives it.
--
-- Anyone describing the agentic layer as "not firing" is describing the
-- proposer seat, not the agent. The agent has been adjusting the engine's
-- dials continuously, for two months, and nothing in the intelligence census
-- reports it -- because the census counts DECISIONS and PROPOSALS, and a dial
-- write is neither.
SELECT pp.updated_by, count(*) AS dial_rows,
       min(pp.updated_at) AS first_write, max(pp.updated_at) AS last_write,
       count(DISTINCT pp.param_key) AS distinct_keys
  FROM public.ottoq_policy_params pp
 WHERE pp.updated_by ILIKE '%prime%'
 GROUP BY 1;

-- ---------------------------------------------------------------------------
-- SECTION 2 -- 49 OF THOSE WRITES LANDED INSIDE CERTIFICATION RUNS
--
--   cert_harness runs written into   17
--   dial rows                        49
--   keys                             deploy_peak_fraction, deploy_surge_catchup,
--                                    energy_demand_factor_expensive,
--                                    energy_demand_factor_peak,
--                                    energy_reserve_shave, forecast_horizon_min
--   window                           2026-08-29 17:01:18 -> 23:03:54 UTC
--
-- An agent changed energy and deployment dials inside runs whose entire purpose
-- is to prove that identical inputs produce identical outputs.
--
-- BUT THE WINDOW IS THE POINT, AND IT IS SIX HOURS ON ONE DAY. Every one of the
-- 49 landed on 2026-08-29; none since, across 1,132 later writes. So this is a
-- historical contamination with a closed window, NOT an ongoing one -- and any
-- canon whose lineage predates 2026-08-29 should be read knowing it.
SELECT count(DISTINCT pp.scope_id) AS cert_runs_written_into,
       count(*)                    AS dial_rows,
       string_agg(DISTINCT pp.param_key, ', ' ORDER BY pp.param_key) AS keys,
       min(pp.updated_at) AS first, max(pp.updated_at) AS last
  FROM public.ottoq_policy_params pp
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = pp.scope_id
 WHERE r.run_by = 'cert_harness' AND pp.updated_by ILIKE '%prime%';

-- ---------------------------------------------------------------------------
-- SECTION 3 -- THE GATE IS ON BY DEFAULT, AND NO GLOBAL ROW TURNS IT OFF
--
-- public.ottoq_cron_tick reads:   ottoq_policy_get(..., 'orchestrator_agent_enabled', 1)
--                                                                             ^ default ONE
--
-- and the key's rows are:
--
--   scope   value  updated_by          applies to        rows
--   run       0    0261_ab_quiesce     ab_harness          12
--   run       0    d3_demo             proposer_demo        2
--   run       0    0113_repair         production_live      1
--   run       0    production_start    production_live      1
--   depot     0    0159_experiment     (Benchmark depot)    1
--                                                          --
--                                                          17
--
-- All seventeen are ZERO -- every one is somebody switching the agent OFF for a
-- particular run. There is NO row at global scope, so any run that does not
-- explicitly quiesce the agent resolves to the caller default of 1 and the
-- agent is ON. Note who is missing from that table: cert_harness. Twelve
-- ab_harness runs quiesce the agent; certification runs do not.
--
-- A CORRECTION TO THE REVIEW THAT RAISED THIS. It reported "ottoq_policy_params
-- holds NO row for orchestrator_agent_enabled at any scope." That is false --
-- there are seventeen. Its substantive point survives intact and is the one
-- that matters: no row at GLOBAL scope plus a caller default of 1 means ON
-- unless someone remembered, and for certification runs nobody did. Re-measured
-- rather than repeated, which is the whole reason to re-measure.
SELECT pp.scope_type, pp.param_value, pp.updated_by, r.run_by, count(*) AS rows
  FROM public.ottoq_policy_params pp
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = pp.scope_id
 WHERE pp.param_key = 'orchestrator_agent_enabled'
 GROUP BY 1,2,3,4 ORDER BY 5 DESC;

-- ---------------------------------------------------------------------------
-- WHAT THIS MEANS FOR THE AGENTIC LAYER, WHICH IS THE USEFUL PART
--
-- The picture "we have an agentic layer but nothing has fired" is wrong, and it
-- was wrong in the most useful possible direction. There are two agentic
-- surfaces and they are in opposite states:
--
--   THE DIAL WRITER   live, 1,181 writes, running every two minutes, ON by
--                     default, invisible to every instrument, and with no seat
--                     in the decide path -- it changes the engine's parameters
--                     without ever producing a decision the shield disposes of.
--   THE PROPOSER SEAT built, shield-gated, audited, and until tonight reading a
--                     blind frame (db/checks/0214, 0215).
--
-- So the work is not "switch the agentic layer on." It is to move the dial
-- writer onto the same footing the proposer seat already has: every agentic
-- change becomes a decision at a probe point, evaluated by the L1 shield and
-- logged, rather than an UPDATE nobody can see. That is the fifth probe point
-- (action_context='policy_change'), and this file is the measurement that says
-- why it is worth building: 1,181 changes have gone through the engine with no
-- shield, no decision row, and no rule evaluation.
--
-- NOT DONE HERE, deliberately: pinning orchestrator_agent_enabled to 0 at
-- global scope. It is the obvious one-row hardening and it is a live
-- behaviour change to a writer that has been running for two months -- it
-- belongs in a migration with a stated blast radius, not in a check file, and
-- not at 11pm without a cert window.
