-- migration-version: 20260920185739
-- migration-name:    my_own_new_probe_writes_blocked_into_a_log_where_that_word_means_something_it_did_not_do
--
-- 0388  0387's PROBE IS MEASURE-ONLY AND ITS LOG ROWS SAY `enforcement_taken='blocked'`.
--       IN THIS TABLE THAT WORD MEANS THE ENGINE PREVENTED SOMETHING. IT DID NOT.
--
-- `forces_recert` **TRUE**, and §4 records that I first classified it FALSE and my own
-- preflight refused the migration and was right.
--
-- ══ 1. THE DEFECT, FOUND BY THE PATH TEST AND NOT BY READING ════════════════
--
-- `0387` wired SM.001 and SM.003 into the state-change triggers as **measuring** probes:
-- `ottoq_shield_probe` logs the evaluation, returns `would_block`, and the trigger
-- deliberately ignores it — an AFTER trigger that raised would abort the tick, which is
-- forbidden, and promoting a `critical` rule to enforcing before its pass rate is known is
-- exactly what 2.9a's blind-spot doctrine says not to do.
--
-- The rolled-back path test on a real `offline → arrived_at_gate` transition returned:
--
--   evals=1  passed=false  severity=critical
--   reason   "actor unknown not authorized for vehicle transition offline → arrived_at_gate"
--   **enforcement_taken = blocked**
--
-- The probe worked. The label is wrong. **The transition happened** — the trigger is AFTER
-- the row changed and it discards the verdict — so nothing was blocked.
--
-- And that word is load-bearing in this table. Across the six pre-existing probe points
-- `enforcement_taken='blocked'` records an action the shield actually prevented:
--
--   task_start            allowed 280,828   blocked   362
--   stall_assignment      allowed  19,040
--   charge_session_start  allowed   9,650   blocked 2,215
--   redeployment          allowed   6,854   blocked   418
--   bess_dispatch         allowed     554   blocked    14
--   policy_write          allowed     255
--
-- Those 418 at `redeployment` are SLA.004 holding vehicles back; they genuinely did not
-- deploy. So a reader — human, KPI, or a future audit — cannot distinguish my observational
-- `blocked` from those. **0387 would have made the shield's own log overstate what the
-- shield does, on a `critical` rule, at transition volume.** That is the same failure shape
-- as G28 (calling a column green when the comparison is narrower than the enforcement) and
-- as `0382` (a column named for a quantity it does not hold), committed this time by me in
-- the act of closing a coverage gap.
--
-- ══ 2. THE FIX IS THE CODEBASE'S OWN WORD FOR IT ════════════════════════════
--
-- `ottoq_evaluate_rule_core` already distinguishes the two, and `0387` simply failed to use
-- it. Verbatim:
--
--   v_taken := CASE WHEN v_enforcement = 'shadow' THEN 'shadow_pass' ELSE 'allowed' END;
--   ...
--   WHEN v_enforcement = 'block'    THEN 'blocked'
--   WHEN v_enforcement = 'warn'     THEN 'warned'
--   WHEN v_enforcement = 'log_only' THEN 'logged'
--   WHEN v_enforcement = 'shadow'   THEN 'shadow_fail'
--
-- So a rule whose `enforcement` is `'shadow'` logs `shadow_pass` / `shadow_fail`, which
-- cannot be read as an action taken. `ottoq_shield_probe` already admits
-- `status IN ('active','shadow')`, so the rule keeps being evaluated at full volume — only
-- the label changes, and it changes to the truth.
--
-- This sets `enforcement='shadow'` on the **active** version of both rules and nothing else.
-- `status` stays `active`. `severity` stays `critical` — the rule is no less serious for
-- being observed, and downgrading severity would hide it from exactly the queries that
-- should find it.
--
-- ══ 3. WHAT IS GIVEN UP, AND WHY IT IS THE RIGHT TRADE ══════════════════════
--
-- `ottoq_shield_probe` computes `would_block := (NOT passed AND enforcement = 'block')`, so
-- under shadow that column now reads FALSE for these two rules. **That loses nothing that
-- is not recoverable**: `shadow_fail` in `enforcement_taken` carries the same information
-- with none of the ambiguity, and `severity='critical'` is still on the row. The alternative
-- — keeping `would_block` truthful by leaving `enforcement='block'` — costs a permanently
-- misleading `enforcement_taken`, and one of the two has to give. A column that lies about
-- what happened is worse than a column that reads false while a clearer one reads true.
--
-- **Promotion is now a single, reversible edit** rather than a rewrite: set `enforcement`
-- back to `'block'` and the same probe starts producing `blocked` — at which point the
-- trigger must also be changed to act on the verdict, because a `blocked` label the trigger
-- ignores is this defect again. Whoever promotes it must do both. Recorded here so that
-- cannot be discovered a third time.
--
-- ══ 4. I CLASSIFIED THIS `FALSE` AND MY OWN PREFLIGHT REFUSED IT ═══════════
--
-- This changes what lands in `ottoq_rule_evaluations`, and the rules atom (`h_rule`) is one
-- of the fourteen — so the instinct was TRUE. I argued myself out of it: `0387` is already
-- `forces_recert TRUE`, so the floor had already moved, every column was already stale, and
-- a second TRUE looked like a needless seven-column recert (~193–780 seconds each) for no
-- extra coverage. I wrote the preflight to assert that condition rather than assume it.
-- **It refused the migration:**
--
--   0388 P0: 2 canon verdict(s) have been certified since 0387, so this change WOULD
--   invalidate one and must be classified forces_recert TRUE. Refusing to apply under a
--   FALSE classification.
--
-- The premise was stale by minutes. `ottoq-recert-runner` had been widened to cover the two
-- `grid_smoke` fixture columns and had certified both — at 18:58 and 18:59, after 0387's
-- 18:56:17 floor — while I was writing this file. So canons *had* been certified in the
-- window, and FALSE would have left two `current` columns whose rule evaluations no longer
-- describe the engine.
--
-- It does genuinely invalidate them, on two atoms rather than one:
--
--   `h_rule`  `enforcement_taken` for these rules becomes `shadow_fail` / `shadow_pass`
--             instead of `blocked` / `allowed`.
--   `h_evt`   `ottoq_evaluate_rule_core` emits an event for a FAIL *or* for **any**
--             shadow-tier evaluation — so shadow PASSES now emit events that were skipped.
--
-- So: TRUE. Applied with the runner paused, deliberately, so the seven twin-depot columns
-- are re-certified once after this rather than once before it and again after.
--
-- **The lesson is the preflight, not the classification.** A `forces_recert` judgement is a
-- claim about a window of time, and a window can close while the migration is being written.
-- Asserting the condition cost four lines and caught a wrong answer no postflight could.

-- ══ P0 PREFLIGHT ═══════════════════════════════════════════════════════════

DO $p0$
DECLARE v_n int; v_since int;
BEGIN
  -- 0387 must be in place, or this is reclassifying a rule nothing probes
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.proname IN ('ottoq_vehicles_state_change','ottoq_stalls_state_change')
     AND p.prosrc LIKE '%ottoq_shield_probe%';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0388 P0: 0387''s probes are not present (found % of 2)', v_n;
  END IF;

  -- both rules must currently be enforcement=block, which is the thing being corrected
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity')
     AND status='active' AND enforcement='block';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0388 P0: expected 2 active block-enforced rules to reclassify, found %', v_n;
  END IF;

  -- THE forces_recert CONDITION, asserted rather than assumed (see section 4)
  SELECT count(*) INTO v_since
    FROM public.ottoq_determinism_verdict_ledger l
   WHERE l.certified_at >= (SELECT classified_at FROM public.ottoq_cert_lineage
                             WHERE name LIKE '0387_%');
  RAISE NOTICE '0388 P0: % canon verdict(s) certified since 0387 -- this is why forces_recert is TRUE', v_since;

  -- and the runner must be paused, or every column it certifies between now and commit is
  -- invalidated the moment this lands
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='ottoq-recert-runner' AND active) THEN
    RAISE EXCEPTION '0388 P0: ottoq-recert-runner is active. Pause it before applying, or it will certify columns this migration immediately invalidates.';
  END IF;
  RAISE NOTICE '0388 P0: probes present, both rules block-enforced, recert runner paused';
END $p0$;

-- ══ THE CHANGE ═════════════════════════════════════════════════════════════

UPDATE public.ottoq_rules
   SET enforcement = 'shadow',
       updated_at  = now(),
       rationale   = COALESCE(rationale,'') ||
         E'\n\n0388: enforcement moved block -> shadow. The rule is PROBED but not enforced: '
         'its probe sits in an AFTER trigger (ottoq_vehicles_state_change / '
         'ottoq_stalls_state_change, added by 0387) which discards the verdict, because an '
         'AFTER trigger that raised would abort the tick. Under enforcement=block the core '
         'logged enforcement_taken=''blocked'' for a transition that in fact proceeded, and in '
         'ottoq_rule_evaluations that word records an action the shield actually prevented '
         '(e.g. SLA.004''s 418 blocks at redeployment). shadow makes the core log '
         'shadow_pass/shadow_fail instead, which cannot be misread. severity stays critical. '
         'TO PROMOTE: set enforcement back to block AND change the trigger to act on the '
         'verdict -- doing only the first reintroduces the defect this migration fixed.'
 WHERE rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity')
   AND status = 'active';

-- ══ POSTFLIGHT ════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity')
     AND status='active' AND enforcement='shadow' AND severity='critical';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0388 P1: expected 2 active shadow-enforced critical rules, found %', v_n;
  END IF;

  -- the ARCHIVED versions must be untouched: they record what the rule was when it ran
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity')
     AND status='archived' AND enforcement='block';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0388 P1: an archived rule version was modified (% still block-enforced, expected 2)', v_n;
  END IF;

  -- and the probe must still resolve to them, or the reclassification hid them
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_rules
                  WHERE rule_code='SM.001.vehicle_transition_validity'
                    AND status IN ('active','shadow')
                    AND 'vehicle_state_change' = ANY(applies_to_actions)) THEN
    RAISE EXCEPTION '0388 P1: SM.001 no longer resolves for the vehicle_state_change probe';
  END IF;
  RAISE NOTICE '0388 P1: both active rules shadow/critical, archived versions untouched, probe still resolves';
END $p1$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0388_my_own_new_probe_writes_blocked_into_a_log_where_that_word_means_something_it_did_not_do', true,
  'Corrects 0387, found by its rolled-back path test rather than by reading. 0387''s probes are '
  'MEASURE-ONLY -- they sit in AFTER triggers that discard the verdict, because a raising AFTER '
  'trigger would abort the tick -- but with enforcement=block the core logged '
  'enforcement_taken=''blocked'' for a transition that actually proceeded. In '
  'ottoq_rule_evaluations that word records an action the shield PREVENTED: across the six '
  'pre-existing probe points there are 3,009 such rows, including SLA.004''s 418 at '
  'redeployment, which are vehicles that genuinely did not deploy. A reader could not have '
  'distinguished my observational blocked from those, so 0387 would have made the shield''s own '
  'log overstate what the shield does, on a critical rule, at transition volume -- the G28 and '
  '0382 shape, committed while closing a coverage gap. Fixed with the codebase''s own mechanism, '
  'which 0387 simply failed to use: ottoq_evaluate_rule_core maps enforcement=shadow to '
  'shadow_pass/shadow_fail, and ottoq_shield_probe already admits status IN (active,shadow), so '
  'the rules keep being evaluated at full volume and only the label changes. severity stays '
  'critical; status stays active; the archived versions are untouched and P1 asserts it. Cost: '
  'would_block now reads false for these two, which is recoverable from shadow_fail plus '
  'severity, whereas a permanently misleading enforcement_taken is not. TO PROMOTE, both halves '
  'are required -- set enforcement back to block AND make the trigger act on the verdict; doing '
  'only the first reintroduces this defect, and that is recorded in the rule''s own rationale so '
  'it cannot be discovered a third time. forces_recert TRUE, AND I FIRST CLASSIFIED IT FALSE. I argued '
  'that 0387 had already moved the floor so nothing was left to invalidate, and wrote a '
  'preflight asserting that condition instead of assuming it. The preflight REFUSED the '
  'migration: the widened recert runner had certified both grid_smoke columns at 18:58 and '
  '18:59, after 0387''s 18:56:17 floor, while the file was being written. It invalidates on two '
  'atoms, not one -- h_rule because enforcement_taken becomes shadow_fail/shadow_pass, and h_evt '
  'because the core emits an event for ANY shadow-tier evaluation including passes, which were '
  'previously skipped. Applied with the runner paused so the seven twin columns are re-certified '
  'once after this rather than once before and again after. The lesson is the preflight: a '
  'forces_recert judgement is a claim about a window of time, and the window can close while the '
  'migration is being written.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
