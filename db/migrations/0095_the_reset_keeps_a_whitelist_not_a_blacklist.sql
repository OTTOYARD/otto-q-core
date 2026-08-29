-- migration-version: 20260829230000
-- migration-name:    the_reset_keeps_a_whitelist_not_a_blacklist
-- 0095 -- third and final round of the world-bleed hunt (0093 -> 0094 -> here), and the design
-- correction the first two rounds were converging on.
--
-- The rolled-back probe at 8 ticks (longer runs touch more paths than the 2-tick probe that
-- sized 0093) found the strip-list still leaking: config keys last_balance_charge_at (16
-- vehicles), deploy_gate (7), arm_fault_at/awaiting_disposition/reason (2/1/1),
-- flagged_issue_type (1) -- and vehicles.target_soc mutated 90 -> 100 (2). Key-by-key
-- blacklisting loses by construction: every new run-written key is a new leak.
--
-- INVERTED: the CRN reset now PROJECTS config onto a durable identity/condition whitelist
-- (oem, inlet, class, seeds, and the scenario-drawn condition scalars) and drops everything
-- else -- so any run-written key, present or future, is stripped automatically. A NEW identity
-- key needs a deliberate whitelist addition here; that is the maintenance burden chosen on
-- purpose. target_soc is pinned NULL (every consumer COALESCEs it with the default policy).
-- This applies ONLY to the cert-harness reset; production vehicle history is untouched, and
-- the finalizer keeps its narrow 0093 plan-residue strip.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_tick_invariance_reset_fleet   fa9fb7a5279368344229906102df9804  (post-0094)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  v_a_old text := E'         current_soc_source = ''estimated'',\n'
               || E'         -- 0093: strip run-plan residue too (covers a run that died un-finalized).\n'
               || E'         config = (COALESCE(v.config,''{}''::jsonb)\n'
               || E'                   - ''service_manifest'' - ''service_manifest_meta'' - ''charge_plan''\n'
               || E'                   - ''deferred_services'' - ''draining_item'')\n'
               || E'                  || jsonb_build_object(''cycles_since_wash'', 1)';
  v_a_new text := E'         current_soc_source = ''estimated'',\n'
               || E'         target_soc = NULL,\n'
               || E'         -- 0095: WHITELIST, not blacklist. Keep durable identity + scenario-drawn\n'
               || E'         -- condition; drop every run-written key, present or future, automatically.\n'
               || E'         -- Measured leaks that ended the blacklist: last_balance_charge_at,\n'
               || E'         -- deploy_gate, arm_fault_*, flagged_issue_type (8-tick probe).\n'
               || E'         config = (SELECT COALESCE(jsonb_object_agg(e.key, e.value), ''{}''::jsonb)\n'
               || E'                     FROM jsonb_each(COALESCE(v.config,''{}''::jsonb)) e\n'
               || E'                    WHERE e.key IN (''oem'',''inlet_type'',''vehicle_class_code'',\n'
               || E'                          ''seed_idx'',''seed_version'',''simulated'',''data_source'',\n'
               || E'                          ''lifetime_miles'',''last_calibration_at'',''battery_chemistry'',\n'
               || E'                          ''battery_onboarded_at'',''balance_interval_days'',\n'
               || E'                          ''nightly_soc_target'',''soil_rate'',''wash_cadence_cycles'',\n'
               || E'                          ''wash_group'',''pm_interval_km'',''calib_interval_h'',\n'
               || E'                          ''battery_soh_pct'',''consumption_scalar'',''charge_curve_scalar'',\n'
               || E'                          ''service_speed_scalar'',''scenario_interval_scale'',\n'
               || E'                          ''condition_drawn_run''))\n'
               || E'                  || jsonb_build_object(''cycles_since_wash'', 1)';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'fa9fb7a5279368344229906102df9804' THEN
    RAISE EXCEPTION '0095 abort: reset_fleet drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0095 abort: config anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('WHITELIST, not blacklist' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0095 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0095 applied: the CRN reset projects onto a whitelist; target_soc pinned.';
END
$do$;
