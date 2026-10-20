-- 0458  **The 20-post depot 0567 measured cannot be built; the buildable one re-stripes canopy B and gives up five standard
--        chargers that carried a sixth to a quarter of the standard chargers' energy; and a base change would have
--        rewritten every past day's re-score.** -> G477, built as db/migrations/0759 (PENDING, Chase's call).
--        Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-19 between 9:40 and 10:32 AM CT (14:40:22 UTC by `date`, 15:32:41
--        UTC by the last query's clock), outside the sweep window. Every claim names its query.
--
-- ══ §1 THE DRAWING (no query: the renderer's own constants, ottoyarddepot-sim at commit 7a19117) ══════════════════════
--
--   src/lib/sitePlan.ts:272 DCFC_ROW_PITCH = 14 and :274 L2_ROW_PITCH = 8.4 render units; at the rows' 60-degree heading
--   the standard pitch is 7.27 units square to the car (:336's own comment). src/lib/ottoChargeArm/cobotSpec.ts:183
--   FLANK_STANDOFF_PU = 3.9 and :186 PEDESTAL_OFFSET_PU = FLANK_STANDOFF_PU + CAR_WIDTH / 2, with CAR_BODY_WIDTH = 4.0 at
--   src/engine/motion/traffic.ts:54: the robotic charger's pedestal stands 5.9 units from its car's centreline. The next
--   car's near flank is 7.27 - 2.0 = 5.27 units away on the standard pitch, so 0567's in-place conversion puts the pedestal
--   inside the next car; on the fast chargers' pitch (12.12 units square) the flank is 10.12 units away. Each canopy holds
--   ten posts on canopy A's pattern (two columns of five, rows 88..144): the site's ceiling is 30, and 40 do not fit.
--
-- ══ §2 WHAT THE FIVE SPACES THE BUILDABLE 20 RETIRES CARRIED (reproduce: (1), (2)) ════════════════════════════════════
--
--   (1), at 10:32 AM CT: the 39 complete dcfc20 arms at the twin depot (26 distinct days; a cell repeated on its seed
--   replays the same day). dcfc20 converts NASH-L2-STALL-01..10, so on those days the standard chargers were 11..15 and
--   canopy C's fifteen. NASH-L2-STALL-11..15 delivered 17.0-26.4% of the standard chargers' energy; arm 109 (seed 2,
--   2026-10-19) 300 of 1,766 kWh, arm 86 (2026-10-17) 495 of 1,913.
--   (2), between 9:58 and 9:59 AM CT, sampled every five sim-minutes: all twenty standard chargers were in use at once on
--   every arm; more than fifteen were in use for 85-930 minutes of the day (4.92-52.33 car-hours beyond fifteen), from the
--   day's first or second tick (11:05-11:10 sim); and in 5-81 samples the cars beyond fifteen outnumbered the fast
--   chargers idle at that moment (arm 77: 580 minutes, 32.00 car-hours, 5.63 fast chargers idle on average when over, 17
--   samples; arm 86: 335, 14.00, 6.33, 6; arm 94: 125, 9.25, 3.56, 14; arm 109: 320, 17.33, 4.52, 18). Read off the
--   recorded days, not re-run: on the 15-standard base the kernel would seat those cars otherwise, and some would wait.
--
-- ══ §3 A BASE CHANGE REWRITES THE PAST FOR A READER OF TODAY'S STALL TABLE (reproduce: (3), (4)) ═════════════════════
--
--   public.ottoq_throughput_scorecard classifies a day's sessions by today's stalls.stall_type, correcting only the
--   converted ids its receipt names, and counts a receipt-less day's fast chargers from today's stalls. (4): 195 of the
--   twin depot's completed runs carry no receipt. After a base change, an old dcfc10 or receipt-less day would read its
--   sessions on the re-striped spaces as fast charges and its fast chargers as 20. 0759 fixes the scorecard (a base
--   history and ottoq_stall_type_at). (3): 24 STABLE functions name stall_type beside a run and a session or booking
--   table; most read a live run's present, where today's type is right; ottoq_charge_order_realized grades a past order
--   by today's types, and ottoq_charger_fit_profile (no caller) reads past sessions the same way. Not patched by 0759.
--   The scorecard's own callees read no stall type (the KPI functions and their six views; ottoq_kpi_five_raw names
--   "stalls" only in a string), so 0759's V5 compares whole scorecards before and after.
--
-- ══ §4 COLUMNS NOTHING MAINTAINS (reproduce: (5)) ═════════════════════════════════════════════════════════════════════
--
--   distance_from_entrance is read by nine functions (choosers order by it) and written by nothing since 0010; 0759 gives
--   the new posts values interpolated along each column. absolute_point is read only by twin.ottoq_grid_fixture_create.
--   NASH-L2-21..25 have had no stall since 0010 and were never decommissioned; twin.ottoq_sim_seed_fleet marks every
--   depot charger Available at each run start (it does not read decommissioned_at), and so it will NASH-L2-11..15 after
--   0759. No stall points at them, so nothing seats a car there. stall_kind is read by five functions, the two recall
--   functions counting 'charging'; 'parking' is named only by ottoq.ottoq_record_enacted_booking, which maps it to
--   staging for a booking's class.

-- (1) the dcfc20 arms: the share of the standard chargers' energy NASH-L2-STALL-11..15 delivered
WITH arms AS (
  SELECT a.arm_id, a.sim_run_id
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
   WHERE c.buildout_code = 'dcfc20' AND a.complete AND s.depot_id = '11111111-1111-1111-1111-111111111111'
), x AS (
  SELECT a.arm_id,
         CASE WHEN st.stall_code IN ('NASH-L2-STALL-11','NASH-L2-STALL-12','NASH-L2-STALL-13','NASH-L2-STALL-14','NASH-L2-STALL-15')
              THEN 'b' WHEN st.canopy_code = 'CANOPY-03' THEN 'c' END AS grp,
         o.energy_delivered_kwh AS kwh, extract(epoch FROM (o.ended_at - o.started_at)) / 3600.0 AS h
    FROM arms a JOIN public.ocpp_sessions o ON o.sim_run_id = a.sim_run_id
    JOIN public.stalls st ON st.id = o.stall_id
   WHERE st.stall_type = 'l2' AND o.started_at IS NOT NULL
), per AS (
  SELECT a.arm_id,
         count(*) FILTER (WHERE grp = 'b') AS s_b, round(sum(h) FILTER (WHERE grp = 'b')::numeric, 1) AS h_b,
         round(sum(kwh) FILTER (WHERE grp = 'b')::numeric, 0) AS kwh_b,
         count(*) FILTER (WHERE grp = 'c') AS s_c, round(sum(h) FILTER (WHERE grp = 'c')::numeric, 1) AS h_c,
         round(sum(kwh) FILTER (WHERE grp = 'c')::numeric, 0) AS kwh_c,
         round(100.0 * sum(kwh) FILTER (WHERE grp = 'b') / NULLIF(sum(kwh) FILTER (WHERE grp IN ('b', 'c')), 0), 1) AS pct_b
    FROM arms a LEFT JOIN x ON x.arm_id = a.arm_id GROUP BY a.arm_id
)
SELECT count(*) AS arms, count(DISTINCT (s_b, h_b, kwh_b, s_c, h_c, kwh_c)) AS distinct_days,
       min(pct_b) AS min_pct, max(pct_b) AS max_pct,
       (SELECT s_b || '/' || kwh_b || '/' || (kwh_b + kwh_c) || '/' || pct_b FROM per WHERE arm_id = 109) AS arm109,
       (SELECT s_b || '/' || kwh_b || '/' || (kwh_b + kwh_c) || '/' || pct_b FROM per WHERE arm_id = 86) AS arm86,
       now() AS at_utc
  FROM per;
-- read 15:32:41 UTC: 39 arms, 26 distinct days, 17.0-26.4%, arm 109 19 sessions / 300 of 1,766 kWh / 17.0%,
-- arm 86 25 / 495 of 1,913 / 25.9%.

-- (2) the standard chargers in use at once, every five sim-minutes, against the fast chargers idle then
WITH arms AS (
  SELECT a.arm_id, a.sim_run_id, sr.sim_clock_start, sr.sim_clock_current
    FROM public.ottoq_throughput_sweep_arms a
    JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
    JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
    JOIN public.ottoq_sim_runs sr ON sr.sim_run_id = a.sim_run_id
   WHERE c.buildout_code = 'dcfc20' AND a.complete AND s.depot_id = '11111111-1111-1111-1111-111111111111'
), x AS (
  SELECT a.arm_id, o.started_at, COALESCE(o.ended_at, a.sim_clock_current) AS ended_at,
         CASE WHEN st.stall_type = 'dcfc' OR st.stall_code IN ('NASH-L2-STALL-01','NASH-L2-STALL-02','NASH-L2-STALL-03',
                                                             'NASH-L2-STALL-04','NASH-L2-STALL-05','NASH-L2-STALL-06',
                                                             'NASH-L2-STALL-07','NASH-L2-STALL-08','NASH-L2-STALL-09',
                                                             'NASH-L2-STALL-10')
              THEN 'dc' ELSE 'l2' END AS k
    FROM arms a JOIN public.ocpp_sessions o ON o.sim_run_id = a.sim_run_id
    JOIN public.stalls st ON st.id = o.stall_id
   WHERE o.started_at IS NOT NULL AND st.stall_type IN ('dcfc', 'l2')
), t AS (
  SELECT a.arm_id, g AS at FROM arms a, generate_series(a.sim_clock_start, a.sim_clock_current, interval '5 minutes') g
), n AS (
  SELECT t.arm_id, t.at, count(*) FILTER (WHERE x.k = 'l2') AS l2, count(*) FILTER (WHERE x.k = 'dc') AS dc
    FROM t LEFT JOIN x ON x.arm_id = t.arm_id AND x.started_at <= t.at AND x.ended_at > t.at
   GROUP BY t.arm_id, t.at
)
SELECT arm_id, count(*) AS samples, max(l2) AS peak_l2, count(*) FILTER (WHERE l2 > 15) * 5 AS min_over_15,
       round(sum(GREATEST(l2 - 15, 0)) * 5 / 60.0, 2) AS car_h_over_15,
       round(avg(20 - dc) FILTER (WHERE l2 > 15), 2) AS idle_dc_when_over,
       count(*) FILTER (WHERE l2 - 15 > 20 - dc) AS samples_overflow_gt_idle_dc,
       min(at) FILTER (WHERE l2 > 15) AS first_over
  FROM n GROUP BY arm_id ORDER BY arm_id;
-- read between 14:58:30 and 14:59:20 UTC: 39 rows; peak_l2 20 on every arm; min_over_15 85-930; car_h_over_15
-- 4.92-52.33; samples_overflow_gt_idle_dc 5-81; first_over 11:05 or 11:10 sim.

-- (3) the readers that classify by stall_type beside a run and a session or booking table (comments stripped)
WITH f AS (
  SELECT n.nspname || '.' || p.proname AS fn, p.provolatile::text AS vol,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.proname NOT LIKE 'ottoq_fn_backup%' AND p.prokind = 'f'
)
SELECT string_agg(fn, ', ' ORDER BY fn) AS readers, count(*) AS n
  FROM f
 WHERE src ~ 'stall_type' AND src ~ '(p_run|p_sim_run_id|sim_run_id\s*=)' AND src ~ '(ocpp_sessions|ottoq_stall_bookings|ottoq_charge_sessions)'
   AND vol = 's';
-- read: 24, among them public.ottoq_throughput_scorecard, public.ottoq_charge_order_realized and
-- public.ottoq_charger_fit_profile.

-- (4) the twin depot's completed runs by receipt
SELECT COALESCE(sr.payload->'site_buildout'->>'buildout_code', '<none>') AS bo, count(*) AS runs
  FROM public.ottoq_sim_runs sr
 WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111' AND sr.status = 'completed'
 GROUP BY 1 ORDER BY 1;
-- read: <none> 195, dcfc10 51, dcfc20 42, dcfc40 10, dcfc40_cab2400 7.

-- (5) who reads the columns a base change moves (comments stripped)
WITH f AS (
  SELECT n.nspname || '.' || p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.proname NOT LIKE 'ottoq_fn_backup%' AND p.prokind = 'f'
)
SELECT 'distance_from_entrance' AS k, string_agg(fn, ', ' ORDER BY fn) AS v FROM f WHERE src ~ 'distance_from_entrance'
UNION ALL SELECT 'absolute_point', string_agg(fn, ', ' ORDER BY fn) FROM f WHERE src ~ 'absolute_point'
UNION ALL SELECT 'decommissioned_at', string_agg(fn, ', ' ORDER BY fn) FROM f WHERE src ~ 'decommissioned_at'
UNION ALL SELECT 'stall_kind', string_agg(fn, ', ' ORDER BY fn) FROM f WHERE src ~ 'stall_kind'
UNION ALL SELECT 'parking', string_agg(fn, ', ' ORDER BY fn) FROM f WHERE src ~ $r$'parking'$r$;
-- read: distance_from_entrance 9 functions (ottoq_book_appointment, ottoq_reconcile_bay_reservations,
-- ottoq_reconcile_displace_stale_claim, ottoq_sim_prearrival_contracts, ottoq_stage_after_tow_retrieval,
-- ottoq_stall_free_between, ottoq_yield_bay_holds, ottoq_decide_tick, ottoq_l2_optimize_assignments); absolute_point
-- twin.ottoq_grid_fixture_create; decommissioned_at ottoq_agent_wake and ottoq_forecast_ev_queue_kw only; stall_kind
-- ottoq_depot_cards, the two recall functions, ottoq_shield_and_log, workload_harness_metrics; 'parking'
-- ottoq.ottoq_record_enacted_booking.
