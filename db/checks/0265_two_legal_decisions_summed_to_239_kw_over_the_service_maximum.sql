-- 0265  TWO INDEPENDENTLY LEGAL DECISIONS SUMMED TO 239 kW OVER THE DEPOT'S
--       DECLARED SERVICE MAXIMUM, AND NO RULE ASSERTS THE SUM.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed 777777, speed 8.0).
--
-- ══ 1. THE ARITHMETIC, WHICH CLOSES EXACTLY ═════════════════════════════════
--
-- The depot declares `dcfc_max_concurrent_kw = 1800` and `service_max_kw = 2500`
-- (`demand_charge_threshold_kw` is NULL). At the snapshot of highest grid import on
-- this run:
--
--   EV charging                     1,691.8 kW    (under the 1,800 nameplate)
--   BESS output                      -968.0 kW    (NEGATIVE — it was CHARGING)
--   solar generation                     0.0 kW
--   building + lighting load            79.0 kW
--   ───────────────────────────────────────────
--   grid import                     2,738.8 kW    **= 1691.8 + 968.0 + 79.0, exactly**
--   declared service_max_kw         2,500.0 kW
--   **overshoot                       238.8 kW    (9.6%)**
--
-- **AND IT HAPPENED EIGHT MINUTES INTO THE RUN.** The peak snapshot is at sim
-- 06:56:09 against a `sim_clock_start` of 06:48 — the cold-start surge, with the
-- arrival wave charging and the BESS filling at the same time. That makes it more
-- explicable and more real, not less: a physical site is at its most exposed exactly
-- when everything starts at once, and the second and third highest imports (1,713.8
-- and 1,675.2 kW, both within seconds of it) carry `bess_output_kw = 0` — so the BESS
-- draw is what took this one over, not the charging wave alone.
--
-- Over the whole run: **1 of 1,139 snapshots** above `service_max_kw`, 0 above the
-- 1,800 kW charging nameplate, and the BESS reached **-989.4 kW** of charge draw at
-- its deepest. So neither decision was illegal on its own terms — charging stayed
-- under its cap and the battery stayed inside its own envelope — **and their sum was
-- not checked by anything.**
--
-- ══ 2. WHY NOTHING CAUGHT IT: THE ENERGY SHIELD HAS NO SITE-SUM RULE ════════
--
-- Rule evaluations on this run, by probe point:
--
--   task_start             85,254 evals, 120 failed
--   stall_assignment        1,075 evals,   0 failed
--   redeployment              996 evals,  84 failed
--   charge_session_start      770 evals,   8 failed
--   policy_write              305 evals,   0 failed
--   **bess_dispatch            225 evals,   0 failed**
--
-- And `bess_dispatch` evaluates exactly **one** rule: `EN.003.bess_limits` (234
-- evals, 0 failures), which checks the battery's own envelope. `EN.001.grid_capacity_ceiling`
-- (safety_critical) caps *aggregate active charging power* and runs at
-- `stall_assignment` and `charge_session_start`. **Neither asserts
-- `charging + BESS_charging + base_load <= service_max_kw`.** The shield gates each
-- consumer against its own limit and never against the shared one.
--
-- **THIS IS 2.3's "SHARED SITE POWER CAP", AND IT IS THE CUMULATIVE-RESOURCE
-- CONSTRAINT.** CLAUDE.md 2.3 names it as one of the four load-bearing constructs of
-- the domain model; 2.5, citing `docs/research/answers/R-12`, records that **cuOpt
-- cannot express a cumulative resource at all** and that this is one of the four
-- reasons the CP-SAT decomposition is *forced rather than chosen*. So this snapshot
-- is not just a defect — **it is the first measured instance on the twin depot of the
-- exact constraint class the solver argument rests on.** It is also the sharpest
-- available answer to "what does the always-on CP-SAT host actually buy": a
-- site-power cumulative constraint that the current shield structurally cannot hold,
-- because a per-consumer rule cannot see a sum.
--
-- NOT FIXED HERE, deliberately. A site-sum rule changes what the BESS is allowed to
-- do, which means it changes `ottoq-energy-mpc`'s setpoints and the `energy_mpc_follow`
-- path. That is an energy-policy decision and it belongs to Chase. The cheap
-- interim, if he wants one, is a MEASURED-only rule at `bess_dispatch` that logs the
-- projected sum without blocking — 2.9a's blind-spot promotion doctrine, the same
-- shape 0370 used.

SELECT round(d.dcfc_max_concurrent_kw, 1)  AS charging_nameplate_kw,
       round(d.service_max_kw, 1)          AS service_max_kw,
       d.demand_charge_threshold_kw,
       (SELECT count(*) FROM public.site_energy_snapshots s
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE r.depot_id = d.id)                                       AS snapshots,
       (SELECT count(*) FROM public.site_energy_snapshots s
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE r.depot_id = d.id AND s.grid_import_kw > d.service_max_kw) AS over_service_max,
       (SELECT count(*) FROM public.site_energy_snapshots s
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE r.depot_id = d.id
           AND s.total_ev_charging_kw > d.dcfc_max_concurrent_kw)         AS over_charging_nameplate,
       (SELECT round(max(s.grid_import_kw),1) FROM public.site_energy_snapshots s
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE r.depot_id = d.id)                                        AS max_grid_import_kw,
       (SELECT round(min(s.bess_output_kw),1) FROM public.site_energy_snapshots s
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE r.depot_id = d.id)                                        AS deepest_bess_charge_kw
  FROM public.depots d
 WHERE d.id = '11111111-1111-1111-1111-111111111111';

-- The decomposition at the peak, so the sum can be checked rather than believed:
SELECT s."timestamp"::text                                AS at_sim_clock,
       round(s.total_ev_charging_kw, 1)                    AS ev_charging_kw,
       round(s.bess_output_kw, 1)                          AS bess_kw_negative_is_charging,
       round(s.solar_generation_kw, 1)                     AS solar_kw,
       round(s.building_load_kw + s.lighting_load_kw, 1)   AS other_load_kw,
       round(s.grid_import_kw, 1)                          AS grid_import_kw,
       round(s.total_ev_charging_kw - s.bess_output_kw
             - s.solar_generation_kw
             + s.building_load_kw + s.lighting_load_kw, 1) AS reconstructed_import_kw,
       round(s.grid_import_kw - 2500, 1)                   AS over_service_max_kw
  FROM public.site_energy_snapshots s
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY s.grid_import_kw DESC
 LIMIT 3;

-- ══ 3. AND A NAMING HAZARD FOUND WHILE CHECKING THE KPI WAS NOT WRONG ═══════
--
-- The chase started from an apparent contradiction: KPI 3 `peak_site_kw` reported
-- **1,529.2** while `max(grid_import_kw)` was **2,738.8**. A 44% gap in a number
-- CLAUDE.md 2.9 describes as *"15-min rolling, matches demand billing"* would be
-- serious. **The KPI is right.** `ottoq_kpi_peak_site_kw` computes
-- `max()` of a 15-minute rolling **AVERAGE** of `grid_import_kw`, which is the shape
-- utilities actually bill on, and 1,529.2 is that number.
--
-- What is wrong is the column that looks like it holds the same thing:
-- **`site_energy_snapshots.peak_demand_kw_15min` is not a 15-minute quantity.**
-- Measured over 1,139 snapshots: it is `>= grid_import_kw` in **1,139 of 1,139**,
-- equal in 54, **never less**, and its maximum equals the all-time instantaneous
-- maximum import exactly. It is a RUNNING PEAK of instantaneous import. Anyone
-- reading it for demand billing overstates by **79%** (2,738.8 against 1,529.2).
--
-- G75's family again, and the third instance tonight after `released_at`/`booked_at`
-- and `stranded_recharges`: a name that describes a quantity the column does not
-- hold. The KPI correctly ignores it and derives its own rolling average, so nothing
-- ships wrong today — it is a landmine for the next person to reach for the
-- conveniently-named column.

SELECT count(*)                                                        AS snapshots,
       count(*) FILTER (WHERE s.peak_demand_kw_15min = s.grid_import_kw) AS equal_to_instantaneous,
       count(*) FILTER (WHERE s.peak_demand_kw_15min > s.grid_import_kw) AS greater_than,
       count(*) FILTER (WHERE s.peak_demand_kw_15min < s.grid_import_kw) AS less_than,
       round(max(s.peak_demand_kw_15min), 1)                            AS max_of_the_column,
       round(max(s.grid_import_kw), 1)                                  AS max_instantaneous_import,
       (SELECT round(k.peak_site_kw_15min, 1) FROM public.ottoq_kpi_peak_site_kw k
         WHERE k.sim_run_id = s.sim_run_id)                             AS kpi_15min_rolling_mean
  FROM public.site_energy_snapshots s
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY s.sim_run_id;
