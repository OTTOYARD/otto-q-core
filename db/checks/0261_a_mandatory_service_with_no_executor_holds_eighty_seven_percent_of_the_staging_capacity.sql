-- 0261  A MANDATORY SERVICE THAT NO CODE IN THIS ENGINE CAN PERFORM IS HOLDING
--       98 OF 113 STAGING STALLS, AND THE "FREE STALLS" NUMBER IS 5x TOO HIGH.
--
-- Read-only. No migration accompanies this file ON PURPOSE: every resolution
-- changes what "serviced" or "ready for work" means, and that is Chase's call, not
-- a migration written at four in the morning. Scope: twin depot
-- 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed 777777, speed 8.0).
--
-- ══ 1. THE NUMBER ═══════════════════════════════════════════════════════════
--
-- Measured at tick 501 on the live run:
--
--   staging stalls, total                                        113
--   free by the POINTER (`stalls.reserved_by`/`current_vehicle_id`)  59
--   free by the CALENDAR (`ottoq_stall_bookings` held/active, live)   12
--   **free on BOTH gates -- what a proposer can actually take**       11
--   held by `perimeter_hold`                                         98
--
--   twin.staging_overflow events this run                            258
--   twin.recharge_stranded                                          108
--   ottoq.refusal_escalated                                          60
--
-- **Anyone reading `stalls.reserved_by` reports 59 free staging stalls. Eleven are
-- takeable.** `ottoq_stall_free_between` -- which every proposer and the reroute
-- walk go through -- reads the calendar, and the calendar says 12. The pointer is
-- not the gate on staging; the calendar is, and it is five times tighter.
--
-- This is the same two-authorities theme as G84 and the wash bays in 0260, and it
-- is the third direction it has appeared in. The rule that falls out of all three:
-- **a free-stall count is only meaningful as the intersection of both gates.** A
-- census over either one alone is a different question, exactly as `0250` said
-- about depot scope.

WITH r AS (
  SELECT sim_run_id, COALESCE(sim_clock_current, sim_clock_start) AS clk
    FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running'
   ORDER BY started_at DESC LIMIT 1
), st AS (
  SELECT s.id, s.stall_type::text AS stall_type,
         (s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
          AND s.status = 'available')                                   AS pointer_free,
         NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                      WHERE b.sim_run_id = (SELECT sim_run_id FROM r)
                        AND b.stall_id   = s.id
                        AND b.state IN ('held','active')
                        AND b.during @> (SELECT clk FROM r))            AS calendar_free
    FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
)
SELECT stall_type,
       count(*)                                                AS total,
       count(*) FILTER (WHERE pointer_free)                     AS pointer_free,
       count(*) FILTER (WHERE calendar_free)                    AS calendar_free,
       --: THE ONLY ONE A PROPOSER CAN ACT ON
       count(*) FILTER (WHERE pointer_free AND calendar_free)   AS free_on_both_gates
  FROM st GROUP BY stall_type ORDER BY stall_type;

-- ══ 2. WHY THE HOLD NEVER CLEARS: THE SERVICE HAS NO EXECUTOR ═══════════════
--
-- `perimeter_walkaround` on this run, read at tick 501: **75 atoms, 0 done, 25 of
-- them `must_do`** -- and the atom count climbs every tick while `done` does not,
-- and it is the only service the engine derives that `service_cadence_policy` does
-- not declare (`service_definitions` does not either). Traced end to end:
--
--   PRODUCER   `ottoq.ottoq_derive_visit_needs` line 231:
--                IF v_is_night AND (p_obs->>'perimeter_walkaround')::boolean THEN
--                  atom svc=perimeter_walkaround, must_do=true, deferrable=false,
--                       est_min=12, concurrency='hold', at_perimeter=true
--              `v_is_night` is `v_hour >= 20 OR v_hour < 6` on `v_hour :=
--              EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))` -- so
--              the CT gating is correct, and this run's sim clock starts at 06:48
--              UTC = 01:48 CT, which is night. The atoms are produced legitimately.
--
--   OBSERVERS  `ottoq.ottoq_observe_asset` sets it `true` unconditionally with the
--              comment "ASSUMPTION G3-3 (the kernel gates it to night)";
--              `twin.ottoq_sim_observe_asset` draws it at `night_walkaround_p`,
--              default **0.90**. So nine in ten vehicles get one.
--
--   EXECUTOR   **NONE.** Every completion path takes a FIXED service list and
--              `perimeter_walkaround` is in none of them:
--                twin.ottoq_sim_advance_flow_contract   ARRAY['charge']
--                twin.ottoq_sim_advance_service_flow    wash / detail / service-bay lists
--                twin.ottoq_sim_advance_visit_atoms     7 svcs, not this one; and it
--                                                       references neither
--                                                       `at_perimeter` nor
--                                                       concurrency `'hold'`
--                public.ottoq_ingest_service_complete   whatever a real OEM reports
--              A grep of every function body in the database for
--              'perimeter_walkaround' returns exactly three: the producer and the
--              two observers. Nothing completes it. `at_perimeter` appears in ONE
--              function, the producer.
--
-- So: a producer sets it for 90% of arrivals, marks it `must_do`, books a
-- `perimeter_hold` on a staging stall, and nothing in the engine can ever satisfy
-- it. The hold therefore does not clear on completion -- it clears on expiry, and
-- **the expiry is what the 248-minute average window is** (measured in `0260` §1:
-- 98 live holds, mean window 248 minutes, on a run whose whole life is 540
-- sim-minutes).

SELECT z.svc, z.atoms, z.done, z.must_do,
       (c.svc IS NULL) AS undeclared_in_cadence_policy,
       --: the executor test, mechanised: does ANY function body name this service?
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE position(z.svc in p.prosrc) > 0)                      AS functions_naming_it
  FROM (
    SELECT a->>'svc' AS svc,
           count(*)                                                  AS atoms,
           count(*) FILTER (WHERE a->>'status' = 'done')              AS done,
           count(*) FILTER (WHERE COALESCE(a->>'must_do','') IN ('true','t')) AS must_do
      FROM public.ottoq_visit_needs n
      JOIN public.ottoq_sim_runs r ON r.sim_run_id = n.sim_run_id
      CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
     WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     GROUP BY 1) z
  LEFT JOIN public.service_cadence_policy c ON c.svc = z.svc
 ORDER BY (z.done = 0 AND z.must_do > 0) DESC, z.atoms DESC;

-- READ `functions_naming_it` AS A FLOOR, NOT A VERDICT. It counts function bodies
-- mentioning the literal, so it cannot tell a producer from a completer, and a
-- completer driven by a variable rather than a literal would not appear at all. It
-- is the cheap screen; the three named functions above are the actual trace. A
-- service with a high count can still have no executor, and a service with a low
-- count can still be completed through `ottoq_ingest_service_complete`, which
-- takes its list from its caller.
--
-- ══ 3. WHAT THIS IS AND IS NOT ══════════════════════════════════════════════
--
-- IT IS NOT A BUG IN THE SIMULATION'S HONESTY. The twin is reporting the truth: a
-- mandatory service is outstanding, so the vehicle is not finished, so the stall
-- stays claimed. Every layer behaves correctly given its input.
--
-- IT IS ALSO NOT COSMETIC. 258 `twin.staging_overflow` events fired on this run
-- while 87% of the staging capacity was held for work that cannot be done, and the
-- number a dashboard would print -- 59 free -- is five times the number a proposer
-- can use. Any throughput or "how many vehicles can this depot hold" claim taken
-- from this run inherits both.
--
-- IT IS A PRODUCT DECISION WITH THREE CANDIDATE ANSWERS, and it is Chase's:
--   (a) MAKE IT PERFORMABLE. Add `perimeter_walkaround` to the twin's atom
--       advancer, most naturally as a `concurrency='hold'` service completed in
--       place after `est_min` (12 minutes) while the vehicle stands. Cheapest, and
--       it makes the 248-minute hold a 12-minute one.
--   (b) STOP IT HOLDING A STALL. Keep the atom, drop the `perimeter_hold` booking,
--       or give it a window of `est_min` rather than hours.
--   (c) STOP DERIVING IT until there is something to perform it -- `must_do: false`
--       and `deferrable: true`, so it never blocks a departure and never claims a
--       place.
--
-- (a) is the one that makes the twin more faithful rather than less, so it is the
-- recommendation; (c) is the one that changes the fewest numbers. I have
-- deliberately implemented NONE of them: each changes what "ready for work" means,
-- and writing a completer for a service nothing performs would be fabricating work
-- completion -- which is the one thing this repo's whole reproducibility apparatus
-- exists to make impossible.

SELECT e.event_type, count(*) AS n
  FROM public.ottoq_events e
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   AND e.event_type IN ('twin.staging_overflow','twin.recharge_stranded',
                        'ottoq.refusal_escalated','twin.bay_credit_none',
                        'ottoq.reservation_reclaim_blocked')
 GROUP BY 1 ORDER BY 2 DESC;
