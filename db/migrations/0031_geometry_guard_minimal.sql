-- MIGRATION: 0031_geometry_guard_minimal.sql
-- Two DB-side geometry checks that run in <1s:
--   1. ottoq_check_fence_containment  — every stall inside its depot perimeter
--   2. ottoq_check_stall_overlap      — no two stalls closer than 5 ft (center-to-center)
--
-- These complement the 489-line JS guard (checkLayoutGeometry.mjs) and run directly
-- on the live database without needing psql.

-- Check 1: Fence containment
CREATE OR REPLACE FUNCTION public.ottoq_check_fence_containment(p_depot_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
DECLARE
  v_failures jsonb := '[]'::jsonb;
  v_rec RECORD;
  v_fence RECORD;
BEGIN
  FOR v_fence IN
    SELECT ss.depot_id, ss.origin_x_ft AS x0, ss.origin_y_ft AS y0,
           ss.origin_x_ft + ss.width_ft AS x1,
           ss.origin_y_ft + ss.length_ft AS y1
      FROM ottoq_site_structures ss
     WHERE ss.structure_kind = 'perimeter_wall'
       AND (p_depot_id IS NULL OR ss.depot_id = p_depot_id)
  LOOP
    FOR v_rec IN
      SELECT s.stall_code, s.relative_x, s.relative_y
        FROM stalls s
       WHERE s.depot_id = v_fence.depot_id
         AND (s.relative_x < v_fence.x0 OR s.relative_x > v_fence.x1
              OR s.relative_y < v_fence.y0 OR s.relative_y > v_fence.y1)
    LOOP
      v_failures := v_failures || jsonb_build_object(
        'check', 'fence_containment',
        'stall_code', v_rec.stall_code,
        'detail', format('stall at (%.2f,%.2f) outside fence (%.2f-%.2f, %.2f-%.2f)',
                         v_rec.relative_x, v_rec.relative_y,
                         v_fence.x0, v_fence.x1, v_fence.y0, v_fence.y1)
      );
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object(
    'check', 'fence_containment',
    'passed', jsonb_array_length(v_failures) = 0,
    'failures', v_failures
  );
END;
$fn$;

-- Check 2: Stall overlap (same-heading stalls < 5ft apart)
CREATE OR REPLACE FUNCTION public.ottoq_check_stall_overlap(p_depot_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT jsonb_build_object(
    'check', 'stall_overlap',
    'passed', count(*) = 0,
    'failure_count', count(*),
    'failures', COALESCE(jsonb_agg(
      jsonb_build_object('a', a_code, 'b', b_code, 'dist_ft', round(dist::numeric,1))
    ) FILTER (WHERE a_code IS NOT NULL), '[]'::jsonb)
  )
  FROM (
    SELECT a.stall_code AS a_code, b.stall_code AS b_code,
           SQRT(POWER(a.relative_x - b.relative_x, 2) + POWER(a.relative_y - b.relative_y, 2)) AS dist
      FROM stalls a
      JOIN stalls b ON b.depot_id = a.depot_id AND b.id > a.id
     WHERE (p_depot_id IS NULL OR a.depot_id = p_depot_id)
       AND a.heading_degrees = b.heading_degrees
       AND SQRT(POWER(a.relative_x - b.relative_x, 2) + POWER(a.relative_y - b.relative_y, 2)) < 5.0
  ) t
$fn$;
