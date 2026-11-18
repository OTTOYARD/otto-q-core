-- migration-version: 20261117235645
-- migration-name:    0844_a_car_the_needs_card_sends_to_a_bay_is_not_admitted_again_in_the_same_tick
--
-- 0844  **A car the needs card has sent to a bay in this tick is not admitted again by service sequencing in the same
--        tick. The second admission took back the first one's booking, and the car was seated for a minute.**
--
-- WHY. Read on the first check run after 0842 (0dc17f83, 2026-11-17, busy_day on 89ac9e74's seed): at sim 15:12:39
--   Waymo-AV-006, owing a tire rotation, was sent to service bay 02 by the needs card (section (4b) of
--   public.ottoq_decide_tick, booking 15:12:39 for 12 minutes, command enter_service, need tire_rotation). In the same
--   tick section (5), service sequencing, admitted it again: ottoq_l2_propose_service saw the rotation open on its visit
--   and proposed admit_service, and ottoq.ottoq_enact_space_assignment, releasing the car's earlier hold, cut the needs
--   card's booking to its first second (15:12:39 to 15:12:40) before booking bay 01. The twin refused the second command
--   and confirmed the first, whose booking had already ended, so the car's seat was floored at one minute: in the bay
--   15:13:31 to 15:14:48, the rotation credited at 15:14:31. A 9-minute job, done in one.
--   It is not new, and 0842 makes it common. Section (5) loops every car staged for service; (4b) seats a car from the
--   needs card's must-do list. A car is in both when its visit owes service-bay work that the card also grades must-do.
--   For preventive maintenance that takes a critical grade, so it was rare: no car was admitted twice in the twin
--   depot's last six runs. A tire job is must-do at 'due' on the card and required on the visit, so both doors fire for
--   most tire jobs. My own rolled-back exercise for 0842 showed the two commands, and I put them down to my harness.
--   They were this.
--
-- §1 WHAT THIS DOES. Section (5)'s loop passes over a car to which this tick has already issued a command that sends
--   it to a stall (a payload with a stall_id), as (4b) already passes over a car the cabin-stop step sent to a post
--   (0817). The car is seen again next tick, as 0081's wash guard leaves it. One predicate in one query.
--   Rules: nothing a car needs is dropped: its seat stands as (4b) booked it (9). No setting (10); one demo run (12).
--   No owner's car moves in any line (14).
--
-- §2 PRECONDITIONS AND CHECKS. P0 no certification in flight and no live run at the twin depot. P1 the decide tick's
--   body (md5 of prosrc, as 0842 left it). P2 once. V1 the anchor matched once; the tick is stored as patched, from its
--   snapshot. V2 a probe, rolled back, on the twin depot's newest finished run: one car staged full with worn tires
--   owing tire_replacement on its visit, both service bays clear. V2a, before the patch: the tick sends it to a bay twice
--   (the defect, reproduced). V2b, after it: once, and the needs card's booking stands, held, for 12 minutes.
--
-- §3 CLASSIFICATION. forces_recert TRUE: a car's service-bay seat changes. forces_dial_restart FALSE.
--
-- APPLIED 2026-11-17 at 23:56:45 UTC (5:56 PM CT), ledger 20261117235645, through apply_migration, on the first send,
--   right after 0843. No run was live. A dry run of the same statements, ending in a raise that rolled everything back,
--   ran first. On check run 0dc17f83's clock: before the patch the probe car was sent to a bay twice and the needs
--   card's booking ended 'done' after 1 second, as the run showed; after it, once, and the booking stood, held, for 720
--   seconds; the tick erred nowhere. The ledger holds this whole file byte for byte as committed before this note (md5
--   ce220cbb8f6827c7cb97d14d0069f107). Read after the apply: md5(prosrc) of public.ottoq_decide_tick
--   17cedddda8c9c211346a1ba8eec6cc62 (was 3f3871c273f10cbd935329ff8e3d16c8).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0844_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0844_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0844 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running') THEN
    RAISE EXCEPTION '0844 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM '3f3871c273f10cbd935329ff8e3d16c8' THEN
    RAISE EXCEPTION '0844 P1: public.ottoq_decide_tick is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0844_%') THEN RAISE EXCEPTION '0844 P2: already applied'; END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0844_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_decide_tick(uuid)']) AS f;

CREATE TEMP TABLE _0844_patch (c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0844_patch VALUES (
$o$                          AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                          AND COALESCE(a->>'must_do','false') = 'true'
                          AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40$o$,
$n$                          AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                          AND COALESCE(a->>'must_do','false') = 'true'
                          AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
       -- 0844: nor a car this tick has already sent to a stall ((4b) above). Admitting it again released (4b)'s booking
       -- to its first second, and the car was seated for a minute (run 0dc17f83). It is seen again next tick.
       AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_commands vc
                        WHERE vc.vehicle_id = v.id AND vc.sim_run_id = p_sim_run_id
                          AND vc.issued_at = v_clock AND vc.status = 'issued' AND vc.payload ? 'stall_id')
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40$n$);

-- V2: the probe. It raises to roll its writes back; the answer comes back as the exception's detail.
CREATE FUNCTION pg_temp._0844_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_car uuid; v_r jsonb := '{}'::jsonb; v_detail text;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot AND r.status IN ('completed', 'stopped')
   ORDER BY r.started_at DESC LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL THEN RAISE EXCEPTION '0844 V2: no run or car to probe with'; END IF;
  BEGIN
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, status = 'available'
     WHERE depot_id = c_depot AND stall_type::text = 'service_bay';
    UPDATE public.ottoq_stall_bookings b SET state = 'released'
      FROM public.stalls s WHERE s.id = b.stall_id AND s.depot_id = c_depot AND s.stall_type::text = 'service_bay'
       AND b.state IN ('held', 'active') AND b.during && tstzrange(v_clock - interval '2 hours', v_clock + interval '4 hours');
    UPDATE public.vehicle_need_profile
       SET tire_tread_mm = 2.6, last_tire_rotation_at = v_clock - interval '10 days', km_at_last_pm = odometer_km,
           brake_wear_pct = 10, last_calibration_at = v_clock, sensor_health_pct = 99, worst_fault_severity = 99,
           open_fault_codes = '{}'::text[], exterior_soil_level = 0, cabin_condition = 'clean', last_wash_at = v_clock,
           last_deep_clean_at = v_clock, software_version = sw_target_version, item_retrieval_pending = false
     WHERE vehicle_id = v_car;
    UPDATE public.ottoq_vehicle_wear SET km_at_last_pm = drive_km_total, hours_at_last_calibration = drive_hours_total
     WHERE vehicle_id = v_car AND sim_run_id = v_run;
    UPDATE public.vehicles SET current_soc = 100, current_state = 'staged_awaiting_service',
           last_state_change = v_clock - interval '5 minutes',
           config = COALESCE(config, '{}'::jsonb) || '{"svc_step": "need_service"}'::jsonb
     WHERE id = v_car;
    UPDATE public.ottoq_visit_needs SET status = 'complete' WHERE vehicle_id = v_car AND status IN ('open', 'in_progress');
    -- the visit owes the replacement (0842's deriver), and the needs card grades it must-do: both doors see the car
    PERFORM ottoq.ottoq_derive_visit_needs(v_car, v_run, v_run, v_clock, c_depot, '{}'::jsonb);
    v_r := v_r || jsonb_build_object('tick', (SELECT to_jsonb(t) FROM public.ottoq_decide_tick(v_run) t));
    v_r := v_r || jsonb_build_object(
      'sent', (SELECT count(*) FROM public.ottoq_vehicle_commands c
                WHERE c.vehicle_id = v_car AND c.sim_run_id = v_run AND c.issued_at = v_clock AND c.payload ? 'stall_id'
                  AND c.command_type = 'enter_service'),
      'card_booking', (SELECT jsonb_build_object('state', b.state,
                                'seconds', round(EXTRACT(EPOCH FROM (upper(b.during) - lower(b.during)))))
                         FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
                        WHERE b.vehicle_id = v_car AND b.sim_run_id = v_run AND s.stall_type::text = 'service_bay'
                          AND to_jsonb(b) ->> 'source' = 'needs_card' AND lower(b.during) = v_clock
                        ORDER BY b.booked_at DESC NULLS LAST LIMIT 1));
    RAISE EXCEPTION USING ERRCODE = 'OQ844', MESSAGE = '0844 V2 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ844' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

DO $v2a$
DECLARE v_r jsonb := pg_temp._0844_probe();
BEGIN
  IF COALESCE((v_r ->> 'sent')::int, 0) < 2 THEN
    RAISE EXCEPTION '0844 V2a: the defect did not reproduce on the tick as it was: %', v_r;
  END IF;
  RAISE NOTICE '0844 V2a (before): %', v_r;
END $v2a$;

DO $patch$
DECLARE p record; v_def text; v_old text; n int;
BEGIN
  SELECT * INTO p FROM _0844_patch;
  v_old := pg_get_functiondef(to_regprocedure('public.ottoq_decide_tick(uuid)'));
  n := (length(v_old) - length(replace(v_old, p.c_old, ''))) / length(p.c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0844 V1: the anchor matches % times, not 1', n; END IF;
  v_def := replace(v_old, p.c_old, p.c_new);
  EXECUTE v_def;
  IF pg_get_functiondef(to_regprocedure('public.ottoq_decide_tick(uuid)')) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0844 V1: the decide tick is not stored as patched';
  END IF;
  IF md5(replace(v_def, p.c_new, p.c_old)) IS DISTINCT FROM
     (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0844_pre' ORDER BY snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0844 V1: the patched definition with the patch reversed is not the snapshot';
  END IF;
END $patch$;

DO $v2b$
DECLARE v_r jsonb := pg_temp._0844_probe();
BEGIN
  IF COALESCE((v_r #>> '{tick,errored}')::int, -1) <> 0 OR COALESCE((v_r ->> 'sent')::int, 0) <> 1
     OR (v_r #>> '{card_booking,state}') IS DISTINCT FROM 'held'
     OR COALESCE((v_r #>> '{card_booking,seconds}')::numeric, 0) <> 720 THEN
    RAISE EXCEPTION '0844 V2b: the car was not sent once, with its 12-minute booking standing: %', v_r;
  END IF;
  RAISE NOTICE '0844 V2b (after): %', v_r;
END $v2b$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0844_a_car_the_needs_card_sends_to_a_bay_is_not_admitted_again_in_the_same_tick', true, false,
        'Section (5) of the decide tick passes over a car this tick already sent to a stall, so service sequencing no '
        || 'longer admits a car the needs card just seated and releases its booking to a second (run 0dc17f83: a tire '
        || 'rotation seated for one minute). Pre-image 0844_pre.', now());
COMMIT;
