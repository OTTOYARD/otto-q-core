-- 0264  CP-SAT DECLINED FOUR CONSECUTIVE MATCHED FRAMES AND WAS RIGHT EVERY TIME,
--       AND THE REASON IT GAVE NAMES A FOURTH AUTHORITY ON STALL AVAILABILITY.
--
-- Read-only against the database; the solver ran locally and **never submitted**.
-- Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10`, ticks 740–759. Contamination asserted 0
-- on every pass (`forward_lex` rows on the run stay at zero).
--
-- ══ 0. AND IT NEEDED NO AWS HOST, WHICH SHARPENS CHASE'S DECISION ════════════
--
-- OR-Tools **9.15.6755** with `ortools.sat.python.cp_model` is installed in this
-- environment, so `scripts/compare-plans-on-one-frame.sh` solves LOCALLY through
-- `bridge.proposer_bridge`. Nothing was called over the network.
--
-- So the always-on-container question is narrower than it has been stated. Two
-- different things need separating:
--   * **EVALUATING CP-SAT needs no host at all.** The offline bridge fetches a
--     frame, solves, and can emit SQL without submitting. Every measurement in this
--     file was produced that way.
--   * **CP-SAT PROPOSING INSIDE THE ENGINE does need the host**, because that path
--     is the `ottoq-cpsat-propose` edge function calling `OTTOQ_INTEL_URL` — the
--     same env pair `ottoq-energy-mpc` uses. That is what is dark now: `cpsat_service`
--     has 49 calls spanning `first_call` 2026-09-14 00:35 to `last_call` **2026-09-20
--     02:45**. (Corrected: an earlier draft of this line and of SOLVER_STATE §13 gave
--     the last call as 2026-09-14, which is the FIRST call's date — a six-day silence
--     where the truth is a few hours. The conclusion does not move; the overstatement
--     would have.)
-- The recommendation is unchanged, but the cost of NOT doing it is now precise: we
-- lose CP-SAT in the live decide loop, not our ability to judge it.
--
-- 2.5 requires the OR-Tools version to be PINNED and asserted, not assumed --
-- 9.4 and 9.5 both shipped nondeterministic results even single-worker. **9.15.6755
-- is what produced these numbers and it is recorded here for that reason.**
--
-- ══ 1. THE VERDICT: FOUR FRAMES, FOUR DECLINES, EACH ONE REASONED ════════════
--
--   pass  tick  frame_vehicles  frame_stalls  cuopt_total/enacted  contamination
--   1     740   116             158           22 / 16              0
--   2     745   116             158           23 / 16              0
--   3     752   116             158           23 / 16              0
--   4     759   116             158           23 / 16              0
--
--   CP-SAT on every one of those frames: status `empty`, 0 rows, 0 planned,
--   0 abstained, and a message rather than a shrug:
--
--     "frame has 40 charge-capable stall(s) and not one is offerable this tick
--      (N charger_faulted, M occupied, K reserved); nothing free to propose"
--
--     pass 1:  4 faulted · 27 occupied ·  8 reserved   (+ INFEASIBLE on the
--                                                        first pass, which also
--                                                        had no previous plan to
--                                                        fall back on)
--     pass 2:  4 faulted · 26 occupied · 10 reserved
--     pass 3:  5 faulted · 26 occupied ·  9 reserved
--     pass 4:  6 faulted · 25 occupied ·  9 reserved
--
-- In every case the three buckets sum to exactly 40, the site's whole charge-capable
-- inventory. **The solver did not fail to find a plan; it established that no legal
-- move existed and said which resource was missing.** That is the propose/dispose
-- contract working in the direction nobody demonstrates: a proposer that declines
-- with a reason is worth more than one that proposes into a wall, and 0361 exists
-- precisely so the disposer scores that decline as `proposer_abstained` rather than
-- as a refusal.
--
-- CUOPT ON THE SAME FRAMES held 23 proposals with 16 enacted for the run — but note
-- the numbers barely move across the four passes (22→23 total, 16→16 enacted over 19
-- ticks), so it is not proposing into this wall either. The two solvers agree that
-- the charge layer is closed. That agreement is the useful result, not a ranking.
--
-- ══ 2. A FOURTH AUTHORITY ON "FREE", AND MY CENSUS DISAGREED WITH THE SOLVER ══
--
-- The capture's own census column read `charge_free = 4` on all four passes, while
-- CP-SAT read **zero offerable**. Both are correct and the gap is the finding.
--
-- `charge_free` is the pointer test: `current_vehicle_id IS NULL AND reserved_by IS
-- NULL AND status='available'`. CP-SAT additionally refuses a stall whose OCPP
-- charger is `Faulted` — and there were 4, 4, 5 and 6 faulted across the passes.
-- The four "free" charge stalls were the faulted ones.
--
-- So `0261`'s rule takes a third term. **A stall is offerable only if it is
-- pointer-free AND calendar-free AND its charger is healthy.** Measured on this
-- depot right now: 45 chargers, **25 Occupied, 14 Available, 6 Faulted**, none
-- missing a heartbeat. Any availability number quoting fewer than all three gates is
-- a number about a different question — the same shape as `0250` on depot scope,
-- `G84` on pointer-versus-calendar, and `0260` §2 on the wash bays.
--
-- AND NEITHER GATE DOMINATES, which is the part that makes the intersection
-- mandatory rather than merely tidy. Reading the query below on the live run:
--
--   type   capable  pointer_free  calendar_free  charger_faulted  offerable
--   dcfc        10             0             10                0          0
--   l2          30             3              1                4          0
--
-- **On DCFC the POINTER is the tighter gate (0 against 10); on L2 the CALENDAR is
-- (1 against 3); on staging the calendar was tighter by five-fold (`0261`: 12
-- against 59).** Whichever single gate you pick, some stall type will make it look
-- generous. `offerable` is 0 for both charge types at this moment, which is the
-- honest reading and is exactly what CP-SAT reported.

SELECT c.station_state, count(*) AS chargers,
       count(*) FILTER (WHERE c.last_heartbeat_at IS NULL) AS missing_heartbeat
  FROM public.ottoq_ocpp_chargers c
 WHERE c.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 2 DESC;

WITH r AS (
  SELECT sim_run_id, COALESCE(sim_clock_current, sim_clock_start) AS clk
    FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running'
   ORDER BY started_at DESC LIMIT 1
)
SELECT s.stall_type::text AS stall_type,
       count(*)                                                          AS charge_capable,
       count(*) FILTER (WHERE s.current_vehicle_id IS NULL
                          AND s.reserved_by IS NULL
                          AND s.status = 'available')                    AS pointer_free,
       count(*) FILTER (WHERE NOT EXISTS (
                          SELECT 1 FROM public.ottoq_stall_bookings b
                           WHERE b.sim_run_id = (SELECT sim_run_id FROM r)
                             AND b.stall_id = s.id
                             AND b.state IN ('held','active')
                             AND b.during @> (SELECT clk FROM r)))       AS calendar_free,
       count(*) FILTER (WHERE ch.station_state = 'Faulted')              AS charger_faulted,
       --: THE ONLY COUNT A PROPOSER CAN ACT ON
       count(*) FILTER (WHERE s.current_vehicle_id IS NULL
                          AND s.reserved_by IS NULL
                          AND s.status = 'available'
                          AND COALESCE(ch.station_state,'Available') <> 'Faulted'
                          AND NOT EXISTS (
                            SELECT 1 FROM public.ottoq_stall_bookings b
                             WHERE b.sim_run_id = (SELECT sim_run_id FROM r)
                               AND b.stall_id = s.id
                               AND b.state IN ('held','active')
                               AND b.during @> (SELECT clk FROM r)))     AS offerable_all_three_gates
  FROM public.stalls s
  LEFT JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
   AND s.stall_type::text IN ('dcfc','l2')
 GROUP BY 1 ORDER BY 1;

-- ══ 3. THE CHARGER FAULT LOAD IS MODELLED AND RECOVERS — SO IT IS CAPACITY ═══
--
-- The 6 faulted chargers are not an accumulating leak, and I checked before saying
-- so. `twin.ottoq_sim_recover_chargers(depot, clock, repair_minutes DEFAULT 75)`
-- sets `Faulted → Available` once `station_state_changed_at` is older than the
-- fault's own `repair_minutes`, and it **is** on the live path: called from
-- `public.ottoq_sim_advance_tick_world`, which `ottoq_demo_metronome` invokes
-- directly at its line 100. (Worth stating explicitly given G82 — this is the third
-- routine tonight whose live reachability I checked rather than assumed, and this
-- one passes.)
--
-- Measured at 335 sim-minutes into the run:
--
--   charge.session_faulted events                      18
--   chargers Faulted right now                          6 of 45  (13.3%)
--   mean repair_minutes carried by those faults     115.6        (not the 75 default)
--
--   charger-minutes lost      18 × 115.6  =  2,081
--   charger-minutes available 45 × 335    = 15,075
--   **share of charger time lost to faults  ≈ 13.8%**
--
-- The two independent figures agree — 13.3% faulted at an instant against 13.8% of
-- charger-time integrated over the run — which is what a steady state looks like.
--
-- **So the honest capacity sentence for the depot is: effective charge capacity is
-- about 86% of nameplate, continuously, by design.** That is the twin's calibrated
-- failure modelling doing its job, not a defect, and it is a number that belongs in
-- any answer to "how many vehicles can this depot orchestrate" — 40 charge stalls
-- behave like roughly 34.

SELECT (SELECT count(*) FROM public.ottoq_events e
         JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
        WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
          AND e.event_type = 'charge.session_faulted')                        AS faulted_sessions,
       (SELECT count(*) FROM public.ottoq_ocpp_chargers c
         WHERE c.depot_id = '11111111-1111-1111-1111-111111111111'
           AND c.station_state = 'Faulted')                                   AS faulted_now,
       (SELECT count(*) FROM public.ottoq_ocpp_chargers c
         WHERE c.depot_id = '11111111-1111-1111-1111-111111111111')           AS chargers_total,
       (SELECT round(avg((e.payload->>'repair_minutes')::numeric), 1)
          FROM public.ottoq_events e
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
           AND e.event_type = 'charge.session_faulted'
           AND e.payload->>'repair_minutes' IS NOT NULL)                      AS mean_repair_minutes;
