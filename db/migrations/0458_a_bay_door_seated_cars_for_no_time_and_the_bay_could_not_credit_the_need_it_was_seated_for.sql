-- migration-version: 20260926033237
-- migration-name:    a_bay_door_seated_cars_for_no_time_and_the_bay_could_not_credit_the_need_it_was_seated_for
--
-- 0458  **A bay door seated cars for no time at all, and the bay could not credit the need a car was seated for, so
--       one car cycled through the wash bay 462 times in eleven sim-hours.** `db/checks/0355` §4–§5. FINDINGS G191.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 736406cf (busy_day, twin depot), live, 2026-09-23 06:40–06:47 UTC:
--     - 598 of 598 needs-card wash bookings closed `interrupted / bay_exit_before_planned_end` after 0.95 min of a
--       9-minute window (12 vehicles); 3 of 3 needs-card detail bookings likewise (0.85 min). Every other bay door
--       ran its full window (activated reservations 9.31 min wash, 20.53 detail; reconcile admits 8.71 / 44.57).
--     - Tesla-AV-062: 459 `replan_escalated` from 09:58 to 21:10 sim, each "attempts 3 of 3,
--       bounded_replan_then_flag"; Tesla-AV-054: 92 from 19:08.
--   Run 689095e2 (busy_day, 2026-09-25): the same door, 17 seats for 6 vehicles, each ejected in the instant it was
--   seated with `twin.service_completed {credited: [], self_healed: true}`.
--
-- ══ §2 THE MECHANISM: TWO DEFECTS THAT ARE EACH SURVIVABLE AND TOGETHER LOOP ══════════════════════════════════
--
--   (1) NO TIMER. Decide 4b (the needs card) books a bay and issues `enter_wash` / `enter_service`;
--       `twin.ottoq_sim_confirm_commands` executes it by writing `current_state = in_wash_bay` (0039) and nothing
--       else. `twin.ottoq_sim_advance_service_flow` STEP 1 completes any in-bay car whose `service_ends_at` is null
--       ("null-timer stuck") on its next pass, which is the same tick. 0016 closed exactly this seam for
--       `ottoq_activate_due_bay_reservations` ("turned a 38-minute service into 2 minutes") by writing `svc_step`
--       and `service_ends_at` pinned to the booking's own end; the command door never got it.
--   (2) NO CREDIT. The card admits a car for a need read from its LIVE condition. AV-062's wash fell due at 20:12
--       sim, eleven hours after its visit was derived, so the visit manifest had no exterior_wash atom. The bay
--       credits `bay_capable ∩ (outstanding atoms ∪ technician flag)` (0009): {exterior_wash, sensor_clean} ∩
--       {readiness_check, interior_deep_clean} = {}. Nothing reset its soil, so the card re-admitted it next tick.
--   (1) alone made every needs-card wash one tick long but credited the ones on the manifest. (2) alone would
--   have cost one uncredited 9-minute wash. Together: an endless two-tick loop that also burned the wash bay.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `twin.ottoq_sim_confirm_commands`, where a command seats a car in a bay: the 0016 contract, verbatim in
--       meaning. `svc_step` = 'washing' / 'servicing'; `service_ends_at` = the booking's own end (payload
--       `booking_id`), else now + the lane's duration from `ottoq_sim_service_minutes` (the service flow's own
--       numbers: wash 9, detail 25, maintenance 40), floored one minute ahead so a seat cannot complete on the tick
--       that made it. And `bay_need` = {svc: payload `need`, ends_at: the same timer text}. The seated booking goes
--       `held -> active`, as 0016's door does ("the reservation is now a REAL occupancy"), so the calendar sweep
--       closes it `done` when the car leaves on time and `interrupted` only when it does not.
--   (b) `twin.ottoq_sim_advance_service_flow` STEP C: the need the car was seated for is real work, exactly as
--       0009 made a technician's `wash_due` flag real work. It joins the credit set only while `bay_need.ends_at`
--       equals the timer the car is exiting on, so a stale need from an earlier seat can never be credited by a
--       later one; the exit clears `bay_need` with the other seat keys. The intersection with what the bay can do
--       is unchanged: a wash bay still cannot credit a deep clean.
--
--   Not changed: which cars decide 4b admits, the loop bound (its flag is still read by nothing that admits a car;
--   with (a) and (b) the loop cannot form by this route, and wiring the flag into decide 4b is recorded as G191's
--   residual), and STEP 1's null-timer self-heal, which still guards any door that forgets the contract.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Both functions run on every world tick. Needs-card seats now last their booking instead of one tick, and
--   credit what they were for, so bookings, events, SDRs and the end state all move. The recertification runner
--   re-certifies every canon column against the new floor.
--
--   PREDICTED on the next busy_day run: 0 needs-card bookings closing `interrupted` after under a minute; no
--   vehicle with more than a handful of `replan_escalated`; needs-card washes closing `done` at ~9 minutes and
--   crediting `exterior_wash`; wash-bay minutes spent on needs-card seats roughly 43 × 9 ≈ 390 against 598 × 0.95
--   ≈ 570 on 736406cf, so bay capacity is freed, not consumed.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0458 P0: a pair is running right now'; END IF;
END $inflight$;

-- ── P2: the two bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure))
     <> '682866083aee6c99d7ddd39de82f3596' THEN
    RAISE EXCEPTION '0458 P2: twin.ottoq_sim_confirm_commands is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure))
     <> '148f27d6ff3219e433424b83ae85517a' THEN
    RAISE EXCEPTION '0458 P2: twin.ottoq_sim_advance_service_flow is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0458_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure,
                 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);

-- ═══ (a) the command door writes the bay contract ═════════════════════════════════════════════════════════════
DO $patch_confirm$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure);
  v_pat_decl text := $p$v_new_state text;\s+-- 0039 completion: the state this command puts the vehicle in$p$;
  v_pat_seat text := $p$UPDATE vehicles\s+SET current_state\s+= v_new_state::vehicle_state,\s+last_state_change = v_now,\s+current_stall_id\s+= CASE WHEN v_rec\.payload \? 'stall_id'\s+THEN \(v_rec\.payload->>'stall_id'\)::uuid\s+ELSE current_stall_id END\s+WHERE id = v_rec\.vehicle_id;$p$;
  v_new_decl text := $r$v_new_state text;      -- 0039 completion: the state this command puts the vehicle in
  v_bay_end   timestamptz;  -- 0458 (G191): when this bay seat's contract says it ends$r$;
  v_new_seat text := $r$-- ══════ 0458 (G191): A SEAT IN A BAY CARRIES THE BAY CONTRACT ══════
        -- This door wrote the state and nothing else, and the service flow's STEP 1 completes an
        -- in-bay car with a null timer on its next pass -- the seam 0016 closed for
        -- ottoq_activate_due_bay_reservations and never here. Every needs-card seat on 736406cf
        -- lasted 0.95 min of 9. Same keys as 0016 and the twin's own admission: svc_step, and
        -- service_ends_at pinned to the booking's end (else the lane's own duration), floored one
        -- minute ahead. bay_need records what the seat is FOR, bound to this timer, so the exit can
        -- credit it (0458 (b)) and a stale one from an earlier seat never can.
        v_bay_end := NULL;
        IF v_new_state IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
          SELECT upper(b.during) INTO v_bay_end
            FROM ottoq_stall_bookings b
           WHERE b.booking_id = NULLIF(v_rec.payload->>'booking_id','')::uuid;
          v_bay_end := GREATEST(
                         COALESCE(v_bay_end,
                                  v_now + make_interval(secs => 60 * CASE v_new_state
                                    WHEN 'in_wash_bay'   THEN ottoq_sim_service_minutes(p_sim_run_id, 'wash_time', 9)
                                    WHEN 'in_detail_bay' THEN ottoq_sim_service_minutes(p_sim_run_id, 'detail_time', 25)
                                    ELSE ottoq_sim_service_minutes(p_sim_run_id, 'maintenance_time', 40) END)),
                         v_now + interval '1 minute');
        END IF;
        UPDATE vehicles
           SET current_state     = v_new_state::vehicle_state,
               last_state_change = v_now,
               current_stall_id  = CASE WHEN v_rec.payload ? 'stall_id'
                                        THEN (v_rec.payload->>'stall_id')::uuid
                                        ELSE current_stall_id END,
               config            = CASE WHEN v_bay_end IS NULL THEN config
                                        ELSE (COALESCE(config, '{}'::jsonb) - 'bay_need')
                                             || jsonb_strip_nulls(jsonb_build_object(
                                                  'svc_step', CASE WHEN v_new_state = 'in_service_bay'
                                                                   THEN 'servicing' ELSE 'washing' END,
                                                  'service_ends_at', v_bay_end::text,
                                                  'bay_need', CASE WHEN NULLIF(v_rec.payload->>'need','') IS NULL THEN NULL
                                                                   ELSE jsonb_build_object('svc', v_rec.payload->>'need',
                                                                                           'ends_at', v_bay_end::text) END)) END
         WHERE id = v_rec.vehicle_id;
        -- The reservation is now a real occupancy, exactly as 0016 stamps it: held -> active, so
        -- the calendar sweep closes it done on time and interrupted only when it is cut short.
        IF v_bay_end IS NOT NULL THEN
          UPDATE ottoq_stall_bookings
             SET state = 'active', booked_by = 'otto_q_enacted'
           WHERE booking_id = NULLIF(v_rec.payload->>'booking_id','')::uuid
             AND state = 'held';
        END IF;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_decl, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0458 (a): the declaration matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_seat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0458 (a): the seat UPDATE matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat_decl, v_new_decl);
  v_def := regexp_replace(v_def, v_pat_seat, v_new_seat);
  EXECUTE v_def;
END $patch_confirm$;

-- ═══ (b) the bay credits the need it was seated for ════════════════════════════════════════════════════════════
DO $patch_flow$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  v_pat_flag  text := $p$v_flag_svcs := CASE WHEN v_rec\.config->>'flagged_issue_type' = 'wash_due'\s+THEN ARRAY\['exterior_wash'\] ELSE ARRAY\[\]::text\[\] END;$p$;
  v_pat_strip text := $p$- 'service_done' - 'awaiting_external_completion'$p$;
  v_new_flag  text := $r$v_flag_svcs := CASE WHEN v_rec.config->>'flagged_issue_type' = 'wash_due'
                        THEN ARRAY['exterior_wash'] ELSE ARRAY[]::text[] END;
    -- 0458 (G191): THE NEED A CAR WAS SEATED FOR IS REAL WORK TOO, for the same reason the
    -- technician flag is. The needs card seats a car for a need read from its live condition,
    -- which can arise after the visit was derived and so be on no manifest: 736406cf's AV-062
    -- was seated 462 times for an overdue wash its visit never listed, credited nothing each
    -- time, and was re-seated. Credited only while bound to the timer this car is exiting on,
    -- so a stale need from an earlier seat cannot ride on a later one; the bay's own
    -- capability set still decides what can be credited at all.
    IF NULLIF(v_rec.config->'bay_need'->>'svc', '') IS NOT NULL
       AND v_rec.config->'bay_need'->>'ends_at' IS NOT DISTINCT FROM v_rec.config->>'service_ends_at' THEN
      v_flag_svcs := v_flag_svcs || ARRAY[v_rec.config->'bay_need'->>'svc'];
    END IF;$r$;
  v_new_strip text := $r$- 'service_done' - 'awaiting_external_completion' - 'bay_need'$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_flag, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0458 (b): the flag credit matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_strip, 'g');
  IF n <> 2 THEN RAISE EXCEPTION '0458 (b): the exit key strip matched % times, not twice', n; END IF;
  v_def := regexp_replace(v_def, v_pat_flag, v_new_flag);
  v_def := regexp_replace(v_def, v_pat_strip, v_new_strip, 'g');
  EXECUTE v_def;
END $patch_flow$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_c text; v_f text;
BEGIN
  v_c := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure);
  v_f := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  -- V1: the contract is written where a command seats a car, and the booking is activated there.
  IF position('0458 (G191): A SEAT IN A BAY CARRIES THE BAY CONTRACT' IN v_c) = 0
     OR position($x$'service_ends_at', v_bay_end::text$x$ IN v_c) = 0
     OR position($x$SET state = 'active', booked_by = 'otto_q_enacted'$x$ IN v_c) = 0 THEN
    RAISE EXCEPTION '0458 V1: the confirm patch is not in the live body';
  END IF;
  -- V2: the credit reads the bound need, and both exits strip it.
  IF position($x$v_flag_svcs := v_flag_svcs || ARRAY[v_rec.config->'bay_need'->>'svc']$x$ IN v_f) = 0
     OR (SELECT count(*) FROM regexp_matches(v_f, $x$- 'awaiting_external_completion' - 'bay_need'$x$, 'g')) <> 2 THEN
    RAISE EXCEPTION '0458 V2: the service-flow patch is not in the live body';
  END IF;
  -- V3: nothing else about either function moved -- still one overload each, same ACL.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'twin' AND p.proname IN ('ottoq_sim_confirm_commands','ottoq_sim_advance_service_flow')) <> 2 THEN
    RAISE EXCEPTION '0458 V3: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0458 V3: the confirm ACL moved';
  END IF;
END $verify$;

-- Rollback: restore both functions from ottoq_schema_snapshots label '0458_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0458_a_bay_door_seated_cars_for_no_time_and_the_bay_could_not_credit_the_need_it_was_seated_for', true,
  'Tick path: twin.ottoq_sim_confirm_commands now writes the bay contract (svc_step, service_ends_at, bay_need) and '
  'activates the seated booking; twin.ottoq_sim_advance_service_flow credits the bound need. Needs-card bay seats '
  'last their booking and credit their need, so bookings, events, SDRs and end state move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
