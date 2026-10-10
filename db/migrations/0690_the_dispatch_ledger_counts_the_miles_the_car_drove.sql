-- migration-version: 20261010111333
-- migration-name:    the_dispatch_ledger_counts_the_miles_the_car_drove
--
-- 0690  **The dispatch ledger counts the miles a car drove, tick by tick, as it already counts the energy.** (G406,
--        found 2026-10-10 comparing the twin with Waymo's CPUC filing, db/checks/0433 §3.)
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_sim_advance_deployed_telemetry closes a dispatch with
--     miles_driven = (SELECT COALESCE(SUM(speed_kmh) / 60.0 * 0.621371, 0) FROM ottoq_telemetry_packets WHERE ...)
--   which counts every telemetry packet as one minute of driving. A deployed car emits one packet a tick, and its
--   packets come 1.5 to 45 sim minutes apart by run. Measured on the twin depot's runs of the 7 days to 2026-10-10
--   (db/checks/0433 (2)): the ledger holds 0.021 of the miles the cars' own speeds give on normal_day, 0.024 on the
--   busy_day pairs and 0.679 on the operator's busy_day. Each tick the same function already computes the tick's
--   true miles (v_miles = the car's average speed x its active fraction x the tick's minutes, which the incident roll
--   reads) and adds the tick's energy to the dispatch. It never added the miles.
--
-- ══ §2 WHAT THIS CHANGES ═══════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Each tick adds v_miles to the dispatch's miles_driven, in the update that adds the tick's energy.
--   (b) The close keeps that total (COALESCE(miles_driven, 0), so a dispatch that closes on its first tick still
--       reads 0, as before), instead of summing packets.
--   Readers, all reporting (db/checks/0433 (3)): public.ottoq_twin_kpi_board ('miles' on the KPI tab),
--   public.ottoq_twin_offsite_window (miles p50, miles per trip-minute) and twin.ottoq_sim_build_arrival_payload
--   (the arrival webhook's odometer_mi, which only the webhook delivery reads). Dispatches closed before this file
--   keep the value they were closed with.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   No atom of the determinism pair reads miles_driven or the arrival webhook's payload (the pair's digest functions,
--   read 2026-10-10: ottoq_boot_state_fingerprint reads dispatches but not their miles; none reads the webhook log),
--   no dial metric does (deployed_car_hours, site_cost_usd_per_day, unmet_demand_car_hours, charge_wait_p95_floor_min,
--   charge_outlast_pct, asset_hours_available_per_day), and no decision does: the column is written here and read only
--   by the three readers above. The tick's draws, energy, battery, packets, incidents and return decisions are
--   computed exactly as before; only the ledger's miles change.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0690_pre'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0690 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0659_the_twins_chargers_can_be_depot_grade_and_the_research_wing_measures_it') THEN
    RAISE EXCEPTION '0690 P1: 0659 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
       <> '56b54f26900c31e65183ede9d7677a92' THEN
    RAISE EXCEPTION '0690 P1: twin.ottoq_sim_advance_deployed_telemetry is not the definition this file patches';
  END IF;
  -- the probe below advances a synthetic dispatch of a stopped run; with a run live it would share the fleet's rows
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0690 P1: a run is live; apply between runs';
  END IF;
END $premises$;

-- ── snapshot: the definition as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0690_pre', 'function', 'twin', 'ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure) AS def) d;

-- ── (a) and (b): the tick accrues its miles, and the close keeps them ──
DO $p_miles$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure);
  a text[] := ARRAY[
$a01$    UPDATE ottoq_vehicle_dispatches
       SET energy_consumed_kwh = COALESCE(energy_consumed_kwh, 0) + v_kwh_consumed
     WHERE dispatch_id = v_dispatch.dispatch_id;
$a01$,
$a02$             miles_driven = (SELECT COALESCE(SUM(speed_kmh) / 60.0 * 0.621371, 0)
                              FROM ottoq_telemetry_packets
                             WHERE sim_run_id = p_sim_run_id
                               AND vehicle_id = v_dispatch.vehicle_id
                               AND sim_clock_at >= v_dispatch.dispatched_at)
$a02$];
  b text[] := ARRAY[
$b01$    UPDATE ottoq_vehicle_dispatches
       SET energy_consumed_kwh = COALESCE(energy_consumed_kwh, 0) + v_kwh_consumed,
           -- 0690 (G406): the tick's miles accrue beside its energy, the v_miles the incident roll reads. The close
           -- used to count each telemetry packet as one minute of driving, and a car sends one packet a tick.
           miles_driven        = COALESCE(miles_driven, 0) + v_miles
     WHERE dispatch_id = v_dispatch.dispatch_id;
$b01$,
$b02$             miles_driven = COALESCE(miles_driven, 0)  -- 0690 (G406): the miles accrued tick by tick
$b02$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '56b54f26900c31e65183ede9d7677a92' THEN
    RAISE EXCEPTION '0690: the deployed-telemetry step is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0690: anchor % of the deployed-telemetry step occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '10c31929ce82ab46f8821401f384b603' THEN
    RAISE EXCEPTION '0690: the deployed-telemetry step, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
       <> '10c31929ce82ab46f8821401f384b603' THEN
    RAISE EXCEPTION '0690: the deployed-telemetry step did not read back as written';
  END IF;
END $p_miles$;

-- ── V1: a synthetic dispatch of a stopped run, advanced four ticks of different lengths and brought home (rolled back).
--        Each tick's added miles must equal the speed the tick's own packet reports x the tick's minutes, and the close
--        must keep the total. ──
DO $v1$
DECLARE
  v_run uuid; v_clock timestamptz; v_veh uuid; v_disp uuid; v_msg text;
  v_ticks numeric[] := ARRAY[5, 10, 7.5, 6];
  v_t timestamptz; v_prev numeric := 0; v_now numeric; v_speed numeric; v_status text;
  v_cmp int := 0; v_bad text; k int; v_parts text[];
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT v.id INTO v_veh
    FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND COALESCE(v.battery_capacity_kwh, 0) > 0
   ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION '0690 V1: no stopped twin run or no twin vehicle to probe';
  END IF;
  BEGIN
    -- 'returning', so the rule-9 departure check (which guards a new 'active' dispatch) does not judge a synthetic car,
    -- with the return trigger every returning dispatch carries (the recall sets it, and chk_completed_has_return_trigger
    -- refuses a completed dispatch without one: the first apply of this file failed here, 2026-10-10 11:10 UTC)
    INSERT INTO public.ottoq_vehicle_dispatches
      (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct, status,
       return_trigger)
    VALUES (v_veh, v_run, v_clock, v_clock + interval '3 hours', 180, 90, 'returning', 'scheduled')
    RETURNING dispatch_id INTO v_disp;
    v_t := v_clock;
    FOR k IN 1 .. array_length(v_ticks, 1) LOOP
      v_t := v_t + make_interval(secs => (v_ticks[k] * 60)::double precision);
      IF k = array_length(v_ticks, 1) THEN
        -- the last tick brings the car home
        UPDATE public.ottoq_vehicle_dispatches SET scheduled_return_at = v_t - interval '5 minutes' WHERE dispatch_id = v_disp;
      END IF;
      PERFORM count(*) FROM twin.ottoq_sim_advance_deployed_telemetry(v_run, v_t, v_ticks[k]);
      SELECT d.miles_driven, d.status INTO v_now, v_status FROM public.ottoq_vehicle_dispatches d WHERE d.dispatch_id = v_disp;
      v_speed := NULL;
      SELECT t.speed_kmh INTO v_speed
        FROM public.ottoq_telemetry_packets t
       WHERE t.sim_run_id = v_run AND t.vehicle_id = v_veh AND t.sim_clock_at = v_t AND t.speed_kmh IS NOT NULL
       LIMIT 1;
      IF v_speed IS NOT NULL THEN
        v_cmp := v_cmp + 1;
        IF abs((COALESCE(v_now, 0) - v_prev) - v_speed * v_ticks[k] / 60.0 * 0.621371) > 1e-9 THEN
          v_bad := format('tick %s added %s miles; its packet''s speed gives %s', k, COALESCE(v_now, 0) - v_prev,
                          v_speed * v_ticks[k] / 60.0 * 0.621371);
        END IF;
      END IF;
      v_prev := COALESCE(v_now, 0);
    END LOOP;
    RAISE EXCEPTION '0690 PROBED|%|%|%|%', v_status, v_prev, v_cmp, COALESCE(v_bad, '');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg NOT LIKE '0690 PROBED|%' THEN
    RAISE EXCEPTION '0690 V1 failed to run: %', v_msg;
  END IF;
  v_parts := string_to_array(v_msg, '|');
  IF v_parts[2] <> 'completed' OR v_parts[3]::numeric <= 0 OR v_parts[4]::int < 2 OR v_parts[5] <> '' THEN
    RAISE EXCEPTION '0690 V1 FAILED: %', v_msg;
  END IF;
  RAISE NOTICE '0690 V1 PASSED: a synthetic dispatch of run % drove % miles over 28.5 sim-minutes in four ticks; % of its ticks matched their packet''s speed exactly, and it closed completed with that total; all rolled back',
    v_run, round(v_parts[3]::numeric, 3), v_parts[4];
END $v1$;

-- ── V2: the definition as written ──
DO $v2$
DECLARE v_def text := pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure);
BEGIN
  IF md5(v_def) <> '10c31929ce82ab46f8821401f384b603' THEN
    RAISE EXCEPTION '0690 V2 FAILED: the deployed-telemetry step is not as written';
  END IF;
  IF strpos(v_def, 'SUM(speed_kmh) / 60.0') > 0 THEN
    RAISE EXCEPTION '0690 V2 FAILED: the packet count is still there';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0690_the_dispatch_ledger_counts_the_miles_the_car_drove', false, false,
  'G406: twin.ottoq_sim_advance_deployed_telemetry adds each tick''s miles (v_miles) to the dispatch beside its energy, '
  'and closes the dispatch on that total instead of counting each telemetry packet as one minute. Only the ledger''s '
  'miles move; their readers are the KPI board, the off-site window and the arrival webhook''s odometer, and no atom, '
  'dial metric or decision reads them: FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 11:13:33 UTC (6:13 AM CT), version 20261010111333 ═════════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 83f080a; the ledger's stored statement is that file byte for
--   byte (md5 c9deab342a18dec8be324b254331194b, 12,049 characters, 12,800 bytes). P1, V1, V2 passed in the apply's
--   transaction. Read after: the deployed-telemetry step's definition md5 10c31929ce82ab46f8821401f384b603 as written;
--   snapshot 0690_pre holds the old definition (56b54f26); lineage FALSE/FALSE (read 11:13:38 UTC). The first apply,
--   of the file as committed in 9eeaa49, rolled back at 11:10 UTC in V1 (its synthetic dispatch had no return trigger;
--   chk_completed_has_return_trigger refused it at the close); 83f080a gave it one and was rehearsed whole with
--   ROLLBACK at 11:12 UTC before this apply.
