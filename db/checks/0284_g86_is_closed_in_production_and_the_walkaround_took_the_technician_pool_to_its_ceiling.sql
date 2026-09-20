-- 0284  G86 IS CLOSED IN PRODUCTION: 83 OF 85 PERIMETER WALKAROUNDS COMPLETED ON A LIVE
--       NIGHT-SPANNING RUN, AGAINST 0 OF 63 BEFORE `0383`. AND THE TECHNICIAN POOL NOW
--       PEAKS AT EXACTLY ITS CEILING — WHICH TOOK ME THREE WRONG UNITS TO ESTABLISH.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live demo run
-- `1efeb1cd-f9b6-4515-8e61-2e5a04121112` (busy_day, seed 101959). This is the first
-- night-spanning run since `0383` landed: seed 101959 gives sim start 01:00 UTC = 20:00 CT,
-- and the measurements below cover sim 01:08 -> 07:01, so the whole window sits inside
-- `v_is_night` (hour >= 20 OR hour < 6, evaluated in America/Chicago). Visits and atoms are
-- `class='engine'` and purge with the run.
--
-- ══ 1. G86, CLOSED AND MEASURED ════════════════════════════════════════════
--
--                            before `0383`        now
--   perimeter_walkaround atoms      63             **85**
--   done                             **0**         **83**
--   ever reached `in_progress`       **0**          83
--   demoted `must_do:false` by
--     `svc_not_retirable`           39 of 63        **0**
--   declared `concurrency`         `hold`        `exterior`
--
-- `0383`'s claim was that the walkaround was not missing an executor -- it was written into
-- a seventh concurrency class with exactly one member, and `ottoq_start_concurrent_atoms`
-- admits only `('cabin','exterior','digital')`. Moving it to `exterior` beside
-- `sensor_clean` should therefore make it simply run. **It does.** All 85 carry
-- `must_do:true`, none is guarded, 0 are pending, and the class as a whole
-- (`perimeter_walkaround` + `sensor_clean`) reads 92 done of 98.
--
-- This is the production confirmation `0383` could only assert from a rolled-back probe, and
-- the part worth keeping is that the fix was one word in a derive function, not a mechanism.

SELECT e->>'svc' AS svc, e->>'concurrency' AS declared_class, count(*) AS atoms,
       count(*) FILTER (WHERE e->>'status' = 'done')        AS done,
       count(*) FILTER (WHERE e->>'status' = 'pending')     AS pending,
       count(*) FILTER (WHERE (e->>'must_do')::boolean)     AS must_do,
       count(*) FILTER (WHERE e ? 'guard_reason')           AS guarded
  FROM public.ottoq_visit_needs n
 CROSS JOIN LATERAL jsonb_array_elements(n.atoms) e
 WHERE n.sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
   AND e->>'svc' IN ('perimeter_walkaround', 'sensor_clean')
 GROUP BY 1, 2 ORDER BY 1;

SELECT * FROM public.ottoq_atom_class_coverage('1efeb1cd-f9b6-4515-8e61-2e5a04121112');

-- ══ 2. WHAT IT COST, AND THE UNIT THAT FINALLY ANSWERED IT ═════════════════
--
-- `0383` warned that the fix "costs a real technician": `exterior` sits inside
-- `ottoq_start_concurrent_atoms`'s `general_tech` subtraction, and the twin depot staffs
-- **10**. So does adding 85 mandatory walkarounds saturate the pool?
--
--   metered atoms that ran (`cabin` + `exterior`)        **230**
--   distinct vehicle busy-spans after merging            **116**
--   **peak vehicles occupying a technician**              **10**
--   mean                                                **5.22**
--   moments above the pool                                **0**
--   p95 time-to-service on this run                   **2.7 min**
--
-- **The pool binds exactly at its ceiling and is never exceeded.** Peak 10 of 10 with zero
-- excursions is the meter working precisely, not a near miss. Mean 5.22 says the pool is
-- half-idle on average, so the walkaround is absorbed rather than crowding anything out --
-- and `p95_time_to_service` at 2.7 minutes (p50 0.4) shows no degradation. The honest
-- sentence: **the walkaround now consumes real technician capacity, drives the pool to its
-- ceiling at peak, and has not cost time-to-service on this run.**
--
-- ══ 3. THREE WRONG UNITS FIRST, AND THE THIRD IS A REPEAT OFFENCE ══════════
--
-- I reported "peak 12 busy against a pool of 10" internally before any of this held up.
-- Each correction is recorded because the shapes are the ones that keep recurring.
--
-- **(a) Unscoped across visit generations.** The first pass counted atoms from every
-- `ottoq_visit_needs` row including superseded ones, so one technician could be counted
-- twice across two generations of the same vehicle's visit. Immaterial here as it happens --
-- this run holds exactly **1** superseded visit against 81 `in_progress` and 35 `open` --
-- but it was luck, not scoping, and it is the `0250` defect class verbatim.
--
-- **(b) A mechanism that looked certain and was refuted by its own lens.** The pool
-- subtraction requires `vn2.status = 'in_progress'` on the VISIT row, and **29 of 230
-- metered atoms ran on visits whose row said `open`** -- occupancy the meter structurally
-- cannot see. That is a real property of the code and it is NOT the cause: recomputing the
-- peak over only what the meter can see gives the SAME 12 and the same 3 moments over. A
-- blindness that does not change the answer is not an explanation. (It remains a latent
-- hazard worth its own look, since 12.6% of metered work is invisible to the meter; it is
-- not raised as a defect here because nothing measurable follows from it on this run.)
--
-- **(c) THE ACTUAL ERROR: I counted atoms and called them technicians.** The function's own
-- comment is explicit -- *"Each tech handles ONE vehicle at a time: plug in -> 3-5 min
-- interior clean -> inspect"* -- so the unit is the VEHICLE, and a vehicle running three
-- concurrent metered atoms is one technician, not three. Merging each vehicle's overlapping
-- atom windows before counting turns peak 12 into peak **10**, and 3 moments over the pool
-- into **0**. Note the direction: the meter decrements per ATOM, so it is *more*
-- conservative than the design requires, which is why no violation was ever possible.
--
-- **This is the third time tonight I have read a count in the wrong unit** -- after "peak
-- 116 concurrently on site" (a roster, not an occupancy) and `0283`'s two retracted cap
-- measurements. The check that would have caught all three in one step: **before comparing a
-- count to a capacity, say out loud what one unit of that capacity is.** Ten technicians is
-- ten vehicles-being-worked, not ten tasks.
--
-- Ruled out on the way, so nobody re-derives it: **exactly one function in the database sets
-- an atom to `in_progress`**, and it is the one that consults the pool. There is no second,
-- unmetered starter.

WITH a AS (
  SELECT n.vehicle_id,
         (e->>'started_at')::timestamptz AS s, (e->>'ends_at')::timestamptz AS f
    FROM public.ottoq_visit_needs n
   CROSS JOIN LATERAL jsonb_array_elements(n.atoms) e
   WHERE n.sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
     AND n.status <> 'superseded'
     AND e->>'concurrency' IN ('cabin', 'exterior')
     --: 0384's lesson: a detector must not raise on the malformed data it exists to find.
     AND pg_input_is_valid(COALESCE(e->>'started_at', ''), 'timestamptz')
     AND pg_input_is_valid(COALESCE(e->>'ends_at', ''), 'timestamptz')),
v AS (SELECT vehicle_id, s, f,
             max(f) OVER (PARTITION BY vehicle_id ORDER BY s
                          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_max
        FROM a),
grp AS (SELECT vehicle_id, s, f,
               sum(CASE WHEN prev_max IS NULL OR s > prev_max THEN 1 ELSE 0 END)
                 OVER (PARTITION BY vehicle_id ORDER BY s) AS g
          FROM v),
--: ONE INTERVAL PER VEHICLE PER CONTIGUOUS BUSY SPAN. This merge is the whole
--: correction of §3(c): without it the query counts tasks, and a technician is a vehicle.
merged AS (SELECT vehicle_id, min(s) AS s, max(f) AS f FROM grp GROUP BY vehicle_id, g),
ev AS (SELECT s AS t, 1 AS d FROM merged UNION ALL SELECT f, -1 FROM merged),
c  AS (SELECT t, sum(d) OVER (ORDER BY t, d DESC ROWS UNBOUNDED PRECEDING) AS busy FROM ev)
SELECT (SELECT count(*) FROM a)                     AS metered_atoms,
       (SELECT count(*) FROM merged)                AS vehicle_busy_spans,
       (SELECT max(busy) FROM c)                    AS peak_vehicles_busy,
       (SELECT round(avg(busy), 2) FROM c)          AS mean_vehicles_busy,
       (SELECT count(*) FROM c WHERE busy > 10)     AS moments_over_pool,
       public.ottoq_depot_staffing_count('11111111-1111-1111-1111-111111111111',
                                         'general_tech') AS pool_size;

-- the 12.6% the meter cannot see (§3b) -- a property, not this run's cause.
SELECT n.status AS visit_status, count(*) AS metered_atoms_that_ran
  FROM public.ottoq_visit_needs n
 CROSS JOIN LATERAL jsonb_array_elements(n.atoms) e
 WHERE n.sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112'
   AND n.status <> 'superseded'
   AND e->>'concurrency' IN ('cabin', 'exterior')
   AND pg_input_is_valid(COALESCE(e->>'started_at', ''), 'timestamptz')
 GROUP BY 1 ORDER BY 2 DESC;

-- ══ 4. WHAT IS NOT ESTABLISHED ═════════════════════════════════════════════
--
-- **This is not a before/after throughput comparison and must not be quoted as one.** The
-- pre-`0383` figures in §1 come from run `562bf027` (busy_day, seed **777777**), a different
-- seed from this run's 101959. Different seeds mean different arrival streams, so the KPI
-- columns are not comparable and no throughput delta is claimed here. The only clean way to
-- price G86 is C5's CRN-paired A/B -- same seed, shield held constant, one arm with the fix
-- -- which `db/checks/0146` specifies and which does not exist yet. What §1 DOES establish
-- needs no pairing: a service that completed zero times now completes, on its own run.
--
-- Also open: one run, one seed, one night window; and 2 of the 85 walkarounds are neither
-- done nor pending, which the class-coverage row attributes to a cancellation.
