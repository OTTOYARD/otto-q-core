-- migration-version: 20260928111517
-- migration-name:    a_car_seated_in_a_bay_early_is_served_now
--
-- 0549  **A car seated in a bay before its booking's window is served now, and the bay is free when the work is done.**
--        (G278.) The needs-card seat puts a car in a wash, detail or service bay as soon as one is free. When the car
--        already held a reservation for that bay later in the day, the booking code adopted it and tried to stretch it
--        back to cover the early start as well as the old end. When another car's reservation sat in between, the
--        stretch failed quietly and the reservation stayed where it was. The door then pinned the car's time in the bay
--        to the reservation's end, so the car sat in the bay until then, and the cars booked in between lost their
--        windows. An adopted bay reservation now moves to start when the car goes in, and keeps its own length.
--
-- ══ §1 WHY (validation run 921e349c, check 0405 §13; CLAUDE.md rule 9; G278) ═════════════════════════════════════════
--
--   Rule 9: no car leaves with a service open, so a bay minute spent on waiting is a minute another car at 100% waits
--   at the gate. On 921e349c (sim times CT):
--     - Tesla-RT-003 held a forward wash reservation on WSH-02 for 10:45-10:54 AM, with a planned leg, made at 6:14
--       AM. At 7:02 AM the needs-card seat found WSH-02 free for the wash's 9 minutes and seated the car.
--     - `ottoq.ottoq_record_enacted_booking` found the car's own reservation on that bay for the same purpose and
--       adopted it, then tried to stretch it to 7:02-10:54 AM. Nine other cars had reservations on WSH-02 in between
--       (7:53 AM to 10:30 AM, all made before 7:02), so the stretch hit the calendar's EXCLUDE constraint. The
--       function caught that with a WARNING and returned the reservation unchanged, still 10:45-10:54.
--     - The door (`twin.ottoq_sim_confirm_commands`, since 0458) pins the car's `service_ends_at` to the booking's
--       end. The car sat in WSH-02 for 232 minutes and left at 10:54 AM to the minute. Six of the nine reservations in
--       between elapsed unused and three were superseded; three of the six cars were later held 240 minutes at the
--       gate at 100%, waiting for a wash.
--   Four entries went this way (2 wash, 2 detail), holding the wash bays 465 minutes before their windows. A fifth
--   stretch succeeded: Tesla-AV-060, seated at 6:07 AM for a deep-clean reservation of 6:41-6:59 AM on WSH-02, had it
--   stretched to 6:07-6:59 and held the bay 52.3 minutes.
--   The deploy gate held 9 cars at 100% for 240 minutes for a wash or deep clean; dbdffd5c, the same seed and sim
--   day, held none.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq.ottoq_record_enacted_booking`, where it adopts the car's own reservation (same stall, same car, same
--       purpose). When the purpose is a bay's (`wash`, `detail`, `service`) and the reservation starts after the car
--       takes the bay, the reservation MOVES to start then. Its length is its own, or the caller's window if that is
--       longer. If that collides, the caller's window is used: the caller found the stall free for it
--       (`ottoq.ottoq_stall_free_between`). If that collides too, the reservation is left as it was, with the WARNING,
--       as today. Every other purpose (charges, holds, staging) is stretched exactly as before.
--   (b) `public.ottoq_decide_tick`, the needs-card seat. With a planned bay leg, the seat asked for the bay from now
--       until the leg's planned end, however far off. It now asks for the leg's length from now. Without a planned
--       leg, the seat asks for the service's minutes from now, as before; on 921e349c every seat was that case.
--   The door is unchanged. With the booking moved, the booking's end is the end of the work.
--
--   Rule 9 holds: no service is shortened. The car gets the whole of its reservation's length, or longer, starting
--   when it goes in. What changes is that the bay is free when the work is done, and the calendar says so.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Any arm in which a car is seated in a bay before its reservation now frees the bay earlier; the cars behind it,
--   the bookings, the stall events and the deploy gate can all move.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - A fix at the door alone (pin the contract to entry plus the booking's length, leave the booking where it is).
--     Rejected: when the car leaves, `ottoq.ottoq_release_vacated_spaces` clips an active booking at
--     GREATEST(lower + 1 second, LEAST(upper, clock)). For a booking still in the future that clip is lower + 1
--     second, so `ottoq_booking_interrupted` would call the work cut short and reopen the car's atoms: the wash would
--     be done twice. The booking has to move with the car.
--   - `ottoq.ottoq_bind_unbooked_bay_occupants` adopts through the same function, so a reservation it adopts early
--     moves as well. That is the same truth for the same reason.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0549 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: the two functions are the ones measured (2026-09-28 10:00 UTC: the booking function's definition, the tick's source) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure))
     <> '8ef93a143df2289724a6ef95a9096fbe' THEN
    RAISE EXCEPTION '0549 P2: ottoq.ottoq_record_enacted_booking is not the function measured';
  END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure))
     <> 'c0cffe382b845d269578e1cf087b46a3' THEN
    RAISE EXCEPTION '0549 P2: public.ottoq_decide_tick is not the function measured';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0549_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure);

-- ── (a) an adopted bay reservation moves to when the car goes in ──
DO $adopt$
DECLARE v_def text; n int;
  c_old CONSTANT text := $a$    BEGIN
      UPDATE public.ottoq_stall_bookings b
         SET during = tstzrange(LEAST(lower(b.during), v_from),
                                GREATEST(upper(b.during), v_from + interval '1 minute'), '[)')
       WHERE b.booking_id = v_existing
         AND lower(b.during) > v_from;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ottoq_record_enacted_booking: could not widen adopted booking % (%): %',
        v_existing, SQLSTATE, SQLERRM;
    END;$a$;
  c_new CONSTANT text := $a$    BEGIN
      IF v_purpose IN ('wash','detail','service') THEN
        -- 0549 (G278): A BAY RESERVATION TAKEN EARLY MOVES TO NOW. The door pins the car's time in the
        -- bay to the booking's end, so stretching the reservation back to now kept the car in the bay
        -- until its old end, and when the stretch collided it was left in the future altogether. It
        -- keeps its own length, or the caller's window if longer; failing that, the caller's window,
        -- which the caller found free; failing that, it stays as it was.
        BEGIN
          UPDATE public.ottoq_stall_bookings b
             SET during = tstzrange(v_from,
                                    v_from + GREATEST(upper(b.during) - lower(b.during), v_to - v_from,
                                                      interval '1 minute'), '[)')
           WHERE b.booking_id = v_existing
             AND lower(b.during) > v_from;
        EXCEPTION WHEN OTHERS THEN
          UPDATE public.ottoq_stall_bookings b
             SET during = tstzrange(v_from, GREATEST(v_to, v_from + interval '1 minute'), '[)')
           WHERE b.booking_id = v_existing
             AND lower(b.during) > v_from;
        END;
      ELSE
        UPDATE public.ottoq_stall_bookings b
           SET during = tstzrange(LEAST(lower(b.during), v_from),
                                  GREATEST(upper(b.during), v_from + interval '1 minute'), '[)')
         WHERE b.booking_id = v_existing
           AND lower(b.during) > v_from;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'ottoq_record_enacted_booking: could not move or widen adopted booking % (%): %',
        v_existing, SQLSTATE, SQLERRM;
    END;$a$;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0549 (a): the adoption anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $adopt$;

-- ── (b) the needs-card seat asks for the leg's length from now, not until the leg's planned end ──
DO $seat$
DECLARE v_def text; n int;
  c_old CONSTANT text := $a$          SELECT l.leg_id, l.planned_end_sim INTO v_bay_leg_id, v_bay_until$a$;
  c_new CONSTANT text := $a$          -- 0549 (G278): the leg's length from now, not its planned end. A car seated now is
          -- served now; asking for the bay until a leg planned hours later held the bay until then.
          SELECT l.leg_id, v_clock + (l.planned_end_sim - l.planned_start_sim) INTO v_bay_leg_id, v_bay_until$a$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0549 (b): the seat anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $seat$;

-- ── V1 (comment-stripped): the move is there once for bay purposes, the stretch is kept for the rest, and the seat
--    asks for the leg's length ──
DO $verify$
DECLARE v_src text; v_tick text;
BEGIN
  v_src := regexp_replace(regexp_replace(pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure),
             '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'IF v_purpose IN \(''wash'',''detail'',''service''\) THEN\s+BEGIN\s+UPDATE public\.ottoq_stall_bookings b\s+SET during = tstzrange\(v_from,\s+v_from \+ GREATEST\(upper\(b\.during\) - lower\(b\.during\), v_to - v_from,\s+interval ''1 minute''\), ''\[\)''\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0549 V1: an adopted bay reservation does not move to now with its own length';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'SET during = tstzrange\(v_from, GREATEST\(v_to, v_from \+ interval ''1 minute''\), ''\[\)''\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0549 V1: the fallback to the caller''s window is missing';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src,
        'SET during = tstzrange\(LEAST\(lower\(b\.during\), v_from\),\s+GREATEST\(upper\(b\.during\), v_from \+ interval ''1 minute''\), ''\[\)''\)', 'g')) <> 1 THEN
    RAISE EXCEPTION '0549 V1: the stretch for every other purpose is not there exactly once';
  END IF;
  v_tick := regexp_replace(regexp_replace(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure),
              '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_tick,
        'SELECT l\.leg_id, v_clock \+ \(l\.planned_end_sim - l\.planned_start_sim\) INTO v_bay_leg_id, v_bay_until', 'g')) <> 1
     OR v_tick LIKE '%SELECT l.leg_id, l.planned_end_sim INTO v_bay_leg_id, v_bay_until%' THEN
    RAISE EXCEPTION '0549 V1: the needs-card seat does not ask for the leg''s length from now';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0549_a_car_seated_in_a_bay_early_is_served_now', true, true,
  'G278: (a) ottoq.ottoq_record_enacted_booking, adopting the car''s own reservation for a bay purpose (wash, detail, '
  'service) that starts after the car takes the bay, now MOVES it to start then, with its own length or the caller''s '
  'window if longer; failing that the caller''s window; failing that it stays, with the WARNING. Every other purpose is '
  'stretched as before. (b) public.ottoq_decide_tick''s needs-card seat asks for a planned bay leg''s length from now, '
  'not until the leg''s planned end. Before, a car seated early held its bay until its reservation''s end, because the '
  'door pins service_ends_at to the booking''s end (921e349c: Tesla-RT-003 232 minutes in WSH-02 for a 9-minute wash; '
  '4 early entries held the wash bays 465 minutes; 9 cars at 100% held 240 minutes at the gate for a wash or deep '
  'clean). No service is shortened.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended validation run 921e349c, a sim day after it ended so no booking of its own can collide.
--   Three twin cars, three wash bays and an L2, t = 2026-09-29 15:00 UTC:
--   (a) c1 holds a wash reservation on w1 at t+120..t+129 and c2 one at t+30..t+38. c1 takes w1 at t for 9 minutes:
--       c1's reservation is adopted and moves to t..t+9; c2's is untouched (the stretch would have collided with it);
--   (b) c1 holds a detail reservation on w2 at t+200..t+229 (29 minutes) and c2 one at t+27..t+35. c1 takes w2 at t
--       for 25 minutes: its own length collides, so it moves to the caller's t..t+25;
--   (c) c3 holds a detail reservation on w3 at t+300..t+329. c3 takes w3 at t for 25 minutes: it keeps its own length,
--       t..t+29;
--   (d) c2 holds a charge_l2 reservation on L2 l1 at t+60..t+120. c2 takes l1 at t for 30 minutes: it is stretched to
--       t..t+120, as before.
DO $v3$
DECLARE
  v_msg text; v_run uuid := '921e349c-ded0-4907-9e0b-6b288b61831f'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz := '2026-09-29 15:00:00+00';
  v_cars uuid[]; c1 uuid; c2 uuid; c3 uuid; w1 uuid; w2 uuid; w3 uuid; l1 uuid;
  ra uuid; rb uuid; rc uuid; rd uuid; oa uuid; ob uuid; ga uuid; gb uuid; gc uuid; gd uuid;
  da tstzrange; db tstzrange; dc tstzrange; dd tstzrange; doa tstzrange; dob tstzrange;
BEGIN
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run) THEN
      RAISE EXCEPTION '0549 V3: run % is gone; point V3 at a run that exists', v_run;
    END IF;
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' ORDER BY v.id LIMIT 3) q;
    c1 := v_cars[1]; c2 := v_cars[2]; c3 := v_cars[3];
    SELECT (array_agg(s.id ORDER BY s.id))[1], (array_agg(s.id ORDER BY s.id))[2], (array_agg(s.id ORDER BY s.id))[3]
      INTO w1, w2, w3 FROM public.stalls s WHERE s.depot_id = v_twin AND s.stall_type::text = 'wash_bay';
    SELECT s.id INTO l1 FROM public.stalls s WHERE s.depot_id = v_twin AND s.stall_type::text = 'l2' ORDER BY s.id LIMIT 1;
    IF c3 IS NULL OR w3 IS NULL OR l1 IS NULL THEN RAISE EXCEPTION '0549 V3: not enough twin cars or stalls'; END IF;

    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, w1, c1, 'wash',   tstzrange(t + interval '120 minutes', t + interval '129 minutes', '[)'), 'held')
    RETURNING booking_id INTO ra;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, w1, c2, 'wash',   tstzrange(t + interval '30 minutes',  t + interval '38 minutes', '[)'), 'held')
    RETURNING booking_id INTO oa;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, w2, c1, 'detail', tstzrange(t + interval '200 minutes', t + interval '229 minutes', '[)'), 'held')
    RETURNING booking_id INTO rb;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, w2, c2, 'detail', tstzrange(t + interval '27 minutes',  t + interval '35 minutes', '[)'), 'held')
    RETURNING booking_id INTO ob;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, w3, c3, 'detail', tstzrange(t + interval '300 minutes', t + interval '329 minutes', '[)'), 'held')
    RETURNING booking_id INTO rc;
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state)
    VALUES (v_run, l1, c2, 'charge_l2', tstzrange(t + interval '60 minutes', t + interval '120 minutes', '[)'), 'held')
    RETURNING booking_id INTO rd;

    ga := ottoq.ottoq_record_enacted_booking(v_run, w1, c1, t, NULL, t, t + interval '9 minutes',  'wash',      'needs_card');
    gb := ottoq.ottoq_record_enacted_booking(v_run, w2, c1, t, NULL, t, t + interval '25 minutes', 'detail',    'needs_card');
    gc := ottoq.ottoq_record_enacted_booking(v_run, w3, c3, t, NULL, t, t + interval '25 minutes', 'detail',    'needs_card');
    gd := ottoq.ottoq_record_enacted_booking(v_run, l1, c2, t, NULL, t, t + interval '30 minutes', 'charge_l2', 'needs_card');

    SELECT during INTO da  FROM public.ottoq_stall_bookings WHERE booking_id = ra;
    SELECT during INTO db  FROM public.ottoq_stall_bookings WHERE booking_id = rb;
    SELECT during INTO dc  FROM public.ottoq_stall_bookings WHERE booking_id = rc;
    SELECT during INTO dd  FROM public.ottoq_stall_bookings WHERE booking_id = rd;
    SELECT during INTO doa FROM public.ottoq_stall_bookings WHERE booking_id = oa;
    SELECT during INTO dob FROM public.ottoq_stall_bookings WHERE booking_id = ob;

    IF ga IS DISTINCT FROM ra OR da <> tstzrange(t, t + interval '9 minutes', '[)')
       OR doa <> tstzrange(t + interval '30 minutes', t + interval '38 minutes', '[)') THEN
      RAISE EXCEPTION '0549 V3 FAILED (a): adopted % (want %), c1 now %, c2 now %', ga, ra, da, doa;
    END IF;
    IF gb IS DISTINCT FROM rb OR db <> tstzrange(t, t + interval '25 minutes', '[)')
       OR dob <> tstzrange(t + interval '27 minutes', t + interval '35 minutes', '[)') THEN
      RAISE EXCEPTION '0549 V3 FAILED (b): adopted % (want %), c1 now %, c2 now %', gb, rb, db, dob;
    END IF;
    IF gc IS DISTINCT FROM rc OR dc <> tstzrange(t, t + interval '29 minutes', '[)') THEN
      RAISE EXCEPTION '0549 V3 FAILED (c): adopted % (want %), c3 now %', gc, rc, dc;
    END IF;
    IF gd IS DISTINCT FROM rd OR dd <> tstzrange(t, t + interval '120 minutes', '[)') THEN
      RAISE EXCEPTION '0549 V3 FAILED (d): adopted % (want %), the charge reservation now %', gd, rd, dd;
    END IF;

    RAISE EXCEPTION '0549 V3 PASSED: (a) a wash reservation taken early moved to now with its 9 minutes, beside another car''s booking the stretch would have hit; (b) a detail reservation whose own 29 minutes collided moved to the caller''s 25; (c) one with room kept its own 29; (d) a charge reservation was stretched as before';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0549 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0549 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0549_pre' as it is.

COMMIT;
