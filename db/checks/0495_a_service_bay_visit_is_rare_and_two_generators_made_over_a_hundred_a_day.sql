-- 0495  **A service bay visit is rare. Two generators in the twin made over a hundred a day; both are fixed, and the
--        first run after them sent six cars.**
--        Production database, 2026-11-14 15:33 to 15:45 UTC (9:33 to 9:45 AM CT), from now() on the reads. Rule 8:
--        the twin depot. Rule 12: two short runs to see finished changes working; no pair, no sweep. Each run is one
--        seed: readings, not ranges.
--
--   NUMBERS. This file was written as 0494, with findings G548 and G549. Another branch (PR 280) had taken 0494, G548
--   and G549 the same night, so this is 0495 with G550 and G551. The two lineage rows of 0837 and 0838, written at the
--   apply, still say G548 and G549: read them as G550 and G551.
--
--   Chase, that morning: "a service bay should be extremely rare or even quarterly from an annual perspective unless
--   there's a major issue with the vehicle like flat tire or malfunction of some sort. So for more than two or three
--   vehicles a day to visit the service bay would be way too much." CLAUDE.md rule 15.
--
-- ══ (1) WHAT WAS THERE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 7c967d67 (busy_day, 9.1 sim-hours, 116 cars, each driving a mean 73.4 km and 1.38 h): service-bay atoms on its
--   visits: mechanical_pm 106 on 102 cars, sensor_calibration 37, fault_repair 5, cosmetic_repair 1. I had read the
--   same line the night before (db/checks/0493 (4): 75 cars, 36 hours) and filed it as the wall of G500-G503.
--   GENERATOR ONE (G550). busy_day's fleet_overrides scaled each car's maintenance interval by 0.01 and its
--   calibration interval by 0.02: 65-95 km and 3.6-6.4 h, where the cars' own draws are 6,523-9,469 km and 181-320 h.
--   GENERATOR TWO (G551), found on 0837's first run. twin.ottoq_sim_observe_asset draws on every arrival from the
--   'service_manifest' feed plan: maintenance (1.25% of arrivals at least, 10% from 80% of the interval, 30% once
--   due), calibration (1%, 8%, 24%), a cosmetic repair (1%) and a fault repair (2%), whatever the car's mileage. The
--   observer called 400 times on one car under version 1: 51 maintenance, 3 calibrations, 4 cosmetic, 8 faults.
--
-- ══ (2) WHAT WAS CHANGED ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   0837 (15:35:39 UTC, ledger 20261114153539): busy_day's two scales are 1. Data only.
--   0838 (15:40:52 UTC, ledger 20261114154052): version 2 of the service_manifest plan, promoted under a person's
--   name. Maintenance and calibration draws are 0, so both come only from ottoq.ottoq_derive_visit_needs when a car's
--   own interval is due (0715). cosmetic_repair 0.02 -> 0.001 and fault_repair_p 0.02 -> 0.002: ASSUMPTIONS, set to
--   keep a 116-car day inside Chase's bound. Data only. 0838's first apply failed inside its own V1 on an operator
--   precedence error and rolled back whole; I had not run it on the scratch PostgreSQL first. Fixed, run there, applied.
--   tests/test_service_bay_visits_are_rare_sql.py: 5 tests on the scratch PostgreSQL.
--
-- ══ (3) THREE RUNS, ONE SEED (673944733802809200), busy_day ══════════════════════════════════════════════════════════
--
--                                      7c967d67 (before)   ff41e769 (0837 only)   01299c54 (0837 and 0838)
--     read at sim                      9.1 h (its end)     8.5 h                  9.0 h
--     visits                           (not read)          151                    110
--     mechanical_pm atoms              106                 8 (2 interval due)     2 (2 interval due)
--     sensor_calibration atoms         37                  8 (1 interval due)     2 (1 interval due, 1 from an escalation)
--     fault_repair atoms               5                   5                      2
--     cosmetic_repair atoms            1                   0                      0
--     cars with service-bay work       (102 owed a PM)     20                     6
--     the service bays' line at the read   (75 cars, 36 h the night before)   (not read)   3 cars, 1.02 h, both bays free
--   7c967d67 was played live at 8x from the cockpit (725 ticks). The other two were started from SQL through
--   public.ottoq_operator_start_run and ticked 30 sim-minutes at a time (18 ticks), so their visit counts are not
--   comparable with a cockpit run's. They are comparable with each other.
--   SIX IS STILL ABOVE THE BOUND, on one seed. Read by source: 3 are intervals falling due (about 1.7 expected a day
--   at this fleet's driving: 116 x 73.4 km / 8,017 km and 116 x 1.38 h / 247 h); 2 are fault repairs drawn at 0.2% of
--   arrivals (0.2 expected in 110; two is an unlucky day or a rate still too high, and one run cannot tell); 1 is a
--   calibration raised by an escalation after a failed sensor clean (from_escalation), a third source this check did
--   not open.
--
-- ══ (4) WHAT THIS MAKES STALE ════════════════════════════════════════════════════════════════════════════════════════
--
--   Every busy_day figure from before 0837 describes a depot with that line in it: G500-G503's wall (124 bay-hours
--   owed against 18), 0781's yield to the bay line and its car-minutes, 0782's open shop, the agent board's "the
--   service bays are the wall", the recalls for service_interval_due (FINDINGS: 90 of 116 cars recalled for it on one
--   run), and the departure and return fits learned on days where the bays held most of the fleet. None was
--   re-measured here. The mechanisms are not wrong; their numbers are a different depot's.
--
-- ══ (5) WHAT IS OPEN ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The intervals themselves. At this driving a car's maintenance falls due about every 42 days and its
--   calibration about every 68, not quarterly. They are the cars' own draws (ottoq_variability_cards), not changed
--   here: Chase's call. (b) The two assumed rates (fault 0.2%, cosmetic 0.05% of arrivals). (c) The escalation that
--   raises a calibration after a failed sensor clean: its rate was not read. (d) public.ottoq_scenarios
--   .initial_conditions still carries a copy of busy_day's overrides with scales 0.0025 and 0.02; no function reads a
--   scale from it (prosrc scan for pm_km_scale: the loader and a metrics function), and it was left as found.
--   (e) A visit's meta still says plan "service_manifest.v1" under version 2: a label written by the generator.
--   (f) A cockpit run (live, 8x) after both changes: not yet made. (g) The fits of §4 have no regime row.
--
-- ══ THE QUERIES ═══════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1), (3) service-bay work on a run's visits, by service, with how many came from the car's own interval
SELECT a ->> 'svc' AS svc, count(*) AS atoms, count(DISTINCT vn.vehicle_id) AS cars,
       count(*) FILTER (WHERE (a ->> 'interval_due')::boolean) AS interval_due,
       count(*) FILTER (WHERE (a ->> 'from_escalation')::boolean) AS from_escalation,
       count(*) FILTER (WHERE a ->> 'status' = 'done') AS done
  FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '01299c54-aac7-4e93-ad3d-5186a5d6f689' AND vn.depot_id = '11111111-1111-1111-1111-111111111111'
   AND a ->> 'requires_bay' = 'service_bay'
 GROUP BY 1 ORDER BY 2 DESC;

-- (1) what every scenario does to a car's intervals, and the active service plan's four numbers
SELECT scenario_code, fleet_overrides -> 'vehicle_overrides' AS vehicle_overrides FROM public.ottoq_sim_scenarios
 WHERE fleet_overrides ? 'vehicle_overrides';
SELECT version, status, plan #> '{probabilities,mechanical_pm}' AS pm, plan #> '{probabilities,sensor_calibration}' AS calibration,
       plan #> '{probabilities,cosmetic_repair}' AS cosmetic, plan -> 'fault_repair_p' AS fault
  FROM public.ottoq_feed_plans WHERE var_key = 'service_manifest' ORDER BY version;

-- (3) the standing reading for rule 15: cars with service-bay work on a run. More than two or three is read as wrong.
SELECT count(DISTINCT vn.vehicle_id) AS cars_with_service_bay_work
  FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
 WHERE vn.sim_run_id = '01299c54-aac7-4e93-ad3d-5186a5d6f689' AND vn.depot_id = '11111111-1111-1111-1111-111111111111'
   AND a ->> 'requires_bay' = 'service_bay';
