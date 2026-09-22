-- 0345  **Chase, reading `0337`: "most of the rules don't actually stop anything. They write a note saying
--       'I object' and the system proceeds anyway. Six of the ten checkpoints work that way. Adding more
--       rules adds more unread notes. If none of our rules work, then we can't accurately calculate or
--       determine anything."**
--
--       **He is right about the mechanism and the six. He is wrong that it makes the engine unmeasurable,
--       and the reason is the finding of this check: at the six discarding checkpoints, only FOUR
--       (rule, context) pairs have ever produced a refusal at all — and every one of the four is a rule
--       whose INPUT was broken, all three of which were fixed today.** The discard was masking broken
--       rules, not masking danger.
--
--       Measured 2026-09-22 ~16:4x UTC (11:4x CT). Twin depot and fixture pooled deliberately — this is a
--       census of code paths, not of depot state, so rule 8's predicate does not apply. Where a rate is
--       quoted it is windowed on the fix that produced it (`0334`'s standing rule).
--
-- ══ §1 THE CENSUS, PER (CALLER, CONTEXT), AND A WHITESPACE NEAR-MISS ═════════
--
-- Ten action contexts are probed, by ten caller functions. **Four contexts are HONOURED** — the caller
-- captures `would_block` and branches on it — **six are ADVISORY**, the caller `PERFORM`s the probe and the
-- rows are discarded by definition:
--
--     HONOURED (4 contexts)
--       task_start            ottoq.ottoq_enact_inspection_seam, public.ottoq_decide_tick (x3 sites)
--       stall_assignment      public.ottoq_decide_tick, public.ottoq_shield_and_log
--       redeployment          public.ottoq_decide_tick, public.ottoq_shield_and_log
--       bess_dispatch         public.ottoq_decide_tick
--
--     ADVISORY (6 contexts)
--       charge_session_start  twin.ottoq_sim_start_charge_session          PERFORM
--       task_completion       public.ottoq_probe_task_completion (wrapper) PERFORM by both its callers
--       vehicle_state_change  public.ottoq_vehicles_state_change           PERFORM
--       stall_state_change    public.ottoq_stalls_state_change             PERFORM
--       bess_state_change     public.ottoq_bess_units_state_change         PERFORM
--       policy_write          public.ottoq_policy_set                      PERFORM
--
-- **AND A NEAR-MISS THAT WOULD HAVE MADE THIS CHECK WRONG, which is the fourth instance of one hazard this
-- repo has already named.** `ottoq_decide_tick` probes at SIX sites. Searching for the literal
-- `COALESCE(v_blocks,0)>0` found the branch at five of them and NOT at the sixth, and I was one sentence
-- away from reporting the decide path as a *mixed* caller that honours five of its six probes. The sixth
-- site's branch is `IF COALESCE(v_blocks,0) > 0 THEN` — **spaces around the `>`.** It honours six of six.
-- Same class as `0337`'s own near-miss (`IF v_blocks > 0` vs `IF COALESCE(v_blocks,0) > 0`) and `0332`'s
-- whitespace-sensitive ILIKE: **an assertion a formatting difference can flip is not an assertion.** The
-- only thing that caught it was reading the site instead of trusting the count.
--
-- Note also `twin.ottoq_sim_advance_visit_atoms` matches `ottoq_shield_probe` on a raw grep and mentions it
-- **zero** times once comments are stripped — it calls the wrapper, not the probe. A caller census that
-- does not strip comments overcounts.
--
-- ══ §2 THE FINDING: FOUR PAIRS CAN REFUSE, AND ALL FOUR WERE BROKEN RULES ════
--
-- A row records a refusal only when `would_block` is true, and `ottoq_shield_probe` computes that as
-- **`NOT passed AND enforcement = 'block'`**. So a rule whose `enforcement` is `shadow`, `warn` or
-- `log_only` **cannot produce a refusal at all**, and discarding its verdict is a no-op by construction.
--
-- Across the six advisory contexts, that leaves exactly four (rule, context) pairs:
--
--     context               rule                              enf     evals   would_block   status of the RULE
--     -------------------   -------------------------------   -----   -----   -----------   ------------------
--     charge_session_start  HW.002.charger_state_precondition block   8,395         4,664   COULD NOT PASS -- fixed 0424
--     task_completion       HW.003.sensor_liveness            block   7,632         1,616   NO JURISDICTION -- fixed 0426
--     task_completion       HW.006.physical_presence_verif.   block     688           476   NO LEGITIMATE INPUT -- fixed 0427
--     bess_state_change     SM.006.bess_transition_validity   block     567            15   MISATTRIBUTED -- fixed 0423
--
-- **And the two highest-traffic advisory contexts produce ZERO refusals, on 155,914 evaluations between
-- them**, because their rules are `shadow`:
--
--     vehicle_state_change  SM.001.vehicle_transition_validity shadow 80,072   0   (6,804 failures, all shadow)
--     stall_state_change    SM.003.stall_transition_validity   shadow 75,842   0   (0 failures)
--     policy_write          AI.001.agent_dial_within_envelope  log_only  724   0   (envelope clamped in 0414)
--
-- **So "six of ten checkpoints discard the verdict" is true and "six of ten checkpoints throw away real
-- protection" is not.** Three of the six had nothing to throw away; the other three were throwing away
-- false alarms from rules with broken inputs, and `0423`/`0424`/`0426`/`0427` fixed all four inputs.
--
-- **WINDOWED ON EACH FIX — the refusal rate at the advisory points is now essentially zero:**
--
--     HW.002  since 0424 (15:05:52)   3,702 evals   0 failed   0 would_block   (was 100% failed)
--     HW.003  since 0426 (15:54:23)   3,362 evals   0 failed   0 would_block   (was 1,616)
--     HW.006  since 0427 (16:30:08)   3,362 evals  16 failed  16 would_block   <-- REAL, see db/checks/0346
--
-- ══ §3 THE ONE GENUINELY OPEN SAFETY GAP, AND IT IS THE PROMOTION TARGET ═════
--
-- **Four energy rules are consulted at every charge start, all `enforcement='block'`, two of them
-- `safety_critical` — and the caller discards all four:**
--
--     EN.001.grid_capacity_ceiling     safety_critical  block   8,587 evals   0 failed
--     EN.005.grid_event_hardstop       safety_critical  block   8,587 evals   0 failed
--     EN.002.stall_power_ceiling       critical         block   8,587 evals   0 failed
--     EN.004.demand_response_compliance critical        block   8,587 evals   0 failed
--
-- **Today this costs nothing, because there is nothing to discard — the site power ceiling has never once
-- been hit. The day it is, the engine starts the charge anyway.** That is the honest statement of the gap:
-- not "the rules do not work" but "at one checkpoint, four working rules are wired to a caller that cannot
-- act on them, and the reason it could not act on them has been removed."
--
-- **And the promotion is now cheap, because BOTH callers already tolerate a refusal — measured, not
-- assumed:**
--
--     twin.ottoq_sim_auto_charge_assign_tick   v_session_id := ottoq_sim_start_charge_session(...)
--                                              EXCEPTION WHEN OTHERS THEN CONTINUE;   <-- already skips
--     twin.ottoq_sim_reconcile_charge_sessions PERFORM ottoq_sim_start_charge_session(...) in a LOOP
--                                              no handler   <-- needs one added, 3 lines
--     public.ottoq_tick_invariance_reset_fleet  mentions it in a COMMENT only
--
-- So the enforcement change is: capture instead of PERFORM, refuse when `would_block > 0`, emit the refusal
-- as a first-class event, gate it on a catalogued dial so it can be switched off without a migration, and
-- add the one missing handler. **What must NOT be done is turning all six on at once** — `0337` G150
-- established that enforcing HW.002 before `0424` would have stopped the twin charging entirely, and that
-- remains the governing lesson: fix the input, measure the rate to zero, then promote, one checkpoint at a
-- time.
--
-- ══ §4 WHAT THIS DOES AND DOES NOT SAY ABOUT OUR NUMBERS ═════════════════════
--
-- Chase's conclusion — *"if none of our rules work then we can't accurately calculate or determine
-- anything"* — conflates two systems that do not share a substrate.
--
--   * **UNAFFECTED: every capacity, throughput and determinism number.** The five canonical KPIs, the
--     fourteen-atom verdict, and `0344`'s 30.3-vehicles-in-overflow all read the event stream, the stall
--     calendar and the run archives. **None of the fourteen atoms reads a rule's enforcement** — `h_evt`
--     digests `event_type|entity_id|sim_clock_at` and nothing else, read from the live
--     `ottoq_determinism_pair` source, not inferred. Of the fifteen functions that read `ottoq_events` and
--     mention `depot_id`, the four carrying a `depot_id` predicate on the event table are all audit or
--     reporting paths (`ottoq_compute_audit_trail_completeness`, `ottoq_generate_incident_report`,
--     `ottoq_replay_window`, the `ottoq_oem_dashboard_summary` view); **every engine and harness reader
--     filters on `sim_run_id`.**
--   * **AFFECTED: any sentence of the form "the safety layer prevented N things."** That number cannot be
--     taken from `enforcement_taken` without naming the probe point, which is G149 and still open.
--   * **AND THE HARD FLOOR IS NOT RULES AT ALL, which is the part the "unread notes" framing misses.** The
--     constraints that cannot be ignored are in the schema: the `ottoq_stall_bookings` EXCLUDE constraint
--     makes double-booking impossible; `HW.004.stall_single_vehicle` says in its own description that it is
--     enforced by a partial unique index rather than by its probe; and `ottoq_events` rejects every UPDATE
--     and DELETE by trigger (`trg_ottoq_events_no_update`, verified today) so the audit trail cannot be
--     edited. Those never "write a note" — they reject the write. **A rule census measures the advisory
--     layer and is silent about the layer underneath it.**

\echo '=== 0345 §1 — which callers honour the verdict and which discard it (comment-stripped) ==='
WITH callers AS (
  SELECT n.nspname AS sch, p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.prosrc ~ 'ottoq_shield_probe' AND p.proname <> 'ottoq_shield_probe')
SELECT sch||'.'||fn AS caller,
       (SELECT count(*) FROM regexp_matches(src,'ottoq_shield_probe','g')) AS probe_sites,
       (src ~ 'PERFORM\s+1?\s*\*?\s*(FROM\s+)?public\.ottoq_shield_probe') AS discards_via_perform,
       -- whitespace-tolerant ON PURPOSE: the strict form missed decide_tick's sixth site (see section 1)
       (SELECT count(*) FROM regexp_matches(src,'COALESCE\s*\(\s*v_blocks\s*,\s*0\s*\)\s*>\s*0','g')) AS honouring_branches
  FROM callers ORDER BY 1;
-- ten callers. decide_tick reads 6 probe_sites and 6 honouring_branches -- NOT 5. The strict literal
-- 'COALESCE(v_blocks,0)>0' returns 5 because one site spells it with spaces around the '>'.

\echo '=== 0345 §2 — at the six advisory contexts, only enforcement=block rules can refuse at all ==='
SELECT re.action_context, re.rule_code, r.enforcement, r.severity,
       count(*) AS evals,
       count(*) FILTER (WHERE NOT re.passed)                     AS failed,
       count(*) FILTER (WHERE re.enforcement_taken='blocked')    AS would_block_rows
  FROM public.ottoq_rule_evaluations re
  JOIN public.ottoq_rules r ON r.rule_code = re.rule_code AND r.status='active'
 WHERE re.action_context IN ('charge_session_start','task_completion','vehicle_state_change',
                             'stall_state_change','bess_state_change','policy_write')
 GROUP BY 1,2,3,4 ORDER BY would_block_rows DESC, evals DESC;
-- Four pairs carry every refusal, and all four are the rules 0423/0424/0426/0427 fixed. The two biggest
-- advisory contexts (155,914 evaluations) refuse NOTHING because SM.001/SM.003 are 'shadow' -- would_block
-- is (NOT passed AND enforcement='block'), so a shadow verdict cannot be a refusal and discarding it is a
-- no-op. SM.001 fails 6,804 times and none of them is a refusal.

\echo '=== 0345 §2b — windowed on each fix: the advisory refusal rate is now ~zero ==='
SELECT rule_code, action_context,
       count(*) AS evals_since_fix,
       count(*) FILTER (WHERE NOT passed) AS failed,
       count(*) FILTER (WHERE enforcement_taken='blocked') AS would_block
  FROM public.ottoq_rule_evaluations
 WHERE (rule_code='HW.002.charger_state_precondition' AND action_context='charge_session_start'
          AND evaluated_at >= '2026-09-22 15:05:52+00')
    OR (rule_code='HW.003.sensor_liveness' AND action_context='task_completion'
          AND evaluated_at >= '2026-09-22 15:54:23+00')
    OR (rule_code='HW.006.physical_presence_verification' AND action_context='task_completion'
          AND evaluated_at >= '2026-09-22 16:30:08+00')
 GROUP BY 1,2 ORDER BY 1;
-- HW.002 3,702/0, HW.003 3,362/0, HW.006 3,362/16. The 16 are REAL and are 0346's subject.

\echo '=== 0345 §3 — four blocking energy rules consulted at every charge start, never once refusing ==='
SELECT re.rule_code, r.severity, r.enforcement,
       count(*) AS evals, count(*) FILTER (WHERE NOT re.passed) AS failed
  FROM public.ottoq_rule_evaluations re
  JOIN public.ottoq_rules r ON r.rule_code=re.rule_code AND r.status='active'
 WHERE re.action_context='charge_session_start' AND re.rule_code LIKE 'EN.%'
 GROUP BY 1,2,3 ORDER BY 1;
-- 0 of 8,587 each. The gap is not that these rules are broken -- it is that the caller cannot act on them.
-- Promotion target, and BOTH callers of the charge start already tolerate a refusal (see section 3).

\echo '=== 0345 §4 — the hard floor is the schema, not the rules ==='
SELECT 'stall_bookings EXCLUDE (no double-booking)' AS mechanism,
       count(*) AS constraints_present
  FROM pg_constraint WHERE conrelid='public.ottoq_stall_bookings'::regclass AND contype='x'
UNION ALL
SELECT 'ottoq_events append-only trigger', count(*)
  FROM pg_trigger WHERE tgrelid='public.ottoq_events'::regclass
   AND tgname='trg_ottoq_events_no_update' AND NOT tgisinternal;
-- These reject the write. They do not write a note. A rule census cannot see them, which is why
-- "six of ten checkpoints are advisory" is not the same claim as "nothing stops anything".
