-- migration-version: 20260926063850
-- migration-name:    the_staging_hold_booked_stalls_promised_to_another_car_and_left_each_refused_booking_held
--
-- 0471  **The staging hold booked stalls promised to another car, and left each booking it could not use held until
--       its window ran out.** `db/checks/0358` §6-§7. FINDINGS G203.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`), read after its stop. 290 `temp_hold` bookings by `otto_q`; 58 of
--   them expired unused (`window_elapsed`) with no event ever putting the car on the stall, all but 8 on windows that
--   started the tick they were booked (the 8 started 36 s later, one tick). Stall pointer just before each booking,
--   rebuilt from the stall's own `stall.state_changed` diffs:
--
--       live reservation by ANOTHER car     34   (23 temp, 11 long)
--       a car on the stall                  18
--       free                                 6
--
--   Every one of the 58 held a staging stall on the calendar for 9-23 minutes for a car that never came.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   Two tick-path callers place a car with no stall the same way: `ottoq.ottoq_book_hold_stall` books a staging stall,
--   then `ottoq_reserve_stall` takes its pointer. They are `ottoq_decide_tick` (3) when the charge proposer abstains,
--   and `ottoq.ottoq_place_unplaced_vehicles`.
--
--   (a) The booking's candidate source is `ottoq.ottoq_stall_free_between`, which reads the calendar, the stall's
--       status, charger health and (behind `calendar_occupancy_guard`, on) the stall's current car. It never reads
--       `reserved_by`. A stall reserved by another car but with no booking covering the window is offered first when
--       it sorts first. That happens whenever a reservation outlives its booking: the refusal reactor reserves for
--       3,600 s beside a 60-minute booking, and a superseded command releases the booking but not the pointer.
--   (b) `ottoq_reserve_stall` then refuses (another car holds the pointer), and neither caller does anything with the
--       booking it just made. It stays `held`, excluded from every other car's search by the calendar, until
--       `ottoq.ottoq_release_expired_bookings` closes it as `window_elapsed`. The 18 car-on-stall cases fail the same
--       way: the occupancy guard trusts the car's planned leg end, and a car still on the stall at the end of its plan
--       passes the guard and fails the reserve.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   A. `ottoq.ottoq_find_and_book_stall` skips a candidate whose pointer is reserved by another car past the window's
--      start. The reservation is the pointer gate `ottoq_reserve_stall` applies (a NULL expiry is not a live
--      reservation there, and is not here). A stall reserved by the same car still books. This is the booking loop
--      behind every `ottoq_book_hold_stall` tier and `ottoq.ottoq_book_workflow_legs`; the shared candidate source
--      `ottoq_stall_free_between`, which knows no vehicle, is unchanged.
--   B. `ottoq_decide_tick` (3): when the reserve fails, the hold booking is released at once
--      (`reserve_refused_decide_tick`).
--   C. `ottoq.ottoq_place_unplaced_vehicles`: the same release when the reserve fails
--      (`reserve_refused_place_unplaced`), and when the arm refuses the move (`move_refused_on_arm`), where the
--      reservation this call just took is also cleared. The arm branch did not
--      fire on 317d4331 and is fixed because it is the same defect in the same function.
--
--   A car that is not placed this tick is tried again next tick, as before. What changes is that its failed attempt
--   no longer takes a staging stall away from every other car for the rest of the window.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Bookings (a determinism atom) and the stalls chosen for them move.
--
--   PREDICTED on the next busy_day run: `otto_q` `temp_hold` bookings released `window_elapsed` with the car never on
--   the stall drop from 58 to near 0, replaced by a small number released `reserve_refused_*` in the same tick.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0471 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured (after 0469) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_find_and_book_stall(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,text,text,uuid,uuid,text,text[])'::regprocedure))
     <> '9525912f3f4639444ac056dcfd41d5e4' THEN
    RAISE EXCEPTION '0471 P2: ottoq.ottoq_find_and_book_stall is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_place_unplaced_vehicles(uuid,uuid,timestamp with time zone,integer)'::regprocedure))
     <> '46812bd53fadc36ac9b6527532bb3735' THEN
    RAISE EXCEPTION '0471 P2: ottoq.ottoq_place_unplaced_vehicles is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> 'c9a11f010e622146397ce78a65f158f6' THEN
    RAISE EXCEPTION '0471 P2: public.ottoq_decide_tick is not the body this file patches';
  END IF;
  -- the pointer gate A mirrors: a NULL expiry is reservable, a live one by another car is not
  IF position($x$AND (reserved_by IS NULL OR reserved_by = p_vehicle_id
          OR reservation_expires_at IS NULL OR reservation_expires_at <= p_now)$x$
              IN pg_get_functiondef('public.ottoq_reserve_stall(uuid,uuid,timestamp with time zone,integer)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0471 P2: ottoq_reserve_stall no longer applies the pointer gate A mirrors';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0471_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('ottoq.ottoq_find_and_book_stall(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,text,text,uuid,uuid,text,text[])'::regprocedure,
                 'ottoq.ottoq_place_unplaced_vehicles(uuid,uuid,timestamp with time zone,integer)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure);

-- ── A: the booking loop skips a stall promised to another car ──
DO $patch_find$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_find_and_book_stall(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,text,text,uuid,uuid,text,text[])'::regprocedure);
  v_pat text := $p$LOOP\s+v_booking := ottoq\.ottoq_book_stall\($p$;
  v_new text := $r$LOOP
    -- 0471 (G203): the candidate source reads the calendar and not the pointer's reservation, so a stall another car
    -- holds a live reservation on was booked here and then refused by ottoq_reserve_stall. Same gate as that function:
    -- a live reservation by another car covering the window's start; a NULL expiry is not live.
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.stalls s
                           WHERE s.id = v_cand.stall_id
                             AND s.reserved_by IS NOT NULL AND s.reserved_by <> p_vehicle_id
                             AND s.reservation_expires_at > p_from);
    v_booking := ottoq.ottoq_book_stall($r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0471 A: the booking loop matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_find$;

-- ── B: the decide tick releases a hold it could not reserve ──
DO $patch_decide$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  v_pat text := $p$PERFORM ottoq\.ottoq_emit_vehicle_command\(p_sim_run_id, v_depot, v_req\.vehicle_id, 'proceed_to_stall',\s+jsonb_build_object\('stall_id', v_stage_stall, 'new_state', 'staged_awaiting_service'\), v_clock\);\s+END IF;$p$;
  v_new text := $r$PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'proceed_to_stall',
                          jsonb_build_object('stall_id', v_stage_stall, 'new_state', 'staged_awaiting_service'), v_clock);
                ELSE
                  -- 0471 (G203): the car is not going to this stall, so the hold is released now instead of keeping
                  -- the stall off the calendar for every other car until its window runs out.
                  UPDATE ottoq_stall_bookings
                     SET state = 'released', released_at = v_clock, release_reason = 'reserve_refused_decide_tick'
                   WHERE booking_id = (v_hold->>'booking_id')::uuid AND state = 'held';
                END IF;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0471 B: the abstain-branch hold matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_decide$;

-- ── C: place_unplaced releases a hold it could not use ──
DO $patch_place$
DECLARE
  v_def  text := pg_get_functiondef('ottoq.ottoq_place_unplaced_vehicles(uuid,uuid,timestamp with time zone,integer)'::regprocedure);
  v_pat1 text := $p$v_stall, p_sim_run_id, p_clock\) THEN\s+v_failed := v_failed \+ 1;\s+ELSE$p$;
  v_new1 text := $r$v_stall, p_sim_run_id, p_clock) THEN
          v_failed := v_failed + 1;
          -- 0471 (G203): the car stays on the arm, so neither the hold nor the reservation just taken will be used.
          UPDATE public.ottoq_stall_bookings
             SET state = 'released', released_at = p_clock, release_reason = 'move_refused_on_arm'
           WHERE booking_id = (v_hold->>'booking_id')::uuid AND state = 'held';
          UPDATE public.stalls
             SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
           WHERE id = v_stall AND reserved_by = v_rec.id AND current_vehicle_id IS NULL;
        ELSE$r$;
  v_pat2 text := $p$v_placed := v_placed \+ 1;\s+END IF;\s+ELSE\s+v_failed := v_failed \+ 1;\s+END IF;$p$;
  v_new2 text := $r$v_placed := v_placed + 1;
        END IF;
      ELSE
        v_failed := v_failed + 1;
        -- 0471 (G203): the reserve was refused (another car holds the pointer), so the hold is released now.
        UPDATE public.ottoq_stall_bookings
           SET state = 'released', released_at = p_clock, release_reason = 'reserve_refused_place_unplaced'
         WHERE booking_id = (v_hold->>'booking_id')::uuid AND state = 'held';
      END IF;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat1, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0471 C1: the arm-refusal branch matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat1, v_new1);
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat2, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0471 C2: the reserve-refused branch matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat2, v_new2);
  EXECUTE v_def;
END $patch_place$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f text := pg_get_functiondef('ottoq.ottoq_find_and_book_stall(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,text,text,uuid,uuid,text,text[])'::regprocedure);
  v_p text := pg_get_functiondef('ottoq.ottoq_place_unplaced_vehicles(uuid,uuid,timestamp with time zone,integer)'::regprocedure);
  v_d text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
BEGIN
  -- V1: the gate sits in the loop, before the booking call.
  IF v_f !~ $x$CONTINUE WHEN EXISTS \(SELECT 1 FROM public\.stalls s\s+WHERE s\.id = v_cand\.stall_id\s+AND s\.reserved_by IS NOT NULL AND s\.reserved_by <> p_vehicle_id\s+AND s\.reservation_expires_at > p_from\);\s+v_booking := ottoq\.ottoq_book_stall\($x$ THEN
    RAISE EXCEPTION '0471 V1: the booking loop is not the body this file writes';
  END IF;
  -- V2: each caller releases on both failure branches; 0467 and 0469 are still in the decide tick.
  IF (SELECT count(*) FROM regexp_matches(v_p, $x$release_reason = '(reserve_refused_place_unplaced|move_refused_on_arm)'$x$, 'g')) <> 2
     OR (SELECT count(*) FROM regexp_matches(v_d, $x$release_reason = 'reserve_refused_decide_tick'$x$, 'g')) <> 1
     OR position('0469 (G200): no command.' IN v_d) = 0
     OR position($x$'reason', 'gate_intake',   -- 0467 (G199)$x$ IN v_d) = 0 THEN
    RAISE EXCEPTION '0471 V2: a caller is not the body this file writes';
  END IF;
  -- V3: one overload each, same grants on the public function.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE (ns.nspname, p.proname) IN (('ottoq','ottoq_find_and_book_stall'), ('ottoq','ottoq_place_unplaced_vehicles'),
                                          ('public','ottoq_decide_tick'))) <> 3 THEN
    RAISE EXCEPTION '0471 V3: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_decide_tick(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0471 V3: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the three functions from ottoq_schema_snapshots label '0471_pre' (CREATE OR REPLACE; ACLs kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0471_the_staging_hold_booked_stalls_promised_to_another_car_and_left_each_refused_booking_held', true,
  'Tick path: ottoq_find_and_book_stall skips a stall reserved by another car; ottoq_decide_tick (3) and '
  'ottoq_place_unplaced_vehicles release a hold booking when the reserve or the arm refuses. Bookings move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
