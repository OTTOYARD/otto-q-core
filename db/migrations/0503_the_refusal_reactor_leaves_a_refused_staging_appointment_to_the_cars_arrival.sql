-- migration-version: 20260926232527
-- migration-name:    the_refusal_reactor_leaves_a_refused_staging_appointment_to_the_cars_arrival
--
-- 0503  **A refused staging appointment was rerouted into an hour's hold that nothing ever used (G235, second
--       half).** `db/checks/0372` §6, `db/checks/0373`.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-26) ════════════════════════════════════════════════════════════════════
--
--   `ottoq.ottoq_react_to_refusals` reroutes a `target_occupied` refusal of `stage`: it reserves a free staging stall
--   for an hour, books it a 60-minute `temp_hold` (`otto_q_reaction`) and sends a new `stage` there. For a recall's
--   staging appointment the car is still on the road, and when it arrives the arrival flow places it itself: the
--   inspection seam books an `inspect` stall, or the charge step books a parking hold through
--   `ottoq.ottoq_book_hold_stall`. Neither looks at the hold the car already has (the enacted-booking seam releases
--   sibling holds of the same purpose only, and the parking-hold writer releases none), so the reroute's hold runs its
--   whole hour empty. On validation run `b0fdc92b`: 7 such holds, every car en route when it was booked, none used, 322
--   stall-minutes. Across every run started in the 9 hours before 23:00 UTC, canon arms included: every staging reroute
--   (194) came from a refused `stage` appointment and not one hold was activated, while the reactor's charge reroutes
--   were used (0373 §1).
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   A refused `stage` whose payload marks it a recall appointment is not rerouted. The refusal is marked reacted with
--   `reaction = {action: 'left_to_arrival', reason}`, nothing is booked or emitted, and the reservation the appointment
--   made on the refused stall is released if it is still the car's and the car is not on the stall. The arrival flow
--   places the car, as it already did. Every other refusal is handled exactly as before, 0490's later-command test
--   first. 0502 removes most of these refusals at the pick; this is what remains of them (a stall taken between the
--   pick and the gate).
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The reactor runs in the certified tick; where a staging appointment is still refused, bookings, commands and events
--   move.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0503 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (V3 plants its case on the depot's own rows, inside a rolled-back block) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0503 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamptz)'::regprocedure))
     <> '60b3adf31c6d480b9fa68e5774df221d' THEN
    RAISE EXCEPTION '0503 P2: ottoq.ottoq_react_to_refusals is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0503_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_react_to_refusals(uuid,uuid,timestamptz)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamptz)'::regprocedure);
  v_old text := $o$                                      'by_command_type',v_newer_type,'by_issued_at',v_newer_at);

    ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
$o$;
  v_new text := $n$                                      'by_command_type',v_newer_type,'by_issued_at',v_newer_at);

    /* 0503 (G235): A REFUSED STAGING APPOINTMENT IS LEFT TO THE CAR'S ARRIVAL. The reroute below booked such a car
       an hour on another staging stall, and nothing used it: 0 of 194 across every run of the 9 hours to 23:00 UTC
       on 2026-09-26, because the arrival flow (the inspection seam, the charge step's parking hold) places the car
       itself and never looks at that hold. The appointment's own reservation on the refused stall goes too: the car
       is not coming to it. */
    ELSIF v_rec.command_type = 'stage' AND v_rec.payload->'appointment' = 'true'::jsonb
       AND v_rec.reason_code IN ('target_occupied','resource_faulted') THEN
      v_outcome := jsonb_build_object('action','left_to_arrival','reason',v_rec.reason_code);
      UPDATE public.stalls s
         SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
       WHERE s.id = NULLIF(v_rec.payload->>'stall_id','')::uuid
         AND s.reserved_by = v_rec.vehicle_id
         AND s.current_vehicle_id IS DISTINCT FROM v_rec.vehicle_id;

    ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0503: the reroute branch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'ottoq.ottoq_react_to_refusals(uuid,uuid,timestamptz)'::regprocedure;
  v_def text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamptz)'::regprocedure);
BEGIN
  -- V1: 0490's later-command test first, then the appointment branch, then the reroute, which is unchanged.
  IF position('IF v_newer_id IS NOT NULL THEN' IN v_def) = 0
     OR position('''left_to_arrival''' IN v_def) = 0
     OR position('IF v_newer_id IS NOT NULL THEN' IN v_def) > position('''left_to_arrival''' IN v_def)
     OR position('''left_to_arrival''' IN v_def)
        > position($x$    ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')$x$ IN v_def)
     OR position($x$'otto_q_reaction')$x$ IN v_def) = 0
     OR position($x$'otto_q_reaction_last_resort')$x$ IN v_def) = 0 THEN
    RAISE EXCEPTION '0503 V1: the reactor is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and search path kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f) <> 'postgres=X/postgres,service_role=X/postgres'
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = v_f) <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0503 V2: ottoq_react_to_refusals''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: the case, planted on the newest stopped operator run and rolled back. Two cars each reserve a staging stall
-- that another car's live `temp_hold` covers, and each is sent `stage` there, which the gate refuses: one as a recall
-- appointment, one as a plain stage (the control). The reactor must leave the appointment to arrival, booking nothing
-- and releasing its reservation, and must still reroute the control.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_clock timestamptz;
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_cars uuid[]; v_stalls uuid[]; v_cmd_app uuid; v_cmd_ctl uuid;
  v_rx_app jsonb; v_rx_ctl jsonb; v_st_app text; v_st_ctl text; v_reserved uuid; v_held int;
BEGIN
  BEGIN
    SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.validation_status IS NULL AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0503 V3 FAILED: no stopped operator run to plant on'; END IF;
    SELECT array_agg(id ORDER BY id) INTO v_cars
      FROM (SELECT v.id FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.current_stall_id IS NULL
             ORDER BY v.id LIMIT 4) x;
    SELECT array_agg(id ORDER BY id) INTO v_stalls
      FROM (SELECT s.id FROM public.stalls s
             WHERE s.depot_id = v_depot AND s.stall_type = 'staging' AND s.zone <> 'arrival_inspection'
               AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
             ORDER BY s.id LIMIT 2) y;
    -- only the planted refusals are the reactor's to take
    UPDATE public.ottoq_vehicle_commands SET reacted_at = v_clock
     WHERE sim_run_id = v_run AND status = 'refused' AND reacted_at IS NULL;
    -- cars 3 and 4 hold the two stalls on the calendar; cars 1 and 2 reserve them and are sent there
    PERFORM ottoq.ottoq_book_stall(v_run, v_stalls[1], v_cars[3], 'temp_hold', v_clock, v_clock + interval '30 minutes',
                                   NULL, NULL, 'v3_0503');
    PERFORM ottoq.ottoq_book_stall(v_run, v_stalls[2], v_cars[4], 'temp_hold', v_clock, v_clock + interval '30 minutes',
                                   NULL, NULL, 'v3_0503');
    PERFORM public.ottoq_reserve_stall(v_stalls[1], v_cars[1], v_clock, 3000);
    PERFORM public.ottoq_reserve_stall(v_stalls[2], v_cars[2], v_clock, 3000);
    v_cmd_app := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_cars[1], 'stage',
                   jsonb_build_object('stall_id', v_stalls[1], 'stall_type', 'staging', 'appointment', true), v_clock);
    v_cmd_ctl := ottoq.ottoq_emit_vehicle_command(v_run, v_depot, v_cars[2], 'stage',
                   jsonb_build_object('stall_id', v_stalls[2], 'stall_type', 'staging'), v_clock);
    SELECT status INTO v_st_app FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app;
    SELECT status INTO v_st_ctl FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_ctl;
    IF v_st_app IS DISTINCT FROM 'refused' OR v_st_ctl IS DISTINCT FROM 'refused' THEN
      RAISE EXCEPTION '0503 V3 FAILED: the planted commands were not refused (% / %)', v_st_app, v_st_ctl;
    END IF;
    PERFORM ottoq.ottoq_react_to_refusals(v_run, v_depot, v_clock);
    SELECT payload->'reaction' INTO v_rx_app FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_app;
    SELECT payload->'reaction' INTO v_rx_ctl FROM public.ottoq_vehicle_commands WHERE command_id = v_cmd_ctl;
    SELECT reserved_by INTO v_reserved FROM public.stalls WHERE id = v_stalls[1];
    SELECT count(*) INTO v_held FROM public.ottoq_stall_bookings
     WHERE sim_run_id = v_run AND vehicle_id = v_cars[1] AND booked_by LIKE 'otto_q_reaction%';
    IF v_rx_app->>'action' IS DISTINCT FROM 'left_to_arrival' OR v_held <> 0 OR v_reserved IS NOT NULL
       OR v_rx_ctl->>'action' IS DISTINCT FROM 'rerouted' THEN
      RAISE EXCEPTION '0503 V3 FAILED: appointment % (reaction holds %, stall reserved by %), control %',
        v_rx_app, v_held, v_reserved, v_rx_ctl;
    END IF;
    RAISE EXCEPTION '0503 V3 PASSED: appointment %, control %', v_rx_app->>'action', v_rx_ctl->>'action';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0503 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0503 V3: no verdict'); END IF;
END $v3$;

-- Rollback: restore ottoq.ottoq_react_to_refusals from ottoq_schema_snapshots label '0503_pre' (CREATE OR REPLACE,
-- ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0503_the_refusal_reactor_leaves_a_refused_staging_appointment_to_the_cars_arrival', true,
  'ottoq_react_to_refusals leaves a refused stage appointment to the car''s arrival: no 60-minute temp_hold, no new '
  'command, and the appointment''s reservation on the refused stall released. Bookings, commands and events move '
  'where a staging appointment is still refused.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
