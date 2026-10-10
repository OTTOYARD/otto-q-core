-- 0432  **Part A's two fixes, checked against the live engine before building them: the corpus mapping must not be
--        applied (the five variables it names do not draw flat noise), the tariff is current as NES publishes it, and
--        the twin's chargers are up 93.7% of the time, below the 97% depot-grade floor 0659 makes a dial.**
--        Part A of the twin data contract review (2026-10-08), items 6 (apply the corpus mapping) and 7 (tariff
--        refresh), and Chase's charger-fault decision (2026-10-09). Measured 2026-10-10 04:45-05:10 UTC (11:45 PM CT on
--        Oct 9 to 12:10 AM CT on Oct 10), read-only, twin depot 11111111-….
--
-- ══ §1 THE CORPUS MAPPING: DO NOT APPLY ottoyarddepot-sim/supabase/proposed/002 ════════════════════════════════════
--
--   The review said five twin variables (trip_duration, charge_time, idle_fraction, incident, charger_fault) "still
--   draw flat random numbers because a mapping was never applied". Read against the live dealer, that is not so:
--
--   (a) Four of the five are never dealt. trip_duration, charge_time, idle_fraction and incident are per-run profile
--       multipliers, read by public.ottoq_profile_rate_mult(run, key) from ottoq_variability_profiles._rates, and 1.0
--       unless a scenario sets one. Not one card exists for any of them (1). Their catalog unit is "×" (0-3, 0-3,
--       0-2, 0-10). 002 maps them to corpus quantities in absolute units: trip_duration_minutes (mean 17.0 min),
--       charge_duration_minutes (mean 206 min), idle_fraction_per_shift (0.31) and collisions_per_million_miles
--       (0.50). Had anything dealt them, a trip would have run 17 times its length and a charge 206 times.
--   (b) The fifth is a fitted model already. charger_fault is dealt by public.ottoq_twin_deal_fault_card, not the
--       generic dealer: a per-session fault chance scaled by each charger's MTBF from the charger_reliability corpus
--       (days_between_faults), by heat, and a repair time from repair_days (feed plan charger_fault_repair v3). 002
--       would map it to session_success_rate, a success fraction (mean 0.80), the opposite quantity.
--   (c) 002's weather half is live already. ambient_temp_c is dealt per day with the NOAA 1991-2020 normals by
--       month ('month:' || MM, America/Chicago) and an AR(1) day-to-day persistence; precipitation comes from its own
--       Markov daily budget (ottoq_precip_daily_mm).
--
--   What does draw flat noise (the dealer's uniform fallback, no fitted distribution under the var_key) (1) (2):
--     - wash_time, detail_time, maintenance_time: uniform 0.7-1.3 per visit, multiplying the nominal service times
--       in ottoq.ottoq_derive_visit_needs (wash 9 min, clamped to 8-10; deep clean 20, at least 12; preventive
--       maintenance 40, at least 20), times each car's own service-speed card (uniform 0.80-1.25 at boot);
--     - cloud_cover_pct: uniform 0-100% per 4-hour block (G402);
--     - the per-car condition cards drawn at boot (battery health, charge-curve and consumption scalars, service
--       intervals, soil rate, wash cadence): uniform over their ranges, as priors, by design.
--   None has a fitted source in the corpus (18 variables from 9 datasets, (3)): no dataset of depot service times
--   or sky cover is held. So the honest state is that these are declared priors, and the fix is data the corpus does
--   not have, not a mapping. Recorded as G403.
--
-- ══ §2 THE TARIFF IS CURRENT AS NES PUBLISHES IT (G404) ═════════════════════════════════════════════════════════
--
--   NES's own rates page (https://www.nespower.com/rates/, read 2026-10-10) links GSA-1/2/3 to
--   https://www.nespower.com/-/media/project/nes/common/pdfs/commercial-rates/2025/april/gsa-123.pdf, whose header
--   reads "GENERAL POWER RATE--SCHEDULE GSA (Effective October 2024)" (sha256 8d524812…611e6e as read). Its Part 3 (over
--   1,000 kW) is what ottoq_depot_tariffs holds for NES_GSA_3 (4), to the cent:
--     service charge $1,454.84 + TVA grid access charge $636.87 (average over 150,000 kWh a month) = $2,091.71 fixed;
--     demand, first 1,000 kW / excess: summer $21.40 / $21.78, winter and transition $20.34 / $20.73;
--     energy 4.785¢/kWh for the first 150,000 kWh a month; seasons Jun-Sep, Dec-Mar, Apr/May/Oct/Nov;
--     every base charge then moves with TVA's adjustment addendum (the fuel cost adjustment; 2.147¢/kWh for October
--     on the rates page).
--   What the review read on OpenEI (a "Mar 2026" NES entry: 8.8¢/kWh energy, $1,680.64 fixed, a $1.34/kW capacity
--   charge) mixes the schedule's parts: $1,680.64 is the service charge with the smaller grid access charge
--   ($1,454.84 + $225.80), and both the 8.69-9.05¢ energy charge and the $1.34/kW capacity charge belong to Part 2
--   (51-1,000 kW). The review's own caution was right; the repo's Part 3 rows are the current ones.
--   Not modelled, and no number moves for it today: Part 3's second energy block (3.883¢/kWh above 150,000 kWh a
--   month). No function reads energy_base_cents_kwh or fixed_monthly_usd; the twin's bills read the demand charges
--   only (5). Watch: NES posted October 2026 schedules for LMS, TDMSA and DC on the same page, and none yet for GSA.
--
-- ══ §3 THE TWIN'S CHARGERS ARE UP 93.7% OF THE TIME (G405; 0659) ════════════════════════════════════════════════
--
--   60 twin-depot runs of the last 7 days whose events span 4 to 24 sim-hours (6): 1,254 faults in 16,519 sessions
--   (7.6%), mean repair 104 minutes, median 61; charger time lost = each fault's own repair minutes against 45
--   chargers over the run's span: **uptime 93.7% pooled, 89.0% at the 10th-percentile run, 86.9% at the worst**. That
--   is with the plan's declared depot discounts (session faults 4x rarer than the public corpus, repairs 50x faster).
--   A public charger built with federal money must be up more than 97% of the time (23 CFR 680.116(b),
--   https://www.law.cornell.edu/cfr/text/23/680.116, read 2026-10-10). 0659 makes depot-grade (>97%) a dial, with
--   today's profile kept as the stress case, and registers the before/after pair. The runs are not independent
--   observations (pairs share seeds, G153); the 93.7% is a level to calibrate against, not a rate with a range.
--
-- ══ §4 A DRY RUN THAT WAITED ON THE SWEEP ════════════════════════════════════════════════════════════════════════
--
--   A rolled-back dry run of 0659's V1 probe (delete one stopped run's fault card, deal it again) hit the connector's
--   60 s limit at about 12:05 AM CT (05:05 UTC) and left nothing behind (pg_stat_activity showed only the sweep runner). The connector
--   runs a statement outside a transaction block, so SET LOCAL lock_timeout did nothing, and the DELETE most likely
--   waited on a card row the throughput sweep's hour-long transaction holds while it purges recent runs. 0657's dry
--   run did the same on vehicles. Rule kept: inside the sweep window (11 PM-6 AM CT), touch no run-scoped row, even of
--   a stopped run.
--
-- ══ REPRODUCE ══

-- (1) every catalogued variable: how it is dealt, whether a fitted distribution sits under its name, and its cards
WITH cards AS (SELECT var_key, count(*) n FROM public.ottoq_variability_cards GROUP BY var_key)
SELECT c.var_key, c.lifespan, c.unit, c.min_value, c.max_value, COALESCE(k.n, 0) AS cards,
       EXISTS (SELECT 1 FROM public.ottoq_calibration_distributions d WHERE d.variable_name = c.var_key) AS has_dist,
       (SELECT count(*) FROM pg_proc p WHERE p.prosrc ~ ('ottoq_twin_deal\s*\([^)]*''' || c.var_key || '''')) AS deal_sites
  FROM public.ottoq_variability_catalog c LEFT JOIN cards k ON k.var_key = c.var_key
 ORDER BY COALESCE(k.n, 0) DESC, c.var_key;

-- (2) the three service-time cards feed the visit's durations; cloud cover's fallback is never reached
SELECT regexp_replace(substring(p.prosrc FROM strpos(p.prosrc, 'v_wash_min :=') FOR 420), '\s+', ' ', 'g') AS durations
  FROM pg_proc p WHERE p.proname = 'ottoq_derive_visit_needs';
SELECT regexp_replace(substring(p.prosrc FROM strpos(p.prosrc, 'v_cloud_pct := COALESCE') FOR 260), '\s+', ' ', 'g') AS cloud
  FROM pg_proc p WHERE p.proname = 'ottoq_sim_advance_weather_and_solar';

-- (3) what the corpus holds
SELECT variable_name, dataset_code, units, count(*) AS segments, sum(sample_count) AS samples
  FROM public.ottoq_calibration_distributions GROUP BY 1, 2, 3 ORDER BY 2, 1;

-- (4) the tariff rows the twin bills
SELECT depot_id, season, demand_first_block_usd_kw, demand_excess_usd_kw, fixed_monthly_usd, energy_base_cents_kwh,
       effective_from FROM public.ottoq_depot_tariffs
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND schedule_code = 'NES_GSA_3' ORDER BY season;

-- (5) which functions read which tariff fields
SELECT n.nspname || '.' || p.proname AS fn, p.prosrc ~ 'energy_base_cents_kwh' AS energy_base,
       p.prosrc ~ 'fixed_monthly_usd' AS fixed, p.prosrc ~ 'demand_first_block_usd_kw' AS first_block,
       p.prosrc ~ 'demand_excess_usd_kw' AS excess
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prosrc ~ 'ottoq_depot_tariffs|demand_(first_block|excess)_usd_kw|energy_base_cents_kwh' ORDER BY 1;

-- (6) charger uptime on the twin depot's recent runs, each run over its own events' sim span
WITH runs AS (SELECT r.sim_run_id FROM public.ottoq_sim_runs r
               WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.started_at > now() - interval '7 days'),
span AS (SELECT e.sim_run_id, extract(epoch FROM (max(e.sim_clock_at) - min(e.sim_clock_at))) / 60.0 AS sim_min
           FROM public.ottoq_events e JOIN runs USING (sim_run_id) WHERE e.sim_clock_at IS NOT NULL GROUP BY e.sim_run_id),
runs2 AS (SELECT * FROM span WHERE sim_min BETWEEN 240 AND 4320),
f AS (SELECT e.sim_run_id, count(*) AS faults, sum(COALESCE((e.payload ->> 'repair_minutes')::numeric, 75)) AS lost_min
        FROM public.ottoq_events e JOIN runs2 USING (sim_run_id) WHERE e.event_type = 'charge.session_faulted' GROUP BY 1),
s AS (SELECT o.sim_run_id, count(*) AS sessions FROM public.ocpp_sessions o JOIN runs2 USING (sim_run_id) GROUP BY 1)
SELECT count(*) AS runs, sum(COALESCE(f.faults, 0)) AS faults, sum(COALESCE(s.sessions, 0)) AS sessions,
       round((1 - sum(COALESCE(f.lost_min, 0)) / sum(45 * r.sim_min))::numeric, 4) AS uptime_pooled,
       round(percentile_cont(0.1) WITHIN GROUP (ORDER BY (1 - COALESCE(f.lost_min, 0) / (45 * r.sim_min)))::numeric, 4) AS p10_run,
       round(min(1 - COALESCE(f.lost_min, 0) / (45 * r.sim_min))::numeric, 4) AS worst_run
  FROM runs2 r LEFT JOIN f USING (sim_run_id) LEFT JOIN s USING (sim_run_id);
