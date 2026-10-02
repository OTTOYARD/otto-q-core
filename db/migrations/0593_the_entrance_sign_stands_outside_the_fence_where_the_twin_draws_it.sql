-- migration-version: 20261002014128
-- migration-name:    the_entrance_sign_stands_outside_the_fence_where_the_twin_draws_it
--
-- 0593  **The entrance sign stands outside the fence, where the twin draws it.** One data row at the twin depot:
--       SIGN-OTTOYARD-FRONT moves to the layout seed's new row. No function changes.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-01: "There is a signage section that completely cuts off a few of the parking spaces in the front of
--   the depot. Move or remove that." The renderer's sign wall stood across staging stalls S2-2..S2-5 (NASH-STG-S013..S016).
--   ottoyarddepot-sim #129 moved it to structurePlan.SIGN_WALL, outside the south fence on the frontage between the gates,
--   and made the layout seed (scripts/buildLayoutSeed.mjs) derive the database row from that same wall instead of a
--   hand-typed 60 ft wall 3 ft inside the fence. The database still holds the old row: 60 x 1 ft, 8 ft tall, origin
--   (196.063, 3) ft, i.e. inside the lot across the front staging row. Twin and engine should describe one depot.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_site_structures, twin depot only, structure_code SIGN-OTTOYARD-FRONT, to the seed's row
--   (unreal/layoutSeed.sql on ottoyarddepot-sim claude/sign-wall-clear-stalls, seed md5 4da9a8d7 unchanged):
--     origin_x_ft 196.0630 -> 207.2244     width_ft  60.0000 -> 37.6772     height_ft 8.0000 -> 7.2215
--     origin_y_ft   3.0000 ->  -3.2968     length_ft  1.0000 ->  1.8839     absolute_lat 36.13970962 -> 36.13969353
--   The centre keeps its x (226.06 ft, mid-frontage) and its longitude. A negative origin_y is south of the fence line
--   (y = 0), which is where the sign now stands. The Benchmark and grid-fixture copies are not changed (0561's rule).
--
--   Readers of the row: public.ottoq_twin_depot_layout (the cockpit's layout read) only. ottoq_check_fence_containment
--   reads perimeter_wall rows and stalls; ottoq_itin_travel_leg names the table in a comment; twin.ottoq_grid_fixture_create
--   copies rows into a fixture depot; twin.ottoq_sim_emit_telemetry does not filter on signs. No decision reads a sign.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the row is exactly the old one (so a hand edit since is not overwritten).
--   V1: the row is the new one. V2: no other structure row at the twin depot changed.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no decision, certified atom or fingerprint reads a sign.
--
-- ROLLBACK: UPDATE public.ottoq_site_structures SET origin_x_ft = 196.063, origin_y_ft = 3, width_ft = 60, length_ft = 1,
--             height_ft = 8, absolute_lat = 36.13970962
--            WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'SIGN-OTTOYARD-FRONT';
--           DELETE FROM public.ottoq_cert_lineage WHERE name = '0593_the_entrance_sign_stands_outside_the_fence_where_the_twin_draws_it';

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0593 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the row is the old one ──
DO $premises$
DECLARE r record;
BEGIN
  SELECT origin_x_ft, origin_y_ft, width_ft, length_ft, height_ft, absolute_lat, absolute_lng INTO r
    FROM public.ottoq_site_structures
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'SIGN-OTTOYARD-FRONT';
  IF NOT FOUND THEN RAISE EXCEPTION '0593 P1: no SIGN-OTTOYARD-FRONT row at the twin depot'; END IF;
  IF round(r.origin_x_ft::numeric, 3) <> 196.063 OR r.origin_y_ft <> 3 OR r.width_ft <> 60 OR r.length_ft <> 1
     OR r.height_ft <> 8 OR round(r.absolute_lat::numeric, 8) <> 36.13970962 THEN
    RAISE EXCEPTION '0593 P1: the sign row is not the one this file moves (%)', to_jsonb(r);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0593_the_entrance_sign_stands_outside_the_fence_where_the_twin_draws_it') THEN
    RAISE EXCEPTION '0593 P1: already applied';
  END IF;
END $premises$;

CREATE TEMP TABLE _0593_before ON COMMIT DROP AS
SELECT structure_id, md5(to_jsonb(s)::text) AS row_md5
  FROM public.ottoq_site_structures s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';

UPDATE public.ottoq_site_structures
   SET origin_x_ft = 207.2244, origin_y_ft = -3.2968, width_ft = 37.6772, length_ft = 1.8839,
       height_ft = 7.2215, absolute_lat = 36.13969353
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'SIGN-OTTOYARD-FRONT';

-- ── V1: the new row; V2: nothing else moved ──
DO $verify$
DECLARE r record; v_changed int;
BEGIN
  SELECT origin_x_ft, origin_y_ft, width_ft, length_ft, height_ft, absolute_lat INTO r
    FROM public.ottoq_site_structures
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'SIGN-OTTOYARD-FRONT';
  IF r.origin_x_ft <> 207.2244 OR r.origin_y_ft <> -3.2968 OR r.width_ft <> 37.6772 OR r.length_ft <> 1.8839
     OR r.height_ft <> 7.2215 OR r.absolute_lat <> 36.13969353 THEN
    RAISE EXCEPTION '0593 V1: the sign row reads %', to_jsonb(r);
  END IF;
  SELECT count(*) INTO v_changed
    FROM _0593_before b JOIN public.ottoq_site_structures s ON s.structure_id = b.structure_id
   WHERE md5(to_jsonb(s)::text) <> b.row_md5;
  IF v_changed <> 1 THEN RAISE EXCEPTION '0593 V2: % structure rows changed, expected 1', v_changed; END IF;
  RAISE NOTICE '0593: SIGN-OTTOYARD-FRONT now centred at x % ft, its north face % ft south of the fence line',
    round((r.origin_x_ft + r.width_ft / 2)::numeric, 2), round((-(r.origin_y_ft + r.length_ft))::numeric, 2);
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0593_the_entrance_sign_stands_outside_the_fence_where_the_twin_draws_it', false, false,
  'Twin depot only. SIGN-OTTOYARD-FRONT moves to the layout seed''s row, derived from the renderer''s '
  'structurePlan.SIGN_WALL: outside the south fence on the frontage between the gates (was 60 ft wide, 3 ft inside the '
  'fence, across the front staging row; Chase 2026-10-01). No decision, certified atom or fingerprint reads a sign.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
