-- 0460  **Every standard charger at the twin depot becomes a robotic fast charger: thirty posts, each with its charge arm
--        and its cleaning arm, and no power ceiling below what they can draw. The renderer, 0759, 0763 and the three
--        writes that put them on, in order.** -> G481.
--        Chase, 2026-10-21 at 6:52 AM CT: "Still don't see the additional DCFC robotic, charging and overhead Robo, vacuum
--        for the rest of the stalls. I see it on the original 10, but we discussed swapping out all of the L2's or 90% of
--        the L2's for DCFC ever bought charging arm with overhead robovac ." Reads against gxdrcyphqjzjsuhxuqtg on
--        2026-10-21 between 7:08 and 7:22 AM CT (12:08:42 UTC, the first query's clock, to 12:22:19 UTC, read before the
--        migration was written). The writes in §4 were held by the connector for Chase's confirmation, which the cloud
--        session that wrote this cannot show (each write sent through it waited 60 seconds and ran nothing), so Chase ran
--        them himself in the Supabase dashboard's SQL editor on 2026-10-22 between 10:04 and 10:11 PM CT: 0759 and 0763
--        pasted whole as committed, and (W1) with its date and its name set to what ran (§4). Each is named with the
--        statement that undoes it.
--
-- ══ §1 WHY ONLY TEN (reproduce: (1)) ═══════════════════════════════════════════════════════════════════════════════════
--
--   The twin depot is built as it always was: 10 fast chargers on canopy A and 30 standard chargers on canopies B and C
--   (1). 0759 (canopy B, ten more posts) was written on 2026-10-19 and never applied: its P0 refuses while 32 research
--   sweeps and 8 dial experiments are active at the depot, and pausing them is an UPDATE the connector holds for Chase.
--   Nothing converted canopy C at all. So the app drew the ten robots canopy A has, and could draw no more.
--
-- ══ §2 THE BUILD ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Thirty is the most the site holds at this arm design (0759 §1): ten posts a canopy on the 14-unit pitch. So "all of
--   the L2's" is thirty robotic posts and no standard charger.
--     ottoyarddepot-sim #152   the renderer's 30-post build (dcfc30), drawn when the twin layout's census reads 30 + 0.
--                              Filmed in the local cockpit on a served layout re-striped the same way: the 2D plan drew
--                              30 charge arms and 30 cleaning arms, DCFC-01..30, and a canopy C car's doors opened and
--                              the cleaning arm worked its cabin, side A then side B. Thirty cars docked on thirty posts
--                              at once in its driver test, touching no car and no structure.
--     0759                     canopy B re-striped (unchanged; its P1 premises all hold on live, read at 7:13 AM CT).
--     0763                     canopy C re-striped, NASH-L2-STALL-31..35 retired, and the depot's limits what is
--                              installed (§3). 16 tests on the scratch PostgreSQL, 0759 applied first
--                              (tests/test_thirty_post_base_sql.py).
--
-- ══ §3 THE POWER: NO CEILING ON THE FRONT END (reproduce: (2), (3), (4)) ═══════════════════════════════════════════
--
--   0763 as first written held the thirty posts to 2,400 kW of shared cabinets on today's 2,500 kW service, with the
--   settings of the research wing's arm 112 (2): forty posts held there met 939.8 car-hours against 940.5 with power to
--   spare, served 215 visits against 205 and peaked at 1,750.4 kW against 2,128.4, every car at 100% (one seed). Chase,
--   2026-10-21, on reading it: "never base variable allocation of resources or throughput or up time or energy consumption
--   based on a hard ceiling until we have everything built out ... The vehicles needs take absolute precedence, and any
--   energy needed is consumed, and we have to fit around that." So 0763 now sets the depot's limits to what is installed,
--   which no car can reach (4): 10,500 kW DC, thirty posts at their 350 kW rating; 12,250 kW service, those plus the
--   battery charging at its 1,500 kW rating and 250 kW of building (the most the energy snapshots have read is 228.2 kW).
--   No setting changes: the held-site settings stay off, because the depot holds no limit to divide. What the thirty
--   posts draw is what a ceiling is later set from, when testing resumes (rule 12), and the margin under that ceiling is
--   worked on the operator's side (the battery, the tariff), never on a vehicle (CLAUDE.md rule 13). The held site stays
--   the build-out dcfc30_cab2400 (2,400/2,500) for that work; the build-out dcfc30 is the depot as built.
--
--   And the one rule that reads those limits cannot refuse a charge on the thirty posts (reproduce: (10), read at 8:28
--   AM CT). EN.001 judges every charge start at the depot's dcfc_max_concurrent_kw less its safety margin (10%), so
--   10,500 kW reads as a 9,450 kW engineering cap, and each start asks for the lower of the post's rating (350 kW) and
--   the car's inlet. The twin depot's 120 cars: 30 at 250 kW, 44 at 104, 34 at 100, and 12 with no inlet recorded,
--   which ask for the post's 350. Thirty posts all charging the thirty hungriest cars draw 12 x 350 + 18 x 250 =
--   8,700 kW, 750 kW under the cap. The margin binds only on a fleet whose cars average more than 315 kW at the inlet
--   across all thirty posts. If such cars come, the depot's figure moves with what is installed (rule 13), never the
--   cars. What the posts have drawn is lower still: on every run started since 2026-10-01 (0573 rebuilt the fast-charge
--   physics on 09-30) no session on a 350 kW post went over its rating and the highest draw was 220.2 kW (11): thirty
--   posts at that draw are 6,606 kW. The three sessions over 350 kW are on runs started 09-29 and 09-30.
--
-- ══ §4 THE WRITES, IN ORDER ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   (W1) The research pause, (W1) below: the 32 active sweeps at the twin depot to 'paused' (a sweep has no other state
--        that keeps it, and nothing re-opens the window while we build, CLAUDE.md rule 12), and the 8 active dial
--        experiments to 'abandoned' (a dial experiment has no paused state; every one of their pairs ran on the depot
--        as built, and 0759's and 0763's lineage rows move the dial floor). Their pairs stay in the pair ledger.
--        Undo: (U1).
--   (W2) 0759, through apply_migration, as written.
--   (W3) 0763, through apply_migration, once ottoyarddepot-sim #152 is live (Lovable: Publish, then Update). Until then
--        the app keeps drawing canopy C as standard chargers.
--   AS RUN, 2026-10-22 CT. The connector held each write for a confirmation the cloud session cannot show, so Chase ran
--   all three in the Supabase dashboard's SQL editor, pasted from a page that copied the committed text: (W1) at 10:04:17
--   PM CT (03:04:17 UTC on 10-23, the abandoned experiments' concluded_at), with its date and its 'by' written as what
--   ran ('Paused 2026-10-22 CT', 'chase_2026_10_22'; the committed text had said 2026-10-21 and claude_code_2026_10_21,
--   and (W1) below is now what ran, md5 e70516e7): 32 sweeps paused and 8 experiments abandoned, none active after; (W2)
--   0759 at 10:05:29 PM CT and (W3) 0763 at 10:11:18 PM CT, each the file as committed at 2f556ae, unedited, with
--   #152 live. The editor writes no ledger row, so both carry APPLIED-NO-LEDGER-ROW and an APPLIED footer, and it
--   appends a row-security line after each script's COMMIT that failed harmlessly on the files' dropped temporary tables
--   (42P01). Read back at 10:18 and 10:26 PM CT: 30 dcfc spaces on live 350 kW chargers, no standard charger, 10,500 /
--   12,250 kW, and the renderer's layout read the same.
--   Then one demo run on the new depot, the way the app's Start does, read for: the census and the posts it serves; cars
--   charging on canopy B and canopy C posts with an arm cycle each; the cleaning arm's tidies there; rule 9 at departure.
--   Checking a change in one demo run is part of building it (rule 12), not testing.
--
-- ══ §5 THE DEMO-RUN CHECK (reproduce: (5)-(9), each on the twin depot's latest run) ═════════════════════════════════
--
--   (5) the base the run ran on (census and power) and the switches it read; (6) its charges by canopy, A = DCFC-01..10,
--   B = 11..20, C = 21..30 (a charge session is one cycle of the post's OTTO-CHARGE ARM: it mates, and lets go at the end);
--   (7) the OTTO-CLEAN ARM's cleans by canopy (0758: every dcfc stall carries one); (8) rule 9 at departure and the
--   throughput; (9) the power the posts drew against the depot's limits, and EN.001's failures (expected 0: nothing
--   installed can reach 10,500 kW).
--
--   The as-built baseline, read on 2026-10-21 at 8:23 AM CT on the depot's latest run, 96371023 (busy_day, 1,605 ticks,
--   10 + 30 chargers, 1,800/2,500 kW, stall_cabin_robot 1, wash_lane_physics 2, the DC power settings off):
--     (6) canopy A 100 charges on its 10 posts for 73 cars, 3,780.6 kWh, the highest post draw 157.83 kW; the 30 L2s 136
--         charges for 96 cars, 3,722.8 kWh.
--     (7) 22 cabin cleans by the cleaning arm, on 9 of canopy A's 10 arms.
--     (8) 96 departures, none below its charge target and none with needed work open; 96 of 210 visits served, 88 cars,
--         114 in the depot at the horizon.
--     (9) the EV draw peaked at 1,247.3 kW and the 15-minute demand at 965.4 kW; EN.001 failed 0 times.
--
-- ══ QUERIES ═════════════════════════════════════════════════════════════════════════════════════════════════════════

-- (1) the twin depot's census, power and research state
SELECT (SELECT jsonb_object_agg(stall_type::text, n) FROM (SELECT stall_type, count(*) n FROM public.stalls
          WHERE depot_id = '11111111-1111-1111-1111-111111111111' GROUP BY 1) x) AS census,
       (SELECT dcfc_max_concurrent_kw || '/' || service_max_kw FROM public.depots
         WHERE id = '11111111-1111-1111-1111-111111111111') AS power,
       (SELECT count(*) FROM public.ottoq_throughput_sweeps
         WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active') AS active_sweeps,
       (SELECT count(*) FROM public.ottoq_dial_experiments
         WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active') AS active_dial_experiments,
       (SELECT name FROM public.ottoq_cert_lineage WHERE name LIKE '0759%' OR name LIKE '0763%' ORDER BY 1 LIMIT 1) AS applied;

-- (2) the arms the power rests on
SELECT a.arm_id, s.sweep_code, a.seed, a.buildout->>'buildout_code' AS buildout,
       a.arm_metrics->>'deployed_car_hours' AS car_hours, a.arm_metrics->>'peak_site_kw' AS peak_kw,
       a.scorecard->'throughput'->>'visits_served' AS visits_served,
       a.scorecard->'rule9'->>'left_below_target' AS below_target,
       a.scorecard->'rule9'->>'left_with_needed_work_open' AS work_open
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
 WHERE a.arm_id IN (95, 107, 112, 117) ORDER BY a.arm_id;

-- (3) arm 112's cell: the held site's settings, kept for the margin work after a ceiling is set (none is written now)
SELECT c.cell_code, c.fixed_params
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
 WHERE a.arm_id = 112;

-- (4) what is installed: the chargers' ratings, the battery's and the most the building has drawn
SELECT (SELECT jsonb_object_agg(max_kw, n) FROM (SELECT max_kw, count(*) n FROM public.ottoq_ocpp_chargers
          WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND decommissioned_at IS NULL GROUP BY 1) c) AS chargers_by_kw,
       (SELECT max_charge_kw FROM public.ottoq_bess_units WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS bess_charge_kw,
       (SELECT max(building_load_kw) FROM public.site_energy_snapshots
         WHERE depot_id = '11111111-1111-1111-1111-111111111111') AS building_max_kw;

-- (5) the twin depot's latest run: the base it ran on and the switches it read
WITH r AS (SELECT sim_run_id, scenario_code, status, started_at, tick_count FROM public.ottoq_sim_runs
            WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1)
SELECT r.sim_run_id, r.scenario_code, r.status, r.started_at, r.tick_count,
       (SELECT jsonb_object_agg(stall_type::text, n) FROM (SELECT stall_type, count(*) n FROM public.stalls
          WHERE depot_id = '11111111-1111-1111-1111-111111111111' GROUP BY 1) x) AS census,
       (SELECT dcfc_max_concurrent_kw || '/' || service_max_kw FROM public.depots
         WHERE id = '11111111-1111-1111-1111-111111111111') AS power,
       (SELECT jsonb_object_agg(k, public.ottoq_policy_get(r.sim_run_id, k, 0))
          FROM unnest(ARRAY['stall_cabin_robot', 'wash_lane_physics', 'dc_power_sharing', 'dc_power_managed',
                            'dc_power_first_reading', 'enforce_site_charge_cap', 'twin_answer_in_tick']) k) AS switches
  FROM r;

-- (6) its charges by canopy: sessions (one charge-arm cycle each), posts used, cars, energy, the highest post draw
WITH r AS (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1)
SELECT CASE WHEN s.stall_code ~ '^NASH-DCFC-STALL-(0[1-9]|10)$' THEN 'A (DCFC-01..10)'
            WHEN s.stall_code ~ '^NASH-DCFC-STALL-(1[1-9]|20)$' THEN 'B (DCFC-11..20)'
            WHEN s.stall_code ~ '^NASH-DCFC-STALL-(2[1-9]|30)$' THEN 'C (DCFC-21..30)'
            ELSE s.stall_type::text END AS canopy,
       count(*) AS sessions, count(DISTINCT o.stall_id) AS posts, count(DISTINCT o.vehicle_id) AS cars,
       round(sum(o.energy_delivered_kwh), 1) AS kwh, max(o.peak_power_kw) AS peak_post_kw,
       count(*) FILTER (WHERE o.ended_at IS NULL) AS charging_now
  FROM r JOIN public.ocpp_sessions o ON o.sim_run_id = r.sim_run_id JOIN public.stalls s ON s.id = o.stall_id
 GROUP BY 1 ORDER BY 1;

-- (7) the cleaning arm's cleans by canopy: done, at work, and the arms that worked
WITH r AS (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1)
SELECT CASE WHEN s.stall_code ~ '^NASH-DCFC-STALL-(0[1-9]|10)$' THEN 'A (DCFC-01..10)'
            WHEN s.stall_code ~ '^NASH-DCFC-STALL-(1[1-9]|20)$' THEN 'B (DCFC-11..20)'
            WHEN s.stall_code ~ '^NASH-DCFC-STALL-(2[1-9]|30)$' THEN 'C (DCFC-21..30)'
            ELSE COALESCE(s.stall_code, 'no stall') END AS canopy,
       count(*) FILTER (WHERE a->>'status' = 'done') AS done, count(*) FILTER (WHERE a->>'status' = 'in_progress') AS at_work,
       count(DISTINCT s.stall_code) AS arms
  FROM r JOIN public.ottoq_visit_needs vn ON vn.sim_run_id = r.sim_run_id
  CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
  LEFT JOIN public.stalls s ON s.id::text = a->>'robot_stall_id'
 WHERE a->>'performed_by' = 'stall_cabin_robot'
 GROUP BY 1 ORDER BY 1;

-- (8) rule 9 at departure, and the throughput
WITH r AS (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1)
SELECT r.sim_run_id, sc.j -> 'rule9' AS rule9, sc.j -> 'throughput' AS throughput
  FROM r CROSS JOIN LATERAL (SELECT public.ottoq_throughput_scorecard(r.sim_run_id) AS j) sc;

-- (9) the power the posts drew against the depot's limits, and EN.001's failures
WITH r AS (SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC LIMIT 1)
SELECT r.sim_run_id, max(e.total_ev_charging_kw) AS peak_ev_kw, max(e.peak_demand_kw_15min) AS peak_15min_kw,
       max(e.grid_import_kw) AS peak_grid_kw,
       (SELECT dcfc_max_concurrent_kw || '/' || service_max_kw FROM public.depots
         WHERE id = '11111111-1111-1111-1111-111111111111') AS limits,
       (SELECT count(*) FROM public.ottoq_rule_evaluations v
         WHERE v.sim_run_id = r.sim_run_id AND v.rule_code LIKE 'EN.001%' AND NOT v.passed) AS en001_failed
  FROM r LEFT JOIN public.site_energy_snapshots e ON e.sim_run_id = r.sim_run_id
 GROUP BY r.sim_run_id;

-- (10) EN.001 on the thirty posts: the most the depot's cars can ask of thirty posts at once, against its cap after the
--      margin (each start asks for LEAST(the post's max_kw, the car's inlet_max_kw), twin.ottoq_sim_start_charge_session)
WITH asks AS (
  SELECT LEAST(350::numeric, v.inlet_max_kw) AS ask_kw
    FROM public.vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'),
top30 AS (SELECT ask_kw FROM asks ORDER BY ask_kw DESC LIMIT 30)
SELECT (SELECT count(*) FROM asks) AS cars, (SELECT sum(ask_kw) FROM top30) AS worst_30_posts_kw,
       (SELECT 10500 * (1 - dcfc_safety_margin_pct / 100.0) FROM public.depots
         WHERE id = '11111111-1111-1111-1111-111111111111') AS en001_cap_after_0763_kw;

-- (11) what the 350 kW posts have drawn, by the day their runs started: sessions, those over the rating, the highest draw
SELECT date_trunc('day', r.started_at) AS run_day, count(*) AS sessions,
       count(*) FILTER (WHERE o.peak_power_kw > c.max_kw) AS over_rating, round(max(o.peak_power_kw), 2) AS max_peak_kw
  FROM public.ocpp_sessions o
  JOIN public.stalls s ON s.id = o.stall_id
  JOIN public.ottoq_ocpp_chargers c ON c.ocpp_identifier = o.charge_point_id
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = o.sim_run_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND c.max_kw = 350
 GROUP BY 1 ORDER BY 1;

-- (W1) the research pause
UPDATE public.ottoq_throughput_sweeps
   SET status = 'paused',
       notes = COALESCE(notes || ' | ', '')
               || 'Paused 2026-10-22 CT for the twin depot''s 30-post base change (0759, 0763; db/checks/0460). Testing is off '
               || 'while we build (CLAUDE.md rule 12). A cell run after it runs on the 30-post depot.'
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active';
UPDATE public.ottoq_dial_experiments
   SET status = 'abandoned', concluded_at = now(),
       verdict = jsonb_build_object(
         'by', 'chase_2026_10_22', 'outcome', 'abandoned_base_change', 'check', 'db/checks/0460', 'finding', 'G481',
         'why', 'Chase, 2026-10-21: every standard charger at the twin depot becomes a robotic fast charger (0759, 0763). '
                || 'Every pair of this experiment ran on the depot as built, and a pair read across the base change would '
                || 'compare two depots (forces_dial_restart). Testing is off while we build (CLAUDE.md rule 12). Its pairs '
                || 'stay in the pair ledger as evidence.',
         'recreate_when', 'testing resumes on Chase''s word, on the 30-post depot')
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'active';

-- (U1) undo (W1), before 0759 is applied (after it, the cells would run on a depot their earlier arms did not)
-- UPDATE public.ottoq_throughput_sweeps SET status = 'active'
--  WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'paused' AND notes LIKE '%db/checks/0460%';
-- UPDATE public.ottoq_dial_experiments SET status = 'active', concluded_at = NULL, verdict = NULL
--  WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND verdict->>'check' = 'db/checks/0460';
