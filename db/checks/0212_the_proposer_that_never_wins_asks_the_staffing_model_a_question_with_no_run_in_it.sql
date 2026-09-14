-- =====================================================================
-- 0212  THE PROPOSER THAT NEVER WINS ASKS THE STAFFING MODEL A QUESTION
--       WITH NO RUN IN IT
-- =====================================================================
-- Read-only. Measured 2026-09-14 01:00-01:15 UTC (8:00-8:15 PM CT,
-- 2026-09-13) against the live otto-q-core engine.
--
-- ---------------------------------------------------------------------
-- FIRST, A CORRECTION TO WHAT 0275 AND I BOTH SAID
--
-- The intelligence census describes ottoq_service_priority as "not
-- switched off -- running and ignored", state INVOKED, 458 decisions and
-- zero enacted. The count is right and the WORD IS WRONG, in the
-- direction that makes the engine sound healthier than it is.
--
-- It is not ignored. It is obeyed, and its answer fails. The consumer is
-- ottoq_decide_tick section (5), line 964:
--
--   v_proposal := COALESCE(
--     ottoq_l2_external_proposal(p_sim_run_id,'service_sequencing',...),
--     ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx));
--
-- A COALESCE, not a contest. When an external proposal exists the local
-- proposer is NEVER CALLED. So on every tick this proposer speaks, it
-- replaces the one that works -- and then:
--
--   l2_engine                 enacted_verb   outcome            n
--   ottoq_service_priority    hold_no_bay    noop_no_candidate  462
--   service_sequencing        admit_service  enacted            367
--
-- 462 for 462 against 367 for 367. Not a low win rate: a total one, in
-- both directions. For sixteen days the presence of this proposer has
-- made that seat strictly worse than its absence.
--
-- ---------------------------------------------------------------------
-- THE MECHANISM, FROM ONE LINE OF A SHARED FUNCTION
--
-- Both proposers compute "how many service lanes are open" by calling
-- twin.ottoq_sim_lane_capacity(p_sim_run_id, p_lane_staff_key, p_physical).
-- They call it differently:
--
--   ottoq_l2_propose_service        (the local one, 367/367 enacted)
--     SELECT count(*) INTO v_phys FROM stalls s
--      WHERE s.depot_id = p_depot_id AND s.stall_type = 'service_bay';
--     v_svc_cap := ottoq_sim_lane_capacity(v_run, 'service_staff', v_phys);
--
--   ottoq_service_priority_propose  (the external one, 0/462 enacted)
--     v_cap := ottoq_sim_lane_capacity(NULL, 'service_staff', 2);
--
-- Two differences. The literal 2 instead of the physical bay count is a
-- LATENT one -- the flagship has exactly 2 service bays, measured, so
-- the numbers coincide here and would diverge at any depot that does not.
-- It is not what is failing today.
--
-- What is failing today is the FIRST ARGUMENT, and the reason is the
-- first executable line of the function both of them call:
--
--   IF p_sim_run_id IS NULL THEN RETURN p_physical; END IF;
--
-- Passing NULL does not mean "any run". It means SKIP THE STAFFING MODEL
-- ENTIRELY and return the raw physical number. Every other caller gets
--   GREATEST(1, FLOOR(p_physical * staffing_level * lane_staff))
-- and this one gets p_physical, flat.
--
-- For run 33f87a41 the boot draw recorded staffing_level 0.696 and
-- service_staff 0.487, so the two calls answer differently on the same
-- world in the same tick:
--
--   local     : GREATEST(1, FLOOR(2 * 0.696 * 0.487)) = GREATEST(1,0) = 1
--   external  : 2
--
-- The external proposer therefore admits a second vehicle to a lane the
-- run's staffing does not staff. ottoq.ottoq_enact_space_assignment,
-- which does honour the run, then refuses -- 'no_free_space' -- and the
-- decision is recorded noop_no_candidate with verb hold_no_bay.
--
-- You can read the contradiction inside a single decision row. The
-- proposal's own rationale says slots_free 1 or 2; the enacted action on
-- the same row says reason 'no_free_space'. Two counters, one tick, one
-- world, different answers.
--
-- ---------------------------------------------------------------------
-- THIS IS THE 0145 DEFECT CLASS, AGAIN
--
-- An unscoped read of a run-scoped quantity. 0145 was the pre-flight
-- validator reading every run's calendar; 0146 was the energy
-- orchestrator summing every run's charging sessions; this is a proposer
-- reading the staffing model with the run argument omitted. The sweep in
-- task #53 looked for unscoped reads of run-scoped TABLES. It would not
-- have found this one, because the unscoped read is an ARGUMENT to a
-- function -- and the function answers, helpfully and wrongly, instead of
-- failing.
--
-- ---------------------------------------------------------------------
-- AND IT IS INSIDE THE CERTIFIED PATH
--
--   run_by          proposals   runs
--   cert_harness        2,344   1,001
--   benchmark              14       5
--   ab_harness             10       5
--   proposer_live           9       3
--   proposer_demo           2       2
--   claude_v2_validation    1       1
--
-- 2,344 of 2,380 proposals were made inside certification runs. Unlike
-- cuOpt (quiesced by 0152) and the LLM proposer (quiesced by 0105), this
-- one is NOT quiesced: it runs in every pair, proposes, fails, and its
-- proposals are hashed into h_prop -- one of the fourteen atoms the
-- verdict compares.
--
-- Both arms fail identically, so every pair still PASSED. A thousand
-- certifications reproduced this defect byte-for-byte and called it
-- green, which is exactly right and exactly the point: the certification
-- proves reproducibility, not correctness. CLAUDE.md C5 says it in the
-- abstract -- "a run ID makes a number reproducible; it does not make it
-- meaningful" -- and this is the concrete instance.
--
-- The consequence for the fix: changing this proposer changes h_prop, so
-- it is forces_recert = TRUE and belongs in an apply window with a round
-- behind it, not a quiet evening patch. Drafted as 0277.
--
-- Tracked as G50.
-- =====================================================================

-- §1  The two outcomes, entire. 462/462 against 367/367.
SELECT l2_engine,
       action_context,
       enacted_action->>'verb'   AS enacted_verb,
       enacted_action->>'reason' AS enacted_reason,
       outcome_status,
       count(*) AS n
  FROM public.ottoq_decisions
 WHERE l2_engine IN ('ottoq_service_priority','service_sequencing')
 GROUP BY 1,2,3,4,5
 ORDER BY 1, n DESC;

-- §2  The contradiction inside one row: the proposal counts free slots,
--     the enactment on the same row says there is no free space.
SELECT d.sim_clock,
       d.proposed_action->>'verb'                        AS proposed_verb,
       d.proposed_action->'rationale'->>'slots_free'     AS proposer_says_slots_free,
       d.enacted_action->>'verb'                         AS enacted_verb,
       d.enacted_action->>'reason'                       AS enacted_reason,
       d.proposed_action->'rationale'->>'must_do'        AS must_do,
       d.proposed_action->'rationale'->>'priority'       AS priority
  FROM public.ottoq_decisions d
 WHERE d.l2_engine = 'ottoq_service_priority'
 ORDER BY d.created_at DESC
 LIMIT 5;

-- §3  THE ONE LINE. Why NULL is not "any run".
SELECT substring(regexp_replace(p.prosrc, E'\\s+', ' ', 'g')
                 from 'IF p_sim_run_id IS NULL THEN[^;]*;') AS the_null_shortcut,
       substring(regexp_replace(p.prosrc, E'\\s+', ' ', 'g')
                 from 'RETURN GREATEST[^;]*;')              AS what_every_other_caller_gets
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_lane_capacity';

-- §4  The two call sites, side by side, from the live bodies.
SELECT n.nspname || '.' || p.proname AS proposer,
       substring(regexp_replace(p.prosrc, E'\\s+', ' ', 'g')
                 from 'ottoq_sim_lane_capacity\([^)]*\)') AS how_it_asks,
       (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                       '--[^' || chr(10) || ']*','','g') ~ 'FROM stalls') AS reads_the_stalls_table
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname IN ('ottoq_l2_propose_service','ottoq_service_priority_propose')
 ORDER BY 1;
-- MEASURED: ottoq_l2_propose_service asks with the run and reads stalls;
-- ottoq_service_priority_propose asks with NULL and does not.

-- §5  The physical truth the external proposer never consults.
SELECT d.name AS depot,
       count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type) AS service_bays
  FROM public.stalls s JOIN public.depots d ON d.id = s.depot_id
 GROUP BY 1 HAVING count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type) > 0
 ORDER BY 2 DESC;
-- MEASURED at the flagship: 2. The hardcoded 2 coincides here, which is
-- why that half of the defect is latent rather than active.

-- §6  Where it proposes: inside the certification, 1,001 runs of it.
SELECT COALESCE(r.run_by,'(null)') AS run_by,
       count(*) AS proposals,
       count(DISTINCT p.sim_run_id) AS runs
  FROM public.ottoq_external_proposals p
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.sim_run_id
 WHERE p.source = 'ottoq_service_priority'
 GROUP BY 1 ORDER BY proposals DESC;

-- §7  And the COALESCE that makes it a replacement rather than a contest.
WITH src AS (
  SELECT prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick'
), lines AS (
  SELECT row_number() OVER () AS ln, l
    FROM src, LATERAL regexp_split_to_table(src.prosrc, chr(10)) AS l
)
SELECT ln, l FROM lines
 WHERE l LIKE '%ottoq_l2_external_proposal(p_sim_run_id, ''service_sequencing''%'
    OR l LIKE '%ottoq_l2_propose_service(v_req.vehicle_id%'
 ORDER BY ln;

-- =====================================================================
-- CORRECTION 2026-09-14 03:30 UTC (10:30 PM CT, 2026-09-13)
-- THIS FILE REDISCOVERED G47 AND GAVE IT A SHALLOWER CAUSE
-- =====================================================================
-- db/checks/0188 -- "the service proposer is heard, consumed, and
-- physically unable to win" -- root-caused this same 0-for-N on
-- 2026-09-13, THE DAY BEFORE this file was written, and its answer is
-- the better one:
--
--   "a resource is taken earlier in the same tick than the proposer's
--    turn to use it"
--
-- 0188 measured 446 decisions naming ottoq_service_priority as the
-- enacted source, every one noop_no_candidate, and found the two
-- service bays booked 1,725 times in three days by section (4b) --
-- which runs at decide_tick line ~846, EARLIER IN THE SAME FUNCTION
-- BODY than section (5)'s seat at line 965.
--
-- WHAT THAT MEANS FOR THE FINDING ABOVE. The NULL run argument is real
-- -- ottoq_service_priority_propose does pass NULL to a run-scoped
-- staffing function, and twin.ottoq_sim_lane_capacity does return the
-- raw physical number for a NULL run. That is a genuine defect of the
-- 0145 class and it is worth fixing. But it is NOT why this proposer
-- has never won, and this file implied that it was.
--
-- Fixing the argument would make the proposer propose LESS OFTEN. On
-- the occasions it still proposed, section (4b) would already have
-- taken the bays and the outcome would be identical. The header above
-- says "the fix is one argument"; that is wrong, and the sentence
-- "MECHANISM" should be read as "a second, independent defect".
--
-- G50 is therefore DEMOTED to a secondary bug, and G47/0188 holds the
-- root cause. The two are not in conflict; they are at different
-- depths, and this file mistook the shallower one for the whole story.
--
-- ---------------------------------------------------------------------
-- AND THE SAME DEFECT EXPLAINS G49, MEASURED HERE
--
-- db/checks/0211 recorded 23 CP-SAT proposals that met
-- noop_no_candidate as a LEAD, saying the state that would settle it
-- was gone. It was not gone -- ottoq_stall_bookings still holds it.
-- Measured on run 33f87a41-3f0e-41c6-8da8-608376d56d6a (query in §8):
--
--   23 of 23   the stall CP-SAT named was booked in that same run
--   23 of 23   booked for a DIFFERENT vehicle
--   18 of 23   booked BEFORE CP-SAT proposed
--    5 of 23   booked between proposing and being considered
--    0 of 23   booked after the decision
--
--   who took them: otto_q / otto_q_enacted / otto_q_reaction
--   for what:      charge_dcfc, charge_l2
--
-- So the dominant cause for CP-SAT (18 of 23, 78%) is NOT the in-tick
-- race that beats the service proposer -- it is that THE FRAME CP-SAT
-- SOLVED AGAINST WAS ALREADY STALE WHEN IT SOLVED. Same family, one
-- level earlier: the proposer's view of the world and the kernel's
-- commitment of the world are not synchronised, and nothing compares
-- them.
--
-- THE DETECTOR IS HALF-BUILT, AND MEASURING IT CORRECTED THE FIRST
-- DRAFT OF THIS PARAGRAPH. The claim I started to write -- that
-- ottoq_build_decision_frame stamps frame_hash -- IS FALSE. Measured
-- (query in §9): frame_hash exists in exactly two places in this
-- database, the column ottoq_proposer_fire_log.frame_hash and the
-- function ottoq_proposer_submit_batch that writes it.
-- ottoq_build_decision_frame does not compute it, ottoq_decide_tick does
-- not read it, ottoq_l2_external_proposal does not read it, and
-- ottoq_submit_external_proposal does not carry it.
--
-- So the hash is computed CLIENT-SIDE by the bridge and deposited in a
-- log. The kernel neither computes the identity of the world it handed
-- out nor compares it to the world it is judging against. A proposal is
-- never checked against the world it was computed from, and the engine
-- has no way to check it even if it wanted to.
--
-- ONE DEFECT, THREE SYMPTOMS, previously filed as three findings:
--   G47 / 0188   service proposer   446/446  resource taken earlier in tick
--   G49 / 0211   CP-SAT              23/23   frame stale before it solved
--   (advisor)    llm_advisor         22/24   stall occupied or reserved
-- G49 is CLOSED by the measurement below. G47 stands. G50 is demoted.
-- =====================================================================

-- §8  THE MEASUREMENT THAT CLOSES G49. Re-runnable against any run.
WITH p AS (
  SELECT pr.proposal_id, pr.entity_id, pr.created_at AS proposed_at,
         (pr.proposal->>'stall_id')::uuid AS want_stall
    FROM public.ottoq_external_proposals pr
   WHERE pr.sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
     AND pr.source = 'forward_lex'
     AND NOT COALESCE((pr.proposal->>'abstain')::boolean, false)
), nxt AS (
  SELECT p.proposal_id, p.entity_id, p.proposed_at, p.want_stall,
         d.outcome_status, d.created_at AS decided_at,
         row_number() OVER (PARTITION BY p.proposal_id ORDER BY d.created_at) rn
    FROM p LEFT JOIN public.ottoq_decisions d
      ON d.sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
     AND d.action_context = 'stall_assignment'
     AND d.entity_id = p.entity_id
     AND d.created_at >= p.proposed_at
), lost AS (SELECT * FROM nxt WHERE rn = 1 AND outcome_status = 'noop_no_candidate'),
   b AS (
  SELECT l.proposal_id, l.proposed_at, l.decided_at,
         min(bk.booked_at)                     AS first_rival_booking,
         string_agg(DISTINCT bk.booked_by, ',') AS rival_bookers,
         string_agg(DISTINCT bk.purpose,   ',') AS rival_purposes
    FROM lost l
    JOIN public.ottoq_stall_bookings bk
      ON bk.stall_id   = l.want_stall
     AND bk.sim_run_id = '33f87a41-3f0e-41c6-8da8-608376d56d6a'
     AND bk.vehicle_id <> l.entity_id
   GROUP BY 1,2,3)
SELECT count(*)                                                          AS n,
       count(*) FILTER (WHERE first_rival_booking <  proposed_at)        AS taken_BEFORE_proposed,
       count(*) FILTER (WHERE first_rival_booking >= proposed_at
                          AND first_rival_booking <= decided_at)         AS taken_BETWEEN,
       count(*) FILTER (WHERE first_rival_booking >  decided_at)         AS taken_AFTER_decision,
       string_agg(DISTINCT rival_bookers,  ' | ')                        AS who_took_them,
       string_agg(DISTINCT rival_purposes, ' | ')                        AS for_what
  FROM b;
-- MEASURED 2026-09-14 03:2x UTC: 23 | 18 | 5 | 0 |
--   otto_q_enacted | otto_q,otto_q_enacted | otto_q,otto_q_enacted,otto_q_reaction
--   charge_dcfc | charge_l2

-- §9  WHERE frame_hash ACTUALLY LIVES. Two places, and neither is on
--     the read or the disposal path. Run both halves.
SELECT n.nspname||'.'||p.proname AS fn,
       (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                       '--[^' || chr(10) || ']*','','g') ~ 'frame_hash') AS mentions_frame_hash
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND p.proname IN ('ottoq_build_decision_frame','ottoq_decide_tick',
                     'ottoq_l2_external_proposal','ottoq_submit_external_proposal')
 ORDER BY 1;
-- MEASURED: false for all four, including the frame builder itself.

SELECT 'column' AS kind, table_name||'.'||column_name AS where_it_is
  FROM information_schema.columns
 WHERE table_schema='public' AND column_name ILIKE '%frame_hash%'
UNION ALL
SELECT 'function', n.nspname||'.'||p.proname
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),
                      '--[^' || chr(10) || ']*','','g') ~ 'frame_hash'
 ORDER BY 1,2;
-- MEASURED: exactly two rows --
--   column   ottoq_proposer_fire_log.frame_hash
--   function public.ottoq_proposer_submit_batch
-- The bridge computes it, one function logs it, nothing compares it.
