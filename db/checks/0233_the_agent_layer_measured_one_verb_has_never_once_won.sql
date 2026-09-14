-- db/checks/0233
-- THE AGENT LAYER, MEASURED: 15,905 PROPOSALS, 4,299 ENACTED, AND ONE VERB
-- THAT HAS NEVER ONCE WON
--
-- Chase's standing instruction is the reason this exists: "just because
-- something hasn't fired doesn't mean we don't need it. It could just be wired
-- incorrectly." So this file does not ask whether a seat is busy. It asks
-- whether a seat CAN win, and separates the two.
--
-- Measured 2026-09-14 over public.ottoq_external_proposals.
--
-- ===========================================================================
-- A. PROPOSE / DISPOSE IS REAL, AND HERE IS THE NUMBER
--
--   source                  proposals  enacted   rate   last seen
--   ----------------------  ---------  -------  -----   ----------
--   greedy_constrained         12,654    4,191  33.1%   2026-09-14 09:23
--   forward_lex (CP-SAT)          447       41   9.2%   2026-09-14 09:23
--   agent_probe                   240       40  16.7%   2026-09-09 09:55
--   cuopt                         136       27  19.9%   2026-08-30 04:36
--   ottoq_service_priority      2,380        0   0.0%   2026-09-14 00:57
--   llm_advisor                    48        0   0.0%   2026-09-14 01:28
--   ----------------------  ---------  -------
--   TOTAL                      15,905    4,299  27.0%
--
-- THE SENTENCE THIS SUPPORTS: "Six proposer seats have produced 15,905
-- proposals; the kernel enacted 4,299 of them, 27%. Agents propose and the
-- solver disposes is a measured ratio here, not a slogan."
--
-- Note forward_lex ABSTAINS 185 times in 447 (41%). A proposer that declines
-- rather than guesses is behaving correctly and the ledger records it.
--
-- ===========================================================================
-- B. THE FINDING: ONE VERB HAS NEVER BEEN ENACTED, EVER
--
--   verb            total   enacted   sources
--   --------------  ------  -------   -----------------------------------
--   assign_stall    13,149    4,232   forward_lex, greedy_constrained, llm_advisor
--   admit_service    2,380        0   ottoq_service_priority
--   triage             236       38   agent_probe
--   (null)             136       27   cuopt
--   promote_ready        4        2   agent_probe
--
-- EVERY verb in this engine enacts except one. `admit_service` is 0 for 2,380,
-- across 1,017 distinct runs, over sixteen days. It is the entire output of
-- ottoq_service_priority, which is why that seat reads 0.0% -- the seat is not
-- weak, its verb has never once been accepted.
--
-- ===========================================================================
-- C. WHAT IS NOT ESTABLISHED, AND WHY THAT MATTERS HERE
--
-- I formed THREE hypotheses about the cause and measurement killed the first
-- two. Recording all three, because the discipline is the point:
--
--   H1  "admit_service proposals carry no stall_id, so they cannot be turned
--        into a booking."  FALSE. They do lack stall_id (0 of 2,380 carry one)
--        -- but agent_probe's `triage` verb ALSO carries none and enacted 40
--        times. A stall-less proposal can be enacted, so that is not the bar.
--
--   H2  "the disposer has no branch for the verb."  FALSE.
--        public.ottoq_decide_tick contains the string `admit_service`. The
--        disposer is not blind to it.
--
--   H3  "it is heard and refused on a real constraint."  NOT ESTABLISHED.
--        Plausible, and it is what the six-dimension audit claimed ("heard and
--        refused on physical capacity"), but I have not read the branch and
--        will not assert a cause I have not measured. Two of my three guesses
--        today were already wrong.
--
-- SO THE CLAIM IS THE SHAPE, NOT THE CAUSE: one verb, zero enactments, ever,
-- while every other verb enacts. That is enough to act on and not enough to
-- explain.
--
-- ===========================================================================
-- D. WHY THE SHAPE ALONE IS ACTIONABLE
--
-- A seat that proposes 2,380 times and is refused 2,380 times is EITHER a
-- correctly-restrained proposer whose moment never arrived, OR a wiring defect
-- that has been silently absorbing a sixth of the engine's proposal volume for
-- sixteen days. Both look identical from outside, and NOTHING IN THE ENGINE
-- DISTINGUISHES THEM -- there is no refusal reason recorded anywhere. The
-- proposal goes to 'superseded' (1,539) or 'expired' (841) and the ledger never
-- says why.
--
-- That is the same defect class as G65, one layer out: the setter refused with
-- a reason and the caller did not read it. Here the disposer refuses and
-- records NO reason at all, so no caller could read it even if it wanted to.
--
-- THE NEXT STEP, in order:
--   1. Read ottoq_decide_tick's admit_service branch and establish H3 or
--      replace it. That is a ~83k-char function; find the branch, not the file.
--   2. Whatever the cause, the ledger should record a REFUSAL REASON on a
--      proposal that is superseded or expired. "Agents propose, solver
--      disposes" is only auditable if the disposal says why. Today 11,606 of
--      15,905 proposals ended without one.
--   3. Only then decide whether ottoq_service_priority is restrained or broken.
--
-- ===========================================================================
-- E. RE-MEASURE

-- the reach table
SELECT source,
       count(*)                                   AS proposals,
       count(*) FILTER (WHERE status='enacted')   AS enacted,
       round(100.0*count(*) FILTER (WHERE status='enacted')/count(*), 1) AS pct,
       count(*) FILTER (WHERE (proposal->>'abstain')::boolean IS TRUE)   AS abstained,
       count(DISTINCT sim_run_id)                 AS runs,
       max(created_at)                            AS last_seen
  FROM public.ottoq_external_proposals
 GROUP BY source ORDER BY enacted DESC, proposals DESC;

-- the verb census -- any verb with enacted = 0 and a large total is this finding
SELECT proposal->>'verb' AS verb,
       count(*) AS total,
       count(*) FILTER (WHERE status='enacted') AS enacted,
       count(DISTINCT sim_run_id) AS runs,
       string_agg(DISTINCT source, ', ') AS sources
  FROM public.ottoq_external_proposals
 GROUP BY 1 ORDER BY total DESC;

-- how many proposals ended WITHOUT any recorded reason (section D step 2)
SELECT count(*) FILTER (WHERE status IN ('superseded','expired')) AS ended_unexplained,
       count(*)                                                    AS all_proposals,
       round(100.0*count(*) FILTER (WHERE status IN ('superseded','expired'))/count(*),1) AS pct
  FROM public.ottoq_external_proposals;

-- and the two hypotheses measurement already killed, so they are not re-formed:
--   H1 dies if any stall-less proposal has ever been enacted
SELECT 'stall-less proposals that WERE enacted (kills H1)' AS check, count(*) AS n
  FROM public.ottoq_external_proposals
 WHERE status='enacted' AND NOT (proposal ? 'stall_id');
--   H2 dies if the disposer names the verb at all
SELECT 'ottoq_decide_tick mentions admit_service (kills H2)' AS check,
       (position('admit_service' in p.prosrc) > 0) AS mentions
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_decide_tick';

-- ===========================================================================
-- F. ADDENDUM, same day: H3 IS REPLACED. THE CAUSE IS AN ATTRIBUTION JOIN,
--    NOT A REFUSAL.
--
-- Section C said the cause was not established and named H3 ("heard and
-- refused on a real constraint") as plausible-but-unverified. It is now
-- replaced by something measured.
--
-- THE WRITE-BACK, ottoq_decide_tick lines 1056-1061:
--
--   UPDATE ottoq_external_proposals p SET status='enacted'
--    WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
--      AND EXISTS (SELECT 1 FROM ottoq_decisions d
--                   WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
--                     AND d.entity_id=p.entity_id AND d.outcome_status='enacted'
--                     AND d.enacted_action->>'source' = p.source);
--
-- A proposal is credited only if the enacted decision's action carries a
-- `source` EQUAL to the proposal's source.
--
-- MEASURED, joining proposals to decisions on (run, entity, tick) for
-- source='ottoq_service_priority':
--
--   enacted_action->>'source'   outcome_status        rows
--   -------------------------   -------------------   ----
--   NULL                        enacted                403
--   'inspect_seam'              noop_no_candidate      382
--   'needs_card'                noop_no_candidate      307
--   'ottoq_service_priority'    noop_no_candidate       43
--   'needs_card'                enacted                  3
--   NULL                        noop_no_candidate        3
--
-- 403 decisions at those exact ticks were ENACTED with a NULL source.
-- `NULL = 'ottoq_service_priority'` is NULL, never true, so the write-back
-- cannot match them -- and line 1063 then marks the proposal 'superseded',
-- because the entity WAS decided this tick just not (provably) by it.
--
-- WHY THE SOURCE IS NULL, and this is the actual defect:
--   ottoq_decide_tick line 964:
--     v_proposal := COALESCE(
--       ottoq_l2_external_proposal(p_sim_run_id,'service_sequencing','vehicle',v),
--       ottoq_l2_propose_service(v, v_depot, v_ctx));
--   ottoq_l2_external_proposal NORMALISES source into the jsonb it returns
--   (its lines 2-5: add `source` when the payload lacks one).
--   ottoq_l2_propose_service -- the HEURISTIC FALLBACK -- does not. Its output
--   carries `l2_engine` and no `source` at all.
--   So every tick the fallback wins, the enacted_action has no source, and the
--   attribution join is unsatisfiable BY CONSTRUCTION.
--
-- WHAT IS THEREFORE ESTABLISHED:
--   * the attribution join cannot credit a null-source enactment (arithmetic);
--   * 403 such enactments exist on the exact ticks in question (measured);
--   * the fallback is not source-normalised while the external path is (read).
--
-- WHAT IS STILL NOT ESTABLISHED -- and it decides the remedy:
--   whether ottoq_service_priority's proposal is (a) FOUND by the lookup and
--   genuinely beaten by the fallback, or (b) NEVER FOUND -- e.g. written after
--   the lookup runs within the same tick, so the COALESCE always falls through.
--   (a) means the ledger under-reports a real contest. (b) means the seat has
--   never actually competed. The 43 rows where the decision DOES carry
--   source='ottoq_service_priority' are all `noop_no_candidate`, which is
--   suggestive of (b) and is not proof.
--
--   NEXT: establish the intra-tick ORDER of ottoq_service_priority_propose
--   versus the line-964 lookup. Until then do not describe this seat as
--   "refused" or as "broken" -- both are unearned.
--
-- AND NOTE THE SHAPE, because it is today's fourth instance: the number
-- "0 of 2,380" is arithmetically correct and answers a different question than
-- the one anyone asks of it. It looks like a verdict on the proposer. It is in
-- large part a verdict on an attribution join that cannot express the credit
-- it is asked to assign.

-- re-measure the attribution join
SELECT p.source AS proposal_source,
       d.enacted_action->>'source' AS decision_source,
       d.outcome_status,
       count(*) AS rows
  FROM public.ottoq_external_proposals p
  JOIN public.ottoq_decisions d
    ON d.sim_run_id = p.sim_run_id AND d.entity_id = p.entity_id
   AND d.tick_seq = p.tick_seq
 WHERE p.source = 'ottoq_service_priority'
 GROUP BY 1,2,3 ORDER BY rows DESC;

-- the general question the above is one instance of: how often does an
-- ENACTED decision carry no source at all? Every one of those is an
-- enactment no proposal can ever be credited for.
--
-- MEASURED 2026-09-14, and this is the number that generalises the whole file:
--
--   enacted decisions with NO source   1,556,209   87.1%
--   enacted decisions WITH a source      231,157   12.9%
--   ------------------------------------------------------
--   total enacted decisions            1,787,366
--
-- THE ATTRIBUTION JOIN CAN ONLY EVER CREDIT 12.9% OF WHAT THE ENGINE DOES.
-- 87.1% of enactments are unattributable by construction -- not because no
-- proposer was involved, but because the action record does not say who. So
-- "proposals enacted" (0233 section A: 4,299 of 15,905, 27%) is a floor on
-- proposer influence and NOT a measure of it, and no per-seat enactment rate in
-- this file should be read as a performance comparison between seats. It is a
-- comparison of which seats happen to travel through a source-preserving path.
SELECT (enacted_action->>'source' IS NULL) AS source_missing,
       outcome_status,
       count(*) AS decisions
  FROM public.ottoq_decisions
 WHERE outcome_status = 'enacted'
 GROUP BY 1,2 ORDER BY decisions DESC;

-- ===========================================================================
-- G. ADDENDUM 2: THE (a)/(b) QUESTION IS SETTLED. THE SEAT DOES COMPETE.
--
-- Addendum F left one thing open and said it decided the remedy: is the
-- ottoq_service_priority proposal (a) FOUND by the lookup and genuinely
-- beaten, or (b) NEVER FOUND because it is written after the lookup runs?
--
-- (b) IS FALSE. public.ottoq_sim_decide_and_dispatch calls, in this order:
--
--   line 87   PERFORM ottoq_l2_optimize_assignments(...)
--   line 88   PERFORM ottoq_service_priority_propose(p_sim_run_id)   <- WRITES
--   line 90   PERFORM public.ottoq_l2_propose_seat(...)
--   line 98   ottoq_decide_tick(p_sim_run_id)                        <- READS
--
-- The proposer runs TEN LINES BEFORE the consumer, in the same function and
-- the same transaction. The proposals are present, pending and fresh when
-- ottoq_decide_tick's line-964 lookup runs. The wiring order is correct.
--
-- AND THE DIRECT EVIDENCE: 43 decisions carry
-- enacted_action->>'source' = 'ottoq_service_priority'. A source only reaches
-- enacted_action by travelling through ottoq_l2_external_proposal's
-- normalisation, so the proposal WAS found and consumed at least 43 times.
--
-- SO THE SEAT COMPETES. It is not unwired and it is not ignored. What remains
-- is narrower and is NOT claimed here: those 43 consumed proposals produced
-- decisions with outcome_status 'noop_no_candidate' rather than 'enacted', and
-- why a consumed proposal yields a no-op is a separate question in a different
-- branch. It does not change the attribution finding, which stands on its own
-- and is much larger: 87.1% of ALL enacted decisions carry no source at all.
--
-- WHAT MAY NOW BE SAID ABOUT ottoq_service_priority, and nothing more:
--   "Its proposals are written before the consumer reads them, and are
--    demonstrably consumed. Its enactment count of zero is not evidence that
--    it is unwired; the ledger cannot credit 87.1% of enactments to anyone."
--
-- WHAT MAY NOT BE SAID: that it is working correctly, or that it is broken.
-- Neither is earned. The measurement that would earn it is a refusal reason
-- (section D step 2) -- until a disposal says why, a restrained proposer and a
-- broken one are the same row.

-- re-measure the call order that settles (b)
SELECT l.lineno, trim(l.line) AS line
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
       LATERAL unnest(string_to_array(p.prosrc, E'\n')) WITH ORDINALITY AS l(line, lineno)
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_decide_and_dispatch'
   AND l.line ~ 'ottoq_service_priority_propose|ottoq_decide_tick\('
 ORDER BY l.lineno;

-- and the 43 that prove consumption
SELECT d.enacted_action->>'source' AS decision_source, d.outcome_status, count(*) AS n
  FROM public.ottoq_decisions d
 WHERE d.enacted_action->>'source' = 'ottoq_service_priority'
 GROUP BY 1,2 ORDER BY n DESC;
