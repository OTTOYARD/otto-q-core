-- 0256  THE RANKED CANDIDATE SET HAS A PRODUCER. 0358/0359 SHIPPED INERT;
--       ottoq-cuopt-propose v27 IS WHAT FILLS THE ARRAY.
--
-- Closes the producer half of G71's answer. 0255 established the finding:
-- 29 of 39 refusals (74%) named a stall that was ALREADY HELD when the proposal
-- was created -- proposer staleness, not depot contention. 0358 built the
-- consumer (`ottoq_promote_proposal_candidates`, wired at the top of
-- `ottoq_dispose_external_proposals`) and 0359 corrected it to carry per-candidate
-- kilowatts. Neither could do anything: **no proposer emitted `candidates`**, so
-- the rescue path was unreachable code for two migrations.
--
-- ══ 1. THE BASELINE, AND WHY IT IS A COMMENT RATHER THAN A QUERY ════════════
--
-- `ottoq_external_proposals` is registered `class='engine'` in
-- `ottoq_run_scope_registry`, so `ottoq_start_demo_run` -> `ottoq_purge_prior_runs`
-- deletes it. Starting the v27 run destroyed the v25 evidence -- measured, not
-- feared: that purge reported **940,266 rows**, `cuopt_invocation_log` among them.
-- So the before-picture was captured BEFORE the run was started and is recorded
-- here, in git, which is the only durable place it can live. This is the 0231 /
-- G72 pattern again and the reason 0340 exists.
--
-- Baseline run `92a6ac36-039f-4c34-9ad2-f0d35471047f` -- busy_day, twin depot
-- (rule 8), seed 1908402609758799079, 1,124 ticks, ended 2026-09-20 01:08 UTC,
-- `failure_reason = 'run_governor: reached the 540 sim-minute ceiling'`.
-- Source `cuopt`, every proposal it wrote:
--
--   proposals                                    74
--   distinct vehicles                            37
--   enacted            (enacted_by_kernel)        4
--   refused                                       7   <- what candidates address
--     stall_reserved                              5
--     stall_occupied                              2
--   superseded                                   60
--     entity_decided_by_other_proposal           45
--     newer_proposal_same_entity                 16   (61 incl. 1 non-cuopt row)
--   expired            (run_finalized)            3   (4 incl. 1 greedy row)
--   proposals carrying `candidates`               0   <- v25 had no producer
--
--   proposals per vehicle:  1->21  2->5  3->5  4->3  5->2  6->1
--   (arithmetic guard, per 0253 Q4b: 21+5+5+3+2+1 = 37 vehicles and
--    21+10+15+12+10+6 = 74 proposals. Both tie to the census above.)
--
-- ══ 2. A SUSPICION RAISED AND DROPPED, RECORDED BECAUSE IT WAS WRONG ════════
--
-- 74 proposals over 37 vehicles is a mean of **exactly 2.00**, which reads like a
-- structural double-submit -- the gate cohort and the Zone A / en-route cohort
-- both proposing for one vehicle, or the function firing twice a tick. It is not.
-- The distribution above is 21 vehicles at one proposal and a tail out to six, so
-- the 2.00 is a coincidence of shape. What it actually shows is ordinary rolling
-- re-solve: a vehicle whose proposal is not enacted is proposed again next tick,
-- and `newer_proposal_same_entity` is the bookkeeping for that. **No defect.**
--
-- ══ 3. WHAT THIS DOES NOT CLAIM, WHICH IS THE LARGER HALF ═══════════════════
--
-- On the baseline run the candidate set addresses **7 of 74** proposals. The
-- dominant non-enactment is supersession (60), and supersession is NOT a refusal
-- and NOT a capacity wall -- it is the same vehicle proposed again before the
-- earlier row was disposed. A ranked candidate set cannot help there and is not
-- claimed to.
--
-- Nor does low enactment mean 33 vehicles went unserved: the local decide path can
-- and does book a vehicle directly, which disposes the proposal without enacting
-- it. **Enactment rate is a measure of who got there first, not of whether the
-- asset was served.** Anyone quoting "4 of 74" as cuOpt's hit rate is quoting a
-- number about proposal bookkeeping and calling it a number about the depot.
--
-- And the structural ceiling, which matters more than any of this: a candidate can
-- only rescue a proposal when a DIFFERENT free same-type stall still exists at
-- dispose time. 0250 measured l2 and dcfc at 87% and 80% occupancy on the twin
-- depot, so at the moment the rescue is most needed the alternatives are scarcest.
-- The ranked set is a fix for staleness, not for contention. Those are different
-- problems and 0255 is what separated them.
--
-- ══ 4. THE PRODUCER, AND THE TWO THINGS THAT MADE IT NON-TRIVIAL ═══════════
--
-- `edge-functions/ottoq-cuopt-propose/index.ts` v27, deployed to
-- gxdrcyphqjzjsuhxuqtg 2026-09-20 ~01:18 UTC. Verified byte-identical to the repo
-- afterwards by `scripts/check-edge-drift.sh` (29 matched, 1 acknowledged
-- exception) -- so the source that was typechecked is the source that is running.
-- G67 is why that check is not optional.
--
--   (a) SAME SERVICE ONLY. A candidate always matches the primary's `stall_type`.
--       Promoting a dcfc vehicle onto an l2 stall would change what the vehicle
--       came for, and choosing a service is a scheduling decision -- CLAUDE.md 2.5:
--       proposers propose, the decide path disposes. A proposer must not make it.
--
--   (b) DETERMINISTIC BY CONSTRUCTION. `freeStalls` comes from a `.limit(120)`
--       query with **no ORDER BY**, so Postgres does not guarantee its row order.
--       The emitted array is therefore sorted on a TOTAL order --
--       (effective kW desc, stall_id asc). This is load-bearing, not tidiness:
--       `ottoq_hash_proposals` digests `p.proposal::text`, so an array that
--       reordered on replay would break the proposals atom of the fourteen-atom
--       verdict. Q2 observes the tie-break holding on live rows.
--
--   A proposal with no alternative omits the key rather than emitting `[]`, so its
--   payload is byte-identical to its v25 form and its hash does not move.
--
-- Two pre-flight checks worth recording because each caught something:
--   * `deno check` rejected the first draft -- TS7006 implicit `any` on the sort
--     parameters, because `pool` is `any[]` so the mapped array lost its type.
--     Supabase's bundler would have accepted it; the type error was real.
--   * the consumer's parse was verified against the exact payload v27 emits before
--     deploying. 0359 gates candidate kW on `~ '^[0-9]+(\.[0-9]+)?$'`, and JSON
--     numbers reach it via `->>` as `150`, `63.8` and `0`. All three parse. A
--     producer and a consumer that disagree on number formatting would have failed
--     silently into the bare-uuid path.
--
-- ══ 5. STATUS OF THE EFFECT MEASUREMENT ════════════════════════════════════
--
-- The CRN-paired run is `f14d5620-0dd9-4b39-9358-842cddecee8f` -- **same scenario
-- and same seed** as the baseline (busy_day / 1908402609758799079), so the world is
-- identical and v27 is the only variable. That pairing is the point: per C5, the
-- shield and the seed sit on the hold-constant side.
--
-- What is asserted here is the CONTRACT: the array is emitted, well-formed,
-- same-type, capped, and deterministically ordered. What is NOT yet measured is the
-- OUTCOME -- refusals avoided -- because the baseline took 1,124 ticks to produce
-- 7 refusals, so a comparable sample needs the paired run to reach comparable
-- depth. Promotion is observable when it happens: `ottoq_promote_proposal_candidates`
-- stamps `promoted_from`, `promoted_at_tick` and `promotion_count` into the
-- proposal. Q4 is that measurement and reads 0 until a primary actually goes
-- infeasible with a live alternative. **0 there is not a pass and not a failure.**
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  The producer exists at all: proposals carrying a ranked set, on the paired
--     run. Before v27 this was 0 for the life of the engine.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
)
SELECT count(*)                                                       AS proposals,
       count(*) FILTER (WHERE p.proposal ? 'candidates')              AS with_candidates,
       count(*) FILTER (WHERE p.source = 'cuopt'
                          AND p.proposal ? 'candidates')              AS cuopt_with_candidates,
       count(*) FILTER (WHERE p.proposal ? 'candidates') > 0          AS producer_is_live
  FROM public.ottoq_external_proposals p, r
 WHERE p.sim_run_id = r.sim_run_id;

-- Q2  THE CONTRACT, AS FOUR ASSERTIONS OVER EVERY EMITTED ELEMENT.
--     Each column must read true. Any false is a producer defect, and the reason
--     each is here rather than trusted:
--       same_type_only      -- (a) above: a proposer must not change the service.
--       within_cap          -- 3 matches ottoq_promote_proposal_candidates'
--                              p_max_promotions default; a longer array is payload
--                              the consumer will never walk.
--       every_cand_has_kw   -- four L1 energy evaluators (EN.001-004) read
--                              requested_kw. This is the 0358 defect 0359 fixed.
--       never_self          -- the primary must not appear among its own fallbacks.
--       tie_break_ordered   -- (b) above: the emitted order is the total order.
--                              Equal kW must fall back to stall_id ascending, which
--                              is the case actually exercised on the twin depot
--                              because same-type plugs share a capacity.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
), c AS (
  SELECT p.proposal_id,
         p.proposal->>'stall_id'                        AS primary_stall,
         p.proposal->>'stall_type'                      AS primary_type,
         e.ord,
         e.value->>'stall_id'                           AS cand_stall,
         (e.value->>'requested_kw')                     AS cand_kw_txt,
         s.stall_type::text                             AS cand_type
    FROM public.ottoq_external_proposals p, r,
         jsonb_array_elements(p.proposal->'candidates') WITH ORDINALITY AS e(value, ord)
    LEFT JOIN public.stalls s ON s.id = (e.value->>'stall_id')::uuid
   WHERE p.sim_run_id = r.sim_run_id
     AND p.proposal ? 'candidates'
)
SELECT count(*)                                                        AS elements,
       count(DISTINCT proposal_id)                                     AS proposals,
       bool_and(cand_type = primary_type)                              AS same_type_only,
       max(ord) <= 3                                                   AS within_cap,
       bool_and(cand_kw_txt ~ '^[0-9]+(\.[0-9]+)?$')                   AS every_cand_has_kw,
       bool_and(cand_stall <> primary_stall)                           AS never_self,
       bool_and(NOT EXISTS (
         SELECT 1 FROM c c2
          WHERE c2.proposal_id = c.proposal_id
            AND c2.ord = c.ord + 1
            AND (c2.cand_kw_txt::numeric > c.cand_kw_txt::numeric
              OR (c2.cand_kw_txt::numeric = c.cand_kw_txt::numeric
                  AND c2.cand_stall < c.cand_stall))))                 AS tie_break_ordered
  FROM c;

-- Q3  A candidate must be a stall that EXISTS and belongs to the depot under test.
--     Rule 8: a stall count without the depot predicate is a number about a
--     different question, and 0250 is the retraction that proved it. A candidate
--     naming another depot's stall would be that defect inside a payload.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
)
SELECT count(*)                                                        AS elements,
       count(s.id)                                                     AS resolve_to_a_stall,
       count(*) FILTER (WHERE s.depot_id = '11111111-1111-1111-1111-111111111111')
                                                                       AS on_the_twin_depot,
       count(*) = count(*) FILTER (WHERE s.depot_id = '11111111-1111-1111-1111-111111111111')
                                                                       AS every_candidate_in_scope
  FROM public.ottoq_external_proposals p, r,
       jsonb_array_elements(p.proposal->'candidates') AS e(value)
  LEFT JOIN public.stalls s ON s.id = (e.value->>'stall_id')::uuid
 WHERE p.sim_run_id = r.sim_run_id
   AND p.proposal ? 'candidates';

-- Q4  THE OUTCOME, and per §5 it reads 0 until a primary goes infeasible while a
--     candidate is still free. Recorded now so the instrument exists and the
--     before-value is on the record rather than reconstructed later.
--     `rescued` is the number that answers G71: a proposal that would have been
--     refused for stall_occupied / stall_reserved and was promoted instead.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
)
SELECT count(*) FILTER (WHERE p.proposal ? 'promoted_from')             AS promoted,
       count(*) FILTER (WHERE p.proposal ? 'promoted_from'
                          AND p.status = 'enacted')                     AS promoted_then_enacted,
       count(*) FILTER (WHERE p.status = 'refused'
                          AND p.disposition_reason IN ('stall_occupied','stall_reserved'))
                                                                        AS still_refused_on_the_stall,
       count(*) FILTER (WHERE p.status = 'refused'
                          AND p.disposition_reason IN ('stall_occupied','stall_reserved')
                          AND p.proposal ? 'candidates')                AS refused_despite_candidates,
       max((p.proposal->>'promotion_count')::int)                       AS max_promotions_on_one_row
  FROM public.ottoq_external_proposals p, r
 WHERE p.sim_run_id = r.sim_run_id;

-- Q5  THE PAIRING, asserted rather than assumed. If the seed or the scenario
--     differs from the baseline, the comparison in §1 is between two different
--     worlds and every delta drawn from it is worthless -- C5's whole point about
--     the hold-constant side of an A/B.
--     Two corrections, both found by running this query rather than writing it.
--
--     (i) The runs are named EXPLICITLY rather than taken as the newest two. An
--         `ORDER BY started_at DESC LIMIT 2` printed `f14d5620` beside an unrelated
--         `production`/seed-42 fixture run, because a third run had started between
--         them -- so the query asserting the pairing was comparing the wrong pair.
--         Ordering is not identity.
--
--     (ii) IT READS `ottoq_run_archives`, NOT `ottoq_sim_runs`. Naming both runs
--         against `ottoq_sim_runs` returned ONE row: `ottoq_purge_prior_runs` ends
--         with `DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = ANY(v_doomed)`
--         and reports the count as `prior_runs_deleted`, so starting the paired run
--         deleted the baseline's own row. 9 runs survive there; the earliest is
--         2026-06-19. **A join to `ottoq_sim_runs` to resolve a historical run ID
--         silently returns nothing** -- same defect class as the clock-domain trap
--         (0251 Q6) and the unscoped `stall_code` join (0253 Q4): a join that drops
--         rows without erroring.
--
--     AND THE ALARM THAT WAS WRONG, RECORDED BECAUSE IT WAS WRONG. That looked at
--     first like a break in CLAUDE.md's credibility rule -- "no number ships
--     without a run ID" cannot hold if the run ID stops resolving. **It holds.**
--     `ottoq_run_archives` is the durable reproducibility record and it retained
--     **1,395 of 1,395 distinct runs, the baseline among them**, with the whole key
--     intact: scenario `busy_day`, policy `otto_q`, seed 1908402609758799079, the
--     twin depot, 1,124 ticks, `config_hash` af2525fa…, `engine_hash` c08000c4….
--     It is class `run_ledger` too and survives because the purge deletes
--     `class='engine'` by registry plus `ottoq_sim_runs` BY NAME.
--     So the honest statement is narrower than the alarm: `ottoq_sim_runs` is the
--     ledger of live and recent runs, `ottoq_run_archives` is the archive, and
--     historical analysis belongs in the second.
--
--     The one real residue is small: `ottoq_sim_runs.purged_at` exists to mark a
--     purged run, reads **0 of 9**, and the purge never references it (`position`
--     of 'purged_at' in its source is 0) -- the row is deleted instead of marked.
--     A column whose only job is to record an event that never writes it.
--
--     EXPECT ONE ROW WHILE THE PAIRED RUN IS STILL RUNNING. `ottoq_run_archives` is
--     written when a run ENDS, so `f14d5620` appears only after it completes. One
--     row here means the run is in flight, not that the pairing failed -- read
--     `still_in_sim_runs` to tell the two apart: the live arm is true there and
--     absent from the archive, the finished arm is the reverse.
SELECT CASE a.sim_run_id
         WHEN '92a6ac36-039f-4c34-9ad2-f0d35471047f' THEN 'baseline (v25)'
         ELSE 'paired (v27)' END            AS arm,
       a.sim_run_id, a.scenario, a.random_seed, a.tick_count, a.policy,
       a.config_hash, a.engine_hash,
       a.random_seed = 1908402609758799079  AS seed_matches_baseline,
       a.scenario = 'busy_day'              AS scenario_matches_baseline,
       a.depot_id = '11111111-1111-1111-1111-111111111111' AS on_the_twin_depot,
       EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                WHERE r.sim_run_id = a.sim_run_id)         AS still_in_sim_runs
  FROM public.ottoq_run_archives a
 WHERE a.sim_run_id IN ('92a6ac36-039f-4c34-9ad2-f0d35471047f',
                        'f14d5620-0dd9-4b39-9358-842cddecee8f')
 ORDER BY a.started_at;
