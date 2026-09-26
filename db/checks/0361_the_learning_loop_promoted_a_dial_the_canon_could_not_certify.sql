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
-- The arms' recall decisions differ (h_rcl moves, with decisions, events, energy, rules and end state), and their
-- 196 dispatches are identical row for row. asset_hours_available_per_day (view
-- ottoq_kpi_asset_hours_available_per_day) is the sum of dispatch durations clipped to the run, so it cannot differ
-- between the arms, and did not on 5 of 5 pairs. The verdict counts identical primaries as ties, so the experiment
-- reads `collecting` at its first look and `inconclusive` at its final one: no false "no effect" is recorded, but no
-- answer is possible either. What recall decides never reaches when a car leaves or returns in these arms. Open.

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
