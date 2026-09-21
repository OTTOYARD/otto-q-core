-- 0277  G86 CLOSED, AND HALF OF WHAT G86 SAID WAS A PREFIX MATCH.
--       `perimeter_walkaround` NEVER LACKED AN EXECUTOR. IT WAS DERIVED INTO A
--       SEVENTH CONCURRENCY CLASS THAT NO STARTER ADMITS, AND IT IS THE CLASS'S
--       ONLY MEMBER. FIXED BY `db/migrations/0383`.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8). The atom
-- populations below are from demo run `562bf027-6c74-4cb1-9d96-722af13b2fcc` plus one
-- surviving 2026-08-30 run; they are `class='engine'` and will not survive the next demo
-- start, so the RUN is cited, never the table.
--
-- ══ 0. THE RETRACTION FIRST, BECAUSE IT IS IN CLAUDE.md AND QUOTED OUTWARD ══
--
-- CLAUDE.md Part 3 carries, and `db/checks/0261` established:
--
--   "Its `perimeter_hold` bookings held **98 of the twin depot's 113 staging stalls** at an
--    average **248-minute** window on a run whose whole life is 540 sim-minutes, while 258
--    `twin.staging_overflow` events fired."
--
-- **Those are not the walkaround's bookings.** `perimeter_hold` is named for the depot's
-- perimeter **RING**; `perimeter_walkaround` is a walk around a **VEHICLE's** perimeter.
-- The two share nine letters and nothing else. `ottoq.ottoq_book_hold_stall` picks the
-- purpose on dwell duration alone:
--
--   v_purpose := CASE WHEN v_is_long THEN 'perimeter_hold' ELSE 'temp_hold' END;
--   -- where v_is_long := v_minutes >= p_long_threshold_min
--
-- and its own comment says what the ring is for: *"the outer ring is the PURPOSE, not an
-- overflow tier."* Long-dwell parking is what staging stalls exist to do.
--
-- **THE CHEAP CHECK THAT SETTLES IT, AND THAT I SHOULD HAVE RUN FIRST.** Fourteen
-- functions mention one string or the other. **Not one mentions both.** The two sets are
-- disjoint: `book_hold_stall`/`arrival_disposition`/`decide_tick`/`is_bay_purpose` on one
-- side, `derive_visit_needs`/`observe_asset` on the other. A service and its alleged
-- bookings that share no code path anywhere are not the same mechanism.
--
-- And the bookings themselves carry the answer in a column:
--
--   purpose          need_code              need_atom              n   avg_min  stalls
--   perimeter_hold   perimeter_hold         **NULL**              82     230.1      82
--   temp_hold        temp_hold              NULL                  86      23.4      47
--   service          perimeter_walkaround   perimeter_walkaround  14      ~40        2
--
-- `need_atom IS NULL` on every one of the 82: a parking hold serves no service atom. The
-- walkaround's real bookings are fourteen `purpose='service'` rows on **two** stalls.
--
-- **So closing G86 frees no staging stalls, and this file must not be read as though it
-- does.** The 258 `twin.staging_overflow` events and the 82 long holds are a separate
-- question about staging capacity under dwell, still open, and untouched by 0383.

SELECT b.purpose, b.need_code, b.need_atom, b.state, count(*) AS n,
       round(avg(EXTRACT(EPOCH FROM (upper(b.during)-lower(b.during)))/60.0),1) AS avg_win_min,
       count(DISTINCT b.stall_id) AS stalls
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
   AND (b.purpose IN ('perimeter_hold','temp_hold') OR b.need_code = 'perimeter_walkaround')
 GROUP BY 1,2,3,4 ORDER BY 5 DESC;

-- the disjointness, as a query rather than an assertion
SELECT p.oid::regprocedure AS fn,
       (p.prosrc LIKE '%perimeter_hold%')       AS mentions_ring_hold,
       (p.prosrc LIKE '%perimeter_walkaround%') AS mentions_the_service
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin')
   AND (p.prosrc LIKE '%perimeter_hold%' OR p.prosrc LIKE '%perimeter_walkaround%')
 ORDER BY 2 DESC, 1;

-- ══ 1. WHAT WAS ACTUALLY WRONG: AN ORPHAN CONCURRENCY CLASS ════════════════
--
-- `0261`'s other half — *"a producer, two observers, and no executor anywhere in the
-- engine"* — is right that nothing ever completed the service and wrong about why. There
-- IS a general in-place executor, and it has been there all along:
-- `twin.ottoq_sim_advance_visit_atoms` completes **any** atom with `status='in_progress'`
-- and `ends_at <= p_clock`, names no service, needs no bay, then closes the atom's
-- flow-contract leg and credits `ottoq_wear_mark_serviced`.
--
-- What gates it is the START side, `ottoq_start_concurrent_atoms`:
--
--   AND v_a->>'concurrency' IN ('cabin','exterior','digital')
--
-- and derive wrote the walkaround as `'concurrency','hold'`. Completion by concurrency
-- class, which is the entire finding in one table:
--
--   concurrency  atoms  services                                  done  in_prog  pending
--   cabin          127  interior_inspection/tidy, item_retrieval,   75        5       46
--                       triage_check
--   gate            98  readiness_check                             33        0       65
--   anchor          67  charge                                      28        0       39
--   bay             64  the wash/detail/service-bay six             23        0       41
--   **hold**      **63**  **perimeter_walkaround**                 **0**    **0**   **63**
--   digital          5  remote_diagnostics                           2        0        3
--   exterior         2  sensor_clean                                 1        0        1
--
-- **Every class completes except `hold`; `hold` holds exactly one service; not one of its
-- 63 atoms has ever reached `in_progress`.** Not a missing feature — a class with no door.
--
-- **AND MY OWN FIRST MEASUREMENT OF THIS TABLE READ `done = 0` FOR ALL FIFTEEN SERVICES**,
-- because I counted `(atom->>'done')::boolean` and the completer writes
-- `status='done'`. A reader that finds nothing anywhere is reporting on itself, and
-- "charging demonstrably works" was the contradiction that caught it within one query.
-- Fifth instance today of a pattern match presented as a finding; the other four are in
-- `0276` §3 and `0275`.

SELECT * FROM public.ottoq_atom_class_coverage() ORDER BY atoms DESC;

-- ══ 2. THE ENGINE HAD ALREADY SAID SO, TWICE, IN MACHINE-READABLE FORM ═════
--
--   * `ottoq.ottoq_atom_retirable_set()` — the engine's own declaration of what it can
--     complete — held 14 services and not this one. So `ottoq.ottoq_atoms_guard` demoted
--     the atom to `must_do:false` with `guard_reason='svc_not_retirable'` **on every write
--     path**: 39 of 63 carry the demotion, and the 25 that do not are all from the
--     2026-08-30 run and predate the guard. I expected a second unguarded writer and there
--     is none — derive applies the guard on both the INSERT and the ON CONFLICT arm.
--   * `public.ottoq_assert_service_vocabulary()` returned
--     `undeclared => {perimeter_walkaround}`, the ONLY entry.
--
-- The guard is why this was survivable: 39 atoms that cannot be done were also not
-- required. But the 25 legacy ones are `must_do:true` AND unperformable, and
-- `ottoq_kpi_service_completion` counts must_do atoms in its denominator — so the defect
-- was **depressing the published completion percentage, not hidden from it.** The KPI was
-- never blind here; nobody read it against the vocabulary function that named the cause.

SELECT COALESCE((at->>'guard_demoted')::boolean,false) AS guard_demoted,
       COALESCE((at->>'must_do')::boolean,false)       AS must_do,
       count(*) AS n,
       min(n2.created_at)::timestamp(0) AS first_seen,
       max(n2.created_at)::timestamp(0) AS last_seen,
       count(DISTINCT n2.sim_run_id) AS runs
  FROM public.ottoq_visit_needs n2
 CROSS JOIN LATERAL jsonb_array_elements(n2.atoms) at
 WHERE n2.depot_id = '11111111-1111-1111-1111-111111111111'
   AND at->>'svc' = 'perimeter_walkaround'
 GROUP BY 1,2 ORDER BY 3 DESC;

SELECT * FROM public.ottoq_assert_service_vocabulary();

-- ══ 3. THE FIX, AND THE ONE WAY IT COULD HAVE BEEN DISHONEST ═══════════════
--
-- `sensor_clean` is the exact precedent and required no new machinery: event-raised,
-- `cadence_kind='event'`, `must_do_at='always'`, `lane='exterior'`, `lane_stalls=NULL`,
-- performed at the vehicle where it stands. The walkaround atom already declared
-- `at_perimeter: true`. So 0383 derives it as `exterior`.
--
-- **THE LABOUR QUESTION IS THE WHOLE INTEGRITY OF THIS CHANGE.** Making a service
-- completable is worthless if the twin completes 63 of them at once with nobody doing the
-- work. `ottoq_start_concurrent_atoms` already meters it:
--
--   v_free := GREATEST(0, ottoq_depot_staffing_count(depot,'general_tech')
--                       - count(in_progress atoms WHERE concurrency IN ('cabin','exterior')))
--
-- `general_tech` is **10** at the twin depot, one vehicle per tech, and `exterior` is
-- already inside that subtraction — so a walkaround now competes with cabin work for a
-- real technician. **And the 10 is a configured site fact, not the function's fallback:**
-- `ottoq_depot_staffing_count` COALESCEs to a hardcoded 10 for this role, which would have
-- made the number unquotable, but `ottoq_depot_staffing` carries explicit rows for this
-- depot — `general_tech` 10, `service_tech` 3, `wash_supervisor` 2 — so the subtraction is
-- metering a declared crew. **`digital` is the branch exempt from the pool** (`IF v_a->>'concurrency'
-- = 'digital' OR v_free > 0`), and it was the cheaper route: one word different and the
-- twin would have reported 63 completed walkarounds performed by nobody. That is the
-- reason `exterior` and not `digital`.
--
-- Three changes, one transaction, and the ORDER between two of them is load-bearing:
-- adding the service to `ottoq_atom_retirable_set()` while nothing retires it would stop
-- the guard demoting and convert 63 harmless atoms into permanent `must_do` blockers.
--
-- ══ 4. PROVEN END TO END, AND ROLLED BACK ══════════════════════════════════
--
-- The live run's sim clock was past the night window (`v_is_night := v_hour >= 20 OR
-- v_hour < 6`, evaluated in America/Chicago), so no further walkaround would be derived on
-- it and waiting would have proved nothing. Tested instead as a transactional probe that
-- ends in `RAISE EXCEPTION`, so every write unwinds — the `0272` pattern:
--
--   step1  derive at 02:30 CT with the observer flag
--          -> cls=**exterior**  must_do=**true**  guard_demoted=**absent**
--             est=12  at_perimeter=true
--   step2  ottoq_start_concurrent_atoms
--          -> started=1  status=**in_progress**
--             started_at=07:30:00Z  ends_at=**07:42:00Z**   (exactly the declared 12 min)
--   step3  twin.ottoq_sim_advance_visit_atoms at +13 min
--          -> advanced=1  status=**done**  done_at=07:42:00Z
--
-- So: derived into an executable class, admitted by the existing starter, metered against
-- a real technician, completed by the existing general completer at exactly its declared
-- duration, in place, consuming no bay. **And `must_do` is now true with no demotion** —
-- the guard stands down because the premise it was built on is gone.
--
-- **NO BACKFILL, DELIBERATELY.** The 63 stored `hold` atoms keep their class and will
-- never start. Rewriting a live run's working set so a fix looks larger is the opposite of
-- measuring it, so `ottoq_atom_class_coverage()` still reports `hold` as an ORPHAN_CLASS
-- today and should. The effect is measured on the next fresh run.

SELECT ottoq.ottoq_atom_retirable('perimeter_walkaround')          AS retirable_now,
       array_length(ottoq.ottoq_atom_retirable_set(),1)            AS retirable_set_n,
       (SELECT lane FROM public.service_cadence_policy
         WHERE svc='perimeter_walkaround' AND is_active)           AS declared_lane,
       ottoq.ottoq_svc_to_stall_type('perimeter_walkaround',
         '11111111-1111-1111-1111-111111111111')                   AS routes_to_stall_type,
       public.ottoq_depot_staffing_count(
         '11111111-1111-1111-1111-111111111111','general_tech')    AS general_tech_pool;

-- ══ 5. WHAT IS NOW GUARDED AGAINST, AND WHAT IS NOT ════════════════════════
--
-- `public.ottoq_atom_class_coverage(p_sim_run_id uuid DEFAULT NULL)` reports every
-- concurrency class observed in `ottoq_visit_needs.atoms` with its services, its counts,
-- and whether **any** atom of that class has ever reached `in_progress` or `done`. An
-- orphan class is exactly `atoms > 0 AND ever_started = 0`.
--
-- It is **evidence-based and not a probe of any starter's source, on purpose.** A text
-- probe would have been the obvious implementation and it is the same class of reasoning
-- that produced §0's retracted attribution: `bay`, `anchor` and `gate` are executed by the
-- bay-exit, charge-session and departure seams respectively, so no single function's text
-- is the authority on what is executable, and a probe would have reported three false
-- orphans while the real one looked like a fourth.
--
-- **Hardened the same day by `db/migrations/0384`**, and the reason belongs in this file
-- rather than only in that one: 0383 shipped the detector reading `started_at` through a
-- bare `::timestamptz` over free-form jsonb. One atom carrying a non-timestamp would make
-- the function raise, and **a detector whose whole purpose is to establish that a class has
-- never moved reports, when it raises, an absence no reader can tell from a clean answer.**
-- That is `0376`'s defect in code written hours after `0376`. Now read through
-- `pg_input_is_valid`, so a bad value nulls the two timestamp columns and every count — and
-- therefore every verdict — stays exact.
--
-- **What it does NOT catch**, stated so nobody over-trusts it: a class whose atoms start
-- and complete but are credited without the work happening (the `credited`/`satisfied`
-- shapes `ottoq_kpi_service_completion` already separates — note `gate`, `anchor` and `bay`
-- return `first_start = NULL` above while reporting dozens done, which is that shape, not
-- a defect). Coverage answers "can this class ever move", not "did the work occur."
--
-- ══ 6. THE FIX IS NOT FREE, AND THIS IS THE PART TO MEASURE NEXT ══════════
--
-- **Making a mandatory service mandatory has a throughput cost, and the previous state was
-- passing a critical gate by withdrawing its own requirement.** `ottoq_eval_sla_004_required_services`
-- is `critical` and its rule is one sentence:
--
--   -- every must_do atom that is not yet done blocks redeployment
--   WHERE COALESCE((a->>'must_do')::boolean, true)
--     AND NOT COALESCE((a->>'deferrable')::boolean, false)
--     AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped')
--
-- Derive writes the walkaround `must_do:true, deferrable:false`. Before 0383,
-- `ottoq_atoms_guard` demoted it to `must_do:false`, so **SLA.004 passed on 39 of 63 atoms
-- because the requirement had been quietly withdrawn, not because it was met.** After 0383
-- the demotion stops and the atom is a real dispatch gate: at night, every arriving vehicle
-- needs 12 metered technician-minutes before it may redeploy.
--
-- That is the correct behaviour — a night safety walkaround SHOULD gate deploy — and it is
-- a cost that must be measured rather than assumed away. Back-of-envelope on the twin
-- depot: 63 walkarounds x 12 min / 10 `general_tech` = ~76 minutes of pool time, against
-- cabin work competing for the same ten people. Whether that shows up as a p95
-- time-to-service regression is an empirical question, and **a fresh run is the only way to
-- answer it** — the 63 stored atoms keep class `hold` and cannot exercise the new path.
--
-- **AND ONE STARVATION PATH WORTH WATCHING, stated now so it is not discovered as a
-- surprise.** The advancer's candidate cursor orders
-- `(urgency='immediate_dispatch') DESC, (state IN charging_dcfc/charging_l2) DESC,
-- last_state_change ASC` and takes `LIMIT 30`. A vehicle already in `staged_for_departure`
-- is therefore ranked BELOW charging vehicles for the same tech pool, while SLA.004 holds
-- it back until its walkaround is done. Under a saturated pool that is a plausible route to
-- a vehicle waiting on a technician who is always allocated to someone still charging.
-- **Not pre-emptively patched:** the mitigations (rank a dispatch-blocked vehicle up, or
-- make the walkaround `deferrable:true`) change what "ready for work" means, which is
-- Chase's call and not a defect to route around. What 0383 guarantees is that the atom CAN
-- complete; whether it completes in time is the next measurement.
--
-- ══ 7. AND ONE THING 0383 DID NOT DO ══════════════════════════════════════
--
-- The two places that enumerate concurrency classes by hand — the admit list in
-- `ottoq_start_concurrent_atoms` and the selection predicate in
-- `twin.ottoq_sim_advance_visit_atoms` — still do. `ottoq.ottoq_bay_purpose_atoms` carries
-- a `-- MUST MIRROR twin.ottoq_sim_advance_service_flow STEP 1` comment for the same
-- reason on the bay side: the codebase already knows hand-mirrored lists are a hazard and
-- documents it rather than enforcing it. A single `ottoq_inplace_concurrency_set()` that
-- both read would make an orphan class impossible rather than merely visible. Deliberately
-- NOT bundled here: it rewrites two more tick-path functions, and a failure in that
-- refactor must not be able to take down a fix that is proven working.
