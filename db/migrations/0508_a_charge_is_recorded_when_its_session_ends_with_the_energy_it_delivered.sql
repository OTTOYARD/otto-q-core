-- migration-version: 20260927012721
-- migration-name:    a_charge_is_recorded_when_its_session_ends_with_the_energy_it_delivered
--
-- 0508  **A charge's itinerary leg and its signed service record ended when the booking window ran out, while the
--       charge went on (G238), and no service record ever carried the energy a charge delivered (G239).**
--       `db/checks/0375`.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-27 on validation run 5344fc12) ══════════════════════════════════════════
--
--   `ottoq.ottoq_release_expired_bookings` ends an active booking that ran its full window `done /
--   window_elapsed_occupied`, and since 0089 it closes the leg that booking serves at the window's end, which issues
--   the leg's signed service record. A charge booking's window is an estimate, and on 5344fc12 21 of 31 completed L2
--   sessions and 9 of 21 DCFC sessions outlasted theirs. So 31 of 67 done charge legs, and their records, ended while
--   the charge went on (a median 24.5 minutes early for L2, 13.0 for DCFC; 1,038 charger-minutes in all).
--   `twin.ottoq_sim_stop_charge_session` closes the charge leg at the session's real end, but it found the leg
--   already closed, and `ottoq_emit_sdr` returns early for a leg that has a record.
--
--   Separately, `ottoq_trg_leg_done_sdr` never passed `ottoq_emit_sdr` the energy or peak it takes, so none of the
--   120,624 surviving twin records carries energy, while 5344fc12's 95 sessions delivered 2,317.8 kWh.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The closer leaves an ACTIVE charge leg open while an OCPP session for the same car on the booking's stall is
--       active. The booking itself still ends at its window, `window_elapsed_occupied`, as before: G81 ("do NOT fix it
--       by re-extending the booking") and 0500 ("a charge overstay keeps its G81 stamp") both stand. The session's
--       stop then closes the leg at the charge's real end, as it was written to.
--   (2) The orphan sweep in `public.ottoq_reconcile_charger_states` ends a session whose car has left its stall
--       without calling the stop, so a leg left open by (1) would never close. The sweep now closes each swept
--       session's active charge leg at the session's own end, in a statement after the sweep's, so the leg's record
--       reads the session as ended.
--   (3) `ottoq_trg_leg_done_sdr` gives a charge leg's record the energy and the peak of the car's sessions that
--       overlap the leg (a sum and a max, so no order is needed and both arms of a pair agree), and the session's id
--       when exactly one overlaps. The energy and peak go through `ottoq_emit_sdr`, so they are in the signed payload.
--       The session id is set on the record afterwards: it is outside the signature and outside `ottoq_hash_sdrs`,
--       which digests content and never a minted id (0216, 0218).
--
--   Other leg types, the bookings and the stop itself are unchanged. Every function that reads an active leg was
--   checked for a charge leg staying active longer: the ones that act on it touch bay legs or interrupted bookings
--   only (`ottoq_decide_tick`'s bay cursors, the two readmit paths, `ottoq_release_vacated_spaces`), and the flow
--   contract already leaves a charging car's plan alone.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_hash_sdrs` digests each record's times, duration, energy and peak; for a charge every one of them can
--   move. What else moves is read in the sweep.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0508 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (the world tick calls all three; V3 plants its cases on the depot's own rows, rolled back) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0508 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure))
     <> 'a6ef4307af4493ec005b082feb5587f5' THEN
    RAISE EXCEPTION '0508 P2: ottoq.ottoq_release_expired_bookings is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_reconcile_charger_states(uuid)'::regprocedure))
     <> '549353877215ad00b591d9d759dd987e' THEN
    RAISE EXCEPTION '0508 P2: public.ottoq_reconcile_charger_states is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_trg_leg_done_sdr()'::regprocedure))
     <> '1bf3d832e254b104d4b88ece836399c1' THEN
    RAISE EXCEPTION '0508 P2: public.ottoq_trg_leg_done_sdr is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0508_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure,
                 'public.ottoq_reconcile_charger_states(uuid)'::regprocedure,
                 'public.ottoq_trg_leg_done_sdr()'::regprocedure);

-- (1) the closer
DO $patch1$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure);
  v_old text := $o$     WHERE u.state = 'done' AND l.leg_id = u.leg_id
       AND l.status IN ('planned','active')
  )$o$;
  v_new text := $n$     WHERE u.state = 'done' AND l.leg_id = u.leg_id
       AND l.status IN ('planned','active')
       -- 0508 (G238): a charge whose session is still running on this stall is closed by the session's stop, at the
       -- charge's real end, not here at the window's. The booking still ends here (G81).
       AND NOT (l.status = 'active' AND l.leg_type IN ('charge_dcfc','charge_l2')
                AND EXISTS (SELECT 1 FROM public.ocpp_sessions os
                             WHERE os.sim_run_id = p_sim_run_id AND os.vehicle_id = u.vehicle_id
                               AND os.stall_id = u.stall_id AND os.status = 'active'))
  )$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0508: the closer''s leg update matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch1$;

-- (2) the orphan sweep
DO $patch2$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_reconcile_charger_states(uuid)'::regprocedure);
  v_pairs text[][] := ARRAY[
    [$o1$DECLARE v_healed integer; v_orphans integer := 0; v_unstuck integer := 0;$o1$,
     $n1$DECLARE v_healed integer; v_orphans integer := 0; v_unstuck integer := 0;
  v_orphan_rows jsonb := '[]'::jsonb; v_o jsonb;   -- 0508$n1$],
    [$o2$    RETURNING cs.id
  )
  SELECT count(*) INTO v_orphans FROM closed;$o2$,
     $n2$    RETURNING cs.id, cs.sim_run_id, cs.vehicle_id, cs.ended_at
  )
  SELECT count(*), COALESCE(jsonb_agg(jsonb_build_object('run', c.sim_run_id, 'vehicle', c.vehicle_id, 'at', c.ended_at)),
                            '[]'::jsonb)
    INTO v_orphans, v_orphan_rows FROM closed c;

  -- 0508 (G238): a charge leg is closed by its session's end, and a swept session ends here without the stop, so its
  -- leg closes here, at the session's own end. A statement of its own, so the leg's record reads the session as ended.
  FOR v_o IN SELECT * FROM jsonb_array_elements(v_orphan_rows) LOOP
    PERFORM public.ottoq_itin_leg_close((v_o->>'run')::uuid, (v_o->>'vehicle')::uuid,
                                        ARRAY['charge_dcfc','charge_l2'], (v_o->>'at')::timestamptz, 'done');
  END LOOP;$n2$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0508: sweep patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch2$;

-- (3) the record
DO $patch3$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_trg_leg_done_sdr()'::regprocedure);
  v_pairs text[][] := ARRAY[
    [$o1$DECLARE v_op record; v_booking uuid; v_visit uuid; v_depot uuid;$o1$,
     $n1$DECLARE v_op record; v_booking uuid; v_visit uuid; v_depot uuid;
  v_kwh numeric; v_peak numeric; v_sessions int; v_session uuid; v_sdr uuid;   -- 0508$n1$],
    [$o2$  PERFORM ottoq_emit_sdr(
    'itinerary_leg', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NEW.sim_run_id,
    NEW.leg_id, NULL, v_visit, v_booking,
    NEW.to_stall_id, v_depot,
    NEW.actual_start_sim, COALESCE(NEW.actual_end_sim, now()));
  RETURN NEW;$o2$,
     $n2$  --: 0508 (G239). A charge's record carries what its session delivered: the energy and the peak of this car's
  --: sessions that overlap the leg (normally one, the session whose stop closed it), summed and maxed so that no
  --: order is needed, and that session's id when exactly one overlaps. The energy and peak are signed with the
  --: record; the id is set after, outside the signature and outside ottoq_hash_sdrs.
  IF NEW.leg_type IN ('charge_dcfc','charge_l2') AND NEW.actual_start_sim IS NOT NULL THEN
    SELECT sum(os.energy_delivered_kwh), max(os.peak_power_kw), count(*),
           CASE WHEN count(*) = 1 THEN (array_agg(os.id))[1] END
      INTO v_kwh, v_peak, v_sessions, v_session
      FROM ocpp_sessions os
     WHERE os.vehicle_id = NEW.vehicle_id
       AND os.sim_run_id IS NOT DISTINCT FROM NEW.sim_run_id
       AND os.started_at < COALESCE(NEW.actual_end_sim, now())
       AND COALESCE(os.ended_at, 'infinity'::timestamptz) > NEW.actual_start_sim;
  END IF;

  v_sdr := ottoq_emit_sdr(
    'itinerary_leg', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NEW.sim_run_id,
    NEW.leg_id, NULL, v_visit, v_booking,
    NEW.to_stall_id, v_depot,
    NEW.actual_start_sim, COALESCE(NEW.actual_end_sim, now()),
    v_kwh, v_peak);
  IF v_sdr IS NOT NULL AND v_session IS NOT NULL THEN
    UPDATE ottoq_service_detail_records SET ocpp_session_id = v_session WHERE sdr_id = v_sdr;
  END IF;
  RETURN NEW;$n2$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0508: record patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch3$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_closer text := pg_get_functiondef('ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure);
  v_sweep  text := pg_get_functiondef('public.ottoq_reconcile_charger_states(uuid)'::regprocedure);
  v_trg    text := pg_get_functiondef('public.ottoq_trg_leg_done_sdr()'::regprocedure);
BEGIN
  -- V1: each body carries its change once.
  IF (length(v_closer) - length(replace(v_closer, 'os.stall_id = u.stall_id AND os.status = ''active''', '')))
       / length('os.stall_id = u.stall_id AND os.status = ''active''') <> 1
     OR (length(v_sweep) - length(replace(v_sweep, 'PERFORM public.ottoq_itin_leg_close(', '')))
       / length('PERFORM public.ottoq_itin_leg_close(') <> 1
     OR position('PERFORM ottoq_emit_sdr(' IN v_trg) > 0
     OR (length(v_trg) - length(replace(v_trg, 'v_kwh, v_peak);', ''))) / length('v_kwh, v_peak);') <> 1
     OR position('SET ocpp_session_id = v_session' IN v_trg) = 0 THEN
    RAISE EXCEPTION '0508 V1: a patched body is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and settings kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT array_to_string(proacl, ',') FROM pg_proc
       WHERE oid = 'ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure)
       <> 'postgres=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc
          WHERE oid = 'ottoq.ottoq_release_expired_bookings(uuid,timestamptz)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_reconcile_charger_states(uuid)'::regprocedure)
       <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_reconcile_charger_states(uuid)'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'public.ottoq_reconcile_charger_states(uuid)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_trg_leg_done_sdr()'::regprocedure)
       <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_trg_leg_done_sdr()'::regprocedure)
     OR (SELECT proconfig FROM pg_proc WHERE oid = 'public.ottoq_trg_leg_done_sdr()'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION '0508 V2: a patched function''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: three cases planted on the newest stopped operator run's own charges, then rolled back.
--   (a) a charge whose record ended at its window while its session ran on: the leg, its booking and its session are
--       put back as they were at the window's end. The closer, a minute past the window, must end the booking
--       `window_elapsed_occupied` and leave the leg open with no record; the session's stop, halfway between then and
--       the session's real end, must close the leg at the stop's clock with one record carrying the session's energy,
--       peak and id.
--   (b) the control, a charge its session closed: put back with its booking open and its session ended. The closer
--       must close it at the window's end, as before, with one record carrying that session's energy and id.
--   (c) a charge whose car has left: its leg put back open and its session marked running again with its own end
--       kept. The orphan sweep must end the session there and close the leg at that end, with one record carrying the
--       session's energy and id.
--   Each clock stays inside its session's own span, so no other session of the same car can overlap the record.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  a record; b record; c record; v_c1 timestamptz; v_stop timestamptz; r record;
BEGIN
  BEGIN
    SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
     WHERE sr.depot_id = v_depot AND sr.validation_status IS NULL AND sr.status = 'completed'
       AND sr.sim_clock_current IS NOT NULL
     ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0508 V3 FAILED: no stopped operator run to plant on'; END IF;

    -- the cases: charge legs of the run with their settled booking and the completed session that charged them
    CREATE TEMP TABLE v3_case ON COMMIT DROP AS
    SELECT l.leg_id, l.vehicle_id, l.leg_type, l.actual_start_sim, l.actual_end_sim,
           bk.booking_id, bk.stall_id, bk.release_reason, lower(bk.during) AS b_lo, upper(bk.during) AS b_hi,
           s.id AS session_id, s.started_at AS s_start, s.ended_at AS s_end, s.energy_delivered_kwh AS s_kwh,
           s.peak_power_kw AS s_peak
      FROM public.ottoq_itinerary_legs l
      JOIN LATERAL (SELECT bb.* FROM public.ottoq_stall_bookings bb WHERE bb.leg_id = l.leg_id
                     ORDER BY (bb.state IN ('superseded','released','cancelled')), lower(bb.during) LIMIT 1) bk ON true
      JOIN LATERAL (SELECT os.* FROM public.ocpp_sessions os
                     WHERE os.sim_run_id = v_run AND os.vehicle_id = l.vehicle_id AND os.stall_id = bk.stall_id
                       AND os.started_at <= l.actual_end_sim AND os.ended_at >= l.actual_start_sim
                     ORDER BY abs(EXTRACT(epoch FROM os.started_at - l.actual_start_sim)) LIMIT 1) s ON true
     WHERE l.sim_run_id = v_run AND l.leg_type IN ('charge_dcfc','charge_l2') AND l.status = 'done'
       AND s.stopped_reason = 'completed' AND s.id_token LIKE 'TWIN-%' AND COALESCE(s.meter_values_count, 0) >= 1;

    SELECT * INTO a FROM v3_case
     WHERE release_reason = 'window_elapsed_occupied' AND s_end > actual_end_sim + interval '5 minutes'
     ORDER BY actual_end_sim, leg_id LIMIT 1;
    SELECT * INTO b FROM v3_case
     WHERE release_reason = 'charge_session_completed' AND vehicle_id <> a.vehicle_id
     ORDER BY actual_end_sim, leg_id LIMIT 1;
    SELECT * INTO c FROM v3_case
     WHERE release_reason = 'window_elapsed_occupied' AND s_end > actual_end_sim + interval '5 minutes'
       AND vehicle_id NOT IN (a.vehicle_id, b.vehicle_id)
     ORDER BY actual_end_sim DESC, leg_id LIMIT 1;
    IF a.leg_id IS NULL OR b.leg_id IS NULL OR c.leg_id IS NULL THEN
      RAISE EXCEPTION '0508 V3 FAILED: the run has no case of each kind to plant (a % b % c %)', a.leg_id, b.leg_id, c.leg_id;
    END IF;

    -- put each back as it stood: the three records go, the three legs are active again, the two bookings of (a) and
    -- (b) are active again, (a)'s session is running with no end yet, and (c)'s is running with its own end kept
    DELETE FROM public.ottoq_service_detail_records WHERE leg_id IN (a.leg_id, b.leg_id, c.leg_id);
    UPDATE public.ottoq_itinerary_legs SET status = 'active', actual_end_sim = NULL, deviation_s = NULL
     WHERE leg_id IN (a.leg_id, b.leg_id, c.leg_id);
    UPDATE public.ottoq_stall_bookings SET state = 'active', released_at = NULL, release_reason = NULL
     WHERE booking_id IN (a.booking_id, b.booking_id);
    UPDATE public.ocpp_sessions SET status = 'active', ended_at = NULL, stopped_reason = NULL WHERE id = a.session_id;
    UPDATE public.ocpp_sessions SET status = 'active', stopped_reason = NULL WHERE id = c.session_id;
    -- (c)'s car has left its stall
    UPDATE public.vehicles SET current_stall_id = NULL WHERE id = c.vehicle_id AND current_stall_id = c.stall_id;

    -- (a): the closer, one minute past its window
    v_c1 := a.b_hi + interval '1 minute';
    PERFORM ottoq.ottoq_release_expired_bookings(v_run, v_c1);

    SELECT l.status, bk.state, bk.release_reason,
           (SELECT count(*) FROM public.ottoq_service_detail_records WHERE leg_id = a.leg_id) AS sdrs
      INTO r
      FROM public.ottoq_itinerary_legs l, public.ottoq_stall_bookings bk
     WHERE l.leg_id = a.leg_id AND bk.booking_id = a.booking_id;
    IF r.status <> 'active' OR r.state <> 'done' OR r.release_reason <> 'window_elapsed_occupied' OR r.sdrs <> 0 THEN
      RAISE EXCEPTION '0508 V3 FAILED (a) at the window: leg %, booking % / %, records %', r.status, r.state, r.release_reason, r.sdrs;
    END IF;

    -- (a): the session stops halfway between then and its own end
    v_stop := v_c1 + (a.s_end - v_c1) / 2;
    PERFORM twin.ottoq_sim_stop_charge_session(a.session_id, 'completed', v_stop, NULL, v_run);
    SELECT l.status, l.actual_end_sim, sd.energy_kwh, sd.peak_kw, sd.ocpp_session_id, sd.ended_at,
           (SELECT count(*) FROM public.ottoq_service_detail_records WHERE leg_id = a.leg_id) AS sdrs
      INTO r
      FROM public.ottoq_itinerary_legs l
      LEFT JOIN public.ottoq_service_detail_records sd ON sd.leg_id = l.leg_id
     WHERE l.leg_id = a.leg_id;
    IF r.status <> 'done' OR r.actual_end_sim IS DISTINCT FROM v_stop OR r.sdrs <> 1 OR r.ended_at IS DISTINCT FROM v_stop
       OR r.energy_kwh IS DISTINCT FROM a.s_kwh OR r.peak_kw IS DISTINCT FROM a.s_peak
       OR r.ocpp_session_id IS DISTINCT FROM a.session_id THEN
      RAISE EXCEPTION '0508 V3 FAILED (a) at the stop: leg % ended % (stop %), records %, energy % (session %), peak % (%), id %',
        r.status, r.actual_end_sim, v_stop, r.sdrs, r.energy_kwh, a.s_kwh, r.peak_kw, a.s_peak, r.ocpp_session_id;
    END IF;

    -- (b): the closer, one minute past its window (a no-op for it if the first call already passed its window)
    PERFORM ottoq.ottoq_release_expired_bookings(v_run, GREATEST(b.b_hi, v_c1) + interval '1 minute');
    SELECT l.status, l.actual_end_sim, sd.energy_kwh, sd.ocpp_session_id, sd.ended_at,
           (SELECT count(*) FROM public.ottoq_service_detail_records WHERE leg_id = b.leg_id) AS sdrs
      INTO r
      FROM public.ottoq_itinerary_legs l
      LEFT JOIN public.ottoq_service_detail_records sd ON sd.leg_id = l.leg_id
     WHERE l.leg_id = b.leg_id;
    IF r.status <> 'done' OR r.actual_end_sim IS DISTINCT FROM b.b_hi OR r.sdrs <> 1
       OR r.energy_kwh IS DISTINCT FROM b.s_kwh OR r.ocpp_session_id IS DISTINCT FROM b.session_id THEN
      RAISE EXCEPTION '0508 V3 FAILED (b): leg % ended % (window %), records %, energy % (session %), session id %',
        r.status, r.actual_end_sim, b.b_hi, r.sdrs, r.energy_kwh, b.s_kwh, r.ocpp_session_id;
    END IF;

    -- (c): the orphan sweep
    PERFORM public.ottoq_reconcile_charger_states(v_depot);
    SELECT l.status, l.actual_end_sim, s.status::text AS s_status, s.ended_at AS s_end, sd.energy_kwh, sd.ocpp_session_id,
           (SELECT count(*) FROM public.ottoq_service_detail_records WHERE leg_id = c.leg_id) AS sdrs
      INTO r
      FROM public.ottoq_itinerary_legs l
      JOIN public.ocpp_sessions s ON s.id = c.session_id
      LEFT JOIN public.ottoq_service_detail_records sd ON sd.leg_id = l.leg_id
     WHERE l.leg_id = c.leg_id;
    IF r.s_status <> 'cancelled' OR r.s_end IS DISTINCT FROM c.s_end OR r.status <> 'done'
       OR r.actual_end_sim IS DISTINCT FROM c.s_end OR r.sdrs <> 1
       OR r.energy_kwh IS DISTINCT FROM c.s_kwh OR r.ocpp_session_id IS DISTINCT FROM c.session_id THEN
      RAISE EXCEPTION '0508 V3 FAILED (c): session %, leg % ended % (session end %), records %, energy % (session %), id %',
        r.s_status, r.status, r.actual_end_sim, r.s_end, r.sdrs, r.energy_kwh, c.s_kwh, r.ocpp_session_id;
    END IF;

    RAISE EXCEPTION '0508 V3 PASSED: (a) % kWh signed at the stop, % past the window; (b) % kWh at the window; (c) % kWh at the session''s end',
      a.s_kwh, v_stop - a.b_hi, b.s_kwh, c.s_kwh;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0508 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0508 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore the three functions from ottoq_schema_snapshots label '0508_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0508_a_charge_is_recorded_when_its_session_ends_with_the_energy_it_delivered', true,
  'The closer leaves an active charge leg open while its session runs (the booking still ends at its window, G81), '
  'the orphan sweep closes a swept session''s charge leg, and a charge''s service record carries the energy and peak '
  'of the sessions that overlap it. ottoq_hash_sdrs digests the records'' times, energy and peak.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
