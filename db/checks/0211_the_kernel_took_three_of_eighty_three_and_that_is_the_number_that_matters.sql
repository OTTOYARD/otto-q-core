-- =====================================================================
-- 0211  THE KERNEL TOOK THREE OF EIGHTY-THREE, AND THAT IS THE NUMBER
--       THAT MATTERS
-- =====================================================================
-- Read-only. Measured 2026-09-14 00:34-00:41 UTC (7:34-7:41 PM CT,
-- 2026-09-13) against run 33f87a41-3f0e-41c6-8da8-608376d56d6a
-- (busy_day, seed 424242, Nashville flagship, run_by='proposer_live').
--
-- ---------------------------------------------------------------------
-- THE HEADLINE, AND THEN THE NUMBER UNDER IT
--
-- CP-SAT proposals reached the live engine through
-- public.ottoq_submit_external_proposal and the deterministic kernel
-- ENACTED them. Three decision rows, l2_engine='forward_lex',
-- outcome_status='enacted', at ticks 2, 8 and 18. In each one
-- enacted_action equals proposed_action exactly -- the kernel took the
-- stall the solver named, not a stall of its own.
--
-- That is the propose/dispose claim in CLAUDE.md rule 6 stopping being
-- an assertion. Before today the ledger carried 90 CP-SAT proposals and
-- zero enactments, and ASSET_LOOP_MAP §4 called CP-SAT "the best-built
-- and least consequential".
--
-- The take rate is 3 of 83. That is the number worth understanding, and
-- most of it is not a rejection. The exact grouping, re-measured at
-- 00:44 UTC with the run still going (83 proposals, and note that
-- ABSTAIN -- CP-SAT declining to name a stall -- is a third of them):
--
--   23  real proposal, superseded; deterministic_v1 then returned
--       noop_no_candidate for the same vehicle after CP-SAT had named a
--       specific stall. THIS IS THE ONLY GROUP THAT LOOKS WRONG.
--   17  real proposal, superseded; deterministic_v1 then enacted a
--       DIFFERENT stall for the same vehicle. The local path won, which
--       is what the one-tick right-of-first-refusal is FOR.
--   12  ABSTAIN, then noop_no_candidate.
--   11  ABSTAIN, then deterministic_v1 enacted.
--    5  real proposal, superseded, no later decision for that vehicle.
--    5  real proposal, still pending; vehicle not yet at a decision point.
--    4  ABSTAIN, no later decision.
--    3  ENACTED.
--    2  ABSTAIN, still pending.
--    1  real proposal superseded, but the same vehicle's next decision
--       was forward_lex enacted -- a later CP-SAT proposal for the same
--       vehicle won.
--
-- So: 29 of 83 (35%) are CP-SAT refusing to answer, not the kernel
-- refusing CP-SAT. That matches the 30% self-refusal rate db/checks/0210
-- measured independently and flagged, and it means the honest
-- denominator for "did the kernel take it" is 54 real proposals, of
-- which 4 were eventually enacted under a forward_lex decision row.
--
-- Writing this up the first time, the draft collapsed the two enacted
-- rows (17 real + 11 abstain) into one "28 the local path won" line.
-- It is recorded because the difference is the whole finding: a
-- proposal the kernel considered and beat is propose/dispose working,
-- and a proposal the proposer never made is a proposer problem wearing
-- the same status value.
--
-- ---------------------------------------------------------------------
-- THE ONE THAT IS A LEAD, STATED AS A LEAD
--
-- The 23 are the interesting rows: the disposer said "no candidate"
-- about a vehicle for which a proposer had just named a specific stall.
-- Three explanations fit and this file does not choose between them:
--
--   (a) the stall was genuinely taken between submit and tick -- the
--       selector's own predicate requires the stall free, unreserved,
--       charger Available and heartbeat fresh within 90 sim-seconds;
--   (b) the vehicle was in an admission path with no proposer seat --
--       ASSET_LOOP_MAP §3 measured that §(3b) gate intake enacts a
--       physical staging assignment with no proposer and no shield
--       probe at all;
--   (c) something else.
--
-- What is NOT established here is that any stall was free at the moment
-- the kernel refused. That state is gone; reconstructing it needs the
-- snapshot, not the proposal. The live probe that CAN be run was: at
-- 00:41 UTC, of the 7 then-pending proposals, 4 passed every clause of
-- the selector's stall predicate and were simply waiting for their
-- vehicle. So the predicate is not rejecting everything -- which makes
-- (a) less likely than it looked and (b) worth measuring next.
--
-- Tracked as G49. The measurement it needs is a decision-snapshot
-- comparison, not another proposal count.
--
-- ---------------------------------------------------------------------
-- WHAT WAS RULED OUT, AND WHY THAT MATTERS
--
-- The obvious hypothesis was that the bridge's 60-second TTL
-- (bridge/proposer_bridge.py DEFAULT_TTL_S = 60) expires proposals
-- before the 2-minute ottoq-depot-tick can consider them. THAT IS
-- WRONG, and the selector says so in its own body:
--
--   AND GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
--                p.created_at + interval '35 minutes') >= now()
--
-- The GREATEST floors every proposal's life at 35 minutes regardless of
-- what the submitter asked for, so the 60-second TTL is decorative and
-- expiry is not the binding constraint. Recorded because it is a clean
-- example of a plausible, arithmetically-tidy root cause that reading
-- the function refuted in one line.
--
-- ---------------------------------------------------------------------
-- THE SHIELD DID ITS JOB ON EVERY ONE
--
-- All three enacted forward_lex decisions carry a non-empty
-- rule_results array and shield_latency_ms > 0. The first reads:
--
--   EN.001.grid_capacity_ceiling   passed  "grid capacity OK: 0.0 +
--                                           200.0 = 200.0 kW
--                                           (headroom 1420.0 kW)"
--   EN.005.grid_event_hardstop     passed  "grid healthy"
--   HW.001.connector_compatibility passed  "multi-standard stall
--                                           supports CCS1"
--   HW.002.charger_state_precondition passed "charger NASH-DCFC-06
--                                           available and online"
--   HW.004.stall_single_vehicle    passed  "stall available"
--
-- So the nondeterministic external solver was consumed behind the
-- inviolable deterministic shield, which is the posture CLAUDE.md 2.5
-- argues is the only safe way to consume a solver that cannot promise
-- reproducibility. It is now a measured posture rather than a designed
-- one.
--
-- One honest caveat: the gate and shield_verdict COLUMNS are NULL on
-- these rows -- and on all 248 deterministic_v1 stall_assignment rows in
-- the same run, and on all 50 reservation_honoured rows. Those two
-- columns are unused on this path for every engine, not for CP-SAT
-- specifically. rule_results is where the evidence lives.
--
-- ---------------------------------------------------------------------
-- AND NEMOTRON CAME BACK IN THE SAME RUN
--
-- 4 nemotron decisions at task_start, all enacted, inside this run;
-- the census moved 262 -> 280 over the session. db/checks/0209
-- predicted this: 0105 quiesces the LLM proposer on cert_harness runs,
-- and 1,057 of the last 1,090 retained runs were cert_harness, so
-- Nemotron had no permitted caller rather than a fault. Starting one
-- non-cert run woke it with nothing else changed.
-- =====================================================================

-- §1  The three enactments, with the full chain.
SELECT d.tick_seq, d.sim_clock, d.entity_id,
       d.l2_engine, d.outcome_status,
       d.proposed_action = d.enacted_action        AS took_exactly_what_was_proposed,
       jsonb_array_length(d.rule_results)          AS rules_evaluated,
       d.shield_latency_ms, d.enact_latency_ms,
       d.proposed_action->>'stall_type'            AS stall_type,
       d.proposed_action->'rationale'->>'tardy_min' AS tardy_min,
       d.proposed_action->'rationale'->>'planned_kwh' AS planned_kwh
  FROM public.ottoq_decisions d
 WHERE d.sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
   AND d.l2_engine = 'forward_lex'
 ORDER BY d.decision_seq;

-- §2  The take-rate breakdown. Every forward_lex proposal, paired with
--     the NEXT stall_assignment decision for the same vehicle.
WITH p AS (
  SELECT proposal_id, entity_id, created_at, status,
         proposal->>'stall_id' AS want_stall,
         COALESCE((proposal->>'abstain')::boolean, false) AS abstain
    FROM public.ottoq_external_proposals
   WHERE sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
     AND source = 'forward_lex'
), nxt AS (
  SELECT p.*, d.l2_engine, d.outcome_status,
         row_number() OVER (PARTITION BY p.proposal_id ORDER BY d.created_at) AS rn
    FROM p
    LEFT JOIN public.ottoq_decisions d
      ON d.sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
     AND d.action_context = 'stall_assignment'
     AND d.entity_id = p.entity_id
     AND d.created_at >= p.created_at
)
SELECT status                                          AS proposal_status,
       abstain,
       COALESCE(l2_engine, '(no later decision)')      AS next_decider,
       COALESCE(outcome_status, '-')                   AS next_outcome,
       count(*)                                        AS n
  FROM nxt
 WHERE rn = 1 OR rn IS NULL
 GROUP BY 1,2,3,4
 ORDER BY n DESC;

-- §3  THE LIVE PROBE. For proposals still pending, run the selector's
--     own stall predicate clause by clause and see which one bites.
--     Re-runnable; it reports on whatever is pending when you run it.
WITH p AS (
  SELECT proposal_id, entity_id, status,
         (proposal->>'stall_id')::uuid AS want_stall,
         COALESCE((proposal->>'abstain')::boolean, false) AS abstain
    FROM public.ottoq_external_proposals
   WHERE sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
     AND source = 'forward_lex' AND status = 'pending'
), clk AS (
  SELECT sim_clock_current FROM public.ottoq_sim_runs
   WHERE sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
)
SELECT p.abstain,
       (s.id IS NULL)                                   AS stall_missing,
       (s.current_vehicle_id IS NOT NULL)               AS stall_occupied,
       NOT (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
            OR s.reservation_expires_at <= clk.sim_clock_current)
                                                        AS blocked_by_reservation,
       (c.station_state IS DISTINCT FROM 'Available')    AS charger_not_available,
       (c.last_heartbeat_at < clk.sim_clock_current - interval '90 seconds')
                                                        AS heartbeat_stale,
       count(*)                                          AS n
  FROM p CROSS JOIN clk
  LEFT JOIN public.stalls s ON s.id = p.want_stall
  LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
 GROUP BY 1,2,3,4,5,6
 ORDER BY n DESC;
-- MEASURED 00:41 UTC: 4 rows with every flag false (admissible, waiting
-- for the vehicle), 2 abstains, 1 blocked by charger_not_available +
-- heartbeat_stale. The predicate is not rejecting everything.

-- §4  The refutation of the TTL hypothesis, from the selector's own body.
SELECT substring(
         regexp_replace(p.prosrc, '\s+', ' ', 'g')
         from 'AND GREATEST[^)]*\)[^)]*\)[^>]*>= now\(\)') AS ttl_clause_as_written
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_external_proposal';
-- The GREATEST floors proposal life at 35 minutes whatever the submitter
-- asked for. bridge/proposer_bridge.py asks for 60 seconds and gets 35
-- minutes. Expiry is not why proposals are not taken.

-- §5  The scoreboard after 0276, which is what a human should read.
SELECT source, kind, state, decisions, enacted, hours_silent, gate_enabled
  FROM public.ottoq_intelligence_status()
 ORDER BY (state <> 'UNREGISTERED'), enacted DESC, source;
-- MEASURED after 0276: cpsat FOLLOWED 3/3, 0.0 h silent; cuopt FOLLOWED
-- 27/27 but 356 h silent behind a dial; ottoq_service_priority INVOKED
-- 458/0 -- running and ignored; anthropic DECLARED, seat never sat in.
-- Zero UNREGISTERED.
