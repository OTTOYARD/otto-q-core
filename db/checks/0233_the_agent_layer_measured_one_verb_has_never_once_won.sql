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
