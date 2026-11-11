-- migration-version: PENDING
-- migration-name:    the_electrical_yard_is_on_the_site_record_and_the_fourth_solar_array_is_the_carports
--
-- 0813  **The electrical yard is on the site record, and the fourth solar array is the carports'.** (G536, G537)
--
-- Closes G536 and G537 (FINDINGS.md). Twin depot only (rule 8).
--
-- WHAT WAS WRONG.
--   G537: 0810 gave the depot seven transformers and a 13.8 kV switchgear as electrical data, and the site record
--         (ottoq_site_structures) still held one battery compound and no transformer at all. The picture drew one.
--   G536: ottoq_canopy_state generates from four 180 kW DC arrays. 0010 retired CANOPY-04 as a structure and left the
--         solar table untouched on purpose, so a quarter of the depot's solar came from an array that stood nowhere.
--
-- WHAT CHASE DECIDED (2026-11-11, in session): the fenced northwest corner and the strip behind the office are for
--   electrical and battery gear; no vehicle travels there. The canopy was left to this build: remove it, or place it
--   where it makes sense.
--
-- WHAT THIS DOES.
--   1. BESS-COMPOUND is resized to the yard the cockpit now draws (battery, MV-SWGR and TX-AUX inside its fence).
--   2. Seven 'transformer' structures, one per ottoq_power_nodes transformer, with the same codes: TX-AUX in the
--      battery yard, TX-A1..TX-C2 in a row behind the office.
--   3. canopy_4's 288 panels (180 kW DC) are recorded on the five perimeter solar carports, shared by roof area. The
--      five roofs are about 1,500 m2, 2.6 times one charging canopy's roof, and the 3D scene has always drawn panels
--      on them. ottoq_canopy_state is NOT changed: generation, and every energy number, is what it was.
--   4. The solar node on the one-line is retitled to say what it now is.
--
-- The geometry is ottoyarddepot-sim's unreal/layoutSeed.sql (generated from src/lib/sitePlan.ts), copied to 4 dp.
-- No engine decision reads any row written here: the readers of ottoq_site_structures are the fence check
-- (perimeter_wall only), the layout RPC for the cockpit, and comments. forces_recert = false.

BEGIN;

UPDATE public.ottoq_site_structures
   SET origin_x_ft = 6.2795, origin_y_ft = 254.3209, width_ft = 87.9134, length_ft = 53.3760,
       absolute_lat = 36.14047200, absolute_lng = -86.77262911,
       properties = properties || '{"holds":["NASH-BESS-01","TX-AUX","MV-SWGR"],"transformer_count":7,"one_line":"one_line_v1 (0810)"}'::jsonb
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'BESS-COMPOUND';

INSERT INTO public.ottoq_site_structures
  (depot_id, structure_code, structure_kind, title, origin_x_ft, origin_y_ft, width_ft, length_ft,
   height_ft, rotation_deg, status, absolute_lat, absolute_lng, properties, introduced_in)
SELECT '11111111-1111-1111-1111-111111111111', v.code, 'transformer',
       'Transformer ' || v.code || ' (2,500 kVA, 13.8 kV to 480 V)', v.x, v.y, 7.5354, 6.9075,
       6.5935, 0, 'active', v.lat, v.lng,
       jsonb_build_object('power_node', v.code, 'rated_kva', 2500, 'yard', v.yard, 'pad_mounted', true),
       '0813'
  FROM (VALUES
    ('TX-A1',  98.9026, 297.9636, 36.14052807, -86.77245073, 'TX-YARD'),
    ('TX-A2', 109.5778, 297.9636, 36.14052807, -86.77241442, 'TX-YARD'),
    ('TX-B1', 120.2530, 297.9636, 36.14052807, -86.77237810, 'TX-YARD'),
    ('TX-B2', 130.9281, 297.9636, 36.14052807, -86.77234179, 'TX-YARD'),
    ('TX-C1', 141.6033, 297.9636, 36.14052807, -86.77230547, 'TX-YARD'),
    ('TX-C2', 152.2785, 297.9636, 36.14052807, -86.77226916, 'TX-YARD'),
    ('TX-AUX', 12.7160, 288.5443, 36.14050219, -86.77274393, 'BESS-COMPOUND')
  ) AS v(code, x, y, lat, lng, yard)
ON CONFLICT (depot_id, structure_code) DO UPDATE
   SET origin_x_ft = EXCLUDED.origin_x_ft, origin_y_ft = EXCLUDED.origin_y_ft, width_ft = EXCLUDED.width_ft,
       length_ft = EXCLUDED.length_ft, height_ft = EXCLUDED.height_ft, status = 'active', title = EXCLUDED.title,
       absolute_lat = EXCLUDED.absolute_lat, absolute_lng = EXCLUDED.absolute_lng, properties = EXCLUDED.properties;

UPDATE public.ottoq_site_structures s
   SET properties = s.properties || jsonb_build_object('solar_array', 'canopy_4', 'panel_count', v.panels, 'solar_kw_dc', v.kw)
  FROM (VALUES ('CARPORT-W', 80, 50.00), ('CARPORT-E', 80, 50.00), ('CARPORT-S1', 41, 25.63),
               ('CARPORT-S2', 48, 30.00), ('CARPORT-S3', 39, 24.38)) AS v(code, panels, kw)
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.structure_code = v.code;

UPDATE public.ottoq_site_structures
   SET properties = properties || '{"array_now_on":"the five solar carports (0813): canopy_4 generates from their roofs"}'::jsonb
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'CANOPY-04';

UPDATE public.ottoq_power_nodes
   SET title = 'Canopy and carport solar (inverters)'
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND node_code = 'PV-CANOPIES';

DO $$
DECLARE v_tx int; v_nodes int; v_panels int; v_kw numeric; v_arrays int; v_inside int;
BEGIN
  SELECT count(*) INTO v_tx FROM public.ottoq_site_structures s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.structure_kind = 'transformer' AND s.status = 'active'
     AND EXISTS (SELECT 1 FROM public.ottoq_power_nodes n WHERE n.depot_id = s.depot_id AND n.node_code = s.structure_code AND n.kind = 'transformer');
  SELECT count(*) INTO v_nodes FROM public.ottoq_power_nodes
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND kind = 'transformer';
  IF v_tx <> 7 OR v_nodes <> 7 THEN RAISE EXCEPTION '0813: % transformer structures for % transformer nodes, want 7 and 7', v_tx, v_nodes; END IF;

  SELECT sum((properties->>'panel_count')::int), sum((properties->>'solar_kw_dc')::numeric) INTO v_panels, v_kw
    FROM public.ottoq_site_structures
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND properties->>'solar_array' = 'canopy_4';
  IF v_panels <> 288 OR abs(v_kw - 180) > 0.05 THEN RAISE EXCEPTION '0813: carports carry % panels and % kW, want 288 and 180', v_panels, v_kw; END IF;

  -- every array in the solar table now stands on an active structure: three canopies and the carports
  SELECT count(*) INTO v_arrays FROM public.ottoq_canopy_state WHERE depot_id = '11111111-1111-1111-1111-111111111111';
  IF v_arrays <> 4 THEN RAISE EXCEPTION '0813: % solar arrays, want 4 (generation must not change)', v_arrays; END IF;

  -- TX-AUX stands inside the battery yard's fence
  SELECT count(*) INTO v_inside FROM public.ottoq_site_structures t JOIN public.ottoq_site_structures b
      ON b.depot_id = t.depot_id AND b.structure_code = 'BESS-COMPOUND'
   WHERE t.depot_id = '11111111-1111-1111-1111-111111111111' AND t.structure_code = 'TX-AUX'
     AND t.origin_x_ft >= b.origin_x_ft AND t.origin_x_ft + t.width_ft <= b.origin_x_ft + b.width_ft
     AND t.origin_y_ft >= b.origin_y_ft AND t.origin_y_ft + t.length_ft <= b.origin_y_ft + b.length_ft;
  IF v_inside <> 1 THEN RAISE EXCEPTION '0813: TX-AUX is not inside the battery yard'; END IF;
END $$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0813_the_electrical_yard_is_on_the_site_record_and_the_fourth_solar_array_is_the_carports', false, false,
        'G536, G537. Site record only: BESS-COMPOUND resized, seven transformer structures, canopy_4''s panels recorded '
        'on the five carports, one node title. ottoq_canopy_state is unchanged and no decision reads these rows.',
        now());

COMMIT;
