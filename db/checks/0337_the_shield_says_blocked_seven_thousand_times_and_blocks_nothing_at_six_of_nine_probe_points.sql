-- 0337  **The 0422+0423 sweep landed 9/9, and reading its ledger produced a finding larger than the
--       one it was run to settle: `enforcement_taken='blocked'` is a RECOMMENDATION THE CALLER MAY
--       DISCARD, and six of the nine probe-point callers discard it. 5,721 of 7,626 'blocked' rows —
--       75% — record a refusal that never happened.**
--
--       And the reason the discard is LOAD-BEARING rather than sloppy: two of the shield's critical
--       rules CANNOT PASS on the twin. HW.002 compares a 90-second liveness threshold against a
--       heartbeat the twin writes once per 1800-second tick, and the charge-start reads it one tick
--       early -- 4,632 failures with a gap of exactly 1800 s and ZERO variance. If those two points
--       enforced, the twin would stop charging and stop completing walkarounds.
--
--       **And §5(a) carries a correction of this file's own first draft**, which said the heartbeat
--       column was "frozen, twenty days stale". It is neither: it is rewritten every tick, and
--       2026-09-02 is a SIM date I compared against the real calendar -- in a paragraph that then
--       disclaimed that exact defect.
--
--       Also here: 0423 verified on the full sweep rather than a spot-check, and a retraction of my own
--       `0331`.
--
--       Measured 2026-09-22 14:4x UTC (09:4x CT), against the sweep that completed 14:12:26 UTC.
--
-- ══ §1 THE SWEEP LANDED, AND 0423 IS VERIFIED ON ALL NINE COLUMNS ════════════
--
-- `ottoq_determinism_canon`: **9 of 9 enabled columns `status='current'`, `outcome='passed'`,
-- `equal=true`, `complete=true`, `disagreeing_atoms` empty, every one `satisfies_floor=true`** against
-- the recert floor `0423` set at 13:42:03.836065+00. First column 13:43:00, last (busy_day/171717/48
-- ticks) 14:12:26.
--
-- `0423` was spot-checked at 5,068 evaluations when it was applied. On the full sweep, partitioned on
-- the floor (**the standing test from `0334` — never quote a rate over a ledger without it**):
--
--     action_context          pre-0423 evals  pre failed        post-0423 evals  post failed
--     ----------------------  --------------  ----------------  ---------------  -----------
--     vehicle_state_change            30,706  6,804  (22.16%)            14,630   **0 (0.00%)**
--     bess_state_change                  231     15  ( 6.49%)               104   **0 (0.00%)**
--     stall_state_change              29,094      0  ( 0.00%)            13,828     0 (0.00%)
--
-- **SM.001 went 22.16% -> 0.00% on 14,630 post-fix evaluations, SM.006 6.49% -> 0.00% on 104.** The
-- lifetime column still reads 15.01% for `vehicle_state_change` and will keep reading that until the
-- next purge, which is exactly why the partition is not optional.
--
-- ══ §2 THE TENTH PROBE POINT, ON 9x THE SAMPLE: `0333` CONFIRMED ═════════════
--
-- `0333` read `task_completion` at 1,230 evaluations and called it "no meaningful verdict yet". At
-- 11,520 evaluations the conclusion is unchanged and now unarguable:
--
--     rule_code                             evals  real verdicts  abstained  failed  verdict
--     ------------------------------------  -----  -------------  ---------  ------  -----------------
--     HW.003.sensor_liveness                2,304          2,304          0     808  FIRING
--     HW.006.physical_presence_verification 2,304            240      2,064     234  FIRING
--     SLA.003.max_visit_duration            2,304              0      2,304       0  **VACUOUS**
--     SM.002.task_transition_validity       2,304              0      2,304       0  **VACUOUS**
--     TW.002.overnight_staging              2,304              0      2,304       0  **VACUOUS**
--
-- **Every one of the 1,042 failures is a single service.** Split by `context->>'svc'`:
-- `perimeter_walkaround` 808 evaluations per code, of which HW.003 fails **808 of 808** and HW.006
-- fails **234 of 808**. The other seven services — interior_inspection (994), interior_tidy (172),
-- triage_check (150), remote_diagnostics (94), sensor_clean (44), item_retrieval (42) — produce
-- **1,496 evaluations and zero failures of any code**.
--
-- Three of five codes abstain on 100% of calls. The two that fire, fire only on the service whose
-- phantom bay booking is already open as #23. **`0333`'s sentence stands verbatim: "task_completion is
-- now probed, and the tenth probe point produces no meaningful verdict yet."**
--
-- ══ §3 THE FINDING: 'blocked' IS A RECOMMENDATION, AND 75% OF THEM ARE DISCARDED ═══
--
-- `ottoq_rule_evaluations.enforcement_taken='blocked'` appears **7,626 times**. I read the 1,042 at
-- `task_completion` as "the engine refused 1,042 safety-critical completions" and started to write that
-- down. **It refused none of them.** 2,451 `perimeter_walkaround` atoms sit at `status='done'` on the
-- twin depot; `ottoq_probe_task_completion` contains no RAISE; `0422`'s splice calls it with `PERFORM`,
-- which discards the returned rows by definition.
--
-- So the column had to be checked at every probe point, from source. All nine callers reach the shield
-- through `public.ottoq_shield_probe`, which cannot raise — it RETURNS a `would_block` column. What
-- decides enforcement is whether the CALLER reads it:
--
--     caller                                 probe point(s)                     branches on verdict?
--     -------------------------------------  ---------------------------------  --------------------
--     ottoq.ottoq_enact_inspection_seam      task_start                         **YES**
--     public.ottoq_shield_and_log            stall_assignment, redeployment     **YES**
--     public.ottoq_decide_tick               bess_dispatch                      **YES**
--     public.ottoq_probe_task_completion     task_completion                    no  (PERFORM)
--     twin.ottoq_sim_start_charge_session    charge_session_start               no  (PERFORM)
--     public.ottoq_vehicles_state_change     vehicle_state_change               no  (PERFORM)
--     public.ottoq_stalls_state_change       stall_state_change                 no  (PERFORM)
--     public.ottoq_bess_units_state_change   bess_state_change                  no  (PERFORM)
--     public.ottoq_policy_set                policy_write                       no  (PERFORM)
--
-- The three that enforce all use the same form, `IF COALESCE(v_blocks,0) > 0 THEN`, after
-- `SELECT count(*) FILTER (WHERE would_block) INTO v_blocks`. (`ottoq_shield_and_log` serves TWO probe
-- points because it takes its context in a variable, `v_ac` — a literal search for 'redeployment'
-- finds no caller at all. Same lesson as `0326` §6(a): the wiring is not in the source text.)
--
--     blocked rows          at ENFORCING points   at DISCARDING points
--     --------------------  -------------------   --------------------
--     task_start                          1,268
--     redeployment                          611
--     bess_dispatch                          26
--     charge_session_start                                     4,664
--     task_completion                                          1,042
--     bess_state_change                                           15
--     --------------------  -------------------   --------------------
--     TOTAL                               1,905   **5,721  (75.0%)**
--
-- Twin depot only (rule 8), the discarding side: 4,632 + 1,014 + 2 = **5,648**.
--
-- **This is not the shield being decorative.** Three probe points — including `task_start`, which
-- carries 13 of the 30 codes and 831,896 evaluations — genuinely refuse. What is wrong is the LEDGER:
-- one column name, `enforcement_taken`, means "the engine refused this" at three probe points and "a
-- rule would have objected and nobody asked" at six, with nothing in the row to tell them apart.
--
-- ══ §4 RETRACTION OF MY OWN `0331`, ELEVEN HOURS OLD ═════════════════════════
--
-- `0331` says, and CLAUDE.md now repeats: *"`SM.006` is `enforcement='block'` and actually REFUSED 13
-- legitimate writes."* **It refused nothing.** `ottoq_bess_units_state_change` says so in its own
-- comment — *"MEASURE ONLY. ottoq_shield_probe logs every evaluation and returns would_block; nothing
-- here reads it"* — and returns `NEW` unconditionally with the probe in a swallowing handler. The
-- independent witness: **all 3 BESS units are `current_state='standby'`**, so the 13 `charging ->
-- standby` writes landed.
--
-- What `0331` got right, and what `0423` actually fixed, is the ATTRIBUTION. The 13 rows are
-- `actor_type='unknown'`, the last at **13:42:00.232233**; the same transition reappears as
-- `actor_type='ottoq_engine'`, passing, from **13:43:00.097686** — three minutes later, across the
-- `0423` boundary. The fix turned a critical rule's false alarm green. It did not unblock anything,
-- because nothing was blocked.
--
-- **The shape, and it is the one I keep writing rules about.** `0332` was "a duration is not a wait" —
-- I had `latency_ms` and read a dependency into it. This is the same error on a column whose name is
-- even more inviting: **`enforcement_taken='blocked'` is a value, not an outcome.** Both times the
-- honest answer was one `SELECT prosrc` away, and both times I wrote the sentence first.
--
-- ══ §5 WHY THE DISCARD IS LOAD-BEARING: TWO CRITICAL RULES ARE TAUTOLOGIES ═══
--
-- The obvious remedy — make the six discarding points enforce — would stop the twin dead. Both rules
-- that fire at the discarding points are unpassable by construction, each for its own reason:
--
--   **HW.002.charger_state_precondition (critical/block), 4,632 blocks on the twin depot. The rule
--   CANNOT PASS — not "usually fails", cannot — and the proof is that the gap has no variance.**
--   Differencing the rule's own recorded `now_ts` against its own `last_heartbeat_at` over all 4,632
--   failures: **mean 1800 s, min 1800 s, max 1800 s, exactly ONE distinct value**, against
--   `max_offline_seconds = 90`.
--
--   1800 seconds is one tick. `ottoq_sim_advance_tick_world` and `twin.ottoq_world_advance` both write
--   `UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = <the tick's sim clock>`, once per tick, gated
--   on `COALESCE(depots.feed_mode,'sim')='sim'` — and the twin depot IS `'sim'`, so it fires. **The
--   charge-session start simply runs EARLIER IN THE TICK than that update**, so it always reads the
--   previous tick's heartbeat and the gap is always exactly one tick. `max_offline_seconds = 90` is a
--   real-world OCPP heartbeat interval; the twin's heartbeat cadence is 1800 sim-seconds. **A units
--   mismatch of exactly 20x, same class as the fault-hazard units defect.**
--
--   **I FIRST WROTE THIS UP AS "the twin emits no OCPP heartbeat; the column is frozen at 2026-09-02
--   02:00:00+00, twenty days stale". EVERY CLAUSE OF THAT WAS WRONG, and the error is the one I had
--   just finished disclaiming two lines below it.** The column is not frozen — it is rewritten every
--   tick. It is not twenty days stale — **2026-09-02 is a SIM date**, the last canon run's final sim
--   clock, and I compared it against the REAL calendar to get "twenty days". That is `0326` §1's defect
--   exactly, in a paragraph whose next sentence said "Note this is NOT the sim/real clock defect of
--   `0326` §1." **Writing the disclaimer is not the same as checking it.** What saved it was asking a
--   question the wrong diagnosis could not answer — *if the column is frozen, why is every failing
--   heartbeat exactly on a :00 or :30 boundary?* — and the answer came back with zero variance.
--
--   **HW.003.sensor_liveness (safety_critical/block), 808 blocks, all `perimeter_walkaround`.** The
--   staleness values are 600/660/720/780/840/900 seconds against a 300-second threshold — i.e. the
--   atom's own elapsed duration, because the SOC sensor last reported when the atom started. The
--   walkaround is declared at 720 s (`0383`); every other service is shorter than the threshold and
--   passes 1,496 of 1,496. `0333` called this tautology on 102 failures; it holds on 808.
--
-- **So the measure-only wiring at those two points is what keeps the engine running, and "turn on
-- enforcement" is the wrong first move.** The order is: fix the rule INPUTS — for HW.002, either move
-- the heartbeat write ahead of the decide path or scale `max_offline_seconds` to the tick (the units
-- question is which clock the threshold is denominated in, and it must be answered, not tuned); for
-- HW.003, give it a sensor age that is not the atom's own duration — then confirm the failure rates go
-- to zero, and only then promote the probe — which is exactly 2.9a's blind-spot doctrine applied to
-- enforcement instead of to atoms.
--
-- ══ §6 WHAT MAY AND MAY NOT BE SAID ══════════════════════════════════════════
--
-- **SAY:** *"The shield probes ten decision points. Three of them refuse the action when a rule
-- objects; six log the objection and proceed; 75% of the ledger's 7,626 'blocked' rows are of the
-- second kind. Two critical rules currently CANNOT PASS on the twin — a charger-liveness check whose
-- 90-second threshold is compared against a heartbeat written once per 1800-second tick, and a
-- sensor-age check whose staleness is the task's own duration — and the non-enforcing wiring at
-- those points is why the twin still runs."*
--
-- **DO NOT SAY:** "N decisions were blocked by the L1 shield", from this table, without naming the
-- probe point. At six of the ten it means the opposite of what it reads.
--
-- **DO NOT SAY** (retracted, §4): "SM.006 refused 13 legitimate writes."
--
-- **UNCHANGED:** `0326` §6's *"34 of 69 (code, context) pairs, 49%"* and the 96.9% enacted-decision
-- coverage. Those measure whether a rule is CONSULTED, which is a different question from whether its
-- answer is READ — and this check is the first measurement of the second one. 2.5's standing caveat,
-- *"a wiring count is not a protection count"*, now has a second floor underneath it.
--
-- **OPEN, and named rather than guessed:** whether the 1,268 `task_start` and 611 `redeployment`
-- blocks — the enforcing side — refused work that should have proceeded. They are real refusals, so
-- they are the ones with a cost. Not measured here.

\echo '=== 0337 §1 — the sweep, and 0423 partitioned on its own recert floor ==='
SELECT scenario, seed, ticks, outcome, equal, complete,
       coalesce(array_length(disagreeing_atoms,1),0) AS n_disagree,
       satisfies_floor, certified_at
  FROM public.ottoq_determinism_canon WHERE enabled ORDER BY certified_at;
-- 9 of 9 current/passed/equal, all satisfying the 13:42:03 floor 0423 set.

SELECT action_context,
       count(*) FILTER (WHERE evaluated_at <  '2026-09-22 13:42:03.836065+00') AS pre_evals,
       count(*) FILTER (WHERE evaluated_at <  '2026-09-22 13:42:03.836065+00' AND NOT passed) AS pre_failed,
       count(*) FILTER (WHERE evaluated_at >= '2026-09-22 13:42:03.836065+00') AS post_evals,
       count(*) FILTER (WHERE evaluated_at >= '2026-09-22 13:42:03.836065+00' AND NOT passed) AS post_failed
  FROM public.ottoq_rule_evaluations
 WHERE action_context IN ('vehicle_state_change','bess_state_change','stall_state_change')
 GROUP BY 1 ORDER BY 1;
-- vehicle_state_change 6,804 -> 0 ; bess_state_change 15 -> 0. The LIFETIME column still reads 15.01%
-- for the first and will until the next purge -- which is why 0334's day/floor partition is standing.

\echo '=== 0337 §2 — every task_completion failure is one service ==='
SELECT rule_code, context->>'svc' AS svc, count(*) AS evals,
       count(*) FILTER (WHERE NOT passed) AS failed
  FROM public.ottoq_rule_evaluations
 WHERE action_context='task_completion'
 GROUP BY 1,2 ORDER BY 1, failed DESC;
-- HW.003: 808 of 808 walkaround fail, 0 of 1,496 everything else. HW.006: 234 of 808 walkaround.
-- SLA.003 / SM.002 / TW.002: 2,304 evaluations each, zero real verdicts.

SELECT * FROM public.ottoq_assert_task_completion_coverage();
-- Three of five codes report VACUOUS. The two that FIRE are the two tautologies of §5.

\echo '=== 0337 §3 — which callers READ the verdict, and which discard it ==='
WITH src AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS s
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
)
SELECT fn,
       (s ~ 'IF\s+COALESCE\(v_blocks\s*,\s*0\)\s*>\s*0|IF\s+v_blocks\s*>\s*0') AS branches_on_verdict,
       (s ~ 'PERFORM\s+1\s+FROM\s+public\.ottoq_shield_probe')                 AS discards_via_perform
  FROM src
 WHERE s ~ 'ottoq_shield_probe' AND fn !~ 'ottoq_shield_probe$'
 ORDER BY branches_on_verdict DESC, fn;
-- 3 branch, 6 discard. NOTE the regex needs the COALESCE alternative: a first pass written as
-- 'IF\s+v_blocks\s*>\s*0' returned FALSE for all three enforcing callers and would have produced the
-- much louder -- and false -- headline "the shield blocks nothing anywhere." Same class as 0332's
-- whitespace-sensitive ILIKE: an assertion a formatting difference can flip is not an assertion.

SELECT action_context,
       count(*) FILTER (WHERE enforcement_taken='blocked') AS rows_saying_blocked,
       count(*) FILTER (WHERE enforcement_taken='blocked'
                          AND depot_id='11111111-1111-1111-1111-111111111111') AS blocked_twin_depot
  FROM public.ottoq_rule_evaluations
 GROUP BY 1 HAVING count(*) FILTER (WHERE enforcement_taken='blocked') > 0
 ORDER BY rows_saying_blocked DESC;
-- Cross this against the table above: charge_session_start (4,664), task_completion (1,042) and
-- bess_state_change (15) are all DISCARDING points -- 5,721 of 7,626, 75%.

\echo '=== 0337 §4 — SM.006 refused nothing: the writes landed ==='
SELECT enforcement_taken, passed, context->>'actor_type' AS actor,
       count(*) AS n, min(evaluated_at) AS first_seen, max(evaluated_at) AS last_seen
  FROM public.ottoq_rule_evaluations
 WHERE action_context='bess_state_change'
   AND context->>'from_state'='charging' AND context->>'to_state'='standby'
 GROUP BY 1,2,3 ORDER BY n DESC;
-- 13 blocked as 'unknown', last at 13:42:00.23 -- then allowed as 'ottoq_engine' from 13:43:00.09.
-- 0423 fixed the ATTRIBUTION across that boundary. It did not unblock anything.

SELECT current_state, count(*) AS units FROM public.ottoq_bess_units GROUP BY 1;
-- All 3 in 'standby'. The charging->standby writes landed. Nothing was refused.

\echo '=== 0337 §5 — the two tautologies, and why the discard is load-bearing ==='
SELECT count(*) AS failures,
       min(EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                             - (result_payload->>'last_heartbeat_at')::timestamptz)))::int AS min_gap_s,
       max(EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                             - (result_payload->>'last_heartbeat_at')::timestamptz)))::int AS max_gap_s,
       count(DISTINCT EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                             - (result_payload->>'last_heartbeat_at')::timestamptz))::int) AS distinct_gaps,
       max((result_payload->>'max_offline_seconds')::int) AS threshold_s
  FROM public.ottoq_rule_evaluations
 WHERE action_context='charge_session_start' AND rule_code='HW.002.charger_state_precondition'
   AND NOT passed AND depot_id='11111111-1111-1111-1111-111111111111'
   AND result_payload ? 'now_ts';
-- 4,632 failures, gap min = max = 1800 s, ONE distinct value, threshold 90 s. Zero variance is the
-- proof: this is not a rule that usually fails, it is a rule that cannot pass. 1800 s is one tick --
-- the charge start runs earlier in the tick than the heartbeat UPDATE, so it always reads the previous
-- tick's value. NOTE the two readings that look like evidence of a freeze and are not: every failing
-- heartbeat sits exactly on a :00/:30 boundary (that is the tick cadence), and the stored column reads
-- 2026-09-02 (that is a SIM date -- the last canon run's final sim clock, NOT twenty days of staleness).

SELECT (SELECT count(*) FROM public.ottoq_ocpp_chargers
         WHERE depot_id='11111111-1111-1111-1111-111111111111') AS twin_chargers,
       (SELECT COALESCE(feed_mode,'sim') FROM public.depots
         WHERE id='11111111-1111-1111-1111-111111111111')       AS feed_mode_gating_the_write;
-- feed_mode='sim', so `IF v_feed_sim THEN ... SET last_heartbeat_at = <tick clock>` DOES run every
-- tick. The writer was never missing; the read is one tick early.

SELECT reason, count(*) AS n
  FROM public.ottoq_rule_evaluations
 WHERE action_context='task_completion' AND NOT passed AND rule_code='HW.003.sensor_liveness'
 GROUP BY 1 ORDER BY n DESC;
-- 600/660/720/780/840/900 seconds against threshold 300 -- the atom's own duration. The walkaround is
-- declared at 720s (0383); every shorter service passes 1,496 of 1,496.
