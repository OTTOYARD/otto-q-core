-- 0303  THE AGENT→CP-SAT LOOP IS WORKING, AND THE FIRST THING IT TOLD US IS THAT THE DEPOT IS
--       FULL. Eleven consecutive hops returned `solved_but_zero_proposals`, and the reason is not a
--       solver fault: **0 of the twin depot's 40 charge-capable stalls were offerable**, with **45
--       vehicles in a serviceable state and 31 held**. This is `0250`'s capacity wall, measured from
--       the solver's own refusal rather than inferred from a census.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Measured 2026-09-21 07:48–07:52 UTC on live run f13fc580 (seed 100021, busy_day, otto_q),
-- sim clock 2026-09-21 05:56 UTC — hour 5, the overnight L2 wave.
--
-- ══ 1. THE SOLVER'S OWN SENTENCE, WHICH IS THE FINDING ══════════════════════
--
-- `fire.error`, verbatim, from the CP-SAT bridge on the live frame:
--
--     "frame has 40 charge-capable stall(s) and not one is offerable this tick
--      (2 charger_faulted, 37 occupied, 1 reserved); nothing free to propose on"
--
-- and the counts beside it:
--
--     n_vehicles 116 · n_in_serviceable_state 45 · n_vehicles_held 31
--     n_stalls 158 · n_charge_stalls 40 · n_stalls_busy 40
--     stalls_blocked { occupied 37, reserved 1, charger_faulted 2 }
--     status "empty" · n_rows 0 · n_planned 0 · n_abstained 0
--     serviceable_states [arrived_at_gate, charging_dcfc, charging_l2, staged_awaiting_service]
--     site.power_cap_kw_hard 633 (derived, ottoq_build_site_descriptor)
--
-- **`n_abstained 0` alongside `n_rows 0` is the distinction that matters.** The solver did not
-- consider 45 vehicles and decline them; it never got a vehicle/stall pair to consider, because
-- there was no free stall to pair with. An abstention is a judgement; this is an empty domain.
--
-- ══ 2. VERIFIED INDEPENDENTLY, AND UNDER ALL THREE GATES ════════════════════
--
-- The solver's count is the solver's word for it, so it was re-derived in SQL against
-- CLAUDE.md's three-gate rule — the pointer, the CALENDAR, and the OCPP charger not being
-- `Faulted`. Measured in the same minute:
--
--   type   total  pointer_occupied  pointer_reserved  charger_faulted  calendar_busy  OFFERABLE
--   dcfc      10                 7                 7                1              7          0
--   l2        30                29                14                1             28          0
--
-- **Zero offerable, and the three gates disagree with each other exactly as that rule warns.** On
-- L2 the pointer says 29 of 30 busy, the reservation column says 14, and the calendar says 28 —
-- quote any single gate and you get a different depot. Only the intersection is the answer, and the
-- intersection is that nothing is free. So the solver's sentence is confirmed and, if anything,
-- slightly conservative (its 37+1+2 against this census's 36+2, a few seconds of drift apart on a
-- live run).

WITH r AS (
  SELECT sim_run_id AS rid, sim_clock_current AS sc
    FROM public.ottoq_sim_runs WHERE status = 'running'
   ORDER BY started_at DESC LIMIT 1
), s AS (
  SELECT st.id, st.stall_type::text AS t, st.current_vehicle_id,
         st.reserved_by, st.reservation_expires_at, st.ocpp_charger_id
    FROM public.stalls st
   WHERE st.depot_id = '11111111-1111-1111-1111-111111111111'
     AND st.stall_type::text IN ('dcfc','l2')
)
SELECT s.t,
       count(*)                                                            AS total,
       count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL)            AS pointer_occupied,
       count(*) FILTER (WHERE s.reserved_by IS NOT NULL
                          AND coalesce(s.reservation_expires_at, (SELECT sc FROM r)) >= (SELECT sc FROM r))
                                                                           AS pointer_reserved,
       count(*) FILTER (WHERE c.station_state = 'Faulted')                 AS charger_faulted,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                       WHERE b.stall_id = s.id AND b.state IN ('held','active')
                                         AND b.during @> (SELECT sc FROM r)))
                                                                           AS calendar_busy,
       -- the only number that answers "can anything be offered": the INTERSECTION
       count(*) FILTER (WHERE s.current_vehicle_id IS NULL
                          AND (s.reserved_by IS NULL
                               OR coalesce(s.reservation_expires_at, (SELECT sc FROM r)) < (SELECT sc FROM r))
                          AND coalesce(c.station_state,'Available') <> 'Faulted'
                          AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                           WHERE b.stall_id = s.id AND b.state IN ('held','active')
                                             AND b.during @> (SELECT sc FROM r)))
                                                                           AS offerable_all_three_gates
  FROM s LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
 GROUP BY s.t ORDER BY s.t;

-- ══ 3. AND THE SERVICE IS NOT THE THING REFUSING — PROVEN BY RUNNING IT LOCALLY ══
--
-- Before calling this a capacity finding rather than a service fault, the SAME solver was run
-- locally on the SAME frame (pulled from `ottoq_build_decision_frame` in the same minute), against
-- the pinned core ref `480427d2`, on a venv holding exactly `requirements.txt`'s pins:
--
--   local   10 ms   status 'empty'   rows 0   real 0   n_in_serviceable_state 45
--   hosted  17 ms   status 'empty'   rows 0   real 0   (ledger: http 200, endpoint_source db)
--
-- **Byte-for-byte the same verdict from two independent executions.** So the EC2 service is
-- behaving identically to the solver in this repository, and "zero proposals" is the frame's
-- answer, not the deployment's. That is worth stating because the previous two days' failures were
-- all deployment failures, and the reflex by now is to suspect the box.
--
-- ══ 4. WHAT THIS IS, IN PRODUCT TERMS, AND IT IS THE GOAL'S OWN QUESTION ════
--
-- CLAUDE.md rule 8 states the goal in Chase's words: *"see potentially how many vehicles at one
-- time we can comfortably stage and sort and orchestrate through there."* **This is that number
-- being hit.** At hour 5 on a busy_day seed, the twin depot's charge capacity is saturated —
-- 40 of 40 charge stalls unavailable — while 45 vehicles sit in a serviceable state and 31 are
-- held. The engine is not failing to decide; there is nothing left to decide with.
--
-- Two components of the saturation are worth separating, because they have different fixes:
--
--   **(a) Occupancy — 36 of 40 stalls have a vehicle in them.** That is demand exceeding charge
--   capacity at the overnight L2 wave, which is a depot-design answer (more L2 points, or
--   shifting the wave), not a scheduling one. No solver recovers a stall that is legitimately
--   in use.
--   **(b) Faults — 2 of 40 chargers are `Faulted`.** Consistent with Part 3's standing measurement
--   that ~13.8% of charger-time is lost to faults on a busy_day run, so effective capacity is
--   ~86% of nameplate continuously. At 100% occupancy those 2 stalls are the difference between
--   zero offerable and two offerable — i.e. between the solver having no move and having one.
--
-- **DO NOT read this as "CP-SAT adds nothing".** It has not yet been given a frame with a free
-- stall, and a solver that correctly reports an empty domain is behaving exactly as an advisory
-- proposer behind a deterministic shield should. What it has demonstrated is that the chain now
-- carries a TRUE answer about the depot from the solver to the ledger — which is the thing that
-- did not work at any point in the previous two days.
--
-- ══ 5. WHAT IS STILL OWED (G108) ════════════════════════════════════════════
--
-- G108 closes on a hop where a charge stall IS offerable: `outcome='answered'` with
-- `proposals_out > 0`, plus `ottoq_external_proposals` rows carrying
-- `submitted_by_role='system:service_role'` and the fire-log row carrying
-- `submit_path='edge:ottoq-cpsat-propose'`. That needs the wave to break, not a code change.
-- Until it happens the honest sentence is: *"the agent chain reaches CP-SAT and CP-SAT answers
-- truthfully; every answer so far has been that the depot has no free charge stall."*

-- The live counts, so a reader can see whether the wave has broken since.
SELECT count(*) FILTER (WHERE endpoint IS NOT NULL AND http_status = 200)               AS hops_reaching_the_service,
       count(*) FILTER (WHERE endpoint IS NOT NULL AND outcome = 'answered')            AS answered_with_rows,
       count(*) FILTER (WHERE endpoint IS NOT NULL
                          AND outcome = 'solved_but_zero_proposals')                    AS empty_frames,
       coalesce(sum(proposals_out) FILTER (WHERE endpoint IS NOT NULL), 0)              AS proposals_from_agent_path,
       max(called_at) FILTER (WHERE endpoint IS NOT NULL)                               AS last_hop
  FROM public.ottoq_model_call_ledger
 WHERE provider = 'cpsat_service';

-- OPEN-ITEM: the agent path reaches CP-SAT and CP-SAT answers truthfully, but every answer so far is "no free charge stall" -- 0 of 40 offerable under all three gates, with 45 serviceable vehicles and 31 held. G108 still needs one hop with proposals_out > 0 plus the matching service_role proposal row, and that needs the overnight wave to break rather than a code change. Separately this file raises the capacity question rule 8 names as the goal: at hour 5 on busy_day the twin depot's charge capacity is fully saturated, and 2 of the 40 stalls are lost to charger faults. Tracked as G108.
