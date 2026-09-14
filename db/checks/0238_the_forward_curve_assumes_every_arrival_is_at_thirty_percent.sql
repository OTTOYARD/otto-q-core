-- 0238  THE FORWARD DEMAND CURVE ASSUMES EVERY ARRIVAL IS AT 30% SoC, 30 MINUTES OUT
--
-- READ-ONLY. No DDL, no DML. Measurement only.
--
-- ---------------------------------------------------------------------------
-- WHY THIS CHECK EXISTS
--
-- Chase, 2026-09-14: "we know exactly SoC and states of all vehicles and
-- assets... so we know realistically when a vehicle will need to return, and
-- their requirements from an energy, and services perspective. We should
-- theoretically identify and compute that through OTTO-Q so there isn't any
-- guessing."
--
-- That is a falsifiable claim about the engine. It is false today, and what
-- makes it false is not a missing subsystem -- it is two literal constants
-- sitting where two measured quantities belong. Both are one join away from
-- the real value, which the engine already tracks.
--
-- This is the same defect class this repo has now convicted eleven times
-- (0098, 0137/0216, 0145/0146, 0227, 0231, 0296, 0304, 0307, 0232, 0233,
-- 0235): AN INSTRUMENT THAT ANSWERS A SLIGHTLY DIFFERENT QUESTION THAN THE
-- ONE BEING ASKED. Here the forecast answers "how much energy would arrive if
-- every vehicle came back at 30% in half an hour", and is read as though it
-- answered "how much energy is actually coming, and when".
--
-- METHOD RULE (0235) OBSERVED THROUGHOUT: before measuring a value, read its
-- ASSIGNMENT. Every claim below cites the assigning line, not a function that
-- merely mentions the name. This check caught one of its own drafts doing the
-- opposite -- see the RETRACTED note in section D.
--
-- ===========================================================================
-- A. THE SoC AXIS IS THE LITERAL 30
--
--   public.ottoq_forecast_net_load, loop 2 (future arrivals), line 43:
--
--     v_kwh := GREATEST(0,(COALESCE(r.target_soc, public.ottoq_default_target_soc())
--                          - p_arrival_soc)/100.0 * COALESCE(r.battery_capacity_kwh,75));
--
--   p_arrival_soc is a PARAMETER. Its signature default:
--     p_arrival_soc numeric DEFAULT 30
--   Its ONLY caller, public.ottoq_bess_reserve_target, passes FIVE arguments:
--     v_load := ottoq_forecast_net_load(p_sim_run_id, p_depot_id, p_sim_clock,
--                                       p_horizon_ticks, p_tick_min);
--   -- so the sixth is never supplied and p_arrival_soc is ALWAYS 30.
--
--   Note loop 1 of the same function (currently-active charging sessions,
--   line 19) DOES read v.current_soc. The two loops of one forecast disagree
--   about whether the vehicle's state is knowable. Only loop 2 guesses.

\echo '== A. assumed arrival SoC (30) vs measured arrival SoC =='
SELECT count(*)                                                            AS sessions,
       round(avg(soc_start),1)                                             AS avg_actual_start_soc,
       round(percentile_cont(0.05) WITHIN GROUP (ORDER BY soc_start)::numeric,1) AS p05,
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY soc_start)::numeric,1) AS p50,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY soc_start)::numeric,1) AS p95,
       count(*) FILTER (WHERE soc_start <= 30)                             AS at_or_below_assumed_30,
       round(100.0*count(*) FILTER (WHERE soc_start <= 30)/count(*),2)     AS pct_at_or_below_30,
       round(avg(energy_delivered_kwh),2)                                  AS avg_actual_kwh_delivered
  FROM public.ocpp_sessions
 WHERE soc_start IS NOT NULL;

-- MEASURED 2026-09-14:
--   sessions 71,941 | avg 75.6 | p05 50.0 | p50 77.0 | p95 88.0
--   at or below the assumed 30%: 331 of 71,941 = 0.46%
--   avg actual energy delivered: 16.81 kWh
--
-- The assumption is wrong for 99.54% of sessions, and wrong in the direction
-- that inflates demand: implied need at an assumed 30% against a 90% target on
-- a 75 kWh pack is 45 kWh, against 16.81 kWh actually delivered (~2.7x over).

-- ===========================================================================
-- B. THE TIME AXIS IS THE LITERAL 30 TOO
--
--   ottoq_vehicle_dispatches.scheduled_return_at is what loop 2 reads as `eta`
--   (line 34). For a recalled vehicle it is written as now + return_eta_minutes.

\echo '== B. every ETA the engine has ever recorded =='
SELECT 'return_eta_minutes'   AS col, count(*) AS rows_nonnull,
       count(DISTINCT return_eta_minutes) AS distinct_vals,
       min(return_eta_minutes) AS lo, max(return_eta_minutes) AS hi
  FROM public.ottoq_vehicle_dispatches WHERE return_eta_minutes IS NOT NULL
UNION ALL
SELECT 'planned_duration_min', count(*), count(DISTINCT planned_duration_min),
       round(min(planned_duration_min),1), round(max(planned_duration_min),1)
  FROM public.ottoq_vehicle_dispatches WHERE planned_duration_min IS NOT NULL;

-- MEASURED 2026-09-14:
--   return_eta_minutes  : 123,665 rows, ONE distinct value, 30 .. 30
--   planned_duration_min: 129,507 rows, 2,321 distinct, 1.0 .. 1,249.6
--
-- So the twin models trip duration richly -- a calibrated draw spanning three
-- orders of magnitude -- and then DISCARDS it the moment a vehicle is
-- recalled. Every recalled vehicle is predicted to arrive in exactly half an
-- hour, whatever it is doing and wherever it is.
--
-- Consequence for the curve: it knows HOW MANY vehicles are coming, but places
-- them all at one instant needing one identical amount of energy. A forecast
-- whose time axis and whose magnitude axis are both constants carries exactly
-- one bit of real information -- the count.

-- ===========================================================================
-- C. SO THE OVERNIGHT PEAK CANNOT EMERGE -- IT HAS TO BE SHAPED
--
--   twin.ottoq_sim_auto_dispatch_tick line 121, inside a fixed clock window
--   (overnight_recall_start_hour 22 .. overnight_recall_end_hour 3):
--
--     v_to_recall := GREATEST(0, v_currently_deployed - v_desired_deployed - v_hyst);
--
--   That is a demand-curve subtraction. SoC does not appear in it. The
--   function's own comment says so: "Twin measures the surplus (a demand
--   fact)". Energy state enters only when ranking WHICH vehicles fill the
--   quota, never WHETHER or WHEN there is one.

\echo '== C. what actually triggers a return, with SoC at the decision =='
SELECT COALESCE(return_trigger,'(null)')                                   AS trigger,
       count(*)                                                            AS n,
       round(100.0*count(*)/sum(count(*)) OVER (),1)                       AS pct,
       count(return_evidence->>'soc_at_decision')                          AS n_with_evidence,
       round(avg((return_evidence->>'soc_at_decision')::numeric),1)        AS avg_soc_at_recall
  FROM public.ottoq_vehicle_dispatches
 WHERE returning_started_at IS NOT NULL
 GROUP BY 1 ORDER BY n DESC;

-- MEASURED 2026-09-14 (123,665 rows with returning_started_at):
--   surplus_to_demand   45,343  36.7%  SoC 78.5
--   prime_inbound       34,185  27.6%  NO EVIDENCE AT ALL -- run-boot fixture,
--                                      not a decision; do not quote it as one
--   wash_cadence        33,855  27.4%  SoC 87.4
--   low_soc_reserve      3,355   2.7%  SoC 42.1  (range 33.1 - 45.0)
--   overnight_prestage   3,280   2.7%  SoC 79.1
--   rider_flag_cleaning  1,370   1.1%  SoC 87.0
--   sensor_soil          1,062   0.9%  SoC 72.0
--   comms_stale            566   0.5%  SoC 83.2
--   service_interval_due   517   0.4%  SoC 74.8
--   timer_backstop          90   0.1%  SoC 92.2
--   critical_reserve        40   0.03% SoC 31.8  (range 24.5 - 34.7)
--   fault_major              2   0.00% SoC 59.8
--
-- ENERGY NEED DRIVES 2.7% OF RETURNS (low_soc_reserve + critical_reserve).
--
-- AND NOTE WHAT THIS DOES **NOT** SAY. The threshold machinery is CORRECT
-- where it fires: low_soc_reserve recalls in a tight 33-45% band and
-- critical_reserve in 24.5-34.7%. Those are clean, state-derived thresholds
-- doing exactly their job. The defect is not that the need path is broken --
-- it is that it almost never gets to decide, because two clocks decide first.
-- Do not "fix" the need path. Give it the seat.

-- ===========================================================================
-- D. WHAT IS **NOT** BROKEN, INCLUDING ONE CLAIM THIS CHECK RETRACTED
--
-- RETRACTED IN DRAFT, recorded because the near-miss is the point. An earlier
-- pass of this check read line 65 of ottoq_energy_orchestrate --
--
--   v_demand_target := COALESCE(ottoq_bess_reserve_target(...), v_demand_target);
--
-- -- called ottoq_bess_reserve_target directly, got 40.8 - 116.1 kW back on
-- 8 of 8 recent runs, and was about to report that the site charge cap
-- collapses to its 50 kW floor and that 0236 had measured a counterfactual
-- engine. THAT WAS WRONG, and reading the engine's own ledger instead of
-- re-deriving the formula is what caught it. ottoq_energy_commands records
-- demand_target CONSTANT for the whole of every run -- 1250 x48, 1250 x22,
-- 1250 x22, 1325 x12, 1325 x12, 318 x6 -- against desired_ev_kw of 175-280.
-- 0236's finding STANDS and is independently reconfirmed here: the cap is
-- 4-7x demand and binds 0.62% of ticks.
--
-- The surviving observation from that pass is smaller but real and is section
-- E's first item: demand_target never moves WITHIN a run while the forecast it
-- is meant to track swings.

\echo '== D. the cap is constant per run while its inputs are not =='
SELECT left(sim_run_id::text,8)                                            AS run,
       count(*)                                                            AS ticks,
       count(DISTINCT (reason->>'demand_target')::numeric)                 AS distinct_demand_target,
       max((reason->>'demand_target')::numeric)                            AS demand_target_kw,
       round(min((reason->>'forecast_charge_kw')::numeric),1)              AS forecast_lo,
       round(max((reason->>'forecast_charge_kw')::numeric),1)              AS forecast_hi,
       round(avg((reason->>'desired_ev_kw')::numeric),1)                   AS avg_desired_ev_kw
  FROM public.ottoq_energy_commands
 WHERE reason ? 'demand_target'
   AND sim_run_id IN (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 6)
 GROUP BY 1 ORDER BY ticks DESC;

-- ===========================================================================
-- E. THE FIX IS AVAILABLE AND SMALL. THE COST IS RECERT, NOT ENGINEERING.
--
-- The state the forecast needs is already tracked. Measured 2026-09-14 on
-- vehicles currently out:
--   status 'active'   : 81 rows, current_soc 56-100, 24 distinct values
--   status 'returning': 19 rows, current_soc 64-100, 11 distinct values
-- The twin updates SoC continuously while a vehicle is deployed. The forecast
-- simply does not read it -- and loop 2 already joins `vehicles v`, so the
-- column is in scope at the line that guesses.

\echo '== E. the state the forecast declines to read =='
SELECT d.status,
       count(*)                         AS deployed,
       count(DISTINCT v.current_soc)    AS distinct_live_soc,
       round(min(v.current_soc),1)      AS min_live_soc,
       round(max(v.current_soc),1)      AS max_live_soc
  FROM public.ottoq_vehicle_dispatches d
  JOIN public.vehicles v ON v.id = d.vehicle_id
 WHERE d.status IN ('active','returning')
 GROUP BY 1 ORDER BY deployed DESC;

-- PROPOSED, smallest first, each measured before the next:
--   (a) ottoq_forecast_net_load loop 2: use v.current_soc for each dispatch
--       instead of p_arrival_soc; keep p_arrival_soc as the fallback when
--       current_soc IS NULL. One expression. The join already exists.
--   (b) return_eta_minutes: derive from the remaining trip instead of the
--       policy constant 30.
--
-- BOTH FORCE RECERT OF EVERY COLUMN. The call chain is
--   ottoq_forecast_net_load <- ottoq_bess_reserve_target
--                           <- ottoq_energy_orchestrate
--                           <- ottoq_sim_advance_tick_world
-- which is inside the certified twin tick path, and h_nrg hashes the energy
-- command stream, so the arms' energy hashes move by construction. Ship (a)
-- alone, recert, measure the delta, and only then consider (b) -- (b) changes
-- arrival TIMES and so moves the booking calendar as well, which is a much
-- wider blast radius than (a)'s single scalar.
--
-- APPLY WINDOW at the time of writing: clean. pg_stat_activity showed 0 active
-- ottoq queries and no cert cron armed at 2026-09-14 15:55 UTC; only
-- ottoq-demo-metronome is scheduled. pg_stat_activity is the ONLY authority
-- here -- ottoq_sim_runs.status is MVCC-invisible to an uncommitted pair.
