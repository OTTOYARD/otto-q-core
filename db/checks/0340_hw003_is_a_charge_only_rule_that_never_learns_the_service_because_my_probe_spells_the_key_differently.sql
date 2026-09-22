-- 0340  **G150(b) is NOT a threshold problem, NOT a tautology in the rule, and the fix I wrote into
--       CLAUDE.md and FINDINGS.md — "give HW.003 a sensor age that is not the atom's own duration" —
--       would have been the wrong fix. `HW.003.sensor_liveness` is a CHARGE-ONLY rule by its own scope
--       guard, and it fails 1,288 walkaround completions because MY probe spells the context key
--       `svc` while the evaluator reads `service_code` / `service`.**
--
--       Measured 2026-09-22 ~15:3x UTC (10:3x CT).
--
-- ══ §1 THE RULE ALREADY KNOWS IT IS CHARGE-ONLY ══════════════════════════════
--
-- `public.ottoq_eval_hw_003_sensor_liveness` opens with a scope guard, and its comment states the intent
-- in full:
--
--     -- SCOPE GUARD (charge-only rule): SOC liveness gates CHARGE-RELATED decisions only.
--     -- A non-charging task transition (inspection / wash / staging) does not depend on SOC
--     -- freshness. Charging task_starts and redeployment carry no such flag and remain FULLY
--     -- gated (stale SOC still blocks them). The rule still runs and records this N/A verdict.
--     IF v_req_charge = 'false'
--        OR (v_svc <> '' AND v_svc NOT IN ('charge','dcfc_charge','l2_charge','charging',
--                                          'fast_charge','dc_fast_charge')) THEN
--
-- and it reads its inputs as
--
--     v_svc        := lower(coalesce(p_context ->> 'service_code', p_context ->> 'service', ''));
--     v_req_charge := p_context ->> 'requires_charging';
--
-- **The probe `0418` built and `0422` wired passes neither.** Its context is
-- `jsonb_build_object('svc', p_svc, 'started_at', …, 'ends_at', …, 'now_ts', …)`. So `v_svc` is `''` and
-- `v_req_charge` is NULL, which makes the guard `NULL OR FALSE` → NULL → **not taken**, and a charge-only
-- rule proceeds to measure SOC staleness on a walk around a vehicle.
--
-- ══ §2 PROVEN ON A LIVE PROBE — SAME VEHICLE, SAME THRESHOLD, SAME CLOCK ═════
--
--     context key passed            passed   reason
--     ---------------------------   ------   ----------------------------------------------------
--     'svc' (what we pass today)    **false**  "SOC sensor stale: 1821142 seconds old (threshold 300)"
--     'service_code' (what it reads) **true**   "non-charging action (perimeter_walkaround): SOC liveness N/A"
--
-- One key. Nothing else differs.
--
-- ══ §3 AND `task_start` ALREADY DOES IT RIGHT, WHICH SETTLES THE CONVENTION ═══
--
--     action_context     evals    carries 'service'   carries 'svc'   failed
--     ----------------   ------   -----------------   -------------   ------
--     task_start         69,514          **69,514**               0   **0**
--     task_completion     3,550                   0           3,550   **1,288**
--     redeployment        2,047                   0               0        0
--
-- **69,514 evaluations at `task_start` carry `service` AND `requires_charging`, and not one has ever
-- failed.** The guard works, has always worked, and the convention was established long before my probe.
-- `task_completion` is the only probe point that spells the key differently, and it is the only one that
-- fails. (`redeployment` carries no service key either and still passes 2,047 of 2,047 — because a vehicle
-- being redeployed genuinely has fresh SOC, so the rule evaluates for real and is satisfied. That is the
-- guard's own documented case: *"redeployment carr[ies] no such flag and remain[s] FULLY gated."*)
--
-- ══ §4 WHAT THIS RETRACTS, INCLUDING IN CLAUDE.md ════════════════════════════
--
-- **RETRACTED:** `0333`'s and `0337` §5's characterisation of HW.003 as *"a tautology — staleness equals
-- the atom's own duration to within 20 seconds, so every atom longer than the 300-second threshold fails
-- by construction."*
--
-- **The measurement was real and the inference was wrong.** Staleness does track the atom's duration —
-- the SOC last reported when the atom started — and that correctly explains *why the number is 600–900
-- seconds*. It does not explain *why the rule was consulted at all*, and I treated the arithmetic as the
-- cause. The rule would have abstained at any threshold, because it never learned it was looking at a
-- walkaround. **A threshold cannot be the cause of a verdict a scope guard should have prevented.**
--
-- **So the prescribed fix changes.** CLAUDE.md 2.9a and FINDINGS G150(b) say to give HW.003 a sensor age
-- that is not the task's own duration. That would have been a real change to a safety-critical rule's
-- semantics, to fix a defect in a context builder I wrote. **SAY INSTEAD: pass the service name the
-- evaluator actually reads, and HW.003 abstains on its own.**
--
-- **And note the shape, which is the ninth instance and the first of its sub-kind.** The family so far is
-- *a real measurement read as answering a question it was not about*. This one is narrower and nastier:
-- **a real measurement that was ABOUT the right question and still had the wrong cause attached**, because
-- the number was consistent with the story. 600–900 s against 300 s is a perfectly good explanation of a
-- failure; it just was not this failure's explanation.
--
-- **THE STANDING TEST: when a rule fires where it obviously should not, read its FIRST branch before its
-- arithmetic.** A scope guard that did not fire is a wiring question, and no amount of threshold analysis
-- will surface it — `0333` and `0337` each measured HW.003 twice and never read line one.
--
-- ══ §5 THE FIX, AND WHAT IT WILL AND WILL NOT DO ═════════════════════════════
--
-- **Add `service` to `ottoq_probe_task_completion`'s context** (ADD, not rename: `svc` is read by the
-- stall resolution and by `0337`'s own analysis queries, so removing it would break readers). One key.
--
-- **Predicted effect, stated before applying so it is falsifiable:** HW.003's 808 walkaround failures at
-- `task_completion` go to **zero abstentions-as-pass**, i.e. the code joins `SLA.003`, `SM.002` and
-- `TW.002` as **VACUOUS at this probe point** — honestly so, because `task_completion` for a *charge* is
-- not probed. That is a worse-looking coverage number and a truer one: `0337` §2 will read **four of five
-- codes vacuous** instead of three, and the only remaining real verdict at the tenth probe point will be
-- HW.006's, which `0425` addresses from the booking side.
--
-- **It does NOT fix HW.006.** That one resolves a stall via `need_atom = svc` and gets a bay the work was
-- never at; `0425` removes the booking. Two different defects at the same probe point, and this file
-- fixes neither of them by fixing the other.

\echo '=== 0340 §1–§2 — one context key decides it, on a live probe ==='
WITH v AS (
  SELECT id AS vid FROM public.vehicles
   WHERE home_depot_id='11111111-1111-1111-1111-111111111111'
     AND current_soc_updated_at IS NOT NULL LIMIT 1
), p AS (
  SELECT COALESCE(default_parameters,'{}'::jsonb) AS params FROM public.ottoq_rules
   WHERE rule_code='HW.003.sensor_liveness' AND status='active' LIMIT 1
)
SELECT
  (public.ottoq_eval_hw_003_sensor_liveness('vehicle', v.vid,
     jsonb_build_object('svc','perimeter_walkaround',
                        'now_ts',(now() + interval '20 minutes')::text), p.params)).passed AS as_probed_today,
  left((public.ottoq_eval_hw_003_sensor_liveness('vehicle', v.vid,
     jsonb_build_object('svc','perimeter_walkaround',
                        'now_ts',(now() + interval '20 minutes')::text), p.params)).reason, 70) AS reason_today,
  (public.ottoq_eval_hw_003_sensor_liveness('vehicle', v.vid,
     jsonb_build_object('service_code','perimeter_walkaround',
                        'now_ts',(now() + interval '20 minutes')::text), p.params)).passed AS with_service_code,
  left((public.ottoq_eval_hw_003_sensor_liveness('vehicle', v.vid,
     jsonb_build_object('service_code','perimeter_walkaround',
                        'now_ts',(now() + interval '20 minutes')::text), p.params)).reason, 70) AS reason_fixed
  FROM v, p;
-- 'svc' -> passed=false, "SOC sensor stale". 'service_code' -> passed=true, "non-charging action ...
-- SOC liveness N/A". The threshold is identical in both calls. The key is the whole defect.

\echo '=== 0340 §3 — task_start already passes the right key and has never failed ==='
SELECT action_context, count(*) AS evals,
       count(*) FILTER (WHERE context ? 'service')           AS has_service,
       count(*) FILTER (WHERE context ? 'service_code')      AS has_service_code,
       count(*) FILTER (WHERE context ? 'svc')               AS has_svc,
       count(*) FILTER (WHERE context ? 'requires_charging') AS has_requires_charging,
       count(*) FILTER (WHERE NOT passed)                    AS failed
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.003.sensor_liveness'
 GROUP BY 1 ORDER BY evals DESC;
-- 69,514 at task_start carry `service` + `requires_charging`, ZERO failures. 3,550 at task_completion
-- carry only `svc`, 1,288 failures. The convention existed; my probe did not follow it.

\echo '=== 0340 §4 — the scope guard is line one of the evaluator, and nothing read it ==='
SELECT substring(regexp_replace(prosrc,'/\*.*?\*/','','g') from 1 for 900) AS first_branch
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_eval_hw_003_sensor_liveness';
-- The guard, and the coalesce that names the keys it reads. 0333 and 0337 each measured this rule's
-- staleness arithmetic and neither read its first branch. When a rule fires where it obviously should
-- not, read the FIRST BRANCH before the arithmetic.
