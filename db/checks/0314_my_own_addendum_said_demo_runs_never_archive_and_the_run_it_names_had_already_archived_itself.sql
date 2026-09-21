-- 0314  RETRACTION of the 🔴 ADDENDUM in db/migrations/0403, which is now on main via PR #201.
--
--       THE ADDENDUM SAYS, VERBATIM:
--
--         "So **a demo run that starts, ticks and stops is never archived, and never captured.**"
--
--       **IT IS FALSE, AND THE RUN IT NAMES IS THE COUNTEREXAMPLE.** `c23de1b8` — the demo run the
--       addendum was written while watching — archived at **2026-09-21 18:30:58 UTC** with
--       `reason='operator_stop'`, tick_count 610, policy `otto_q`. The capture trigger fired on that
--       INSERT and `ottoq_run_dial_ledger` + `ottoq_run_reward_ledger` each went from 0 rows to 1.
--       The addendum was written at ~18:0x and was wrong within thirty minutes of being committed.
--
--       And it is not a one-off that happened to land: **`operator_stop` archives number 49 over the
--       table's life**, the oldest surviving one from 2026-09-17, every one `policy='otto_q'`.
--
-- ══ WHY IT WAS WRONG, AND IT IS THE SAME DEFECT TWICE IN TWO DAYS ═════════
--
-- The addendum's method was: search `pg_proc` for callers of `ottoq_archive_run`, find exactly two
-- (`ottoq_determinism_pair`, `ottoq_sim_release_depot`), confirm `ottoq_sim_stop_and_reset`'s source
-- does not mention the archiver, conclude the capability does not exist. Every one of those
-- observations is individually TRUE and still checks out today. The conclusion does not follow,
-- because **the third caller is not a database function.**
--
--   supabase/functions/otto-twin-control/index.ts:152
--     p_reason: body.reason ?? "operator_stop",
--
-- The cockpit's stop path is an EDGE FUNCTION that calls `ottoq_sim_stop_and_reset` and
-- `ottoq_archive_run` as two separate RPCs. `ottoq_sim_stop_and_reset` genuinely does not archive —
-- it does not have to, because its caller does.
--
-- **The one query that settles it, and which the addendum never ran:** the reason string it saw in
-- the data is not produced by anything in the database.
--
--   SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'operator_stop';
--   -- 0
--
-- 49 rows carry a literal that no function in the database can write. That is a caller outside
-- Postgres, and it should have been the first thing asked rather than a fact discovered afterwards.
--
-- **THIRD INSTANCE OF THE CLASS IN TWO DAYS, and that is the finding worth more than the fix:**
--   (a) `0313` — "the cockpit never reads ottoq_decisions", from a grep that matched only
--       `.from('literal')` while the live surface uses `.rpc()` on a different client;
--   (b) "no function writes `model_parameters`" — false; `otto-q-api` has `updateModelParameters`;
--   (c) this one.
-- All three are the same mistake: **`pg_proc` is not the whole engine.** This system's behaviour is
-- split across database functions, edge functions and the client, and a negative claim about any of
-- them requires a census of all three, not a census of the one that is easy to query. A negative
-- claim from a single surface is a hypothesis, not a measurement.
--
-- ══ WHAT THE ADDENDUM GOT RIGHT, AND IT IS THE HALF THAT MATTERS ══════════
--
-- **The diet skew is real and is NOT retracted.** Of 1,526 archives, **1,278 are
-- `determinism_arm_complete`** — 84% — written by the recert runner. The non-cert remainder is
-- roughly 130 rows: `operator_stop` 49, the run-governor 540-minute ceiling 33, the metronome
-- 60-real-minute backstop 17, `ab_arm_complete` 12, `monitor auto-stop` 5, and a scatter of
-- test/diag rows. So left alone, the learner's diet is ~90% certification-harness runs, which
-- `0312` measured at **30.00 sim-min/tick against production's 2.00** and `0311` showed are
-- structurally half-inert on charging.
--
-- **That is the open problem, restated correctly:** not "demo runs never reach the learner" but
-- "demo runs reach the learner outnumbered nine to one by the least representative runs the engine
-- produces." The fix is a sampling or weighting decision in reanalysis, NOT a new archive call —
-- and the addendum's three proposed candidates (archive from `ottoq_sim_stop_and_reset`, from the
-- metronome ceiling path, or explicitly per run) are all solutions to a problem that does not exist.
-- **Do not implement any of them.** Two of the three would double-archive against the edge function.
--
-- **AND ONE GENUINE GAP SURVIVES:** a run stopped by neither the cockpit nor a ceiling — a session
-- that dies, a container reclaimed mid-run — still never archives, because every archiving path is
-- an explicit call by whoever stopped it. Nothing sweeps orphaned `status='running'` rows. That is
-- narrow, it is not what the addendum described, and it is left open rather than fixed here.
--
-- ══ WHAT THIS MEANS FOR G116 — BETTER THAN FILED ═══════════════════════════
--
-- `0403`/`0404` were filed with the caveat that the substrate had never captured a real run. It has
-- now, unattended, on the ordinary cockpit stop path, with no code change between the filing and the
-- capture. Measured on the first row:
--
--   reward 0.1 · kpis_weighed 5 · weight_version 1 · returns_unserved 0 · rules_blocked 417
--   rule_evaluations 40,910 · sim_min_per_tick 0.2836 · 13 dials · engine_hash 43123b34…
--
-- **`reward = 0.1` is a datum, not a grade.** Reward is only interpretable as a delta within a cell
-- (same scenario + seed + engine_hash), which is why `0404` gates promotion on a populated cell and
-- seven refusals. One row licenses no statement about how well OTTO-Q is doing.
--
-- **And the clock stamp earns itself immediately.** The row records **0.2836 sim-min/tick** — a
-- THIRD clock, against `production_live` 2.00 and `cert_harness` 30.00. `0402` added that stamp so a
-- number could state the granularity it was earned at; the first real reward row is already at a
-- granularity neither previously-measured configuration uses.

\echo '=== 0314 §1 — the addendum is falsified by the run it names ==='
SELECT sim_run_id, archived_at, reason, tick_count, policy
  FROM public.ottoq_run_archives
 WHERE sim_run_id = 'c23de1b8-62bf-4a7b-bf9d-46ce4757d510';
-- EXPECT: 1 row, reason='operator_stop', tick_count=610. The addendum says this cannot happen.

\echo '=== 0314 §2 — and it is not a one-off: 49 operator_stop archives, oldest 2026-09-17 ==='
SELECT count(*) AS operator_stop_archives,
       min(archived_at) AS oldest,
       max(archived_at) AS newest,
       count(DISTINCT policy) AS distinct_policies
  FROM public.ottoq_run_archives
 WHERE reason = 'operator_stop';

\echo '=== 0314 §3 — THE QUERY THE ADDENDUM NEVER RAN: no DB function can write that literal ==='
SELECT count(*) AS db_functions_mentioning_operator_stop
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND p.prosrc ~ 'operator_stop';
-- EXPECT: 0. 49 rows carry a string nothing in the database produces -> the caller is outside
-- Postgres. Source: supabase/functions/otto-twin-control/index.ts:152.

\echo '=== 0314 §4 — the addendum observations are each still true; only the conclusion failed ==='
SELECT p.proname,
       p.prosrc ~* 'ottoq_archive_run' AS calls_archiver
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND p.proname IN ('ottoq_sim_stop_and_reset','ottoq_start_demo_run',
                     'ottoq_determinism_pair','ottoq_sim_release_depot')
 ORDER BY 1;
-- EXPECT: stop_and_reset FALSE, start_demo_run FALSE, determinism_pair TRUE, release_depot TRUE.
-- All four as the addendum reported. The edge function is the missing third caller.

\echo '=== 0314 §5 — the diet skew, which is NOT retracted ==='
SELECT reason, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
  FROM public.ottoq_run_archives
 GROUP BY 1 ORDER BY 2 DESC LIMIT 8;
-- EXPECT: determinism_arm_complete ~84%. The learner's default diet is certification-harness runs
-- at 30.00 sim-min/tick, ~9:1 over everything else. THAT is the open problem, not archiving.

\echo '=== 0314 §6 — the capture fired unattended, and the trigger is live ==='
SELECT (SELECT count(*) FROM public.ottoq_run_dial_ledger)      AS dial_rows,
       (SELECT count(*) FROM public.ottoq_run_reward_ledger)    AS reward_rows,
       (SELECT count(*) FROM public.ottoq_dial_promotion_ledger) AS promotion_rows,
       (SELECT array_agg(tgname) FROM pg_trigger
         WHERE tgrelid = 'public.ottoq_run_archives'::regclass AND NOT tgisinternal) AS triggers;
-- EXPECT: dial_rows >= 1, reward_rows >= 1, promotion_rows = 0 (correct: promotion needs a
-- populated cell), trigger trg_ottoq_capture_run_dials present.

\echo '=== 0314 §7 — the first reward row, and the third clock ==='
SELECT sim_run_id, scenario, random_seed, reward, kpis_weighed,
       returns_unserved, rules_blocked, rule_evaluations,
       round(sim_min_per_tick::numeric, 4) AS sim_min_per_tick
  FROM public.ottoq_run_reward_ledger
 ORDER BY sim_run_id;
-- sim_min_per_tick 0.2836 against production_live 2.00 and cert_harness 30.00 (0312/0402).
-- reward 0.1 is a baseline datum; it is interpretable only as a delta inside a cell.

\echo '=== 0314 §8 — the gap that DOES survive: orphaned runs nobody stopped ==='
SELECT count(*) AS running_rows_with_no_archive
  FROM public.ottoq_sim_runs r
 WHERE r.status = 'running'
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = r.sim_run_id);
-- Every archiving path is an explicit call by whoever stopped the run. A run whose caller dies
-- mid-flight is never archived and never captured. Narrow, real, and left open here.
