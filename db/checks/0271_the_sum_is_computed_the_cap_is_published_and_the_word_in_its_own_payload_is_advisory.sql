-- 0271  G89 WAS DIAGNOSED WRONG, AND BY ME. THE SUM *IS* COMPUTED. A CORRECT CAP
--       *IS* PUBLISHED. THE WORD IN ITS OWN PAYLOAD IS `advisory`.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10`. **This supersedes G89's mechanism and
-- narrows `0374`'s framing** -- the instrument `0374` built is still right and still
-- needed; the sentence it was built on was not.
--
-- ══ 0. WHAT I SET OUT TO BUILD, AND WHY I DID NOT ═══════════════════════════
--
-- G89's own row recommends *"a MEASURED-only rule at `bess_dispatch` logging the
-- projected sum without blocking"*, and `0374`'s FINDINGS entry concedes that a meter
-- is not a projection. So the next build was going to be that projection.
--
-- **It already exists.** `ottoq_energy_orchestrate` computes the projection every
-- tick, subtracts the battery's own draw, and publishes the result. Rule 5 -- check
-- whether a thing exists before building it -- is what stopped a duplicate, and what
-- it turned up instead is a better finding than the one it was checking.
--
-- ══ 1. THE CHAIN THAT ACTUALLY EXISTS ═══════════════════════════════════════
--
-- `public.ottoq_energy_orchestrate(sim_run, depot, clock, tick)`, per tick:
--
--   v_demand_target := v_service_max * factor            -- 2,500 x 0.9 = 2,250
--   IF policy energy_reserve_shave >= 0.5 THEN
--     v_demand_target := COALESCE(ottoq_bess_reserve_target(...), v_demand_target)
--   v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch)
--
-- **The third line is exactly the sum G89 says nothing computes.** `v_bess_dispatch`
-- is negative when the battery charges, so a charging battery *reduces* the EV charge
-- cap, kW for kW. The model is sound and it is the cumulative-resource reasoning the
-- finding claimed was absent.
--
-- It publishes both terms into `ottoq_energy_commands` as `charge_cap_kw` and
-- `bess_setpoint_kw`. Two minutes before the excursion, at 06:54:07:
--
--   charge_cap_kw     **795.0**   reason: demand_target 1325, base_load 0, solar 0
--   bess_setpoint_kw  **-530.0**  reason: mode charge_offpeak_reserve, soc_pct 13.81
--
-- A 795 kW cap on EV charging, correctly reduced for a 530 kW battery draw. **Then EV
-- charging ran at 1,691.8 kW.**

SELECT c.command_type, c.setpoint_kw, c.issued_at,
       c.reason->>'advisory'       AS advisory,
       c.reason->>'demand_target'  AS demand_target,
       c.reason->>'soc_pct'        AS soc_pct,
       c.reason->>'mode'           AS mode
  FROM public.ottoq_energy_commands c
 WHERE c.sim_run_id = '5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'
   AND c.depot_id   = '11111111-1111-1111-1111-111111111111'
   AND c.issued_at BETWEEN '2026-09-19 06:54:00+00' AND '2026-09-19 06:57:00+00'
 ORDER BY c.issued_at, c.command_type;

-- ══ 2. DEFECT ONE: THE CAP SAYS `advisory` IN ITS OWN PAYLOAD ═══════════════
--
-- Every `charge_cap_kw` command carries `"advisory": true` in its reason. Not some:
--
--   caps published                    **1,260**
--   marked advisory                   **1,260**
--   not advisory                          **0**
--
-- So the site publishes a power budget 1,260 times per run and binds itself to it
-- zero times. Measured against what actually flowed, the cap is *mostly* respected
-- anyway -- **26 of 1,260 snapshots (2.1%) drew more EV load than the cap in force,
-- worst overshoot 205.0 kW, mean overshoot when over 67.7 kW** -- which is the reading
-- that makes this a real finding rather than a catastrophe: the decide path broadly
-- follows an advisory budget, and in the 2% tail nothing holds it.
--
-- **This is the honest correction to G89 and it cuts in our favour on design and
-- against us on enforcement.** The architecture is right -- 2.5's power publication
-- boundary says OTTO-Q publishes forward schedules rather than commanding devices, and
-- an advisory `charge_cap_kw` is exactly that shape. What is missing is the *inside*
-- half: publishing a budget to the outside world is a boundary decision, but the
-- engine's own decide path treating its own budget as advisory is not a boundary, it
-- is an unenforced constraint.

WITH c AS (
  SELECT (reason->>'advisory')::boolean AS advisory, setpoint_kw
    FROM public.ottoq_energy_commands
   WHERE sim_run_id = '5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'
     AND command_type = 'charge_cap_kw'
)
SELECT count(*)                                   AS caps_published,
       count(*) FILTER (WHERE advisory)           AS marked_advisory,
       count(*) FILTER (WHERE advisory IS NOT TRUE) AS binding,
       round(min(setpoint_kw),1) AS min_cap, round(max(setpoint_kw),1) AS max_cap
  FROM c;

WITH s AS (
  SELECT timestamp, total_ev_charging_kw AS ev
    FROM public.site_energy_snapshots
   WHERE sim_run_id = '5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'
     AND depot_id   = '11111111-1111-1111-1111-111111111111'
), paired AS (
  SELECT s.ev,
         (SELECT c.setpoint_kw FROM public.ottoq_energy_commands c
           WHERE c.sim_run_id = '5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'
             AND c.command_type = 'charge_cap_kw'
             AND c.issued_at <= s.timestamp
           ORDER BY c.issued_at DESC LIMIT 1) AS cap
    FROM s
)
SELECT count(*)                                        AS snaps,
       count(*) FILTER (WHERE ev > cap)                AS ev_over_published_cap,
       round(100.0*count(*) FILTER (WHERE ev > cap)/NULLIF(count(*),0),1) AS pct_over,
       round(max(ev - cap),1)                          AS worst_overshoot_kw,
       round(avg(ev - cap) FILTER (WHERE ev > cap),1)  AS mean_overshoot_when_over
  FROM paired WHERE cap IS NOT NULL;

-- ══ 3. DEFECT TWO, AND THIS IS THE ONE THAT CAUSED THE EXCURSION ════════════
--
-- At the excursion instant the published cap was **not** 795. It was **1,762.0**, and
-- its `demand_target` read **2,802** -- against a service contract of **2,500**. The
-- target derived from the contract had become larger than the contract.
--
--   06:55:14   cap 1,569.8   demand_target 2,616
--   06:55:40   cap 1,800.6   demand_target 2,871
--   **06:56:09   cap 1,762.0   demand_target 2,802**   <- the excursion tick
--   06:56:30   cap 2,804.4   demand_target 2,883
--
-- **The cause is the unclamped override**, and the function it calls is not at fault.
-- `ottoq_bess_reserve_target` binary-searches for the lowest grid-import ceiling the
-- battery can hold across the forecast horizon given its available energy: `lo` is the
-- minimum forecast net load, `hi` the maximum, and it returns `hi` when the battery
-- cannot shave. **That is a CAPABILITY answer -- "the lowest peak I can hold" -- and
-- with SoC at 13.81% against a ~10% floor plus uncertainty, available energy is
-- approximately zero, so the water-fill degenerates to the forecast peak itself.**
--
-- `ottoq_energy_orchestrate` then substitutes that capability answer for a
-- contract-derived PERMISSION, with no `LEAST(v_service_max, ...)`:
--
--   v_demand_target := COALESCE(ottoq_bess_reserve_target(...), v_demand_target)
--
-- So when the battery is empty and forecast load is high -- precisely the dangerous
-- combination -- the demand target becomes "whatever we expect to draw", which is not
-- a target at all and is unbounded above by the utility contract.
--
-- **MEASURED, and note which way the numbers cut:**
--
--   charge_cap commands carrying a demand_target        **1,260**
--   demand_target above contract-derived 2,250 (0.9x)      **29**
--   **demand_target above service_max 2,500 itself**       **16**
--   worst demand_target                                **2,959.0**  (459 over contract)
--   **median demand_target**                           **1,048.0**
--
-- **The override is doing its job in the overwhelming majority of ticks.** Median
-- 1,048 against a contract-derived 2,250 means the water-fill normally *tightens* the
-- target by more than half -- it is a good mechanism and this is not an argument to
-- remove it. In 16 ticks of 1,260 it loosened the target past the utility contract
-- instead, and one of those 16 is the excursion `0374` exists to record.
--
-- Note also `factor` is **0.9**, not the 0.50 default in the source -- so the
-- contract-derived target is 2,250 rather than the 1,250 a reader of the function
-- would assume. I computed the first version of this section against 1,250 and had to
-- redo it; the policy value, not the default, is the one that is in force.

WITH c AS (
  SELECT (reason->>'demand_target')::numeric AS dt
    FROM public.ottoq_energy_commands
   WHERE sim_run_id = '5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'
     AND command_type = 'charge_cap_kw'
     AND reason->>'demand_target' IS NOT NULL
)
SELECT count(*)                                   AS caps,
       count(*) FILTER (WHERE dt > 2250)          AS over_contract_derived,
       count(*) FILTER (WHERE dt > 2500)          AS over_service_max,
       round(min(dt),1) AS min_dt, round(max(dt),1) AS max_dt,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY dt))::numeric,1) AS median_dt
  FROM c;

SELECT public.ottoq_policy_get('5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'::uuid,
                               'energy_reserve_shave', 0)      AS reserve_shave_on,
       public.ottoq_policy_get('5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10'::uuid,
                               'energy_demand_factor_peak', 0.50) AS factor_in_force;

-- ══ 4. WHAT THIS DOES TO G89, AND TO THE CP-SAT ARGUMENT ════════════════════
--
-- **G89's sentence "nothing asserts the sum" is FALSE and I repeated it in `0374`'s
-- header, its table COMMENT, its registry note and its cert-lineage note.** The
-- accurate statement is narrower and more useful:
--
--   * **The sum is computed every tick** by `ottoq_energy_orchestrate`, correctly,
--     with the battery's own draw subtracted.
--   * **No RULE asserts it** -- which is the part of G89 that survives. EN.001 meters
--     EV load only, and the orchestrator is not a rule: it publishes, it does not
--     refuse. So the L1 shield still cannot see a site total, and `0374`'s ledger is
--     still the only durable record of a crossing.
--   * **The excursion was a planning defect, not an unmodelled constraint.** An
--     unclamped capability-for-permission substitution produced a 1,762 kW cap where
--     the contract-derived arithmetic gives 2,250 - 72 + 0 - 968 = **1,210**. The
--     engine permitted 552 kW more than its own contract-derived formula allows.
--
-- **AND IT WEAKENS THE cuOpt CLAIM I MADE TWICE TONIGHT.** `0374` and `0269` both say
-- this excursion is "the first measured instance of the cumulative-resource construct
-- cuOpt cannot express". That was overreach. A cumulative site-power resource IS
-- reasoned about here, in SQL, per tick. What is missing is *enforcement inside the
-- feasibility layer* and *a clamp*, neither of which is a solver capability argument.
-- The honest version: **this excursion shows the site power cap is currently handled
-- by an advisory publication plus an unclamped heuristic, where a scheduler with a
-- first-class cumulative resource would carry it as a hard constraint.** That is still
-- a point for CP-SAT. It is a weaker and truer one, and `0374`'s wording should be
-- read with this file beside it.
--
-- ══ 5. THE FIX, AND WHY IT IS NOT MINE TO MAKE ══════════════════════════════
--
-- Defect two is one line:
--
--   v_demand_target := LEAST(v_service_max,
--                            COALESCE(ottoq_bess_reserve_target(...), v_demand_target));
--
-- I have not applied it, and the reason is not caution for its own sake. **It lowers
-- the EV charge cap in exactly the 16 ticks where the battery is empty and demand is
-- high** -- so it trades charging throughput at the worst moment for staying inside
-- the utility contract. On the evidence that is the right trade (a demand-charge
-- excursion is expensive and a breaker trip is worse), but it is a throughput decision
-- on the one depot under test, and rule 8's whole point is that this depot's capacity
-- is the open question. Chase decides.
--
-- Defect one -- the advisory cap -- is a larger decision and is the more interesting
-- one: making `charge_cap_kw` binding inside the decide path is the same shape as
-- widening EN.001's meter, i.e. a change to the feasible set, which per 2.9a lands
-- MEASURED first. The measurement is in §2: it would have bitten 26 times in 1,260
-- ticks, at a mean 67.7 kW.
--
-- **What IS mine and is done in `0378`: capturing these 16 rows into evidence before
-- they are purged.** `ottoq_energy_commands` is `class='engine'`, so the next demo run
-- deletes the entire causal record above -- every number in this file. That is the
-- 0231 fragility for the third time in one night.
