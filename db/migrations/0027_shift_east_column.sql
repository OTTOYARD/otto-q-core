-- 0027: shift staging_east column east to clear lane overlap (P1-5)
-- The E-column staging stalls at x=437.2121 (both depots) overlap the northbound
-- driving lane by 0.9 plan units. Moved 2 plan units east (3.14 ft) to match
-- the sitePlan.ts fix (x0 284.5→286.5, carport 278→280).
-- West avenue has 4.1u clearance and no hotspot; this mirrors that pattern.

DO $$
DECLARE
  v_fix_ft numeric := 3.14;
BEGIN
  UPDATE stalls
     SET relative_x = relative_x + v_fix_ft
   WHERE zone = 'staging_east';

  RAISE NOTICE 'Shifted % staging_east stalls east by % ft', 
    (SELECT count(*) FROM stalls WHERE zone = 'staging_east'), v_fix_ft;
END
$$;
