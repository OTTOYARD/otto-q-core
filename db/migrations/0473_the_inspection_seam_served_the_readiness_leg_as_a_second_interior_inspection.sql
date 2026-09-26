-- migration-version: 20260926070924
-- migration-name:    the_inspection_seam_served_the_readiness_leg_as_a_second_interior_inspection
--
-- 0473  **The inspection seam served every itinerary's final readiness leg as a second interior inspection, as soon
--       as the first was done.** `db/checks/0359`. FINDINGS G207.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run 49c45bd4 (busy_day, twin depot `11111111-…`), sim 8:00-10:35 AM CT, read live: 91 `inspect`
--   bookings for 52 cars, 33 of them a second visit to the inspection lane within two minutes of the first, each on
--   a different leg. Of the run's 203 `inspect` legs, 106 carry `duration_basis.atom = 'readiness_check'` and 97
--   `interior_inspection`; 46 of the readiness legs were served at the inspection lane (42 done), half of all its use.
--   Waymo-AV-024: interior inspection 10:31-10:35 on stall bf082cbd, then its readiness leg, planned for 3:31 AM after
--   an overnight L2 charge, served on the same stall 10:35-10:38.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_plan_visit_itinerary` ends every itinerary with a fixed 3-minute leg of type `inspect` tagged
--   `atom: readiness_check`: the readiness gate at the end of the visit, which the service flow's deploy gate performs.
--   `ottoq.ottoq_enact_inspection_seam` exists for `interior_inspection` (its `c_svc`) but picks the first planned leg
--   of type `inspect` by seq, whatever its atom and whenever it is planned. Once the interior-inspection leg is done,
--   the readiness leg is next, so the car goes straight back to the lane. Serving it early also empties the itinerary
--   of planned legs, which lets the next `ottoq_plan_visit_itinerary` call append a new set (11 cars carry 4 inspect
--   legs).
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The seam's leg pick takes only legs whose atom is `interior_inspection`, or that carry no atom at all (legs
--   written before the planner tagged them). The readiness leg stays planned until the visit's artifacts are released
--   at redeploy, as every other unserved leg does. Nothing else reads the leg type differently.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Inspection bookings, commands, decisions and legs move.
--
--   PREDICTED on the next busy_day run: no `inspect` booking whose leg is tagged `readiness_check`; inspection-lane
--   visits roughly halve; no car carries more than two `inspect` legs per visit.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0473 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (after 0472) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure))
     <> '59f58d0c40bf0a508257a4f61c1fb605' THEN
    RAISE EXCEPTION '0473 P2: ottoq.ottoq_enact_inspection_seam is not the body this file patches';
  END IF;
  -- the planner still tags its fixed final leg as the readiness check, and its concurrent legs by their atom
  IF position($x$'inspect', v_cursor, v_cursor + interval '3 minutes',
         180, jsonb_build_object('kind','flow_contract','atom','readiness_check'), 'planned');$x$
              IN pg_get_functiondef('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0473 P2: the planner no longer tags its final inspect leg readiness_check';
  END IF;
  IF public.ottoq_svc_to_leg_type('interior_inspection') IS DISTINCT FROM 'inspect' THEN
    RAISE EXCEPTION '0473 P2: interior_inspection no longer maps to the inspect leg type';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0473_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure;

DO $patch_seam$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure);
  v_pat text := $p$AND il\.leg_type\s+= v_leg_type\s+AND il\.to_stall_id IS NULL\s+ORDER BY il\.seq$p$;
  v_new text := $r$AND il.leg_type    = v_leg_type
           AND il.to_stall_id IS NULL
           -- 0473 (G207): an interior inspection, not the readiness leg the planner ends every itinerary with
           -- (also type inspect, atom readiness_check). Untagged legs predate the tag and are inspections.
           AND COALESCE(il.duration_basis->>'atom', c_svc) = c_svc
         ORDER BY il.seq$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0473: the seam leg pick matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_seam$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)'::regprocedure);
BEGIN
  -- V1: the atom filter sits in the leg pick, once; 0472's skip is still there.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$AND COALESCE\(il\.duration_basis->>'atom', c_svc\) = c_svc\s+ORDER BY il\.seq$x$, 'g')) <> 1
     OR position('0472 (G204)' IN v_s) = 0 THEN
    RAISE EXCEPTION '0473 V1: the seam is not the body this file writes';
  END IF;
  -- V2: one overload, the same ACL (owner and service_role).
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'ottoq' AND p.proname = 'ottoq_enact_inspection_seam') <> 1 THEN
    RAISE EXCEPTION '0473 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0473 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0473_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0473_the_inspection_seam_served_the_readiness_leg_as_a_second_interior_inspection', true,
  'Tick path: ottoq_enact_inspection_seam serves only interior_inspection legs (or untagged ones), not the planner''s '
  'final readiness leg. Inspection bookings, commands, decisions and legs move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
