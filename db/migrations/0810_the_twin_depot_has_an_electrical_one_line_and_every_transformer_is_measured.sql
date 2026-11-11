-- migration-version: 20261111151626
-- migration-name:    the_twin_depot_has_an_electrical_one_line_and_every_transformer_is_measured
--
-- 0810  **The twin depot has an electrical one-line: a utility service, seven transformers and thirty posts, each
--       measured on every tick, each transformer with its own temperature, and a door that takes a whole transformer's
--       posts down at once.** (G531-G534)
--
-- ══ §0 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Until this file the depot's electricity was one number. 0763 set it to what is installed (rule 13): 10,500 kW of
--   posts, 12,250 kW of service. Nothing said how that power reaches a post. A real depot of this size is fed at the
--   utility's primary voltage through several transformers, and three things follow from that which the twin could not
--   show:
--
--   (a) A transformer is what a utility sizes, prices and takes two years to deliver. Rule 13 says the depot's ceiling
--       is set later, "from what they drew". What a transformer can carry is set by its temperature, not by the sum of
--       the nameplates under it, so the measurement that sets a ceiling is each transformer's load and temperature
--       through a day. Nothing recorded either.
--   (b) Chargers do not only fail one at a time. A feeder or a transformer takes every post under it at once.
--       scenarios/zone_power_loss.json has said since C7: "ZONE-scoped loss (a subset of points) has no injector yet",
--       "provisional_gap: per-zone breaker model; today the cap is site-wide".
--   (c) The twin's site meter adds up the power delivered to the cars. A utility meter sits on the other side of the
--       chargers' conversion and the transformers, so it reads more. Nothing measured how much more.
--
-- ══ §1 WHAT WAS WRONG IN THE DEPOT'S OWN FACTS (read 2026-11-11, production and the lab agree) ══════════════════════
--
--   G531  depots.service_voltage is 480 for a service of 12,250 kW. At 480 V three-phase that is about 14,700 A. No
--         480 V service is built at that current; a depot this size takes service at the utility's primary voltage.
--         Nashville Electric Service lists 13,800 V (3-wire, 3-phase) as a standard primary voltage
--         (https://nespower.com/builders-and-developers, read 2026-11-11). No function reads the column (prosrc scan,
--         0 hits), so nothing acted on it. This file sets it to 13,800 and fills service_max_kva.
--   G532  Five standard chargers, NASH-L2-21..25, are in service with no stall. 0759 retired L2 11..15, 0763 retired
--         31..35 and turned 16..20 and 26..30 into fast chargers; 21..25 were in neither list. They take a heartbeat
--         every tick and read Available. No stall names them, so no car can be sent to one, and the one-line gives them
--         no node. Decommissioning them is 0811, its own file: the end-state fingerprint hashes every charger row at
--         the depot, so that change moves the end-state digest of every later arm, and this file must move none.
--   G533  The twin's site meter reads the power delivered to the cars (the sum of each session's DC power). The posts'
--         maker gives 94% efficiency or better at full load and a power factor of 0.97 or better (ABB Terra HP; the
--         only copy found is a reseller's sheet, InCharge v1.5,
--         https://inchargeus.com/wp-content/uploads/2026/07/InCharge_Specsheet_Terra-High-Power_v1.5.pdf, read
--         2026-11-11). At 94%, thirty posts at 350 kW draw 11,170 kW from the grid side, not 10,500, before any
--         transformer loss. This file does not change the site meter (bills, the battery's forecast and the energy atom
--         read it). It measures the grid-side figure beside it, per run, so the gap has a number (§2 (c)).
--   G534  The BESS compound's structure row says transformer_count 2, from the 2,500 kW depot. This file sets it to the
--         seven it declares.
--
-- ══ §2 WHAT THIS BUILDS ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) THE ONE-LINE, AS DATA. public.ottoq_power_nodes: a tree per depot. For the twin depot (rule 8, the only depot
--       seeded): SERVICE (13.8 kV, NES) -> MV-SWGR -> six charger transformers TX-A1, TX-A2, TX-B1, TX-B2, TX-C1, TX-C2
--       (one per canopy column, five posts each) and TX-AUX (the battery, the building, the canopies' solar) -> the
--       thirty posts. Every size comes from one rule, public.ottoq_power_one_line_design: the smallest standard
--       rating that carries 125% of everything connected under it, all at once. So nothing in it is below what the
--       hardware can draw (rule 13), and the tree restricts nothing: no engine function reads it to gate, slow or
--       refuse a car. It measures.
--   (b) THE MEASUREMENT. A trigger on site_energy_snapshots (the row the tick writes when it reads the site meter)
--       reads each post's power at that instant, rolls it up the tree, and steps each transformer's temperature. It
--       writes public.ottoq_power_node_ticks (run-scoped working data) and keeps one row per run and node in
--       public.ottoq_power_node_study (evidence: it survives the demo-run purge, as 0340's ledger does). The trigger
--       swallows its own errors, so it can never stop a tick. It reads no random draw and no wall clock. It writes no
--       event and no row any of the fourteen atoms hashes.
--   (c) THE TEMPERATURE. Each transformer's top-oil and winding hot-spot temperatures follow the loading guide's
--       model (IEEE C57.91 as set out in Dong et al., IEEE Trans. Power Delivery 2020, DOI 10.1109/TPWRD.2020.2988921,
--       author's copy https://arxiv.org/pdf/1909.06996, read 2026-11-11): the top-oil rise moves toward
--       rise_rated x ((K^2 R + 1)/(R + 1))^n and the hot-spot rise toward rise_rated x K^(2m), each on its own time
--       constant, n = 0.8 for a naturally cooled unit and m = 0.8; the insulation ages at
--       exp(15000/383 - 15000/(hot_spot + 273)) times its normal rate, 1.0 at 110 C. The air temperature is the twin's
--       own weather. The paper says the rated rises, the loss ratio and the time constants come from the maker's
--       nameplate. No unit has been bought, so the seven carry typical values, each marked ASSUMPTION in the node's
--       provenance, pending docs/research/requests/R-22.
--   (d) THE CEILING, FROM THE MEASUREMENT (rule 13). public.ottoq_power_rightsize(run) replays each transformer's
--       measured day at every standard rating and names the smallest whose hot spot never passes 110 C and whose
--       day ages the insulation no faster than normal. It is a reading for a person. It changes no node (rule 10).
--   (d2) WHAT THE DAY ASKED OF THE POSTS, AND N-1. public.ottoq_power_resilience(run), made at the run's end from its
--       charge sessions: for each charger transformer, its busiest moment and whether the posts under the other
--       transformers could have taken its cars; for the depot, the most any post delivered against its rating and how
--       many cars can take more than 150 kW at all (G535). A reading; it changes nothing.
--   (e) THE ZONE TRIP. public.ottoq_twin_trip_power_node(run, node, minutes, actor) takes down every post under a node
--       through the existing cockpit door, ottoq_twin_inject_charger_fault, one post at a time: the session ends, the
--       charger reads Faulted, the car is re-queued to finish (rule 9: a charger fault is one of the two reasons a
--       charge ends short, and the car is re-queued). The trip is recorded in public.ottoq_power_node_trips
--       (evidence) and each charger's fault payload names the node, so a reader can tell one common-cause event from
--       five independent faults.
--   (f) THE READ. public.ottoq_power_one_line(depot, run) returns the tree with each node's latest reading and its
--       run study, for the cockpit's Power tab.
--
--   Rule 9: nothing here ends, slows or reorders a charge except the trip door, which is a fault. Rule 10: the
--   right-size reader recommends and applies nothing. Rule 12: no sweep, pair or dial experiment; the check is one lab
--   day (db/checks/0481). Rule 13: every rating is at or above what is connected. Rule 14: no car's place changes.
--
--   forces_recert FALSE and forces_dial_restart FALSE: no existing function body is replaced; the new tables are read
--   by no decision and hashed by no atom; the trigger writes only its own two tables. The corrected facts (§1: the
--   service voltage and the compound's transformer count) are read by no engine function and hashed by no atom.
--   Measured in the lab, on production's engine through 0809: a 48-tick busy_day arm with this file and one without
--   it agree on all fourteen atoms (db/checks/0481 §1).
--
-- ══ §3 APPLY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Between runs. One transaction. Lab-tested on the 2026-11-04 export of production (db/checks/0481).

BEGIN;

-- ── P0  preconditions ───────────────────────────────────────────────────────────────────────────────────────────────
DO $p0$
BEGIN
  IF to_regclass('public.ottoq_power_nodes') IS NOT NULL THEN
    RAISE EXCEPTION '0810 P0: ottoq_power_nodes already exists';
  END IF;
  IF (SELECT count(*) FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text = 'dcfc'
         AND c.decommissioned_at IS NULL AND c.max_kw = 350) <> 30 THEN
    RAISE EXCEPTION '0810 P0: the twin depot is not thirty 350 kW posts; the one-line below was drawn for that depot';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0810 P0: a run is live at the twin depot; apply between runs';
  END IF;
  CREATE TEMP TABLE ottoq_0810_before ON COMMIT DROP AS
    SELECT ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111') AS fp;
END $p0$;

-- ── (a) the one-line ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.ottoq_power_nodes (
  node_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  depot_id              uuid NOT NULL REFERENCES public.depots(id) ON DELETE CASCADE,
  node_code             text NOT NULL,
  parent_code           text,
  kind                  text NOT NULL CHECK (kind IN ('utility_service','mv_switchgear','transformer','post','bess','solar','building')),
  title                 text NOT NULL,
  voltage_v             numeric,
  rated_kva             numeric CHECK (rated_kva IS NULL OR rated_kva > 0),
  rated_kw              numeric CHECK (rated_kw IS NULL OR rated_kw > 0),
  charger_id            uuid REFERENCES public.ottoq_ocpp_chargers(charger_id) ON DELETE SET NULL,
  bess_id               uuid REFERENCES public.ottoq_bess_units(bess_id) ON DELETE SET NULL,
  canopy_code           text,
  efficiency            numeric CHECK (efficiency IS NULL OR (efficiency > 0.5 AND efficiency <= 1)),
  power_factor          numeric NOT NULL DEFAULT 0.97 CHECK (power_factor > 0.5 AND power_factor <= 1),
  top_oil_rise_rated_c  numeric,
  hot_spot_rise_rated_c numeric,
  loss_ratio            numeric,
  rated_loss_pct        numeric,
  oil_tau_min           numeric,
  winding_tau_min       numeric,
  exp_n                 numeric,
  exp_m                 numeric,
  design_code           text NOT NULL DEFAULT 'one_line_v1',
  provenance            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (depot_id, node_code),
  CHECK (kind <> 'transformer' OR (rated_kva IS NOT NULL AND top_oil_rise_rated_c IS NOT NULL
         AND hot_spot_rise_rated_c IS NOT NULL AND loss_ratio IS NOT NULL AND rated_loss_pct IS NOT NULL
         AND oil_tau_min > 0 AND winding_tau_min > 0 AND exp_n IS NOT NULL AND exp_m IS NOT NULL)),
  CHECK (kind <> 'post' OR (charger_id IS NOT NULL AND rated_kw IS NOT NULL AND efficiency IS NOT NULL))
);
CREATE UNIQUE INDEX ottoq_power_nodes_one_node_per_charger ON public.ottoq_power_nodes (charger_id) WHERE charger_id IS NOT NULL;
CREATE INDEX ottoq_power_nodes_parent ON public.ottoq_power_nodes (depot_id, parent_code);
COMMENT ON TABLE public.ottoq_power_nodes IS
  '0810: a depot''s electrical one-line as a tree (utility service, switchgear, transformers, posts, battery, solar, '
  'building). Reference data, sized by ottoq_power_one_line_design at or above everything connected (rule 13). No engine '
  'function reads it to gate, slow or refuse a car: it is what ottoq_power_capture_tick measures against.';

-- The smallest standard three-phase rating, in kVA, that carries p_kva. ASSUMPTION (pending R-22): the list is the
-- common pad-mounted sizes; 480 V secondaries above 3,750 kVA are not offered here because their current is.
CREATE FUNCTION public.ottoq_power_standard_kva(p_kva numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = '' AS $f$
  SELECT min(s) FROM unnest(ARRAY[300, 500, 750, 1000, 1500, 2000, 2500, 3000, 3750]::numeric[]) s WHERE s >= p_kva
$f$;

-- One thermal step of a transformer (§2 (c)). Rises are over ambient (top oil) and over top oil (hot spot); p_k is
-- load over rating; p_dt_min the minutes since the last step. Exact for a load held constant over the step.
CREATE FUNCTION public.ottoq_power_thermal_step(
  p_k numeric, p_dt_min numeric, p_top_oil_rise numeric, p_hot_spot_rise numeric,
  p_top_oil_rise_rated numeric, p_hot_spot_rise_rated numeric, p_loss_ratio numeric,
  p_oil_tau_min numeric, p_winding_tau_min numeric, p_n numeric, p_m numeric,
  OUT top_oil_rise numeric, OUT hot_spot_rise numeric)
LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $f$
DECLARE
  v_k   double precision := GREATEST(COALESCE(p_k, 0), 0);
  v_tou double precision := p_top_oil_rise_rated * power((v_k * v_k * p_loss_ratio + 1) / (p_loss_ratio + 1), p_n::double precision);
  v_hsu double precision := p_hot_spot_rise_rated * power(v_k, 2 * p_m::double precision);
BEGIN
  IF p_top_oil_rise IS NULL OR p_hot_spot_rise IS NULL OR p_dt_min IS NULL OR p_dt_min <= 0 THEN
    -- the first reading of a run: the unit is taken to have sat at this load long enough to settle
    top_oil_rise := round(v_tou::numeric, 4); hot_spot_rise := round(v_hsu::numeric, 4); RETURN;
  END IF;
  top_oil_rise  := round((v_tou + (p_top_oil_rise  - v_tou) * exp(-LEAST(p_dt_min::double precision / p_oil_tau_min, 500)))::numeric, 4);
  hot_spot_rise := round((v_hsu + (p_hot_spot_rise - v_hsu) * exp(-LEAST(p_dt_min::double precision / p_winding_tau_min, 500)))::numeric, 4);
END $f$;

-- How fast the insulation ages at a hot-spot temperature, as a multiple of normal (1.0 at 110 C).
CREATE FUNCTION public.ottoq_power_aging_factor(p_hot_spot_c numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = '' AS $f$
  SELECT round(exp(15000.0 / 383.0 - 15000.0 / (p_hot_spot_c::double precision + 273.0))::numeric, 6)
$f$;

-- The design rule (§2 (a)): returns the node rows for a depot from its installed hardware. One transformer per canopy
-- column of posts; one for the battery, the building and the solar. Pure: it writes nothing.
CREATE FUNCTION public.ottoq_power_one_line_design(p_depot_id uuid)
RETURNS SETOF public.ottoq_power_nodes LANGUAGE plpgsql STABLE SET search_path = '' AS $f$
DECLARE
  c_eff  CONSTANT numeric := 0.94;   -- post, AC to DC at full load (G533's source)
  c_pf   CONSTANT numeric := 0.97;
  c_cont CONSTANT numeric := 1.25;   -- a charger is a continuous load: its supply is sized at 125% of it
  v_tx   record; v_post record; n public.ottoq_power_nodes; v_total_kva numeric := 0; v_aux_kw numeric;
  v_bess record; v_building_kw numeric := 250;   -- 0763 §1: the most the depot's snapshots have read is 228.2 kW
  v_solar_kw numeric;
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

  SELECT b.bess_id, b.bess_identifier, GREATEST(b.max_charge_kw, b.max_discharge_kw) AS kw INTO v_bess
    FROM public.ottoq_bess_units b WHERE b.depot_id = p_depot_id ORDER BY b.bess_identifier LIMIT 1;
  SELECT COALESCE(sum(nameplate_ac_kw), 0) INTO v_solar_kw FROM public.ottoq_canopy_state WHERE depot_id = p_depot_id;
  v_aux_kw := COALESCE(v_bess.kw, 0) + v_building_kw;   -- the most TX-AUX carries: the battery charging while the building runs
  n := NULL; n.node_id := gen_random_uuid(); n.depot_id := p_depot_id; n.node_code := 'TX-AUX'; n.parent_code := 'MV-SWGR';
  n.kind := 'transformer'; n.voltage_v := 480; n.power_factor := c_pf;
  n.rated_kva := public.ottoq_power_standard_kva(v_aux_kw / c_pf * c_cont);
  n.title := 'Transformer TX-AUX (battery, building, canopy solar)';
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
SELECT * FROM public.ottoq_power_one_line_design('11111111-1111-1111-1111-111111111111');

-- ── (b) the measurement ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.ottoq_power_node_ticks (
  tick_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sim_run_id   uuid REFERENCES public.ottoq_sim_runs(sim_run_id),
  depot_id     uuid NOT NULL,
  node_code    text NOT NULL,
  sim_clock_at timestamptz NOT NULL,
  dt_s         numeric NOT NULL,
  kw_dc        numeric,
  kw_ac        numeric NOT NULL,
  kva          numeric NOT NULL,
  load_pu      numeric,
  loss_kw      numeric,
  ambient_c    numeric,
  top_oil_c    numeric,
  hot_spot_c   numeric,
  aging_factor numeric
);
CREATE INDEX ottoq_power_node_ticks_run_node_clock ON public.ottoq_power_node_ticks (sim_run_id, node_code, sim_clock_at);
COMMENT ON TABLE public.ottoq_power_node_ticks IS
  '0810: one row per tick for the service and each transformer and non-post leaf: the load at the instant the site meter '
  'was read, and each transformer''s temperatures. Run-scoped working data (class engine): the demo-run purge deletes it. '
  'The run''s durable record is ottoq_power_node_study.';

CREATE TABLE public.ottoq_power_node_study (
  sim_run_id        uuid NOT NULL,          -- no FK, deliberately: evidence outlives its run (0340)
  depot_id          uuid NOT NULL,
  node_code         text NOT NULL,
  kind              text NOT NULL,
  rated_kva         numeric,
  rated_kw          numeric,
  first_clock_at    timestamptz NOT NULL,
  last_clock_at     timestamptz NOT NULL,
  ticks             integer NOT NULL DEFAULT 0,
  seconds_observed  numeric NOT NULL DEFAULT 0,
  energy_kwh_dc     numeric NOT NULL DEFAULT 0,
  energy_kwh_ac     numeric NOT NULL DEFAULT 0,
  loss_kwh          numeric NOT NULL DEFAULT 0,
  peak_kw_ac        numeric NOT NULL DEFAULT 0,
  peak_kva          numeric NOT NULL DEFAULT 0,
  peak_at           timestamptz,
  peak_30min_kva    numeric,
  peak_30min_at     timestamptz,
  peak_load_pu      numeric,
  seconds_energized numeric NOT NULL DEFAULT 0,
  load_seconds      numeric[] NOT NULL DEFAULT array_fill(0::numeric, ARRAY[11]),
  last_top_oil_rise numeric,
  last_hot_spot_rise numeric,
  max_top_oil_c     numeric,
  max_hot_spot_c    numeric,
  max_hot_spot_at   timestamptz,
  aging_hours       numeric NOT NULL DEFAULT 0,
  rightsize         jsonb,
  resilience        jsonb,
  scenario_code     text,
  random_seed       bigint,
  engine_hash       text,
  PRIMARY KEY (sim_run_id, node_code)
);
COMMENT ON TABLE public.ottoq_power_node_study IS
  '0810: one row per run and node: energy, peaks, the full half hour with the highest mean load, seconds in each tenth of '
  'rating (load_seconds[1] = under 10% .. [11] = at or over 100%), and for a transformer its hottest readings and the '
  'insulation life it used (aging_hours, against seconds_observed/3600 at normal aging). Evidence: no key to '
  'ottoq_sim_runs, so the demo-run purge leaves it. No number from it ships without its sim_run_id.';

CREATE TABLE public.ottoq_power_node_trips (
  trip_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id        uuid NOT NULL,          -- no FK, deliberately: evidence
  depot_id          uuid NOT NULL,
  node_code         text NOT NULL,
  tripped_at_sim    timestamptz NOT NULL,
  recovers_at_sim   timestamptz NOT NULL,
  repair_minutes    numeric NOT NULL,
  actor             text NOT NULL,
  posts_under_node  integer NOT NULL,
  posts_faulted     integer NOT NULL,
  sessions_stopped  integer NOT NULL,
  cars_on_posts     integer NOT NULL,
  detail            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ottoq_power_node_trips_run ON public.ottoq_power_node_trips (sim_run_id, tripped_at_sim);
COMMENT ON TABLE public.ottoq_power_node_trips IS
  '0810: every time ottoq_twin_trip_power_node took a node''s posts down: one common-cause event, where the chargers'' '
  'own records show one fault each. Evidence.';

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
 ('public', 'ottoq_power_node_ticks', 'sim_run_id', 'engine',
  '0810: per-tick load and transformer temperatures; run-scoped working data, must not outlive its run. Carries the FK check (b2) asks of an engine table, not CASCADE (check (c)).'),
 ('public', 'ottoq_power_node_study', 'sim_run_id', 'evidence',
  '0810: one row per run and node (energy, peaks, hottest readings, insulation life used). Evidence: the measurement rule 13 sets a ceiling from must survive the demo-run purge. No FK to ottoq_sim_runs, as 0340.'),
 ('public', 'ottoq_power_node_trips', 'sim_run_id', 'evidence',
  '0810: each zone trip, as one common-cause event. Evidence. No FK to ottoq_sim_runs, as 0340.');

ALTER TABLE public.ottoq_power_nodes      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_power_node_ticks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_power_node_study ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_power_node_trips ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_power_nodes_read      ON public.ottoq_power_nodes      FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY ottoq_power_node_ticks_read ON public.ottoq_power_node_ticks FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY ottoq_power_node_study_read ON public.ottoq_power_node_study FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY ottoq_power_node_trips_read ON public.ottoq_power_node_trips FOR SELECT TO anon, authenticated USING (true);
REVOKE ALL ON public.ottoq_power_nodes, public.ottoq_power_node_ticks, public.ottoq_power_node_study, public.ottoq_power_node_trips FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_power_nodes, public.ottoq_power_node_ticks, public.ottoq_power_node_study, public.ottoq_power_node_trips TO anon, authenticated, service_role;

-- The capture. Called by the trigger below with the snapshot the tick just wrote. Separate from the trigger function
-- so the lab and a check can call it directly.
CREATE FUNCTION public.ottoq_power_capture(
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
   WHERE n.depot_id = p_depot_id AND n.kind IN ('post', 'building', 'bess', 'solar');

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
REVOKE ALL ON FUNCTION public.ottoq_power_capture(uuid, uuid, timestamptz, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_power_capture(uuid, uuid, timestamptz, numeric, numeric, numeric) TO service_role;

CREATE FUNCTION public.ottoq_power_capture_tick()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
BEGIN
  -- Never stops a tick: whatever goes wrong here is a warning and the snapshot stands (as 0340's capture triggers).
  BEGIN
    PERFORM public.ottoq_power_capture(NEW.depot_id, NEW.sim_run_id, NEW."timestamp",
                                       NEW.building_load_kw, NEW.bess_output_kw, NEW.solar_generation_kw);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0810 power capture: % %', SQLSTATE, SQLERRM;
  END;
  RETURN NULL;
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_power_capture_tick() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_ottoq_power_capture_tick AFTER INSERT ON public.site_energy_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_power_capture_tick();

-- ── (d) the ceiling, read from the measurement ──────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.ottoq_power_rightsize(p_sim_run_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
DECLARE
  v_tx record; v_t record; v_size numeric; v_out jsonb := '[]'::jsonb; v_sizes jsonb;
  v_top numeric; v_hsr numeric; v_step record; v_hot numeric; v_max numeric; v_age numeric; v_secs numeric;
  v_pick numeric; v_n integer;
BEGIN
  FOR v_tx IN
    SELECT n.* FROM public.ottoq_power_nodes n
     WHERE n.kind = 'transformer'
       AND n.depot_id = (SELECT depot_id FROM public.ottoq_power_node_study WHERE sim_run_id = p_sim_run_id AND node_code = 'SERVICE')
     ORDER BY n.node_code
  LOOP
    v_sizes := '[]'::jsonb; v_pick := NULL;
    SELECT count(*) INTO v_n FROM public.ottoq_power_node_ticks WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code;
    IF v_n = 0 THEN CONTINUE; END IF;   -- the working rows are gone (purged); the stored reading stands
    FOR v_size IN SELECT s FROM unnest(ARRAY[300, 500, 750, 1000, 1500, 2000, 2500, 3000, 3750]::numeric[]) s ORDER BY s
    LOOP
      v_top := NULL; v_hsr := NULL; v_max := NULL; v_age := 0; v_secs := 0;
      FOR v_t IN SELECT kva, dt_s, ambient_c FROM public.ottoq_power_node_ticks
                  WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code ORDER BY sim_clock_at, tick_id
      LOOP
        SELECT * INTO v_step FROM public.ottoq_power_thermal_step(v_t.kva / v_size, v_t.dt_s / 60.0, v_top, v_hsr,
          v_tx.top_oil_rise_rated_c, v_tx.hot_spot_rise_rated_c, v_tx.loss_ratio, v_tx.oil_tau_min, v_tx.winding_tau_min, v_tx.exp_n, v_tx.exp_m);
        v_top := v_step.top_oil_rise; v_hsr := v_step.hot_spot_rise;
        v_hot := v_t.ambient_c + v_top + v_hsr;
        v_max := GREATEST(v_max, v_hot);
        v_age := v_age + public.ottoq_power_aging_factor(v_hot) * v_t.dt_s; v_secs := v_secs + v_t.dt_s;
      END LOOP;
      v_sizes := v_sizes || jsonb_build_object('kva', v_size, 'max_hot_spot_c', round(v_max, 1),
        'aging_vs_normal', round(v_age / NULLIF(v_secs, 0), 4));
      IF v_pick IS NULL AND v_max <= 110 AND v_age / NULLIF(v_secs, 0) <= 1 THEN v_pick := v_size; END IF;
    END LOOP;
    UPDATE public.ottoq_power_node_study SET rightsize = jsonb_build_object(
        'installed_kva', v_tx.rated_kva, 'smallest_kva_this_day_fits', v_pick,
        'rule', 'hot spot never over 110 C and the day ages the insulation no faster than normal',
        'by_size', v_sizes, 'is', 'a reading of one run, for a person; it changes no node (rules 10, 13)')
     WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code;
    v_out := v_out || jsonb_build_object('node', v_tx.node_code, 'installed_kva', v_tx.rated_kva, 'smallest_kva_this_day_fits', v_pick);
  END LOOP;
  RETURN jsonb_build_object('sim_run_id', p_sim_run_id, 'transformers', v_out);
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_power_rightsize(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_power_rightsize(uuid) TO service_role;

-- What the day asked of the posts, and whether it could have ridden through losing any one transformer. Read from the
-- run's own charge sessions (working rows), so it is made once, at the run's end, and kept on the study.
--   on a transformer's row: its busiest moment (the most cars charging under it at once), the posts free under the other
--     transformers at that moment, and the worst shortfall of the day (cars under it that no other post could have
--     taken, at any session start). Posts already down are not counted out, so it is the best case.
--   on the service's row: the most any post delivered, how many charges ever passed 150 kW, and how many of the depot's
--     cars can take more than 150 kW at all (vehicles.inlet_max_kw).
-- A reading for a person; it changes nothing (rules 10, 13).
CREATE FUNCTION public.ottoq_power_resilience(p_sim_run_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
DECLARE
  v_depot uuid; v_end timestamptz; v_tx record; v_busy record; v_short record; v_out jsonb := '[]'::jsonb; v_posts jsonb;
  v_n int;
BEGIN
  SELECT depot_id, last_clock_at INTO v_depot, v_end FROM public.ottoq_power_node_study
   WHERE sim_run_id = p_sim_run_id AND node_code = 'SERVICE';
  IF v_depot IS NULL THEN RETURN jsonb_build_object('sim_run_id', p_sim_run_id, 'measured', false); END IF;
  SELECT count(*) INTO v_n FROM public.ocpp_sessions WHERE sim_run_id = p_sim_run_id;
  IF v_n = 0 THEN RETURN jsonb_build_object('sim_run_id', p_sim_run_id, 'measured', false, 'why', 'no charge sessions left to read'); END IF;

  FOR v_tx IN
    SELECT n.node_code, (SELECT count(*) FROM public.ottoq_power_nodes p WHERE p.depot_id = n.depot_id AND p.kind = 'post' AND p.parent_code <> n.node_code) AS posts_else
      FROM public.ottoq_power_nodes n
     WHERE n.depot_id = v_depot AND n.kind = 'transformer'
       AND EXISTS (SELECT 1 FROM public.ottoq_power_nodes p WHERE p.depot_id = n.depot_id AND p.parent_code = n.node_code AND p.kind = 'post')
     ORDER BY n.node_code
  LOOP
    WITH s AS (
      SELECT o.started_at, COALESCE(o.ended_at, v_end) AS ended_at, (pn.parent_code = v_tx.node_code) AS here
        FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id
        JOIN public.ottoq_power_nodes pn ON pn.charger_id = st.ocpp_charger_id
       WHERE o.sim_run_id = p_sim_run_id),
    m AS (
      SELECT b.t,
             (SELECT count(*) FROM s WHERE s.here AND s.started_at <= b.t AND s.ended_at > b.t) AS cars_here,
             v_tx.posts_else - (SELECT count(*) FROM s WHERE NOT s.here AND s.started_at <= b.t AND s.ended_at > b.t) AS free_else
        FROM (SELECT DISTINCT started_at AS t FROM s WHERE here) b)
    SELECT * INTO v_busy FROM m ORDER BY cars_here DESC, free_else, t LIMIT 1;
    WITH s AS (
      SELECT o.started_at, COALESCE(o.ended_at, v_end) AS ended_at, (pn.parent_code = v_tx.node_code) AS here
        FROM public.ocpp_sessions o JOIN public.stalls st ON st.id = o.stall_id
        JOIN public.ottoq_power_nodes pn ON pn.charger_id = st.ocpp_charger_id
       WHERE o.sim_run_id = p_sim_run_id),
    m AS (
      SELECT b.t,
             (SELECT count(*) FROM s WHERE s.here AND s.started_at <= b.t AND s.ended_at > b.t) AS cars_here,
             v_tx.posts_else - (SELECT count(*) FROM s WHERE NOT s.here AND s.started_at <= b.t AND s.ended_at > b.t) AS free_else
        FROM (SELECT DISTINCT started_at AS t FROM s WHERE here) b)
    SELECT t, cars_here, free_else, GREATEST(cars_here - free_else, 0) AS short INTO v_short
      FROM m ORDER BY GREATEST(cars_here - free_else, 0) DESC, t LIMIT 1;
    UPDATE public.ottoq_power_node_study SET resilience = jsonb_build_object(
        'busiest_at', v_busy.t, 'cars_at_busiest', COALESCE(v_busy.cars_here, 0), 'free_posts_elsewhere_then', v_busy.free_else,
        'worst_shortfall_cars', COALESCE(v_short.short, 0), 'worst_shortfall_at', CASE WHEN v_short.short > 0 THEN v_short.t END,
        'posts_elsewhere', v_tx.posts_else,
        'is', 'a reading of one run: posts already down are not counted out, and a car moved is still a charge interrupted')
     WHERE sim_run_id = p_sim_run_id AND node_code = v_tx.node_code;
    v_out := v_out || jsonb_build_object('node', v_tx.node_code, 'cars_at_busiest', COALESCE(v_busy.cars_here, 0),
      'worst_shortfall_cars', COALESCE(v_short.short, 0));
  END LOOP;

  SELECT jsonb_build_object(
           'sessions', count(*), 'most_any_post_delivered_kw', max(o.peak_power_kw),
           'sessions_over_150_kw', count(*) FILTER (WHERE o.peak_power_kw > 150),
           'lowest_battery_at_plug_in_pct', min(o.soc_start),
           'cars', (SELECT count(*) FROM public.vehicles v WHERE v.home_depot_id = v_depot),
           'cars_that_can_take_over_150_kw', (SELECT count(*) FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.inlet_max_kw > 150),
           'cars_with_no_inlet_limit_on_file', (SELECT count(*) FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.inlet_max_kw IS NULL),
           'post_rating_kw', (SELECT max(rated_kw) FROM public.ottoq_power_nodes WHERE depot_id = v_depot AND kind = 'post'))
    INTO v_posts FROM public.ocpp_sessions o WHERE o.sim_run_id = p_sim_run_id;
  UPDATE public.ottoq_power_node_study SET resilience = v_posts WHERE sim_run_id = p_sim_run_id AND node_code = 'SERVICE';
  RETURN jsonb_build_object('sim_run_id', p_sim_run_id, 'measured', true, 'posts', v_posts, 'transformers', v_out);
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_power_resilience(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_power_resilience(uuid) TO service_role;

-- A run that stops is read once, while its working rows still exist; and its engine hash is stamped on its study.
CREATE FUNCTION public.ottoq_power_study_on_run_end()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_power_node_study WHERE sim_run_id = NEW.sim_run_id) THEN
      UPDATE public.ottoq_power_node_study SET engine_hash = public.ottoq_engine_hash()
       WHERE sim_run_id = NEW.sim_run_id AND engine_hash IS NULL;
      PERFORM public.ottoq_power_rightsize(NEW.sim_run_id);
      PERFORM public.ottoq_power_resilience(NEW.sim_run_id);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0810 power study at run end: % %', SQLSTATE, SQLERRM;
  END;
  RETURN NULL;
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_power_study_on_run_end() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_ottoq_power_study_on_run_end AFTER UPDATE OF status ON public.ottoq_sim_runs
  FOR EACH ROW WHEN (OLD.status = 'running' AND NEW.status IN ('completed', 'failed', 'aborted'))
  EXECUTE FUNCTION public.ottoq_power_study_on_run_end();

-- ── (e) the zone trip ───────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.ottoq_twin_trip_power_node(
  p_sim_run_id uuid, p_node_code text, p_repair_minutes numeric DEFAULT 60, p_actor text DEFAULT 'operator')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
DECLARE
  v_run record; v_node record; v_post record; v_res jsonb; v_trip uuid := gen_random_uuid();
  v_repair numeric := LEAST(GREATEST(COALESCE(p_repair_minutes, 60), 5), 480);
  v_under int := 0; v_faulted int := 0; v_stopped int := 0; v_cars int := 0; v_posts jsonb := '[]'::jsonb;
BEGIN
  SELECT sim_run_id, depot_id, status, sim_clock_current INTO v_run
    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id FOR UPDATE;
  IF v_run.sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found'); END IF;
  IF v_run.status <> 'running' THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_not_running', 'status', v_run.status); END IF;
  SELECT * INTO v_node FROM public.ottoq_power_nodes WHERE depot_id = v_run.depot_id AND node_code = p_node_code;
  IF v_node.node_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'node_not_at_this_depot'); END IF;
  IF v_node.kind NOT IN ('transformer', 'mv_switchgear', 'utility_service') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_a_node_with_posts_under_it', 'kind', v_node.kind);
  END IF;

  FOR v_post IN
    WITH RECURSIVE under AS (
      SELECT n.node_code, n.kind, n.charger_id FROM public.ottoq_power_nodes n
       WHERE n.depot_id = v_run.depot_id AND n.parent_code = p_node_code
      UNION ALL
      SELECT n.node_code, n.kind, n.charger_id FROM public.ottoq_power_nodes n JOIN under u ON n.parent_code = u.node_code
       WHERE n.depot_id = v_run.depot_id)
    SELECT u.node_code, u.charger_id, c.station_state FROM under u JOIN public.ottoq_ocpp_chargers c ON c.charger_id = u.charger_id
     WHERE u.kind = 'post' ORDER BY u.node_code
  LOOP
    v_under := v_under + 1;
    IF v_post.station_state = 'Faulted' THEN
      v_posts := v_posts || jsonb_build_object('post', v_post.node_code, 'was', 'already_faulted'); CONTINUE;
    END IF;
    -- the existing door: ends the session, marks the charger Faulted, re-queues the car to finish (rule 9)
    v_res := public.ottoq_twin_inject_charger_fault(p_sim_run_id, v_post.charger_id, v_repair, p_actor);
    IF COALESCE((v_res->>'ok')::boolean, false) THEN
      v_faulted := v_faulted + 1;
      v_stopped := v_stopped + COALESCE((v_res->>'sessions_stopped')::int, 0);
      v_cars    := v_cars + CASE WHEN COALESCE((v_res->>'had_vehicle')::boolean, false) THEN 1 ELSE 0 END;
      UPDATE public.ottoq_ocpp_chargers
         SET last_fault_payload = COALESCE(last_fault_payload, '{}'::jsonb)
               || jsonb_build_object('power_node', p_node_code, 'common_cause', true, 'trip_id', v_trip)
       WHERE charger_id = v_post.charger_id AND station_state = 'Faulted';
    END IF;
    v_posts := v_posts || jsonb_build_object('post', v_post.node_code, 'ok', v_res->'ok',
      'had_vehicle', v_res->'had_vehicle', 'sessions_stopped', v_res->'sessions_stopped', 'reason', v_res->'reason');
  END LOOP;

  INSERT INTO public.ottoq_power_node_trips (trip_id, sim_run_id, depot_id, node_code, tripped_at_sim, recovers_at_sim,
    repair_minutes, actor, posts_under_node, posts_faulted, sessions_stopped, cars_on_posts, detail)
  VALUES (v_trip, p_sim_run_id, v_run.depot_id, p_node_code, v_run.sim_clock_current,
    v_run.sim_clock_current + make_interval(secs => (v_repair * 60)::double precision),
    v_repair, COALESCE(p_actor, 'operator'), v_under, v_faulted, v_stopped, v_cars, jsonb_build_object('posts', v_posts));

  RETURN jsonb_build_object('ok', v_faulted > 0, 'trip_id', v_trip, 'node', p_node_code, 'posts_under_node', v_under,
    'posts_faulted', v_faulted, 'sessions_stopped', v_stopped, 'cars_on_posts', v_cars, 'repair_minutes', v_repair,
    'tripped_at_sim', v_run.sim_clock_current,
    'recovers_at_sim', v_run.sim_clock_current + make_interval(secs => (v_repair * 60)::double precision));
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_twin_trip_power_node(uuid, text, numeric, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_twin_trip_power_node(uuid, text, numeric, text) TO service_role;
COMMENT ON FUNCTION public.ottoq_twin_trip_power_node(uuid, text, numeric, text) IS
  '0810: takes down every post under a power node (a transformer, the switchgear or the service) through '
  'ottoq_twin_inject_charger_fault, one post at a time, and records one common-cause trip. Granted as that door is: '
  'service_role only.';

-- ── (f) the read ────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.ottoq_power_one_line(p_depot_id uuid, p_sim_run_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $f$
DECLARE
  v_run uuid := p_sim_run_id; v_clock timestamptz; v_status text; v_meter numeric; v_nodes jsonb; v_trips jsonb;
BEGIN
  IF v_run IS NULL THEN
    v_run := public.ottoq_depot_running_run(p_depot_id);
    IF v_run IS NULL THEN   -- no live run: the newest run with a study
      SELECT st.sim_run_id INTO v_run FROM public.ottoq_power_node_study st
       WHERE st.depot_id = p_depot_id AND st.node_code = 'SERVICE' ORDER BY st.last_clock_at DESC, st.sim_run_id LIMIT 1;
    END IF;
  END IF;
  SELECT status INTO v_status FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
  SELECT last_clock_at INTO v_clock FROM public.ottoq_power_node_study WHERE sim_run_id = v_run AND node_code = 'SERVICE';
  SELECT s.grid_import_kw - s.grid_export_kw INTO v_meter FROM public.site_energy_snapshots s
   WHERE s.depot_id = p_depot_id AND s.sim_run_id = v_run AND s."timestamp" = v_clock ORDER BY s.id LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'code', n.node_code, 'parent', n.parent_code, 'kind', n.kind, 'title', n.title, 'voltage_v', n.voltage_v,
      'rated_kva', n.rated_kva, 'rated_kw', n.rated_kw, 'canopy', n.canopy_code,
      'charger_state', c.station_state,
      'power_node_fault', CASE WHEN c.station_state = 'Faulted' THEN c.last_fault_payload->>'power_node' END,
      'now', CASE WHEN t.tick_id IS NOT NULL THEN jsonb_build_object('kw_dc', t.kw_dc, 'kw_ac', t.kw_ac, 'kva', t.kva,
               'load_pu', t.load_pu, 'loss_kw', t.loss_kw, 'ambient_c', t.ambient_c, 'top_oil_c', t.top_oil_c,
               'hot_spot_c', t.hot_spot_c, 'aging_factor', t.aging_factor)
                  WHEN n.kind = 'post' AND v_clock IS NOT NULL THEN jsonb_build_object('kw_dc', COALESCE(pp.kw, 0),
               'kw_ac', round(COALESCE(pp.kw, 0) / n.efficiency, 2), 'load_pu', round(COALESCE(pp.kw, 0) / n.rated_kw, 4)) END,
      'study', CASE WHEN st.sim_run_id IS NOT NULL THEN jsonb_build_object(
               'hours', round(st.seconds_observed / 3600.0, 2), 'energy_kwh_dc', round(st.energy_kwh_dc, 1),
               'energy_kwh_ac', round(st.energy_kwh_ac, 1), 'loss_kwh', round(st.loss_kwh, 1),
               'peak_kw_ac', round(st.peak_kw_ac, 1), 'peak_kva', round(st.peak_kva, 1), 'peak_at', st.peak_at,
               'peak_30min_kva', st.peak_30min_kva, 'peak_load_pu', st.peak_load_pu,
               'hours_energized', round(st.seconds_energized / 3600.0, 2), 'load_seconds', to_jsonb(st.load_seconds),
               'max_top_oil_c', st.max_top_oil_c, 'max_hot_spot_c', st.max_hot_spot_c, 'max_hot_spot_at', st.max_hot_spot_at,
               'aging_hours', round(st.aging_hours, 3), 'rightsize', st.rightsize, 'resilience', st.resilience) END)
      ORDER BY n.kind, n.node_code), '[]'::jsonb)
    INTO v_nodes
    FROM public.ottoq_power_nodes n
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = n.charger_id
    LEFT JOIN public.ottoq_power_node_study st ON st.sim_run_id = v_run AND st.node_code = n.node_code
    LEFT JOIN LATERAL (SELECT * FROM public.ottoq_power_node_ticks t
                        WHERE t.sim_run_id = v_run AND t.node_code = n.node_code AND t.sim_clock_at = v_clock
                        ORDER BY t.tick_id DESC LIMIT 1) t ON true
    LEFT JOIN LATERAL (   -- a post's power at the one-line's clock, by the capture's own predicate
      SELECT sum((cs.last_meter_value->>'power_kw')::numeric) AS kw
        FROM public.ocpp_sessions cs JOIN public.stalls s ON s.id = cs.stall_id
       WHERE n.kind = 'post' AND s.ocpp_charger_id = n.charger_id AND cs.depot_id = p_depot_id AND cs.sim_run_id = v_run
         AND cs.status IN ('active'::public.ocpp_session_status, 'completed'::public.ocpp_session_status)
         AND cs.started_at <= v_clock AND (cs.ended_at IS NULL OR cs.ended_at >= v_clock)) pp ON true
   WHERE n.depot_id = p_depot_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('trip_id', tr.trip_id, 'node', tr.node_code, 'tripped_at_sim', tr.tripped_at_sim,
           'recovers_at_sim', tr.recovers_at_sim, 'posts_faulted', tr.posts_faulted, 'sessions_stopped', tr.sessions_stopped,
           'cars_on_posts', tr.cars_on_posts, 'actor', tr.actor) ORDER BY tr.tripped_at_sim), '[]'::jsonb)
    INTO v_trips FROM public.ottoq_power_node_trips tr WHERE tr.sim_run_id = v_run;

  RETURN jsonb_build_object('depot_id', p_depot_id, 'design', 'one_line_v1', 'sim_run_id', v_run, 'run_status', v_status,
    'as_of_sim', v_clock, 'site_meter_kw', v_meter, 'nodes', v_nodes, 'trips', v_trips,
    'says', 'Ratings are what is installed, at or above everything connected (rule 13). Nothing here limits a car.');
END $f$;
REVOKE ALL ON FUNCTION public.ottoq_power_one_line(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_power_one_line(uuid, uuid) TO anon, authenticated, service_role;

-- ── the corrected facts (§1: G531, G534) ────────────────────────────────────────────────────────────────────────────────
UPDATE public.depots
   SET service_voltage = 13800,
       service_max_kva = (SELECT rated_kva FROM public.ottoq_power_nodes
                           WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND node_code = 'SERVICE'),
       service_provider = COALESCE(service_provider, 'Nashville Electric Service')
 WHERE id = '11111111-1111-1111-1111-111111111111';

UPDATE public.ottoq_site_structures
   SET properties = properties || jsonb_build_object('transformer_count', 7, 'one_line', 'one_line_v1 (0810)'),
       title = 'BESS + Transformer Compound'
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'BESS-COMPOUND';

-- ── V  verification ─────────────────────────────────────────────────────────────────────────────────────────────────
DO $v$
DECLARE v_n int; v_bad text; v record; v_fp_before text; r record;
BEGIN
  -- V1 the tree: 1 service, 1 switchgear, 7 transformers, 30 posts, battery, building, solar; one root; every parent exists
  SELECT count(*) FILTER (WHERE kind = 'utility_service') AS svc, count(*) FILTER (WHERE kind = 'transformer') AS tx,
         count(*) FILTER (WHERE kind = 'post') AS posts, count(*) FILTER (WHERE parent_code IS NULL) AS roots INTO v
    FROM public.ottoq_power_nodes WHERE depot_id = '11111111-1111-1111-1111-111111111111';
  IF (v.svc, v.tx, v.posts, v.roots) IS DISTINCT FROM (1::bigint, 7::bigint, 30::bigint, 1::bigint) THEN
    RAISE EXCEPTION '0810 V1: the one-line is not 1 service, 7 transformers, 30 posts, 1 root: %', v; END IF;
  SELECT string_agg(n.node_code, ',') INTO v_bad FROM public.ottoq_power_nodes n
   WHERE n.parent_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.ottoq_power_nodes p
                                                    WHERE p.depot_id = n.depot_id AND p.node_code = n.parent_code);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0810 V1: nodes with no parent row: %', v_bad; END IF;
  -- every post in service at a stall has exactly one node, five to a transformer
  SELECT count(*) INTO v_n FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND c.decommissioned_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_power_nodes n WHERE n.charger_id = c.charger_id);
  IF v_n <> 0 THEN RAISE EXCEPTION '0810 V1: % chargers at a stall have no node', v_n; END IF;
  SELECT string_agg(parent_code || ':' || n, ',') INTO v_bad
    FROM (SELECT parent_code, count(*) n FROM public.ottoq_power_nodes WHERE kind = 'post' GROUP BY 1) x WHERE n <> 5;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0810 V1: transformers without five posts: %', v_bad; END IF;

  -- V2 RULE 13: every transformer carries everything connected under it, all at once, with room; so does the service
  FOR r IN
    SELECT t.node_code, t.rated_kva,
           (SELECT COALESCE(sum(CASE l.kind WHEN 'post' THEN l.rated_kw / l.efficiency WHEN 'solar' THEN 0 ELSE l.rated_kw END), 0)
              FROM public.ottoq_power_nodes l WHERE l.depot_id = t.depot_id AND l.parent_code = t.node_code) / t.power_factor AS connected_kva
      FROM public.ottoq_power_nodes t WHERE t.kind = 'transformer'
  LOOP
    IF r.rated_kva < r.connected_kva * 1.25 THEN
      RAISE EXCEPTION '0810 V2 (rule 13): % is rated % kVA under 125%% of the % kVA connected', r.node_code, r.rated_kva, round(r.connected_kva, 1);
    END IF;
  END LOOP;
  IF (SELECT rated_kva FROM public.ottoq_power_nodes WHERE node_code = 'SERVICE' AND depot_id = '11111111-1111-1111-1111-111111111111')
     <> (SELECT sum(rated_kva) FROM public.ottoq_power_nodes WHERE kind = 'transformer' AND depot_id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0810 V2: the service is not the sum of its transformers'; END IF;

  -- V3 the physics, at its three fixed points: rated load settles at the rated rises; 110 C ages at 1.0; no load, no rise but the core's
  SELECT * INTO v FROM public.ottoq_power_thermal_step(1, 100000, 10, 3, 55, 25, 5, 180, 5, 0.8, 0.8);
  IF abs(v.top_oil_rise - 55) > 0.001 OR abs(v.hot_spot_rise - 25) > 0.001 THEN
    RAISE EXCEPTION '0810 V3: rated load does not settle at the rated rises: %', v; END IF;
  IF public.ottoq_power_aging_factor(110) <> 1 THEN RAISE EXCEPTION '0810 V3: aging at 110 C is not 1.0'; END IF;
  IF NOT (public.ottoq_power_aging_factor(117) BETWEEN 1.9 AND 2.2) THEN
    RAISE EXCEPTION '0810 V3: aging does not about double 7 C over the reference: %', public.ottoq_power_aging_factor(117); END IF;
  SELECT * INTO v FROM public.ottoq_power_thermal_step(0, 100000, 55, 25, 55, 25, 5, 180, 5, 0.8, 0.8);
  IF v.hot_spot_rise <> 0 OR abs(v.top_oil_rise - 55 * power(1.0 / 6, 0.8)) > 0.001 THEN
    RAISE EXCEPTION '0810 V3: an unloaded unit does not settle at its no-load rise: %', v; END IF;
  -- one oil time constant closes 63.2% of the gap
  SELECT * INTO v FROM public.ottoq_power_thermal_step(1, 180, 0, 25, 55, 25, 5, 180, 5, 0.8, 0.8);
  IF abs(v.top_oil_rise - 55 * (1 - exp(-1.0))) > 0.001 THEN RAISE EXCEPTION '0810 V3: one time constant is not 63.2%%: %', v; END IF;

  -- V4 the registry accepts the three tables (the purge calls this guard on every start)
  SELECT count(*) INTO v_n FROM public.ottoq_check_run_scope_registry() g
   WHERE g::text LIKE '%ottoq_power_node%';
  IF v_n <> 0 THEN RAISE EXCEPTION '0810 V4: the run-scope registry objects to a power table'; END IF;

  -- V5 the corrected facts
  IF (SELECT service_voltage FROM public.depots WHERE id = '11111111-1111-1111-1111-111111111111') <> 13800 THEN
    RAISE EXCEPTION '0810 V5: service voltage'; END IF;

  -- V6 the world the certification hashes still counts thirty chargers
  IF ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111')
     IS DISTINCT FROM (SELECT fp FROM ottoq_0810_before) THEN
    RAISE EXCEPTION '0810 V6: the world fingerprint moved: % -> %', (SELECT fp FROM ottoq_0810_before),
      ottoq.ottoq_world_fingerprint_sections('11111111-1111-1111-1111-111111111111'); END IF;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0810_the_twin_depot_has_an_electrical_one_line_and_every_transformer_is_measured', false, false,
        'G531-G534. Adds the depot''s electrical one-line as data (ottoq_power_nodes), a capture trigger on '
        'site_energy_snapshots that writes only ottoq_power_node_ticks (engine) and ottoq_power_node_study (evidence), a '
        'right-size reader, and a zone-trip door over ottoq_twin_inject_charger_fault. No existing function body is '
        'replaced; no decision reads the new tables; no atom hashes them; the capture reads no random draw and no wall '
        'clock. Corrects service_voltage (read by nothing) and the compound''s transformer count. Lab: fourteen of '
        'fourteen atoms equal with and without it (db/checks/0481).',
        now());

COMMIT;

-- APPLIED 2026-11-11: 2026-11-11 15:16:26 UTC (9:16 AM CT), ledger 20261111151626, by Claude Code through the Management API's migrations endpoint on Chase's
--   instruction of 9:15 AM CT ("Apply 0810 and 0811 to the otto-q-core production database, deploy otto-twin-control, and
--   start demo runs at the twin depot as needed"). The stored statement's md5 equals this file's as committed before this
--   header and footer changed (1986d5e6f3fbe9b6b6aa91807fdef032).
