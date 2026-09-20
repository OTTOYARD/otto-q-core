-- 0278  G91: THE CABIN ADMISSION GATE STOPS ONE STATE SHORT, AND THE FUNCTION'S OWN
--       COMMENT ALREADY DESCRIBES THE FAILURE IT CAUSES. FIXED BY `db/migrations/0385`.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), completed
-- demo run `562bf027-6c74-4cb1-9d96-722af13b2fcc` (busy_day, seed 777777, 1,241 ticks,
-- 542.6 sim-minutes, 620 decision snapshots). Those tables are `class='engine'` and the
-- next demo run takes them to zero, so every figure below cites the run.
--
-- ══ 0. THE FIX I WAS ABOUT TO BUILD WAS THE WRONG FIX ══════════════════════
--
-- After 0383 I recorded a starvation risk: a vehicle blocked from departing competes for
-- the `general_tech` pool against charging vehicles that the cursor ranks ABOVE it, so it
-- could wait on a technician forever. I planned to re-rank the ORDER BY.
--
-- **Measured, that is wrong in the way that matters: the pool is not contended for this
-- population at all.** Across the blocked vehicle-ticks the `general_tech` pool averaged
-- **1.66 of 10** busy and was full in **18 of 3,055 (0.6%)**. Re-ranking a queue would have
-- re-ranked a queue nobody was waiting in. Independent arithmetic agrees: 221 cabin starts
-- at ~4 minutes against 10 technicians x 542 sim-minutes is ~16% utilisation.
--
-- **And ORDER BY was the wrong lever on its own terms.** It orders CANDIDATES. These
-- vehicles are never candidates.
--
-- ══ 1. THE ACTUAL GATE ═════════════════════════════════════════════════════
--
-- `twin.ottoq_sim_advance_visit_atoms`'s first cursor admits six vehicle states, then
-- sub-gates by concurrency class, verbatim before 0385:
--
--     AND ( (a->>'concurrency' = 'cabin'
--              AND v.current_state IN ('charging_dcfc','charging_l2',
--                                      'charge_complete_holding'))
--        OR (a->>'concurrency' IN ('exterior','digital')) )
--
-- `exterior` and `digital` are startable in all six. **`cabin` is startable in three**, and
-- `staged_for_departure` is not among them. A vehicle that arrives in that state still
-- holding a mandatory cabin atom fails the EXISTS, is never selected, and **cannot be
-- rescued at any value of `v_free`** — this is stronger than starvation, which at least
-- implies a queue.
--
-- Meanwhile `ottoq_eval_sla_004_required_services` (severity `critical`) blocks
-- redeployment on exactly that atom shape:
--
--     WHERE COALESCE((a->>'must_do')::boolean, true)
--       AND NOT COALESCE((a->>'deferrable')::boolean, false)
--       AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped')
--
-- So the vehicle may not leave, and nothing may start the work that would let it.
--
-- ══ 2. AND THE COMMENT ABOVE THE LIST DIAGNOSES THIS, FOR THE NEIGHBOUR ════
--
-- Sitting directly above that gate, unchanged since it was written:
--
--     "charge_complete_holding is kept ONLY as a catch-up: without it a vehicle whose
--      charge finished before the tech arrived would never be cleaned and SLA.004 would
--      block its deploy forever."
--
-- The mechanism was seen exactly, and fixed for the state immediately before the one where
-- it still bites. A vehicle can leave `charge_complete_holding` for `staged_for_departure`
-- with the atom still pending, and past that boundary the catch-up stops applying. **0385
-- adds the second catch-up and changes nothing else.**

SELECT (p.prosrc LIKE '%''staged\_for\_departure''))%')            AS gate_admits_sfd_now,
       (p.prosrc LIKE '%''charge\_complete\_holding''%')            AS catch_up_1_intact,
       (p.prosrc LIKE '%OR (a->>''concurrency'' IN (''exterior'',''digital''))%')
                                                                   AS exterior_still_state_free
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_visit_atoms';

-- ══ 3. THE MEASUREMENT ═════════════════════════════════════════════════════
--
-- **Blocked vehicle-ticks, every one of them cabin.** Over the run there were **3,055**
-- vehicle-ticks in which a vehicle sat in `staged_for_departure` holding an unstarted
-- blocking in-place atom: **3,049 `interior_inspection` + 6 `interior_tidy`**, and
-- **ZERO `exterior`**. That last zero is the control — `exterior` is the one class where
-- pool contention could have bound, and it never arose.
--
-- **End state, which is the figure this file stands behind.** 28 vehicles finished the run
-- holding a pending, non-deferrable, `must_do` cabin atom: **21 `interior_inspection` + 7
-- `interior_tidy`**. None could redeploy; nothing could start their atom.
--
-- **A shape figure, deliberately NOT quoted as a dwell.** 95 of 115 vehicles appear in
-- `staged_for_departure` at some tick; 29 span >= 400 sim-minutes, the widest 541.4 of
-- 542.6. **That span is first-seen to last-seen, not continuous occupancy** — a vehicle
-- that enters, leaves and returns yields a wide span from two short visits. It bounds the
-- problem; it is not a stranding duration.
--
-- **What could NOT be established.** The snapshot frame carries `vehicles[].state` but no
-- atoms, so for an arbitrary past tick there is no stored record of which atoms were
-- pending. The per-tick pairing above was reconstructed by interval arithmetic over each
-- atom's own `started_at`/`ends_at`, which is sound for atoms that eventually started and
-- necessarily approximate for atoms that never did. The 28-vehicle end state needs no
-- reconstruction and is the number to quote.

SELECT v.current_state,
       at->>'concurrency' AS cls,
       at->>'svc'         AS svc,
       count(*)           AS stranded_atoms,
       count(DISTINCT v.id) AS vehicles
  FROM public.ottoq_visit_needs n
  JOIN public.vehicles v ON v.id = n.vehicle_id
 CROSS JOIN LATERAL jsonb_array_elements(n.atoms) at
 WHERE n.depot_id = '11111111-1111-1111-1111-111111111111'
   AND n.sim_run_id = '562bf027-6c74-4cb1-9d96-722af13b2fcc'
   AND COALESCE(at->>'status','pending') = 'pending'
   AND COALESCE((at->>'must_do')::boolean, false)
   AND NOT COALESCE((at->>'deferrable')::boolean, false)
 GROUP BY 1,2,3 ORDER BY 4 DESC;

-- NOTE ON READING THAT QUERY AFTER A RUN ENDS: `vehicles.current_state` reads `offline`
-- for every row once the run is torn down, so it cannot be used to recover the state a
-- vehicle was IN while blocked. That is why the per-tick work above goes to
-- `ottoq_decision_snapshots`, whose frame preserves state per tick.

WITH f AS (
  SELECT s.tick_seq, s.sim_clock, e->>'id' AS vid, e->>'state' AS state
    FROM public.ottoq_decision_snapshots s
   CROSS JOIN LATERAL jsonb_array_elements(s.frame->'vehicles') e
   WHERE s.sim_run_id = '562bf027-6c74-4cb1-9d96-722af13b2fcc'
), sfd AS (
  SELECT vid,
         round(EXTRACT(EPOCH FROM (max(sim_clock) - min(sim_clock)))/60.0, 1) AS span_sim_min
    FROM f WHERE state = 'staged_for_departure' GROUP BY vid
)
SELECT count(*)                                        AS vehicles_ever_sfd,
       count(*) FILTER (WHERE span_sim_min >= 400)     AS span_400min_plus,
       round(max(span_sim_min),1)                      AS widest_span_min,
       'SPAN IS FIRST-TO-LAST-SEEN, NOT CONTINUOUS DWELL' AS caveat
  FROM sfd;

-- ══ 4. THE DOCTRINE THE GATE DEFENDS IS ALREADY 84% BYPASSED ═══════════════
--
-- The gate exists for `M3_cabin_at_charger`: cabin work should overlap a charging session,
-- because serialising it gives away throughput (CLAUDE.md 2.3). Loosening it deserved care,
-- so it was checked rather than assumed — and the doctrine turns out to be nominal.
--
-- The gate is a SELECTION filter only. `ottoq_start_concurrent_atoms` re-checks no vehicle
-- state, and `public.ottoq_decide_tick` calls it from two stall-enactment sites of its own,
-- where the vehicle has been assigned a stall but the twin has not yet flipped its state.
-- Measured state at cabin-atom start on this run:
--
--   arrived_at_gate            **141**
--   staged_awaiting_service     **45**
--   charging_l2                 **24**
--   charging_dcfc               **11**
--   -----------------------------------
--   in a charging state      **35 of 221 = 15.8%**
--
-- The gate's own comment justifies itself by saying *"only 5.8% of interior cleans actually
-- overlapped a charge"*. It is now 15.8% — better, and still not the doctrine. **So adding
-- one catch-up state to a selection filter cannot weaken an invariant that the executing
-- path never enforced.**
--
-- **This is a finding about M3 in its own right and is left OPEN, not fixed by 0385.**
-- Making cabin work genuinely charge-overlapped would mean gating the STARTER rather than
-- the cursor, and that is a throughput change, not a deadlock repair. Tracked as G92.
--
-- ══ 5. WHERE THE POOL *DOES* BIND, WHICH IS THE OPPOSITE END ═══════════════
--
-- The `general_tech` pool is not idle everywhere. Reconstructed over 546 sim-minutes it
-- reached its full headcount of 10, averaged 1.72, and sat at the cap for 11 minutes
-- (2.01%). Broken down by what the waiting vehicle was waiting FOR, the mean technicians
-- busy during a DCFC wait was **9.91 of 10**. So a reserved slice of the pool for departing
-- vehicles — the other fix I considered — would have been paid for by the population that
-- is genuinely contended. **Not built, for that reason.**
--
-- ══ 6. ONE MORE THING RULED OUT RATHER THAN FIXED ══════════════════════════
--
-- `SLA.004` is the only one of five gates that does not exempt `readiness_check`, and that
-- omission accounts for **22 of the 25** shield blocks on this run. It looks like a defect
-- and is not one: `twin.ottoq_sim_advance_visit_atoms` carries a dedicated branch that
-- completes a pending `readiness_check` the moment a vehicle is in `staged_for_departure`,
-- so those blocks resolve themselves on the next tick rather than stranding anything. The
-- 3 remaining blocks are `charge N% < target`, which is the full-charge doctrine working.
-- **Left alone deliberately** — exempting it would remove a gate that is doing its job.

SELECT left(reason, 120) AS reason, count(*) AS n
  FROM public.ottoq_rule_evaluations
 WHERE rule_code = 'SLA.004.required_services_complete' AND passed IS FALSE
 GROUP BY 1 ORDER BY 2 DESC;
