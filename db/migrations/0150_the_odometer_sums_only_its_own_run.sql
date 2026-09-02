-- =====================================================================
-- 0150  The odometer sums only its own run
-- =====================================================================
-- Convicted in db/checks/0066 §2. twin.ottoq_sim_build_arrival_payload
-- computes the OEM arrival odometer as
--   config lifetime_miles + SUM(miles_driven) over ALL completed dispatches
-- for the vehicle, with no run predicate. Measured: 116 flagship
-- vehicles, avg 361.64 distinct runs summed into each, 380.1 foreign sim
-- miles apiece. Between the two arms of one pair, each arm completes
-- ~117 dispatches before the next arm's seed, so arm B's sum carries
-- arm A's mileage: 43 of 43 vehicles with an odometer_mi in the webhook
-- payload differed, arm B always higher.
--
-- The function has no run parameter, but it has p_dispatch_id, and the
-- dispatch row carries sim_run_id. Scope the sum to the run of the
-- dispatch being reported, with the zero-uuid COALESCE idiom (0020/0124)
-- so production (NULL run) sums only production history.
--
-- Classified forces_recert = FALSE, with the reason stated: the odometer
-- reaches only the webhook payload (ottoq_oem_webhook_log). 0066
-- measured it differing 43/43 on a pair whose h_cmd/h_dec/h_bkg/h_evt
-- all matched, so it demonstrably feeds no hashed stream and no
-- decision. A correctness fix on an unhashed outbound surface; it
-- cannot move canon.
-- =====================================================================

DO $pin$
DECLARE v_pin text; v_n int;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)), count(*) OVER () INTO v_pin, v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_build_arrival_payload';
  IF v_n <> 1 THEN RAISE EXCEPTION '0150 expected 1 arity, found %', v_n; END IF;
  IF v_pin IS DISTINCT FROM 'bf33897a2fedad9d7887dad2e8dfb321' THEN
    RAISE EXCEPTION '0150 pin mismatch twin.ottoq_sim_build_arrival_payload: %', v_pin;
  END IF;
END $pin$;

DO $anchor$
DECLARE v_raw text; v_src text; v_a text := $a$WHERE vehicle_id = p_vehicle.id AND status = 'completed'), 0);$a$; v_nr int; v_ns int;
BEGIN
  SELECT pg_get_functiondef(p.oid), regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g')
    INTO v_raw, v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_build_arrival_payload';
  v_nr := (length(v_raw)-length(replace(v_raw,v_a,'')))/length(v_a);
  v_ns := (length(v_src)-length(replace(v_src,v_a,'')))/length(v_a);
  IF v_nr <> 1 OR v_ns <> 1 THEN RAISE EXCEPTION '0150 anchor expected once, raw=% stripped=%', v_nr, v_ns; END IF;
  IF position('sim_run_id' in v_src) <> 0 THEN RAISE EXCEPTION '0150 function already mentions sim_run_id - refusing to double-apply'; END IF;
END $anchor$;

-- Proof: the defect reproduces. Pick a flagship vehicle with completed
-- dispatches from more than one run; the unscoped sum must EXCEED the
-- sum scoped to any single one of its runs. Cannot pass vacuously: it
-- aborts if no such vehicle exists.
DO $proof$
DECLARE v_veh uuid; v_run uuid; v_all numeric; v_one numeric; v_runs int;
BEGIN
  SELECT d.vehicle_id, count(DISTINCT COALESCE(d.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid))
    INTO v_veh, v_runs
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id=d.vehicle_id
   WHERE d.status='completed' AND v.home_depot_id='11111111-1111-1111-1111-111111111111'
   GROUP BY d.vehicle_id HAVING count(DISTINCT COALESCE(d.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)) > 1
   ORDER BY 2 DESC LIMIT 1;
  IF v_veh IS NULL THEN RAISE EXCEPTION '0150 proof: no flagship vehicle has completed dispatches across >1 run'; END IF;
  SELECT sim_run_id INTO v_run FROM ottoq_vehicle_dispatches WHERE vehicle_id=v_veh AND status='completed' AND sim_run_id IS NOT NULL LIMIT 1;
  SELECT COALESCE(SUM(miles_driven),0) INTO v_all FROM ottoq_vehicle_dispatches WHERE vehicle_id=v_veh AND status='completed';
  SELECT COALESCE(SUM(miles_driven),0) INTO v_one FROM ottoq_vehicle_dispatches WHERE vehicle_id=v_veh AND status='completed' AND sim_run_id = v_run;
  IF NOT (v_all > v_one) THEN
    RAISE EXCEPTION '0150 proof failed: unscoped sum % is not greater than one-run sum % for vehicle % (% runs)', v_all, v_one, v_veh, v_runs;
  END IF;
END $proof$;

DO $edit$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_build_arrival_payload';
  v_def := replace(v_def,
    $a$WHERE vehicle_id = p_vehicle.id AND status = 'completed'), 0);$a$,
    $a$WHERE vehicle_id = p_vehicle.id AND status = 'completed'
                                AND COALESCE(sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                                  = COALESCE((SELECT d0.sim_run_id FROM ottoq_vehicle_dispatches d0
                                               WHERE d0.dispatch_id = p_dispatch_id),
                                             '00000000-0000-0000-0000-000000000000'::uuid)), 0);$a$);
  EXECUTE v_def;
END $edit$;

DO $post$
DECLARE v_src text; v_pin text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_build_arrival_payload';
  IF v_n <> 1 THEN RAISE EXCEPTION '0150 arity changed to %', v_n; END IF;
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g'), md5(pg_get_functiondef(p.oid))
    INTO v_src, v_pin FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_build_arrival_payload';
  IF v_pin = 'bf33897a2fedad9d7887dad2e8dfb321' THEN RAISE EXCEPTION '0150 body did not change'; END IF;
  IF position('WHERE d0.dispatch_id = p_dispatch_id' in v_src) = 0 THEN RAISE EXCEPTION '0150 run predicate missing'; END IF;
  IF position($a$status = 'completed'), 0);$a$ in v_src) <> 0 THEN RAISE EXCEPTION '0150 old unscoped sum survived'; END IF;
  RAISE NOTICE '0150 applied; new pin %', v_pin;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_odometer_sums_only_its_own_run', false,
        'Scopes the OEM arrival odometer sum to the dispatch''s own run. Reaches only the webhook payload (unhashed); measured in 0066 to differ 43/43 on a pair whose every hash matched, so it cannot move canon.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
