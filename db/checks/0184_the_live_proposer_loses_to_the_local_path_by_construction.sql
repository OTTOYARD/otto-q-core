-- ===========================================================================
-- db/checks/0184  THE LIVE PROPOSER LOSES TO THE LOCAL PATH BY CONSTRUCTION
-- ===========================================================================
-- 2026-09-12 17:13 UTC. Read-only. BUILD_QUEUE #4 / proposer/README.md L-40.
--
-- QUESTION. bridge/proposer_bridge.py can now submit the CP-SAT proposer's rows
-- (source 'forward_lex') through ottoq_submit_external_proposal. If it did so
-- today, against a live twin run, would a single one of them ever be ENACTED?
--
-- ANSWER. No -- and not because of the shield. By the ORDER BY.
--
-- ---------------------------------------------------------------------------
-- 1. THE MECHANISM, FROM THE LIVE BODIES (md5-pinned in migration 0259)
-- ---------------------------------------------------------------------------
--
-- ottoq_sim_decide_and_dispatch (the metronome's decide, prosrc md5 50b59879...)
-- runs, in this order, inside ONE transaction:
--
--   PERFORM ottoq_cuopt_first_refusal_arm(run, tick);     -- may arm a hold
--   PERFORM ottoq_l2_optimize_assignments(run, depot, sim_clock);
--   ... ottoq_decide_tick(run) ...                         -- the cursor
--
-- ottoq_l2_optimize_assignments (md5 7f990f88...) begins with
--
--   DELETE FROM ottoq_external_proposals
--    WHERE sim_run_id = p_sim_run_id AND source = 'greedy_constrained'
--      AND action_context = 'stall_assignment';
--
-- then, for every at-gate vehicle that has NO pending row with
--
--   p.source = 'cuopt'                                     -- FR-3, one name
--
-- INSERTs a fresh greedy_constrained row with created_at = now(). now() is the
-- TRANSACTION timestamp -- this tick's.
--
-- ottoq_decide_tick then asks ottoq_l2_external_proposal (md5 e6b62773...) for
-- the winning pending row per vehicle:
--
--   ORDER BY (p.source = 'cuopt') DESC, (p.source = 'cuopt_fallback') DESC,
--            p.created_at DESC, p.tick_seq DESC NULLS LAST, p.source ASC,
--            p.proposal::text ASC
--   LIMIT 1
--
-- A forward_lex row is submitted by a process OUTSIDE the tick, in its own
-- transaction, BEFORE the tick that will consider it. Its created_at is therefore
-- strictly older than the greedy row the tick manufactures for the same vehicle.
-- Neither is cuopt, so the first two keys tie; the third key is created_at DESC;
-- the greedy row wins. Every tick. For every vehicle.
--
-- The hold does not help: ottoq_cuopt_defer_hold (md5 65fb1de2...) binds only
-- while cuopt_propose_enabled >= 1 -- a demo that switches the NVIDIA proposer
-- off has no hold at all -- and releases only for
--
--   p.source IN ('cuopt', 'cuopt_fallback')
--
-- so a forward_lex answer does not release it either; the vehicle waits out the
-- tick and then greedy takes it at the next one, by the ORDER BY above.
--
-- ---------------------------------------------------------------------------
-- 2. THE SECOND FINDING: A REPLAY OF SUCH A RUN WOULD NOT BE FAITHFUL TO IT
-- ---------------------------------------------------------------------------
--
-- Posture B (0237/0239) certifies an out-of-process proposer by capturing its
-- stream and injecting it into both arms of a pair. ottoq_proposal_replay_inject
-- inserts the captured rows INSIDE the pair's transaction, so their created_at is
-- the pair's now() -- the SAME value as the greedy rows the arm regenerates. The
-- third key ties; the fourth, tick_seq DESC, ties (the capture keeps tick_seq);
-- the fifth is p.source ASC, and 'forward_lex' < 'greedy_constrained'.
--
-- So in a REPLAY the forward_lex row WINS the very tie it LOSES live. The pair
-- would still pass (both arms are wrong the same way), h_prop would be
-- non-trivial, and the certified behaviour would not be the live behaviour.
-- That is the exact failure the replay mechanism exists to prevent, one key
-- deeper than 0238 looked. It is a second, independent reason 0259 must land
-- before any forward_lex capture is replayed: with a declared rank, live and
-- replay resolve on the FIRST key and agree.
--
-- ---------------------------------------------------------------------------
-- 3. WHAT 0259 CHANGES, AND THE PROOF IT CHANGES NOTHING ELSE (measured)
-- ---------------------------------------------------------------------------
--
-- 0259 replaces the two literals with a rank read from ottoq_proposer_precedence
-- (cuopt 0, cuopt_fallback 1, forward_lex 10, unlisted = max), generalizes FR-3,
-- the hold release and the arm predicate to declared flags, and adds a second
-- hold-gate key. Its A2 recomputes the winner of every historical group under
-- both orderings. Run here first, read-only, 2026-09-12 17:13 UTC:
--
--   rows_total       15,123
--   groups_total     14,779      (run, context, entity_type, entity)
--   groups_multi        162      groups with more than one row
--   winners_differ        0      <- the claim
--   mixed-source stall groups, ever:  1   (cuopt vs greedy_constrained)
--
-- and the table has never held a forward_lex row (section 4), so no historical
-- selection could move and none does.
--
WITH seed(source, rank) AS (VALUES ('cuopt', 0), ('cuopt_fallback', 1), ('forward_lex', 10)),
ranked AS (
  SELECT p.proposal_id,
         row_number() OVER (PARTITION BY p.sim_run_id, p.action_context, p.entity_type, p.entity_id
                            ORDER BY (p.source = 'cuopt') DESC, (p.source = 'cuopt_fallback') DESC, p.created_at DESC,
                                     p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC, p.proposal_id) AS rn_old,
         row_number() OVER (PARTITION BY p.sim_run_id, p.action_context, p.entity_type, p.entity_id
                            ORDER BY COALESCE((SELECT s.rank FROM seed s WHERE s.source = p.source), 2147483647) ASC, p.created_at DESC,
                                     p.tick_seq DESC NULLS LAST, p.source ASC, p.proposal::text ASC, p.proposal_id) AS rn_new,
         count(*) OVER (PARTITION BY p.sim_run_id, p.action_context, p.entity_type, p.entity_id) AS n_in_group
    FROM public.ottoq_external_proposals p)
SELECT (SELECT count(*) FROM public.ottoq_external_proposals)                    AS rows_total,
       (SELECT count(*) FROM ranked WHERE rn_old = 1)                            AS groups_total,
       (SELECT count(*) FROM ranked WHERE rn_old = 1 AND n_in_group > 1)         AS groups_multi,
       (SELECT count(*) FROM (SELECT a.proposal_id FROM ranked a WHERE a.rn_old = 1
                              EXCEPT SELECT b.proposal_id FROM ranked b WHERE b.rn_new = 1) d) AS winners_differ;

-- ---------------------------------------------------------------------------
-- 4. WHO HAS EVER PROPOSED WHAT (the "0 forward_lex rows" line, measured)
-- ---------------------------------------------------------------------------
--
--   source                  action_context      status      n
--   agent_probe             service_sequencing  enacted     40      (0239 replay probe)
--   agent_probe             service_sequencing  pending    150
--   agent_probe             service_sequencing  superseded  50
--   cuopt                   stall_assignment    enacted     27
--   cuopt                   stall_assignment    expired     62
--   cuopt                   stall_assignment    superseded  47
--   greedy_constrained      stall_assignment    enacted   4134
--   greedy_constrained      stall_assignment    expired    659
--   greedy_constrained      stall_assignment    pending   1892
--   greedy_constrained      stall_assignment    superseded 5847
--   ottoq_service_priority  service_sequencing  expired    223
--   ottoq_service_priority  service_sequencing  pending    573
--   ottoq_service_priority  service_sequencing  superseded 1419
--   forward_lex             --                  --           0
--
SELECT source, action_context, status, count(*) AS n
  FROM public.ottoq_external_proposals
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

-- ---------------------------------------------------------------------------
-- 5. VERDICT
-- ---------------------------------------------------------------------------
--
-- The bridge is necessary and not sufficient. Without 0259 the CP-SAT proposer
-- is a proposer that is heard and never followed -- which is worse than one that
-- is not wired, because the ledger would say "invoked N, enacted 0" and invite
-- the wrong conclusion (that the solver is bad) for the right observation (that
-- the ORDER BY never let it through). 0259 first; then a live run with
-- proposer_hold_enabled=1 and cuopt_propose_enabled=0; then the capture and the
-- replay pair. In that order, and each with its run id.
-- ===========================================================================
