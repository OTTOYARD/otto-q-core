-- 0350  **`0349` §1b is RETRACTED IN ITS METHOD. `sessions_that_started_anyway = 0` was not a
--       measurement — it joined `ocpp_sessions.started_at`, which is a **SIM** timestamp, against
--       `ottoq_events.occurred_at`, which is **REAL**, inside a `BETWEEN … ± 5 s` window. Those two
--       domains are three weeks apart. The window could never match anything, so the zero was
--       STRUCTURAL and proved nothing.**
--
--       That file's own headline was *"THE REFUSAL IS VERIFIED BY OUTCOME, NOT BY LOG."* It was
--       verified by neither. And the defect is the one `0326` §1 named — a predicate evaluated against
--       the wrong clock — **in a file that cites `0326` §1 by number.**
--
--       **THE CONCLUSION SURVIVES, AND ON A BETTER POPULATION.** Redone in the sim domain over
--       **28** surviving refusals (`0349` had 4), no session started at any refused instant, for the
--       refused vehicle or for any other vehicle on that charger. §2 has the sequence, which is
--       stronger evidence than `0349` ever offered.
--
--       **AND EVERY FIGURE IN THIS FILE IS A POINT-IN-TIME READING THAT IS ALREADY GONE.** A demo run
--       started at ~02:15 UTC *between two of my own queries* and purged the ledgers: at 02:19:33
--       `ottoq_rule_evaluations` held **208 rows**, against the ~150,000 the sections below are
--       computed from, and `ottoq.charge_start_refused` read **0**. Per `0329`'s doctrine these numbers
--       may be quoted as measured and must NOT be offered as re-derivable — re-running the queries
--       below today returns a different, much smaller world. **This is CLAUDE.md Part 3's "cite the
--       run, never the table" happening to the measurement itself, mid-flight.**
--
--       Measured 2026-09-23 ~02:05–02:19 UTC (2026-09-22 ~21:05–21:19 CT).
--
-- ══ §1 THE CLOCK DOMAINS, WHICH NOTHING IN THIS REPO HAD WRITTEN DOWN ════════
--
--     column                          domain    evidence
--     ocpp_sessions.started_at        SIM       run sim_clock_start 2026-09-01 02:00, session min
--                                               2026-09-01 03:00, run real start 2026-09-23 01:46
--     ottoq_stall_bookings.during     SIM       established by 0326 §1
--     ottoq_events.sim_clock_at       SIM       equals the run's sim_clock_start at tick 0
--     ottoq_events.occurred_at        REAL      equals the run's real started_at
--
-- So `ocpp_sessions.started_at` may be compared to `during` and to `sim_clock_at`, and **never** to
-- `occurred_at`. `0349` §1b did the one forbidden pairing.
--
-- ══ §1b AND `occurred_at` IS WORSE THAN "REAL" — IT COLLAPSES TO A SINGLE INSTANT ══
--
-- Measured on one determinism-pair arm (`aadba3d6`):
--
--     rows 14,833 · DISTINCT occurred_at = 1 · DISTINCT sim_clock_at = 49
--
-- **Every event a pair arm writes carries the SAME `occurred_at`**, because `now()` is
-- transaction-stable and the arm is one transaction. So `occurred_at` cannot order, window, or rate
-- anything inside a pair — it is the transaction's birthday, not the event's. **Any real-clock window
-- over pair-generated events degenerates to all-or-nothing**, which is the deeper reason `0349`'s
-- `± 5 s` was hopeless: even in the right domain it would have matched either every row or none.
--
-- **STANDING TEST, and it is one line: before comparing two timestamps from this database, print
-- `min()` of each beside the run's `started_at` AND `sim_clock_start`.** Three of the four columns
-- above disagree with the name you would guess.
--
-- ══ §2 THE REFUSALS, REDONE IN THE SIM DOMAIN — AND THE SHIELD LOOKS BETTER ══
--
--     28 refusal events · 1 run (7a42982a) · 2 vehicles · 2 chargers · rule EN.001 every time
--     sessions at the refused instant, same vehicle + charger .............  0 of 28
--     sessions at the refused instant, ANY vehicle on that charger .......  0 of 28
--     the broken 0349 test, re-run on this population .................... 0 of 28  (structurally)
--
-- **The sequence is the finding.** Vehicle `…0004` was refused **27 times** between sim 09:25:15 and
-- 09:38:33 — every refusal `EN.001.grid_capacity_ceiling`, 350 kW requested — and its own session
-- then started at **09:38:52, 18.7 sim-seconds after the last refusal**, and ran to completion at
-- 10:17:59 (39 sim-minutes). **The shield held a vehicle off the grid for 13.3 sim-minutes across 27
-- attempts and admitted it once the cap allowed.** That is a deferral, not a bypass, and it is the
-- behaviour `0345` §3 predicted in writing.
--
-- **The nearest same-vehicle session to ANY refusal is 18.7 s, and it is AFTER.** Nothing sits at
-- delta 0.
--
-- **A near-miss worth keeping: a ±60 s window reported "3 started anyway" and I nearly wrote that
-- down.** All three are this admission-after-the-cap-freed, seen through a window wide enough to
-- straddle it. Widening a window until it catches something is not evidence; the signed delta and the
-- exact-instant test are.
--
-- ══ §3 THE EVENT LEDGER IS COMPLETE AT THAT CHECKPOINT, 1:1 ══════════════════
--
--     run 7a42982a: EN.001 blocked evaluations at charge_session_start = 28
--                   ottoq.charge_start_refused events                  = 28
--
-- Exactly one event per blocked evaluation, no run with one and not the other. `0428`'s event write
-- is not lossy.
--
-- ══ §4 THE WHOLE SHIELD'S EFFECT SPLIT, UNCONTAMINATED FOR THE FIRST TIME ════
--
-- `0430`'s caveat was that 4,664 of its 7,371 `refused` rows were pre-`0424` `HW.002` false alarms,
-- so the honest pair was the post-fix window (`refused=106 / recorded_only=32`). **Those rows have
-- since been purged, so this reading contains no pre-fix era at all:**
--
--     rule / context                                  effect          n    runs
--     HW.005.vehicle_one_active_task / task_start      refused       284       7
--     SLA.004.required_services_complete / redeploy    refused       195       9
--     EN.001.grid_capacity_ceiling / stall_assignment  refused       176       1
--     EN.001.grid_capacity_ceiling / charge_start      refused        28       1
--     EN.003.bess_limits / bess_dispatch               refused        10       8
--     HW.006.physical_presence / task_completion       recorded_only  77      17
--     SM.006.bess_transition_validity / bess_state     recorded_only  15       —
--                                                      refused  = 693
--                                                      recorded_only = 92
--                                                      unknown_posture = 0
--
-- **`EN.001` ALSO REFUSES AT `stall_assignment`, 176 TIMES, AND NOTHING IN THIS REPO HAD RECORDED
-- THAT.** It is the larger half of that rule's work — six times the charge-start refusals — and it
-- means the grid ceiling is enforced at two checkpoints, not one. `0345` §3 listed EN.001 among four
-- energy rules with *"0 failures in 8,587 evaluations each"* and treated the whole family as
-- untested; on this evidence EN.001 is the most active blocking rule in the energy set.
--
-- **AND THE TWO REPAIRED RULES ARE NOW VERIFIED AT SCALE:**
--
--     HW.002.charger_state_precondition   76,126 evaluations   0 failures
--     HW.003.sensor_liveness              52,593 evaluations   0 failures
--
-- HW.002 previously failed **100%** and was arithmetically incapable of passing (`0337`/`0342`);
-- HW.003 failed 808 of 808 on a scope guard it never reached (`0340`). `0424` and `0426` hold at
-- 128,719 evaluations between them.
--
-- ══ §5 G157 RE-MEASURED, AND `0346`/`0347`'s "l2-ONLY" IS HALF WRONG ═════════
--
-- `0346` saw 16 HW.006 failures, **all l2**, against 96 of 96 passing on tethered `dcfc`, and `0347`
-- concluded *"the tether exemption IS the l2/dcfc split."* On 30x the evidence:
--
--     stall_kind   failed   passed   failure rate
--     dcfc              7      720          0.96%
--     l2               39      381          9.29%
--     (no stall)        —      975   "insufficient context for presence verification"
--
-- **`dcfc` fails too.** The tether is a **~10x reduction, not an exemption**, and any sentence saying
-- the defect is confined to L2 is wrong. `0346`'s 96-of-96 was a small sample of a 0.96% event.
--
-- **The two defect forms, on 49 incidents:**
--
--     stall_kind   defect                     incidents   runs   stalls   vehicles
--     l2           holds_DIFFERENT_vehicle           22      8       14         17
--     l2           pointer_EMPTY                     20     12       11         14
--     dcfc         holds_DIFFERENT_vehicle            4      2        4          4
--     dcfc         pointer_EMPTY                      3      2        3          3
--
-- **26 of 49 are the serious form** — the stall records vehicle B while vehicle A's charge session
-- closes on it. As `0346` said, that is not a calendar double-booking and the EXCLUDE constraint is
-- not implicated; it is the physical pointer disagreeing with the session.
--
-- ══ §6 A COUNTING DEFECT IN MY OWN INSTRUMENT: `DISTINCT ON` HIDES FAILURES ══
--
--     (stall, vehicle, evaluated_at) triples ................. 1,147
--     rows per triple ....................................... 1.45
--     triples whose duplicate rows DISAGREE on `passed` ......    3
--
-- `0346` established that this ledger carries ~2 rows per triple and that quoting the row count
-- doubles the defect. **What it did not find is that the duplicates are not always copies.** Three
-- triples carry both a passed and a failed row, so a `DISTINCT ON (…) ORDER BY …` over them keeps
-- whichever sorts first and **reports 46 incidents where there are 49**. My first pass did exactly
-- that. **A de-duplication whose key does not include the value being measured can drop a failure.**
--
-- (`rows_per_triple` has also moved: 5.05 → 3.30 (`0346`) → **1.45**. Declining, cause still
-- unestablished, and still nothing identifies the caller — `ottoq_probe_task_completion` takes no
-- argument naming who asked.)
--
-- ══ §7 THE REASON THIS FILE CANNOT BE RE-RUN, WHICH IS ITSELF THE FINDING ════
--
-- **Neither of G157's two candidate homes is durable. Both are `class='engine'`.**
--
--     table                          class     rows after the 02:15 purge
--     ottoq_rule_evaluations         engine    208        (was ~150,000)
--     space_conflict_ledger          engine    24 / 2 runs (was 2,312)
--
-- **And `space_conflict_ledger` fooled me in a way worth recording.** Before the purge it read 2,312
-- rows with `min(recorded_at) = 2026-08-30`, and I took the August floor as evidence that it survives
-- purges. **After the purge it STILL reads `min(recorded_at) = 2026-08-30`**, because a couple of old
-- rows happen to remain. **A table's earliest timestamp says nothing about whether it is purged** —
-- the purge is not chronological, it is by run. Check `ottoq_run_scope_registry.class`, never the
-- oldest row. (`0347`'s conflict-ledger vocabulary — `standing_claim_contradicted`,
-- `stale_claim_displaced` — is gone; one kind remains.)
--
-- **SO THE FIX G157 NEEDS IS NOT A DIAGNOSIS, IT IS A DURABLE LEDGER.** A safety-critical rule whose
-- only record of 49 physical-pointer divergences evaporates on the next demo run cannot support any
-- claim, in either direction — the exact argument `0231` made for cuOpt and `0340` settled with an
-- append-only `class='evidence'` ledger carrying no FK to `ottoq_sim_runs`. That is the next build,
-- and it is a prerequisite for closing G157 rather than re-measuring it every morning.

\echo '=== 0350 §1 — the clock domains: compare min() of each against the run BEFORE joining ==='
SELECT r.sim_run_id,
       r.started_at::text       AS run_REAL_start,
       r.sim_clock_start::text  AS run_SIM_start,
       min(s.started_at)::text  AS ocpp_sessions_started_at_min,
       min(e.occurred_at)::text AS events_occurred_at_min,
       min(e.sim_clock_at)::text AS events_sim_clock_at_min
  FROM public.ottoq_sim_runs r
  LEFT JOIN public.ocpp_sessions s ON s.sim_run_id = r.sim_run_id
  LEFT JOIN public.ottoq_events  e ON e.sim_run_id = r.sim_run_id
 GROUP BY 1,2,3 ORDER BY r.started_at DESC LIMIT 3;
-- started_at tracks the SIM clock; occurred_at tracks the REAL clock. 0349 joined one to the other.

\echo '=== 0350 §1b — occurred_at COLLAPSES: one distinct value for a whole pair arm ==='
SELECT sim_run_id,
       count(*) AS events,
       count(DISTINCT occurred_at)  AS distinct_occurred_at,
       count(DISTINCT sim_clock_at) AS distinct_sim_clock_at
  FROM public.ottoq_events
 WHERE sim_run_id IS NOT NULL
 GROUP BY 1 ORDER BY 2 DESC LIMIT 3;
-- 14,833 events, ONE occurred_at, 49 sim_clock_at. now() is transaction-stable and an arm is one
-- transaction, so occurred_at is the transaction's birthday. It cannot order events within a pair.

\echo '=== 0350 §2 — refusals verified in the SIM domain: nothing started at the refused instant ==='
WITH ref AS (
  SELECT e.sim_clock_at, e.sim_run_id,
         (e.payload->>'charger_id')::uuid AS charger_id,
         (e.payload->>'vehicle_id')::uuid AS vehicle_id
    FROM public.ottoq_events e WHERE e.event_type='ottoq.charge_start_refused')
SELECT count(*) AS refusals,
       count(DISTINCT r.vehicle_id) AS vehicles,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_ocpp_chargers c
           JOIN public.ocpp_sessions s ON s.charge_point_id=c.ocpp_identifier
          WHERE c.charger_id=r.charger_id AND s.sim_run_id=r.sim_run_id
            AND s.started_at = r.sim_clock_at AND s.vehicle_id = r.vehicle_id)) AS own_vehicle_started,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_ocpp_chargers c
           JOIN public.ocpp_sessions s ON s.charge_point_id=c.ocpp_identifier
          WHERE c.charger_id=r.charger_id AND s.sim_run_id=r.sim_run_id
            AND s.started_at = r.sim_clock_at)) AS ANY_vehicle_started_on_that_charger
  FROM ref r;
-- 28 refusals, 0 and 0. The signed-delta view (§2 prose) shows the one admitted session arrives
-- 18.7 SIM-SECONDS AFTER the last refusal, which is the cap freeing, not a bypass.

\echo '=== 0350 §3 — one refusal event per blocked evaluation, per run ==='
SELECT COALESCE(b.sim_run_id, ev.sim_run_id) AS run,
       COALESCE(b.blocked_evals,0) AS en001_blocked_at_charge_start,
       COALESCE(ev.refusal_events,0) AS refusal_events
  FROM (SELECT sim_run_id, count(*) AS blocked_evals FROM public.ottoq_rule_evaluations
         WHERE action_context='charge_session_start' AND enforcement_taken='blocked' GROUP BY 1) b
  FULL JOIN (SELECT sim_run_id, count(*) AS refusal_events FROM public.ottoq_events
              WHERE event_type='ottoq.charge_start_refused' GROUP BY 1) ev
         ON ev.sim_run_id = b.sim_run_id
 ORDER BY 2 DESC;
-- 28 / 28 on the one run that had any. Neither column ever appears without the other.

\echo '=== 0350 §4 — the shield effect split (refused vs recorded_only), no pre-0424 era ==='
SELECT rule_code, action_context, enforcement, effect, probe_posture,
       count(*) AS n, count(DISTINCT sim_run_id) AS runs
  FROM public.ottoq_rule_evaluation_effect
 WHERE effect IN ('refused','recorded_only','unknown_posture')
 GROUP BY 1,2,3,4,5 ORDER BY n DESC;
-- refused 693 across FIVE (rule,context) pairs; recorded_only 92 across two; unknown 0.
-- EN.001 at stall_assignment (176) is the largest single refuser and was previously unrecorded.

\echo '=== 0350 §4b — the two repaired rules at scale: 0 failures ==='
SELECT rule_code, count(*) AS evaluations, count(*) FILTER (WHERE NOT passed) AS failures
  FROM public.ottoq_rule_evaluations
 WHERE rule_code LIKE 'HW.002%' OR rule_code LIKE 'HW.003%'
 GROUP BY 1 ORDER BY 2 DESC;
-- HW.002 76,126/0 (was failing 100% and could not pass); HW.003 52,593/0 (was 808/808).

\echo '=== 0350 §5 — G157 is NOT l2-only: dcfc fails at 0.96%, l2 at 9.29% ==='
WITH e AS (
  SELECT (result_payload->>'stall_id')::uuid AS pstall, entity_id, evaluated_at, passed, sim_run_id,
         result_payload
    FROM public.ottoq_rule_evaluations
   WHERE rule_code LIKE 'HW.006%' AND action_context='task_completion')
SELECT COALESCE(st.stall_type::text,'(no stall resolved)') AS stall_kind,
       count(*) FILTER (WHERE NOT e.passed) AS failed,
       count(*) FILTER (WHERE e.passed)     AS passed,
       count(DISTINCT e.pstall)             AS stalls,
       count(DISTINCT e.sim_run_id)         AS runs
  FROM e LEFT JOIN public.stalls st ON st.id = e.pstall
 GROUP BY 1 ORDER BY 2 DESC;
-- The tether is a ~10x reduction, NOT an exemption. 0347's "the tether exemption IS the l2/dcfc
-- split" is half retracted: dcfc fails 7 times across 5 stalls and 2 runs.

\echo '=== 0350 §5b — the two defect forms, de-duplicated on a key that includes `passed` ==='
WITH e AS (
  SELECT DISTINCT (result_payload->>'stall_id')::uuid AS pstall, entity_id, evaluated_at, passed,
         sim_run_id, (result_payload->>'stall_current_vehicle_id') AS held
    FROM public.ottoq_rule_evaluations
   WHERE rule_code LIKE 'HW.006%' AND action_context='task_completion' AND NOT passed
     AND result_payload->>'stall_id' IS NOT NULL)
SELECT st.stall_type::text AS stall_kind,
       CASE WHEN e.held IS NULL THEN 'pointer_EMPTY' ELSE 'holds_DIFFERENT_vehicle' END AS defect,
       count(*) AS incidents, count(DISTINCT e.sim_run_id) AS runs,
       count(DISTINCT e.pstall) AS stalls, count(DISTINCT e.entity_id) AS vehicles
  FROM e JOIN public.stalls st ON st.id = e.pstall
 GROUP BY 1,2 ORDER BY 3 DESC;
-- 49 incidents; 26 are the serious `holds_DIFFERENT_vehicle` form. NOTE the DISTINCT includes
-- `passed` -- see §6: three triples carry BOTH verdicts, and a DISTINCT ON without it reports 46.

\echo '=== 0350 §6 — the duplicate rows are not always copies: 3 triples DISAGREE ==='
WITH e AS (
  SELECT (result_payload->>'stall_id')::uuid AS pstall, entity_id, evaluated_at, passed
    FROM public.ottoq_rule_evaluations
   WHERE rule_code LIKE 'HW.006%' AND action_context='task_completion'
     AND result_payload->>'stall_id' IS NOT NULL)
SELECT count(*) AS triples, round(avg(n),2) AS rows_per_triple,
       count(*) FILTER (WHERE kinds > 1) AS triples_where_rows_DISAGREE
  FROM (SELECT pstall, entity_id, evaluated_at, count(*) AS n, count(DISTINCT passed) AS kinds
          FROM e GROUP BY 1,2,3) g;
-- 1,147 triples, 1.45 rows each, 3 disagreeing. A de-dup key that omits the measured value can
-- silently drop a failure -- which is how 46 became the wrong answer for 49.

\echo '=== 0350 §7 — why none of the above can be re-run: both homes are class=engine ==='
SELECT reg.table_name,
       string_agg(DISTINCT reg.class::text, ', ') AS registry_class,
       (SELECT count(*) FROM public.ottoq_rule_evaluations) AS rule_evals_now,
       (SELECT count(*) FROM public.space_conflict_ledger)  AS conflict_rows_now,
       (SELECT min(recorded_at)::text FROM public.space_conflict_ledger) AS conflict_earliest_row
  FROM public.ottoq_run_scope_registry reg
 WHERE reg.table_name IN ('ottoq_rule_evaluations','space_conflict_ledger')
 GROUP BY reg.table_name ORDER BY 1;
-- BOTH engine. And note `conflict_earliest_row` still reads 2026-08-30 AFTER the purge that took
-- 2,288 of its rows: an old floor does not mean a durable table. Read the registry class.
