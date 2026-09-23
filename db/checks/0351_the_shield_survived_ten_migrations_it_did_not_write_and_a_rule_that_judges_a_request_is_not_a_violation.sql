-- 0351  **An independent re-census of the L1 shield after TEN migrations that this branch did not write
--       and that are not in the repository (`0431`–`0440`, applied by a concurrent session — see
--       `db/migrations/0441`'s footer). The shield is structurally UNCHANGED, and none of the ten
--       touched `ottoq_rules` at all.**
--
--           declared (code,context) pairs ...... 69      identical to 0326 §6
--           distinct declared contexts ......... 31      identical
--           probe points ....................... 11      identical to 0430 V1
--           enforced / advisory / unresolvable .  5 / 5 / 1   identical to 0430 V1
--           rule rows / codes / active ......... 54 / 30 / 30
--
--       **And the row count is NOT evidence of their work, which I nearly implied.** 53 → 54 is my own
--       `0423` from 09-21: no rule row has an `updated_at` inside the last 24 hours. Checked, because
--       "a number moved while someone else was working" is not the same as "they moved it."
--
--       **THE ONE ALARMING-LOOKING FINDING IS BENIGN, AND THE REASON IS THE LESSON: A RULE THAT JUDGES A
--       REQUEST IS NOT A RULE THAT RECORDS A VIOLATION.** §2.
--
--       Measured 2026-09-23 02:35–02:50 UTC (2026-09-22 09:35–09:50 PM CT) against live run
--       `324eb0f1-957a-455f-9023-3fb7feeab9a0` (`busy_day`, twin depot, tick 279+).
--
-- ══ §1 COVERAGE HAS IMPROVED, AND THE UNIT IS ONE RUN ════════════════════════
--
-- On this single run, **26 of 30 active codes are evaluated**, against CLAUDE.md 2.5's standing "24 of
-- 30". Four are not, and **two are critical, not three** — HW.006 is now evaluated (208 evaluations)
-- because `0427` gave it a probe with a resolvable stall:
--
--     code                                     sev       enf        declared  probed  evals
--     SM.004.role_gated_actions                critical  block             7       0      0
--     SM.005.audit_note_required_on_overrides  critical  block             1       0      0
--     TW.004.tariff_window                     info      log_only          2       0      0
--     SLA.002.max_queue_depth                  warning   warn              2       0      0
--
-- `0326` §6's reconciliation stands: SM.004's seven contexts are human/UI actions with no DB path, so
-- an unprobed context for an action nobody performs costs nothing. **The test is whether the engine
-- performs the action, not the count.**
--
-- **Every `safety_critical` code is probed on every context it declares** — HW.001 (2/2), HW.003 (3/3),
-- EN.003 (1/3 declared, 1 probed), EN.005 (3/3), EN.001 (3 of 4). And the two rules repaired yesterday
-- hold on this run: **HW.002 4,133 evaluations / 0 failures, HW.003 4,074 / 0.**
--
-- ══ §1b AND A COUNTING TRAP I FELL INTO WHILE BUILDING THAT TABLE ════════════
--
-- `ottoq_rule_evaluations` is `class='engine'` and `ottoq_purge_prior_runs` deletes **by run**. So a row
-- whose `sim_run_id` is **NULL belongs to no run and is therefore IMMORTAL.** Measured:
--
--     run 324eb0f1 ....... 54,825 evaluations   179 failures   26 codes
--     (NULL run) .........     72 evaluations    16 failures    2 codes   earliest 2026-09-19
--
-- **72 rows — 0.13% of the population — carry 8.2% of all visible failures, and they are four days
-- old.** The two codes are `AI.001.agent_dial_within_envelope` (38 rows, 1 failure) and
-- `SM.006.bess_transition_validity` (34 rows, 15 failures), and SM.006 is **still writing NULL-run rows
-- now** (latest 2026-09-23 01:46:51). So SM.006's "15 failures" is the *same historical 15* `0337` §4
-- described, re-read as if current, on every run, forever.
--
-- `0337` §4 already found that these rows have `sim_run_id IS NULL` — it used that as the discriminator
-- proving the actor is misattributed. **What nobody recorded is the second consequence: NULL-run rows
-- outlive every purge and silently contaminate any lifetime rate.** My own §1 table did exactly that.
--
-- **STANDING TEST: a per-run rule figure must carry `WHERE sim_run_id = '<run>'`.** `0334`'s rule
-- ("GROUP BY the day and read the last row") in a second dimension: here it is not time that ages the
-- total, it is *immortality* — a small, ancient, failure-dense population that no purge can clear.
--
-- ══ §2 THE AGENT WROTE A DIAL BELOW ITS FLOOR — AND THE ENVELOPE HELD ════════
--
-- `AI.001.agent_dial_within_envelope` is `severity='critical'`, `enforcement='log_only'`, and it has
-- **one failure**:
--
--     "deploy_peak_fraction = 0.35 is below the agent floor 0.5"
--     by ottoq_prime · agent_lo 0.5 · agent_hi 1.0 · at policy_write · 2026-09-22 04:58:40 UTC
--
-- **Read carelessly this says the agent pushed a dial 30% below its declared floor and a `log_only`
-- rule let it through. That reading is FALSE, and the order of statements in
-- `public.ottoq_policy_set` is why:**
--
--     1.  v_final := public.ottoq_dial_clamp(p_param_key, p_param_value, p_by);   <-- CLAMP FIRST
--     2.  PERFORM ottoq_shield_probe('policy_write', … 'requested', p_param_value) <-- judges the
--                                                                                     PRE-clamp value
--     3.  INSERT … VALUES (…, v_final, …)                                          <-- stores CLAMPED
--
-- and `ottoq_dial_clamp` applies the agent envelope specifically:
-- `IF ottoq_is_agent_actor(p_by) THEN v_out := GREATEST(v_alo, LEAST(v_ahi, v_out)); END IF;`
--
-- **So AI.001 records the agent's INTENT, not the engine's state, and `log_only` is the correct posture
-- for it.** CLAUDE.md 2.5's claim that the agent's dial writes are *"clamped to the declared envelope
-- since `0414`"* is correct.
--
-- **VERIFIED BY OUTCOME, not by reading the code** — which is the discipline `0350` had to learn:
--
--     deploy_peak_fraction: 312 stored rows · all updated_by='ottoq_prime' · min 0.5 · max 1.00
--                           rows stored BELOW the agent floor of 0.5 .......... 0
--                           (catalog range is 0.30 .. 1.00, so the agent envelope is TIGHTER
--                            than the parameter's own range, and it is the binding one)
--
-- **This is the fourth member of a family that keeps appearing on this branch** — `0332` a duration is
-- not a wait, `0337` a value is not an outcome, `0350` a sim timestamp is not a real one — and the
-- general form is now clear enough to state as a rule: **before calling a rule failure a violation,
-- find out WHICH VALUE the rule was handed.** A rule that judges a request and a rule that judges a
-- write produce identical-looking failure rows.
--
-- ══ §3 AN APPARENT CONTRADICTION, RESOLVED, WITH ONE PIECE GENUINELY UNRECOVERABLE ══
--
-- Three facts that cannot all hold if those 312 writes went through the gate today:
--
--     ottoq_is_agent_actor('ottoq_prime') ................................ TRUE
--     deploy_peak_fraction.agent_writable ................................ FALSE
--     ottoq_policy_set: IF is_agent_actor(p_by) AND NOT agent_writable
--                       THEN RETURN 'not_agent_writable'
--     …yet 312 rows are stored with updated_by='ottoq_prime', the last on 2026-09-22 20:50:39
--
-- Resolved by two measurements rather than by choosing the comfortable explanation:
--
--   (a) **The gate works.** A live probe call (rolled back) returns
--       `{"ok": false, "error": "not_agent_writable", "param": "deploy_peak_fraction"}`. It refuses the
--       agent today.
--   (b) **No bypasser writes as the agent.** Nine functions write `ottoq_policy_params` directly and
--       **only `ottoq_policy_set` checks `agent_writable`** — the other eight are harness, pair, MPC and
--       fixture functions. But censused for the literals, **not one of them mentions `ottoq_prime` or
--       `deploy_peak_fraction`.** So the gate is not decorative and the eight are not the writer.
--
-- **Therefore the 312 rows were written while the dial WAS agent-writable, and it has since been
-- de-authorised.** The agent's actuator surface is now **3 of 185 dials** — `energy_demand_factor_peak`,
-- `energy_demand_factor_expensive`, `energy_reserve_shave` — all energy, where CLAUDE.md 2.5 still
-- describes **six** dial writes. The circumstantial fit for the change is the concurrent session's
-- `0438_three_of_the_agents_five_dials_did_nothing_and_its_board_never_said_so`, applied
-- `20260923012821`, which is **after** the last write at 09-22 20:50:39.
--
-- **AND THAT LAST STEP IS AN INFERENCE, NOT A MEASUREMENT, BECAUSE IT CANNOT BE MEASURED.**
-- `ottoq_policy_param_catalog` has **no `updated_at` and no `updated_by`** — its twelve columns are
-- `param_key, description, default_value, min_value, max_value, affects, min_exclusive, max_exclusive,
-- agent_writable, agent_min_value, agent_max_value, agent_max_drift_pct`. So **`agent_writable` is an
-- authorisation boundary whose changes leave no trace**: there is no way to date the flip, name who
-- flipped it, or distinguish "de-authorised yesterday" from "never authorised and something bypassed
-- the gate." I have ruled the second out by (a) and (b) above, on today's code — but a future reader
-- cannot re-derive even that much, because the code may have changed by then.
--
-- **THE ONE RECOMMENDATION FROM THIS FILE, and it is small:** give
-- `ottoq_policy_param_catalog` `updated_at` / `updated_by`, or capture the agent-authorisation flags
-- into an `evidence`-class ledger. Everything else here is either unchanged or already correct; this is
-- the only place where the engine cannot answer a question about its own safety boundary. It is NOT
-- built in this file — the catalog is shared with a concurrently-migrating session, and `0441`'s footer
-- is explicit that no reconciliation with those ten migrations has been attempted.

\echo '=== 0351 §1 — the shield after ten unseen migrations: structurally unchanged ==='
SELECT 'rule rows / codes / active' AS metric,
       count(*)||' / '||count(DISTINCT rule_code)||' / '||
       count(DISTINCT rule_code) FILTER (WHERE status='active') AS value
  FROM public.ottoq_rules
UNION ALL
SELECT 'rule rows updated in the last 24h', count(*)::text
  FROM public.ottoq_rules WHERE updated_at > now() - interval '24 hours'
UNION ALL
SELECT 'declared (code,context) pairs', count(*)::text FROM (
  SELECT DISTINCT rule_code, unnest(applies_to_actions) AS ctx
    FROM public.ottoq_rules WHERE status='active') q
UNION ALL
SELECT 'distinct declared contexts', count(DISTINCT ctx)::text FROM (
  SELECT unnest(applies_to_actions) AS ctx FROM public.ottoq_rules WHERE status='active') q
UNION ALL
SELECT 'probe points / enforced / advisory / other',
       count(*)||' / '||count(*) FILTER (WHERE posture='enforced')
       ||' / '||count(*) FILTER (WHERE posture='advisory')
       ||' / '||count(*) FILTER (WHERE posture NOT IN ('enforced','advisory'))
  FROM public.ottoq_shield_probe_posture();
-- 54/30/30, ZERO rows updated in 24h, 69 pairs, 31 contexts, 11/5/5/1. The ten migrations 0431-0440
-- did not touch ottoq_rules. 53->54 is 0423 from 09-21, not their work.

\echo '=== 0351 §1b — NULL-run evaluations are IMMORTAL: the purge deletes by run ==='
SELECT COALESCE(sim_run_id::text,'(NULL run -- survives every purge)') AS run,
       count(*) AS evals, count(*) FILTER (WHERE NOT passed) AS failures,
       count(DISTINCT rule_code) AS codes, min(evaluated_at)::text AS earliest,
       max(evaluated_at)::text AS latest
  FROM public.ottoq_rule_evaluations
 GROUP BY 1 ORDER BY 2 DESC;
-- 72 NULL-run rows (0.13%) carry 16 of 195 failures (8.2%) and are four days old. AI.001 and SM.006
-- write with sim_run_id NULL, so SM.006's "15 failures" is the SAME historical 15 on every run.
-- A per-run rule figure MUST carry WHERE sim_run_id = '<run>'.

\echo '=== 0351 §2 — AI.001 judges the REQUEST; the clamp fixes the value before it is stored ==='
SELECT (src ~ 'v_final\s*:=\s*public\.ottoq_dial_clamp') AS clamps_into_v_final,
       position('ottoq_dial_clamp' in src)               AS clamp_at,
       position('ottoq_shield_probe' in src)             AS probe_at,
       position('INSERT INTO ottoq_policy_params' in src) AS insert_at,
       (src ~ '''requested''\s*,\s*p_param_value')       AS probe_sees_PRE_clamp_value
  FROM (SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='ottoq_policy_set') s;
-- clamp BEFORE probe BEFORE insert, and the probe is handed p_param_value (pre-clamp) while the insert
-- stores v_final (post-clamp). So an AI.001 failure is the agent's INTENT, not the engine's state.

\echo '=== 0351 §2b — VERIFIED BY OUTCOME: nothing below the agent floor was ever stored ==='
SELECT count(*) AS stored_rows,
       min(param_value) AS min_stored, max(param_value) AS max_stored,
       count(*) FILTER (WHERE param_value < 0.5) AS stored_BELOW_agent_floor,
       count(*) FILTER (WHERE updated_by='ottoq_prime') AS written_by_agent,
       (SELECT min_value::text||'..'||max_value::text||' agent_writable='||agent_writable::text
          FROM public.ottoq_policy_param_catalog WHERE param_key='deploy_peak_fraction') AS catalog
  FROM public.ottoq_policy_params WHERE param_key='deploy_peak_fraction';
-- 312 rows, all by the agent, min 0.5, ZERO below the 0.5 floor -- while the catalog range allows 0.30.
-- The agent envelope is TIGHTER than the parameter range and is the binding constraint.

\echo '=== 0351 §3 — only ONE of nine direct writers of ottoq_policy_params checks agent_writable ==='
WITH f AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq'))
SELECT fn,
       (src ~ 'agent_writable')            AS checks_agent_writable,
       (src ~ 'ottoq_prime')               AS mentions_the_agent,
       (src ~ 'deploy_peak_fraction')      AS mentions_that_dial
  FROM f
 WHERE src ~ '(INSERT\s+INTO|UPDATE)\s+(public\.)?ottoq_policy_params'
 ORDER BY 2 DESC, 1;
-- Nine writers, one gate. But NOT ONE of the eight bypassers mentions ottoq_prime or that dial, so the
-- gate is not decorative -- the 312 rows were written while the dial WAS agent-writable.

\echo '=== 0351 §3b — the agent actuator surface, and a boundary with no audit trail ==='
SELECT count(*) AS dials_total,
       count(*) FILTER (WHERE agent_writable) AS agent_writable_now,
       string_agg(param_key, ', ' ORDER BY param_key) FILTER (WHERE agent_writable) AS which,
       (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='public' AND table_name='ottoq_policy_param_catalog'
           AND column_name IN ('updated_at','updated_by')) AS audit_columns_on_the_catalog
  FROM public.ottoq_policy_param_catalog;
-- 3 of 185, all energy dials -- CLAUDE.md 2.5 still says six. And audit_columns = 0: agent_writable is
-- an authorisation boundary whose changes leave NO trace, so the de-authorisation above cannot be
-- dated, attributed, or re-derived by a future reader. That is this file's one recommendation.
