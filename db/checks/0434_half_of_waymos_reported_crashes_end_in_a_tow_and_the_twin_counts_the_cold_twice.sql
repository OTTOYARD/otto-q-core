-- 0434  **Half of Waymo's reported crashes end with the car towed, the parking-lot ones read like a depot's hazards,
--        and the twin counts the cold and the heat twice.**
--        Part A of the twin data contract review (2026-10-08), items 2 (NHTSA crash reports) and 4 (fitted temperature
--        effects). The external figures, with their files, dates and URLs:
--        docs/research/direct/2026-10-10-nhtsa-crash-reports-and-temperature-curves.md.
--        Measured 2026-10-10 05:52-05:57 UTC (12:52-12:57 AM CT), read-only, twin depot 11111111-…, during the throughput
--        sweep (reads only).
--
-- ══ §1 TOWED CARS (G408, extended) ═════════════════════════════════════════════════════════════════════════════
--
--   NHTSA's Standing General Order crash reports for automated driving systems (incidents 2025-04 to 2026-08, file
--   sha256 f856d0b9…f7f5): 1,211 Waymo reports, the Waymo towed in 647 (53.4%). With the CPUC filing's 10.3
--   collisions per million miles (0433 §4), about 5.5 tow-ins per million miles. The twin (1): 5e-7 incidents per mile,
--   45% of its kinds towed (collision_moderate 25%, breakdown_electrical 8%, tire_failure 6%, stranded_low_soc 4%,
--   collision_major 2%), so 0.23 tow-ins per million miles, x0.4 on busy_day: about a 24th.
--   The two public sources do not reconcile: NHTSA's file has 183 Waymo reports in California for April-June 2026,
--   the CPUC filing 291 collision rows for the same quarter, each with an NHTSA report id (redacted).
--
-- ══ §2 THE YARD'S HAZARDS ARE IN THE PARKING-LOT REPORTS (G409) ═════════════════════════════════════════════════
--
--   99 of the 1,211 (8.2%) were in parking lots, 54 of them towed. Named most: barrier 18, curb 16, gate 8, pole 5,
--   bollard 4, wall 4; among them barrier arms lowering onto a car that followed another through, and the roof sensor
--   striking a carport (twice). The twin depot (2): 2 gates with barrier arms and ALPR, 6 metal canopies of 12 ft over
--   the perimeter staging stalls, 4 solar canopies of 14 ft over the fast chargers. height_ft is the structure's top;
--   nothing records the clearance beneath a canopy or a gate, and no vehicle class records its height with sensors.
--
-- ══ §3 THE CLIMATE DRAIN COUNTS TEMPERATURE TWICE (G410) ═══════════════════════════════════════════════════════
--
--   twin.ottoq_sim_compute_discharge_rate already carries temperature: a cabin load of 0.5 kW + 0.15 kW per °C beyond
--   5 °C either side of 22 °C (at most 5), and a battery factor of +2%/°C below 5 °C and +1.5%/°C above 35 °C. On top,
--   public.ottoq_twin_arrival_soc_drain adds 8 x heat_stress + 12 x cold_stress battery points per hour out
--   (heat_stress = (day mean - 28) / 10, cold_stress = (5 - day mean) / 15, each clamped to 0-1;
--   public.ottoq_twin_climate_stress), drawn as power since 0486. For a Waymo I-Pace (84.7 kWh) at normal_day's mean
--   duty, range relative to the twin's own 21.5 °C, physics only / with the drain: -15 °C 43.9% / 27.0%; 10 °C 87.2% /
--   87.2%; 31 °C 92.3% / 73.1%. Geotab's published points, relative to its 21.5 °C peak (page of 2025-10-30): 47.0% at
--   -15 °C, at least 87.0% from 10 to 31 °C. The physics alone sits on them; the drain pulls both ends below.
--   It barely fires now (3): over the twin depot's 76 runs of the last 7 days the day means ran 10.1-28.9 °C (every run
--   starts on 2026-09-01), 4 day cards above 28 °C and none below 5 °C, and the drain averaged 0.03 points an hour (at
--   most 0.76). So removing it moves nothing measured this week; it would move any winter or July scenario.
--
-- ══ REPRODUCE ══
-- The external tables: python3 -I over the downloaded CSV, as in the note.

-- (1) the twin's incident rate and the kinds that tow, from the live function
SELECT substring(p.prosrc FROM 'v_per_mile NUMERIC := ([0-9.]+)') AS per_mile,
       regexp_replace(substring(p.prosrc FROM strpos(p.prosrc, 'IF v_pick < 0.55') FOR 900), '\s+', ' ', 'g') AS kinds
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_maybe_incident';

-- (2) the twin depot's structures and their heights
SELECT structure_kind, count(*) AS n, min(height_ft) AS h_min, max(height_ft) AS h_max
  FROM public.ottoq_site_structures
 WHERE depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 2 DESC;

-- (3) the climate drain the twin's recent runs actually drew
WITH r AS (
  SELECT r.sim_run_id FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.started_at > now() - interval '7 days'),
c AS (
  SELECT vc.sim_run_id, vc.value::numeric AS t
    FROM public.ottoq_variability_cards vc JOIN r USING (sim_run_id)
   WHERE vc.var_key = 'ambient_temp_c' AND vc.scope_instance = 'global')
SELECT count(*) AS day_cards, count(DISTINCT sim_run_id) AS runs, round(min(t), 1) AS t_min, round(max(t), 1) AS t_max,
       count(*) FILTER (WHERE t > 28) AS hot_days, count(*) FILTER (WHERE t < 5) AS cold_days,
       round(avg(8 * GREATEST(0, LEAST(1, (t - 28) / 10.0)) + 12 * GREATEST(0, LEAST(1, (5 - t) / 15.0))), 2) AS mean_drain_pts_h,
       round(max(8 * GREATEST(0, LEAST(1, (t - 28) / 10.0)) + 12 * GREATEST(0, LEAST(1, (5 - t) / 15.0))), 2) AS max_drain_pts_h
  FROM c;
