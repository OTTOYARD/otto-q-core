-- 0400  **The challenger's first live day: what it questioned, how hindsight graded it, and what the cockpits showed.**
--
--       Written on 2026-09-27 (19:00-21:30 UTC, 2:00-4:30 PM CT) around validation run ad106e55, the first live operator
--       run since the challenger (0532), its cockpit reads (0536) and the listing rule (0537) were applied. Read-only.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   busy_day, started through `ottoq_start_busy_run(8)` by a one-shot cron job (769, `SET statement_timeout = 0`) and
--   played live at 8x, so the challenger's scan (cron 765, every minute, operator and production runs) watches it. The
--   operator governor stops a run at 540 sim-minutes: 5:03 AM to 2:03 PM CT sim. The scorecard is the one command and
--   its two companions, as 0397 §5 read 6e0352a0.

\echo '=== 0400 §1 — the run and its scorecard ==='
SELECT r.sim_run_id, r.run_by, r.status, r.sim_clock_start, r.sim_clock_current, r.tick_count, r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf';
SELECT public.ottoq_kpi_five('ad106e55-e775-4780-b853-418f504d4bcf');
SELECT public.ottoq_kpi_charge_wait('ad106e55-e775-4780-b853-418f504d4bcf');
SELECT public.ottoq_kpi_supply_gap('ad106e55-e775-4780-b853-418f504d4bcf') - 'by_hour_ct';
-- READ (2026-09-27 20:52 UTC, 3:52 PM CT): the governor stopped the run at 20:44:00 UTC (3:44 PM CT), `reached the 540
--   sim-minute ceiling`, at sim 2:20 PM CT: 557 sim-minutes and 1,057 ticks (the governor looks every 2 real minutes, 16
--   sim-minutes at 8x). Started 19:14 UTC; the start's purge of the prior runs took about 23 minutes of that, and the
--   first attempt through MCP was cancelled by the role's 2-minute statement timeout and rolled back, which is why cron
--   769 started it. The start hour is seed-derived (`ottoq_demo_start_clock`): 5:03 AM, where the operator runs archived
--   since 2026-09-26 all opened at 8:00. The boot prime took 15 from a pool of 29, and the fleet of 116 began 45 at the
--   gate, 29 staged for departure, 15 charged and holding, 27 staged awaiting service.
--     KPI 1 asset hours 149.72 · KPI 2 turns per point 3.42 · KPI 3 peak site kW 1,193.7 (demand 1,477.3)
--     KPI 4 touches per turn 0.965 · KPI 5 p95 time to service 240.1 min (p50 13.6) · returns unserved 19
--     charge wait: p50 27.6, p95 300.2, max 358.4 min; 171 of 200 visits owing a charge charged; 29 still waiting at
--       the end, p50 213.9 min so far, one for the whole run (557)
--     supply gap: 238.5 of 380.6 demand car-hours unmet (62.7%), 142.2 deployed; peak shortfall 44 cars
--   The same shape as the two earlier full busy days (G255: 62.6% and 64.6% unmet): the depot is short of charger time
--   all day, and cars waited for a charger in every one of the 557 minutes (§2(c)).

-- ══ §2 WHAT THE CHALLENGER ASKED, AND WHAT HINDSIGHT SAID ══════════════════════════════════════════════════════════════
--
--   Each episode is one question about one charger (Q1 its car, Q2 its free state, Q3 its fault), from its first scan to
--   the scan that no longer sees it. The grade is written when it closes (`ottoq_challenger_close`):
--     - Q1 `charging_above_floor_while_cars_wait`: the saving is the lesser of the minutes the car charged on after the
--       first sight and the minutes the longest waiter waited on; confirmed at 5 or more, refuted under 1.
--     - Q2 `charger_offerable_while_cars_wait`: confirmed if two scans saw the charger free and the waiter waited 5
--       more minutes; refuted if one scan did and the waiter plugged in within 5.
--     - Q3 `charger_faulted_while_cars_wait`: confirmed if the fault lasted 30 minutes while cars waited.
--   0537: an episode is a question on the cockpits once a second scan still sees it (`scans_seen >= 2`). One-scan
--   sightings stay in the ledger with their grades and are counted apart. `listed` below is that rule.

\echo '=== 0400 §2(a) — episodes by question, listing, status and grade ==='
SELECT f.question, (f.scans_seen >= 2) AS listed, f.status, COALESCE(f.grade, '-') AS grade, count(*) AS episodes,
       round(avg(f.scans_seen), 1) AS mean_scans,
       round(avg(EXTRACT(epoch FROM COALESCE(f.closed_sim, f.last_seen_sim) - f.first_seen_sim) / 60), 1) AS mean_open_min
  FROM public.ottoq_challenger_findings f
 WHERE f.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2 DESC, 3, 4;
-- READ (2026-09-27 20:52 UTC): 112 episodes, every one closed.
--     question                 listed   grade          episodes  mean scans  mean open min
--     Q1 charging above floor  yes      confirmed          42        3.5          27.7
--                              no       confirmed          14        1.0           8.0
--                              no       inconclusive       11        1.0           7.3
--     Q2 charger offerable     no       refuted            29        1.0           9.1
--                              no       inconclusive        3        1.0           7.8
--     Q3 charger faulted       yes      confirmed           8       25.8         204.4
--                              yes      inconclusive        2        2.0          15.3
--                              no       inconclusive        3        1.0           8.2
--   - **Q2 raised no question all day.** Its 32 sightings were all single scans: the 29 of the opening catch-up (G262)
--     and 3 later ones the engine had filled by the next scan. No charger stayed free by every gate across two scans while
--     a car waited. That is the assignment side of the engine holding up for nine hours.
--   - **Q3's eight confirmations are the day's largest capacity loss.** Three of the ten fast chargers were faulted for
--     most of the day: NASH-DCFC-STALL-08 `fault.station_hardware` from 5:54 AM to the end (504 min),
--     NASH-DCFC-STALL-10 `fault.thermal_emergency` from 7:06 AM to the end (432 min), NASH-DCFC-STALL-03
--     `fault.station_hardware` 8:02 AM to 1:38 PM (328 min, after a 56-minute cable fault from 6:34). With DCFC-01's
--     88-minute cable fault that is about 1,408 of the day's 5,570 fast-charger minutes (25%), lost while up to 64 cars
--     waited. The twin injects charger faults by design (~13.8% of charger time on a busy day, 0264 §3); a quarter of the
--     fast chargers for most of a day is the tail of that draw, and nothing in the engine repairs a charger.
--   - Q1 is §2(b).

\echo '=== 0400 §2(b) — Q1 in hindsight: minutes charged past first sight, and the longest waiter''s further wait ==='
SELECT (f.scans_seen >= 2) AS listed, f.grade, count(*) AS episodes,
       round(avg((f.realized->>'minutes_charged_after_first_sight')::numeric), 1) AS mean_min_charged_after,
       round(avg((f.realized->>'beneficiary_waited_after_min')::numeric), 1) AS mean_waiter_waited_after,
       round(sum((f.realized->>'saving_min')::numeric), 0) AS claimed_saving_min,
       count(*) FILTER (WHERE (f.realized->>'beneficiary_still_waiting')::boolean) AS waiter_still_waiting_at_close
  FROM public.ottoq_challenger_findings f
 WHERE f.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'
   AND f.question = 'charging_above_floor_while_cars_wait' AND f.status = 'closed'
 GROUP BY 1, 2 ORDER BY 1 DESC, 2;
-- READ (2026-09-27 20:52 UTC):
--     listed  grade         episodes  charged on  waiter waited on  claimed saving  waiter still waiting
--                                       (mean min)     (mean min)
--     yes     confirmed        42         23.8          26.4             964 min            38
--     no      confirmed        14          6.7           7.8              92 min            13
--     no      inconclusive     11          3.1           7.3              34 min            11
--   **Every listed Q1 question was graded confirmed, and at this playback speed it could not have been graded anything
--   else (G264).** The grade is the lesser of the minutes the car charged on and the minutes the longest waiter waited on,
--   confirmed at 5. A listed episode was seen by two scans, and at 8x consecutive scans are 7.5 to 24 sim-minutes apart
--   (p50 8.1), so every listed car had charged on at least 9.5 minutes; the saving falls under 5 only if the longest
--   waiter plugged in within 5 minutes of first sight, and none of the 42 did (38 were still waiting when the episode
--   closed). Refuted needs a saving under 1 minute, which no listed episode can reach. So on a day when cars wait in every
--   minute the grade records that the car kept charging and the queue kept waiting. That is true, and it is not the
--   claim the cockpits attach to it: they word a confirmed Q1 as `a real gain missed` and its record as `right 42 of 42
--   graded (100%)`, while the paired test of the same lever (`dcfc_target_soc_day` 90 against 85, pair 102, 0399 §1(b))
--   lost the day on its first seed. Only the one-scan sightings discriminate (11 of 25 inconclusive), and 0537 keeps those
--   off the lists. The local grade is the challenger's evidence; the day's answer is the pair.

\echo '=== 0400 §2(c) — the taper tax on this day, against 6ddd827e and 6e0352a0 (0398 §3) ==='
SELECT t->'dcfc_sessions' AS dcfc_sessions, t->'dcfc_busy_min' AS dcfc_busy, t->'dcfc_mean_session_min' AS mean_session,
       t->'dcfc_above_floor_while_waiting_min' AS above_floor_waiting,
       t->'dcfc_above_85_while_waiting_min' AS above_85_waiting,
       t->'mean_cars_waiting' AS mean_waiting, t->'max_cars_waiting' AS max_waiting
  FROM (SELECT public.ottoq_challenger_taper_tax('ad106e55-e775-4780-b853-418f504d4bcf') AS t) x;
-- READ (2026-09-27 20:52 UTC): 82 DCFC sessions, 3,713 busy DCFC-minutes, a mean session of 45.3 minutes, 20.1 of them
--   above the floor. **1,403 DCFC-minutes (37.8%) went to cars at or above the 80% floor while cars waited**, 743 to cars
--   above 85%. Cars waited in all 557 minutes, a mean 37.2 at once and at most 60. L2 added 2,377 minutes above the floor
--   while cars waited. Against 6ddd827e and 6e0352a0 (0398 §3: 40.3% and 39.6%) the share is the same: G257 holds on a
--   third busy day, starting three hours earlier.

-- ══ §3 WHAT THE COCKPITS READ ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin (Intelligence › Challenge & learn), PULSE (OTTO-Q › Challenge & Learn) and the three decision streams read
--   `ottoq_challenger_board` and `ottoq_activity_feed_v2`. Under 0537 the feed must carry exactly one flag per listed
--   episode and one grade per listed closed episode; the board's `sightings` must count the rest. The feed is read over
--   the whole run (`p_window_ticks => 100000`); the cockpits read its default 240-tick window.

\echo '=== 0400 §3 — the board and the feed against the ledger ==='
WITH f AS (SELECT * FROM public.ottoq_challenger_findings WHERE sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'),
     feed AS (SELECT v.action
                FROM public.ottoq_activity_feed_v2('ad106e55-e775-4780-b853-418f504d4bcf', 100000, NULL, false, 100000) v
               WHERE v.action IN ('challenger_flag', 'challenger_grade')),
     b AS (SELECT public.ottoq_challenger_board('ad106e55-e775-4780-b853-418f504d4bcf') AS j)
SELECT (SELECT count(*) FROM f WHERE scans_seen >= 2) AS listed_episodes,
       (SELECT count(*) FROM f WHERE scans_seen >= 2 AND status = 'closed') AS listed_closed,
       (SELECT count(*) FROM feed WHERE action = 'challenger_flag') AS feed_flags,
       (SELECT count(*) FROM feed WHERE action = 'challenger_grade') AS feed_grades,
       (SELECT count(*) FROM f WHERE scans_seen < 2) AS one_scan_sightings,
       (SELECT sum(COALESCE((q->'sightings'->>'transient')::int, 0) + COALESCE((q->'sightings'->>'pending')::int, 0))
          FROM b, jsonb_array_elements(b.j->'questions') q) AS board_sightings;
-- READ (2026-09-27 20:52 UTC): listed 52, closed 52; feed flags 52, feed grades 52; one-scan sightings 60, board
--   sightings 60 (Q1 25, Q2 32, Q3 3, none pending). **The three cockpits' reads agree with the ledger exactly.** The
--   board's per-question lines read Q1 `run` 42 episodes, 42 confirmed, claimed saving 964.3 min, `lifetime` 42 of 42
--   graded (`hit_rate` 1); Q2 no episodes; Q3 10 episodes, 8 confirmed and 2 inconclusive (`hit_rate` 1). The twin and
--   PULSE render the lifetime line as `right 42 of 42 graded (100%) across 1 run`: §2(b) and G264 are why that line needs
--   to say what the grade measures.

-- ══ §4 0535 ON A LIVE DAY ══════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0400 §4 — top-offs asked on the run, and how they ended ==='
SELECT a.approval_type, a.status, COALESCE(a.payload->>'expired_reason', '-') AS expired_reason, count(*) AS approvals
  FROM public.ottoq_ops_approvals a
 WHERE a.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ (2026-09-27 20:52 UTC): **no top-off was asked all day** (no `opportunistic_charge` row): 0535's `vehicle_moved_on`
--   expiry had nothing to act on. At the 90% day ceiling a session ends at 89.5, and the planner raised none (the
--   control arm of pair 102 raised 2 in 540 minutes). The only approvals were 90 in-depot reassignments: 88 declined by
--   the automatic gate and 2 expired at the run's end.

-- ══ §5 THE STRONGEST CONFIRMATIONS: A FAST CHARGE PLANNED BEFORE 6 AM KEEPS THE NIGHT CEILING (G263) ═════════════════
--
--   `twin.ottoq_sim_advance_charge_sessions` stops a session at
--   `LEAST(vehicles.target_soc, ottoq_target_soc_cap(stall_type, session.started_at, run))`, and
--   `ottoq_charge_plan_for_visit` sets the car's target from the same ceiling at plan time, marked
--   `no_mid_session_switch`. The DCFC ceiling is `dcfc_target_soc_day` (90) outside the depot night and
--   `dcfc_target_soc_night` (100) inside it (`ottoq_is_depot_night`: 8 PM to 6 AM CT). A busy_day run opens at 5:03 AM,
--   so every fast charge planned in its first hour keeps the night ceiling for its whole session, however long it runs
--   into the day. For a car whose own target is 100 (LFP, `ottoq_charge_plan_for_visit`) that ceiling binds.

\echo '=== 0400 §5(a) — DCFC sessions by the ceiling they were started under ==='
SELECT public.ottoq_is_depot_night(os.started_at) AS started_in_night,
       public.ottoq_target_soc_cap('dcfc', os.started_at, os.sim_run_id) AS ceiling_at_start,
       count(*) AS sessions, count(*) FILTER (WHERE os.soc_end >= 95) AS ended_95_plus,
       round(avg(os.soc_start)) AS mean_soc_start, round(avg(os.soc_end)) AS mean_soc_end,
       round(avg(EXTRACT(epoch FROM COALESCE(os.ended_at, r.sim_clock_current) - os.started_at) / 60), 1) AS mean_min
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = os.sim_run_id
 WHERE os.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf' AND st.stall_type = 'dcfc'
 GROUP BY 1, 2 ORDER BY 1 DESC;
-- READ (2026-09-27 20:52 UTC):
--     started in the night  ceiling  sessions  ended 95+  mean SoC start -> end  mean min
--     yes (5:03-6:00 AM)      100        12         2           41 -> 87           55.9
--     no                       90        70         0           47 -> 87           43.5

\echo '=== 0400 §5(b) — the sessions that charged past 90%: when they crossed it, and the power they drew above it ==='
WITH s AS (
  SELECT os.id, v.display_name, st.stall_code, os.started_at, os.ended_at, os.soc_start, os.soc_end
    FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
    JOIN public.vehicles v ON v.id = os.vehicle_id
   WHERE os.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf' AND st.stall_type = 'dcfc' AND os.soc_end > 90),
mv AS (
  SELECT m.ocpp_session_id, m.sim_clock_at,
         (SELECT (x->>'value')::numeric FROM jsonb_array_elements(m.payload->'sampledValue') x
           WHERE x->>'measurand' = 'SoC') AS soc,
         (SELECT (x->>'value')::numeric FROM jsonb_array_elements(m.payload->'sampledValue') x
           WHERE x->>'measurand' = 'Power.Active.Import') AS kw
    FROM public.ottoq_ocpp_messages m WHERE m.ocpp_session_id IN (SELECT id FROM s) AND m.message_type = 'MeterValues')
SELECT s.display_name, s.stall_code, to_char(s.started_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS start_ct,
       to_char(s.ended_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS end_ct, s.soc_start, s.soc_end,
       to_char(min(mv.sim_clock_at) FILTER (WHERE mv.soc >= 90) AT TIME ZONE 'America/Chicago', 'HH24:MI')
         AS crossed_90_ct,
       round(EXTRACT(epoch FROM s.ended_at - min(mv.sim_clock_at) FILTER (WHERE mv.soc >= 90)) / 60, 1) AS min_above_90,
       round(avg(mv.kw) FILTER (WHERE mv.soc >= 90), 1) AS mean_kw_above_90,
       (SELECT string_agg(f.finding_id || ' ' || f.grade || ', ' || f.scans_seen || ' scans', '; ')
          FROM public.ottoq_challenger_findings f WHERE f.entity_id = s.id) AS challenger
  FROM s JOIN mv ON mv.ocpp_session_id = s.id
 GROUP BY s.id, s.display_name, s.stall_code, s.started_at, s.ended_at, s.soc_start, s.soc_end ORDER BY s.started_at;
-- READ (2026-09-27 20:52 UTC): two sessions, both night-started, both found by the challenger.
--     Waymo-AV-029  DCFC-STALL-10  5:15 -> 6:40 AM  81 -> 100%  crossed 90 at 5:45  55.8 min above 90 at 9.4 kW  Q1 61
--     Waymo-AV-020  DCFC-STALL-05  5:17 -> 6:45 AM  81 -> 100%  crossed 90 at 5:47  57.5 min above 90 at 9.0 kW  Q1 62
--   Below 90 the same sessions drew 15.9 and 15.6 kW. Both were planned `overnight_dcfc_to_100` at 5:13 AM and plugged in
--   on their reservations (`reservation_honoured`); both arrived above the floor, while 19 cars waited, 15 below it. The
--   challenger flagged both at its first listed scan (5:23 AM, 10 and 11 scans): charged on 78 and 82 minutes while the
--   longest waiter, Zoox-003, waited on 79 and 87. The day's two longest Q1 episodes are the night ceiling (G263).

\echo '=== 0400 §5(c) — what each night-started fast charge was told to stop at (the StartTransaction target) ==='
SELECT public.ottoq_is_depot_night(os.started_at) AS started_in_night,
       (SELECT m.payload->>'target_soc_pct' FROM public.ottoq_ocpp_messages m
         WHERE m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction' LIMIT 1) AS start_target,
       count(*) AS sessions
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
 WHERE os.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf' AND st.stall_type = 'dcfc'
 GROUP BY 1, 2 ORDER BY 1 DESC, 2;
-- READ (2026-09-27 20:52 UTC): night-started 2 told 100, 9 told 85, 1 told 90; day-started 65 told 90, 5 told 85. A
--   session stops at the lower of its car's own target and the ceiling, so the night ceiling binds only for a car whose
--   own target is above 90: the two booked by appointment at night, whose plan asked 100 (a car with no recorded
--   chemistry is planned as LFP).

\echo '=== 0400 §5(d) — the lever, registered as an experiment rather than enacted ==='
SELECT e.experiment_id, e.param_key, e.control_value, e.treatment_value, e.sim_start, e.ticks, e.sim_min_per_tick,
       e.primary_metric, e.run_after, c.agent_writable
  FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c ON c.param_key = e.param_key
 WHERE e.experiment_id = '11b546b1-2de1-4aaf-8eae-b2c760902f74';
-- READ (2026-09-27 20:52 UTC): 11b546b1, `dcfc_target_soc_night` 100 against 90, arms from 2026-09-01 10:03 UTC (5:03 AM
--   CT) for 90 ticks of 6 sim-minutes, primary `unmet_demand_car_hours`, `run_after` 2026-09-28 11:00 UTC,
--   `agent_writable` false. Registered at 20:09 UTC. `ottoq_dial_next_experiment` still names 143a11c7, so tonight's
--   window (1:00-5:41 AM CT) goes to the two experiments collecting their first looks. It waits for the next window
--   Chase opens; a win is a recommendation, not a change.
