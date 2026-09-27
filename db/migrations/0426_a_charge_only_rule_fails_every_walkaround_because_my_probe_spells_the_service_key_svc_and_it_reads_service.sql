-- migration-version: 20260922155423
-- migration-name:    a_charge_only_rule_fails_every_walkaround_because_my_probe_spells_the_service_key_svc_and_it_reads_service
--
-- 0426  **`HW.003.sensor_liveness` is `safety_critical`/`block` and fails 1,288 of 3,550 evaluations at
--       `task_completion` — every one a non-charging service — because the probe I built in `0418` and
--       wired in `0422` spells the service key `svc`, and the evaluator reads `service_code` / `service`.
--       Diagnosed in `db/checks/0340` (G150(b)).**
--
--       The rule is **charge-only by its own scope guard** and would abstain on its own. Proven on a live
--       probe, same vehicle / threshold / clock: key `svc` → `passed=false`, *"SOC sensor stale: 1821142
--       seconds old (threshold 300)"*; key `service_code` → `passed=true`, *"non-charging action
--       (perimeter_walkaround): SOC liveness N/A"*.
--
--       **`task_start` already does it right and settles the convention: 69,514 evaluations carrying
--       `service` AND `requires_charging`, and not one failure in the table's life.** `task_completion` is
--       the only probe point that spells it differently and the only one that fails.
--
--       `forces_recert` **TRUE**: `rules` is one of the fourteen atoms and this changes HW.003's verdict on
--       every non-charging task completion.
--
-- ══ §1 THE CHANGE, AND WHY IT IS AN ADD RATHER THAN A RENAME ═══════════════════
--
-- One key added to `ottoq_probe_task_completion`'s context: `'service', p_svc`, beside the existing
-- `'svc', p_svc`.
--
-- **`svc` is deliberately KEPT.** It is read by the probe's own stall resolution
-- (`ottoq_stall_bookings.need_atom = svc`, per `0418`) and by every analysis query written against this
-- probe point — `0337` §2's per-(code, svc) split is the one that produced the finding this migration
-- rests on. Renaming the key would fix one rule and blind the instrument that found it.
--
-- **`requires_charging` is deliberately NOT added.** The guard fires on EITHER a `requires_charging='false'`
-- flag OR a service name outside the charge allowlist (`charge`, `dcfc_charge`, `l2_charge`, `charging`,
-- `fast_charge`, `dc_fast_charge`). The service name alone is sufficient for all seven non-charging
-- services, and for a charge atom `service='charge'` is IN the allowlist, so the rule still evaluates for
-- real. Adding a second, redundant flag would give two places for the same fact to disagree.
--
-- ══ §2 WHAT THIS RETRACTS — THE FIX PREVIOUSLY PRESCRIBED WAS WRONG ═══════════
--
-- CLAUDE.md 2.9a and FINDINGS G150(b) both say to *"give HW.003 a sensor age that is not the task's own
-- duration."* **Do not do that.** `0333` and `0337` characterised these failures as a tautology because
-- reported staleness tracks the atom's duration to within 20 seconds. That measurement is real and
-- correctly explains **why the number is 600–900 seconds**; it does not explain **why the rule was
-- consulted at all**, and I attached it as the cause because it was consistent with the failure.
--
-- **A threshold cannot be the cause of a verdict a scope guard should have prevented.** The prescribed fix
-- would have changed a safety-critical rule's semantics to compensate for a defect in a context builder I
-- wrote. `0340` §4 carries the standing test: **when a rule fires where it obviously should not, read its
-- FIRST branch before its arithmetic.**
--
-- ══ §3 THE PREDICTED EFFECT, STATED BEFORE APPLYING SO IT IS FALSIFIABLE ══════
--
-- HW.003 will **abstain** on every non-charging completion, so it joins `SLA.003`, `SM.002` and `TW.002`
-- as **VACUOUS at this probe point** — `0337` §2 will read **four of five codes vacuous instead of three.**
--
-- **That is a worse-looking coverage number and a truer one**, and it must be reported as such rather than
-- as an improvement: the honest reading is *"`task_completion` is probed, and four of its five declared
-- codes have nothing to say about the completions this engine actually performs, because `task_completion`
-- for a CHARGE is not probed."* Nothing is gained in protection here; what is removed is 1,288
-- `safety_critical` false alarms that a reader auditing the shield would have taken for real.
--
-- **It does NOT fix HW.006**, the other firing code at this probe point. That one resolves a stall via
-- `need_atom = svc` and is handed a bay the work was never at; `0425` removes the booking. Two independent
-- defects at one probe point, and neither fixes the other.
--
-- ══ §4 PRE-FLIGHT, CHANGE, VERIFICATION ═══════════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the defect is live, and the key mismatch is exactly as measured ──
DO $$
DECLARE v_failed int; v_with_service int; v_with_svc int;
BEGIN
  SELECT count(*) FILTER (WHERE NOT passed),
         count(*) FILTER (WHERE context ? 'service' OR context ? 'service_code'),
         count(*) FILTER (WHERE context ? 'svc')
    INTO v_failed, v_with_service, v_with_svc
    FROM public.ottoq_rule_evaluations
   WHERE rule_code='HW.003.sensor_liveness' AND action_context='task_completion';

  IF v_with_svc = 0 THEN
    RAISE EXCEPTION '0426 P1: no task_completion HW.003 evaluation carries ''svc'' -- the probe context '
                    'changed or the ledger was purged. Re-derive db/checks/0340 before applying.';
  END IF;
  IF v_with_service <> 0 THEN
    RAISE EXCEPTION '0426 P1: % task_completion evaluations already carry service/service_code -- '
                    'somebody fixed this. STOP and re-read.', v_with_service;
  END IF;
  IF v_failed = 0 THEN
    RAISE EXCEPTION '0426 P1: zero HW.003 failures at task_completion -- the defect this migration fixes '
                    'is not present. Re-derive db/checks/0340.';
  END IF;
  RAISE NOTICE '0426 P1: % failures, % carry svc, 0 carry service -- defect confirmed',
               v_failed, v_with_svc;
END $$;

-- ── P2: the scope guard exists and reads the keys we are about to supply.
-- Asserted from source rather than assumed: if the evaluator stops consulting `service`, adding it is a
-- no-op and this migration is theatre.
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_eval_hw_003_sensor_liveness';
  IF v_src IS NULL THEN RAISE EXCEPTION '0426 P2: ottoq_eval_hw_003_sensor_liveness not found'; END IF;
  IF position('''service''' in v_src) = 0 THEN
    RAISE EXCEPTION '0426 P2: the evaluator no longer reads a ''service'' context key, so supplying it '
                    'would change nothing. Re-read the evaluator before applying.';
  END IF;
  IF v_src !~ 'NOT IN \(''charge''' THEN
    RAISE EXCEPTION '0426 P2: the charge-only scope guard is not in the evaluator any more -- the premise '
                    'of this migration (the rule abstains on non-charging services) is gone. STOP.';
  END IF;
  RAISE NOTICE '0426 P2: scope guard present and reads ''service''';
END $$;

-- ── P3: nothing in flight (G141: a pair is invisible to ottoq_sim_runs) ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN RAISE EXCEPTION '0426 P3: % run(s) running/paused -- apply between runs', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND query LIKE '%ottoq\_recert\_runner%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0426 P3b: a determinism pair is in flight (invisible to ottoq_sim_runs -- G141). '
                    'Only pg_stat_activity is honest about this. Wait for the sweep.';
  END IF;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0426_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_probe_task_completion';

-- ── THE CHANGE: one key added beside the existing one ──
DO $$
DECLARE
  v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_probe_task_completion';
  IF v_def IS NULL THEN RAISE EXCEPTION '0426: ottoq_probe_task_completion not found'; END IF;

  v_anchor := E'             ''svc'',         p_svc,';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0426: anchor matched % times, expected exactly 1 -- the function was reformatted; '
                    're-read pg_get_functiondef and re-derive the anchor', v_hits;
  END IF;

  -- 0426: HW.003 is charge-only by its own scope guard but reads the service under
  -- `service_code`/`service`, never `svc` -- so without this key it measures SOC staleness on a
  -- walkaround and fails it safety_critical. `svc` STAYS: the stall resolution above and every
  -- analysis query on this probe point read it. See db/checks/0340.
  v_insert := v_anchor || E'\n             ''service'',     p_svc,';

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0426: byte delta % <> expected % -- refusing a substitution that did more than one '
                    'replacement', length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0426: ottoq_probe_task_completion installed, +% bytes', length(v_new) - length(v_def);
END $$;

-- ── V1: both keys present, and `svc` was not renamed away ──
DO $$
DECLARE v_src text; v_svc int; v_service int;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_probe_task_completion';
  v_svc     := (length(v_src) - length(replace(v_src, '''svc''', '')))     / length('''svc''');
  v_service := (length(v_src) - length(replace(v_src, '''service''', ''))) / length('''service''');
  IF v_svc < 1 THEN
    RAISE EXCEPTION '0426 V1: ''svc'' is gone -- the key was RENAMED, which blinds the stall resolution '
                    'and every analysis query on this probe point';
  END IF;
  IF v_service < 1 THEN
    RAISE EXCEPTION '0426 V1: ''service'' was not added';
  END IF;
  RAISE NOTICE '0426 V1: svc present (%), service present (%) -- added, not renamed', v_svc, v_service;
END $$;

-- ── V2: THE ASSERTION THAT MATTERS. The rule must now abstain on a non-charging service
-- and must STILL evaluate for real on a charge. A fix that made HW.003 unable to fire at all
-- would be worse than the defect.
DO $$
DECLARE v_params jsonb; v_vid uuid; v_res public.ottoq_rule_result;
BEGIN
  SELECT COALESCE(default_parameters,'{}'::jsonb) INTO v_params FROM public.ottoq_rules
   WHERE rule_code='HW.003.sensor_liveness' AND status='active' LIMIT 1;
  SELECT id INTO v_vid FROM public.vehicles
   WHERE home_depot_id='11111111-1111-1111-1111-111111111111'
     AND current_soc_updated_at IS NOT NULL LIMIT 1;
  IF v_vid IS NULL THEN RAISE EXCEPTION '0426 V2: no twin-depot vehicle with SOC telemetry to probe'; END IF;

  -- (a) non-charging service, deliberately stale clock: must ABSTAIN on the scope guard.
  v_res := public.ottoq_eval_hw_003_sensor_liveness('vehicle', v_vid,
             jsonb_build_object('service','perimeter_walkaround',
                                'now_ts',(now() + interval '20 minutes')::text), v_params);
  IF NOT v_res.passed THEN
    RAISE EXCEPTION '0426 V2a: HW.003 still FAILS a non-charging service with the service key supplied '
                    '(%) -- the scope guard did not fire and this migration does not fix the defect',
                    v_res.reason;
  END IF;
  IF v_res.reason NOT LIKE '%N/A%' THEN
    RAISE EXCEPTION '0426 V2a: HW.003 passed a non-charging service but not via the scope guard (%) -- '
                    'it passed because the SOC happened to be fresh, which is not what is being asserted',
                    v_res.reason;
  END IF;

  -- (b) a CHARGE with a stale clock: must STILL FAIL. The rule keeps its teeth where it has jurisdiction.
  v_res := public.ottoq_eval_hw_003_sensor_liveness('vehicle', v_vid,
             jsonb_build_object('service','charge',
                                'now_ts',(now() + interval '20 minutes')::text), v_params);
  IF v_res.passed THEN
    RAISE EXCEPTION '0426 V2b: HW.003 PASSED a charge with 20-minute-stale SOC -- the fix has disarmed a '
                    'safety_critical rule where it DOES have jurisdiction, which is worse than the defect';
  END IF;
  RAISE NOTICE '0426 V2: abstains on perimeter_walkaround via the scope guard, still refuses a stale charge';
END $$;

-- ── LINEAGE. In the file and inside the transaction (see 0425's note on 0267/0271). ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0426_a_charge_only_rule_fails_every_walkaround_because_my_probe_spells_the_service_key_svc_and_it_reads_service',
  true,
  'Adds ''service'' beside ''svc'' in ottoq_probe_task_completion''s shield context. HW.003.sensor_liveness '
  'is safety_critical/block and charge-only by its own scope guard, but reads the service under '
  'service_code/service -- so the probe 0418 built and 0422 wired never told it what service it was '
  'judging, and it measured SOC staleness on a walk around a vehicle: 1,288 failures of 3,550. Proven on a '
  'live probe, same vehicle/threshold/clock: key ''svc'' fails "SOC sensor stale", key ''service_code'' '
  'passes "non-charging action ... SOC liveness N/A". task_start already carries service + '
  'requires_charging on 69,514 evaluations with ZERO failures, which settles the convention. TRUE because '
  '`rules` is one of the fourteen atoms. RETRACTS the fix previously prescribed in CLAUDE.md 2.9a and '
  'FINDINGS G150(b) -- "give HW.003 a sensor age that is not the task''s own duration" -- which would have '
  'changed a safety-critical rule''s semantics to compensate for a context builder I wrote: 0333/0337 read '
  'the staleness arithmetic as the cause when the real cause is a scope guard that never fired. `svc` is '
  'KEPT, not renamed (the stall resolution and every analysis query read it), and requires_charging is '
  'deliberately NOT added (the service name alone satisfies the guard; a second flag is a second place to '
  'disagree). PREDICTED EFFECT, stated before applying: HW.003 becomes VACUOUS at this probe point, so '
  '0337 section 2 reads FOUR of five codes vacuous instead of three -- a worse-looking and truer number, '
  'because task_completion for a CHARGE is not probed. Nothing is gained in protection; 1,288 '
  'safety_critical FALSE ALARMS are removed. Does NOT fix HW.006 at the same probe point -- that is 0425.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §5 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` TRUE — resweep before quoting any determinism claim.
--
-- Then, windowed on the apply (the standing rule from `0334` — the lifetime column keeps the 1,288):
--
--   SELECT rule_code,
--          count(*) AS evals,
--          count(*) FILTER (WHERE NOT passed) AS failed,
--          count(*) FILTER (WHERE reason LIKE '%N/A%') AS abstained_on_scope_guard
--     FROM public.ottoq_rule_evaluations
--    WHERE action_context='task_completion' AND rule_code='HW.003.sensor_liveness'
--      AND evaluated_at >= '<this migration's apply timestamp>'
--    GROUP BY 1;
--
-- **Expect `failed = 0` and `abstained_on_scope_guard = evals`.** If failures persist, the guard is still
-- not firing and `0340`'s diagnosis is wrong — check whether `jsonb_strip_nulls` dropped the key because
-- `p_svc` was NULL, which is the one path that would silently restore the old behaviour.
--
-- And re-run `ottoq_assert_task_completion_coverage()`: it should report **four** VACUOUS codes, with
-- HW.006 the only one producing real verdicts. Report that as the honest coverage reading, not as a
-- regression and not as an improvement.

-- ══ APPLIED ═══════════════════════════════════════════════════════════════════
--
-- **Applied 2026-09-22 15:54:23 UTC (10:54 AM CT) as `20260922155423`**, 51 seconds after `0425`, in the
-- same verified-clear window so ONE resweep covers both. All blocks ran: P1 confirmed 1,288 failures with
-- 3,550 carrying `svc` and 0 carrying `service`, P2 confirmed the scope guard is present and reads
-- `service`, the splice landed on an anchor matching exactly once, V1 confirmed added-not-renamed, and V2
-- passed BOTH halves — abstains on `perimeter_walkaround` via the guard (reason contains N/A), still
-- refuses a `charge` with 20-minute-stale SOC.
--
-- **VERIFIED independently of the migration's own asserts:** `ottoq_probe_task_completion` now carries
-- `'svc'` once AND `'service'` once — the key was added, not renamed, so the stall resolution and every
-- analysis query on this probe point still work.
--
-- **DEVIATION, declared:** as with `0424`/`0425`, whole-line comments and the psql directive were stripped
-- for the inline channel; file and submission differ by exactly those 22 characters of
-- `\set ON_ERROR_STOP on`. No other difference.
--
-- **NOT YET VERIFIED:** §5's windowed query. Expect `failed = 0` and
-- `abstained_on_scope_guard = evals` on evaluations after the apply, and
-- `ottoq_assert_task_completion_coverage()` to report **four** VACUOUS codes with HW.006 the only one
-- producing real verdicts. **Report that as the honest coverage reading — neither a regression nor an
-- improvement.** The lifetime column keeps the 1,288 (append-only), so the window is not optional.

