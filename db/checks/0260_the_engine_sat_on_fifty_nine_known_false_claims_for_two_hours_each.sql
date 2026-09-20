-- 0260  THE ENGINE SAT ON FIFTY-NINE KNOWN-FALSE CALENDAR CLAIMS FOR AN AVERAGE
--       OF TWO HOURS EACH, AND A WASH-BAY INVESTIGATION THAT FOUND NOTHING WRONG.
--
-- Read-only. After-measurement for migration 0370 (G85), plus a negative result
-- recorded so nobody spends the hour on it again. Scope: twin depot
-- 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed 777777, speed 8.0).
--
-- ══ 1. WHAT THE DETECTOR SAW ON ITS FIRST TICK ══════════════════════════════
--
--   conflict_kind                  resolution                 type         n
--   standing_claim_contradicted    recorded_not_acted         staging     59
--   assignment_refused_occupied    command_refused_preflight  l2          10
--   assignment_refused_occupied    command_refused_preflight  staging      8
--   assignment_refused_occupied    command_refused_preflight  dcfc         7
--   stale_claim_displaced          reality_outranks_plan      service_bay  1
--
-- All 59 are `perimeter_hold`, and the two numbers that matter are the ones the
-- old ledger could never have produced:
--
--   average claim age at detection          **114.6 minutes**
--   average claim time still to run         **140.5 minutes**
--
-- So each contradicted claim had been standing for nearly two hours and had over
-- two hours left to run. The engine could have known for 115 minutes on average;
-- instead it learned at assignment time, as one of the 25
-- `assignment_refused_occupied` rows, when the holder finally travelled. **The 25
-- refusals are the late symptom of the 59 standing contradictions nothing counted.**
--
-- And the size of the hold: 98 of the depot's 113 staging stalls held by
-- `perimeter_hold` at that moment, average window 248 minutes on a run whose whole
-- life is 540 sim-minutes, for `perimeter_walkaround` -- **36 atoms, 0 done**, and
-- declared in NEITHER `service_cadence_policy` NOR `service_definitions`. That is
-- CLAUDE.md 2.3's standing note with today's numbers behind it, and it is now a
-- capacity finding rather than a curiosity.

SELECT l.conflict_kind, l.resolution, l.stall_type, count(*) AS n,
       round(avg((l.detail->>'claim_age_min')::numeric), 1)       AS avg_claim_age_min,
       round(avg((l.detail->>'claim_remaining_min')::numeric), 1) AS avg_remaining_min,
       string_agg(DISTINCT l.detail->>'purpose', ',')             AS purposes
  FROM public.space_conflict_ledger l
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1,2,3 ORDER BY 4 DESC;

-- WHAT MAY BE SAID, AND WHAT MAY NOT. SAY: "fifty-nine live calendar claims were
-- contradicted by a vehicle already in the stall, standing an average of 115
-- minutes, and none of them was in the conflict ledger." DO NOT say the engine
-- has 59 fewer usable stalls than it thinks -- 26 of the contradicted stalls were
-- EMPTY at the same moment and the other 57 held a vehicle that may itself be
-- legitimately parked; the recoverable capacity is a separate measurement and this
-- detector deliberately does not make it. 0370 counts; it changes no assignment.
--
-- ══ 2. THE WASH BAY: INVESTIGATED, NOTHING WRONG, WRITTEN DOWN ══════════════
--
-- Recorded as a NEGATIVE RESULT because two plausible defects were chased here and
-- both were wrong, and the next person will otherwise chase them again.
--
-- The trigger: `wash_bay` showed **3 stalls, 0 reserved, 0 occupied** in two
-- separate censuses while `exterior_wash` had 20 atoms and 11 done. A service that
-- CLAUDE.md 2.4 says needs a separate bay, apparently completing without one.
--
-- HYPOTHESIS 1 -- "washes complete without occupying a bay, so the throughput model
-- is optimistic." WRONG. The bays are booked: 31 bookings this run, 24 `wash` and
-- 7 `detail`. They are booked through the CALENDAR without `stalls.reserved_by`
-- being set, which is why a reservation census reads zero. The EXCLUDE constraint
-- on bookings is what prevents double-booking, so physical safety never depended on
-- the pointer. What this does mean: **any census of "free stalls" that reads only
-- `reserved_by` is blind to calendar-held bays.** Same two-authorities theme as G84,
-- in the other direction, and worth remembering before quoting a free-stall count.
--
-- HYPOTHESIS 2 -- "8 of 13 concluded wash bookings are `interrupted /
-- bay_exit_before_planned_end` while their work atom says `done`, so the state is
-- mislabelled." ALSO WRONG, and the way it looked true is instructive: on all 8,
-- `planned_min` EQUALS `actual_min` to two decimals, which reads like a booking
-- released exactly at its planned end and still called an early exit. It is not.
-- `ottoq.ottoq_release_vacated_spaces` CLIPS `during` to the actual occupancy in
-- the same UPDATE that sets the state, so after the fact the table cannot show the
-- shortfall. The decision itself is made by `ottoq.ottoq_booking_interrupted(purpose,
-- planned_s, actual_s)` on the pre-clip values, and **those values are preserved in
-- the `ottoq.booking_interrupted` event payload**, not lost.
--
-- AND THE MECHANISM IS BETTER INSTRUMENTED THAN THE HYPOTHESIS ASSUMED.
-- `workload_harness_metrics` already carries an `interruption_emission_ratio`
-- invariant whose own comment says "50 of 52 bookings reached state='interrupted'
-- WITHOUT emitting ottoq.booking_interrupted ... do not trust ANY
-- interruption-derived number in the same run until it reads 1.000". Measured on
-- this run: **16 interrupted bookings, 16 distinct emitted booking_ids, ratio
-- 1.000 -- PASS.** So interruption numbers on this run are trustworthy, and the
-- re-plan side works too: `ottoq_reopen_visit_atoms` put 2 atoms back with
-- `reopen_reason='bay_session_interrupted'`, both `in_progress`.
--
-- Nothing to fix. Both hypotheses retracted.

WITH b AS (
  SELECT count(DISTINCT sb.booking_id)::numeric n
    FROM public.ottoq_stall_bookings sb
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = sb.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND sb.state = 'interrupted'
), e AS (
  SELECT count(DISTINCT (ev.payload->>'booking_id'))::numeric n
    FROM public.ottoq_events ev
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = ev.sim_run_id
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND ev.event_type = 'ottoq.booking_interrupted'
     AND NULLIF(ev.payload->>'booking_id','') IS NOT NULL
)
SELECT b.n AS interrupted_bookings, e.n AS emitted_events,
       round(e.n / NULLIF(b.n, 0), 3) AS emission_ratio,
       CASE WHEN b.n = 0 AND e.n = 0 THEN 'PASS (no interruptions)'
            WHEN b.n = e.n           THEN 'PASS - every interruption emitted'
            WHEN e.n < b.n           THEN '*** FAIL: BLIND SPOT - interruption metrics under-count'
            ELSE                          '*** FAIL: more events than interrupted bookings' END AS verdict
  FROM b, e;

-- ══ 3. THE SERVICE CATALOGUE, AS THE RUN ACTUALLY USES IT ═══════════════════
--
-- Atom counts on this run (atoms / done / must_do), the vocabulary C11's pack spec
-- has to cover. FIRST, A CORRECTION OF MY OWN: an earlier reading of this table
-- used an `a->>'required'` key and reported **0 required for every service**, which
-- is true and useless -- no atom carries `required`. The field that gates is
-- `must_do`, and with the right field the table says something quite different:
--
--   readiness_check       94 /  17 / 94        interior_inspection   90 / 57 / 90
--   charge                61 /  20 / 55        perimeter_walkaround  61 /  0 / 25
--   exterior_wash         32 /  14 / 10        interior_tidy         28 / 10 / 28
--   interior_deep_clean   11 /   3 /  9        triage_check          10 /  9 / 10
--   sensor_clean           7 /   5 /  7        item_retrieval         7 /  5 /  7
--   fault_repair           5 /   2 /  5        remote_diagnostics     4 /  1 /  0
--   sensor_calibration     3 /   0 /  0        mechanical_pm          2 /  0 /  0
--   cosmetic_repair        1 /   0 /  0
--
-- TWO CATALOGUE INCONSISTENCIES, NAMED NOT FIXED:
--
--   (a) **`perimeter_walkaround`: 61 atoms, 0 done, and 25 of them `must_do`.**
--       CLAUDE.md 2.3's standing note says it is "derived 108 times per run,
--       required of none, performed never". The middle clause is no longer true and
--       that is the part that matters: **twenty-five of these are mandatory, none
--       has ever completed, and the service is declared in neither
--       `service_cadence_policy` nor `service_definitions`** -- the only row in this
--       table with `undeclared_in_cadence_policy = true`. Per section 1 its
--       `perimeter_hold` bookings hold **98 of 113 staging stalls** at an average
--       248-minute window. A mandatory service that never completes cannot release
--       the hold it takes, so the hold does not clear on completion -- it clears on
--       expiry, which is what the 248 minutes are. Of everything in this file this
--       is the one worth Chase's attention, and it is a design question rather than
--       a bug: either the walkaround should be performable, or it should not hold a
--       staging stall while it waits.
--
--   (b) `service_cadence_policy` gives `interior_deep_clean` **`lane_stalls = 0`**
--       while its atoms declare `requires_bay = 'detail'` and its bookings land on
--       `wash_bay` stalls under purpose `detail` (8 this run, 3 atoms done, 9 of 11
--       `must_do`). A lane declared with zero capacity, served by another lane's
--       stalls. Harmless today; it is exactly the declared-versus-actual gap C11's
--       conformance harness exists to catch, so it belongs in `PACK_SPEC.md`'s
--       validation rather than in a fix here.

WITH atoms AS (
  SELECT a->>'svc'          AS svc,
         a->>'status'       AS status,
         a->>'must_do'      AS must_do,
         a->>'requires_bay' AS requires_bay
    FROM public.ottoq_visit_needs n
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = n.sim_run_id
    CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
), rolled AS (
  SELECT svc,
         count(*)                                                AS atoms,
         count(*) FILTER (WHERE status = 'done')                  AS done,
         count(*) FILTER (WHERE COALESCE(must_do,'') IN ('true','t')) AS must_do,
         max(requires_bay)                                        AS requires_bay
    FROM atoms GROUP BY svc
)
SELECT z.svc, z.atoms, z.done, z.must_do, z.requires_bay,
       c.lane_stalls AS declared_lane_stalls,
       c.interval_h  AS declared_interval_h,
       --: the point of the LEFT JOIN: a NULL here is a service the engine derives
       --: and no catalogue declares. perimeter_walkaround is that row.
       (c.svc IS NULL) AS undeclared_in_cadence_policy
  FROM rolled z
  LEFT JOIN public.service_cadence_policy c ON c.svc = z.svc
 ORDER BY z.atoms DESC;
