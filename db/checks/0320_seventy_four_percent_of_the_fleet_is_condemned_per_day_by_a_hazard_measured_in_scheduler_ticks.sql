-- 0320  **The 86-of-116 tow rate on run `d68d05bb` is fully explained, it is NOT the 7x DTC
--       injection, and the mechanism is a fault hazard denominated in SCHEDULER TICKS.**
--
--       `twin.ottoq_sim_vehicle_exception_handler` rolls `vehicle_fault_rate_per_tick = 0.004`
--       against every in-depot vehicle, every tick. The longer a run is, the more of the fleet
--       dies — and nothing about that is a property of a vehicle.
--
--       `forces_recert` TRUE for any fix: this changes decisions, events and end state.
--
-- ══ §1 THE MECHANISM, AND THE ARITHMETIC MATCHES TO FOUR FIGURES ════════════
--
--     v_per_tick := COALESCE(ottoq_policy_get(p_sim_run_id,'vehicle_fault_rate_per_tick',0.004), 0.004);
--
--     FOR v_rec IN
--       SELECT ... FROM vehicles
--        WHERE home_depot_id = p_depot_id AND category = 'autonomous'
--          AND current_state IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay',
--                                'in_service_bay','charge_complete_holding','staged_awaiting_service')
--          AND NOT jsonb_exists(config, 'exception')
--     LOOP
--       IF ottoq_sim_seeded_random(v_seed, 'roll:'||v_rec.id::text) < v_per_tick THEN   -- fault
--
-- Three properties follow, and together they predict the observation exactly:
--
--   (a) The roll is **per vehicle, per tick**, across seven in-depot states.
--   (b) `NOT jsonb_exists(config,'exception')` makes a vehicle eligible **at most once**. That is
--       why the run shows **86 transitions across 86 distinct vehicles** — a 1:1 ratio I flagged
--       earlier as "too clean to be emergent." It is not emergent; it is an exclusion clause.
--   (c) So P(a vehicle is condemned) = `1 - 0.996 ^ (eligible ticks)`.
--
-- Measured on `d68d05bb` (busy_day, seed 700001, 1,104 ticks, 116 vehicles):
--
--     eligible ticks      P(condemned)      note
--     ---------------     ------------      ----------------------------------------
--                 48            17.5%      the certification horizon -- looks fine
--                100            33.0%
--                337            74.1%      <-- OBSERVED 86/116 = 74.138%
--              1,104            98.8%      a vehicle that never leaves the depot
--
-- Solving the observed share for exposure gives **~337 eligible ticks per vehicle**, or about 30%
-- of the run spent in one of those seven states. That is an entirely plausible in-depot duty
-- cycle, and it reproduces 74.1% against a measured 74.138%. **The mechanism is settled.**
--
-- ══ §2 THIS CLOSES `0319`'s OPEN QUESTION, IN THE DIRECTION `0319` SUSPECTED ═
--
-- `0319` §7 said: *"NOT established: that the 7x DTC rate accounts for all 86 `tow_requested`
-- vehicles [...] the remainder is unattributed."* It is now attributed, and the 7x is almost
-- entirely innocent. Transitions into `tow_requested` by the state they came FROM:
--
--     charging_l2               35
--     staged_awaiting_service   33
--     staged_for_departure       9
--     deployed                   5   <-- the ONLY path the DTC spawner can reach
--     charge_complete_holding     2
--     charging_dcfc              1
--     arrived_at_gate            1
--
-- `twin.ottoq_sim_maybe_spawn_dtc` is called only from
-- `twin.ottoq_sim_advance_deployed_telemetry`, i.e. only for vehicles that are DEPLOYED. So the
-- 7x-scaled DTC path can account for at most the **5** `deployed -> tow_requested` transitions.
-- **68 of 86 happened to vehicles sitting still inside the depot**, 35 of them mid-L2-charge.
--
-- **And the two fault systems are unconnected.** `vehicle_fault_rate_per_tick` comes from
-- `ottoq_policy_get`; it never consults `ottoq_profile_rate_mult`. So `busy_day`'s
-- `_rates.dtc = 7.0` does not scale it, and no scenario in the library can tune it. Two parallel
-- fault models, one scenario-tunable and one not, and the one that does 94% of the damage is the
-- one no scenario can reach.
--
-- ══ §3 THE DEFECT IS THE UNIT, NOT THE VALUE ═══════════════════════════════
--
-- Lowering 0.004 would move the number and leave the defect. **A hazard denominated in scheduler
-- ticks is not a physical quantity**, and two consequences follow that a calibrated fleet model
-- must not have:
--
--   **(a) Fleet reliability depends on run length.** The same dial reads 17.5% at the 48-tick
--        certification horizon and 98.8% over a full day in depot. Every canon column in
--        `ottoq_cert_columns` is 6–48 ticks, so **certification runs never see this** — the dial
--        looks calibrated precisely where we measure it and fails everywhere we demo it.
--
--   **(b) Fleet reliability depends on `tick_interval_seconds`.** A tick is 30 sim-seconds on this
--        scenario. Halve the tick interval for finer resolution and you double every vehicle's
--        fault rate, having changed nothing about the vehicles. That is the same class as G15 (a
--        wall clock inside a certified path): a physical model reading an implementation detail.
--
-- **The fix is to denominate it per unit of SIM TIME and derive the per-tick probability from
-- `tick_interval_seconds`** — `vehicle_fault_rate_per_sim_hour`, converted at the call site. Then
-- the hazard is invariant to both run length and tick resolution, which is what "a fault rate"
-- means.
--
-- **And the value should come from the calibration layer, not from a literal.** CLAUDE.md 2.8
-- names `ottoq_calibration_*` over **CA DMV AV reports**, which carry exactly this: autonomous
-- vehicle failure and disengagement rates. A fault hazard sourced from a public regulatory filing
-- is defensible under diligence; `0.004` in a `COALESCE` default is not. The scaling hook should
-- then run through `ottoq_profile_rate_mult(run,'vehicle_fault')` so scenarios can stress it, which
-- closes §2's asymmetry in the same change.
--
-- ══ §4 WHAT THIS CONTAMINATES, AND IT IS THE HEADLINE CAPACITY NUMBER ═══════
--
-- I reported to Chase that the twin depot's wall is service and wash bays: **116 vehicles wanted
-- service, 27 got a bay**, `svc_cap 2`, `wash_cap 3`, overflow stable at 17–24. That measurement
-- is now **not trustworthy as a capacity result**, and the reason is causal rather than
-- incidental:
--
-- A condemned vehicle is `tow_requested`, then triaged to `emergency_staged` (54 of them, via
-- `vehicle.tow_retrieved_staged`), and it needs a **service bay** to clear. So the fault model was
-- manufacturing service demand faster than two bays could retire it. **The queue I measured is
-- substantially a queue of vehicles the fault dial condemned, not a queue of vehicles that needed
-- routine service.** "116 wanted service" conflates scheduled need with manufactured breakdown.
--
-- **So the stall-mix / power sweep must not run until this is fixed**, or every configuration will
-- return the same answer — the queue formed at the bays — for a reason that has nothing to do with
-- stalls, chargers or power.
--
-- ══ §5 WHAT IS NOT CLAIMED ═════════════════════════════════════════════════
--
-- **The 0.004 is not asserted to be wrong as a design intent** — only wrong as a unit, and
-- miscalibrated for horizons longer than certification. It may be exactly right for a 48-tick
-- pair, which is plausibly what it was tuned against.
--
-- **The `emergency_staged` 54 are not a separate fault source.** `vehicle.tow_retrieved_staged`
-- fires 54 times for 54 vehicles from actor `incident_triage`, downstream of the tow. Earlier I
-- listed `tow_requested` 86 and `emergency_staged` 54 as though they were two populations; they are
-- one population at two stages.
--
-- **Not measured:** how much of the 27-of-116 service throughput was consumed by fault triage
-- versus scheduled atoms. That is the number that would say what the depot's real service capacity
-- is, and it needs the fix first.

\echo '=== 0320 §1 — the dial, and the probability it implies at each horizon ==='
SELECT public.ottoq_policy_get(NULL,'vehicle_fault_rate_per_tick', 0.004)   AS rate_per_tick,
       round((1 - power(1 - 0.004,   48))::numeric, 3) AS p_at_48_ticks,
       round((1 - power(1 - 0.004,  337))::numeric, 3) AS p_at_337_ticks,
       round((1 - power(1 - 0.004, 1104))::numeric, 3) AS p_at_1104_ticks;
-- 17.5% at the certification horizon; 98.8% over a day spent in depot. Same dial.

\echo '=== 0320 §2 — every certification column is short enough never to see it ==='
SELECT ticks, count(*) AS canon_columns,
       round((1 - power(1 - 0.004, ticks))::numeric, 3) AS p_vehicle_condemned
  FROM public.ottoq_cert_columns
 GROUP BY ticks ORDER BY ticks;
-- The canon certifies horizons where the fault dial is invisible. That is why nine green columns
-- and a 74%-condemned demo run are both true at once.

\echo '=== 0320 §3 — the hazard reads a scheduler detail, so scenarios change physics ==='
SELECT scenario_code,
       (timeline #>> '{tick_interval_seconds}')::int AS tick_seconds,
       default_time_scale,
       'a shorter tick multiplies every vehicle''s fault rate' AS consequence
  FROM public.ottoq_scenarios
 WHERE status = 'active'
 ORDER BY scenario_code LIMIT 8;
-- Any scenario that changes tick_interval_seconds silently changes fleet reliability.

\echo '=== 0320 §4 — two fault systems, and only one is scenario-tunable ==='
SELECT 'twin.ottoq_sim_maybe_spawn_dtc'            AS mechanism,
       'ottoq_profile_rate_mult(run, ''dtc'')'      AS scaled_by,
       'deployed vehicles only'                    AS population,
       '5 of 86 tows on d68d05bb'                  AS observed_contribution
UNION ALL
SELECT 'twin.ottoq_sim_vehicle_exception_handler',
       'NOTHING -- ottoq_policy_get literal',
       '7 in-depot states, once per vehicle',
       '81 of 86 tows on d68d05bb';
-- The mechanism doing 94% of the damage is the one no scenario can reach.
