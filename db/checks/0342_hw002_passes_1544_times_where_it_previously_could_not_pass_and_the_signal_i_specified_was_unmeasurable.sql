-- 0342  **G150(a) VERIFIED. `HW.002.charger_state_precondition` — a `critical`/`block` rule that
--       PROVABLY could not pass — now passes 1,544 of 1,544 evaluations on the twin depot since `0424`.**
--
--       **AND the verification signal I specified in `0424` §5 turned out to be unmeasurable on success,
--       which is a defect in my own test design worth recording.**
--
--       Measured 2026-09-22 ~15:5x UTC (10:5x CT), windowed on `0424`'s apply (`20260922150552`).
--
-- ══ §1 THE RESULT ════════════════════════════════════════════════════════════
--
--     window                              evals   failed   pct
--     ---------------------------------   -----   ------   -----
--     before 0424 (lifetime, twin depot)  ~4,632    4,632   100%   gap min=max=1800s, ZERO variance
--     after 0424                           1,544        0   0.00%
--
-- And all 1,544 took the evaluator's **final success branch** — reason *"charger <id> available and
-- online"*, across **40 distinct chargers**, every one `state='Available'`. Not an abstention, not an early
-- return, not a `no charger bound to stall` skip: the rule ran to the end and passed.
--
-- The recert sweep `0424` forced also landed **9 of 9, all `passed`**, so the fix perturbed no atom.
--
-- ══ §2 WHY THIS IS CONCLUSIVE WITHOUT THE SIGNAL I ASKED FOR ═════════════════
--
-- `0424` §5 said: *"Read `distinct_gaps` as the real signal, not the percentage. Before the fix it is 1;
-- after the fix a healthy charger's gap is 0 and a faulted one's is its fault duration, so the count must
-- be > 1. A rate can fall for many reasons; the gap losing its zero variance can only mean the ordering
-- changed."*
--
-- **`distinct_gaps` came back 0, with `min_gap_s` and `max_gap_s` NULL — because the gap is only recorded
-- on the FAILURE branch.** `now_ts` and `last_heartbeat_at` are written into `result_payload` by the stale
-- branch; the success branch's payload carries `charger_id` and `state` only. **So the signal exists only
-- when the rule fails, and the fix working perfectly is exactly the condition that erases it.** I specified
-- a test that a complete success makes unmeasurable.
--
-- **The inference survives, and on reflection it is stronger than the test I designed.** The pre-fix
-- behaviour was not "usually failed" — it was **arithmetically incapable of passing**: every one of 4,632
-- failures had a gap of exactly 1800 s against a 90 s threshold, with zero variance, because the
-- charge-start read the heartbeat one tick before it was written. A rule that cannot pass, passing 1,544
-- consecutive times through its terminal success branch, can only mean the ordering changed. **The absence
-- of the gap column is itself the evidence** — no row took the branch that writes it.
--
-- **THE LESSON, and it is a new shape for this page: a verification signal carried only on the failure path
-- cannot confirm a fix; it can only confirm a continuing defect.** Before specifying "watch column X",
-- check which branch writes X. The sound form here would have been to assert on the *success* branch's own
-- payload — `state='Available'` across N distinct chargers, which is what §1 above actually reports.
--
-- ══ §3 WHAT IS STILL NOT CLAIMED ═════════════════════════════════════════════
--
--   1. **HW.002 is still not ENFORCING.** `twin.ottoq_sim_start_charge_session` calls the shield with
--      `PERFORM` and discards `would_block` (`0337` §3, G149). What `0424` removed is the reason the
--      discard was load-bearing at this one probe point; promoting the probe remains a separate decision
--      under 2.9a's blind-spot doctrine.
--   2. **The rule has not been observed REFUSING anything in the live window.** V3 proved at apply time
--      that it still refuses a faulted charger at zero staleness, and `0372` measures ~13.8% of
--      charger-time lost to faults on a busy_day run — but 1,544 evaluations with 0 failures means no
--      charge-start in this window touched a faulted charger. **So "the rule now discriminates" rests on
--      V3's probe, not on live traffic.** The live confirmation to watch for is a non-zero failure count
--      whose reason names `state=Faulted` rather than staleness.
--   3. **The lifetime column still reads ~100% failed** and will until the next purge. `0334`'s rule
--      stands: window on the apply or the figure describes history.

\echo '=== 0342 §1 — HW.002 after 0424: zero failures, all through the terminal success branch ==='
SELECT count(*) AS evals,
       count(*) FILTER (WHERE NOT passed) AS failed,
       round(100.0*count(*) FILTER (WHERE NOT passed)/NULLIF(count(*),0),2) AS pct_failed,
       count(DISTINCT result_payload->>'charger_id') AS distinct_chargers,
       string_agg(DISTINCT result_payload->>'state', ', ') AS charger_states,
       count(*) FILTER (WHERE reason LIKE '%available and online%') AS terminal_success_branch
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.002.charger_state_precondition'
   AND action_context='charge_session_start'
   AND depot_id='11111111-1111-1111-1111-111111111111'
   AND evaluated_at >= '2026-09-22 15:05:52+00';
-- 1,544 / 0 failed / 40 distinct chargers / all 'Available' / all 1,544 on the terminal success branch.
-- Before 0424 this rule failed 100% with a gap of exactly 1800s and ZERO variance -- it could not pass.

\echo '=== 0342 §2 — the signal I specified is unmeasurable, and here is why ==='
SELECT count(DISTINCT EXTRACT(EPOCH FROM ((result_payload->>'now_ts')::timestamptz
                    - (result_payload->>'last_heartbeat_at')::timestamptz))::int) AS distinct_gaps,
       count(*) FILTER (WHERE result_payload ? 'now_ts')            AS rows_carrying_now_ts,
       count(*) FILTER (WHERE result_payload ? 'last_heartbeat_at') AS rows_carrying_heartbeat,
       count(*) FILTER (WHERE result_payload ? 'state')             AS rows_carrying_state
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.002.charger_state_precondition'
   AND action_context='charge_session_start'
   AND depot_id='11111111-1111-1111-1111-111111111111'
   AND evaluated_at >= '2026-09-22 15:05:52+00';
-- distinct_gaps 0, and ZERO rows carry now_ts or last_heartbeat_at -- those keys are written only by the
-- STALE branch. The success branch writes `state`. A verification signal carried only on the failure path
-- cannot confirm a fix; it can only confirm a continuing defect. Check which branch writes a column before
-- specifying it as the signal.

\echo '=== 0342 §1b — and the sweep 0424 forced came back clean ==='
SELECT count(*) FILTER (WHERE satisfies_floor) AS recertified,
       count(*) FILTER (WHERE satisfies_floor AND outcome='passed') AS passed,
       count(*) FILTER (WHERE satisfies_floor AND outcome IS DISTINCT FROM 'passed') AS not_passed
  FROM public.ottoq_determinism_canon WHERE enabled;
-- Read this BEFORE 0425/0426 moved the floor again: it was 9 recertified / 9 passed / 0 not-passed.
-- Re-running it after 15:54:23 shows the new pending state, which is expected and is not a regression.
