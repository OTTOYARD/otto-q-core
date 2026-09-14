-- ===========================================================================
-- 0178  THE OPERATION CATALOG IS THE OTHER TABLE
--       (and one operation is in neither)
-- ===========================================================================
-- Measured 2026-09-12 14:50-15:00 UTC (09:50-10:00 AM CT), read-only, while round 38
-- ran. Nothing was written; no run was started.
--
-- Follows db/checks/0177, which established that the work record is atoms[].status and
-- that the atom's service key is `svc`. The obvious next question -- and the one that
-- decides whether a pack can extend the operation set as DATA, which is the whole
-- platform thesis of CLAUDE.md 2.2 -- is: where does the `svc` vocabulary come from?
--
-- ---------------------------------------------------------------------------
-- 1. TWO CANDIDATE CATALOGS, AND WHICH ONE THE ENGINE ACTUALLY READS
-- ---------------------------------------------------------------------------
--
--   public.service_cadence_policy   15 rows, 15 distinct svc,  8 routines read it
--   public.service_definitions      27 rows,  9 distinct code, 6 routines read it
--
-- They are almost disjoint. Of the 16 distinct `svc` values that appear in atoms across
-- the whole table, `service_cadence_policy` declares 15 -- every one active, every one
-- carrying a `lane` -- and `service_definitions` declares exactly ONE, `exterior_wash`.
--
--   svc                    in service_cadence_policy (lane)   in service_definitions
--   charge                 yes  (anchor)                      no
--   cosmetic_repair        yes  (service_bay)                 no
--   exterior_wash          yes  (wash_bay)                    YES
--   fault_repair           yes  (service_bay)                 no
--   interior_deep_clean    yes  (detail)                      no
--   interior_inspection    yes  (cabin)                       no
--   interior_tidy          yes  (cabin)                       no
--   item_retrieval         yes  (cabin)                       no
--   mechanical_pm          yes  (service_bay)                 no
--   readiness_check        yes  (gate)                        no
--   remote_diagnostics     yes  (digital)                     no
--   sensor_calibration     yes  (service_bay)                 no
--   sensor_clean           yes  (exterior)                    no
--   software_update        yes  (digital)                     no
--   triage_check           yes  (cabin)                       no
--   perimeter_walkaround   NO                                 no
--
-- The bridge between the two is ottoq.ottoq_svc_to_stall_type(p_svc, p_depot_id), and it
-- settles the precedence in code rather than by inference. It reads
-- service_cadence_policy FIRST, and falls back to service_definitions only when no
-- cadence row exists -- under a comment that names the situation exactly:
--
--     -- Fallback: the catalogue table named in the brief. Only trusted when the type exists.
--
-- So the live operation catalog is service_cadence_policy. service_definitions is a
-- fallback consulted by one bridge, and it is the table CLAUDE.md 2.3 leads with.
--
-- WHAT THIS DOES AND DOES NOT SAY ABOUT CLAUDE.md. 2.3's row reads
-- "`service_definitions` (9), `service_cadence_policy`". It names BOTH, so it is not
-- wrong -- but the count is attached to the fallback (and "(9)" is its DISTINCT-code
-- count against 27 rows), and the ordering reads as though the first were the catalog.
-- The correction is therefore modest and is made as a marked note on that line, in the
-- style Part 3 already uses for the stalls figure: say which is live, which is fallback,
-- and which carries the count.
--
-- THE GOOD NEWS, WHICH IS THE LARGER HALF. The operation vocabulary IS declarative and
-- IS pack-extensible, 15 of 16 services, each with a lane, all active, read by eight
-- routines. C11's conformance harness has a real extension point to aim at. It just is
-- not the table the brief points at first.
--
-- ---------------------------------------------------------------------------
-- 2. THE ONE OPERATION IN NEITHER CATALOG
-- ---------------------------------------------------------------------------
--
-- perimeter_walkaround. Measured in 0177 against run 5d00244c: 108 atoms in a single
-- run, must_do 0, done 0, never started 108. Derived for almost every vehicle, required
-- of none, performed never -- and declared nowhere.
--
-- A HYPOTHESIS I FORMED AND THEN KILLED, recorded because it was wrong in an
-- instructive way. Since ottoq_svc_to_stall_type returns NULL for an undeclared service,
-- the obvious story was "no catalog row -> no bay -> can never be scheduled." Tested
-- against the flagship depot:
--
--     ottoq_svc_to_stall_type('perimeter_walkaround', flagship) -> NULL
--     ottoq_svc_to_stall_type('readiness_check',      flagship) -> NULL
--     ottoq_svc_to_stall_type('charge',               flagship) -> NULL
--     ottoq_svc_to_stall_type('exterior_wash',        flagship) -> 'wash_bay'
--
-- readiness_check and charge ALSO resolve to NULL -- NULL means "needs no bay", not
-- "cannot be scheduled" -- and they complete 45 and 64 times respectively in the same
-- run. So the missing catalog row is NOT established as the cause. Something else never
-- starts a walkaround, and this check does not name it.
--
-- That matters beyond this one service: it means an UNDECLARED operation is
-- indistinguishable, at the bay resolver, from a declared operation that needs no bay.
-- A pack could add an operation, spell it wrong, and get silence rather than an error.
-- A conformance harness (C11) should refuse a pack whose atoms name a service no catalog
-- declares -- which is a one-query assertion, and §3.3 below is that query.
--
-- ---------------------------------------------------------------------------
-- 3. WHAT THIS CHANGES
-- ---------------------------------------------------------------------------
--
--   * 0177's 4g (ship service_completion as a count) needs its vocabulary pinned to
--     service_cadence_policy, not service_definitions.
--   * C11/PACK_SPEC gains a concrete, measurable conformance rule: every `svc` an
--     atom names must exist and be active in the catalog. It fails today, on one row.
--   * CLAUDE.md 2.3 line 99 gets a marked note. The figure is not deleted; Part 3's
--     precedent is to leave the point-in-time record and say what is true now.
--
-- ===========================================================================
-- RE-RUNNABLE MEASUREMENTS
-- ===========================================================================

-- 3.1  The two catalogs, sized and counted by readers.
SELECT 'service_cadence_policy' AS catalog,
       (SELECT count(*) FROM public.service_cadence_policy) AS rows,
       (SELECT count(DISTINCT svc) FROM public.service_cadence_policy) AS distinct_keys,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~* 'service_cadence_policy') AS readers
UNION ALL
SELECT 'service_definitions',
       (SELECT count(*) FROM public.service_definitions),
       (SELECT count(DISTINCT code) FROM public.service_definitions),
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~* 'service_definitions');

-- 3.2  Atom vocabulary against both catalogs. The full 16-row table of section 1.
WITH atomsvc AS (
  SELECT DISTINCT (e->>'svc') AS svc
    FROM public.ottoq_visit_needs vn,
         jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
   WHERE (e->>'svc') IS NOT NULL
)
SELECT a.svc,
       (scp.svc IS NOT NULL) AS in_cadence_policy,
       scp.lane, scp.is_active,
       (sd.code IS NOT NULL) AS in_service_definitions
  FROM atomsvc a
  LEFT JOIN (SELECT DISTINCT svc, lane, is_active FROM public.service_cadence_policy) scp
         ON scp.svc = a.svc
  LEFT JOIN (SELECT DISTINCT code FROM public.service_definitions) sd
         ON sd.code = a.svc
 ORDER BY (scp.svc IS NULL) DESC, a.svc;

-- 3.3  THE CONFORMANCE ASSERTION C11 SHOULD CARRY. Every service an atom names must be
--      declared and active in the live catalog. Empty = conformant. One row today.
WITH atomsvc AS (
  SELECT DISTINCT (e->>'svc') AS svc
    FROM public.ottoq_visit_needs vn,
         jsonb_array_elements(COALESCE(vn.atoms,'[]'::jsonb)) e
   WHERE (e->>'svc') IS NOT NULL
)
SELECT a.svc AS undeclared_service
  FROM atomsvc a
 WHERE NOT EXISTS (SELECT 1 FROM public.service_cadence_policy p
                    WHERE p.svc = a.svc AND p.is_active)
 ORDER BY 1;

-- 3.4  The bay resolver's answers, which is why "returns NULL" proves nothing on its own.
SELECT s.svc,
       ottoq.ottoq_svc_to_stall_type(s.svc, '11111111-1111-1111-1111-111111111111'::uuid) AS bay
  FROM (VALUES ('perimeter_walkaround'),('readiness_check'),('charge'),('exterior_wash')) s(svc);
