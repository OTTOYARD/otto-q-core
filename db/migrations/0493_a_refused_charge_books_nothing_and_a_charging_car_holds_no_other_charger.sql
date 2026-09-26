-- migration-version: 20260926183701
-- migration-name:    a_refused_charge_books_nothing_and_a_charging_car_holds_no_other_charger
--
-- 0493  **The charge step never read the emission gate's answer, the gate intake could take a car the charge step had
--       just sent to a charger, and a car on a charger kept its hold on another (G226, G210, part of G195).**
--       `db/checks/0367`. Measured on the canon under 0492 (verdicts 375-383) and on operator run 461c79fa.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) G226. `ottoq_decide_tick` (3) reserves the proposal's charger, emits `begin_charge`, and then claims the kW,
--   starts the concurrent atoms, plans the itinerary, records the enacted booking and logs `enacted`, without reading
--   what the emission gate (`ottoq.ottoq_emit_vehicle_command`) did with the command. The gate refuses what
--   `ottoq_validate_assignment` refuses, here a live calendar booking held by another car: 57 of the 217 `begin_charge`
--   (3) issued on busy_day/171717/48 (verdict 383, each arm), 19-31 on every 12- and 24-tick arm, 5 of 75 on
--   461c79fa. Every one was logged `enacted`. `ottoq.ottoq_record_enacted_booking` then took the other car's booking
--   for a phantom (its car was not on the stall) and superseded it, 55 of the 57, and booked the refused car on a
--   charger it was not going to, 54 of the 57. That booking is the next car's refusal: 21 of the 57 bookings that
--   refused (3) on that arm had been left by an earlier refused (3) decision.
--
--   (b) G210, what remained of it. (3) charges a car below its visit target. `ottoq_derive_visit_needs` and 0486's
--   `ottoq_reassess_charge_needs` give a charge only below the target minus 1, and the gate intake (3b) takes a car
--   whose visit has no open charge. A car that reached the gate at the target minus 1 (84 against an immediate
--   dispatch target of 85, on every canon arm that had such a pair) was sent to an L2 by (3) and to staging by (3b)
--   in the same tick. The door (`twin.ottoq_sim_confirm_commands`) keeps the newest stall command, and on a tie of
--   `issued_at` the command type decides, so staging won and the begin_charge was retired `superseded`. None of those
--   cars was charged in the next three hours: the charger's reservation, its booking and its kW claim were left
--   behind, and the decision read `enacted`.
--
--   (c) Part of G195. When a car takes a charger, `ottoq_record_enacted_booking` releases its other `held` bookings of
--   the same purpose. `ottoq_plan_visit_itinerary` plans the charge leg as `charge_dcfc` below 45% SoC and `charge_l2`
--   above, a forward booking is made for that type, and (3) often puts the car on the other type, so the forward
--   booking stays held on a charger the car will not use. The refusal reactor's reroute books through
--   `ottoq_book_stall` and releases nothing. Of the 57 bookings that refused (3) on the 48-tick arm, 22 were such
--   forward bookings for a car (3) had put on the other type, and 5 were for a car a reroute had put on a charger.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) (3) reads the command it emitted. A refused command claims no kW, starts nothing, plans nothing and books
--   nothing. The reservation (3) took for it is released, and the decision is logged `deferred_stale_entity` (the
--   outcome (3) already uses when the reservation itself fails) with verb `charger_refused`, the gate's code and
--   detail, and the command id. The reactor reroutes the refusal as it did.
--   (b) (3) charges below the visit target minus 1, the deriver's rule. The re-assessment runs before the decide tick,
--   so at the gate (3) and (3b) now split the cars by one rule. The gate intake also skips a car that already holds a
--   stall command issued this tick, the guard 0472 gave the inspection seam, so the two cannot both take a car again.
--   (c) A car put on a charger by (3) (through `ottoq_record_enacted_booking`) or by a reroute the gate accepted
--   releases its other `held` charge bookings of either type, on stalls it is not standing on. A release across types
--   reads `superseded_by_enacted_other_charger` or `superseded_by_reroute`, so it can be told from the same-purpose one.
--
--   Not changed: the 8 forward bookings on that arm whose car had not charged anywhere (they may be the car's real
--   plan), and the appointment planner's pre-arrival commands, which the gate refuses for the same reason (19 on that
--   arm) and whose reroutes the door refuses for a car still on the road. Both are measured in 0367 §4.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   Commands, bookings, decisions and events move on every canon column that charges a car.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0493 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured, and the two facts it relies on ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> '03195b9839d6fe4cd767457537c0fecc' THEN
    RAISE EXCEPTION '0493 P2: public.ottoq_decide_tick is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure))
     <> '915693e1534d6c0eae346e30e7e7f0af' THEN
    RAISE EXCEPTION '0493 P2: ottoq.ottoq_record_enacted_booking is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure))
     <> '13ba72eb886ec7010c4f1f76a81d8b1d' THEN
    RAISE EXCEPTION '0493 P2: ottoq.ottoq_react_to_refusals is not the body this file patches';
  END IF;
  -- the rule (3) adopts is the deriver's
  IF position('IF v_soc < v_visit_target - 1 THEN' IN
       pg_get_functiondef('ottoq.ottoq_derive_visit_needs'::regproc)) = 0 THEN
    RAISE EXCEPTION '0493 P2: the visit deriver no longer charges below the target minus 1';
  END IF;
  -- the re-assessment still runs before the decide tick, so a car that needs a charge has its atom when (3b) looks
  IF strpos(pg_get_functiondef('public.ottoq_sim_decide_and_dispatch'::regproc), 'ottoq.ottoq_reassess_charge_needs(') = 0
     OR strpos(pg_get_functiondef('public.ottoq_sim_decide_and_dispatch'::regproc), 'ottoq.ottoq_reassess_charge_needs(')
        > strpos(pg_get_functiondef('public.ottoq_sim_decide_and_dispatch'::regproc), 'ottoq_decide_tick(p_sim_run_id)') THEN
    RAISE EXCEPTION '0493 P2: the re-assessment no longer runs before the decide tick';
  END IF;
  -- an accepted command is written with the column default
  IF (SELECT column_default FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'ottoq_vehicle_commands' AND column_name = 'status')
     IS DISTINCT FROM $d$'issued'::text$d$ THEN
    RAISE EXCEPTION '0493 P2: an accepted command no longer reads issued';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0493_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_decide_tick(uuid)'::regprocedure,
                 'ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure,
                 'ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure);

-- ── (a) and (b): the decide tick ──
DO $patch_tick$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  v_old text[] := ARRAY[
-- 1. four scalars for the command (3) emits
$o1$  v_charge_leg RECORD; v_bkg uuid;
$o1$,
-- 2. the charge rule
$o2$       AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0123 */
              ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc())
$o2$,
-- 3. the emit keeps its command id
$o3$        PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge',
$o3$,
-- 4. the gate's answer is read before anything is claimed or booked
$o4$      -- 0039: charge stall claim handled by twin on command confirmation
        PERFORM ottoq_claim_tick_kw(p_sim_run_id, v_tick, v_depot, (v_action->>'requested_kw')::numeric, v_req.vehicle_id);
$o4$,
-- 5. the enacted path closes
$o5$        v_outcome:='enacted'; v_enacted:=v_enacted+1;
        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>'requested_kw')::numeric,0);
$o5$,
-- 6. the gate intake skips a car already sent somewhere this tick
$o6$     ORDER BY v.last_state_change ASC NULLS FIRST, v.id   /* 0054: the sibling cursors' own fairness idiom, made explicit here too */
$o6$];
  v_new text[] := ARRAY[
$n1$  v_charge_leg RECORD; v_bkg uuid;
  v_cmd_id uuid; v_cmd_status text; v_cmd_code text; v_cmd_detail text; /* 0493 */
$n1$,
$n2$       -- 0493 (G210): the deriver's charge rule, below the visit target minus 1 (ottoq_derive_visit_needs and
       -- ottoq_reassess_charge_needs). At the target minus 1 the gate intake (3b) took the car as needing no charge
       -- while this cursor sent it to a charger, in the same tick.
       AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0123 */
              ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1
$n2$,
$n3$        v_cmd_id := ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge',
$n3$,
$n4$      -- 0039: charge stall claim handled by twin on command confirmation
        -- 0493 (G226): THE EMISSION GATE'S ANSWER IS READ. The gate refuses what ottoq_validate_assignment refuses,
        -- most often a live calendar booking held by another car. Everything below used to run anyway: the decision
        -- read enacted, the kW was claimed, and ottoq_record_enacted_booking superseded the other car's booking and
        -- booked this car on a charger it was not going to (57 of 217 on busy_day/171717/48, verdict 383). A refused
        -- command now claims, starts, plans and books nothing, the reservation taken above is released, and the
        -- refusal reactor reroutes it as before.
        SELECT c.status, c.reason_code, c.reason_detail INTO v_cmd_status, v_cmd_code, v_cmd_detail
          FROM public.ottoq_vehicle_commands c WHERE c.command_id = v_cmd_id;
        IF v_cmd_status = 'refused' THEN
          UPDATE public.stalls
             SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
           WHERE id = (v_action->>'stall_id')::uuid AND reserved_by = v_req.vehicle_id AND current_vehicle_id IS NULL;
          v_action := jsonb_build_object('verb', 'charger_refused', 'reason', COALESCE(v_cmd_code, 'refused'),
                                         'stall_type', v_action->>'stall_type', 'refused_detail', v_cmd_detail,
                                         'command_id', v_cmd_id);
          v_outcome := 'deferred_stale_entity'; v_deferred := v_deferred + 1;
        ELSE
        PERFORM ottoq_claim_tick_kw(p_sim_run_id, v_tick, v_depot, (v_action->>'requested_kw')::numeric, v_req.vehicle_id);
$n4$,
$n5$        v_outcome:='enacted'; v_enacted:=v_enacted+1;
        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>'requested_kw')::numeric,0);
        END IF;  -- 0493 (G226): the refused command's branch opens above the kW claim
$n5$,
$n6$       -- 0493 (G210): nothing else sent this car to a stall this tick. The charge step (3) runs first, and when both
       -- took a car the door kept one of the two by command type, not by what the car needed. 0472 gave the
       -- inspection seam the same guard.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc
                        WHERE vc.vehicle_id = v.id AND vc.sim_run_id = p_sim_run_id
                          AND vc.issued_at = v_clock AND vc.status = 'issued'
                          AND vc.payload ? 'stall_id')
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id   /* 0054: the sibling cursors' own fairness idiom, made explicit here too */
$n6$];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_old, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0493: decide-tick patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_old[i], v_new[i]);
  END LOOP;
  EXECUTE v_def;
END $patch_tick$;

-- ── (c) the enacted-booking seam: a charge hold of either type is the car's sibling ──
DO $patch_booking$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure);
  v_old text := $o$     SET state          = 'superseded',
         released_at    = p_clock,
         release_reason = 'superseded_by_enacted_same_purpose'
   WHERE b.sim_run_id = p_sim_run_id
     AND b.vehicle_id = p_vehicle_id
     AND b.purpose    = v_purpose
     AND b.stall_id  <> p_stall_id
$o$;
  v_new text := $n$     SET state          = 'superseded',
         released_at    = p_clock,
         release_reason = CASE WHEN b.purpose = v_purpose THEN 'superseded_by_enacted_same_purpose'
                               ELSE 'superseded_by_enacted_other_charger' END
   WHERE b.sim_run_id = p_sim_run_id
     AND b.vehicle_id = p_vehicle_id
     -- 0493 (G195): a charge is one need whichever charger serves it. The itinerary plans the leg as charge_dcfc below
     -- 45% SoC and charge_l2 above, the car is often put on the other type, and a same-purpose match left that hold.
     AND (b.purpose = v_purpose
          OR (b.purpose IN ('charge_dcfc','charge_l2') AND v_purpose IN ('charge_dcfc','charge_l2')))
     AND b.stall_id  <> p_stall_id
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0493: the sibling-hold release matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_booking$;

-- ── (c) the refusal reactor: a reroute onto a charger releases the car's other charge holds ──
DO $patch_reactor$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure);
  v_old text := $o$                 'reroute_reason', v_rec.reason_code),
          p_clock);
        v_outcome := jsonb_build_object('action','rerouted','new_command_id',v_new_cmd,
$o$;
  v_new text := $n$                 'reroute_reason', v_rec.reason_code),
          p_clock);
        -- 0493 (G195): a car a reroute puts on a charger holds no other charge hold. Its forward booking stayed held
        -- on a charger it was no longer going to (5 of the 57 bookings that refused the charge step on
        -- busy_day/171717/48 belonged to such a car).
        IF v_purpose IN ('charge_dcfc','charge_l2')
           AND (SELECT c.status FROM public.ottoq_vehicle_commands c WHERE c.command_id = v_new_cmd) = 'issued' THEN
          UPDATE public.ottoq_stall_bookings b
             SET state = 'superseded', released_at = p_clock, release_reason = 'superseded_by_reroute'
           WHERE b.sim_run_id = p_sim_run_id
             AND b.vehicle_id = v_rec.vehicle_id
             AND b.purpose IN ('charge_dcfc','charge_l2')
             AND b.stall_id <> v_new_stall
             AND b.state = 'held'
             AND NOT EXISTS (SELECT 1 FROM public.vehicles vx
                              WHERE vx.id = b.vehicle_id AND vx.current_stall_id = b.stall_id);
        END IF;
        v_outcome := jsonb_build_object('action','rerouted','new_command_id',v_new_cmd,
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0493: the reroute emit matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_reactor$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_tick    text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  v_reb     text := pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure);
  v_reactor text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure);
  v_f regprocedure;
BEGIN
  -- V1: (3) keeps the command id, reads its status before the kW claim, and closes the enacted path after it.
  IF position($x$v_cmd_id := ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge',$x$ IN v_tick) = 0
     OR position($x$PERFORM ottoq.ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge'$x$ IN v_tick) > 0
     OR NOT (position($x$IF v_cmd_status = 'refused' THEN$x$ IN v_tick)
               < position('PERFORM ottoq_claim_tick_kw(' IN v_tick)
             AND position('PERFORM ottoq_claim_tick_kw(' IN v_tick)
               < position('END IF;  -- 0493 (G226)' IN v_tick)
             AND position('ottoq.ottoq_record_enacted_booking(' IN v_tick)
               < position('END IF;  -- 0493 (G226)' IN v_tick)) THEN
    RAISE EXCEPTION '0493 V1: the charge step does not read the gate''s answer before it claims and books';
  END IF;
  -- V2: (3) charges below the target minus 1, once, and (3b) carries the guard, inside its own cursor.
  IF (length(v_tick) - length(replace(v_tick, 'public.ottoq_default_target_soc()) - 1', ''))) / length('public.ottoq_default_target_soc()) - 1') <> 1
     OR NOT (position('0493 (G210): nothing else sent this car' IN v_tick) > position('-- (3b) GATE INTAKE' IN v_tick)
             AND position('0493 (G210): nothing else sent this car' IN v_tick) < position($x$'reason', 'gate_intake',$x$ IN v_tick)) THEN
    RAISE EXCEPTION '0493 V2: the charge rule or the intake guard is not where this file puts it';
  END IF;
  -- V3: the enacted-booking seam and the reactor release a charge hold of either type.
  IF position($x$OR (b.purpose IN ('charge_dcfc','charge_l2') AND v_purpose IN ('charge_dcfc','charge_l2'))$x$ IN v_reb) = 0
     OR position('superseded_by_enacted_other_charger' IN v_reb) = 0
     OR position($x$release_reason = 'superseded_by_reroute'$x$ IN v_reactor) = 0 THEN
    RAISE EXCEPTION '0493 V3: a charge hold of the other type is still left behind';
  END IF;
  -- V4: privileges and security definer kept on all three (CREATE OR REPLACE keeps the ACL).
  FOREACH v_f IN ARRAY ARRAY['public.ottoq_decide_tick(uuid)'::regprocedure,
    'ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure,
    'ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure] LOOP
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
       OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
          <> (CASE WHEN v_f = 'public.ottoq_decide_tick(uuid)'::regprocedure
                   THEN 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
                   ELSE 'postgres=X/postgres,service_role=X/postgres' END) THEN
      RAISE EXCEPTION '0493 V4: % lost its privileges or security definer', v_f;
    END IF;
  END LOOP;
END $verify$;

-- Rollback: restore the three functions from ottoq_schema_snapshots label '0493_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0493_a_refused_charge_books_nothing_and_a_charging_car_holds_no_other_charger', true,
  'ottoq_decide_tick (3) reads the emission gate''s answer (a refused begin_charge books, claims and logs nothing as '
  'enacted), charges below the visit target minus 1, and (3b) skips a car already sent this tick. A car put on a '
  'charger releases its held charge bookings of either type. Commands, bookings, decisions and events move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
