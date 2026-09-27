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
-- READ: pending (the run's end).

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
-- READ: pending.

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
-- READ: pending.

\echo '=== 0400 §2(c) — the taper tax on this day, against 6ddd827e and 6e0352a0 (0398 §3) ==='
SELECT t->'dcfc_sessions' AS dcfc_sessions, t->'dcfc_busy_min' AS dcfc_busy, t->'dcfc_mean_session_min' AS mean_session,
       t->'dcfc_above_floor_while_waiting_min' AS above_floor_waiting, t->'dcfc_above_85_while_waiting_min' AS above_85_waiting,
       t->'mean_cars_waiting' AS mean_waiting, t->'max_cars_waiting' AS max_waiting
  FROM (SELECT public.ottoq_challenger_taper_tax('ad106e55-e775-4780-b853-418f504d4bcf') AS t) x;
-- READ: pending.

-- ══ §3 WHAT THE COCKPITS READ ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin (Intelligence › Challenge & learn), PULSE (OTTO-Q › Challenge & Learn) and the three decision streams read
--   `ottoq_challenger_board` and `ottoq_activity_feed_v2`. Under 0537 the feed must carry exactly one flag per listed
--   episode and one grade per listed closed episode; the board's `sightings` must count the rest. The feed is read over
--   the whole run (`p_window_ticks => 100000`); the cockpits read its default 240-tick window.

\echo '=== 0400 §3 — the board and the feed against the ledger ==='
WITH f AS (SELECT * FROM public.ottoq_challenger_findings WHERE sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'),
     feed AS (SELECT v.action FROM public.ottoq_activity_feed_v2('ad106e55-e775-4780-b853-418f504d4bcf', 100000, NULL, false, 100000) v
               WHERE v.action IN ('challenger_flag', 'challenger_grade')),
     b AS (SELECT public.ottoq_challenger_board('ad106e55-e775-4780-b853-418f504d4bcf') AS j)
SELECT (SELECT count(*) FROM f WHERE scans_seen >= 2) AS listed_episodes,
       (SELECT count(*) FROM f WHERE scans_seen >= 2 AND status = 'closed') AS listed_closed,
       (SELECT count(*) FROM feed WHERE action = 'challenger_flag') AS feed_flags,
       (SELECT count(*) FROM feed WHERE action = 'challenger_grade') AS feed_grades,
       (SELECT count(*) FROM f WHERE scans_seen < 2) AS one_scan_sightings,
       (SELECT sum(COALESCE((q->'sightings'->>'transient')::int, 0) + COALESCE((q->'sightings'->>'pending')::int, 0))
          FROM b, jsonb_array_elements(b.j->'questions') q) AS board_sightings;
-- READ: pending.

-- ══ §4 0535 ON A LIVE DAY ══════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0400 §4 — top-offs asked on the run, and how they ended ==='
SELECT a.approval_type, a.status, COALESCE(a.payload->>'expired_reason', '-') AS expired_reason, count(*) AS approvals
  FROM public.ottoq_ops_approvals a
 WHERE a.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
-- READ: pending.

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
-- READ: pending.

\echo '=== 0400 §5(b) — the sessions that charged past 90%: when they crossed it, and the power they drew above it ==='
WITH s AS (
  SELECT os.id, v.display_name, st.stall_code, os.started_at, os.ended_at, os.soc_start, os.soc_end
    FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id JOIN public.vehicles v ON v.id = os.vehicle_id
   WHERE os.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf' AND st.stall_type = 'dcfc' AND os.soc_end > 90),
mv AS (
  SELECT m.ocpp_session_id, m.sim_clock_at,
         (SELECT (x->>'value')::numeric FROM jsonb_array_elements(m.payload->'sampledValue') x WHERE x->>'measurand' = 'SoC') AS soc,
         (SELECT (x->>'value')::numeric FROM jsonb_array_elements(m.payload->'sampledValue') x
           WHERE x->>'measurand' = 'Power.Active.Import') AS kw
    FROM public.ottoq_ocpp_messages m WHERE m.ocpp_session_id IN (SELECT id FROM s) AND m.message_type = 'MeterValues')
SELECT s.display_name, s.stall_code, to_char(s.started_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS start_ct,
       to_char(s.ended_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS end_ct, s.soc_start, s.soc_end,
       to_char(min(mv.sim_clock_at) FILTER (WHERE mv.soc >= 90) AT TIME ZONE 'America/Chicago', 'HH24:MI') AS crossed_90_ct,
       round(EXTRACT(epoch FROM s.ended_at - min(mv.sim_clock_at) FILTER (WHERE mv.soc >= 90)) / 60, 1) AS min_above_90,
       round(avg(mv.kw) FILTER (WHERE mv.soc >= 90), 1) AS mean_kw_above_90,
       (SELECT string_agg(f.finding_id || ' ' || f.grade || ', ' || f.scans_seen || ' scans', '; ')
          FROM public.ottoq_challenger_findings f WHERE f.entity_id = s.id) AS challenger
  FROM s JOIN mv ON mv.ocpp_session_id = s.id
 GROUP BY s.id, s.display_name, s.stall_code, s.started_at, s.ended_at, s.soc_start, s.soc_end ORDER BY s.started_at;
-- READ: pending.

\echo '=== 0400 §5(c) — what each night-started fast charge was told to stop at (the StartTransaction target) ==='
SELECT public.ottoq_is_depot_night(os.started_at) AS started_in_night,
       (SELECT m.payload->>'target_soc_pct' FROM public.ottoq_ocpp_messages m
         WHERE m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction' LIMIT 1) AS start_target, count(*) AS sessions
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
 WHERE os.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf' AND st.stall_type = 'dcfc'
 GROUP BY 1, 2 ORDER BY 1 DESC, 2;
-- READ: pending.

\echo '=== 0400 §5(d) — the lever, registered as an experiment rather than enacted ==='
SELECT e.experiment_id, e.param_key, e.control_value, e.treatment_value, e.sim_start, e.ticks, e.sim_min_per_tick,
       e.primary_metric, e.run_after, c.agent_writable
  FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c ON c.param_key = e.param_key
 WHERE e.experiment_id = '11b546b1-2de1-4aaf-8eae-b2c760902f74';
-- READ: pending.
