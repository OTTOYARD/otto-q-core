-- migration-version: PENDING
-- migration-name:    0840_each_canopy_board_is_on_the_one_line_and_is_measured_from_its_working_arms
--
-- 0840  **Each fast-charger canopy's board is on the one-line, under TX-AUX, and is measured every tick from the
--        OTTO-CLEAN ARMs at work on that canopy.**
--
-- WHY. The site record now places each fast-charger canopy's plant: a board under the canopy's south end, fed from
--   TX-AUX, that feeds the canopy's 10 OTTO-CLEAN ARMs and their vacuum producer (ottoyarddepot-sim PR #177, merged
--   2026-11-16: sitePlan.CANOPY_PLANT, src/lib/siteCanopy.ts). The engine's one-line (0810) has no such load: TX-AUX's
--   children are the battery, the building and the solar, so its power study never sees an arm or a producer.
--   Chase, 2026-11-16, on that follow-up: "Sure, keep building what you see necessary."
--
-- §1 WHAT WAS SO (read 2026-11-16, production).
--   TX-AUX: 2,500 kVA, sized for 1,750 kW connected (the battery's 1,500 and the building's 250). The design rule
--   (ottoq_power_one_line_design) and the live tree agree, both ways. Each canopy has 10 fast-charger posts, each with
--   an OTTO-CLEAN ARM over it. An arm's work is an atom on its car's visit: performed_by 'stall_cabin_robot', its
--   robot_stall_id, started_at and ends_at (done_at when done), in sim time.
--   Run 6f9a1b0e (busy_day, 763 ticks, 324 arm atoms), read with this file's own window: at most 8, 9 and 8 arms were
--   at work at once on canopies 01, 02 and 03, and 1.38 on average over the run. Counted by atom, canopy 01's peak reads
--   10: at that tick 2 of its stalls each had 2 arm atoms open, so a board counts arms (distinct stalls), not atoms.
--
-- §2 WHAT THIS DOES.
--   (a) kind 'canopy_board' on ottoq_power_nodes. The kind CHECK is widened in one statement: its one DROP is of that
--       constraint, replaced in the same statement by a wider one, so no row and no dependent is lost.
--   (b) The design rule gives one board per canopy with fast chargers, under TX-AUX: BOARD-A, BOARD-B and BOARD-C, each
--       rated for every arm at work at once (10 x (2.4 kW for the arm + 3 kW for the producer) = 54 kW), and counts them
--       in TX-AUX's connected load. TX-AUX's rating does not move: 1,912 kW x 1.25 / 0.97 = 2,464 kVA, under 2,500.
--   (c) public.ottoq_power_canopy_board_load(depot, run, clock), read-only: for each board, the arms at work at that
--       instant (an arm atom that started at or before it and is not yet done) and its load. An idle arm draws its
--       standby (0.1 kW, ASSUMPTION), and an arm at work its 2.4 kW and the producer's 3 kW for it.
--   (d) ottoq_power_capture reads each board as a leaf. So TX-AUX's flow and temperature, the service's reading and each
--       board's own study now carry the arms. The capture runs where it always ran; a board's arms are those of the
--       visits as they stand when the site meter is read.
--   Rules 9 and 14: no car's place, charge or service changes. Rule 10: it measures and recommends nothing. Rule 12: no
--   sweep, pair or dial; the checks are a replay of a finished run's arms and a probe that is rolled back. Rule 13: every
--   rating is at or above what is connected, and nothing reads the tree to gate a car.
--
-- §3 PRECONDITIONS AND CHECKS. P0 no certification in flight and no live run at the twin depot (between runs, as 0810).
--   P1 the 2 bodies this file replaces are 0810's (md5 of prosrc). P2 once.
--   V1 the 3 boards: one per canopy with fast chargers, under TX-AUX, arms = its posts, rated = arms x 5.4 kW.
--   V2 TX-AUX's rating is unchanged and at least 125% of everything connected under it.
--   V3 the design rule and the tree agree, both ways. V4 the world fingerprint is unchanged.
--   V5 a probe, rolled back: a capture with no run gives each board its standby, and TX-AUX the sum of its leaves.
--   V6 when run 6f9a1b0e's visits are still there, the board-load function sees its arms at work.
--
-- §4 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: the capture writes only its own 2 tables, which
--   no decision reads and no atom hashes (0810 §2), and the new function is read only by the capture.
--
-- ROLLBACK, in this order: EXECUTE the `definition`s in ottoq_schema_snapshots WHERE label = '0840_pre' (the capture and
--   the design rule); DELETE FROM public.ottoq_power_nodes WHERE kind = 'canopy_board'; set TX-AUX's title and
--   provenance from the restored design rule; restore the kind CHECK without 'canopy_board'; DROP FUNCTION
--   public.ottoq_power_canopy_board_load(uuid, uuid, timestamptz); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE
--   '0840_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0, P1, P2 ──────────────────────────────────────────────────────────────────────────────────────────────────────
DO $p0$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0840 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0840 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p
       WHERE p.oid = to_regprocedure('public.ottoq_power_capture(uuid,uuid,timestamptz,numeric,numeric,numeric)'))
     IS DISTINCT FROM '3ea79ddd37f41673d3f556e6c524bc92' THEN
    RAISE EXCEPTION '0840 P1: ottoq_power_capture is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_power_one_line_design(uuid)'))
     IS DISTINCT FROM 'e7f03b76c4d9fd3ebbfa671ad4a53218' THEN
    RAISE EXCEPTION '0840 P1: ottoq_power_one_line_design is not the body this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_power_canopy_board_load(uuid,uuid,timestamptz)') IS NOT NULL THEN
    RAISE EXCEPTION '0840 P2: already applied';
  END IF;
  CREATE TEMP TABLE _0840_before ON COMMIT DROP AS
    SELECT ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111') AS fp;
END $p0$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0840_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_power_capture(uuid,uuid,timestamptz,numeric,numeric,numeric)',
                    'public.ottoq_power_one_line_design(uuid)']) AS f;

-- ── (a) the kind ────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.ottoq_power_nodes
  DROP CONSTRAINT ottoq_power_nodes_kind_check,
  ADD CONSTRAINT ottoq_power_nodes_kind_check
    CHECK (kind IN ('utility_service', 'mv_switchgear', 'transformer', 'post', 'bess', 'solar', 'building', 'canopy_board'));

-- ── (c) a board's load at an instant ────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.ottoq_power_canopy_board_load(p_depot_id uuid, p_sim_run_id uuid, p_clock timestamptz)
RETURNS TABLE (node_code text, canopy_code text, arms integer, working integer, kw_ac numeric)
LANGUAGE sql STABLE SET search_path = '' AS $f$
  /* 0840: each canopy board's arms at work at p_clock (an arm atom that started at or before it and is not yet done,
     counted once a stall) and its load: an idle arm its standby, an arm at work its own draw and the producer's for it.
     The figures are the board's own (its provenance, set by ottoq_power_one_line_design). Read-only. */
  WITH at_work AS (
    SELECT s.canopy_code, count(DISTINCT s.id)::int AS n
      FROM public.ottoq_visit_needs vn
      CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) r
      JOIN public.stalls s ON s.id::text = r->>'robot_stall_id' AND s.depot_id = p_depot_id
     WHERE vn.depot_id = p_depot_id
       AND (vn.sim_run_id = p_sim_run_id OR (p_sim_run_id IS NULL AND vn.sim_run_id IS NULL))
       AND r->>'performed_by' = 'stall_cabin_robot' AND r->>'status' IN ('in_progress', 'done')
       AND (r->>'started_at')::timestamptz <= p_clock
       AND COALESCE(r->>'done_at', r->>'ends_at')::timestamptz > p_clock
     GROUP BY 1)
  SELECT n.node_code, n.canopy_code, a.arms, COALESCE(w.n, 0),
         round((a.arms - LEAST(COALESCE(w.n, 0), a.arms)) * a.standby + LEAST(COALESCE(w.n, 0), a.arms) * (a.arm + a.vac), 3)
    FROM public.ottoq_power_nodes n
    CROSS JOIN LATERAL (SELECT COALESCE((n.provenance->>'arms')::int, 0) AS arms,
                               COALESCE((n.provenance->>'standby_kw_per_arm')::numeric, 0) AS standby,
                               COALESCE((n.provenance->>'arm_kw')::numeric, 0) AS arm,
                               COALESCE((n.provenance->>'vacuum_kw_per_arm')::numeric, 0) AS vac) a
    LEFT JOIN at_work w ON w.canopy_code = n.canopy_code
   WHERE n.depot_id = p_depot_id AND n.kind = 'canopy_board'
$f$;
REVOKE ALL ON FUNCTION public.ottoq_power_canopy_board_load(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_power_canopy_board_load(uuid, uuid, timestamptz) TO service_role;
COMMENT ON FUNCTION public.ottoq_power_canopy_board_load(uuid, uuid, timestamptz) IS
  '0840: each canopy board''s OTTO-CLEAN ARMs at work at an instant and its load. Read only by ottoq_power_capture. '
  'It measures; no engine function reads it to decide.';

-- ── (b) the design rule, with the boards ────────────────────────────────────────────────────────────────────────────
-- 0810's rule, and one board per canopy with fast chargers under TX-AUX, counted in TX-AUX's connected load. Pure.
CREATE OR REPLACE FUNCTION public.ottoq_power_one_line_design(p_depot_id uuid)
RETURNS SETOF public.ottoq_power_nodes LANGUAGE plpgsql STABLE SET search_path = '' AS $f$
DECLARE
  c_eff  CONSTANT numeric := 0.94;   -- post, AC to DC at full load (G533's source)
  c_pf   CONSTANT numeric := 0.97;
  c_cont CONSTANT numeric := 1.25;   -- a charger is a continuous load: its supply is sized at 125% of it
  v_tx   record; v_post record; n public.ottoq_power_nodes; v_total_kva numeric := 0; v_aux_kw numeric;
  v_bess record; v_building_kw numeric := 250;   -- 0763 §1: the most the depot's snapshots have read is 228.2 kW
  v_solar_kw numeric;
  v_board record; v_boards_kw numeric := 0;
  c_arm_kw     CONSTANT numeric := 2.4;   -- 0840: an OTTO-CLEAN ARM's motors, all at once (cad/otto_cad/robots/clean_arm.py)
  c_vac_kw     CONSTANT numeric := 3.0;   -- 0840: the canopy's vacuum producer, per working arm (clean_arm.py, VAC)
  c_standby_kw CONSTANT numeric := 0.1;   -- 0840: an idle arm: its controller, drives and supplies (ASSUMPTION)
  c_board_pf   CONSTANT numeric := 0.9;   -- 0840: motors and a drive (ASSUMPTION, as the site record's siteCanopy.ts)
  v_typ jsonb := jsonb_build_object('ASSUMPTION', 'typical 65 C-rise, naturally cooled, liquid-filled unit; replace with the '
    'nameplate when a unit is chosen (R-22)', 'model', 'IEEE C57.91 as in DOI 10.1109/TPWRD.2020.2988921');
BEGIN
  FOR v_tx IN
    SELECT s.canopy_code, s.equipment_config->>'canopy_side' AS side,
           'TX-' || chr(64 + right(s.canopy_code, 2)::int) || CASE s.equipment_config->>'canopy_side' WHEN 'W' THEN '1' ELSE '2' END AS code,
           sum(c.max_kw) AS dc_kw, count(*) AS posts
      FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text = 'dcfc' AND c.decommissioned_at IS NULL
     GROUP BY 1, 2 ORDER BY 1, 2 DESC
  LOOP
    n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := v_tx.code; n.parent_code := 'MV-SWGR';
    n.kind := 'transformer'; n.canopy_code := v_tx.canopy_code; n.voltage_v := 480; n.power_factor := c_pf;
    n.rated_kva := public.ottoq_power_standard_kva(v_tx.dc_kw / c_eff / c_pf * c_cont);
    n.title := format('Transformer %s (%s, %s side, %s posts)', v_tx.code, v_tx.canopy_code, v_tx.side, v_tx.posts);
    n.top_oil_rise_rated_c := 55; n.hot_spot_rise_rated_c := 25; n.loss_ratio := 5; n.rated_loss_pct := 1.0;
    n.oil_tau_min := 180; n.winding_tau_min := 5; n.exp_n := 0.8; n.exp_m := 0.8;
    n.design_code := 'one_line_v1'; n.created_at := now();
    n.provenance := v_typ || jsonb_build_object('connected_dc_kw', v_tx.dc_kw,
      'connected_kva', round(v_tx.dc_kw / c_eff / c_pf, 1), 'sized_at', '125% of connected, next standard rating');
    v_total_kva := v_total_kva + n.rated_kva;
    RETURN NEXT n;
    FOR v_post IN
      SELECT c.charger_id, c.ocpp_identifier, c.max_kw, s.display_name
        FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.depot_id = p_depot_id AND s.stall_type::text = 'dcfc' AND c.decommissioned_at IS NULL
         AND s.canopy_code = v_tx.canopy_code AND s.equipment_config->>'canopy_side' = v_tx.side
       ORDER BY c.ocpp_identifier
    LOOP
      n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := v_post.ocpp_identifier;
      n.parent_code := v_tx.code; n.kind := 'post'; n.title := v_post.display_name; n.voltage_v := 480;
      n.rated_kw := v_post.max_kw; n.charger_id := v_post.charger_id; n.canopy_code := v_tx.canopy_code;
      n.efficiency := c_eff; n.power_factor := c_pf; n.design_code := 'one_line_v1'; n.created_at := now();
      n.provenance := jsonb_build_object('efficiency_and_power_factor',
        'ABB Terra HP, >= 94% at full load, >= 0.97 (reseller sheet, InCharge v1.5, read 2026-11-11); held constant at every load: ASSUMPTION');
      RETURN NEXT n;
    END LOOP;
  END LOOP;

  -- 0840: one board per canopy with fast chargers, under TX-AUX: an OTTO-CLEAN ARM over each post, and the canopy's
  -- vacuum producer. Its rating is everything under it at once: every arm working and the producer serving each.
  FOR v_board IN
    SELECT s.canopy_code, count(*)::int AS arms
      FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text = 'dcfc' AND c.decommissioned_at IS NULL AND s.canopy_code IS NOT NULL
     GROUP BY 1 ORDER BY 1
  LOOP
    n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id;
    n.node_code := 'BOARD-' || chr(64 + right(v_board.canopy_code, 2)::int); n.parent_code := 'TX-AUX';
    n.kind := 'canopy_board'; n.canopy_code := v_board.canopy_code; n.voltage_v := 480;
    n.rated_kw := v_board.arms * (c_arm_kw + c_vac_kw); n.power_factor := c_board_pf;
    n.title := format('Canopy %s board (%s clean arms and their vacuum producer)', chr(64 + right(v_board.canopy_code, 2)::int), v_board.arms);
    n.design_code := 'one_line_v1'; n.created_at := now();
    n.provenance := jsonb_build_object('arms', v_board.arms, 'arm_kw', c_arm_kw, 'vacuum_kw_per_arm', c_vac_kw,
      'standby_kw_per_arm', c_standby_kw,
      'ASSUMPTION', 'an arm''s 2.4 kW and the producer''s 3 kW a working arm are the clean arm CAD''s; the standby and the '
        || 'power factor are typical values; replace with the chosen units'' sheets',
      'site', 'ottoyarddepot-sim sitePlan.CANOPY_PLANT and src/lib/siteCanopy.ts (PR #177, 2026-11-16): the board stands '
        || 'under the canopy''s south end and is fed from TX-AUX');
    v_boards_kw := v_boards_kw + n.rated_kw;
    RETURN NEXT n;
  END LOOP;

  SELECT b.bess_id, b.bess_identifier, GREATEST(b.max_charge_kw, b.max_discharge_kw) AS kw INTO v_bess
    FROM public.ottoq_bess_units b WHERE b.depot_id = p_depot_id ORDER BY b.bess_identifier LIMIT 1;
  SELECT COALESCE(sum(nameplate_ac_kw), 0) INTO v_solar_kw FROM public.ottoq_canopy_state WHERE depot_id = p_depot_id;
  -- the most TX-AUX carries: the battery charging while the building runs and every clean arm works (0840)
  v_aux_kw := COALESCE(v_bess.kw, 0) + v_building_kw + v_boards_kw;
  n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := 'TX-AUX'; n.parent_code := 'MV-SWGR';
  n.kind := 'transformer'; n.voltage_v := 480; n.power_factor := c_pf;
  n.rated_kva := public.ottoq_power_standard_kva(v_aux_kw / c_pf * c_cont);
  n.title := 'Transformer TX-AUX (battery, building, canopy solar, canopy boards)';
  n.top_oil_rise_rated_c := 55; n.hot_spot_rise_rated_c := 25; n.loss_ratio := 5; n.rated_loss_pct := 1.0;
  n.oil_tau_min := 180; n.winding_tau_min := 5; n.exp_n := 0.8; n.exp_m := 0.8; n.design_code := 'one_line_v1'; n.created_at := now();
  n.provenance := v_typ || jsonb_build_object('connected_kw', v_aux_kw, 'sized_at', '125% of connected, next standard rating');
  v_total_kva := v_total_kva + n.rated_kva;
  RETURN NEXT n;
  IF v_bess.bess_id IS NOT NULL THEN
    n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := v_bess.bess_identifier; n.parent_code := 'TX-AUX';
    n.kind := 'bess'; n.title := 'Battery ' || v_bess.bess_identifier; n.voltage_v := 480; n.rated_kw := v_bess.kw;
    n.bess_id := v_bess.bess_id; n.power_factor := c_pf; n.design_code := 'one_line_v1'; n.created_at := now(); n.provenance := '{}';
    RETURN NEXT n;
  END IF;
  n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := 'BUILDING'; n.parent_code := 'TX-AUX';
  n.kind := 'building'; n.title := 'Office, service garage, wash building, lighting'; n.voltage_v := 480; n.rated_kw := v_building_kw;
  n.power_factor := c_pf; n.design_code := 'one_line_v1'; n.created_at := now();
  n.provenance := jsonb_build_object('rated_kw', '0763 §1: 250 kW allowed; the most read is 228.2 kW');
  RETURN NEXT n;
  IF v_solar_kw > 0 THEN
    n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := 'PV-CANOPIES'; n.parent_code := 'TX-AUX';
    n.kind := 'solar'; n.title := 'Canopy solar (inverters)'; n.voltage_v := 480; n.rated_kw := v_solar_kw;
    n.power_factor := c_pf; n.design_code := 'one_line_v1'; n.created_at := now(); n.provenance := '{}';
    RETURN NEXT n;
  END IF;

  n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := 'MV-SWGR'; n.parent_code := 'SERVICE';
  n.kind := 'mv_switchgear'; n.title := 'Primary switchgear (one feeder per transformer)'; n.voltage_v := 13800;
  n.rated_kva := v_total_kva; n.power_factor := c_pf; n.design_code := 'one_line_v1'; n.created_at := now(); n.provenance := '{}';
  RETURN NEXT n;
  n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := 'SERVICE'; n.parent_code := NULL;
  n.kind := 'utility_service'; n.title := 'Utility service, primary metered'; n.voltage_v := 13800;
  n.rated_kva := v_total_kva; n.power_factor := c_pf; n.design_code := 'one_line_v1'; n.created_at := now();
  n.provenance := jsonb_build_object('voltage', 'Nashville Electric Service lists 13,800 V (3-wire, 3-phase) as a standard '
    'primary voltage; https://nespower.com/builders-and-developers, read 2026-11-11');
  RETURN NEXT n;
END $f$;

INSERT INTO public.ottoq_power_nodes
SELECT * FROM public.ottoq_power_one_line_design('11111111-1111-1111-1111-111111111111') WHERE kind = 'canopy_board';

UPDATE public.ottoq_power_nodes t
   SET title = d.title, provenance = d.provenance
  FROM public.ottoq_power_one_line_design('11111111-1111-1111-1111-111111111111') d
 WHERE t.depot_id = '11111111-1111-1111-1111-111111111111' AND t.node_code = 'TX-AUX' AND d.node_code = 'TX-AUX';

-- ── (d) the capture, with the boards as leaves ──────────────────────────────────────────────────────────────────────
-- 0810's capture; each canopy board is a leaf, its load what ottoq_power_canopy_board_load gives at the instant.
CREATE OR REPLACE FUNCTION public.ottoq_power_capture(
  p_depot_id uuid, p_sim_run_id uuid, p_clock timestamptz,
  p_building_kw numeric, p_bess_output_kw numeric, p_solar_kw numeric)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
DECLARE
  v_run      uuid := p_sim_run_id;
  v_key      uuid;
  v_ambient  numeric;
  v_meta     record;
  v_tx       record;
  v_prev     record;
  v_dt_s     numeric;
  v_k        numeric;
  v_step     record;
  v_loss     numeric;
  v_top      numeric; v_hot numeric; v_faa numeric;
  v_bin      integer;
  v_svc_ac   numeric := 0; v_svc_dc numeric := 0; v_svc_loss numeric := 0;
  v_p30      numeric; v_rows integer := 0;
  v_first    timestamptz;
  v_leaves   jsonb;
  v_leaf     record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_power_nodes WHERE depot_id = p_depot_id) THEN RETURN 0; END IF;
  IF v_run IS NULL THEN v_run := public.ottoq_depot_running_run(p_depot_id); END IF;
  v_key := COALESCE(v_run, '00000000-0000-0000-0000-000000000000'::uuid);
  -- a second snapshot at one instant (a re-run tick) is measured once
  IF EXISTS (SELECT 1 FROM public.ottoq_power_node_study
              WHERE sim_run_id = v_key AND node_code = 'SERVICE' AND last_clock_at >= p_clock) THEN RETURN 0; END IF;

  SELECT ambient_temp_c INTO v_ambient FROM public.ottoq_weather_snapshots
   WHERE depot_id = p_depot_id AND sim_clock_at <= p_clock
     AND COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = v_key
   ORDER BY sim_clock_at DESC, ambient_temp_c DESC LIMIT 1;
  v_ambient := COALESCE(v_ambient, 22);
  SELECT scenario_code, random_seed INTO v_meta FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;

  -- every leaf's load at this instant. A post's DC power is its sessions' last meter reading, by the predicate the
  -- site meter itself uses (ottoq_sim_compute_charger_load_kw), so the posts sum to total_ev_charging_kw.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('node_code', n.node_code, 'parent_code', n.parent_code, 'kind', n.kind,
           'rated_kw', n.rated_kw, 'pf', n.power_factor,
           'kw_dc', CASE n.kind WHEN 'post' THEN COALESCE(p.kw, 0) END,
           'kw_ac', CASE n.kind
                      WHEN 'post'     THEN COALESCE(p.kw, 0) / n.efficiency
                      WHEN 'building' THEN COALESCE(p_building_kw, 0)
                      WHEN 'bess'     THEN -COALESCE(p_bess_output_kw, 0)   -- charging is load, discharging is supply
                      WHEN 'solar'    THEN -COALESCE(p_solar_kw, 0)
                      WHEN 'canopy_board' THEN COALESCE(b.kw_ac, 0)    -- 0840: its clean arms, at work and idle
                      ELSE 0
                    END) ORDER BY n.node_code), '[]'::jsonb)
    INTO v_leaves
    FROM public.ottoq_power_nodes n
    LEFT JOIN LATERAL (
      SELECT sum((cs.last_meter_value->>'power_kw')::numeric) AS kw
        FROM public.ocpp_sessions cs JOIN public.stalls s ON s.id = cs.stall_id
       WHERE n.kind = 'post' AND s.ocpp_charger_id = n.charger_id AND cs.depot_id = p_depot_id
         AND cs.status IN ('active'::public.ocpp_session_status, 'completed'::public.ocpp_session_status)
         AND cs.started_at <= p_clock AND (cs.ended_at IS NULL OR cs.ended_at >= p_clock)
         AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = v_key) p ON true
    LEFT JOIN public.ottoq_power_canopy_board_load(p_depot_id, v_run, p_clock) b ON b.node_code = n.node_code   -- 0840
   WHERE n.depot_id = p_depot_id AND n.kind IN ('post', 'building', 'bess', 'solar', 'canopy_board');

  SELECT first_clock_at, last_clock_at INTO v_prev FROM public.ottoq_power_node_study
   WHERE sim_run_id = v_key AND node_code = 'SERVICE';
  v_first := COALESCE(v_prev.first_clock_at, p_clock);
  v_dt_s  := CASE WHEN v_prev.last_clock_at IS NULL THEN 0
                  ELSE LEAST(extract(epoch FROM p_clock - v_prev.last_clock_at), 21600) END;

  -- leaves: a study row each; a tick row for all but the posts (30 rows a tick would be most of the working table)
  FOR v_leaf IN
    SELECT * FROM jsonb_to_recordset(v_leaves)
      AS l(node_code text, parent_code text, kind text, rated_kw numeric, pf numeric, kw_dc numeric, kw_ac numeric)
  LOOP
    INSERT INTO public.ottoq_power_node_study AS st
      (sim_run_id, depot_id, node_code, kind, rated_kw, first_clock_at, last_clock_at, ticks, peak_kw_ac, peak_kva, peak_at,
       peak_load_pu, scenario_code, random_seed)
    VALUES (v_key, p_depot_id, v_leaf.node_code, v_leaf.kind, v_leaf.rated_kw, p_clock, p_clock, 1, abs(v_leaf.kw_ac),
            abs(v_leaf.kw_ac) / v_leaf.pf, p_clock,
            round(COALESCE(v_leaf.kw_dc, abs(v_leaf.kw_ac)) / v_leaf.rated_kw, 4), v_meta.scenario_code, v_meta.random_seed)
    ON CONFLICT (sim_run_id, node_code) DO UPDATE SET
      last_clock_at     = p_clock,
      ticks             = st.ticks + 1,
      seconds_observed  = st.seconds_observed + v_dt_s,
      energy_kwh_dc     = st.energy_kwh_dc + COALESCE(v_leaf.kw_dc, 0) * v_dt_s / 3600.0,
      energy_kwh_ac     = st.energy_kwh_ac + v_leaf.kw_ac * v_dt_s / 3600.0,   -- signed: supply counts against load
      seconds_energized = st.seconds_energized + CASE WHEN abs(v_leaf.kw_ac) > 0.5 THEN v_dt_s ELSE 0 END,
      peak_at           = CASE WHEN EXCLUDED.peak_kw_ac > st.peak_kw_ac THEN p_clock ELSE st.peak_at END,
      peak_load_pu      = GREATEST(st.peak_load_pu, EXCLUDED.peak_load_pu),
      peak_kva          = GREATEST(st.peak_kva, EXCLUDED.peak_kva),
      peak_kw_ac        = GREATEST(st.peak_kw_ac, EXCLUDED.peak_kw_ac);
    IF v_leaf.kind <> 'post' THEN
      INSERT INTO public.ottoq_power_node_ticks (sim_run_id, depot_id, node_code, sim_clock_at, dt_s, kw_ac, kva, load_pu, ambient_c)
      VALUES (v_run, p_depot_id, v_leaf.node_code, p_clock, v_dt_s, round(v_leaf.kw_ac, 2), round(abs(v_leaf.kw_ac) / v_leaf.pf, 2),
              round(abs(v_leaf.kw_ac) / v_leaf.rated_kw, 4), v_ambient);
    END IF;
  END LOOP;

  -- transformers: what flows through each is the net of its leaves; its heat follows the size of that flow
  FOR v_tx IN
    SELECT n.*, COALESCE(a.kw_ac, 0) AS net_ac, COALESCE(a.kw_dc, 0) AS sum_dc
      FROM public.ottoq_power_nodes n
      LEFT JOIN (SELECT l.parent_code, sum(l.kw_ac) AS kw_ac, sum(l.kw_dc) AS kw_dc
                   FROM jsonb_to_recordset(v_leaves) AS l(parent_code text, kw_dc numeric, kw_ac numeric) GROUP BY 1) a
        ON a.parent_code = n.node_code
     WHERE n.depot_id = p_depot_id AND n.kind = 'transformer' ORDER BY n.node_code
  LOOP
    v_k := abs(v_tx.net_ac) / v_tx.power_factor / v_tx.rated_kva;
    SELECT last_top_oil_rise, last_hot_spot_rise INTO v_prev FROM public.ottoq_power_node_study
     WHERE sim_run_id = v_key AND node_code = v_tx.node_code;
    SELECT * INTO v_step FROM public.ottoq_power_thermal_step(v_k, v_dt_s / 60.0, v_prev.last_top_oil_rise, v_prev.last_hot_spot_rise,
      v_tx.top_oil_rise_rated_c, v_tx.hot_spot_rise_rated_c, v_tx.loss_ratio, v_tx.oil_tau_min, v_tx.winding_tau_min, v_tx.exp_n, v_tx.exp_m);
    v_top := round(v_ambient + v_step.top_oil_rise, 2);
    v_hot := round(v_ambient + v_step.top_oil_rise + v_step.hot_spot_rise, 2);
    v_faa := public.ottoq_power_aging_factor(v_hot);
    -- losses at this load: the no-load part always, the load part with the square of the load
    v_loss := v_tx.rated_kva * v_tx.rated_loss_pct / 100.0 * (1 + v_tx.loss_ratio * v_k * v_k) / (1 + v_tx.loss_ratio);
    v_bin  := LEAST(floor(v_k * 10)::int, 10) + 1;
    v_svc_ac := v_svc_ac + v_tx.net_ac + v_loss; v_svc_dc := v_svc_dc + v_tx.sum_dc; v_svc_loss := v_svc_loss + v_loss;

    INSERT INTO public.ottoq_power_node_ticks (sim_run_id, depot_id, node_code, sim_clock_at, dt_s, kw_dc, kw_ac, kva, load_pu, loss_kw, ambient_c, top_oil_c, hot_spot_c, aging_factor)
    VALUES (v_run, p_depot_id, v_tx.node_code, p_clock, v_dt_s, v_tx.sum_dc, round(v_tx.net_ac, 2),
            round(abs(v_tx.net_ac) / v_tx.power_factor, 2), round(v_k, 4), round(v_loss, 3), v_ambient, v_top, v_hot, v_faa);
    v_rows := v_rows + 1;

    -- the full half hour with the highest mean load, once the run is half an hour old (G469: never a short window)
    v_p30 := NULL;
    IF p_clock - v_first >= interval '30 minutes' THEN
      SELECT sum(t.kva * t.dt_s) / NULLIF(sum(t.dt_s), 0) INTO v_p30 FROM public.ottoq_power_node_ticks t
       WHERE t.sim_run_id IS NOT DISTINCT FROM v_run AND t.node_code = v_tx.node_code
         AND t.sim_clock_at > p_clock - interval '30 minutes' AND t.sim_clock_at <= p_clock;
    END IF;

    INSERT INTO public.ottoq_power_node_study AS st
      (sim_run_id, depot_id, node_code, kind, rated_kva, first_clock_at, last_clock_at, ticks, peak_kw_ac, peak_kva, peak_at,
       peak_load_pu, last_top_oil_rise, last_hot_spot_rise, max_top_oil_c, max_hot_spot_c, max_hot_spot_at,
       scenario_code, random_seed)
    VALUES (v_key, p_depot_id, v_tx.node_code, 'transformer', v_tx.rated_kva, p_clock, p_clock, 1, abs(v_tx.net_ac),
            abs(v_tx.net_ac) / v_tx.power_factor, p_clock, round(v_k, 4), v_step.top_oil_rise, v_step.hot_spot_rise,
            v_top, v_hot, p_clock, v_meta.scenario_code, v_meta.random_seed)
    ON CONFLICT (sim_run_id, node_code) DO UPDATE SET
      last_clock_at      = p_clock,
      ticks              = st.ticks + 1,
      seconds_observed   = st.seconds_observed + v_dt_s,
      energy_kwh_dc      = st.energy_kwh_dc + v_tx.sum_dc * v_dt_s / 3600.0,
      energy_kwh_ac      = st.energy_kwh_ac + abs(v_tx.net_ac) * v_dt_s / 3600.0,
      loss_kwh           = st.loss_kwh + v_loss * v_dt_s / 3600.0,
      seconds_energized  = st.seconds_energized + CASE WHEN abs(v_tx.net_ac) > 0.5 THEN v_dt_s ELSE 0 END,
      load_seconds       = st.load_seconds[1:v_bin - 1] || (st.load_seconds[v_bin] + v_dt_s) || st.load_seconds[v_bin + 1:11],
      peak_at            = CASE WHEN EXCLUDED.peak_kva > st.peak_kva THEN p_clock ELSE st.peak_at END,
      peak_kw_ac         = GREATEST(st.peak_kw_ac, EXCLUDED.peak_kw_ac),
      peak_kva           = GREATEST(st.peak_kva, EXCLUDED.peak_kva),
      peak_load_pu       = GREATEST(st.peak_load_pu, EXCLUDED.peak_load_pu),
      peak_30min_at      = CASE WHEN v_p30 > COALESCE(st.peak_30min_kva, -1) THEN p_clock ELSE st.peak_30min_at END,
      peak_30min_kva     = GREATEST(st.peak_30min_kva, round(v_p30, 2)),
      last_top_oil_rise  = v_step.top_oil_rise,
      last_hot_spot_rise = v_step.hot_spot_rise,
      max_top_oil_c      = GREATEST(st.max_top_oil_c, v_top),
      max_hot_spot_at    = CASE WHEN v_hot > st.max_hot_spot_c THEN p_clock ELSE st.max_hot_spot_at END,
      max_hot_spot_c     = GREATEST(st.max_hot_spot_c, v_hot),
      aging_hours        = st.aging_hours + v_faa * v_dt_s / 3600.0;
  END LOOP;

  -- the service: what a primary meter would read (every transformer's flow and loss), beside the DC the cars took
  INSERT INTO public.ottoq_power_node_ticks (sim_run_id, depot_id, node_code, sim_clock_at, dt_s, kw_dc, kw_ac, kva, load_pu, loss_kw, ambient_c)
  SELECT v_run, p_depot_id, 'SERVICE', p_clock, v_dt_s, v_svc_dc, round(v_svc_ac, 2), round(abs(v_svc_ac) / n.power_factor, 2),
         round(abs(v_svc_ac) / n.power_factor / n.rated_kva, 4), round(v_svc_loss, 3), v_ambient
    FROM public.ottoq_power_nodes n WHERE n.depot_id = p_depot_id AND n.node_code = 'SERVICE';
  v_p30 := NULL;
  IF p_clock - v_first >= interval '30 minutes' THEN
    SELECT sum(t.kva * t.dt_s) / NULLIF(sum(t.dt_s), 0) INTO v_p30 FROM public.ottoq_power_node_ticks t
     WHERE t.sim_run_id IS NOT DISTINCT FROM v_run AND t.node_code = 'SERVICE'
       AND t.sim_clock_at > p_clock - interval '30 minutes' AND t.sim_clock_at <= p_clock;
  END IF;
  INSERT INTO public.ottoq_power_node_study AS st
    (sim_run_id, depot_id, node_code, kind, rated_kva, first_clock_at, last_clock_at, ticks, peak_kw_ac, peak_kva, peak_at,
     peak_load_pu, scenario_code, random_seed)
  SELECT v_key, p_depot_id, 'SERVICE', 'utility_service', n.rated_kva, p_clock, p_clock, 1, abs(v_svc_ac),
         abs(v_svc_ac) / n.power_factor, p_clock, round(abs(v_svc_ac) / n.power_factor / n.rated_kva, 4),
         v_meta.scenario_code, v_meta.random_seed
    FROM public.ottoq_power_nodes n WHERE n.depot_id = p_depot_id AND n.node_code = 'SERVICE'
  ON CONFLICT (sim_run_id, node_code) DO UPDATE SET
    last_clock_at     = p_clock,
    ticks             = st.ticks + 1,
    seconds_observed  = st.seconds_observed + v_dt_s,
    energy_kwh_dc     = st.energy_kwh_dc + v_svc_dc * v_dt_s / 3600.0,
    energy_kwh_ac     = st.energy_kwh_ac + GREATEST(v_svc_ac, 0) * v_dt_s / 3600.0,
    loss_kwh          = st.loss_kwh + v_svc_loss * v_dt_s / 3600.0,
    seconds_energized = st.seconds_energized + v_dt_s,
    peak_at           = CASE WHEN EXCLUDED.peak_kva > st.peak_kva THEN p_clock ELSE st.peak_at END,
    peak_kw_ac        = GREATEST(st.peak_kw_ac, EXCLUDED.peak_kw_ac),
    peak_kva          = GREATEST(st.peak_kva, EXCLUDED.peak_kva),
    peak_load_pu      = GREATEST(st.peak_load_pu, EXCLUDED.peak_load_pu),
    peak_30min_at     = CASE WHEN v_p30 > COALESCE(st.peak_30min_kva, -1) THEN p_clock ELSE st.peak_30min_at END,
    peak_30min_kva    = GREATEST(st.peak_30min_kva, round(v_p30, 2));
  RETURN v_rows + 1;
END $f$;

-- ── V1 the boards ───────────────────────────────────────────────────────────────────────────────────────────────────
DO $v1$
DECLARE v_bad text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_power_nodes WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND kind = 'canopy_board';
  IF v_n <> 3 THEN RAISE EXCEPTION '0840 V1: % canopy boards, not 3', v_n; END IF;
  SELECT string_agg(b.node_code, ', ') INTO v_bad
    FROM public.ottoq_power_nodes b
    LEFT JOIN (SELECT s.canopy_code, count(*)::int AS posts
                 FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'dcfc' AND c.decommissioned_at IS NULL
                GROUP BY 1) p ON p.canopy_code = b.canopy_code
   WHERE b.depot_id = '11111111-1111-1111-1111-111111111111' AND b.kind = 'canopy_board'
     AND NOT (b.parent_code = 'TX-AUX' AND (b.provenance->>'arms')::int = p.posts AND b.rated_kw = p.posts * 5.4
              AND b.node_code = 'BOARD-' || chr(64 + right(b.canopy_code, 2)::int));
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0840 V1: not as designed: %', v_bad; END IF;
END $v1$;

-- ── V2 TX-AUX ───────────────────────────────────────────────────────────────────────────────────────────────────────
DO $v2$
DECLARE v_kva numeric; v_ratio numeric; v_conn numeric;
BEGIN
  SELECT t.rated_kva, (t.provenance->>'connected_kw')::numeric INTO v_kva, v_conn
    FROM public.ottoq_power_nodes t WHERE t.depot_id = '11111111-1111-1111-1111-111111111111' AND t.node_code = 'TX-AUX';
  IF v_kva <> 2500 THEN RAISE EXCEPTION '0840 V2: TX-AUX reads % kVA, not the 2,500 it had', v_kva; END IF;
  SELECT v_kva / (sum(CASE l.kind WHEN 'solar' THEN 0 ELSE l.rated_kw END) / 0.97) INTO v_ratio
    FROM public.ottoq_power_nodes l WHERE l.depot_id = '11111111-1111-1111-1111-111111111111' AND l.parent_code = 'TX-AUX';
  IF v_ratio < 1.25 THEN RAISE EXCEPTION '0840 V2: TX-AUX carries only % of what is connected under it', round(v_ratio, 3); END IF;
  IF v_conn <> 1912 THEN RAISE EXCEPTION '0840 V2: TX-AUX''s connected load reads %, not 1,912 kW', v_conn; END IF;
END $v2$;

-- ── V3 the design rule and the tree agree, both ways ────────────────────────────────────────────────────────────────
DO $v3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM (
    (SELECT node_code, parent_code, kind, rated_kva, rated_kw FROM public.ottoq_power_one_line_design('11111111-1111-1111-1111-111111111111')
     EXCEPT SELECT node_code, parent_code, kind, rated_kva, rated_kw FROM public.ottoq_power_nodes WHERE depot_id = '11111111-1111-1111-1111-111111111111')
    UNION ALL
    (SELECT node_code, parent_code, kind, rated_kva, rated_kw FROM public.ottoq_power_nodes WHERE depot_id = '11111111-1111-1111-1111-111111111111'
     EXCEPT SELECT node_code, parent_code, kind, rated_kva, rated_kw FROM public.ottoq_power_one_line_design('11111111-1111-1111-1111-111111111111'))) d;
  IF v_n <> 0 THEN RAISE EXCEPTION '0840 V3: the design rule and the tree differ in % rows', v_n; END IF;
END $v3$;

-- ── V4 the world fingerprint ────────────────────────────────────────────────────────────────────────────────────────
DO $v4$
BEGIN
  IF (SELECT fp FROM _0840_before)::text IS DISTINCT FROM ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111')::text THEN
    RAISE EXCEPTION '0840 V4: the world fingerprint moved';
  END IF;
END $v4$;

-- ── V5 a capture with no run, rolled back ───────────────────────────────────────────────────────────────────────────
DO $v5$
DECLARE v_detail text; v_r jsonb; v_ret int;
BEGIN
  BEGIN
    SELECT public.ottoq_power_capture('11111111-1111-1111-1111-111111111111', NULL, '2099-01-01 00:00:00+00', 100, -200, 50) INTO v_ret;
    SELECT jsonb_build_object('returned', v_ret,
             'boards', (SELECT jsonb_object_agg(t.node_code, t.kw_ac) FROM public.ottoq_power_node_ticks t
                         WHERE t.sim_run_id IS NULL AND t.sim_clock_at = '2099-01-01 00:00:00+00' AND t.node_code LIKE 'BOARD-%'),
             'aux', (SELECT t.kw_ac FROM public.ottoq_power_node_ticks t
                      WHERE t.sim_run_id IS NULL AND t.sim_clock_at = '2099-01-01 00:00:00+00' AND t.node_code = 'TX-AUX'))
      INTO v_r;
    RAISE EXCEPTION USING ERRCODE = 'OQ840', MESSAGE = '0840 V5 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ840' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    v_r := v_detail::jsonb;
  END;
  IF (v_r->>'returned')::int <> 8 THEN RAISE EXCEPTION '0840 V5: the capture returned % rows, not 8: %', v_r->>'returned', v_r; END IF;
  IF (SELECT count(*) FROM jsonb_each_text(v_r->'boards') e WHERE e.value::numeric = 1.0) <> 3 THEN
    RAISE EXCEPTION '0840 V5: each idle board should read its 10 arms'' standby, 1 kW: %', v_r;
  END IF;
  IF (v_r->>'aux')::numeric <> 253 THEN   -- 100 building + 200 charging the battery - 50 solar + 3 for the boards
    RAISE EXCEPTION '0840 V5: TX-AUX should carry 253 kW: %', v_r;
  END IF;
END $v5$;

-- ── V6 a finished run's arms, seen by the board-load function ───────────────────────────────────────────────────────
DO $v6$
DECLARE v_visits int; v_most jsonb;
BEGIN
  SELECT count(*) INTO v_visits FROM public.ottoq_visit_needs WHERE sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3';
  IF v_visits = 0 THEN RAISE NOTICE '0840 V6: run 6f9a1b0e''s visits are gone; skipped'; RETURN; END IF;
  SELECT jsonb_object_agg(x.node_code, x.most) INTO v_most FROM (
    SELECT b.node_code, max(b.working) AS most
      FROM (SELECT DISTINCT s."timestamp" AS t FROM public.site_energy_snapshots s WHERE s.sim_run_id = '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3') sn
      CROSS JOIN LATERAL public.ottoq_power_canopy_board_load('11111111-1111-1111-1111-111111111111', '6f9a1b0e-6463-4edf-8a70-4c05eb4b25f3', sn.t) b
     GROUP BY 1) x;
  IF COALESCE((SELECT max(e.value::int) FROM jsonb_each_text(v_most) e), 0) < 1 THEN
    RAISE EXCEPTION '0840 V6: no arm at work on run 6f9a1b0e, which had 324 arm atoms: %', v_most;
  END IF;
  RAISE NOTICE '0840 V6: the most arms at work at once on run 6f9a1b0e: %', v_most;
END $v6$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0840_each_canopy_board_is_on_the_one_line_and_is_measured_from_its_working_arms', false, false,
        'Three canopy boards under TX-AUX, measured each tick from the clean arms at work; the capture and the design rule '
        || 'replaced (0840_pre). No decision reads them and no atom hashes their tables.', now());
COMMIT;
