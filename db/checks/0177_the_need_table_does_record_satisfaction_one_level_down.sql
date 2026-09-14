-- ===========================================================================
-- 0177  THE NEED TABLE DOES RECORD SATISFACTION -- ONE LEVEL DOWN
--       (0171's second floor is UNBLOCKED; and three completion writers
--        disagree about what a finished operation looks like)
-- ===========================================================================
-- Measured 2026-09-12 14:35-14:50 UTC (09:35-09:50 AM CT), read-only, while round 38
-- ran. Nothing was written; no run was started.
--
-- db/checks/0171 declared the intent's SECOND FLOOR -- service_completion -- BLOCKED,
-- on this measurement: all 107,055 ottoq_visit_needs rows carry status='superseded' and
-- the counts for complete / open / in_progress / carried_over are zero. That
-- measurement was right. THE CONCLUSION DRAWN FROM IT WAS WRONG, and the sentence to
-- retire is 0171's own: "the need table records DEMAND and never records SATISFACTION."
-- It is true of the status COLUMN. It is false of the TABLE.
--
-- ---------------------------------------------------------------------------
-- 1. WHERE SATISFACTION ACTUALLY LIVES
-- ---------------------------------------------------------------------------
--
-- ottoq_visit_needs.atoms is a jsonb array, one element per operation, and each element
-- carries its own status. Pinned to run 5d00244c-10c8-4ffc-b6c0-20dff04024bb
-- (busy_day/424242/12t, fired 2026-09-12 14:29 UTC), whose ROW status is
-- 'superseded' for all 116 rows:
--
--   atoms total          549
--   status done          247
--   never_started (none) 295
--   in_progress            4
--   cancelled              2
--   open                   1
--
-- So 247 operations were completed inside a run whose every need row reads
-- 'superseded'. The row status is the run-terminal janitor's stamp; the atom status is
-- the work record. 0171 read the first and concluded about the second.
--
-- ---------------------------------------------------------------------------
-- 2. THE FLOOR IS COMPUTABLE, REPRODUCIBLE AND SENSITIVE -- ALL THREE MEASURED
-- ---------------------------------------------------------------------------
--
-- Four pairs from round 38, both arms of each listed separately, nothing averaged:
--
--   fired  seed    scenario    arm        atoms  must_do  done  must_do_done
--   13:47  314159  busy_day    64e75783    535     381    248      220
--   13:47  314159  busy_day    a8d0d948    535     381    248      220
--   14:01  171717  busy_day    96b371e8    549     379    239      208
--   14:01  171717  busy_day    a9a67c1b    549     379    239      208
--   14:15  171717  normal_day  921b2952    548     375    243      213
--   14:15  171717  normal_day  c06e1608    548     375    243      213
--   14:29  424242  busy_day    5d00244c    549     386    247      219
--   14:29  424242  busy_day    6545cc5b    549     386    247      219
--
--   REPRODUCIBLE: in all four pairs the two arms agree EXACTLY, on every column.
--   SENSITIVE:    the values differ across (seed, scenario) -- must_do completion
--                 57.7% / 54.9% / 56.8% / 56.7%. It is not a constant, which is what
--                 0172 caught the readiness deadline being.
--
-- That is the bar a KPI has to clear before it can ship, and this one clears it on
-- measurement rather than on argument. service_completion_rate is therefore UNBLOCKED:
-- it is `done / must_do` over the atoms, per run, and it already varies with the world.
--
-- ---------------------------------------------------------------------------
-- 3. AND NOW THE PART THAT IS NOT GOOD NEWS: THREE COMPLETION SHAPES
-- ---------------------------------------------------------------------------
--
-- Timestamp coverage of the 247 done atoms in run 5d00244c, by service:
--
--   svc                  done  started_at  ends_at  done_at  closed_at  closed_by
--   interior_inspection    66      66         66       66        0      (null)
--   charge                 64       0          0        0       64      ottoq_satisfied
--   readiness_check        45       0          0       45        0      (null)
--   exterior_wash          23       0          0       23        0      (null)
--   interior_tidy          19      18         18       19        0      (null)
--   triage_check            7       7          7        7        0      (null)
--   interior_deep_clean     6       0          0        6        0      (null)
--   item_retrieval          5       5          5        5        0      (null)
--   sensor_clean            5       3          3        5        0      (null)
--   remote_diagnostics      4       4          4        4        0      (null)
--   cosmetic_repair         2       0          0        2        0      (null)
--   mechanical_pm           1       0          0        1        0      (null)
--
-- THREE DIFFERENT VOCABULARIES FOR "FINISHED":
--   shape 1, EXECUTED -- started_at + ends_at + done_at. 103 of 247 atoms.
--   shape 2, CREDITED -- done_at only, no start and no end. 80 atoms.
--   shape 3, SATISFIED -- closed_at + closed_by='ottoq_satisfied', and NO done_at at
--            all. 64 atoms, every one of them `charge`.
--
-- CONSEQUENCES, stated as limits rather than as a complaint:
--
--   (a) A COUNT of completion works across all three shapes. 247 is a real number.
--   (b) A DURATION works only for shape 1 -- 103 of 247, 41.7%. Anything of the form
--       "how long did an operation take" is unmeasurable for 58% of completed work.
--   (c) For `charge` it is 0%. The single operation whose duration dominates every
--       schedule in this system carries no start, no end and no done_at -- only the
--       instant a satisfaction check noticed it no longer needed charging. So the
--       duration model cannot be calibrated from the atom ledger for the one service
--       the duration model is mostly about.
--
-- WHY THAT MATTERS BEYOND TIDINESS. BUILD_QUEUE 4f opened on "charge_dcfc averages 73
-- booked minutes against a catalog of 20-45" and treated it as a contradiction. It is
-- not -- not yet. The atom's OWN estimate for charge in this run is est_min 35.8,
-- squarely inside the catalog band. 73 minutes is how long a STALL was booked; 35.8 is
-- how long the charge was expected to take. Those are different quantities and the
-- difference between them is exactly the dwell a turns-per-point KPI is about. Which of
-- them is wrong cannot be settled from here, because the one number that would settle
-- it -- the actual charge duration -- is the one shape 3 does not record. 4f is
-- therefore RESTATED, not answered, and its 73-vs-45 framing must not be quoted.
--
-- ---------------------------------------------------------------------------
-- 4. ONE MORE THING THE COUNTS SAY OUT LOUD
-- ---------------------------------------------------------------------------
--
--   perimeter_walkaround: 108 atoms in one run. must_do 0. done 0. never started 108.
--
-- It is derived for almost every vehicle, required of none, and performed never. 0172
-- separately measured `perimeter_hold` consuming 45,025 booked stall-minutes -- the
-- largest single consumer of the calendar, ahead of charge_l2 and charge_dcfc. Those
-- are two different objects (a hold is a booking, a walkaround is an operation) and
-- whether the first is the staging cost of the second is NOT established here. Logged
-- because "derived 108 times, performed zero times" is this list's governing pattern
-- again: machinery that exists and is never called.
--
-- ---------------------------------------------------------------------------
-- 5. METHOD NOTE -- THE SAMPLE MOVED UNDER ME AGAIN, MID-MEASUREMENT
-- ---------------------------------------------------------------------------
--
-- The first pass of section 1 read "the most recent 12-tick flagship cert run" without
-- pinning it, and between two queries round 38's 14:29 pair landed and became the most
-- recent. The totals happened to be close enough (549/247 both times) that nothing
-- looked wrong. 0172 recorded this exact trap four hours earlier and I walked into it
-- again. Every number above is now pinned to a named run id or listed per arm. The rule
-- stands and is apparently worth repeating: while a round is firing, "most recent" is
-- not an identifier.
--
-- ---------------------------------------------------------------------------
-- 6. WHAT THIS CHANGES IN THE QUEUE
-- ---------------------------------------------------------------------------
--
--   * 0171's service_completion floor: BLOCKED -> BUILDABLE, from the atoms.
--   * The metric ships as a COUNT first (done / must_do), with no duration claim
--     attached, because (b) and (c) above bound what the ledger can support.
--   * A duration or tardiness metric needs shape 3 to stamp a start and an end, which
--     is a change to the charge satisfaction path -- filed, not done here.
--   * 4f's "73 vs 45" is withdrawn as a contradiction and restated as two different
--     quantities with the reconciling number missing.
--
-- The workflow that prompted this (read-only, five investigators plus adversarial
-- verify) reported the same direction independently. Its headline claims were NOT taken
-- on report: sections 1-4 above are my own measurements against the live database, and
-- section 3's three-shape split is not in its output at all.
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 6.1  The floor itself, per arm. Pass the run ids you mean; never "most recent".
WITH a AS (
  SELECT vn.sim_run_id,
         COALESCE(e->>'status','never_started') AS st,
         COALESCE((e->>'must_do')::boolean,false) AS must_do,
         ((e->>'started_at') IS NOT NULL AND (e->>'ends_at') IS NOT NULL) AS timeable
    FROM public.ottoq_visit_needs vn,
         jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
   WHERE vn.sim_run_id IN ('5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid,
                           '6545cc5b-2deb-4174-b549-28ccd1677947'::uuid)
)
SELECT sim_run_id,
       count(*) AS atoms,
       count(*) FILTER (WHERE must_do) AS must_do,
       count(*) FILTER (WHERE must_do AND st='done') AS must_do_done,
       round(100.0*count(*) FILTER (WHERE must_do AND st='done')
             / nullif(count(*) FILTER (WHERE must_do),0),1) AS service_completion_pct,
       count(*) FILTER (WHERE st='done' AND timeable) AS done_and_timeable,
       round(100.0*count(*) FILTER (WHERE st='done' AND timeable)
             / nullif(count(*) FILTER (WHERE st='done'),0),1) AS pct_of_done_with_a_duration
  FROM a
 GROUP BY 1;

-- 6.2  The three completion shapes. If a fourth appears, the metric needs re-reading
--      before it is quoted.
WITH a AS (
  SELECT (e->>'svc') AS svc,
         ((e->>'started_at') IS NOT NULL) AS has_started,
         ((e->>'ends_at')    IS NOT NULL) AS has_ends,
         ((e->>'done_at')    IS NOT NULL) AS has_done_at,
         ((e->>'closed_at')  IS NOT NULL) AS has_closed_at,
         (e->>'closed_by')   AS closed_by
    FROM public.ottoq_visit_needs vn,
         jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
   WHERE vn.sim_run_id = '5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid
     AND COALESCE(e->>'status','') = 'done'
)
SELECT CASE WHEN has_started AND has_ends AND has_done_at THEN '1_executed'
            WHEN has_done_at                              THEN '2_credited'
            WHEN has_closed_at                            THEN '3_satisfied'
            ELSE '4_UNKNOWN_SHAPE' END AS shape,
       count(*) AS atoms,
       string_agg(DISTINCT svc, ', ' ORDER BY svc) AS services,
       string_agg(DISTINCT COALESCE(closed_by,'(null)'), ',') AS closed_by
  FROM a
 GROUP BY 1
 ORDER BY 1;

-- 6.3  Derived but never required and never performed.
WITH a AS (
  SELECT (e->>'svc') AS svc, COALESCE(e->>'status','never_started') AS st,
         COALESCE((e->>'must_do')::boolean,false) AS must_do
    FROM public.ottoq_visit_needs vn,
         jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
   WHERE vn.sim_run_id = '5d00244c-10c8-4ffc-b6c0-20dff04024bb'::uuid
)
SELECT svc, count(*) AS atoms,
       count(*) FILTER (WHERE must_do) AS must_do,
       count(*) FILTER (WHERE st='done') AS done,
       count(*) FILTER (WHERE st='never_started') AS never_started
  FROM a
 GROUP BY svc
HAVING count(*) FILTER (WHERE st='done') = 0
 ORDER BY atoms DESC;
