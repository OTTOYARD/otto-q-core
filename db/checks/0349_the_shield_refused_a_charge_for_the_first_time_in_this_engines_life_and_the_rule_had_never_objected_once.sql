-- 0349  **`EN.001.grid_capacity_ceiling` — `safety_critical`, `enforcement='block'`, **zero failures in
--       8,587 lifetime evaluations** — refused a charge. Four times, on a live run, five minutes after the
--       run started. `"would exceed engineering cap: 1318.9 + 350.0 = 1668.9 kW (cap with margin:
--       1620.0 kW)"`.**
--
--       **This is the gap `0345` §3 named in writing — *"costs nothing today because the site power ceiling
--       has never been hit; the day it is, the engine starts the charge anyway"* — and `0428` closed it
--       three and a half hours before it mattered.**
--
--       **AND THE REFUSAL IS VERIFIED BY OUTCOME, NOT BY LOG: `sessions_that_started_anyway = 0`.** No
--       `ocpp_sessions` row appeared on either charger within five seconds of its refusal. The engine did
--       not start the charge.
--
--       Run `6a8a7029-e7c4-4521-a4f5-606e48e2a465`, `busy_day`, seed 920348, twin depot.
--       Measured 2026-09-22 ~17:5x UTC (12:5x CT).
--
-- ══ §1 WHAT HAPPENED, AND THE COUNTERFACTUAL ════════════════════════════════
--
--     4 refusal events · 4 distinct (charger, tick) pairs · 2 distinct DCFC chargers · 350 kW each
--     rule      EN.001.grid_capacity_ceiling   severity safety_critical   enforcement block
--     tick 1    1318.9 + 350.0 = 1668.9 kW     against a 1620.0 kW cap-with-margin
--     tick 2    1340.2 + 350.0 = 1690.2 kW     against the same cap
--     of 545 `charge_session_start` evaluations on this run
--
-- **Before `0428`, every one of those four would have been `recorded_only`** — the row written, the verdict
-- discarded by `PERFORM`, and both 350 kW charges started. The site would have committed **1,668.9 kW
-- against a 1,620 kW engineering cap: 48.9 kW over, twice, in two consecutive ticks.**
--
-- That is the entire argument of `0345` and `0428`, observed rather than reasoned:
--
--   * `0337` found the discard and (correctly, at the time) said **do not** turn enforcement on, because the
--     rules at that checkpoint were broken.
--   * `0424` fixed the broken one (`HW.002`, which could not pass).
--   * `0345` measured what remained: four energy rules, **0 failures in 8,587 evaluations each**, wired to a
--     caller that threw their answer away — *"the day it is, the engine starts the charge anyway."*
--   * `0428` promoted the checkpoint, with P4 refusing to apply unless the ledger showed zero would-block
--     rows first (it read 21,610 / 0).
--   * **Three and a half hours later the ceiling was hit and the shield held.**
--
-- ══ §2 THE CAVEAT, BECAUSE ONE NUMBER HERE LOOKS ALARMING AND IS NOT THE RULE'S INPUT ══
--
-- Summing `ocpp_sessions.max_rate_limit_kw` over the 36 active sessions gives **2,037.6 kW**, which is
-- *above* the 1,620 kW cap and reads like an ongoing violation. **It is not, and conflating the two would be
-- this branch's most-repeated error.** That column is per-session **nameplate ceiling** — the most that
-- session could draw — and `EN.001` evaluates **actual aggregate draw**, which it reported as 1,318.9 and
-- 1,340.2 kW at the two refusals. A fleet of sessions whose nameplates sum above the cap is normal and is
-- what a charge-management layer exists to handle; a fleet whose *draw* exceeds it is the violation.
--
-- **So do not quote `sum(max_rate_limit_kw)` as site load.** `EN.001`'s own reason string carries the number
-- that matters, and it is the only one to quote.
--
-- ══ §3 `0429` VERIFIED ON LIVE TRAFFIC ══════════════════════════════════════
--
--     SELECT * FROM public.ottoq_assert_event_depot_attribution('<this run>');
--
--     entity_type  class                    events  unattributed  verdict
--     depot        identity                     61             0  OK          <-- was 100% NULL before 0429
--     stall        attributed_at_emit          714             0  OK
--     ocpp_session attributed_at_emit          126             0  OK
--     sdr          attributed_at_emit           53             0  OK
--     vehicle      derivable_not_inferred    1,388             4  NOT_INFERRED BY DESIGN (G158)
--     system       no_depot_by_design            8             8  NO_DEPOT_BY_DESIGN
--
-- **All 61 depot events on this run carry their depot.** Every one of them would have been invisible to a
-- query written to rule 8's mandated predicate this morning. And the `vehicle` class reads exactly what
-- `0429` §2 said it should — **`NOT_INFERRED BY DESIGN`**, which is honest state rather than a failure.
--
-- ══ §4 G157 AND G121 DID *NOT* REPRODUCE, WHICH IS INFORMATION AND NOT EXONERATION ══
--
-- Both open questions needed exactly this run. At this moment, on 36 active sessions:
--
--     stall_kind  active  vehicle_moved_away  pointer_empty  holds_other  available_while_charging
--     l2              23                   0              0            0                        0
--     dcfc             6                   0              0            0                        0
--
-- **Zero divergence of any kind, and zero G121 instances across all 158 twin stalls.**
--
-- **What that does and does not mean.** `0347` measured 42 G157 incidents accumulating over ~45 minutes of
-- engine time on the *previous* run, and `0348` found G121 at 0 instances then too. A clean reading five
-- minutes into a fresh run is **not** evidence the defects are fixed — nothing was changed that would fix
-- them, and `0347`'s mechanism (a charge session outliving its vehicle's stall assignment) needs a vehicle
-- to be *re-tasked mid-charge*, which takes contention time to arise. **The honest statement: the conditions
-- that produce them had not yet occurred on this run.** `0334`'s rule in its other direction — an early
-- window is as misleading as a lifetime total.
--
-- The instruments are now proven to run against a live run, which is what this file adds for them.
--
-- ══ §5 THREE PROCESS FINDINGS FROM GETTING THE RUN STARTED, ALL WORTH KEEPING ══
--
--   1. **`ottoq_start_demo_run` cannot be called through a 60-second channel.** Its `ottoq_purge_prior_runs`
--      is the last statement and the expensive one; a client disconnect at 60 s rolls the whole transaction
--      back, **including the run it had already created**. Two attempts died that way with no trace.
--   2. **It also needs `statement_timeout = 0`, and the reason is an FK.** Scheduled through `pg_cron`
--      without it, the purge died on `UPDATE ONLY ottoq_events SET parent_event_id = NULL` — the
--      `ON DELETE SET NULL` cascade from `ottoq_events_parent_event_id_fkey`, which touches every child of
--      every deleted event. **The engine's own long jobs (746) prefix `SET statement_timeout = 0` for
--      exactly this reason;** mine did not, and that is the whole difference between the failed attempt and
--      the successful one.
--   3. **`pg_sleep` inside a statement does NOT advance the transaction snapshot, so poll-by-sleeping lies.**
--      Every `SELECT pg_sleep(n), (SELECT … )` poll returned the world as of *statement start*: I read
--      `my_run = 0` four minutes after the run was created, and `now()` kept returning the same timestamp
--      while `clock_timestamp()` moved. **A poll must be a fresh statement.** This is the same family as
--      everything else on this branch — a real reading of a question it was not about.
--
-- **And `cron.job_run_details` confirmed G141's warning in a new way:** the successful job reported
-- `status='succeeded'` with `return_message='SET'` **while the real work was still running**, because
-- pg_cron files the first statement's result. Only `pg_stat_activity` showed the truth.
--
-- **Cleanup, because a one-off cron job is not one-off:** both scheduled jobs used a `MI HH * * *`
-- expression, which fires **daily**. Both were unscheduled immediately (`cron.job` holds zero `oneoff%`
-- rows) — otherwise this file would have started a demo run every day at 17:45 UTC forever.

\echo '=== 0349 §1 — the first real refusal at an enforcing checkpoint, and what it said ==='
SELECT rule_code, severity, enforcement, passed, left(reason,110) AS reason, evaluated_at
  FROM public.ottoq_rule_evaluations
 WHERE action_context='charge_session_start' AND enforcement_taken='blocked'
   AND sim_run_id='6a8a7029-e7c4-4521-a4f5-606e48e2a465'
 ORDER BY evaluated_at;
-- EN.001.grid_capacity_ceiling, safety_critical/block, 4 rows across 2 ticks and 2 DCFC chargers.
-- 1318.9 + 350.0 = 1668.9 against a 1620.0 cap. Before 0428 all four were recorded_only and both
-- charges would have started -- 48.9 kW over the engineering cap, twice.

\echo '=== 0349 §1b — VERIFIED BY OUTCOME: no session started on those chargers ==='
WITH ref AS (
  SELECT (payload->>'charger_id')::uuid AS charger_id, occurred_at
    FROM public.ottoq_events WHERE event_type='ottoq.charge_start_refused')
SELECT count(*) AS refusal_events,
       count(DISTINCT (charger_id, occurred_at)) AS distinct_refusals,
       count(DISTINCT charger_id) AS distinct_chargers,
       (SELECT count(*) FROM ref r
          JOIN public.ottoq_ocpp_chargers c ON c.charger_id = r.charger_id
          JOIN public.ocpp_sessions s ON s.charge_point_id = c.ocpp_identifier
             AND s.started_at BETWEEN r.occurred_at - interval '5 s' AND r.occurred_at + interval '5 s')
         AS sessions_that_started_anyway
  FROM ref;
-- sessions_that_started_anyway = 0. The refusal is an OUTCOME, not a log line. This is the assertion that
-- separates 0428 from the five checkpoints that are still advisory.

\echo '=== 0349 §2 — the number NOT to quote: nameplate sum is not site load ==='
SELECT count(*) AS active_sessions,
       round(sum(max_rate_limit_kw)::numeric,1) AS committed_nameplate_kw,
       round(max(max_rate_limit_kw)::numeric,1) AS largest_single_kw
  FROM public.ocpp_sessions
 WHERE sim_run_id='6a8a7029-e7c4-4521-a4f5-606e48e2a465' AND status='active';
-- 2,037.6 kW of NAMEPLATE across 36 sessions, above the 1,620 cap -- and NOT a violation. EN.001 reads
-- actual aggregate draw (1,318.9 / 1,340.2 at the refusals). Never quote sum(max_rate_limit_kw) as load.

\echo '=== 0349 §3 — 0429 verified on live traffic: every depot event carries its depot ==='
SELECT * FROM public.ottoq_assert_event_depot_attribution('6a8a7029-e7c4-4521-a4f5-606e48e2a465');
-- depot: 61 events, 0 unattributed, OK -- all 61 were invisible to a rule-8 query this morning.
-- vehicle: NOT_INFERRED BY DESIGN (G158), which is honest state and not a failure.

\echo '=== 0349 §4 — G157 and G121 had not yet reproduced on this run ==='
SELECT st.stall_type::text AS stall_kind,
       count(*) AS active_sessions,
       count(*) FILTER (WHERE v.current_stall_id IS DISTINCT FROM s.stall_id) AS vehicle_moved_away,
       count(*) FILTER (WHERE st.current_vehicle_id IS NULL)                  AS pointer_empty,
       count(*) FILTER (WHERE st.current_vehicle_id IS NOT NULL
                          AND st.current_vehicle_id <> s.vehicle_id)          AS holds_other,
       count(*) FILTER (WHERE st.status::text='available')                    AS available_while_charging
  FROM public.ocpp_sessions s
  JOIN public.stalls st ON st.id = s.stall_id
  JOIN public.vehicles v ON v.id = s.vehicle_id
 WHERE s.status='active' AND st.depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 2 DESC;
-- All zeros. NOT evidence of a fix -- nothing was changed that would fix them, and 0347's mechanism needs
-- a vehicle re-tasked mid-charge, which takes contention time. The conditions had not yet occurred.
