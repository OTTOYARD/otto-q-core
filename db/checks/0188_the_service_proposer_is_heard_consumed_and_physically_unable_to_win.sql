-- ---------------------------------------------------------------------------
-- 0188 — G47 ROOT-CAUSED: the certified proposer that has never been followed
-- is not a dead seat. It is heard, consumed, and beaten to the resource by an
-- earlier section of the same tick.
--
-- THE FINDING THAT OPENED THIS (AGENT_HARNESS.md, 2026-09-13):
--   ottoq_service_priority — one of only THREE rows in ottoq_certified_proposers
--   — has 2,335 proposals over 15 days (2026-08-29 → 09-13) and ZERO enacted,
--   in the service_sequencing context, while agent_probe enacted 40 of 240 in
--   that same context. Three hypotheses: the seat is never consulted; the rows
--   always lose a tie; or the rows are structurally infeasible.
--
-- ALL THREE ARE WRONG, and the real answer is the same defect family as the
-- stall-hold gap (proposer/README.md L-60, migration 0264): a resource is taken
-- earlier in the same tick than the proposer's turn to use it.
-- ---------------------------------------------------------------------------

-- 1. THE SEAT IS CONSULTED. decide_tick §(5) SERVICE SEQUENCING calls the
--    selector before its heuristic, exactly as §(3) does for stall assignment.
WITH src AS (SELECT p.prosrc s FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='ottoq_decide_tick' AND p.prokind='f'),
lines AS (SELECT ord ln, l FROM src, regexp_split_to_table(s, E'\n') WITH ORDINALITY AS t(l, ord))
SELECT ln, trim(l) FROM lines WHERE l LIKE '%service_sequencing%' ORDER BY ln;
-- MEASURED 2026-09-13:
--   943  -- (5) SERVICE SEQUENCING
--   965  ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id),
--   1006 v_bay_leg_id, 'service_sequencing');
-- So line 965 is the seat, inside COALESCE(selector, ottoq_l2_propose_service(...)).

-- 2. ITS PROPOSALS ARE CONSUMED — and every single consumption is a no-op.
SELECT d.outcome_status, coalesce(d.resolved_action_context, d.action_context) AS ctx,
       count(*) AS n, min(d.created_at)::date AS first, max(d.created_at)::date AS last
  FROM public.ottoq_decisions d
 WHERE d.enacted_action->>'source' = 'ottoq_service_priority'
 GROUP BY 1,2 ORDER BY n DESC;
-- MEASURED: one row. noop_no_candidate | task_start | 446 | 2026-08-29 | 2026-09-13.
-- 446 decisions name this proposer as the source of the enacted action, and not
-- one of them enacted anything.

-- 3. WHY: the branch that sets that outcome in §(5) is "no bay -> do not enter one".
WITH src AS (SELECT p.prosrc s FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='public' AND p.proname='ottoq_decide_tick' AND p.prokind='f'),
lines AS (SELECT ord ln, l FROM src, regexp_split_to_table(s, E'\n') WITH ORDINALITY AS t(l, ord))
SELECT ln, trim(l) FROM lines WHERE ln BETWEEN 1027 AND 1036 ORDER BY ln;
-- MEASURED: 1029  -- NO BAY -> DO NOT ENTER ONE. Identical in effect to this proposer's own
--           1032  jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
--           1035  v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; ...

-- 4. AND THE BAYS ARE NOT IDLE — they are taken, 1,725 times in three days, on
--    TWO stalls, by the bay loop §(4b) which runs EARLIER IN THE SAME TICK.
SELECT s.stall_type, count(*) AS stalls,
       count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL) AS occupied_now,
       (SELECT count(*) FROM public.ottoq_stall_bookings b
         WHERE b.stall_id IN (SELECT id FROM public.stalls s2
                               WHERE s2.depot_id = s.depot_id AND s2.stall_type = s.stall_type)
           AND b.booked_at > now() - interval '3 days') AS bookings_3d
  FROM public.stalls s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY s.depot_id, s.stall_type ORDER BY 2 DESC;
-- MEASURED: staging 113 (59,288 bookings/3d) · l2 30 (24,712) · dcfc 10 (6,665)
--           wash_bay 3 (9,085) · service_bay 2 (1,725).
-- Two service bays, heavily booked. The flagship depot's 158 stalls match the
-- certification's own wsec n.stalls = 158, so this is the world the cert runs on.

-- ---------------------------------------------------------------------------
-- THE CONCLUSION, AND WHY IT IS NOT A SHRUG
--
-- ottoq_service_priority is heard (the seat is wired), consumed (446 decisions
-- name it), and PHYSICALLY UNABLE TO BE FOLLOWED, because by the time §(5) runs,
-- §(4b) has booked both service bays in the same tick. Its proposals are then
-- marked superseded (the entity was decided this tick, by something else) or
-- expired. That is why a CERTIFIED proposer shows 2,335 proposals and zero
-- enactments over fifteen days.
--
-- THIS IS THE SAME DEFECT AS THE STALL-HOLD GAP, ON A DIFFERENT RESOURCE.
-- proposer/README.md L-60 and db/checks/0186: the CP-SAT proposer's 90 rows died
-- because nothing protects the charge stall a proposer names for the one tick its
-- vehicle is held. Here nothing protects the service bay a proposer names either,
-- and the competitor is not another proposer — it is an earlier section of the
-- disposer itself. So "the proposer is most useful under contention" (Chase,
-- 2026-09-13) has a corollary the design must answer: UNDER CONTENTION, THE
-- PROPOSER IS EXACTLY WHO LOSES, because it is asked last.
--
-- THREE CANDIDATE FIXES, none applied, in increasing order of risk:
--   (a) Extend whatever 0264 settles for charge stalls to bays: a pending
--       proposal's named resource is held for one tick for that proposal.
--       Cheapest if 0264's mechanism is resource-generic rather than
--       stall-specific — which is an argument for designing it generically.
--   (b) Let §(5) see what §(4b) did: pass the bays booked this tick into the
--       proposer's context so it proposes a bay that can still be had, or
--       abstains honestly instead of proposing into a wall.
--   (c) Reorder the tick so service sequencing is asked before the bay loop.
--       Highest risk: it changes the disposer's order, which is a certification
--       recert and a behaviour change on every run, for the benefit of one lane.
--
-- WHAT MUST NOT HAPPEN: quoting "2,335 proposals" as evidence of an active
-- agent layer. Nothing it proposed has ever happened. AGENT_HARNESS.md states
-- the zero and names this file.
--
-- A SECOND, SMALLER TRAP FOUND ON THE WAY (recorded, not yet a defect):
-- decide_tick's lifecycle closer credits a proposal only when
--     d.enacted_action->>'source' = p.source
-- at the same tick for the same entity. Measured over three days, 24,953 enacted
-- task_start decisions carry NO 'source' key at all, and several stall_assignment
-- paths write a PATH name rather than a proposer name ('reservation_honoured'
-- 5,742, 'inspect_seam' 9,132, 'needs_card' 892). Those particular paths owe no
-- proposal credit — they consumed a reservation or a seam, not a proposal — so
-- nothing is wrong today. But the rule means ANY future proposer whose consuming
-- path rewrites or drops `source` will read as "0 enacted" while being followed
-- every tick. Credit by proposal id would be immune; credit by string match is
-- not. Check this before reading an enactment count as influence.
-- ---------------------------------------------------------------------------
