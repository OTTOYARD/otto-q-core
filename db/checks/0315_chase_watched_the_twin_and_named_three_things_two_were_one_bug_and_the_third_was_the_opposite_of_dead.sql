-- 0315  **Chase watched run `c23de1b8` in the cockpit and reported three things. Two of them are
--       ONE bug. The third is the opposite of what it looks like.** In his words:
--
--         (1) "vehicles were entering the depot and just immediately going to stage along the
--             perimeter … vehicles entering the depot are generally returning for service"
--         (2) "once services are complete, all vehicles should return for dispatch or egress out of
--             the depot. Not just stage and park along the perimeter. That long-term perimeter
--             parking for all vehicles is generally only occurring during early morning hours when
--             there's no dispatch or ride hail potential."
--         (3) "the robotic charge arms were not active when vehicles were in those specific
--             charging stalls"
--
--       **(1) and (2) are the same defect, and clause two of his own sentence is its diagnosis.**
--       Fixed by `db/migrations/0407`. **(3) is not a defect at all in the subsystem he named** —
--       the arms are the busiest thing in the twin. What is missing is their telemetry.
--
-- ══ §1 — THE CLOCK. ONE BUG BEHIND BOTH (1) AND (2) ════════════════════════
--
-- `ottoq_start_demo_run` picks the hour of day uniformly at random:
--
--     v_offset_min := CASE
--       WHEN p_seed IS NOT NULL THEN (abs(hashtext(p_seed::text)) % 1440)
--       ELSE floor(random() * 1440)::int
--     END;
--
-- `% 1440` is every minute of a 24-hour day, and **nothing ties a scenario to the time of day it is
-- about.** Seed 700001 hashed to 277, so a scenario titled *"Busy Day — Sustained Depot Pressure"*
-- ran **23:37 → 03:52 America/Chicago**.
--
-- `ottoq_deploy_target_fraction(hour, peak)` against the twin depot's 116 vehicles:
--
--     hour 23  0.066 ->  7        hour 02  0.005 -> 0
--     hour 00  0.017 ->  1        hour 03  0.005 -> 0
--     hour 01  0.008 ->  0
--
-- **The deploy target was ZERO for the last three hours of the run.** 21 vehicles deployed anyway,
-- so the engine over-delivered against its own target.
--
-- **So nothing was malfunctioning.** At 2 AM, parking returning vehicles on the perimeter is
-- correct behaviour. Chase supplied the mechanism himself, before seeing any of this: *"that
-- long-term perimeter parking … is generally only occurring during early morning hours when there's
-- no dispatch or ride hail potential."* The twin agreed with him completely. It thought it was 2 AM.
--
-- **The parking logic is right and the clock is wrong, and that distinction is the whole finding.**
-- A fix aimed at the staging logic — which is where both symptoms point — would have broken
-- behaviour that was already correct.
--
-- **AND IT IS NOT ONE BAD CONSTANT.** `charger_outage_morning_rush`, a scenario whose entire
-- identity is a time of day, picks its hour uniformly at random too. So does `heat_wave`. A scenario
-- library whose names assert a time and whose clock ignores it is the defect class.
--
-- **Why `0297`/G107 did not catch this, having edited exactly this code.** G107 fixed a real and
-- different bug — the world was BUILT at one clock and TICKED from another, 7h25m apart — and closed
-- it by preserving the VALUE and moving the world to meet it. Its comment says so. That was correct
-- and is not retracted. Nobody asked whether the value was *sensible*.
--
-- ══ §2 — THE SECOND MECHANISM: ONE DIAL, TWO VALUES ════════════════════════
--
-- Secondary, real, and not the main cause. `deploy_peak_fraction` resolves run -> depot -> global ->
-- **the caller's own hardcoded literal**, and the callers disagree:
--
--     public.ottoq_cil_propose                 0.90
--     public.ottoq_agent_board                 0.90
--     public.ottoq_decide_tick                 0.90
--     twin.ottoq_sim_advance_service_flow      0.55   <-- the one that MOVES vehicles
--
-- Measured: **307 run-scoped rows, 0 depot rows, 0 global rows, and no row for `c23de1b8`.** So on
-- the run Chase watched, every caller fell through to its own literal: the planners aimed at 90%
-- deployment while the executor worked to 55%. `db/migrations/0401` installs the global row at 0.90.
-- **It helps and it is not the fix** — at 0.90 the 01:00–03:00 target is still ~0.
--
-- ══ §3 — THE ARMS ARE NOT DEAD. THEY ARE THE BUSIEST SUBSYSTEM IN THE TWIN ══
--
-- **I nearly filed this one wrong, twice.** First census: `vehicles.robotic_tether_phase` is NULL
-- for all 116 twin-depot vehicles and 0 of 226 fleetwide have ever carried a phase, stall or
-- expiry; `ottoq_events` holds **zero** arm or tether rows; and `robotic_demate_seconds` appears in
-- exactly one function with the literal **-1**. That reads as a subsystem that has never run.
--
-- **Every part of that reading was wrong.**
--
--   · `twin.arm_cycles` holds **52,532 rows** — 26,956 `latched`, 22,364 `cleared`, 3,127
--     `abandoned`, 85 `emergency_released`, across 28,357 mates and 24,175 demates.
--   · `ottoq_arm_timings()` resolves correctly: `connect_seconds` 18.5, `demate_seconds` 11.5,
--     `source: ottoq_policy_params`. **The -1 is a "derive it" sentinel, not a broken value** — and
--     `0401` deliberately reconciles the catalog TO -1 rather than to 11.5, because the declared
--     11.5 would switch on a legacy override the engine has never used.
--   · The wiring is complete: `ottoq_arm_begin_cycle` is called by `twin.ottoq_sim_start_charge_session`
--     and `stop_charge_session`; `ottoq_arm_advance_cycles` and `ottoq_release_expired_tethers` are
--     called from `public.ottoq_sim_advance_tick_world`, the tick path itself.
--
-- **So what Chase saw is real and the cause is presentational, not mechanical.** The arm state lives
-- entirely in `twin.arm_cycles` and reaches neither of the two places anything can render from:
--
--   (a) **`ottoq_events` has 0 arm rows**, so the arms can never appear in the decision log, the
--       activity feed, or any audit trail. That is a genuine gap and is this check's open item.
--   (b) `vehicles.robotic_tether_*` — the columns a 3D renderer would bind to — read NULL.
--
-- **AND (b) IS NOT YET ESTABLISHED AS A DEFECT, WHICH MATTERS.** Every one of the 52,532 cycles is
-- closed (26,956 + 22,364 + 3,127 + 85 = 52,532 exactly), because the run ended. A closed cycle
-- SHOULD leave no live tether. **So NULL is the correct post-run value and proves nothing either
-- way.** Deciding whether the renderer's binding is populated requires sampling those columns
-- DURING a live run, which has not been done. Recorded as unknown rather than guessed — this file
-- has already had to walk back two readings of this same subsystem.
--
-- ══ §4 — AND ONE MORE GATE THE COCKPIT WOULD HIT ANYWAY ════════════════════
--
-- `ottoq_arm_timings` is one of the RPCs `0198` revoked from `anon`, and `ottoyarddepot-sim`
-- references it six times. So even with arms running and events emitted, the cockpit could not read
-- their timings until `db/migrations/0405` restored the grant.

\echo '=== 0315 §1 — the run Chase watched, in LOCAL time, against the deploy curve ==='
SELECT to_char(r.sim_clock_start   AT TIME ZONE 'America/Chicago', 'YYYY-MM-DD HH24:MI') AS start_ct,
       to_char(r.sim_clock_current AT TIME ZONE 'America/Chicago', 'YYYY-MM-DD HH24:MI') AS end_ct,
       r.tick_count
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id = 'c23de1b8-62bf-4a7b-bf9d-46ce4757d510';
-- EXPECT: 2026-09-20 23:37 -> 2026-09-21 03:52. The whole run in the overnight trough.

\echo '=== 0315 §1b — the curve at those hours, and the target in vehicles ==='
SELECT h AS local_hour,
       round(public.ottoq_deploy_target_fraction(h, 0.55)::numeric, 3) AS target_fraction,
       floor(116 * public.ottoq_deploy_target_fraction(h, 0.55))       AS target_vehicles
  FROM unnest(ARRAY[23,0,1,2,3,5,6,7,8]) h;
-- EXPECT: 7, 1, 0, 0, 0 for the run's hours; 17, 30, 45, 56 for 05:00-08:00, which is the window
-- 0407 moves busy_day into.

\echo '=== 0315 §1c — the trail, as Chase described it ==='
SELECT 'arrivals -> staged_awaiting_service' AS leg,
       count(*) FILTER (WHERE payload->'diff'->'current_state'->>'from' = 'arrived_at_gate'
                          AND payload->'diff'->'current_state'->>'to'   = 'staged_awaiting_service') AS n
  FROM public.ottoq_events WHERE event_type = 'vehicle.state_changed'
UNION ALL
SELECT 'staged_for_departure -> deployed',
       count(*) FILTER (WHERE payload->'diff'->'current_state'->>'from' = 'staged_for_departure'
                          AND payload->'diff'->'current_state'->>'to'   = 'deployed')
  FROM public.ottoq_events WHERE event_type = 'vehicle.state_changed'
UNION ALL
SELECT 'entered staged_for_departure (any source)',
       count(*) FILTER (WHERE payload->'diff'->'current_state'->>'to' = 'staged_for_departure')
  FROM public.ottoq_events WHERE event_type = 'vehicle.state_changed';
-- EXPECT on c23de1b8: 79 of 87 arrivals straight to staging; 103 reached staged_for_departure and
-- 9 deployed from there.

\echo '=== 0315 §1d — 58% of the depot calendar was parking, not service ==='
SELECT count(*) FILTER (WHERE purpose IN ('perimeter_hold','temp_hold','staging')) AS parking_holds,
       count(*) FILTER (WHERE purpose NOT IN ('perimeter_hold','temp_hold','staging')) AS service_bookings
  FROM public.ottoq_stall_bookings;

\echo '=== 0315 §2 — one dial, two values, and nothing settling it ==='
SELECT n.nspname||'.'||p.proname AS fn, x.lit AS hardcoded_default
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL (SELECT (regexp_matches(p.prosrc,
      'deploy_peak_fraction''?[^0-9-]{0,40}(-?[0-9]+\.?[0-9]*)'))[1] AS lit) x
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'deploy_peak_fraction'
 ORDER BY 2, 1;
-- EXPECT before 0401: three sites at 0.90 and twin.ottoq_sim_advance_service_flow at 0.55.

SELECT scope_type, count(*) AS rows
  FROM public.ottoq_policy_params WHERE param_key = 'deploy_peak_fraction'
 GROUP BY 1 ORDER BY 1;
-- EXPECT before 0401: run 307, and NO global or depot row -- so each caller uses its own literal.

\echo '=== 0315 §3 — the arms are running, hard ==='
SELECT (SELECT count(*) FROM twin.arm_cycles)                                        AS arm_cycles,
       (SELECT count(*) FROM twin.arm_cycles WHERE outcome = 'latched')              AS latched,
       (SELECT count(*) FROM twin.arm_cycles WHERE outcome = 'cleared')              AS cleared,
       (SELECT count(*) FROM twin.arm_cycles WHERE ended_at IS NULL)                 AS still_open,
       (SELECT count(*) FROM public.ottoq_events
         WHERE event_type ILIKE '%tether%' OR event_type ILIKE '%robotic%'
            OR event_type ILIKE '%arm.%')                                            AS arm_EVENTS;
-- EXPECT: ~52,532 cycles, ~26,956 latched, ~22,364 cleared, 0 still open (the run ended), and
-- **0 arm events**. The mechanism runs; its telemetry does not exist. That is the open item.

\echo '=== 0315 §3b — the timings resolve; -1 is a sentinel, not a broken value ==='
SELECT public.ottoq_arm_timings('c23de1b8-62bf-4a7b-bf9d-46ce4757d510'::uuid) AS timings;
-- EXPECT: connect_seconds 18.5, demate_seconds 11.5, demate_source 'derived'.

\echo '=== 0315 §3c — the wiring is complete: the tick path drives the arms ==='
SELECT n.nspname||'.'||p.proname AS caller,
       p.prosrc ~ 'ottoq_arm_begin_cycle'       AS calls_begin,
       p.prosrc ~ 'ottoq_arm_advance_cycles'    AS calls_advance,
       p.prosrc ~ 'ottoq_release_expired_tethers' AS calls_release
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND p.proname <> ALL (ARRAY['ottoq_arm_begin_cycle','ottoq_arm_advance_cycles','ottoq_release_expired_tethers'])
   AND (p.prosrc ~ 'ottoq_arm_begin_cycle' OR p.prosrc ~ 'ottoq_arm_advance_cycles'
        OR p.prosrc ~ 'ottoq_release_expired_tethers')
 ORDER BY 1;
-- EXPECT: twin.ottoq_sim_start_charge_session and stop_charge_session begin cycles;
-- public.ottoq_sim_advance_tick_world advances and releases. Nothing is unwired.

\echo '=== 0315 §3d — the question this file deliberately leaves OPEN ==='
SELECT count(*) FILTER (WHERE robotic_tether_phase IS NOT NULL) AS vehicles_with_live_tether,
       count(*)                                                 AS vehicles
  FROM public.vehicles;
-- Reads 0 of 226 NOW, and that is the CORRECT post-run value because every cycle is closed.
-- It is NOT evidence that the renderer's binding is broken. Answering that needs a sample taken
-- DURING a live run. Recorded as unknown.
