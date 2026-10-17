-- migration-version: PENDING
-- migration-name:    the_site_power_gate_can_read_the_meter_instead_of_guessing
--
-- 0727  **The site power gate can read the meter instead of guessing.** With the dial `site_cap_gate_metered` at 1, the
--       0132 gate counts a charge under way at the power its charger last metered, not at a band of its state of
--       charge. Off by default: at 0 every run computes what it computed before. Research wing, rule 10; the second
--       half of G445.
--
-- ══ §1 WHY (db/checks/0451 §2 (d)) ════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_decide_tick defers a charge (`deferred_site_power_cap`) when committed EV kW plus the request would pass
--   ottoq_ev_charge_allowance_kw. "Committed" is an estimate: LEAST(connector kW, inlet kW or 250) times 0.85 under 55%
--   charge, 0.55 under 75%, else 0.30, over every car in a charging state; no meter is read. Reconstructed per tick from
--   run 8954bcf7's own OCPP 2.0.1 frames (dcfc10.otto_q.energy_off, 24 h, 283 ticks) the estimate read a median 1.50x the
--   metered power, p90 1.96x. At ten chargers the gate never binds, so it costs nothing; on a site with more chargers
--   than power (0724's and 0728's forty) it defers a car while a third of the limit is unused. Every active charge
--   meters its power every tick (twin.ottoq_sim_advance_charge_sessions writes ocpp_sessions.last_meter_value, the same
--   field the site meter sums, twin.ottoq_sim_compute_charger_load_kw), so the gate can read what the site reads.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The dial `site_cap_gate_metered`, catalogued 0..1, default 0, not agent-writable.
--   (b) public.ottoq_decide_tick, one anchored replacement: the estimate's SELECT becomes an IF on the dial. At 1, a car
--       in a charging state on a stall with an active session counts at that session's last metered power_kw; a car with
--       no metered session yet (the tick it plugs in) counts at the band estimate exactly as before. At 0 the original
--       SELECT runs unchanged. The allowance, the request, the comparison and every outcome are untouched.
--   Rule 9: the gate only decides WHEN a charge starts; reading the meter lets a car start sooner when there is room,
--   and never stops, slows or shortens a charge.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: ottoq_decide_tick is the body read on 2026-10-17 (prosrc md5 d6e9d26b...); the dial is
--   absent. Pre-image to ottoq_schema_snapshots as '0727_pre'. V1: THE DIAL-OFF PATH IS THE OLD PATH: the stored body with
--   the replacement undone is byte for byte the pre-image. V2: the metered branch reads the meter column the site meter
--   reads and keeps the estimate as its fallback. V3: the dial is catalogued 0..1 default 0 and no row sets it.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: at 0 (every canon cell) the decide path reads one dial a tick and
--   runs the original statement; V1 proves the rest of the body unchanged.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0727_pre' AND object_kind = 'function';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'site_cap_gate_metered';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0727_the_site_power_gate_can_read_the_meter_instead_of_guessing'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0727 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, the dial absent ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM 'd6e9d26b0d3d32328638c826eaeca084' THEN
    RAISE EXCEPTION '0727 P1: public.ottoq_decide_tick is not the body read on 2026-10-17 (md5 d6e9d26b)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'site_cap_gate_metered')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'site_cap_gate_metered') THEN
    RAISE EXCEPTION '0727 P1: site_cap_gate_metered already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0727_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('site_cap_gate_metered',
        '0727: what the 0132 site power gate counts as committed EV load. 1 = a charge under way at the power its charger '
        'last metered (ocpp_sessions.last_meter_value, the field the site meter sums), and the band estimate only for a '
        'car not yet metered. 0 = the band estimate for every car (LEAST(connector, inlet or 250) x 0.85/0.55/0.30 by '
        'state of charge), which read a median 1.50x the metered power (db/checks/0451 §2 (d)). Decides only when a charge '
        'starts; never stops, slows or shortens one.',
        0, 0, 1, 'public.ottoq_decide_tick', false);

CREATE TEMP TABLE _0727_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0727_patch VALUES
(1,
$old$  IF v_charge_cap_kw IS NOT NULL THEN
    SELECT COALESCE(SUM(LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END),0) INTO v_ev_committed_kw
      FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
     WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
  END IF;
$old$,
$new$  IF v_charge_cap_kw IS NOT NULL THEN
    IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'site_cap_gate_metered', 0), 0) >= 1 THEN
      /* 0727: a charge under way counts at the power its charger last metered (the field the site meter sums); a car
         not yet metered, at the band estimate below, as before. */
      SELECT COALESCE(SUM(COALESCE((cs.last_meter_value->>'power_kw')::numeric,
               LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END)),0) INTO v_ev_committed_kw
        FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
        LEFT JOIN ocpp_sessions cs ON cs.stall_id = st.id AND cs.status = 'active' AND cs.vehicle_id = vv.id
       WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
    ELSE
    SELECT COALESCE(SUM(LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END),0) INTO v_ev_committed_kw
      FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
     WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
    END IF;
  END IF;
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0727_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0727: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0727: ottoq_decide_tick is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the dial-off path is the old path ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0727_patch ORDER BY seq LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'd6e9d26b0d3d32328638c826eaeca084' THEN
    RAISE EXCEPTION '0727 V1: ottoq_decide_tick less the 0727 replacement is not the pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the metered branch reads the site meter's column and keeps the estimate as its fallback ──
DO $v2$
DECLARE v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;
  IF (length(v_src) - length(replace(v_src, 'INTO v_ev_committed_kw', ''))) / length('INTO v_ev_committed_kw') <> 2
     OR strpos(v_src, '(cs.last_meter_value->>''power_kw'')::numeric') = 0
     OR strpos((SELECT prosrc FROM pg_proc WHERE oid = 'twin.ottoq_sim_compute_charger_load_kw(uuid,timestamp with time zone)'::regprocedure),
               'last_meter_value->>''power_kw''') = 0 THEN
    RAISE EXCEPTION '0727 V2: the metered branch does not read the column the site meter sums';
  END IF;
END $v2$;

-- ── V3: the dial ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'site_cap_gate_metered'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'site_cap_gate_metered') THEN
    RAISE EXCEPTION '0727 V3: site_cap_gate_metered is not catalogued 0..1 default 0 with no row setting it';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0727_the_site_power_gate_can_read_the_meter_instead_of_guessing', false, false,
  'Dial site_cap_gate_metered (default 0); ottoq_decide_tick''s committed-EV estimate becomes an IF on it, the original '
  'statement in its ELSE. At 1 a charge under way counts at its last metered power. V1 proves the body less the '
  'replacement is the pre-image, so every run at 0 decides what it decided before.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
