-- 0361  **The learning loop ran overnight, concluded one experiment and promoted its winner, and the promoted value
--       made the canon fail on the energy atom alone, because a wall-clock solve time sat inside hashed evidence.**
--       FINDINGS G211, G212. The fix is `db/migrations/0477`.
--
--       The dial runner (cron 755) ran from 08:00 to 11:00 UTC on 2026-09-26 (3:00-6:00 AM CT), one pair per call,
--       on the twin depot (busy_day, 48 ticks), and switched itself off at 11:00:49 UTC. Everything below was read
--       from the ledgers after that; CT times throughout, UTC where a ledger stamp is quoted.

-- ══ §1 THE PAIRS ════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0361 §1 — every dial pair of the night (G153: one pair is one seed, so pairs are independent observations) ==='
SELECT left(l.experiment_id::text, 8) AS exp, l.seed, l.ran_at, l.wall_s, l.complete, l.world_identical, l.both_paid_shield,
       l.metrics_a->'asset_hours_available_per_day' AS hours_a, l.metrics_b->'asset_hours_available_per_day' AS hours_b,
       l.metrics_a->'site_cost_usd_per_day' AS cost_a, l.metrics_b->'site_cost_usd_per_day' AS cost_b
  FROM public.ottoq_dial_pair_ledger l
 WHERE l.ran_at >= '2026-09-26 07:55+00'
 ORDER BY l.ran_at;
-- 11 pairs, all complete, world-identical and shield-paid, 457-533 s each, 11 distinct seeds.
--   b66fa99c (energy_reserve_shave 0 vs 1, primary site_cost_usd_per_day, lower is better): 6 pairs, 3:00-4:30 AM.
--     Site cost per day, control vs treatment: 1,821.31 vs 1,634.77 · 1,537.28 vs 1,411.66 · 1,698.47 vs 1,528.33 ·
--     2,317.65 vs 2,286.11 · 1,545.78 vs 1,495.98 · 1,657.30 vs 1,500.39. Asset hours equal in every pair.
--   3a2c5fa1 (recall_implementation_id 1 vs 3, primary asset_hours_available_per_day, higher is better): 5 pairs.
--     The primary reads identical in every pair (467/467, 480/480, 444.5/444.5, 412.5/412.5, ...). See §4.

-- ══ §2 THE VERDICT AND THE PROMOTION ════════════════════════════════════════════════════════════════════════════

\echo '=== 0361 §2 — the promotion ledger ==='
SELECT promotion_id, decided_at, param_key, from_value, to_value, outcome, left(reason, 120) AS reason, rolled_back_of,
       evidence->>'why' AS why, evidence->'guardrails'->'breached' AS breached
  FROM public.ottoq_dial_promotion_ledger ORDER BY promotion_id;
-- 9   09:40:00 UTC (4:40 AM CT)  energy_reserve_shave 0 -> 1  enacted  treatment_wins_and_every_gate_passed
--     "6 of 6 non-tied pairs favour the treatment (0 tied), p = 0.01563 <= 0.025, mean gain 7.08% on
--     site_cost_usd_per_day"; guardrails: peak kW -0.50%, touches, p95 time to service, turns and asset hours 0%,
--     safety-critical refusals more on 0 pairs and fewer on 4. The runner concluded the experiment at its first look
--     and the promoter (gate dial_promotion_enabled, on since migration 0404) set the depot's value through the
--     setter, with lineage row dial_promotion_9_energy_reserve_shave (forces_recert).
-- 10  11:08:57 UTC (6:08 AM CT)  energy_reserve_shave 1 -> 0  rolled_back  G211, rolled_back_of 9 (§3).

-- ══ §3 G211: THE PROMOTED VALUE COULD NOT CERTIFY ═════════════════════════════════════════════════════════════════

\echo '=== 0361 §3 — the certification verdicts after the promotion ==='
SELECT r.verdict_id, r.certified_at, r.scenario, r.seed, r.ticks, r.outcome, r.equal, r.disagreeing_atoms,
       r.verdict->'arm_a'->>'h_nrg' AS h_nrg_a, r.verdict->'arm_b'->>'h_nrg' AS h_nrg_b
  FROM public.ottoq_determinism_verdict_ledger r
 WHERE r.certified_at > '2026-09-26 09:40+00'
 ORDER BY r.verdict_id;
-- The promotion's lineage row moved the recertification floor to 09:40:00 UTC. From 09:49 the runner (cron 746) ran
-- busy_day / 171717 / 12 ticks back to back, about two minutes a pair, and failed it every time: verdicts 272-311,
-- 40 in 78 minutes, each `failed` on the single atom `energy`, with 13 of 14 atoms equal, the world end state
-- included, and a different h_nrg in every arm of every attempt. A failed column stays below the floor, so the
-- runner retried it forever and never reached the other six twin-depot columns.

\echo '=== 0361 §3b — the energy commands of verdict 311''s two arms, set difference both ways ==='
WITH a AS (SELECT tick_seq, command_type, source, setpoint_kw, horizon_min, issued_at, reason::text AS reason
             FROM public.ottoq_energy_commands WHERE sim_run_id = '736141c3-0d3c-4daf-a469-2b1d62774254'),
     b AS (SELECT tick_seq, command_type, source, setpoint_kw, horizon_min, issued_at, reason::text AS reason
             FROM public.ottoq_energy_commands WHERE sim_run_id = 'c76e02b2-32bb-4160-8e8d-5a61fc47e7c8')
SELECT (SELECT count(*) FROM a) AS n_a, (SELECT count(*) FROM b) AS n_b,
       (SELECT count(*) FROM (SELECT * FROM a EXCEPT SELECT * FROM b) x) AS a_only,
       (SELECT count(*) FROM (SELECT tick_seq, command_type, source, setpoint_kw, horizon_min, issued_at,
                                     ((reason::jsonb) #- '{day_plan,solve_ms}')::text FROM a
                             EXCEPT
                             SELECT tick_seq, command_type, source, setpoint_kw, horizon_min, issued_at,
                                     ((reason::jsonb) #- '{day_plan,solve_ms}')::text FROM b) y) AS a_only_without_solve_ms;
-- 24 and 24 commands; 8 differ; 0 differ once day_plan.solve_ms is removed. The one differing field is the day-plan
-- optimizer's wall-clock solve time (52 vs 61 ms, 33 vs 37, 40 vs 36, 63 vs 59, 61 vs 60, 62 vs 59, 57 vs 60,
-- 57 vs 60), which public.ottoq_bess_day_plan measures with clock_timestamp() and public.ottoq_energy_orchestrate
-- embeds in the BESS command's reason, the text the energy atom hashes. With reserve shaving off the plan is not in
-- the reason, which is why every column had certified at 2:13-2:27 AM. The behaviour was deterministic; the evidence
-- was not. The class of 0137 (a write timestamp in a fingerprint) and 0216 (a minted id).
--
-- The experiment's result is unaffected: site cost is computed from setpoints and meter readings, which are
-- identical between the arms of a pair up to solve_ms, and solve_ms enters no cost.
--
-- Done at 11:08:57 UTC (6:08 AM CT): energy_reserve_shave set back to 0 at the twin depot through the setter, lineage
-- row rollback_dial_promotion_9_energy_reserve_shave (forces_recert, so the canon re-certifies under the value it
-- runs), and promotion-ledger row 10 (rolled_back_of 9). The first twin-depot pair after the rollback is §5.

-- ══ §4 G212: THE RECALL EXPERIMENT CANNOT MOVE ITS PRIMARY METRIC ══════════════════════════════════════════════════

\echo '=== 0361 §4 — the latest recall pair: dispatches, arm against arm ==='
WITH p AS (SELECT l.run_a, l.run_b, l.moved FROM public.ottoq_dial_pair_ledger l
            WHERE l.experiment_id = '3a2c5fa1-aa46-4471-bc10-2413c63a7312' AND l.ran_at > '2026-09-26 07:55+00'
            ORDER BY l.ran_at DESC LIMIT 1),
da AS (SELECT vehicle_id, dispatched_at, actual_return_at, scheduled_return_at, status FROM public.ottoq_vehicle_dispatches d, p WHERE d.sim_run_id = p.run_a),
db AS (SELECT vehicle_id, dispatched_at, actual_return_at, scheduled_return_at, status FROM public.ottoq_vehicle_dispatches d, p WHERE d.sim_run_id = p.run_b)
SELECT (SELECT moved FROM p) AS moved_digests, (SELECT count(*) FROM da) AS dispatches_a, (SELECT count(*) FROM db) AS dispatches_b,
       (SELECT count(*) FROM (SELECT * FROM da EXCEPT SELECT * FROM db) x) AS in_a_not_b,
       (SELECT count(*) FROM (SELECT * FROM db EXCEPT SELECT * FROM da) x) AS in_b_not_a;
-- The arms' 196 dispatches are identical row for row, so asset_hours_available_per_day (view
-- ottoq_kpi_asset_hours_available_per_day, the sum of dispatch durations clipped to the run) cannot differ between
-- them, and did not on 5 of 5 pairs. The verdict counts identical primaries as ties: no false "no effect" is
-- recorded, and no answer is possible either.
--
-- CORRECTED the same morning, and the first reading was wrong. It said "what recall decides never reaches when a
-- car leaves or returns". It does: twin.ottoq_sim_advance_deployed_telemetry acts on a triggered return (status
-- returning, scheduled_return_at moved). What happened is that the arms decided nothing differently:

\echo '=== 0361 §4b — the recall decisions of each pair, arm against arm, field for field ==='
WITH p AS (SELECT l.seed, l.run_a, l.run_b FROM public.ottoq_dial_pair_ledger l
            WHERE l.experiment_id = '3a2c5fa1-aa46-4471-bc10-2413c63a7312' AND l.ran_at > '2026-09-26 07:55+00')
SELECT p.seed,
       (SELECT count(*) FROM public.ottoq_recall_decisions d WHERE d.sim_run_id = p.run_a) AS decisions_a,
       (SELECT count(*) FROM (
          SELECT vehicle_id, decided_at_sim, should_return, return_trigger, urgency, rung, is_deferrable, lead_ticks, projected_eta_min
            FROM public.ottoq_recall_decisions WHERE sim_run_id = p.run_a
          EXCEPT ALL
          SELECT vehicle_id, decided_at_sim, should_return, return_trigger, urgency, rung, is_deferrable, lead_ticks, projected_eta_min
            FROM public.ottoq_recall_decisions WHERE sim_run_id = p.run_b) x) AS differing
  FROM p ORDER BY p.seed;
-- 5 pairs, 1,014-1,202 decisions an arm, 0 differing in any decision field. Both arms fired the same 563 returns with
-- the same trigger mix (low_soc_reserve 239, overnight_prestage 167, sensor_soil 89, wash_cadence 51, comms_stale 12,
-- rider_flag_cleaning 5), and neither fired an interval-maintenance trigger. interval_scheduled_v1 differs from
-- naive_threshold_v1 only when a car's interval maintenance comes due, and no car of the reset certification fleet
-- reaches its interval within 48 ticks. The hypothesis came from live run 324eb0f1, where naive recall pulled 58 cars
-- for maintenance; the dial arms start from the canonical reset, which never gets there.
--
-- Two things still moved between the arms, and neither is the dial. h_rcl hashes each decision with the
-- implementation's name (public.ottoq_evaluate_return_need), so it differs whenever the names do. And the energy,
-- decision, event, rule and end-state atoms moved because of G214 (§8): the arms started with different canopy
-- soiling. The experiment was abandoned at 11:44 UTC (6:44 AM CT, §9).

-- ══ §5 THE FIRST TWIN-DEPOT PAIR AFTER THE ROLLBACK ═════════════════════════════════════════════════════════════════

\echo '=== 0361 §5 — busy_day / 171717 / 12: the pair after the rollback against the last pass before the promotion ==='
SELECT r.verdict_id, r.certified_at, r.outcome, r.disagreeing_atoms,
       r.verdict->'arm_a'->>'h_nrg' AS h_nrg, r.verdict->'arm_a'->>'h_evt' AS h_evt, r.verdict->'arm_a'->>'h_dec' AS h_dec
  FROM public.ottoq_determinism_verdict_ledger r
 WHERE r.verdict_id IN (264, 316)
 ORDER BY r.verdict_id;
-- 264  07:12:00 UTC (2:12 AM CT), before the promotion   passed  {}  d6d398f7…  a77df08d…  ce8be339…
-- 316  11:10:56 UTC (6:10 AM CT), after the rollback     passed  {}  d6d398f7…  a77df08d…  ce8be339…
--
-- The pair the runner began two minutes after the rollback passed, with both arms' energy atoms equal, and it lands
-- on the digests the same column certified at 2:12 AM CT on the energy, event and decision atoms alike: different
-- runs, transactions and backends four hours apart, so the rollback restored the certified behaviour exactly, and the
-- 40 failures were the promoted value's evidence and nothing else. The runner was then paused (11:11 UTC) so
-- 0474-0477 could be probed and applied into a quiet world.

-- ══ §6 0477, AND THE PROMOTION RESTORED ════════════════════════════════════════════════════════════════════════════
--
--   A static read first: public.ottoq_bess_day_plan calls clock_timestamp() exactly twice, once to start its timer and
--   once to compute solve_ms, and public.ottoq_energy_orchestrate and public.ottoq_publish_day_plan call no volatile
--   clock or random function at all. So solve_ms is the only wall-clock value the day plan carries, and once the reason
--   drops it, nothing in the embedded plan can differ between identical arms.
--
--   0474-0477 applied 11:22:38-11:24:03 UTC (6:22-6:24 AM CT), each stored statement's md5 equal to its file's body.
--   At 11:25:33 UTC (6:25 AM CT) energy_reserve_shave was set back to 1 at the twin depot through the setter, with
--   promotion-ledger row 11 (outcome enacted, experiment b66fa99c, evidence restores 9 and reverses_rollback 10) and
--   lineage row dial_promotion_11_energy_reserve_shave (forces_recert), and the runner (cron 746) was re-enabled.
--   Row 11 says plainly that the experiment's conclusion is carried over, not re-measured: its six pairs ran on engine
--   f086c4ec…, and the value is enacted on engine 4de37d8e…, which carries 0474-0477.
--
--   Found on the way (G213): the setter's upsert is `ON CONFLICT … DO UPDATE SET param_value, updated_at` and never
--   updates updated_by, so a dial row names the first writer it ever had, not the latest. Row 11's write reads
--   updated_by ottoq_prime:promoter, the label promotion 9 created the row with, not the label this restore passed.
--   The column's only readers are the two MPC lookaheads' cleanup (DELETE … WHERE updated_by = 'mpc'), and neither
--   runs: ottoq_mpc_energy_lookahead has no caller, and ottoq_mpc_lookahead's one caller, ottoq_cil_tick, has no
--   caller, no cron job and no recorded call. So it misattributes and decides nothing. Open.
--
-- ══ §7 THE CANON UNDER THE RESTORED VALUE ═══════════════════════════════════════════════════════════════════════════

\echo '=== 0361 §7 — the verdicts since the restore ==='
SELECT r.verdict_id, r.certified_at, r.scenario, r.seed, r.ticks, r.outcome, r.disagreeing_atoms,
       (r.verdict->'arm_a'->>'h_nrg') = (r.verdict->'arm_b'->>'h_nrg') AS energy_equal
  FROM public.ottoq_determinism_verdict_ledger r
 WHERE r.certified_at > '2026-09-26 11:25:33+00'
 ORDER BY r.verdict_id;

\echo '=== 0361 §7b — verdict 319 carried the reserve-shaving plan, so its pass is not vacuous ==='
WITH ids AS (SELECT (verdict->'arm_a'->>'run')::uuid AS a, (verdict->'arm_b'->>'run')::uuid AS b
               FROM public.ottoq_determinism_verdict_ledger WHERE verdict_id = 319)
SELECT (SELECT count(*) FROM public.ottoq_energy_commands c, ids WHERE c.sim_run_id = ids.a) AS commands_a,
       (SELECT count(*) FROM public.ottoq_energy_commands c, ids WHERE c.sim_run_id = ids.a AND c.reason::jsonb ? 'day_plan') AS with_plan_a,
       (SELECT count(*) FROM public.ottoq_energy_commands c, ids WHERE c.sim_run_id = ids.b AND c.reason::jsonb ? 'day_plan') AS with_plan_b,
       (SELECT count(*) FROM public.ottoq_energy_commands c, ids
         WHERE c.sim_run_id IN (ids.a, ids.b) AND (c.reason::jsonb -> 'day_plan') ? 'solve_ms') AS with_solve_ms,
       (SELECT public.ottoq_policy_get(ids.a, 'energy_reserve_shave', -1) FROM ids) AS shave_arm_a_reads;
-- 317  11:26 UTC  grid_smoke / 239001 / 6    passed  energy equal
-- 318  11:27 UTC  grid_smoke / 424242 / 6    passed  energy equal
-- 319  11:28 UTC  busy_day / 171717 / 12     passed  energy equal   (6:28 AM CT)
--
-- 319 is the column that failed 40 times under the promoted value before 0477. It passes under the same value now,
-- and not vacuously: each arm has 24 energy commands, 12 of which carry the reserve-shaving day plan in the hashed
-- reason, none carries solve_ms, and the arm reads energy_reserve_shave 1. G211's prediction holds on the column
-- that exposed it. The other six twin-depot columns follow below.

-- ══ §8 G214: THE ARMS DID NOT START WITH THE SAME SOLAR PANELS ═══════════════════════════════════════════════════════

\echo '=== 0361 §8 — the first energy difference of the latest recall pair, and where it comes from ==='
WITH p AS (SELECT l.run_a, l.run_b FROM public.ottoq_dial_pair_ledger l
            WHERE l.experiment_id = '3a2c5fa1-aa46-4471-bc10-2413c63a7312' AND l.ran_at > '2026-09-26 07:55+00'
            ORDER BY l.ran_at DESC LIMIT 1),
a AS (SELECT s.timestamp AS t, s.building_load_kw AS bld, s.solar_generation_kw AS sol, s.total_ev_charging_kw AS ev
        FROM public.site_energy_snapshots s, p WHERE s.sim_run_id = p.run_a),
b AS (SELECT s.timestamp AS t, s.building_load_kw AS bld, s.solar_generation_kw AS sol, s.total_ev_charging_kw AS ev
        FROM public.site_energy_snapshots s, p WHERE s.sim_run_id = p.run_b)
SELECT a.t, a.bld, b.bld AS bld_b, a.ev, b.ev AS ev_b, a.sol, b.sol AS sol_b, round(b.sol / NULLIF(a.sol, 0), 4) AS ratio
  FROM a JOIN b USING (t) WHERE (a.bld, a.sol, a.ev) IS DISTINCT FROM (b.bld, b.sol, b.ev) ORDER BY a.t LIMIT 4;
-- 12:00 UTC  building 103.1 = 103.1  EV 351.9 = 351.9  solar  48.7 / 46.7  0.9589
-- 12:30      building  93.7 =  93.7  EV 450.1 = 450.1  solar 103.5 / 99.4  0.9604
-- 13:00                                               solar 199.9 / 192.0  0.9605
-- The energy commands first differ at tick 7 in net load, 543 against 545 kW. Dispatches (196), charge sessions
-- (180, every physical field) and recall decisions are identical; solar alone differs, by a constant 4%. On canopy_1
-- at 12:00, same irradiance (76.8 W/m2), temperature and weather: soiling_factor 0.9082 in arm A, 0.8724 in arm B.

\echo '=== 0361 §8b — the soiling every overnight arm started with (canopy_1), and the pair''s primary ==='
WITH pairs AS (SELECT left(l.experiment_id::text, 8) AS exp, l.ran_at, l.run_a, l.run_b,
                      (l.metrics_a->>'site_cost_usd_per_day')::numeric AS cost_a, (l.metrics_b->>'site_cost_usd_per_day')::numeric AS cost_b
                 FROM public.ottoq_dial_pair_ledger l WHERE l.ran_at >= '2026-09-26 07:55+00'),
s AS (SELECT o.sim_run_id, (array_agg(o.soiling_factor ORDER BY o.sim_clock_at))[1] AS soil0, round(sum(o.ac_power_kw) * 0.5, 1) AS kwh
        FROM public.ottoq_solar_output o
       WHERE o.canopy_code = 'canopy_1' AND o.sim_run_id IN (SELECT run_a FROM pairs UNION ALL SELECT run_b FROM pairs)
       GROUP BY o.sim_run_id)
SELECT p.exp, to_char(p.ran_at, 'HH24:MI') AS ran, sa.soil0 AS soil_a0, sb.soil0 AS soil_b0, sa.kwh AS c1_kwh_a, sb.kwh AS c1_kwh_b,
       p.cost_a, p.cost_b
  FROM pairs p JOIN s sa ON sa.sim_run_id = p.run_a JOIN s sb ON sb.sim_run_id = p.run_b ORDER BY p.ran_at;
-- exp       ran    soil A0  soil B0   canopy_1 kWh A / B   site cost A / B ($/day)
-- b66fa99c  08:00  0.8500   0.8500     612.0 /  612.0      1,821.31 / 1,634.77
-- 3a2c5fa1  08:10  0.8500   0.9854     981.0 / 1117.2
-- b66fa99c  08:20  0.9854   0.9496    1011.2 /  974.0      1,537.28 / 1,411.66   treatment dirtier
-- 3a2c5fa1  08:30  0.9139   0.8781     662.4 /  636.1
-- b66fa99c  08:40  0.8500   0.8500     838.7 /  838.7      1,698.47 / 1,528.33
-- 3a2c5fa1  08:50  0.8500   0.8500     870.3 /  870.3
-- b66fa99c  09:00  0.8500   0.8500     516.9 /  516.9      2,317.65 / 2,286.11
-- 3a2c5fa1  09:10  0.8500   0.9840     909.2 / 1013.5
-- b66fa99c  09:20  0.9840   0.9482    1023.1 /  985.4      1,545.78 / 1,495.98   treatment dirtier
-- 3a2c5fa1  09:30  0.9125   0.8767    1010.3 /  970.2
-- b66fa99c  09:40  0.8500   0.9854     827.7 /  922.0      1,657.30 / 1,500.39   treatment CLEANER
--
-- The mechanism: twin.ottoq_sim_advance_weather_and_solar keeps each canopy's soiling in ottoq_canopy_state, one row
-- per canopy per depot, drifting it down about 0.075% a dry tick (floor 0.85) and up 0.03 a rainy one (cap 1.0), and
-- nothing scopes the row to a run or resets it. The two arms of a pair run back to back, so arm B starts where arm A
-- ended. They agree only while the soiling is pinned at its floor; a seed that rains lifts it, and the next arm
-- inherits the lift. public.ottoq_bess_day_plan forecasts solar from the same row. (The precipitation chain beside
-- it was scoped to its run by 0134; the soiling was not.)
--
-- What it did to the night's two verdicts:
--   energy_reserve_shave (b66fa99c): three pairs started clean and all three favour the treatment; two started with
--   the treatment's panels dirtier and it still won both; one, the sixth, started with them cleaner. The verdict's
--   p = 0.0156 needed all six: five of five is p = 0.031, above the 0.025 per-look alpha. The effect looks real (the
--   clean pairs save 10.2%, 10.0% and 1.4%, the two handicapped ones 8.2% and 3.2%), but the gate passed on a pair the
--   confound favoured. So the promotion stands on the evidence and not on its own arithmetic, and it is re-measured
--   once 0479 lands.
--   recall_implementation_id (3a2c5fa1): every moved atom but h_rcl is this (§4b).
--
--   And the canon: verdicts 273 and 280 of G211's window differ in 12 energy commands with solve_ms removed, and their
--   arms started at different soiling (273: 0.9771-0.9854 against 0.9679-0.9762). G211 had two causes. solve_ms was the
--   persistent one; this one washed out on its own once the retries had drifted the panels back down to the floor,
--   and it comes back after any run that rains. Every canon column certified today started at the floor.
--
-- Fixed by db/migrations/0479: the solar step and the day plan read the run's own recorded soiling, 0.85 before
-- the run's first row.

-- ══ §9 THE RECALL EXPERIMENT, ABANDONED ═════════════════════════════════════════════════════════════════════════════
--
--   11:44 UTC (6:44 AM CT): 3a2c5fa1 set to status abandoned, verdict outcome abandoned_uninformative, with §4b's
--   evidence and the condition to recreate it (a canonical fleet reset that seeds maintenance-interval progress, so
--   some cars cross their interval in the run). It had held half the dial runner's nightly budget for an experiment
--   whose arms could not differ.

-- ══ §10 0479, BEFORE AND AFTER, AND THE REPLICATION ═════════════════════════════════════════════════════════════════
--
--   11:52 UTC (6:52 AM CT), after the sweep of 0474-0477 had certified 9 of 9 (busy_day/171717/48 last, verdict 325),
--   on a rolled-back transaction: the stopped run 49c45bd4 (its last recorded soiling 0.79 on every canopy), the shared
--   canopy rows set first to 0.97 and then to 0.90, as a rainy run would leave them, and one solar step at the run's
--   clock + 30 min each time, under the old body and under 0479's:
--
--                          shared row 0.97              shared row 0.90
--   before 0479            soiling 0.9571, 111.89 kW    soiling 0.8591, 100.43 kW     (canopy_1)
--   after 0479             soiling 0.7900,  92.35 kW    soiling 0.7900,  92.35 kW
--
--   Before, the run's panels are whatever the shared row says. After, they are the run's own, whatever the row says.
--   (0.79 is below the 0.85 floor because 49c45bd4 ran a solar_soiling variability profile, applied after the floor.)
--
--   Applied: 0478 at 11:53:37, 0479 at 11:54:29, 0480 at 11:54:49 UTC, each stored statement's md5 equal to its file's
--   body. 0479 moved the recertification floor to 11:54:29, and the runner began the sweep at 11:55. 0480 registered
--   experiment 82c5568b, b66fa99c's design under a new id and so new seeds, which the dial runner takes up in its next
--   window (3:00-6:00 AM CT).
--
--   The sweep under 0479 (floor 11:54:29 UTC) certified 9 of 9: grid_smoke 239001/6 and 424242/6 (verdicts 326,
--   327), busy_day 171717/12, 314159/12 and 424242/12 (328, 329, 333), normal_day 171717/12 (334), busy_day 171717/24
--   and 424242/24 (335, 336), and busy_day 171717/48 (337, the last, done at 12:21 UTC). On every column, each of the
--   eleven digests is identical to the same column's last verdict before 0479 (317-325): 0479 moved no certified
--   digest. That fits what it changes. At 12:19 UTC every shared canopy row, at both depots, read 0.85, the floor, and
--   0479 starts every run at 0.85, so a pair whose arms both found the row at the floor behaves the same under either
--   body. The pairs §8 caught diverging were the ones whose arms found the row at different values.

-- ══ §11 THE RUNNER THAT RETRIED FOREVER, AND THE WINDOW NOBODY OPENED ══════════════════════════════════════════════
--
--   0481 (G211's open half), dry-run at 12:02 UTC on a rolled-back transaction with a simulated G211: a fake enacted
--   promotion of energy_reserve_shave whose lineage row is the newest floor-mover, then failed verdicts for
--   busy_day / 171717 / 12 at the twin depot.
--     two failures              -> guard: none ("the column has not failed enough times since the promotion")
--     a third                   -> guard: rolled_back; the rollback's ledger row reads "the canon could not certify it:
--                                  busy_day / 171717 / 12 ticks failed 3 times since the promotion ...", carries the
--                                  3 verdict ids, and a forces_recert lineage row moved the floor
--     called again              -> guard: none ("the promotion is not enacted, or is already rolled back")
--   Under 0481, G211's night would have ended after three failed pairs, about six minutes, instead of forty in 78.
--
--   0482: the dial runner's window. Last night's was opened and closed by hand (the close was a one-shot reminder at
--   11:00:49 UTC), and nothing would open it again for 0480's replication. Two pg_cron jobs now set the runner's gate
--   through the setter, 1 at 08:00 UTC and 0 at 11:00 UTC (3:00-6:00 AM CDT). Its first apply, at 12:06 UTC, queued
--   behind a running certification pair: the apply path takes a lock on supabase_migrations.schema_migrations, which
--   the pair holds a share lock on for its whole transaction because the recert floor reads it. The client timed out
--   at 60 s and the server cancelled the apply cleanly (no row, no jobs). G194's shape: the file had no P0 because it
--   schedules only, and that turned out not to matter to the lock. It has a P0 now.
--
--   Applied at 12:22 UTC (7:22 AM CT), a minute after the last column of the 0479 sweep certified (verdict 337):
--   0481 = 20260926122216 and 0482 = 20260926122233, each stored statement's md5 equal to its file's body
--   (49101ffd..., 5bea4df2...). Read back at once:
--     cron 746            active, calls the guard once (character 1,407), between the pick and the pair, with the
--                         record the pair is called with; six firings to 12:28 UTC succeeded (no column below the
--                         floor, so none reached the guard)
--     the guard today     action none, "the floor was not moved by a dial promotion" (0479 moved it)
--     jobs 761 / 762      ottoq_dial_window_open 0 8 * * *, ottoq_dial_window_close 0 11 * * *, both active
--     the gate            dial_experiment_runner_enabled reads 0: V2's write was undone, so the window first opens at
--                         08:00 UTC tomorrow (3:00 AM CT), for 0480's replication
