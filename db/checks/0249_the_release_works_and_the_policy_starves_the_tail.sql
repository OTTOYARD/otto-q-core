-- ============================================================================
-- 0249 — 0329's MECHANISM IS RIGHT AND ITS POLICY IS WRONG: THE RELEASE FREES
--        THE SPACE, AND THE VEHICLE THAT LOST IT STARVES.
-- ============================================================================
-- Paired runs, identical configuration (tick_interval 30 s, time_scale 60,
-- demo_speed_x 1.0, seed 771771, busy_day, flagship, policy otto_q). The only
-- difference is the run-scoped dial `space_departure_release_enabled`. No
-- global or depot scope carries it, so nothing else could have moved.
--
--   CONTROL   c9b05a04-678f-4d27-9bb6-f93d2e501d64  dial 0  (29 ticks)
--   TREATMENT 39c7400a-e19a-44d4-a901-7aea6bd99b39  dial 1  (33 ticks)
--
-- Both ended on the same governor reason but at different points, so every
-- comparison below is CLIPPED TO 870 SIM-MINUTES from each run's own start --
-- the control's full horizon. The unclipped numbers are given too, and they
-- tell the same story, but the clipped ones are the ones that are entitled to.
--
-- ── WHAT WORKED, AND IT WORKED WELL ────────────────────────────────────────
--                                     control   treatment
--   space conflicts (clipped)             134          19     -86%
--   p50 time-to-service (min)              60          30     halved
--   sweep-1 departures fired                 0           4
--   sweep-2 no-show releases                36         158
--
-- The instrument did exactly what 0329 designed it to do. Claims held against
-- vehicles that were not in the stall are now retired, and the median vehicle
-- reaches service in half the time.
--
-- ── WHAT BROKE, AND IT IS WORSE THAN WHAT WAS FIXED ────────────────────────
--                                     control   treatment
--   p95 time-to-service (min)             243         480     +97%
--   turns completed                       332         295     -11%
--   returns_unserved                        0           1
--   peak_site_kw                         1762      2026.4     +15%
--
-- A fix that halves the median, doubles the p95 and leaves a vehicle unserved
-- has not improved the depot. It has redistributed the pain onto the vehicles
-- that were already worst off.
--
-- ── THE MECHANISM OF THE HARM, MEASURED RATHER THAN INFERRED ───────────────
-- Counting how many times a SINGLE vehicle had a claim released out from under
-- it, clipped to the same 870 sim-minutes:
--
--                                     control   treatment
--   vehicles that lost a claim             30          80
--   worst single vehicle                    3          12
--   vehicles that lost 3 or more            1          22
--
-- One vehicle had its space taken away TWELVE times. Twenty-two vehicles lost
-- a claim three times or more, against one in the control. That is starvation,
-- and it is the direct explanation of p50 down / p95 up: freeing the space
-- lets whoever is ready NOW win, and the vehicle that just lost re-enters the
-- same race on equal terms and can lose again, indefinitely.
--
-- ── AND HERE IS THE ACTUAL DEFECT, WHICH THE ORIGINAL MEASUREMENT ALREADY
--    CONTAINED AND I DID NOT READ CORRECTLY WHEN I WROTE 0329 ──────────────
-- 0328's ledger recorded WHERE the blocking vehicle was at the moment of every
-- refusal: arrived_at_gate 60%, staged_awaiting_service 22.5%,
-- en_route_to_depot 17.5%. Every one of those is a vehicle that is AT THE
-- DEPOT OR ON ITS WAY TO IT.
--
-- 0329's sweep 2 releases a `held` claim purely because a grace period elapsed
-- after the window opened. It asks whether the vehicle is IN THE STALL. It
-- never asks whether the vehicle is COMING. So it takes the space away from
-- vehicles that are standing in the yard waiting for it -- which is precisely
-- the population it then starves.
--
-- Sweep 1 carries two independent witnesses that the vehicle has LEFT. Sweep 2
-- carries no witness at all about the vehicle's INTENT. That asymmetry is the
-- whole defect, and it shows in the firing counts: sweep 1 fired 4 times and
-- did no measurable harm; sweep 2 fired 158 times and did all of it.
--
-- ── VERDICT ────────────────────────────────────────────────────────────────
-- The dial STAYS 0. It shipped inert by design and that decision is the reason
-- this finding cost one pair of twin runs instead of a production regression.
--
-- Two follow-ups, in this order:
--   1. SPLIT THE DIAL. Sweep 1 and sweep 2 are independently switchable, so
--      the half that works is not held hostage by the half that does not.
--   2. GIVE SWEEP 2 AN INTENT WITNESS. It must not retire a claim held by a
--      vehicle that is physically at the depot, or whose return ETA lands
--      inside the booking window. The ETA and its provenance already exist
--      (0320-0322); this needs no new estimate, only that the sweep read one.
--
-- NOT CLAIMED: that fixing sweep 2 will make the combined change net-positive.
-- That is the next pair of runs, not a prediction to be quoted from here.
-- ============================================================================

-- REPRODUCTION A: the headline comparison, both arms, unclipped.
WITH arms(arm, rid) AS (VALUES
  ('1_CONTROL   dial=0','c9b05a04-678f-4d27-9bb6-f93d2e501d64'::uuid),
  ('2_TREATMENT dial=1','39c7400a-e19a-44d4-a901-7aea6bd99b39'::uuid))
SELECT a.arm,
  k->>'p50_time_to_service_min'  AS p50,
  k->>'p95_time_to_service_min'  AS p95,
  k->'audit'->'p95_time_to_service_min'->>'max_time_to_service_min' AS max_tts,
  k->>'returns_unserved'         AS unserved,
  k->'audit'->'service_point_turns_per_point_per_day'->>'turns_completed'  AS turns,
  k->'audit'->'service_point_turns_per_point_per_day'->>'released_no_show' AS no_show,
  k->>'peak_site_kw'             AS peak_kw,
  (SELECT count(*) FROM public.space_conflict_ledger c WHERE c.sim_run_id=a.rid) AS conflicts
FROM arms a, LATERAL (SELECT public.ottoq_kpi_five(a.rid) AS k) kk
ORDER BY a.arm;

-- REPRODUCTION B: the starvation count, CLIPPED so the horizons match.
WITH arms(arm, rid) AS (VALUES
  ('1_CONTROL','c9b05a04-678f-4d27-9bb6-f93d2e501d64'::uuid),
  ('2_TREATMENT','39c7400a-e19a-44d4-a901-7aea6bd99b39'::uuid)),
h AS (SELECT a.arm, a.rid, r.sim_clock_start + interval '870 minutes' AS cutoff
        FROM arms a JOIN public.ottoq_sim_runs r ON r.sim_run_id=a.rid),
rel AS (
  SELECT h.arm, b.vehicle_id, count(*) AS releases
    FROM h JOIN public.ottoq_stall_bookings b ON b.sim_run_id=h.rid
   WHERE b.release_reason='no_show_grace_elapsed' AND b.released_at <= h.cutoff
   GROUP BY 1,2)
SELECT h.arm,
  (SELECT count(*) FROM public.ottoq_stall_bookings b
    WHERE b.sim_run_id=h.rid AND b.release_reason='no_show_grace_elapsed'
      AND b.released_at<=h.cutoff)                                   AS noshow_releases,
  (SELECT count(*)            FROM rel WHERE rel.arm=h.arm)          AS vehicles_released,
  (SELECT COALESCE(max(releases),0) FROM rel WHERE rel.arm=h.arm)    AS worst_vehicle,
  (SELECT count(*) FROM rel WHERE rel.arm=h.arm AND releases>=3)     AS vehicles_3plus,
  (SELECT count(*) FROM public.space_conflict_ledger c
    WHERE c.sim_run_id=h.rid AND c.sim_clock<=h.cutoff)              AS conflicts
FROM h ORDER BY 1;
-- Expected 2026-09-15:
--   1_CONTROL     36 releases,  30 vehicles, worst  3,  1 at 3+, 134 conflicts
--   2_TREATMENT  158 releases,  80 vehicles, worst 12, 22 at 3+,  19 conflicts

-- REPRODUCTION C: the dial really was the only difference.
SELECT scope_type, scope_id, param_key, param_value
  FROM public.ottoq_policy_params
 WHERE param_key='space_departure_release_enabled';
-- Expected: exactly one row, scope_type='run', the treatment run, value 1.
