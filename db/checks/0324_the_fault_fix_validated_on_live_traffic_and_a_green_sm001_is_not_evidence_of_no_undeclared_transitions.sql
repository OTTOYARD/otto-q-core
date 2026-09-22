-- 0324  **`0413` and `0412` validated on live traffic, on the SAME scenario, seed, depot and tick
--       length as the run that exposed the defect — so the only thing that changed is the fix.
--       And the validation turned up a third finding neither migration anticipated: SM.001 is
--       524-for-524 green on a run that contains fifteen undeclared transitions, because the path
--       that produces them never reaches the probe.**
--
--       Run `61cedc05-fa8a-44f0-8a31-5cd6404404ff` — busy_day, **seed 700001**, twin depot,
--       30-second ticks. The baseline is `d68d05bb`, identical in all four, where 86 of 116 vehicles
--       were condemned (74.138%). Measured at tick 125 with the run still going.
--
-- ══ §1 THE FAULT FIX: THE TWO DIALS MAKE PREDICTIONS THAT DIFFER BY 500x ══════
--
-- A validation that only says "zero faults, looks better" proves nothing — zero is also what a
-- slightly-wrong dial produces over a short horizon. **The discrimination has to be stated as what
-- each dial PREDICTS at the exposure actually observed**, and at this exposure they are far apart.
--
-- Measured exposure, using `sim_clock_at` (NOT `occurred_at` — `0413` §2 records the eightfold error
-- that mistake caused) over every vehicle's state timeline clamped to the run:
--
--     ticks elapsed                             125
--     sim hours                                0.30
--     eligible vehicle-hours                   23.9
--     eligible vehicle-TICKS                  2,868   (23.9 h x 3600 / 30 s)
--
--     dial                        prediction at this exposure      P(observing zero)
--     ------------------------    ---------------------------      -----------------
--     OLD  0.004 per tick         **11.5 vehicles condemned**      0.996^2868 = 1.0e-5
--     NEW  0.00088 per elig. h    **0.021 vehicles condemned**     97.9%
--
--     OBSERVED                    **0 vehicles condemned**
--
-- **So the observation is what the new dial expects and is a one-in-a-hundred-thousand event under the
-- old one.** That is the validation: not that the number got smaller, but that the run discriminates
-- between the two hypotheses and lands on the fixed one. The old dial would have condemned about a
-- tenth of the fleet in the first eighteen sim-minutes.
--
-- **What is NOT yet shown**, and needs the run to finish: that the realised rate MATCHES 0.00088
-- rather than merely being below the old one. At 0.021 expected faults you cannot measure a rate at
-- all — you can only exclude a much larger one. Confirming the value needs roughly 1,700 eligible
-- vehicle-hours (a full sim-day) to see the ~1.5 faults it predicts. **The fix is validated as a
-- correction; the calibration is not yet validated as a value.** Those are different claims and this
-- file makes only the first.
--
-- ══ §2 THE TRANSITION FIX: ONE UNDECLARED TRANSITION LEFT, AND IT IS THE ONE
--       `0412` DELIBERATELY LEFT ═══════════════════════════════════════════════
--
-- Undeclared observed transitions on this run:
--
--     offline -> charge_complete_holding        15 occurrences
--
-- **That is it — one transition, and it is exactly `0412`'s group (c), boot-state synthesis**, which
-- that migration declined to declare because the right fix is either to declare the landing states the
-- seeder uses or to make the seeder route through a declared one, and that is a question rather than a
-- gap. The operational bucket `0412`'s V3 asserts empty **is empty on live traffic**, which is the
-- assertion holding outside its own transaction for the first time.
--
-- Groups (a) return-to-service and (b) end-of-run reset are absent for good reasons rather than fixed
-- ones: with zero faults there are no tows, so nothing can return to service, and the run has not
-- ended so nothing has been released to `offline`. **Their absence here is not evidence about them.**
--
-- And SM.001 confirms the declarations bind: **524 evaluations at `vehicle_state_change`, all passed**,
-- including transitions `0412` added — `charge_complete_holding -> staged_awaiting_service` (140),
-- `staged_awaiting_service -> charging_l2` (96), `in_wash_bay -> staged_awaiting_service` (8).
--
-- ══ §3 THE FINDING NEITHER MIGRATION ANTICIPATED: A GREEN RULE OVER AN
--       UNDECLARED TRANSITION ═════════════════════════════════════════════════
--
-- **SM.001 logged ZERO failures on a run containing fifteen undeclared transitions.** Both facts are
-- true at once, and the reason is that the probe never saw them: of the 524 SM.001 evaluations on this
-- run, **not one carries `from_state='offline'`.**
--
-- `SM.001` probes from `ottoq_vehicles_state_change`, a row-level trigger. The boot-state transitions
-- are written by the seeding path, which does not reach it — so the fifteen occurrences are visible in
-- `ottoq_events` and invisible to the shield. **The events census and the rule evaluations measure
-- different populations, and only the census sees seeding.**
--
-- **THIS BREAKS `0412` §4's PROMOTION ORDER, WHICH I WROTE, AND IT MUST BE AMENDED.** That section
-- says step 5 is *"a clean full-day run showing residual failures are only group (c)"* before promoting
-- SM.001 from `shadow` to `block`. **Group (c) produces no failures at all**, so the stated condition
-- is satisfied trivially and proves nothing: a run would show zero residual failures whether or not
-- the boot-state question had been answered. The condition has to be rewritten against the EVENTS
-- census — which `0412`'s own V3 already uses — and not against SM.001's log.
--
-- **And the general lesson is the sharpest of the four this branch collected.** Three times tonight a
-- number was wrong because a word spanned two states (`0415`), a denominator was inflated (`0322` §8),
-- or an aggregate spanned an outage (`0322` §10). This is the fourth shape and the most dangerous:
-- **a rule reporting green because it was never asked.** Coverage and cleanliness are different
-- properties, and a passing rule is evidence only over the population its probe actually sees.
-- `0323` §3 found the same shape from the other end — three probe points nobody had counted.

\echo '=== 0324 §1 — the two dials, and what each predicts at the exposure observed ==='
WITH r AS (
  SELECT sim_run_id, tick_interval_seconds,
         (SELECT min(sim_clock_at) FROM public.ottoq_events e WHERE e.sim_run_id=x.sim_run_id) AS t0,
         (SELECT max(sim_clock_at) FROM public.ottoq_events e WHERE e.sim_run_id=x.sim_run_id) AS t1
    FROM public.ottoq_sim_runs x WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff'
), ev AS (
  SELECT e.entity_id AS vid, e.sim_clock_at AS t,
         e.payload->'diff'->'current_state'->>'from' AS sf,
         e.payload->'diff'->'current_state'->>'to'   AS st
    FROM public.ottoq_events e, r
   WHERE e.sim_run_id=r.sim_run_id AND e.event_type='vehicle.state_changed'
     AND e.payload->'diff' ? 'current_state'
), seg AS (
  SELECT vid, sf AS st, (SELECT t0 FROM r) AS a, t AS b
    FROM (SELECT vid,t,sf,row_number() OVER (PARTITION BY vid ORDER BY t) rn FROM ev) q WHERE rn=1
  UNION ALL
  SELECT vid, st, t, COALESCE(lead(t) OVER (PARTITION BY vid ORDER BY t), (SELECT t1 FROM r)) FROM ev
), expo AS (
  SELECT sum(EXTRACT(epoch FROM (b-a))) FILTER (WHERE st IN
           ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay',
            'charge_complete_holding','staged_awaiting_service'))/3600.0 AS eligible_vh
    FROM seg WHERE b>a
)
SELECT round((SELECT eligible_vh FROM expo)::numeric, 1) AS eligible_vehicle_hours,
       round(((SELECT eligible_vh FROM expo) * 3600
              / (SELECT tick_interval_seconds FROM r))::numeric, 0) AS eligible_vehicle_ticks,
       round((0.004 * (SELECT eligible_vh FROM expo) * 3600
              / (SELECT tick_interval_seconds FROM r))::numeric, 1) AS old_dial_expected_condemned,
       round((0.00088 * (SELECT eligible_vh FROM expo))::numeric, 3) AS new_dial_expected_condemned,
       (SELECT count(DISTINCT vid) FROM ev WHERE st='tow_requested') AS observed_condemned;
-- Observed 0. The old dial's prediction of ~11.5 has probability 1.0e-5 of producing zero.

\echo '=== 0324 §2 — undeclared transitions remaining on live traffic ==='
WITH observed AS (
  SELECT payload->'diff'->'current_state'->>'from' AS f,
         payload->'diff'->'current_state'->>'to'   AS t, count(*) AS n
    FROM public.ottoq_events
   WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff'
     AND event_type='vehicle.state_changed' AND payload->'diff' ? 'current_state'
     AND payload->'diff'->'current_state'->>'from' IS DISTINCT FROM payload->'diff'->'current_state'->>'to'
   GROUP BY 1,2
)
SELECT o.f AS from_state, o.t AS to_state, o.n AS occurrences,
       CASE WHEN o.f='offline' THEN '0412 group (c): boot-state, deliberately left'
            WHEN o.t='offline' THEN '0412 group (b): end-of-run reset'
            WHEN o.f IN ('tow_requested','emergency_staged') THEN '0412 group (a): return-to-service'
            ELSE 'OPERATIONAL GAP -- 0412 should have closed this' END AS bucket
  FROM observed o
  LEFT JOIN public.ottoq_state_transitions s
    ON s.entity_kind='vehicle' AND s.from_state=o.f AND s.to_state=o.t AND s.status='active'
 WHERE s.transition_id IS NULL
 ORDER BY o.n DESC;

\echo '=== 0324 §3 — SM.001 is green because it was never asked ==='
SELECT count(*) AS sm001_evaluations,
       count(*) FILTER (WHERE passed) AS passed,
       count(*) FILTER (WHERE NOT passed) AS failed,
       count(*) FILTER (WHERE context->>'from_state' = 'offline') AS evaluations_from_offline
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='SM.001.vehicle_transition_validity'
   AND evaluated_at > (SELECT started_at FROM public.ottoq_sim_runs
                        WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff');
-- Zero evaluations from offline, against fifteen such transitions in ottoq_events. The seeding path
-- does not reach the row-level trigger SM.001 probes from, so a green SM.001 says nothing about the
-- one group still undeclared. 0412 §4's step 5 must be rewritten against the events census.
