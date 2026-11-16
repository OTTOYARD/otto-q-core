-- 0496  **Each fast-charger canopy's board is on the one-line. On a finished day its arms drew 43 to 49 kW at their
--        busiest, and the arms' own records showed 8 cars on 2 runs leaving the depot with a deep clean still to do.**
--        Production database, 2026-11-16 14:56 to 15:42 UTC (8:56 to 9:42 AM CT), read-only, after 0840's apply at
--        14:54:57 UTC. Rule 8: the twin depot. Rule 12: a replay of finished runs through a read-only function and a
--        probe that was rolled back; no run started, no pair, no sweep. Each run is one seed: readings, not ranges.
--
--   Chase, 2026-11-16, on the follow-up from ottoyarddepot-sim PR #177 (the canopy boards placed and fed from TX-AUX):
--   "Sure, keep building what you see necessary."
--
-- ══ (1) WHAT WAS THERE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   0810's one-line at the twin depot: SERVICE (13.8 kV), MV-SWGR, six charger transformers (TX-A1 to TX-C2, 5 posts
--   each) and TX-AUX (2,500 kVA) with the battery (1,500 kW), the building (250 kW) and the canopy solar (600 kW). TX-AUX
--   was sized for 1,750 kW connected. The design rule and the tree agreed, both ways.
--   ottoyarddepot-sim PR #177 (merged 6:52 AM CT that day) put a board under each fast-charger canopy's south end, fed
--   from TX-AUX: 54 kW a board, its 10 OTTO-CLEAN ARMs at 2.4 kW each and their vacuum producer at 3 kW a working arm,
--   480 V, power factor 0.9 (ASSUMPTION). The engine had no such load.
--   An arm's work is an atom on its car's visit (ottoq_visit_needs.atoms): performed_by 'stall_cabin_robot', its
--   robot_stall_id, started_at, ends_at, done_at when done, status.
--
-- ══ (2) WHAT WAS CHANGED: 0840, ledger 20261116145457 (8:54 AM CT) ═══════════════════════════════════════════════════
--
--   (a) kind 'canopy_board' on ottoq_power_nodes. (b) The design rule gives BOARD-A, BOARD-B and BOARD-C under TX-AUX at
--   54 kW each and counts them in TX-AUX's connected load: 1,750 to 1,912 kW. 2,500 kVA still covers 125% of it
--   (1,912 x 1.25 / 0.97 = 2,464 kVA). (c) public.ottoq_power_canopy_board_load(depot, run, clock), read-only: each
--   board's arms at work at that instant (counted once a stall) and its load. (d) ottoq_power_capture reads each board as
--   a leaf, so TX-AUX's flow and temperature and the service's reading carry the arms.
--   A dry run of the same statements, ending in ROLLBACK, ran first (V1-V6 passed, nothing persisted). The apply passed
--   on the first send, between runs. The ledger holds the file from BEGIN to COMMIT byte for byte, and the three stored
--   bodies hash as the file's (0840's APPLIED note).
--
-- ══ (3) WHAT A FINISHED DAY SAYS: run 6f9a1b0e (busy_day, 763 ticks, 9.07 sim-hours, 324 arm atoms) ═══════════════
--
--   Its 763 snapshot instants, replayed through the board-load function after the apply (Q1, Q2):
--                                        BOARD-A   BOARD-B   BOARD-C
--     the most arms at work at once         8         9         8
--     peak kW                             43.4      48.7      43.4      (of 54 kW rated: 80%, 90%, 80%)
--     mean kW                              8.32      8.31      8.34
--     mean arms at work                    1.38      1.38      1.38
--     instants with any arm at work       76.0%     71.6%     67.9%
--   Together: at most 124.9 kW, with 23 arms at work, at sim 14:11 UTC (8:11 AM CT in the twin's day, its morning
--   surge); 217.2 kWh over the run, 1.6% of the 13,827.0 kWh the service read for that day.
--   TX-AUX with the boards (Q2, its own 763 ticks from that run plus the boards at each instant): TX-AUX's busiest
--   moment is the battery discharging, 957.2 kW flowing up to the switchgear. The boards are on the same 480 V bus, so
--   they take from that flow: 952.7 kW with them. Its largest forward flow rises from 240.3 to 266.7 kW. So the boards
--   do not raise TX-AUX's peak; they are a small load on a unit whose largest duty is the battery.
--   Counted by atom, CANOPY-01 reads 10 at one instant against 8 arms: on each canopy, at 59 to 64 of the 763 instants,
--   two arm atoms were open on one stall. A board counts arms (distinct stalls). Section (5) has why there were two.
--
-- ══ (4) WHO READS THE BOARDS, AND WHAT IT COSTS A TICK ═══════════════════════════════════════════════════════════════
--
--   Every function that reads the tree (comment-stripped prosrc scan, Q3): the board-load function, the capture,
--   ottoq_power_one_line (the cockpits' read), ottoq_power_resilience, ottoq_power_rightsize, ottoq_twin_trip_power_node.
--   - ottoq_power_one_line is generic: a board comes back with its title, rating, the tick at the one-line's clock and
--     its study row. Runs measured before the apply show the boards with no reading.
--   - ottoq_power_rightsize reads TX-AUX's own ticks, which now carry the boards; nothing to change.
--   - ottoq_power_resilience reads only transformers with posts under them; TX-AUX has none.
--   - ottoq_twin_trip_power_node trips the posts under a node; a board has none.
--   None of them decides anything for a car (rule 13). The tick's trigger (ottoq_power_capture_tick) catches any error
--   from the capture and raises a warning, so a board can never stop a tick.
--   Cost: the board-load function took 10.4 ms at the last instant of 6f9a1b0e (1,670 buffers, all from cache). It reads
--   the run's visits, so it grows with the length of the run.
--
-- ══ (5) WHAT THE ARMS' ATOMS SHOWED: TWO FINDINGS, ONE OF THEM RULE 9 ═════════════════════════════════════════════
--
--   G552 (rule 9). WHEN A CAR'S VISIT IS REPLACED WHILE AN ARM IS CLEANING IT, THE ROUTINE IS LEFT OPEN ON THE OLD VISIT
--   AND IS NOT ON THE NEW ONE, AND THE CAR CAN LEAVE WITH THE CLEAN NOT DONE (Q4, Q5).
--     Every routine left 'in_progress' with no done_at, on the three runs still in the database:
--                                   interrupted   left before    done before    no departure
--                                   deep cleans   it was done    leaving        after (run ended)
--       5ea96a57 (138 ticks)            13             4              7               2
--       6f9a1b0e (763 ticks)            11             4              7               0
--       bf447eb4 (87 ticks)             11             0              0              11
--     And 3, 4 and 3 interior tidies left open, all at a run's end with no departure after.
--     On 6f9a1b0e, all 11 deep cleans were interrupted in the run's first 72 sim-minutes, on visits that were then
--     replaced. Each atom says must_do true, deferrable false, raised in the depot by the needs card. For the 7 cars
--     that had it done before leaving, the visit that replaced theirs carried the deep clean again. For the other 4 it
--     did not (Q5: readiness_check and interior_inspection, with a tidy, a triage check or a sensor clean), and the
--     departure test reads the car's live visit. So 4 cars left with it:
--       car        clean interrupted   left the depot   back      clean done
--       1b9b6ea1   14:05               14:16            15:30     16:21
--       1225f10e   14:21               14:56            16:06     17:38
--       c8ae20e3   14:49               15:34            16:46     19:59
--       a1111111   14:52               15:31            16:43     19:57
--     (sim UTC; each left at 100% charge; each clean was done by an arm on a later visit after the car came back.)
--     0839 (an arm routine cut short is owed and finished before the car leaves) was live on both runs and did not
--     catch these: the routine was not cut short on its visit, its visit was replaced under it.
--     For the boards: an open atom counts its arm at work until its planned end. On 6f9a1b0e that is at most 91.0 of
--     the 2,185.2 arm-minutes counted (4.2%; Q6). The bound includes the work done before each interruption, so the
--     true overcount is smaller.
--     NOT FIXED HERE. It is the engine's visit replacement and departure test, not the one-line: its own migration.
--
--   G553. ON 9 VISITS, AN INTERIOR DEEP CLEAN AND AN INTERIOR TIDY RAN ON THE SAME ARM AT THE SAME TIME (Q7). All on
--     6f9a1b0e, both done, overlapping 9.7 minutes on average, 10.8 at the most. An arm does one routine at a time:
--     either the tidy is part of the deep clean and should not run beside it, or the two run one after the other. The
--     engine's timeline gives the arm that overlap for free. A board counts the arm once, so its power is not doubled.
--     NOT CHANGED HERE: which of the two is right is the cabin model's decision (0817, 0821, 0822).
--
-- ══ (6) WHAT IS NOT VERIFIED, AND WHAT IS OPEN ════════════════════════════════════════════════════════════════════
--
--   (a) No run has been measured live since the apply. The capture was proven at the apply on one instant with no run
--       (V5: each idle board 1.0 kW, TX-AUX 253 kW) and the board-load function on a finished run (above). The first
--       run after the apply is the first live reading: Q8 reads it.
--   (b) Every board figure is an assumption: the arm's 2.4 kW and the producer's 3 kW a working arm are the clean arm
--       CAD's, the 0.1 kW standby and the 0.9 power factor are typical values. The producer is modelled per working
--       arm; a real central producer likely draws a base load whenever any arm works. Replace with the chosen units'
--       sheets.
--   (c) A board's load follows the engine's plan for each routine (started_at to done_at, or to ends_at while open),
--       not a meter. G552's open atoms show where the plan and the arm part.
--   (d) The twin's Power tab drops a kind it does not know, so it shows no board until ottoyarddepot-sim learns the kind.
--   (e) G552 and G553 are open.
--
-- ══ THE QUERIES ══════════════════════════════════════════════════════════════════════════════════════════════════════

-- Q1 each board over a finished run's instants
WITH sn AS (SELECT DISTINCT s."timestamp" AS t FROM public.site_energy_snapshots s
             WHERE s.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3')
SELECT b.node_code, count(*) AS instants, max(b.working) AS most_working, round(avg(b.working), 2) AS mean_working,
       max(b.kw_ac) AS peak_kw, round(avg(b.kw_ac), 2) AS mean_kw,
       round(100.0 * count(*) FILTER (WHERE b.working > 0) / count(*), 1) AS pct_instants_any_arm
  FROM sn CROSS JOIN LATERAL public.ottoq_power_canopy_board_load('11111111-1111-1111-1111-111111111111',
       '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3', sn.t) b
 GROUP BY 1 ORDER BY 1;

-- Q2 the three boards together, and TX-AUX's own ticks with and without them
WITH sn AS (SELECT DISTINCT s."timestamp" AS t FROM public.site_energy_snapshots s
             WHERE s.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3'),
b AS (SELECT sn.t, sum(x.kw_ac) AS boards_kw, sum(x.working) AS arms
        FROM sn CROSS JOIN LATERAL public.ottoq_power_canopy_board_load('11111111-1111-1111-1111-111111111111',
             '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3', sn.t) x GROUP BY sn.t),
j AS (SELECT b.*, a.kw_ac AS aux_kw, a.dt_s FROM b LEFT JOIN public.ottoq_power_node_ticks a
        ON a.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3' AND a.node_code = 'TX-AUX' AND a.sim_clock_at = b.t)
SELECT max(boards_kw) AS boards_together_peak_kw, max(arms) AS arms_at_that_peak,
       round(sum(boards_kw * dt_s) / 3600.0, 1) AS boards_kwh,
       round(max(abs(aux_kw)), 1) AS aux_peak_without, round(max(abs(aux_kw + boards_kw)), 1) AS aux_peak_with,
       round(max(aux_kw), 1) AS aux_forward_without, round(max(aux_kw + boards_kw), 1) AS aux_forward_with
  FROM j;

-- Q3 every function that reads the tree (comments stripped)
SELECT n.nspname || '.' || p.proname AS fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'ottoq', 'twin')
   AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'ottoq_power_node(s|_study|_ticks)'
 GROUP BY 1 ORDER BY 1;

-- Q4 G552: every arm routine left open, and whether its car left before the same service was done
WITH stranded AS (
  SELECT DISTINCT vn.sim_run_id AS run, vn.vehicle_id, vn.visit_id, r->>'svc' AS svc, (r->>'started_at')::timestamptz AS stranded_at
    FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) r
   WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111'
     AND vn.sim_run_id IN ('6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3', 'bf447eb4-0572-460b-a479-3c9ca70939df',
                           '5ea96a57-4893-470e-b92a-00590755f7b7')
     AND r->>'performed_by' = 'stall_cabin_robot' AND r->>'status' = 'in_progress' AND r->>'done_at' IS NULL),
judged AS (
  SELECT s.*, (SELECT min((r->>'done_at')::timestamptz) FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) r
                WHERE vn.vehicle_id = s.vehicle_id AND vn.sim_run_id = s.run AND r->>'svc' = s.svc AND r->>'status' = 'done'
                  AND (r->>'done_at')::timestamptz > s.stranded_at) AS done_at,
         (SELECT min(x.dispatched_at) FROM public.ottoq_vehicle_dispatches x
           WHERE x.vehicle_id = s.vehicle_id AND x.sim_run_id = s.run AND x.dispatched_at >= s.stranded_at) AS next_out
    FROM stranded s)
SELECT left(run::text, 8) AS run, svc, count(*) AS stranded,
       count(*) FILTER (WHERE next_out IS NOT NULL AND (done_at IS NULL OR next_out < done_at)) AS left_before_done,
       count(*) FILTER (WHERE next_out IS NULL) AS no_departure_after,
       count(*) FILTER (WHERE done_at IS NOT NULL AND (next_out IS NULL OR done_at <= next_out)) AS done_before_leaving
  FROM judged GROUP BY 1, 2 ORDER BY 1, 2;

-- Q5 G552: the cars that left, with the visit that replaced the open routine's
WITH stranded AS (
  SELECT vn.vehicle_id, vn.created_at, min((r->>'started_at')::timestamptz) AS stranded_at
    FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) r
   WHERE vn.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3' AND r->>'performed_by' = 'stall_cabin_robot'
     AND r->>'status' = 'in_progress' AND r->>'done_at' IS NULL AND r->>'svc' = 'interior_deep_clean'
   GROUP BY 1, 2)
SELECT left(s.vehicle_id::text, 8) AS car, s.stranded_at,
       (SELECT min(x.dispatched_at) FROM public.ottoq_vehicle_dispatches x WHERE x.vehicle_id = s.vehicle_id
          AND x.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3' AND x.dispatched_at >= s.stranded_at) AS left_at,
       (SELECT min((r->>'done_at')::timestamptz) FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) r
         WHERE vn.vehicle_id = s.vehicle_id AND vn.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3'
           AND r->>'svc' = 'interior_deep_clean' AND r->>'status' = 'done' AND (r->>'done_at')::timestamptz > s.stranded_at) AS done_at,
       (SELECT jsonb_agg(r2->>'svc') FROM public.ottoq_visit_needs v2 CROSS JOIN LATERAL jsonb_array_elements(v2.atoms) r2
         WHERE v2.visit_id = (SELECT v3.visit_id FROM public.ottoq_visit_needs v3 WHERE v3.vehicle_id = s.vehicle_id
                                AND v3.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3' AND v3.created_at > s.created_at
                              ORDER BY v3.created_at LIMIT 1)) AS next_visit_services
  FROM stranded s ORDER BY s.stranded_at;

-- Q6 the boards' overcount bound: arm-minutes counted only because of an open routine
WITH sn AS (SELECT DISTINCT s."timestamp" AS t FROM public.site_energy_snapshots s
             WHERE s.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3'),
g AS (SELECT t, lead(t) OVER (ORDER BY t) - t AS dt FROM sn),
a AS (SELECT r->>'robot_stall_id' AS stall, (r->>'status' = 'in_progress' AND r->>'done_at' IS NULL) AS open_atom,
             (r->>'started_at')::timestamptz AS s, COALESCE((r->>'done_at')::timestamptz, (r->>'ends_at')::timestamptz) AS f
        FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) r
       WHERE vn.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3' AND r->>'performed_by' = 'stall_cabin_robot'
         AND r->>'status' IN ('in_progress', 'done')),
per AS (SELECT g.t, g.dt, a.stall, bool_and(a.open_atom) AS only_open FROM g JOIN a ON a.s <= g.t AND a.f > g.t
         WHERE g.dt IS NOT NULL GROUP BY 1, 2, 3)
SELECT round(extract(epoch FROM sum(dt) FILTER (WHERE only_open)) / 60.0, 1) AS arm_minutes_only_open,
       round(extract(epoch FROM sum(dt)) / 60.0, 1) AS arm_minutes_counted
  FROM per;

-- Q7 G553: two arm routines of one visit open on one arm at the same time
WITH a AS (SELECT vn.visit_id, r->>'robot_stall_id' AS stall, r->>'svc' AS svc, r->>'status' AS status,
                  (r->>'started_at')::timestamptz AS s, COALESCE((r->>'done_at')::timestamptz, (r->>'ends_at')::timestamptz) AS f
             FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) r
            WHERE vn.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3' AND r->>'performed_by' = 'stall_cabin_robot'
              AND r->>'status' IN ('in_progress', 'done'))
SELECT x.svc AS svc_1, y.svc AS svc_2, count(*) AS pairs,
       round(avg(extract(epoch FROM LEAST(x.f, y.f) - GREATEST(x.s, y.s)) / 60.0), 1) AS mean_overlap_min,
       round(max(extract(epoch FROM LEAST(x.f, y.f) - GREATEST(x.s, y.s)) / 60.0), 1) AS max_overlap_min
  FROM a x JOIN a y ON x.visit_id = y.visit_id AND x.stall = y.stall AND x.svc < y.svc AND x.s < y.f AND y.s < x.f
 GROUP BY 1, 2;

-- Q8 the first live reading: each board's study on the newest run measured after the apply
SELECT st.sim_run_id, st.node_code, st.ticks, round(st.peak_kw_ac, 1) AS peak_kw, round(st.energy_kwh_ac, 1) AS kwh,
       st.first_clock_at, st.last_clock_at
  FROM public.ottoq_power_node_study st
 WHERE st.depot_id = '11111111-1111-1111-1111-111111111111' AND st.kind = 'canopy_board'
 ORDER BY st.last_clock_at DESC, st.node_code LIMIT 3;
