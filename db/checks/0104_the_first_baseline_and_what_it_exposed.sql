-- =====================================================================
-- 0104  The first baseline, and what it exposed
-- =====================================================================
-- 0191 built the baseline OTTO-Q had never been measured against. This is
-- the first result. It is not the result anyone was hoping for, and it is
-- more useful than the one they were.
--
-- *** CORRECTION (2026-09-04, same day, see db/checks/0105) *** The two
-- p95 wait columns below are WITHDRAWN, not adjusted. Both arms were fed
-- l.planned_start_sim as the readiness time; that column is a plan the
-- engine authored and habitually beats (mean deviation -66 to -113 min),
-- so the OTTO-Q column measured plan adherence rather than waiting, and
-- the FIFO column was forced to 0.0 arithmetically -- with idle stalls,
-- GREATEST(ready_at, free_at) returns ready_at and no other value was
-- reachable. The two columns never measured the same quantity. Measured
-- honestly (arrival -> first service start, KPI 5's own definition) the
-- run's p95 is 240 min, not 60. The TURNS columns are unaffected and
-- stand. Section 4's open question is closed by 0105: ~30 min of the
-- delay is the decision clock and the rest is a cold-start burst
-- draining -- it was never contention. Section 5's premise is
-- strengthened, not weakened: 0105 shows busy_day is a 90-minute mass
-- arrival followed by ~20 hours of an empty depot.
--
-- SECTION 1 — OTTO-Q vs FIFO, eight runs, same demand
-- ---------------------------------------------------------------------
--   demand   stalls   OTTO-Q turns   FIFO turns   OTTO-Q p95   FIFO p95
--     260      108        259           243         7.1 min     0.0 min
--     240      112        240           221        60.0 min     0.0 min
--                                    (x6 more at the same figures)
--
-- OTTO-Q completes essentially 100% of the demand. FIFO drops 6-8%.
-- That is a real, consistent throughput win: roughly +7% on completed
-- turns, on identical demand, with identical stalls and identical
-- observed service times.
--
-- OTTO-Q's p95 wait is WORSE -- up to 60 minutes against FIFO's zero.
-- Do not explain that away. It is the honest half of the result.
--
-- SECTION 2 — BUT THE TEST IS NOT A TEST YET
-- ---------------------------------------------------------------------
-- Aggregate stall utilisation on the busiest recorded run:
--
--   busy stall-minutes   1,838
--   stalls                 111
--   window                 720 min
--   UTILISATION            2.3%
--
-- The aggregate is misleading in our favour AND against us, so break it
-- down by the resource that actually constrains anything:
--
--   stall_type      stalls   jobs   utilisation
--   wash_bay            3     31       20.3%
--   service_bay         2      7       14.9%
--   dcfc               10     28        4.4%
--   l2                 30     74        2.6%
--   staging            66     92        0.7%
--
-- Two things follow.
--
-- First, the 2.3% headline is an artifact: 66 of the 111 "stalls" are
-- STAGING -- parking spaces, essentially free. Putting them in the
-- denominator hides where the load actually sits. The real bottlenecks
-- are the wash bay (3) and the service bay (2).
--
-- Second, and this is the finding:
--
--   THE TIGHTEST RESOURCE IN THE BUSIEST RECORDED RUN PEAKS AT 20%.
--   WE HAVE NEVER RUN THIS PRODUCT UNDER LOAD.
--
-- Scheduling is the allocation of SCARCE resources. Nothing here has ever
-- been scarce. Thirteen determinism rounds, 762 archived runs, five
-- corrected KPIs -- all of it measured a depot that was 80% idle at its
-- worst pinch point.
--
-- SECTION 3 — WHAT THAT DOES AND DOES NOT INVALIDATE
-- ---------------------------------------------------------------------
-- STILL GOOD. Determinism is a property of the engine, not of the load;
-- round 13's 24-of-24 stands. The KPI corrections (0182-0190) are
-- definitional and stand. cuOpt's retirement (D001) rests on latency and
-- solver shape, not on load, and stands.
--
-- NOT YET EARNED. Any claim that OTTO-Q schedules WELL. The +7% is real
-- but it was won against a naive baseline on an easy day. The value of
-- optimisation appears under contention, and we have no contended
-- measurement at all. A 20%-utilised wash bay cannot demonstrate
-- scheduling skill, and neither can it expose scheduling failure.
--
-- SECTION 4 — THE 60-MINUTE WAIT IS NOT CONTENTION
-- ---------------------------------------------------------------------
-- At these utilisations, queueing cannot explain a 60-minute p95 wait.
-- Something is DEFERRING work while capacity sits idle -- cadence rules,
-- overnight staging windows, service sequencing, or a power gate. That
-- may be entirely correct behaviour (batching into a tariff window is a
-- reason to wait) or it may be the engine idling assets.
--
-- Not diagnosed here, and deliberately not guessed at. It is the first
-- question the contended scenario should answer, because under load the
-- same behaviour will either pay for itself or become the bottleneck.
--
-- SECTION 5 — WHAT IS NEEDED NEXT
-- ---------------------------------------------------------------------
-- A contended scenario. CLAUDE.md C8 already specifies one in detail --
-- Site Alpha: 3,000 kW cap, three tenants (18 robotaxis overnight-heavy,
-- 6 yard tractors on daytime waves, 24 AMRs opportunity-charging), 10
-- DCFC, 8 L2, 2 wash, 1 calibration, 6 AMR pads, 1 swap dock. That
-- inventory against that fleet produces real contention at the wash bay
-- and the power cap, which is exactly where scheduling either earns its
-- keep or does not.
--
-- Then re-run this baseline against it. The comparison only becomes
-- evidence at that point.
--
-- SECTION 6 — THE METHOD, AND ITS LIMITS
-- ---------------------------------------------------------------------
-- The baseline is a counterfactual replay, not a closed-loop FIFO world.
-- It gets the same stall inventory, the same observed service durations
-- and the same readiness times, and differs only by taking work in
-- ready-time order into the earliest-free compatible stall. It does not
-- model how a FIFO depot's different early choices would have changed
-- later demand. Stall-free legs are excluded from both sides.
--
-- It is deliberately generous to the baseline. If OTTO-Q could not beat
-- a naive ordering given identical everything else, that would be worth
-- knowing, and this is built to be able to report it.
-- =====================================================================

-- §1 — the comparison, across the busiest runs
WITH runs AS (
  SELECT r.sim_run_id,
         (SELECT count(*) FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id=r.sim_run_id AND l.status='done' AND l.to_stall_id IS NOT NULL
             AND l.leg_type <> ALL (ARRAY['taxi','stage','depart'])) AS demand
    FROM public.ottoq_sim_runs r WHERE r.sim_clock_current IS NOT NULL
   ORDER BY demand DESC NULLS LAST LIMIT 8
), scored AS (SELECT sim_run_id, demand, public.ottoq_baseline_fifo(sim_run_id) AS j FROM runs)
SELECT demand,
       (j#>>'{stalls_available}')::int              AS stalls,
       (j#>>'{actual_otto_q,turns_completed}')::int AS ottoq_turns,
       (j#>>'{baseline_fifo,turns_completed}')::int AS fifo_turns,
       (j#>>'{actual_otto_q,p95_wait_min}')::numeric AS ottoq_p95,
       (j#>>'{baseline_fifo,p95_wait_min}')::numeric AS fifo_p95
  FROM scored WHERE (j->>'ok')::boolean ORDER BY demand DESC;

-- §2 — utilisation by the resource that actually constrains. The
-- aggregate over all stall types is misleading: staging dominates the
-- count and carries almost no load.
WITH r AS (SELECT sim_run_id, EXTRACT(epoch FROM sim_clock_current - sim_clock_start)/60.0 AS win
             FROM public.ottoq_sim_runs WHERE sim_run_id='85034701-a556-4853-b148-b8d40c35b490'),
inv AS (SELECT s.stall_type, count(DISTINCT s.id) AS stalls FROM public.stalls s
         WHERE s.id IN (SELECT DISTINCT to_stall_id FROM public.ottoq_itinerary_legs
                         WHERE sim_run_id=(SELECT sim_run_id FROM r) AND to_stall_id IS NOT NULL)
         GROUP BY 1)
SELECT s.stall_type, inv.stalls, count(*) AS jobs_done,
       round(sum(EXTRACT(epoch FROM l.actual_end_sim - l.actual_start_sim)/60.0)::numeric,0) AS busy_min,
       round((100.0*sum(EXTRACT(epoch FROM l.actual_end_sim - l.actual_start_sim)/60.0)
              /(inv.stalls * (SELECT win FROM r)))::numeric,1) AS utilisation_pct
  FROM public.ottoq_itinerary_legs l
  JOIN public.stalls s ON s.id = l.to_stall_id
  JOIN inv ON inv.stall_type = s.stall_type
 WHERE l.sim_run_id=(SELECT sim_run_id FROM r) AND l.status='done'
   AND l.leg_type <> ALL (ARRAY['taxi','stage','depart'])
 GROUP BY s.stall_type, inv.stalls ORDER BY utilisation_pct DESC;
