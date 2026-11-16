-- 0497  **G552 is closed. On a check run the wash triage's new visits kept every arm deep clean it replaced (6 carried,
--        6 raised again), and no car left without its clean. 0840's canopy boards were read live for the first time,
--        and TX-AUX equals the sum of its leaves on every tick.**
--        Production database, 2026-11-16 16:37 to 16:53 UTC (10:37 to 10:53 AM CT). Rule 8: the twin depot. Rule 12: one
--        demo run started to see two finished changes working, read, and stopped; no pair, no sweep. One seed: readings,
--        not ranges.
--
-- ══ (1) THE CHANGE ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0841 (ledger 20261116163709, 10:37 AM CT): ottoq.ottoq_derive_visit_needs's 0698 carry matches the run as
--   COALESCE(p_sim_run_id, v_run), where it matched the caller's p_sim_run_id as passed. The wash triage passes no run id,
--   so on its path the carry had found nothing while the unscoped supersede closed the car's visit (G552, db/checks/0496
--   (5); 0200 had recorded the gap). At the apply, V3's probe on a twin car: on the body as it was nothing was carried
--   and the departure test let the car leave; patched, the deep clean was carried, under way, and the car was held.
--
-- ══ (2) THE CHECK RUN: 265ff1e5 ══════════════════════════════════════════════════════════════════════════════════════
--
--   Started by me through the cockpit's own doors: public.ottoq_operator_start_run('busy_day', seed, 'operator_demo'),
--   then ottoq_set_playback live at 8x, as a cockpit run is played. The seed is 6f9a1b0e's (2934934160383281539), so the
--   morning starts from the same world. Live 16:39 to 16:53 UTC; read at tick 151 (101 sim-minutes, 8:00 to 9:41 AM CT
--   in the twin's day), then stopped through public.ottoq_sim_stop_and_reset (archived, the depot reset to empty, 23
--   sessions ended). Neither door purges a prior run; the runs 0496 read are still in the database.
--   Live playback is not a replay: a tick's sim length follows the database's load, so the two runs part after the first
--   tick (CLAUDE.md 2.5). What is compared is the same path, counted the same way (Q1).
--
--   An arm's deep clean left under way on a visit that was then replaced:
--                                          6f9a1b0e (before)   5ea96a57 (before)   265ff1e5 (after 0841)
--     cases                                      11                  13                  12
--     the next visit carried it                   0                   0                   6
--     the next visit raised it again              7                   7                   6
--     the next visit did not have it              4                   4                   0
--     the car left before the clean was done      4                   4                   0
--     the clean done before the car left          7                   7                  12
--   (5ea96a57's 13 include 2 with no departure before the run stopped; its other columns are as 0496 Q4 read them.)
--   265ff1e5 was read before the stop. Q1 re-run after it reads 13: the stop closes the run's open visits, and one more
--   routine (sim 9:41 AM CT) was under way at that moment, with no next visit and no departure. And a slip of mine,
--   caught on that re-run: my first query sorted "carried" against "raised again" with bool_or over the next visit's
--   atoms, which is NULL over none and so put a next visit without the clean under "raised again". Q1 as written
--   below tests each case with EXISTS; it reads 6 carried, 6 raised again, 0 without the clean (and the 1 at the stop).
--   On 265ff1e5 the 12 fell between sim 8:07 and 9:13 AM CT. The 6 carried cleans were all finished by the arm, none
--   interrupted: in each the car stayed on its post while its visit was derived again. Before 0841 each of those was
--   dropped in the middle of its routine (Q2).
--
-- ══ (3) 0840, READ LIVE ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   159 ticks on 265ff1e5 (Q3):
--     - TX-AUX's flow equals the sum of its six leaves (the battery, the building, the solar and the three boards) on every
--       tick: the largest difference is 0.00 kW.
--     - The boards:   BOARD-A peak 48.7 kW (90% of 54), 23.8 kWh;  BOARD-B 48.7 kW (90%), 20.6 kWh;  BOARD-C 43.4 kW (80%),
--       20.8 kWh. Together: 140.8 kW at the most, 38.8 kW on average, 65.2 kWh of the 2,161 kWh the service read over 1.70
--       sim-hours (3.0%, a busy morning).
--   The twin's Power tab (ottoyarddepot-sim PR #178, run locally against production's live answer at sim 8:10 AM CT):
--   TX-AUX's boxes read BLDG 85, BATT +223, SOLAR +52 and BOARDS 72 (the boards' live 16.9 + 27.5 + 27.5); its card lists
--   each board on its own line.
--
-- ══ (4) WHAT IS NOT VERIFIED, AND WHAT IS OPEN ═══════════════════════════════════════════════════════════════════════
--
--   (a) One run, one seed, 101 sim-minutes: the morning surge, where every G552 case on the earlier runs fell, not a whole
--       day.
--   (b) The replaced visit keeps its own copy of a carried atom, still in_progress (the carry copies; it does not move).
--       It holds no car, since the departure test reads the live visit, but a reader of atoms on every visit counts it:
--       0840's board counts its arm at work until its planned end (0496 Q6's bound).
--   (c) The deriver's other carry, from a 'carried_over' visit (0193's scope), still matches the caller's run id. Its gap is
--       0200's, recorded. Today it costs nothing: the table holds no 'carried_over' visit, and the only functions that
--       name the status (comment-stripped scan) read it: the deriver and the agent board.
--   (d) G553 (a deep clean and a tidy on one arm at once) is open.
--
-- ══ THE QUERIES ══════════════════════════════════════════════════════════════════════════════════════════════════════

-- Q1 a run's arm deep cleans left under way on a replaced visit, and what became of each
WITH v AS (
  SELECT vn.*, lead(vn.visit_id) OVER (PARTITION BY vn.vehicle_id ORDER BY vn.created_at, vn.visit_key) AS next_visit
    FROM public.ottoq_visit_needs vn
   WHERE vn.sim_run_id = '265ff1e5-f573-49b5-9b9a-f23c7422539e' AND vn.depot_id = '11111111-1111-1111-1111-111111111111'),
s AS (
  SELECT v.vehicle_id, v.next_visit, (r->>'started_at')::timestamptz AS started
    FROM v CROSS JOIN LATERAL jsonb_array_elements(v.atoms) r
   WHERE v.status = 'superseded' AND r->>'performed_by' = 'stall_cabin_robot' AND r->>'svc' = 'interior_deep_clean'
     AND r->>'status' = 'in_progress' AND r->>'done_at' IS NULL),
j AS (
  SELECT s.*,
         CASE WHEN s.next_visit IS NULL THEN 'no next visit'
              WHEN EXISTS (SELECT 1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                            WHERE n.visit_id = s.next_visit AND a->>'svc' = 'interior_deep_clean'
                              AND COALESCE((a->>'carried')::boolean, false)) THEN 'carried'
              WHEN EXISTS (SELECT 1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                            WHERE n.visit_id = s.next_visit AND a->>'svc' = 'interior_deep_clean') THEN 'raised again'
              ELSE 'did not have it' END AS next_has,
         (SELECT min((a->>'done_at')::timestamptz) FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
           WHERE n.vehicle_id = s.vehicle_id AND n.sim_run_id = '265ff1e5-f573-49b5-9b9a-f23c7422539e'
             AND a->>'svc' = 'interior_deep_clean' AND a->>'status' = 'done' AND (a->>'done_at')::timestamptz > s.started) AS done_at,
         (SELECT min(x.dispatched_at) FROM public.ottoq_vehicle_dispatches x WHERE x.vehicle_id = s.vehicle_id
            AND x.sim_run_id = '265ff1e5-f573-49b5-9b9a-f23c7422539e' AND x.dispatched_at >= s.started) AS left_at
    FROM s)
SELECT next_has, count(*) AS cases,
       count(*) FILTER (WHERE left_at IS NOT NULL AND (done_at IS NULL OR left_at < done_at)) AS left_before_done,
       count(*) FILTER (WHERE done_at IS NOT NULL AND (left_at IS NULL OR done_at <= left_at)) AS done_before_leaving
  FROM j GROUP BY 1 ORDER BY 1;

-- Q2 how the carried atoms ended
SELECT a->>'svc' AS svc, COALESCE(a->>'status', 'pending') AS status, (a ? 'interrupted') AS was_interrupted,
       a->>'performed_by' AS by, count(*)
  FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
 WHERE n.sim_run_id = '265ff1e5-f573-49b5-9b9a-f23c7422539e' AND COALESCE((a->>'carried')::boolean, false)
 GROUP BY 1, 2, 3, 4;

-- Q3 0840 live: TX-AUX against the sum of its leaves on every tick, and each board's study
WITH t AS (SELECT sim_clock_at, node_code, kw_ac FROM public.ottoq_power_node_ticks
            WHERE sim_run_id = '265ff1e5-f573-49b5-9b9a-f23c7422539e'),
per AS (SELECT a.sim_clock_at, a.kw_ac AS aux,
               (SELECT sum(l.kw_ac) FROM t l WHERE l.sim_clock_at = a.sim_clock_at AND l.node_code IN
                  (SELECT node_code FROM public.ottoq_power_nodes
                    WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND parent_code = 'TX-AUX')) AS leaves_sum,
               (SELECT sum(l.kw_ac) FROM t l WHERE l.sim_clock_at = a.sim_clock_at AND l.node_code LIKE 'BOARD-%') AS boards
          FROM t a WHERE a.node_code = 'TX-AUX')
SELECT count(*) AS ticks, max(abs(aux - leaves_sum)) AS max_abs_diff_kw, max(boards) AS boards_peak_kw,
       round(avg(boards), 2) AS boards_mean_kw,
       (SELECT jsonb_object_agg(node_code, jsonb_build_object('peak_kw', round(peak_kw_ac, 1), 'kwh', round(energy_kwh_ac, 1)))
          FROM public.ottoq_power_node_study
         WHERE sim_run_id = '265ff1e5-f573-49b5-9b9a-f23c7422539e' AND kind = 'canopy_board') AS boards_study
  FROM per;
