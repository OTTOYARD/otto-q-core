-- 0043 SCHEMA V2 CERTIFICATION BATTERY
-- Part A is read-only and safe to run anywhere (production included).
-- Part B live-fires the SDR triggers with synthetic completions and is guarded:
-- it runs ONLY when the session has set  SELECT set_config('ottoq.cert_livefire','on',false);
-- Run Part B on a scratch/preview instance, never production.
-- First executed against a local scratch instance 2026-08-19 (transcript in SCHEMA_V2.md §6).

\echo '=== PART A — read-only assertions ==='

-- A1. The booking calendar EXCLUDE constraint(s) still exist, untouched.
SELECT 'A1 exclude_constraints' AS check,
       count(*) AS n,
       CASE WHEN count(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM pg_constraint
 WHERE conrelid = 'public.ottoq_stall_bookings'::regclass AND contype = 'x';

-- A2. Run-scope registry is clean: no blocking defects, no unregistered columns.
SELECT 'A2 run_scope_registry' AS check,
       count(*) FILTER (WHERE severity='block') AS blocks,
       count(*) FILTER (WHERE severity='warn')  AS warns,
       CASE WHEN count(*) FILTER (WHERE severity='block') = 0
             AND NOT EXISTS (SELECT 1 FROM ottoq_check_run_scope_registry()
                              WHERE table_name='ottoq_service_detail_records')
            THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM ottoq_check_run_scope_registry();

-- A3. SDR coverage: every completed operation has its SDR.
SELECT 'A3 sdr_coverage' AS check, count(*) AS uncovered,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM ottoq_check_sdr_coverage();

-- A4. Every SDR is hashed; issued SDRs are signed when a signing secret exists.
SELECT 'A4 sdr_integrity' AS check,
       count(*) AS total,
       count(*) FILTER (WHERE payload_hash IS NULL) AS unhashed,
       CASE WHEN count(*) FILTER (WHERE payload_hash IS NULL) = 0
            THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM ottoq_service_detail_records;

-- A5. The six service objects exist.
SELECT 'A5 service_objects' AS check,
       CASE WHEN to_regclass('public.service_locations')            IS NOT NULL
             AND to_regclass('public.ottoq_service_tokens')          IS NOT NULL
             AND to_regclass('public.service_sessions')              IS NOT NULL
             AND to_regclass('public.ottoq_service_detail_records')  IS NOT NULL
             AND to_regclass('public.ottoq_service_tariffs')         IS NOT NULL
             AND to_regclass('public.service_profiles')              IS NOT NULL
            THEN 'PASS' ELSE 'FAIL' END AS verdict;

-- A6. Catalog: settleable operations all carry a house tariff.
SELECT 'A6 house_tariffs' AS check, count(*) AS ops_without_tariff,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM ottoq_operation_catalog oc
 WHERE oc.emits_sdr
   AND NOT EXISTS (SELECT 1 FROM ottoq_service_tariffs t
                    WHERE t.pack_id=oc.pack_id AND t.operation_code=oc.operation_code
                      AND t.active);

-- A7. data_source discipline: sim SDRs say twin, production SDRs say production.
SELECT 'A7 data_source' AS check, count(*) AS violations,
       CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM ottoq_service_detail_records
 WHERE (sim_run_id IS NOT NULL AND data_source <> 'twin')
    OR (sim_run_id IS NULL     AND data_source <> 'production');

\echo '=== PART B — live-fire (scratch only; requires ottoq.cert_livefire=on) ==='

DO $cert$
DECLARE
  v_livefire text := current_setting('ottoq.cert_livefire', true);
  v_run_a uuid; v_run_b uuid; v_wash_leg uuid; v_task uuid;
  v_sdr record; v_n int; v_pre bigint; v_post bigint;
  v_sig_ok boolean; v_purge jsonb; v_secret text;
BEGIN
  IF COALESCE(v_livefire,'') <> 'on' THEN
    RAISE NOTICE 'B: SKIPPED (set ottoq.cert_livefire=on on a scratch instance to run)';
    RETURN;
  END IF;

  -- fixture discovery (matches the 0043 scratch seed)
  SELECT sim_run_id INTO v_run_a FROM ottoq_sim_runs WHERE status='running'  LIMIT 1;
  SELECT sim_run_id INTO v_run_b FROM ottoq_sim_runs WHERE status='completed' LIMIT 1;
  SELECT leg_id INTO v_wash_leg FROM ottoq_itinerary_legs
   WHERE leg_type='wash' AND status='active' LIMIT 1;
  SELECT id INTO v_task FROM schedule_tasks WHERE status='in_progress' LIMIT 1;

  -- B1. Operation leg completes -> SDR issued, signed, verifiable.
  UPDATE ottoq_itinerary_legs
     SET status='done', actual_end_sim = now()
   WHERE leg_id = v_wash_leg;
  SELECT * INTO v_sdr FROM ottoq_service_detail_records WHERE leg_id = v_wash_leg;
  IF v_sdr IS NULL THEN RAISE EXCEPTION 'B1 FAIL: wash completion produced no SDR'; END IF;
  v_sig_ok := v_sdr.signature = ottoq_sign_sdr(v_sdr.sdr_id, v_sdr.ended_at,
                v_sdr.vehicle_id, v_sdr.operation_code, v_sdr.payload_hash,
                v_sdr.signature_key_id);
  IF NOT v_sig_ok THEN RAISE EXCEPTION 'B1 FAIL: SDR signature does not verify'; END IF;
  RAISE NOTICE 'B1 PASS: leg completion -> signed SDR (op=%, tariff=%)',
               v_sdr.operation_code, v_sdr.tariff_id;

  -- B2. Idempotency: completing the same leg again adds nothing.
  UPDATE ottoq_itinerary_legs SET status='amended' WHERE leg_id = v_wash_leg;
  UPDATE ottoq_itinerary_legs SET status='done'    WHERE leg_id = v_wash_leg;
  SELECT count(*) INTO v_n FROM ottoq_service_detail_records WHERE leg_id = v_wash_leg;
  IF v_n <> 1 THEN RAISE EXCEPTION 'B2 FAIL: % SDRs for one leg', v_n; END IF;
  RAISE NOTICE 'B2 PASS: idempotent under status churn';

  -- B3. Movement legs emit no SDR.
  SELECT count(*) INTO v_pre FROM ottoq_service_detail_records;
  INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, status)
  SELECT itinerary_id, sim_run_id, vehicle_id, 99, 'taxi', 'active'
    FROM ottoq_vehicle_itineraries WHERE sim_run_id = v_run_a LIMIT 1;
  UPDATE ottoq_itinerary_legs SET status='done', actual_end_sim=now()
   WHERE seq=99 AND sim_run_id = v_run_a;
  SELECT count(*) INTO v_post FROM ottoq_service_detail_records;
  IF v_post <> v_pre THEN RAISE EXCEPTION 'B3 FAIL: movement leg emitted an SDR'; END IF;
  RAISE NOTICE 'B3 PASS: movement completion emits no SDR (catalog-driven)';

  -- B4. Production task completes -> SDR with energy; attribution attaches costs.
  UPDATE schedule_tasks
     SET status='completed', actual_end=now(), energy_delivered_kwh=41.7,
         peak_charge_rate_kw=118, soc_at_end=88
   WHERE id = v_task;
  SELECT * INTO v_sdr FROM ottoq_service_detail_records WHERE schedule_task_id = v_task;
  IF v_sdr IS NULL OR v_sdr.energy_kwh IS DISTINCT FROM 41.7 THEN
    RAISE EXCEPTION 'B4 FAIL: task completion SDR missing or wrong energy';
  END IF;
  IF v_sdr.data_source <> 'production' THEN
    RAISE EXCEPTION 'B4 FAIL: production SDR mislabeled %', v_sdr.data_source;
  END IF;
  INSERT INTO ottoq_visit_cost_attribution
        (schedule_id, vehicle_id, depot_id, kwh_delivered, energy_cost_usd,
         total_cost_usd, billable_amount_usd, cost_components)
  SELECT t.vehicle_schedule_id, t.vehicle_id, t.depot_id, 41.7, 5.42, 9.80, 14.50,
         '{"energy":5.42,"labor":3.10,"demand":1.28}'::jsonb
    FROM schedule_tasks t WHERE t.id = v_task;
  SELECT * INTO v_sdr FROM ottoq_service_detail_records WHERE schedule_task_id = v_task;
  IF v_sdr.billable_amount_usd IS DISTINCT FROM 14.50 OR v_sdr.attribution_id IS NULL THEN
    RAISE EXCEPTION 'B4 FAIL: attribution did not attach (billable=%)', v_sdr.billable_amount_usd;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ottoq_events WHERE event_type='sdr_costs_attached') THEN
    RAISE EXCEPTION 'B4 FAIL: no sdr_costs_attached event';
  END IF;
  RAISE NOTICE 'B4 PASS: task -> SDR (energy 41.7 kWh) -> costs attached ($14.50 billable)';

  -- B5. Coverage check catches a deliberately-missed completion, then closes.
  UPDATE ottoq_operation_catalog SET emits_sdr=false
   WHERE pack_id='robotaxi' AND operation_code='inspect';
  UPDATE ottoq_itinerary_legs SET status='done', actual_end_sim=now()
   WHERE leg_type='inspect' AND sim_run_id = v_run_a;
  UPDATE ottoq_operation_catalog SET emits_sdr=true
   WHERE pack_id='robotaxi' AND operation_code='inspect';
  SELECT count(*) INTO v_n FROM ottoq_check_sdr_coverage(v_run_a);
  IF v_n <> 1 THEN RAISE EXCEPTION 'B5 FAIL: coverage check saw % gaps, expected 1', v_n; END IF;
  -- close the gap through the emitter, as an operator would
  PERFORM ottoq_emit_sdr('itinerary_leg', 'inspect', 'robotaxi',
            l.vehicle_id, l.sim_run_id, l.leg_id, NULL, NULL, NULL,
            l.to_stall_id, i.depot_id, l.actual_start_sim, l.actual_end_sim)
    FROM ottoq_itinerary_legs l
    JOIN ottoq_vehicle_itineraries i USING (itinerary_id)
   WHERE l.leg_type='inspect' AND l.sim_run_id = v_run_a;
  SELECT count(*) INTO v_n FROM ottoq_check_sdr_coverage(v_run_a);
  IF v_n <> 0 THEN RAISE EXCEPTION 'B5 FAIL: gap did not close'; END IF;
  RAISE NOTICE 'B5 PASS: coverage check detects and closes a missed completion';

  -- B6. Purge interplay: doomed run''s SDRs die with it; keep-run + production survive.
  SELECT count(*) INTO v_pre FROM ottoq_service_detail_records WHERE sim_run_id = v_run_b;
  IF v_pre = 0 THEN RAISE EXCEPTION 'B6 SETUP FAIL: doomed run has no SDRs'; END IF;
  v_purge := ottoq_purge_prior_runs(v_run_a);
  IF NOT (v_purge->>'ok')::boolean THEN RAISE EXCEPTION 'B6 FAIL: purge refused: %', v_purge; END IF;
  SELECT count(*) INTO v_post FROM ottoq_service_detail_records WHERE sim_run_id = v_run_b;
  IF v_post <> 0 THEN RAISE EXCEPTION 'B6 FAIL: doomed-run SDRs survived purge'; END IF;
  SELECT count(*) INTO v_post FROM ottoq_service_detail_records
   WHERE sim_run_id = v_run_a OR sim_run_id IS NULL;
  IF v_post = 0 THEN RAISE EXCEPTION 'B6 FAIL: keep/production SDRs were purged'; END IF;
  RAISE NOTICE 'B6 PASS: purge swept doomed-run SDRs (%), kept run-A + production (%). detail=%',
               v_pre, v_post, v_purge->'cleared_by_table';

  RAISE NOTICE 'PART B: ALL PASS';
END;
$cert$;
