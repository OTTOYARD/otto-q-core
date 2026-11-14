-- migration-version: PENDING
-- migration-name:    0826_every_fast_charger_arm_stands_on_the_cars_left
--
-- 0826  **Every fast-charger post's arm stands on the car's left.**
--
-- NOT APPLIED. APPLY IT WHEN ottoyarddepot-sim PR #170 IS MERGED AND DEPLOYED, NOT BEFORE: until then the twin the
--   viewer sees still draws a west-column post's arm on the car's right, and a left-port car this file lets OTTO-Q seat
--   there would stand at an arm that does not reach it (mateSolver refuses, the arm stays folded).
--
-- WHY. Chase, 2026-11-13 (morning CT): "let's go ahead and flip the right hand charger arms to the left-hand side.
--   Let's still keep it angled since it's easy to pull in and back out that way."
--   No vehicle in the fleet has its charge inlet on its right (0824's profiles: I-PACE, Model Y, Gravity and the
--   Zeekr on the left; the Zoox presents either flank; the Cybercab's is in its rear bumper). With 15 of the twin
--   depot's 30 posts standing on the car's right, 78 of its 116 cars fitted 15 posts (0824 section 3).
--
-- §1 WHAT WAS SO. public.ottoq_stall_arm_side reads the side from the post's heading: 60 (the west column) is the
--   car's right, 300 (the east column) its left. That was the depot as drawn until ottoyarddepot-sim's
--   depotPlacement.towardFor changed on 2026-11-13.
--
-- §2 WHAT THIS DOES. public.ottoq_stall_arm_side returns 'left' for every fast-charger post. Nothing else changes:
--   the fit rule, the proposer's filter and the charge step's check (0824, 0825) read this function. With every post
--   on the left, every car of the six profiles fits every post, so the decline and the side preference never fire
--   at the twin depot; they stay for a depot that has a post on the right, or a vehicle with a right-side inlet.
--   No stall row is written and no stall moves: the posts keep their headings and their places.
--
-- §3 WHAT THIS DOES NOT DO. It does not record the side per post. If a depot is ever built with posts on both sides,
--   the side belongs on the stall row; this function is then the one place to read it.
--
-- §4 PRECONDITIONS AND CHECKS. P0 no certification in flight. P1 the body this file replaces (md5 of prosrc, read from
--   0824 as applied). P2 once. V3 at the twin depot all 30 posts read 'left', and every autonomous car there fits
--   every post by the pure rule.
--
-- §5 CLASSIFICATION. forces_recert TRUE (which posts a left-port car is offered changes at the twin depot),
--   forces_dial_restart FALSE.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0826_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0826_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0826 P0: a certification is in flight'; END IF;
  IF position('s.heading_degrees < 180 THEN ''right'' ELSE ''left''' IN
              (SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_stall_arm_side(uuid)'))) = 0 THEN
    RAISE EXCEPTION '0826 P1: public.ottoq_stall_arm_side is not the body 0824 stored';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0826_%') THEN RAISE EXCEPTION '0826 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0826_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_stall_arm_side(uuid)']) AS f;

CREATE OR REPLACE FUNCTION public.ottoq_stall_arm_side(p_stall uuid)
 RETURNS text LANGUAGE sql STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0826: every fast-charger post's arm stands on the car's LEFT (ottoyarddepot-sim depotPlacement.towardFor, since
     2026-11-13). Before, 0824 read it from the heading: 60, the west column, was the car's right. */
  SELECT CASE WHEN s.stall_type::text <> 'dcfc' THEN NULL ELSE 'left' END
    FROM public.stalls s WHERE s.id = p_stall;
$function$;

CREATE TEMP TABLE _0826_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_left int; v_posts int; v_cars int; v_misfit int;
BEGIN
  SELECT count(*) FILTER (WHERE public.ottoq_stall_arm_side(id) = 'left'), count(*)
    INTO v_left, v_posts FROM public.stalls WHERE depot_id = c_depot AND stall_type::text = 'dcfc';
  IF v_posts = 0 OR v_left <> v_posts THEN RAISE EXCEPTION '0826 V3: % of % posts read left', v_left, v_posts; END IF;
  SELECT count(*), count(*) FILTER (WHERE NOT public.ottoq_port_side_fits(pf.port_face, pf.presents_either_side, 'left'))
    INTO v_cars, v_misfit
    FROM public.vehicles v CROSS JOIN LATERAL public.ottoq_vehicle_port_profile(v.id) pf
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous';
  IF v_misfit > 0 THEN RAISE EXCEPTION '0826 V3: % of % cars at the twin depot do not fit a left-arm post', v_misfit, v_cars; END IF;
  INSERT INTO _0826_selftest VALUES (jsonb_build_object('posts_left', v_left, 'posts', v_posts, 'cars', v_cars, 'cars_that_fit_no_post', v_misfit));
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0826_every_fast_charger_arm_stands_on_the_cars_left', true, false,
        'Every fast-charger post reads arm side left. V3 at apply: '
        || COALESCE((SELECT result::text FROM _0826_selftest LIMIT 1), 'no result'), now());
COMMIT;
