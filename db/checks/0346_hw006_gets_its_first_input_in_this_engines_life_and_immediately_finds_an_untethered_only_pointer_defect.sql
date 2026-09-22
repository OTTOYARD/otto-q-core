-- 0346  **`0427` VERIFIED, and it earned its keep inside seven minutes. `HW.006.physical_presence_verification`
--       has carried a `stall_id` on 304 evaluations — the first legitimate inputs of its life — and it is
--       failing 16 of them. ALL SIXTEEN ARE `l2`. The tethered `dcfc` path passes 96 of 96.**
--
--       That is `0427` §3's FIRST predicted branch, stated before applying: *"If HW.006 FAILS on untethered
--       (L2) closes, the stall pointer is being cleared somewhere upstream of this function, which is a
--       genuine state-machine finding and is adjacent to G121."* Filed as **G157**.
--
--       Measured 2026-09-22 ~16:4x UTC (11:4x CT), windowed on `0427`'s apply (`20260922163008`).
--
-- ══ §1 THE PROBE WORKS, AND BOTH RULES IT WAS BUILT FOR NOW HAVE CASES ═══════
--
--     since 20260922163008, action_context='task_completion'
--     rule                              evals   with_stall   svc='charge'   failed
--     -------------------------------   -----   ----------   ------------   ------
--     HW.006.physical_presence_verif.   1,074          304            412       16
--     HW.003.sensor_liveness            1,074          304            412        0
--     SLA.003.max_visit_duration        1,074          304            412        0
--     SM.002.task_transition_validity   1,074          304            412        0
--     TW.002.overnight_staging          1,074          304            412        0
--
-- **`with_stall` went from 0 to 304**, which is the whole point of `0427` and the thing `0343` said had
-- never happened once. And `HW.003` — charge-only by its own scope guard (`0340`) — now sees **412 real
-- charge cases and passes every one**, which is `0427` §2's prediction confirmed: one probe moved two of
-- `task_completion`'s five vacuous codes to meaningful.
--
-- The other three remain vacuous at this point (0 failures on 1,074), unchanged and not claimed otherwise.
--
-- ══ §2 THE FINDING: L2 ONLY, AND TWO DISTINCT SUB-CAUSES ═════════════════════
--
--     stall_kind   evals   failed   pct
--     ----------   -----   ------   ----
--     l2             208       16   7.7%
--     dcfc            96        0   0.0%
--
-- **The split is exactly the discriminator `0427` §3 named.** `0427` placed the probe ABOVE the
-- tether-guarded pointer clear precisely so a tethered close (where the arm still holds the car and the
-- pointer is never cleared here) and an untethered close would both be observable. Tethered passes
-- perfectly; untethered fails 7.7% of the time. **So the pointer is being emptied before the charge-stop
-- function runs, on some L2 closes, by something that is not this function.**
--
-- **And the evaluator's own payload separates two different defects, which is why it must not be reported
-- as one number.** `ottoq_eval_hw_006_presence_verification` fails on `IS DISTINCT FROM`, so it catches
-- both an empty pointer and a pointer holding somebody else, and records which:
--
--     18 rows / 9 distinct incidents
--       12 rows / 6 incidents   stall_current_vehicle_id IS NULL      -- pointer emptied early
--        6 rows / 3 incidents   stall_current_vehicle_id = ANOTHER    -- 3 distinct other vehicles
--
-- **The second one is the serious one.** An L2 stall records vehicle B while vehicle A's charge session is
-- still open and closing on that same stall. That is not a double-booking — `ottoq_stall_bookings`'s EXCLUDE
-- constraint makes that impossible and it is not implicated — it is the **physical pointer** disagreeing
-- with the session, which is the exact defect shape CLAUDE.md's "assignment plus verification, always" rule
-- exists to catch, and which `space_conflict_ledger` exists to record. **Whether these nine incidents
-- reached that ledger is NOT measured here and is the first question of G157.**
--
-- ══ §3 A COUNTING CAVEAT THAT MUST TRAVEL WITH EVERY NUMBER FROM THIS PROBE ═══
--
-- **Among stall-carrying evaluations the rows are exactly 2.00 per (stall, vehicle, evaluated_at): 396 rows
-- over 198 distinct triples, with 396 distinct `evaluation_id`s.** So "16 failures" is **9 incidents**, and
-- anyone quoting the row count doubles the defect.
--
-- **The duplication is NOT something `0427` introduced** — checked, because that was the obvious suspicion:
-- rows per triple is **5.05 before `0427` and 3.30 after**, i.e. it predates the change and got *less*
-- duplicated, not more. (Those two ratios are over all evaluations including no-stall ones, where several
-- atoms of one vehicle share a tick timestamp and collapse into one triple; the clean 2.00 is the
-- stall-carrying subset.) **Cause not established.** The leading candidate is that a `charge` atom's
-- completion resolves the same `need_atom='charge'` booking through `0422`'s probe as the charge-session
-- close does through `0427`'s, so one physical completion is probed twice. **The one query that would
-- settle it is to stamp the probe with its call site** — `ottoq_probe_task_completion` takes no argument
-- naming its caller, which is the same gap `0337` G149 found in `enforcement_taken`: the ledger records
-- what was decided and not who asked.
--
-- **So the honest sentence: *"HW.006 has 304 legitimate inputs and fails 9 untethered incidents, none
-- tethered; the failures are 6 emptied pointers and 3 stalls holding a different vehicle; and the probe
-- double-counts by exactly two so the row count is not the incident count."***
--
-- ══ §4 WHAT IS NOT CLAIMED ═══════════════════════════════════════════════════
--
--   1. **This is not G121.** G121 is three `dcfc` stalls reading `status='available'` while holding a live
--      `current_vehicle_id` — a pointer that is too FULL, persistent across ticks. This is an `l2` pointer
--      that is too EMPTY (or points elsewhere) at one moment. `0333` made exactly this mistake in the other
--      direction and it is worth not repeating: **adjacent is not identical.** What they share is a writer
--      of `stalls.current_vehicle_id` that the signed event stream does not explain (`0341`'s finding), and
--      that is why both belong to the same census.
--   2. **HW.006 is still NOT enforcing.** `task_completion` is one of the six advisory contexts (`0345` §1);
--      `ottoq_probe_task_completion` is `PERFORM`ed by both its callers. Measured first, per 2.9a.
--      **And on this evidence it must stay that way for now: enforcing it today would refuse 7.7% of L2
--      charge completions**, which is the `0345` §3 lesson applied before rather than after the damage.
--   3. **The 9 incidents are not yet attributed to a writer.** Six functions can clear a stall pointer;
--      which of them ran between this session's start and its close is the measurement G157 needs, and it
--      needs the event stream's stall diff (`0341`: `current_vehicle_id` is present on 53,720 events), not
--      another probe.
--   4. **One run, seven minutes.** The rate is 7.7% of 208 L2 evaluations on a live demo run, not a
--      certified figure, and `0339`'s rule applies to any attempt to accumulate it across sweeps.

\echo '=== 0346 §1 — 0427 verified: HW.006 has inputs for the first time, HW.003 has real charge cases ==='
SELECT rule_code,
       count(*) AS evals,
       count(*) FILTER (WHERE context ? 'stall_id')        AS with_stall,
       count(*) FILTER (WHERE context->>'svc' = 'charge')  AS svc_charge,
       count(*) FILTER (WHERE NOT passed)                  AS failed,
       left(min(reason) FILTER (WHERE NOT passed), 90)      AS a_failure_reason
  FROM public.ottoq_rule_evaluations
 WHERE action_context='task_completion' AND evaluated_at >= '2026-09-22 16:30:08+00'
 GROUP BY 1 ORDER BY 1;
-- with_stall 304 (was 0 for the life of the engine); svc_charge 412; HW.003 0 failed on real charge cases.

\echo '=== 0346 §2 — the split that discriminates the cause: L2 only, DCFC clean ==='
SELECT st.stall_type::text AS stall_kind,
       (st.stall_type::text = 'dcfc') AS tethered_path,
       count(*) AS evals,
       count(*) FILTER (WHERE NOT re.passed) AS failed,
       round(100.0*count(*) FILTER (WHERE NOT re.passed)/count(*),1) AS pct_failed
  FROM public.ottoq_rule_evaluations re
  JOIN public.stalls st ON st.id = (re.context->>'stall_id')::uuid
 WHERE re.rule_code='HW.006.physical_presence_verification'
   AND re.action_context='task_completion'
   AND re.evaluated_at >= '2026-09-22 16:30:08+00'
 GROUP BY 1,2 ORDER BY evals DESC;
-- l2 208/16 = 7.7%; dcfc 96/0. 0427 §3's first predicted branch, and the probe was placed above the
-- tether-guarded clear specifically so this comparison would be possible.

\echo '=== 0346 §2b — two sub-causes, de-duplicated to incidents (see section 3) ==='
SELECT count(*) AS rows,
       count(DISTINCT (result_payload->>'stall_id',
                       result_payload->>'expected_vehicle_id',
                       evaluated_at))                                          AS distinct_incidents,
       count(*) FILTER (WHERE result_payload->>'stall_current_vehicle_id' IS NULL)     AS pointer_empty_rows,
       count(*) FILTER (WHERE result_payload->>'stall_current_vehicle_id' IS NOT NULL) AS pointer_other_rows,
       count(DISTINCT result_payload->>'stall_current_vehicle_id')             AS distinct_other_vehicles
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.006.physical_presence_verification' AND action_context='task_completion'
   AND NOT passed AND evaluated_at >= '2026-09-22 16:30:08+00';
-- 18 rows / 9 incidents / 12 empty / 6 pointing at 3 other vehicles. The 3 "other vehicle" incidents are an
-- L2 stall recording vehicle B while vehicle A's session closes on it -- NOT a calendar double-booking
-- (the EXCLUDE constraint is not implicated), a pointer-versus-session disagreement.

\echo '=== 0346 §3 — the 2.00x duplication, and the proof it predates 0427 ==='
SELECT count(*) AS rows,
       count(DISTINCT (context->>'stall_id', entity_id::text, evaluated_at::text)) AS distinct_triples,
       round(count(*)::numeric
             / NULLIF(count(DISTINCT (context->>'stall_id', entity_id::text, evaluated_at::text)),0), 2)
         AS rows_per_triple
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.006.physical_presence_verification' AND action_context='task_completion'
   AND evaluated_at >= '2026-09-22 16:30:08+00' AND context ? 'stall_id';
-- exactly 2.00. So 16 failing rows are 9 incidents -- never quote the row count as an incident count.

SELECT CASE WHEN evaluated_at >= '2026-09-22 16:30:08+00' THEN 'after 0427' ELSE 'before 0427' END AS era,
       count(*) AS rows,
       round(count(*)::numeric
             / NULLIF(count(DISTINCT (entity_id::text, evaluated_at::text,
                                      coalesce(context->>'stall_id','-'))),0), 2) AS rows_per_triple
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.006.physical_presence_verification' AND action_context='task_completion'
   AND evaluated_at >= '2026-09-22 15:54:23+00'
 GROUP BY 1 ORDER BY 1;
-- 5.05 before, 3.30 after: the duplication predates 0427 and DECREASED. Checked because assuming my own
-- change caused it was the obvious and wrong first guess.
