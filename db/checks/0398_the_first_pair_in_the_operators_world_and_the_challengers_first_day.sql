-- 0398  **The first dial pair run in the operator's world (0531, G256), the operator's wall-clock stamp measured, and the
--       challenger's first readings (0532): the taper tax on the day's full runs and its first live scans.**
--
--       Written on 2026-09-27 (16:10-17:30 UTC, 11:10 AM-12:30 PM CT) after 0531 was applied. Read-only.

-- ══ §1 THE FIRST PAIR THROUGH THE OPERATOR'S DOOR ═════════════════════════════════════════════════════════════════════
--
--   The charge-target experiment 08262943 (`dcfc_target_soc_day` 90 against 85, busy_day 8 AM-5 PM at 6 sim-minutes a
--   tick for 90 ticks, primary `unmet_demand_car_hours`, lower) was registered at 16:13 UTC and its first seed paired at
--   16:15 by a one-shot cron job (764, removing itself when done) -- the dial runner stays off until tonight's window.
--   The question it answers first is not the dial's: it is whether an arm now lives in the operator's world.

\echo '=== 0398 §1(a) — the pair: valid, the same world, what moved, what it cost ==='
SELECT p.pair_id, p.seed, p.complete, p.world_identical, p.both_paid_shield, p.moved, p.wall_s,
       p.metrics_a->'unmet_demand_car_hours' AS unmet_a, p.metrics_b->'unmet_demand_car_hours' AS unmet_b,
       p.metrics_a->'unmet_demand_pct' AS unmet_pct_a, p.metrics_b->'unmet_demand_pct' AS unmet_pct_b
  FROM public.ottoq_dial_pair_ledger p
 WHERE p.experiment_id = '08262943-e487-4a24-9ddb-0686737bcf98' ORDER BY p.pair_id;
-- READ (2026-09-27 16:40 UTC; job 764 ran 16:15:00-16:35:05 UTC and removed itself): pair 95, seed 812326339305302355,
--   complete, the same world, both arms paid the shield -- and `moved` is EMPTY. Every atom of the treatment arm (85%)
--   equals the control's (90%): 336.3 unmet car-hours of 440.0 in both, 76.4%, in 1,182 seconds of wall time.
--   A cap that moves nothing on a day when cars spent 863-1,107 DCFC-minutes above 85% (§3) is a cap nobody reads.
--   `ottoq_target_soc_cap` reads `ottoq_policy_get(NULL, 'dcfc_target_soc_day', 90)`: the GLOBAL scope. The pair writes
--   the arm's value at run scope, which no reader of this dial consults. Every pair of this experiment would have been
--   identical, and a verdict over identical pairs would have concluded that the dial does nothing. G258.

\echo '=== 0398 §1(b) — each arm hour by hour against the operator''s two full days ==='
SELECT r.label, h.key AS hour_ct, (h.value->>'target')::int AS target, (h.value->>'deployed')::int AS deployed
  FROM (SELECT 'control (90)' AS label, run_a AS id FROM public.ottoq_dial_pair_ledger
         WHERE experiment_id = '08262943-e487-4a24-9ddb-0686737bcf98' ORDER BY pair_id LIMIT 1) r,
       jsonb_each(public.ottoq_kpi_supply_gap(r.id)->'by_hour_ct') h
 ORDER BY 2;
-- READ (2026-09-27 16:42 UTC): the arm lives in the operator's world now. Dealt through the door (13 at the gate, 91
--   staged, 46 primed, a profile row), its cars went out 47.4 minutes a trip and used 30.8 points (the operator's 55 and
--   37; the old arm's 281 and 31), 199 dispatches and 193 returns in nine hours (the operator's 204-218 and 199-208; the
--   old arm's 168 and 116). Hour by hour, cars out against the target: 37/45 at 8, 37/49 at 9, then 9, 4, 3, 4, 5, 2
--   and 4 against 48-52 -- the operator's shape, collapsing at 10 AM. It collapses harder: 76.4% unmet against the
--   operator's 62.6% and 64.6% (and the old arm's 1.2%). The one difference left by construction is the cadence: the
--   arm decides every 6 sim-minutes, the operator's live run about every 36 sim-seconds, so a charger freed mid-tick
--   waits for the next tick to be refilled. Both arms share it, so the comparison is fair; the level is not the
--   operator's. Read the arms' differences, never their level, as the operator's.

-- ══ §2 THE OPERATOR'S DEAL STAMPED THE WALL CLOCK, MEASURED ═══════════════════════════════════════════════════════════
--
--   0531 §2(b) says the operator's fleet deal wrote now() into `last_state_change`; this is the measurement behind it,
--   from the signed event stream of the last operator run dealt that way.

\echo '=== 0398 §2 — 6e0352a0: each car''s first last_state_change against the run''s sim start ==='
WITH r AS (SELECT sim_run_id, sim_clock_start, started_at FROM public.ottoq_sim_runs
            WHERE sim_run_id = '6e0352a0-243d-4429-9c4d-70debc73f902'),
lsc AS (
  SELECT DISTINCT ON (e.entity_id) e.entity_id, (e.payload->'diff'->'last_state_change'->>'to')::timestamptz AS lsc_to
    FROM public.ottoq_events e, r
   WHERE e.sim_run_id = r.sim_run_id AND (e.event_type || '') = 'vehicle.state_changed'
     AND e.payload->'diff' ? 'last_state_change' AND e.sim_clock_at <= r.sim_clock_start + interval '1 minute'
   ORDER BY e.entity_id, e.event_seq)
SELECT count(*) AS cars, count(*) FILTER (WHERE lsc.lsc_to > r.sim_clock_start) AS after_sim_start,
       round(min(extract(epoch FROM lsc.lsc_to - r.sim_clock_start) / 60)::numeric, 1) AS min_ahead_min,
       round(max(extract(epoch FROM lsc.lsc_to - r.sim_clock_start) / 60)::numeric, 1) AS max_ahead_min,
       min(r.started_at) AS real_start, min(r.sim_clock_start) AS sim_start
  FROM lsc, r GROUP BY r.sim_clock_start;
-- READ (2026-09-27 16:20 UTC): 116 cars, all 116 with their first state stamp AFTER the sim start, 8.2 to 96.5
--   sim-minutes ahead. The run was started at 14:37:07 UTC for a 13:00 sim start; the deal staggered now() back by up
--   to 90 minutes, so every stamp landed between the two. A dwell read as the sim clock minus the stamp was negative for
--   the first 8-97 sim-minutes of the day, for every car. After 0531 the deal stamps the run's sim start (0531 V3(b):
--   0 cars after it, 0 before the 90-minute stagger, 0 SoC stamps or heartbeats off).

-- ══ §3 THE TAPER TAX: TWO OF EVERY FIVE DCFC-MINUTES WENT TO A CAR ALREADY ABLE TO DEPLOY ═══════════════════════════
--
--   0532's hindsight measure. Waiting is 0501's definition over the day; when a charging car crossed the floor (80%)
--   and 85% is read from the signed SoC stream.

\echo '=== 0398 §3 — the day''s two full busy runs: charger time spent above the floor while cars waited ==='
SELECT left(r.id::text, 8) AS run, t->'minutes' AS minutes, t->'minutes_with_cars_waiting' AS min_waiting,
       t->'mean_cars_waiting' AS mean_waiting, t->'max_cars_waiting' AS max_waiting, t->'dcfc_sessions' AS dcfc_sessions,
       t->'dcfc_busy_min' AS dcfc_busy, t->'dcfc_above_floor_while_waiting_min' AS above_floor_waiting,
       t->'dcfc_above_85_while_waiting_min' AS above_85_waiting, t->'dcfc_mean_session_min' AS mean_session,
       t->'dcfc_mean_min_above_floor' AS mean_above_floor, t->'l2_above_floor_while_waiting_min' AS l2_above_floor_waiting
  FROM (VALUES ('6ddd827e-b549-43cf-8154-4d1bfb20cabf'::uuid), ('6e0352a0-243d-4429-9c4d-70debc73f902'::uuid)) r(id),
       LATERAL (SELECT public.ottoq_challenger_taper_tax(r.id) AS t) x;
-- READ (2026-09-27 16:31 UTC, in 0532's partial dry run; about 1 s a run):
--     run       minutes  waiting in  mean/max waiting  DCFC sessions  DCFC busy  above floor, waiting  above 85  session  above floor
--     6ddd827e  553      553         31.1 / 52         90             4,981      2,009 (40.3%)          1,107     55.5     25.5
--     6e0352a0  551      551         34.2 / 58         80             3,980      1,576 (39.6%)            863     49.8     22.9
--   Replicated on two seeds: cars waited for a charger in every minute of both days, and two of every five DCFC-minutes
--   went to a car already able to deploy. A DCFC session averaged 50-56 minutes, 23-26 of them above the floor: the
--   taper above 80% costs about as much charger time as the whole climb to it. L2 adds 4,038-4,052 charger-minutes
--   above the floor while cars waited, on 30 stalls against 10.
--   What it is worth is not this number: a charger freed at 80% serves the next car, which returns sooner at a lower
--   state of charge and comes back for more. Only the paired experiment (08262943, §1) says what the depot gains.
