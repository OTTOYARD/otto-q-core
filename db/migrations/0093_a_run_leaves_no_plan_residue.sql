-- migration-version: 20260829220000
-- migration-name:    a_run_leaves_no_plan_residue
-- 0093 -- check 0046 bleed #1, measured to the key. A rolled-back probe (seeded reset ->
-- snapshot -> 2-tick run -> teardown -> same-seed reset -> snapshot -> column diff) showed
-- exactly what a run leaves on the shared world that neither the finalizer nor the seeded
-- reset restores:
--
--   vehicles.config keys: service_manifest (64 vehicles after 2 ticks), service_manifest_meta
--     (64), charge_plan (19), deferred_services (15), draining_item (3) -- run-generated PLAN
--     state stamped onto the fleet. The next run reads the previous run's plans: this is the
--     monotonic wash/soil/energy drift across the 0046 arms (wash_atoms 84->73->64).
--   vehicles.current_soc_source: oem_telemetry -> estimated (29) -- the twin's burn-model
--     label (0073), never restored.
--   stalls.reserved_at (71) -- the reset clears reserved_by and reservation_expires_at but
--     not the claim timestamp itself.
--   ottoq_ocpp_chargers: station_state (4), last_fault_code (4), station_state_changed_at (5)
--     -- sim-injected charger faults survive the teardown's reconcile.
--
-- config also carries durable identity (oem, inlet_type, vehicle_class_code, seeded condition
-- scalars) -- so no blanket wipe: the strip is exactly the five keys the probe proved bleed.
--
-- FOUR PATCHES + ONE NEW FUNCTION:
--   A. public.ottoq_sim_release_depot: the finalizer's existing config strip (svc_step,
--      service_ends_at) extends to the five plan keys -- a run that ends leaves no plan
--      residue on the fleet, for EVERY run, not just cert arms.
--   B. public.ottoq_tick_invariance_reset_fleet (the CRN reset): same strip (covers a run
--      that died un-finalized), plus current_soc_source := 'estimated'.
--   C. same function: stalls also clear reserved_at.
--   D. same function: depot chargers canonicalize (Available, no fault code, no fault clock).
--   E. NEW ottoq.ottoq_world_fingerprint(depot): stable md5 over the start-relevant world
--      (vehicles: soc/state/stall/soc_source/config; stalls: status/occupant/claims;
--      chargers: state/fault). twin.ottoq_sim_start_run stamps it into the run payload
--      BEFORE the cold-start prime -- so any two runs can prove, not assume, that they
--      started from the same world. Property (a) of the determinism claim becomes checkable
--      in one comparison.
--
-- Pre-image pins, read live 2026-08-29 (each anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_release_depot            b52fd398953feb84790775254a89eeb0  (post-0089)
--   public.ottoq_tick_invariance_reset_fleet  ae67c98bb00b994173d75af020d2dffd
--   twin.ottoq_sim_start_run                  31a02960bf8522a0f9dcab0d4e96cca4  (post-0092)

-- ---------- E (created first; the start_run patch references it) ----------
CREATE OR REPLACE FUNCTION ottoq.ottoq_world_fingerprint(p_depot uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- The start-relevant world, hashed. jsonb text output is key-sorted, so config::text is
  -- deterministic. Extend the column set only alongside the 0046 probe that justifies it.
  SELECT md5(
    COALESCE((SELECT string_agg(v.id::text||'|'||COALESCE(v.current_soc::text,'-')||'|'
                     ||v.current_state::text||'|'||COALESCE(v.current_stall_id::text,'-')||'|'
                     ||COALESCE(v.current_soc_source,'-')||'|'||COALESCE(v.config::text,'{}'),
                     E'\n' ORDER BY v.id)
                FROM public.vehicles v
               WHERE v.home_depot_id = p_depot AND v.category='autonomous'), '')
    || '#' ||
    COALESCE((SELECT string_agg(s.id::text||'|'||s.status||'|'
                     ||COALESCE(s.current_vehicle_id::text,'-')||'|'||COALESCE(s.reserved_by::text,'-')||'|'
                     ||COALESCE(s.reserved_at::text,'-')||'|'||COALESCE(s.reservation_expires_at::text,'-'),
                     E'\n' ORDER BY s.id)
                FROM public.stalls s WHERE s.depot_id = p_depot), '')
    || '#' ||
    COALESCE((SELECT string_agg(c.charger_id::text||'|'||COALESCE(c.station_state,'-')||'|'
                     ||COALESCE(c.last_fault_code,'-'), E'\n' ORDER BY c.charger_id)
                FROM public.ottoq_ocpp_chargers c
                JOIN public.stalls s ON s.ocpp_charger_id = c.charger_id
               WHERE s.depot_id = p_depot), '')
  )
$fn$;

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  v_a_old text := E'         config = (COALESCE(config,''{}''::jsonb) - ''svc_step'' - ''service_ends_at'')';
  v_a_new text := E'         -- 0093: a run that ends leaves no plan residue on the fleet. These five keys\n'
               || E'         -- are run-generated plan state (measured bleeding into the next run).\n'
               || E'         config = (COALESCE(config,''{}''::jsonb) - ''svc_step'' - ''service_ends_at''\n'
               || E'                   - ''service_manifest'' - ''service_manifest_meta'' - ''charge_plan''\n'
               || E'                   - ''deferred_services'' - ''draining_item'')';

  v_b_old text := E'         config = COALESCE(v.config,''{}''::jsonb) || jsonb_build_object(''cycles_since_wash'', 1)';
  v_b_new text := E'         current_soc_source = ''estimated'',\n'
               || E'         -- 0093: strip run-plan residue too (covers a run that died un-finalized).\n'
               || E'         config = (COALESCE(v.config,''{}''::jsonb)\n'
               || E'                   - ''service_manifest'' - ''service_manifest_meta'' - ''charge_plan''\n'
               || E'                   - ''deferred_services'' - ''draining_item'')\n'
               || E'                  || jsonb_build_object(''cycles_since_wash'', 1)';

  v_c_old text := E'                    reservation_expires_at = NULL, status = ''available''';
  v_c_new text := E'                    reserved_at = NULL,\n'
               || E'                    reservation_expires_at = NULL, status = ''available''';

  v_d_old text := E'   WHERE depot_id = p_depot_id AND status <> ''maintenance'';\n  RETURN v_n;';
  v_d_new text := E'   WHERE depot_id = p_depot_id AND status <> ''maintenance'';\n\n'
               || E'  -- 0093: sim-injected charger faults survive the teardown reconcile; a seeded\n'
               || E'  -- world reset canonicalizes them (measured: 4 chargers stuck non-Available).\n'
               || E'  UPDATE public.ottoq_ocpp_chargers c\n'
               || E'     SET station_state = ''Available'', last_fault_code = NULL,\n'
               || E'         station_state_changed_at = NULL\n'
               || E'   WHERE c.charger_id IN (SELECT s.ocpp_charger_id FROM public.stalls s\n'
               || E'                           WHERE s.depot_id = p_depot_id AND s.ocpp_charger_id IS NOT NULL)\n'
               || E'     AND (c.station_state IS DISTINCT FROM ''Available''\n'
               || E'          OR c.last_fault_code IS NOT NULL OR c.station_state_changed_at IS NOT NULL);\n'
               || E'  RETURN v_n;';

  v_e_old text := E'  PERFORM set_config(''ottoq.sim_run_id'', v_run_id::text, true);\n\n  -- COLD START.';
  v_e_new text := E'  PERFORM set_config(''ottoq.sim_run_id'', v_run_id::text, true);\n\n'
               || E'  -- 0093: fingerprint the PRE-run world (before the cold-start prime mutates it),\n'
               || E'  -- so any two runs can prove they started equal instead of assuming it.\n'
               || E'  BEGIN\n'
               || E'    UPDATE ottoq_sim_runs\n'
               || E'       SET payload = COALESCE(payload,''{}''::jsonb)\n'
               || E'           || jsonb_build_object(''world_fingerprint'',\n'
               || E'                ottoq.ottoq_world_fingerprint(v_scenario.depot_id))\n'
               || E'     WHERE sim_run_id = v_run_id;\n'
               || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world fingerprint failed: %'', SQLERRM;\n'
               || E'  END;\n\n'
               || E'  -- COLD START.';
BEGIN
  -- ---------- A: finalizer ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'b52fd398953feb84790775254a89eeb0' THEN
    RAISE EXCEPTION '0093 abort: release_depot drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0093 abort: finalizer strip anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_a_old, v_a_new);
  IF position('no plan residue' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0093 abort: patch A did not survive';
  END IF;

  -- ---------- B, C, D: the CRN reset ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'ae67c98bb00b994173d75af020d2dffd' THEN
    RAISE EXCEPTION '0093 abort: reset_fleet drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_b_old, ''))) / length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0093 abort: reset config anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_c_old, ''))) / length(v_c_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0093 abort: reset stalls anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_d_old, ''))) / length(v_d_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0093 abort: reset tail anchor found % times', v_cnt; END IF;
  EXECUTE replace(replace(replace(v_src, v_b_old, v_b_new), v_c_old, v_c_new), v_d_old, v_d_new);
  v_src := pg_get_functiondef(v_oid);
  IF position('current_soc_source = ''estimated''' in v_src) = 0
     OR position('reserved_at = NULL' in v_src) = 0
     OR position('canonicalizes' in v_src) = 0 THEN
    RAISE EXCEPTION '0093 abort: patches B/C/D did not all survive';
  END IF;

  -- ---------- E: start_run stamps the fingerprint ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_run';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '31a02960bf8522a0f9dcab0d4e96cca4' THEN
    RAISE EXCEPTION '0093 abort: sim_start_run drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_e_old, ''))) / length(v_e_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0093 abort: start-run anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_e_old, v_e_new);
  IF position('world_fingerprint' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0093 abort: patch E did not survive';
  END IF;

  RAISE NOTICE '0093 applied: no plan residue, canonical seeded world, fingerprinted starts.';
END
$do$;
