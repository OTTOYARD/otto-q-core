-- 0267  THE PAIRED RUN FINISHED. THE HONEST DELTA IS +10% WORK FINISHED PER TICK,
--       NOT THE 3x I READ AT HALFWAY.
--
-- Read-only. The definitive before/after for 0367–0372, from `ottoq_run_archives`,
-- which survives the purge. Scope: twin depot 11111111-1111-1111-1111-111111111111
-- (rule 8). **This file supersedes `db/checks/0263` §2, whose figures were taken at
-- tick 671 of an unfinished run and overstated the result.**
--
-- ══ 1. THE PAIR IS AS CLEAN AS THIS RIG GETS ════════════════════════════════
--
-- Same seed **777777**, same scenario **busy_day**, same depot, same speed **8.0**,
-- and both runs stopped by the SAME cause — `run_governor: reached the 540
-- sim-minute ceiling` — at **1,245** and **1,260** ticks, 1.2% apart. `engine_hash`
-- differs (`e8eaf299…` before, `84355554…` after) and that is correct: all of
-- 0367–0372 are `forces_recert TRUE`, so the canon matrix is supposed to notice. What
-- changed is the decide path, which is the thing under test.
--
--   metric                  3fb415d8 (before)   5b37ee46 (after)    per tick
--   ticks                        1,245               1,260            +1.2%
--   commands_issued             10,110  (8.120)      7,885  (6.258)   **-23.0%**
--   commands_refused               435  (0.3494)       508  (0.4032)  **+15.4%**
--   dispatches                     168  (0.13494)      174  (0.13810)   +2.3%
--   **tasks_completed**            485  (0.38956)      540  (0.42857)  **+10.0%**
--   charge_sessions                177  (0.14217)      183  (0.14524)   +2.2%
--   events_generated            29,424              30,870              +2.5%
--   vehicles_simulated             104                 101              -2.9%
--   commands per dispatch         60.2                45.3            **-24.8%**
--   ottoq.refusal_escalated        393  (0.3157)       293  (0.2325)  **-26.4%**
--
-- **WHAT TO SAY: ten percent more work finished per tick, a quarter less command
-- churn per dispatch, a quarter fewer escalations — on identical inputs.** And the
-- +10% is on **three fewer vehicles**, so per vehicle it is slightly better than it
-- reads.
--
-- **WHAT NOT TO SAY, AND I SAID IT AT HALFWAY.** `0263` §2 reported commands per tick
-- down **3.3x** and dispatches per tick up **29%**. Both were artefacts of reading a
-- run that was 51% complete against one that was finished: command volume accelerated
-- sharply in the second half (1,637 commands at tick 671, 7,885 by tick 1,260 — so
-- 2.44/tick became 6.26/tick). The file named that confound explicitly — *"arrival
-- demand is not uniform across a busy_day … a partial run's per-tick rate against a
-- full run's is a real confound, not a rounding one"* — and then the numbers were
-- quotable anyway, which is how a caveat fails to do its job. **The caveat has to be
-- the headline or it is decoration.**
--
-- And one figure from §2 SURVIVES and is worth keeping for the opposite reason: the
-- refusals-per-tick identity to three decimals (0.349 vs 0.349) was **coincidence of
-- the halfway point**. Finished, it is 0.3494 against 0.4032 — refusals per tick are
-- **up 15%**, not flat. A striking coincidence is not evidence, and this one lasted
-- about four hours.

SELECT a.sim_run_id, a.tick_count, a.engine_hash, a.reason,
       (a.metrics->>'commands_issued')::numeric                                     AS commands,
       (a.metrics->>'commands_refused')::numeric                                    AS refused,
       (a.metrics->>'dispatches')::numeric                                          AS dispatches,
       (a.metrics->>'tasks_completed')::numeric                                     AS tasks_completed,
       (a.metrics->>'charge_sessions')::numeric                                     AS charge_sessions,
       (a.metrics->>'vehicles_simulated')::numeric                                  AS vehicles,
       round((a.metrics->>'commands_issued')::numeric  / a.tick_count, 4)           AS commands_per_tick,
       round((a.metrics->>'commands_refused')::numeric / a.tick_count, 4)           AS refused_per_tick,
       round((a.metrics->>'tasks_completed')::numeric  / a.tick_count, 5)           AS tasks_per_tick,
       round((a.metrics->>'commands_issued')::numeric
             / NULLIF((a.metrics->>'dispatches')::numeric, 0), 1)                   AS commands_per_dispatch
  FROM public.ottoq_run_archives a
 WHERE a.depot_id = '11111111-1111-1111-1111-111111111111'
   AND a.random_seed = 777777 AND a.scenario = 'busy_day' AND a.tick_count > 0
 ORDER BY a.archived_at DESC LIMIT 4;

-- ══ 2. WHERE THE EXTRA REFUSALS WENT, WHICH IS THE POINT ════════════════════
--
-- Refusals per tick rose 15% and that is not a regression, because the refusals are
-- now being ANSWERED rather than escalated. On the finished run:
--
--   refused, all causes                                     508
--     not reroutable by design (superseded,
--     vehicle_state_incompatible, …)                        225
--     **reroutable (target_occupied / resource_faulted on
--     proceed_to_stall / begin_charge / stage)             283**
--       **rerouted                                          210   = 74.2%**
--       escalated no_capacity                                73
--
-- **74.2% of the refusals the reactor is able to act on now find a stall**, against
-- 2 of 7 (29%) measured immediately before 0368 and 0369 — a small sample then, and
-- the only one that existed. 210 reroutes on the twin depot, where before 0368 the
-- walk searched ten DCFC stalls for vehicles whose target was one of 113 staging
-- ones and `db/checks/0262` attributes 54 of the first 78 to that fix alone.
--
-- So the causal story ends where it should: **more refusals reach a reroute, a quarter
-- fewer reach an escalation, the same fleet finishes 10% more work per tick, and the
-- engine spends a quarter fewer commands per vehicle dispatched.** No claim is made
-- here about p95 time-to-service or touch events; those are KPI questions and a single
-- pair cannot settle them.

SELECT count(*) FILTER (WHERE c.status = 'refused')                                  AS refused_all,
       count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code NOT IN ('target_occupied','resource_faulted'))
                                                                                     AS not_reroutable_by_design,
       count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code IN ('target_occupied','resource_faulted')
                          AND c.command_type IN ('proceed_to_stall','begin_charge','stage'))
                                                                                     AS reroutable,
       count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted')           AS rerouted,
       count(*) FILTER (WHERE c.payload->'reaction'->>'reason' = 'no_capacity')        AS escalated_no_capacity,
       round(100.0 * count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted')
             / NULLIF(count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code IN ('target_occupied','resource_faulted')
                          AND c.command_type IN ('proceed_to_stall','begin_charge','stage')), 0), 1)
                                                                                     AS reroute_success_pct
  FROM public.ottoq_vehicle_commands c
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111';

-- ══ 3. THE RECLAIMER NEVER ONCE FAILED OR FELL SILENT ═══════════════════════
--
-- 0367 installed an alarm precisely so that "ran and found nothing" could never again
-- be confused with "ran and could take nothing" (0360 was silently returning
-- `deadlock detected` on every call). Over the whole 1,260-tick run:
--
--   ottoq.reservation_reclaim_blocked events        **0**
--   standing_claim_contradicted rows (0370)          415
--
-- Zero blocked events across 1,260 ticks is the evidence that 0371's removal of
-- `SKIP LOCKED` did not reintroduce 0360's deadlock — the ascending-id lock order
-- held. And 415 standing contradictions is 0370 measuring, not acting: the engine now
-- counts every calendar claim physical reality has already overruled, which it could
-- not do this morning.

SELECT (SELECT count(*) FROM public.ottoq_events e
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
           AND e.event_type = 'ottoq.reservation_reclaim_blocked')          AS reclaim_blocked_events,
       (SELECT count(*) FROM public.space_conflict_ledger l
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
           AND l.conflict_kind = 'standing_claim_contradicted')             AS standing_contradictions,
       (SELECT count(*) FROM public.ottoq_events e
          JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
           AND e.event_type = 'twin.staging_overflow')                      AS staging_overflow_events;
