-- ============================================================================
-- depot_geometry_guard.sql -- STANDING CHECK, READ ONLY
--
-- Migration 0010 asserts the depot's geometry at the moment it applies. This file
-- asserts it any time you like, against whatever is in the table right now. It
-- writes nothing: every statement is a SELECT, so it is safe to run on production,
-- in CI, or in the middle of a demo.
--
-- The seed-side twin of this file is ottoyarddepot-sim/scripts/checkLayoutGeometry.mjs,
-- which checks the layout BEFORE it reaches the database. This one checks after.
--
-- WHY IT EXISTS. Before 0010, this database held 54 overlapping stall pairs, 13
-- staging spaces inside the wash building, 20 charging spaces with no drivable
-- aisle, and 5 bays with no dimensions at all. None of it was noticed for months,
-- because nothing ever looked. Every check below names the offending stall codes,
-- because a count is not something anyone can act on.
--
-- USAGE
--   psql "$DATABASE_URL" -f db/checks/depot_geometry_guard.sql
--   Every result set should come back with status = 'PASS'.
--
-- ----------------------------------------------------------------------------
-- MEASURABILITY -- read this before editing any geometry check below.
--
-- A stall with NULL width, depth or coordinates has NO FOOTPRINT. It cannot be
-- overlapped, enclosed or fenced, because there is nothing there to test. It is
-- not a passing stall, it is an UNTESTED one, and the two must never print the
-- same way.
--
-- This is not hypothetical. It is the exact defect that made 0010 necessary, and
-- the first version of THIS FILE got it wrong. LEAST() and GREATEST() in Postgres
-- SKIP nulls rather than propagating them, so LEAST(NULL, c.x1) returns c.x1 --
-- a stall with no dimensions silently adopted its neighbour's edges and collided
-- with everything. Measured on the live pre-0010 database, check 3 reported
--
--     779 overlapping pairs per depot
--
-- when the true figure at the declared footprints is
--
--      54 overlapping pairs across 76 of 150 stalls   <- the audit's headline
--
-- The other 725 were phantoms manufactured by the five NULL-dimension bays. And
-- the error is not always inflationary: in check 5, `b.x0 < f.x0` with a NULL x0
-- yields NULL, so those same five stalls were dropped from the fence test
-- entirely -- a NULL-dimension stall sitting outside the fence would not have
-- been reported at all.
--
-- So every geometry CTE below is restricted to MEASURABLE stalls, and every
-- geometry check carries a `not_assessed` column and reports FAIL whenever that
-- column is non-zero. A check that quietly skips its hardest input is worse than
-- no check, because it reports confidence it has not earned.
-- ----------------------------------------------------------------------------
-- ============================================================================

\echo '=== 1. counts per depot (expect staging 115, l2 30, dcfc 10, wash_bay 3, service_bay 2) ==='
SELECT d.depot_id,
       CASE WHEN bool_and(ok) AND count(*) = 5 THEN 'PASS' ELSE 'FAIL' END AS status,
       string_agg(stall_type || '=' || n || CASE WHEN ok THEN '' ELSE ' (WRONG)' END,
                  ', ' ORDER BY stall_type) AS detail
  FROM (
    SELECT depot_id, stall_type::text AS stall_type, count(*) AS n,
           count(*) = CASE stall_type::text
             WHEN 'staging' THEN 115 WHEN 'l2' THEN 30 WHEN 'dcfc' THEN 10
             WHEN 'wash_bay' THEN 3 WHEN 'service_bay' THEN 2 ELSE -1 END AS ok
      FROM public.stalls GROUP BY depot_id, stall_type
  ) d
 GROUP BY d.depot_id ORDER BY d.depot_id;

\echo ''
\echo '=== 2. no NULL or non-positive width / depth / coordinates / map point ==='
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS offending_stalls,
       left(coalesce(string_agg(stall_code, ', ' ORDER BY stall_code), ''), 1200) AS stall_codes
  FROM public.stalls
 WHERE stall_width_ft IS NULL OR stall_depth_ft IS NULL
    OR stall_width_ft <= 0 OR stall_depth_ft <= 0
    OR relative_x IS NULL OR relative_y IS NULL
    OR absolute_lat IS NULL OR absolute_lng IS NULL OR absolute_point IS NULL;

\echo ''
\echo '=== 3. zero overlapping stall pairs ==='
-- heading 0/180 puts the vehicle LENGTH on y; 90/270 puts it on x.
-- Restricted to measurable stalls -- see the MEASURABILITY note in the header.
WITH b AS (
  SELECT depot_id, stall_code,
         relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
         relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
         relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
         relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
    FROM public.stalls
   WHERE stall_width_ft IS NOT NULL AND stall_depth_ft IS NOT NULL
     AND stall_width_ft > 0 AND stall_depth_ft > 0
     AND relative_x IS NOT NULL AND relative_y IS NOT NULL),
skipped AS (
  SELECT count(*) AS n FROM public.stalls
   WHERE stall_width_ft IS NULL OR stall_depth_ft IS NULL
      OR stall_width_ft <= 0 OR stall_depth_ft <= 0
      OR relative_x IS NULL OR relative_y IS NULL)
SELECT CASE WHEN count(*) = 0 AND (SELECT n FROM skipped) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS overlapping_pairs,
       (SELECT n FROM skipped) AS not_assessed,
       left(coalesce(string_agg(a.stall_code || ' <-> ' || c.stall_code ||
              ' (' || round(LEAST(LEAST(a.x1,c.x1)-GREATEST(a.x0,c.x0),
                                  LEAST(a.y1,c.y1)-GREATEST(a.y0,c.y0))::numeric, 2) || ' ft)',
              ', ' ORDER BY a.stall_code), ''), 1500) AS pairs
  FROM b a JOIN b c ON c.depot_id = a.depot_id AND c.stall_code > a.stall_code
 WHERE LEAST(a.x1, c.x1) - GREATEST(a.x0, c.x0) > 0.000001
   AND LEAST(a.y1, c.y1) - GREATEST(a.y0, c.y0) > 0.000001;

\echo ''
\echo '=== 4. no stall inside a structure, except the founder-confirmed service garage ==='
-- The two service bays sit inside the office building ON PURPOSE: it is an ATTACHED
-- SERVICE GARAGE and the founder confirmed it when reviewing the layout. A wash bay
-- is inside the wash building by definition. Those five are exempt BY CODE so that
-- any OTHER stall inside any OTHER structure still fails. Do not generalise this to
-- "bays may be inside buildings" -- that would hide the next one.
WITH b AS (
  SELECT depot_id, stall_code,
         relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
         relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
         relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
         relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
    FROM public.stalls
   WHERE stall_width_ft IS NOT NULL AND stall_depth_ft IS NOT NULL
     AND stall_width_ft > 0 AND stall_depth_ft > 0
     AND relative_x IS NOT NULL AND relative_y IS NOT NULL),
skipped AS (
  SELECT count(*) AS n FROM public.stalls
   WHERE stall_width_ft IS NULL OR stall_depth_ft IS NULL
      OR stall_width_ft <= 0 OR stall_depth_ft <= 0
      OR relative_x IS NULL OR relative_y IS NULL)
SELECT CASE WHEN count(*) = 0 AND (SELECT n FROM skipped) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS buried_stalls,
       (SELECT n FROM skipped) AS not_assessed,
       left(coalesce(string_agg(b.stall_code || ' in ' || t.structure_code ||
                                ' (' || t.structure_kind || ')', ', ' ORDER BY b.stall_code), ''), 1500) AS detail
  FROM b
  JOIN public.ottoq_site_structures t
    ON t.depot_id = b.depot_id
   AND t.status = 'active'
   AND t.width_ft IS NOT NULL AND t.length_ft IS NOT NULL
   AND t.structure_kind IN ('office_building','service_building','wash_building',
                            'bess_compound','transformer','perimeter_wall','lighting_pole')
   AND LEAST(b.x1, t.origin_x_ft + t.width_ft)  - GREATEST(b.x0, t.origin_x_ft) > 0.000001
   AND LEAST(b.y1, t.origin_y_ft + t.length_ft) - GREATEST(b.y0, t.origin_y_ft) > 0.000001
 WHERE NOT (b.stall_code IN ('NASH-SVC-01','NASH-SVC-02') AND t.structure_code = 'OFFICE-01')
   AND NOT (b.stall_code IN ('NASH-WSH-01','NASH-WSH-02','NASH-WSH-03') AND t.structure_code = 'WASH-01-BLDG');

\echo ''
\echo '=== 5. every stall inside the perimeter fence ==='
WITH f AS (SELECT depot_id, origin_x_ft x0, origin_y_ft y0,
                  origin_x_ft + width_ft x1, origin_y_ft + length_ft y1
             FROM public.ottoq_site_structures WHERE structure_code = 'FENCE-PERIMETER'),
     b AS (
  SELECT depot_id, stall_code,
         relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
         relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
         relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
         relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
    FROM public.stalls
   WHERE stall_width_ft IS NOT NULL AND stall_depth_ft IS NOT NULL
     AND stall_width_ft > 0 AND stall_depth_ft > 0
     AND relative_x IS NOT NULL AND relative_y IS NOT NULL),
skipped AS (
  SELECT count(*) AS n FROM public.stalls
   WHERE stall_width_ft IS NULL OR stall_depth_ft IS NULL
      OR stall_width_ft <= 0 OR stall_depth_ft <= 0
      OR relative_x IS NULL OR relative_y IS NULL)
SELECT CASE WHEN count(*) = 0 AND (SELECT n FROM skipped) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS outside_fence,
       (SELECT n FROM skipped) AS not_assessed,
       left(coalesce(string_agg(b.stall_code, ', ' ORDER BY b.stall_code), ''), 1200) AS stall_codes
  FROM b JOIN f ON f.depot_id = b.depot_id
 WHERE b.x0 < f.x0 - 0.000001 OR b.y0 < f.y0 - 0.000001
    OR b.x1 > f.x1 + 0.000001 OR b.y1 > f.y1 + 0.000001;

\echo ''
\echo '=== 6. the parcel is the real one (452 x 314 ft, ~3.26 acres) ==='
SELECT CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
       count(*) AS depots_with_wrong_parcel,
       left(coalesce(string_agg(id::text || ' = ' || site_length_ft || ' x ' || site_width_ft ||
                                ' ft / ' || site_acres || ' ac', ', ' ORDER BY id), ''), 800) AS detail
  FROM public.depots
 WHERE round(site_length_ft) <> 452 OR round(site_width_ft) <> 314;

\echo ''
\echo '=== 7. REPORT ONLY: stalls tighter than the 6.6 x 16.0 ft design vehicle ==='
-- Not a failure. Canopy B and C west columns are pitched at 16.17 ft, so their
-- stalls derive to 15.67 ft deep. The layout is founder-approved and no stall
-- centre moved. Named here so nobody has to rediscover it with a tape measure.
SELECT count(*) AS tight_stalls,
       left(coalesce(string_agg(stall_code || ' (' || round(stall_width_ft,2) || ' x ' ||
                                round(stall_depth_ft,2) || ' ft)', ', ' ORDER BY stall_code), ''), 1500) AS detail
  FROM public.stalls
 WHERE stall_depth_ft < 16.0 OR stall_width_ft < 6.6;
