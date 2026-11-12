-- migration-version: 20261112140245
-- migration-name:    0817_the_wash_bay_is_exterior_only_and_cabin_work_is_done_at_a_fast_charger_post
--
-- 0817  **The wash bay is exterior only, and a car's cabin work is done at a fast-charger post.**
--
-- WHY. Chase, 2026-11-12 (morning, CT): "the washbay is only for external washing and then the sensor/camera detail
-- ... If the vehicle needs full detail, being interior and exterior, then it should first go to a charging post with the
-- overhead vacuum, have the interior complete, and then proceed to the washbay for external detail ... I'm just trying
-- to remove opening the doors in any fashion away from the wash base since there is water and dampness occurring."
-- And, the same morning, to the two questions put to him: "Yes to both, go and build" (no charge threshold, 100% stays;
-- the routine sensor clean stays at the charger), with "any interior cleaning goes straight to the charging post for the
-- vacuum overhead ... Any external washing goes to a bay with the detailed polish off".
--
-- §1 WHAT WAS SO, measured on run 5480be1f (twin depot, the first run after 0816; db/checks/0483 §3): 17 detail seats
--   in a wash bay. I had read them from the source as the technician flags' door (minor_cosmetic, wash_due). MEASURED,
--   that was wrong: no seat on that run came from a flag. The two real doors, from each seat's own booking:
--   (a) 9 seats, source needs_card, need interior_deep_clean, NO visit atom. The needs card reads the car's live
--       condition, so a deep clean falls due on a car whose visit never had the atom: 3 boot cars at 88-90%, 1 at 86%,
--       and 5 cars at 100% whose charge was done. 0816's test reads a visit atom, so it never saw them.
--   (b) 8 seats, source bay_reservation_activated_early, need_source visit_atom. The planner reserved a wash bay for
--       the deep clean when the visit was planned. The post's arm then did the clean, the reservation stayed held, and
--       the bay seated the car 30 to 320 minutes after its cabin was clean. 16.5 minutes of a wash bay for nothing.
--
-- §2 WHAT THIS DOES. All of it is behind a new dial, wash_bay_exterior_only (default 0; 1 at the twin depot), which
--   also needs cabin_robot_deep_clean and stall_cabin_robot on (public.ottoq_wash_bay_exterior_only).
--   (a) NO CABIN WORK IS ROUTED TO A WASH BAY. public.ottoq_deep_clean_waits_for_post is true for every car, so the
--       service flow's wash lane, the needs card's space routing (4b), the charge disposition (4) and the seat's kind
--       (ottoq_visit_wants_detail) all leave the deep clean to a post. A seat in a wash bay is a wash seat.
--   (b) THE TECHNICIAN FLAGS. wash_due is an exterior wash and takes a wash seat. minor_cosmetic takes no seat: it is
--       cosmetic damage to the body, which no bay repairs (0009 GAP 1), and it stays a note for a person. Chase read it
--       as an interior flag; it is not, and nothing here treats it as one.
--   (c) A WASH BAY HELD FOR CABIN WORK IS RELEASED. Each decide tick releases the run's held 'detail' bookings on wash
--       bays (door (b) of §1). The car's exterior wash, if it has one, is seated by the walk-in doors as any wash is.
--   (d) THE CABIN STOP. A parked car (staged_awaiting_service) with an interior deep clean to do and no charge to do
--       (at or above its target minus 1, the charge cursor's own line, so each car is one door's) is sent to a free
--       fast-charger post and stands there, not plugged in, while the post's arm runs the deep program. It is seated
--       through the engine's own command door (proceed_to_stall, state charge_complete_holding: a car on a charger
--       with no charge under way), with the post reserved and booked on the calendar. The arm's starter takes a car so
--       marked; the mover's hold keeps it on the post until the arm is home; the post is then freed and the car is
--       section (4)'s, which sends it to a wash bay if it has an exterior wash to do. Interior first, then exterior.
--       A deep clean the needs card raised with no atom on the visit is written to the car's open visit as a must-do
--       atom (or to a new visit when none is open, as the rider-flag sweep does), so the arm, the departure test and
--       the service record all see it.
--   (e) WHO GETS A POST. A charging car is never refused a post for a cabin stop: stops are seated after the charge
--       step (3) and the gate intake (3b), on a post still free. One exception, so no car starves: a car that has
--       waited charge_wait_floor_min (90) for its cabin stop is seated before the charge step. A stop holds its post
--       for the program (10.8 minutes) and about two ticks. Rule 14: the order is by wait, and reads no owner.
--
-- §3 RULE 9, CHECKED. No service is skipped, shortened or deferred past departure: the deep clean stays (or becomes) a
--   must-do atom, and 0543's departure test keeps the car until it is done. No charge is touched: a car below its
--   target is the charge step's, and a car on a cabin stop is at its target. Queueing for a post is queueing.
--   RULE 13: nothing here reads a power figure. RULE 8: the twin depot.
--
-- §4 WHAT THIS DOES NOT DO.
--   - It does not plug in a car on a cabin stop. A charger will not start a session at the target (0446, G179), and
--     with the target at 100 (0539) a car with no charge to do is full. Chase's "top off while it is there" is what the
--     charge step already does for every car below its target, on whichever charger it gets.
--   - It does not prefer a fast charger for a car that has both a charge and a deep clean to do. Such a car that
--     charges on an L2 (no arm) takes a cabin stop afterwards. Not measured how often.
--   - It does not stop the planner reserving a wash bay for a deep clean; it releases the reservation (§2 (c)).
--   - The routine sensor clean stays at the charger, by a technician (Chase, the same morning). The twin shows no
--     machine for it.
--   - A post whose charger is Faulted is not used for a stop, though its arm may be fit. The arm has no state of its
--     own in the engine.
--
-- §5 PRECONDITIONS AND CHECKS. P0 nothing in flight, no run live. P1 the bodies this file was written against, and
--   0816 applied. P2 once. V1 each patched body with its patches reversed is its pre-image. V2 every anchor matched
--   the number of times it names. V3 the behaviour, staged on a past run inside a block that is rolled back.
--     twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)   d96b1456ad268de7fd7458beffef0881
--     public.ottoq_decide_tick(uuid)                                       544c41b17aadb9860a4a6752d54f9f10
--     twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)                 46e591cf3489a8b29cc3dcf4c0a08ac9
--     public.ottoq_start_concurrent_atoms(uuid,timestamptz)                6e70f6eb180101cea1dd43e592052378
--     public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)          7b56721a38ccd720d2919cffd5fca495
--     ottoq.ottoq_uplink_transfer_holds(uuid,uuid)                         dfd5d9d7b68066b2e933f5056bcaaceb
--     public.ottoq_deep_clean_waits_for_post(uuid,uuid)                    496773fc2b8ea7a06697ce2ddb686178
--
-- §6 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: at wash_bay_exterior_only 0 (the default, and
--   what every certification arm and dial experiment runs at) the helper is false, the two flag tests return what the
--   lines they replace returned, and no new branch is reached. ON at the twin depot (rule 12).
--
-- ROLLBACK: EXECUTE the seven `definition`s in ottoq_schema_snapshots WHERE label = '0817_pre'; DROP the six functions
--   this file creates; DELETE the dial's rows from ottoq_policy_params and ottoq_policy_param_catalog; DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0817_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0817 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0817 P0: a run is live. V3 stages a past run as running, so apply between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against ──
DO $p1$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 'd96b1456ad268de7fd7458beffef0881'),
      ('public.ottoq_decide_tick(uuid)',                                     '544c41b17aadb9860a4a6752d54f9f10'),
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',               '46e591cf3489a8b29cc3dcf4c0a08ac9'),
      ('public.ottoq_start_concurrent_atoms(uuid,timestamptz)',              '6e70f6eb180101cea1dd43e592052378'),
      ('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)',        '7b56721a38ccd720d2919cffd5fca495'),
      ('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)',                       'dfd5d9d7b68066b2e933f5056bcaaceb'),
      ('public.ottoq_deep_clean_waits_for_post(uuid,uuid)',                  '496773fc2b8ea7a06697ce2ddb686178')) v(fn, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0817 P1: % is not the body this file was written against', r.fn;
    END IF;
  END LOOP;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0817_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'wash_bay_exterior_only') THEN
    RAISE EXCEPTION '0817 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0817_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure,
                 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure,
                 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure,
                 'ottoq.ottoq_uplink_transfer_holds(uuid,uuid)'::regprocedure,
                 'public.ottoq_deep_clean_waits_for_post(uuid,uuid)'::regprocedure);

-- ── the dial ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('wash_bay_exterior_only',
   '0817: 1 = the wash bay does exterior work only (the wash, then the sensor polish), and no door opens there. A '
   'car''s interior deep clean is done at a fast-charger post by the post''s cleaning arm: while it charges there, or, '
   'for a car with no charge to do, on a cabin stop (the car stands on a free post, not plugged in, for the arm''s '
   'program). The wash_due flag takes a wash seat and minor_cosmetic takes no seat. A wash bay held for cabin work is '
   'released (Chase, 2026-11-12). 0 = as before 0817. Needs cabin_robot_deep_clean at 1 and stall_cabin_robot at 1 or 2.',
   0, 0, 1,
   'public.ottoq_wash_bay_exterior_only; public.ottoq_cabin_post_stops; public.ottoq_deep_clean_waits_for_post; '
   'public.ottoq_decide_tick; twin.ottoq_sim_advance_service_flow; public.ottoq_start_concurrent_atoms', false);

-- ── the one test: the wash bay is exterior only in this run ──
CREATE FUNCTION public.ottoq_wash_bay_exterior_only(p_sim_run_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0817: the wash bay does exterior work only. True when the dial is on and the fast chargers' cleaning arms do the
  -- interior deep clean (0815's dial, and stalls that have arms): without the arms there is nowhere else for the
  -- cabin work to go, and the dial alone changes nothing.
  SELECT COALESCE(public.ottoq_policy_get(p_sim_run_id, 'wash_bay_exterior_only', 0), 0) >= 1
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_deep_clean', 0), 0) >= 1
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 1;
$function$;

COMMENT ON FUNCTION public.ottoq_wash_bay_exterior_only(uuid) IS
  '0817: the wash bay does exterior work only in this run (wash_bay_exterior_only, with cabin_robot_deep_clean and '
  'stall_cabin_robot on). Every door into a wash bay reads this one test.';

-- ── the technician flags' two doors ──
CREATE FUNCTION public.ottoq_flag_wants_wash_bay(p_sim_run_id uuid, p_config jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0817: does the car's technician flag send it to a wash bay? As before 0817, wash_due and minor_cosmetic both do.
  -- With the wash bay exterior only, wash_due does (it is an exterior wash) and minor_cosmetic does not: no bay
  -- repairs cosmetic damage (0009 GAP 1), and the flag stays a note for a person.
  SELECT COALESCE(CASE WHEN public.ottoq_wash_bay_exterior_only(p_sim_run_id)
                       THEN p_config->>'flagged_issue_type' = 'wash_due'
                       ELSE p_config->>'flagged_issue_type' IN ('minor_cosmetic', 'wash_due') END, false);
$function$;

CREATE FUNCTION public.ottoq_flag_wants_detail_seat(p_sim_run_id uuid, p_config jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0817: does the car's technician flag make its wash-bay seat a detail seat? As before 0817, either flag does. With
  -- the wash bay exterior only, no seat there is a detail seat.
  SELECT COALESCE(NOT public.ottoq_wash_bay_exterior_only(p_sim_run_id)
                  AND p_config->>'flagged_issue_type' IN ('minor_cosmetic', 'wash_due'), false);
$function$;

-- ── (a) the deep clean is the post's, for every car ──
CREATE OR REPLACE FUNCTION public.ottoq_deep_clean_waits_for_post(p_sim_run_id uuid, p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0816: true when the fast chargers' cleaning arms do the interior deep clean (0815's dial, and stalls that have
  -- arms), and this car's open visit in the run has a deep clean still to do and a charge still to do. Such a car is
  -- going to a charger, and at a fast-charger post the arm does the clean while the car charges. False the moment the
  -- charge is done: a deep clean the arm did not do is then the detail seat's, so the service is never left undone.
  -- 0817: with the wash bay exterior only, true for every car: no deep clean is a wash bay's. A car with no charge to
  -- do takes a cabin stop at a post (public.ottoq_cabin_post_stops), so the service is still never left undone.
  SELECT public.ottoq_wash_bay_exterior_only(p_sim_run_id)
      OR (COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_deep_clean', 0), 0) >= 1
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 1
     AND EXISTS (
       SELECT 1 FROM public.ottoq_visit_needs vn
        WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress')
          AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) d
                       WHERE d->>'svc' = 'interior_deep_clean'
                         AND COALESCE(d->>'status','pending') NOT IN ('done','cancelled','skipped'))
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) c
                       WHERE c->>'svc' = 'charge'
                         AND COALESCE(c->>'status','pending') NOT IN ('done','cancelled','skipped'))));
$function$;

-- ── (d) the cabin stop: its mark on the visit ──
CREATE FUNCTION public.ottoq_cabin_stop_mark(p_sim_run_id uuid, p_depot uuid, p_vehicle uuid, p_clock timestamptz,
                                             p_stall uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_visit uuid; v_atoms jsonb; v_ord bigint; v_mark jsonb; v_atom jsonb; v_key text;
BEGIN
  -- 0817: the car's interior deep clean, on its open visit in this run, as a must-do atom; with p_stall, marked for a
  -- cabin stop at that post. Returns the visit, or NULL when the visit's deep clean still waits on its triage.
  v_mark := CASE WHEN p_stall IS NULL THEN '{}'::jsonb
                 ELSE jsonb_build_object('cabin_stop_stall_id', p_stall, 'cabin_stop_at', p_clock) END;
  SELECT n.visit_id, n.atoms INTO v_visit, v_atoms
    FROM public.ottoq_visit_needs n
   WHERE n.vehicle_id = p_vehicle AND n.status IN ('open','in_progress') AND n.sim_run_id = p_sim_run_id
   ORDER BY n.created_at DESC, n.visit_key DESC LIMIT 1;
  IF v_visit IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_atoms, '[]'::jsonb)) e
                WHERE e->>'svc' = 'interior_deep_clean' AND COALESCE(e->>'status','pending') = 'pending'
                  AND COALESCE((e->>'confirm_required')::boolean, false)) THEN
      RETURN NULL;
    END IF;
    SELECT min(x.o) INTO v_ord
      FROM jsonb_array_elements(COALESCE(v_atoms, '[]'::jsonb)) WITH ORDINALITY x(e, o)
     WHERE x.e->>'svc' = 'interior_deep_clean' AND COALESCE(x.e->>'status','pending') = 'pending';
    IF v_ord IS NOT NULL THEN
      UPDATE public.ottoq_visit_needs n
         SET atoms = (SELECT jsonb_agg(CASE WHEN x.o = v_ord
                                            THEN x.e || jsonb_build_object('must_do', true) || v_mark
                                            ELSE x.e END ORDER BY x.o)
                        FROM jsonb_array_elements(n.atoms) WITH ORDINALITY x(e, o))
       WHERE n.visit_id = v_visit;
      RETURN v_visit;
    END IF;
  END IF;
  v_atom := jsonb_build_object(
      'svc', 'interior_deep_clean', 'must_do', true, 'deferrable', false, 'est_min', 16, 'concurrency', 'bay',
      'requires_bay', 'detail', 'carryover_eligible', false, 'raised_in_depot', true,
      'why', 'The needs card found an interior deep clean due while the car was in the depot. The cleaning arm of a '
             || 'fast-charger post does it (0817).') || v_mark;
  IF v_visit IS NOT NULL THEN
    UPDATE public.ottoq_visit_needs n SET atoms = COALESCE(n.atoms, '[]'::jsonb) || v_atom WHERE n.visit_id = v_visit;
    RETURN v_visit;
  END IF;
  -- no open visit in the run: open one whose whole content is the clean, as the rider-flag sweep does (0020)
  v_key := p_vehicle::text || ':cs:' || to_char(p_clock, 'YYYYMMDDHH24MISS');
  INSERT INTO public.ottoq_visit_needs
         (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency, atoms, status, source, meta)
  VALUES (p_vehicle, p_sim_run_id, p_depot, p_clock, v_key, 'C_cabin_stop', 'standard', jsonb_build_array(v_atom),
          'open', 'cabin_post_stop', jsonb_build_object('generator', 'ottoq_cabin_stop_mark'))
  ON CONFLICT (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  DO UPDATE SET atoms = EXCLUDED.atoms, status = 'open', meta = EXCLUDED.meta
  RETURNING visit_id INTO v_visit;
  RETURN v_visit;
END;
$function$;

-- ── (d) the cabin stop: its end ──
CREATE FUNCTION public.ottoq_cabin_stop_release(p_sim_run_id uuid, p_vehicle uuid, p_visit uuid, p_stall uuid,
                                                p_clock timestamptz)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- 0817: the post is free again and the car points at no stall, as after a charge arm's demate
  -- (ottoq_release_expired_tethers writes the same two rows). The booking closes at the true end of the stay; one
  -- whose car never arrived is released. The atom keeps the post it was cleaned on, and loses the mark.
  UPDATE public.stalls s
     SET current_vehicle_id = NULL,
         status = CASE WHEN s.status = 'occupied' THEN 'available' ELSE s.status END
   WHERE s.id = p_stall AND s.current_vehicle_id = p_vehicle;
  UPDATE public.stalls s
     SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE s.id = p_stall AND s.reserved_by = p_vehicle;
  UPDATE public.vehicles v SET current_stall_id = NULL WHERE v.id = p_vehicle AND v.current_stall_id = p_stall;
  UPDATE public.ottoq_stall_bookings b
     SET state = CASE WHEN lower(b.during) < p_clock THEN 'done' ELSE 'released' END,
         released_at = p_clock, release_reason = 'cabin_stop_ended',
         during = CASE WHEN lower(b.during) < p_clock
                       THEN tstzrange(lower(b.during),
                                      GREATEST(lower(b.during) + interval '1 second', LEAST(upper(b.during), p_clock)), '[)')
                       ELSE b.during END
   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = p_stall AND b.vehicle_id = p_vehicle
     AND b.state IN ('held','active');
  UPDATE public.ottoq_visit_needs n
     SET atoms = (SELECT jsonb_agg(CASE WHEN x.e->>'cabin_stop_stall_id' = p_stall::text
                                        THEN (x.e - 'cabin_stop_stall_id' - 'cabin_stop_at')
                                             || jsonb_build_object('cabin_stop_post', p_stall, 'cabin_stop_ended_at', p_clock)
                                        ELSE x.e END ORDER BY x.o)
                    FROM jsonb_array_elements(n.atoms) WITH ORDINALITY x(e, o))
   WHERE n.visit_id = p_visit;
END;
$function$;

-- ── (c), (d), (e): the decide tick's step ──
CREATE FUNCTION public.ottoq_cabin_post_stops(p_sim_run_id uuid, p_depot uuid, p_clock timestamptz, p_tick bigint,
                                              p_snapshot uuid, p_floor_only boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  r record; v_cycle numeric; v_until timestamptz; v_floor numeric;
  v_stall uuid; v_visit uuid; v_bkg uuid; v_cmd uuid; v_ok boolean;
  v_ctx jsonb; v_prop jsonb; v_blocks int; v_codes text[]; v_rules jsonb;
  v_swept int := 0; v_released int := 0; v_dropped int := 0; v_seated int := 0; v_no_post int := 0; v_refused int := 0;
BEGIN
  -- 0817. Called twice in a decide tick, and only with the wash bay exterior only.
  --   p_floor_only TRUE, before the charge step (3): the housekeeping (a wash bay held for cabin work is released; a
  --     finished stop frees its post), then a stop for each car that has waited the floor for one.
  --   p_floor_only FALSE, after the charge step and the gate intake: a stop for every other waiting car, on a post
  --     the charge step left free.
  IF p_sim_run_id IS NULL OR p_depot IS NULL OR p_clock IS NULL
     OR NOT public.ottoq_wash_bay_exterior_only(p_sim_run_id) THEN
    RETURN jsonb_build_object('on', false);
  END IF;
  v_cycle := 2 * GREATEST(0, COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_deep_side_min', 5.0), 5.0))
             + GREATEST(0, COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_motion_min', 0.8), 0.8));
  -- the program, and the ticks either side of it: the command is confirmed a tick after it is issued, the arm starts
  -- on the pass after that, and the post is freed on the decide tick after the arm is home
  v_until := p_clock + make_interval(secs => (round((v_cycle + 4) * 60))::double precision);
  v_floor := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90);
  IF v_floor <= 0 THEN v_floor := 90; END IF;

  IF p_floor_only THEN
    -- (c) a wash bay held for cabin work is released
    UPDATE public.ottoq_stall_bookings b
       SET state = 'released', released_at = p_clock, release_reason = 'cabin_work_is_the_posts_arm'
      FROM public.stalls s
     WHERE s.id = b.stall_id AND s.depot_id = p_depot AND s.stall_type::text = 'wash_bay'
       AND b.sim_run_id = p_sim_run_id AND b.purpose = 'detail' AND b.state = 'held';
    GET DIAGNOSTICS v_swept = ROW_COUNT;

    -- (d) a stop that has ended frees its post. A stop is its mark on an atom: done, the arm is home; pending on the
    -- post for 20 minutes, or off the post for 3, the stop did not happen (the command was refused, or the car was
    -- moved), and the atom goes back to waiting for one.
    FOR r IN
      SELECT vn.visit_id, vn.vehicle_id, v.current_stall_id,
             x.e->>'cabin_stop_stall_id' AS stop_stall, COALESCE(x.e->>'status','pending') AS a_status,
             (x.e->>'cabin_stop_at')::timestamptz AS stop_at
        FROM public.ottoq_visit_needs vn
        JOIN public.vehicles v ON v.id = vn.vehicle_id
        CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) x(e)
       WHERE vn.depot_id = p_depot AND vn.sim_run_id = p_sim_run_id
         AND x.e ? 'cabin_stop_stall_id'
       ORDER BY vn.vehicle_id, vn.visit_id
    LOOP
      IF r.a_status = 'in_progress' THEN CONTINUE; END IF;
      IF r.a_status = 'pending' THEN
        IF r.current_stall_id::text = r.stop_stall AND p_clock < r.stop_at + interval '20 minutes' THEN CONTINUE; END IF;
        IF r.current_stall_id::text IS DISTINCT FROM r.stop_stall AND p_clock < r.stop_at + interval '3 minutes' THEN
          CONTINUE;
        END IF;
        v_dropped := v_dropped + 1;
      ELSE
        v_released := v_released + 1;
      END IF;
      PERFORM public.ottoq_cabin_stop_release(p_sim_run_id, r.vehicle_id, r.visit_id, r.stop_stall::uuid, p_clock);
    END LOOP;
  END IF;

  -- (d), (e) the cars that wait for a stop: parked, fit to move, no charge to do, and an interior deep clean to do
  FOR r IN
    SELECT q.* FROM (
      SELECT v.id AS vehicle_id, v.fleet_operator_id, v.current_stall_id AS prev_stall,
             EXTRACT(epoch FROM (p_clock - v.last_state_change)) / 60.0 AS wait_min, v.last_state_change,
             EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                      WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open','in_progress')
                        AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status','pending') = 'pending'
                        AND NOT COALESCE((a->>'confirm_required')::boolean, false)) AS has_atom
        FROM public.vehicles v
       WHERE v.home_depot_id = p_depot AND v.category = 'autonomous'
         AND v.current_state = 'staged_awaiting_service'
         AND NOT public.ottoq_vehicle_fault_open(v.config)
         AND NOT public.ottoq_vehicle_is_tethered(v.id, p_clock)
         AND NOT ottoq.ottoq_uplink_transfer_holds(v.id, p_sim_run_id)
         AND COALESCE(public.ottoq_approach_zone(v.id, p_sim_run_id), 'B') <> 'C'
         -- the charge cursor's own line (0493), so a car is the charge step's or this step's, never both
         AND NOT (v.current_soc < COALESCE((SELECT vn.target_soc FROM public.ottoq_visit_needs vn
                     WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                       AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                           = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                     ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1)
         -- nothing else sent this car to a stall this tick (0493's guard)
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc
                          WHERE vc.vehicle_id = v.id AND vc.sim_run_id = p_sim_run_id
                            AND vc.issued_at = p_clock AND vc.status = 'issued' AND vc.payload ? 'stall_id')
         -- no stop already under way for it, and no arm at work in it
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                          WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id
                            AND vn.status IN ('open','in_progress')
                            AND (a ? 'cabin_stop_stall_id'
                                 OR (a->>'status' = 'in_progress' AND a->>'performed_by' = 'stall_cabin_robot')))
    ) q
    WHERE (NOT p_floor_only OR q.wait_min >= v_floor)
      AND (q.has_atom
           -- the needs card's own finding, with no atom yet on the visit (§1 (a)). Read only on the second call: the
           -- first then finds the atom the second wrote.
           OR (NOT p_floor_only
               AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                                WHERE vn.vehicle_id = q.vehicle_id AND vn.sim_run_id = p_sim_run_id
                                  AND vn.status IN ('open','in_progress') AND a->>'svc' = 'interior_deep_clean'
                                  AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
               AND EXISTS (SELECT 1 FROM public.ottoq_vehicle_needs_card c
                            WHERE c.depot_id = p_depot AND c.vehicle_id = q.vehicle_id
                              AND 'interior_deep_clean' = ANY (COALESCE(c.must_do_now, '{}'::text[])))))
    ORDER BY q.last_state_change ASC NULLS FIRST, q.vehicle_id
    LIMIT 10
  LOOP
    -- a post free on the floor, on the calendar for the whole stop, its charger fit, and one the command door accepts
    SELECT s.id INTO v_stall
      FROM ottoq.ottoq_stall_free_between(p_sim_run_id, p_depot, p_clock, v_until, 'dcfc', NULL, 50, NULL) f
      JOIN public.stalls s ON s.id = f.stall_id
      JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
     WHERE s.current_vehicle_id IS NULL AND s.status NOT IN ('maintenance','closed')
       AND (s.reserved_by IS NULL OR s.reserved_by = r.vehicle_id OR s.reservation_expires_at <= p_clock)
       AND ch.station_state::text = 'Available'
       AND COALESCE((ottoq.ottoq_validate_assignment(r.vehicle_id, s.id, 'proceed_to_stall', p_clock, p_sim_run_id)->>'ok')::boolean, false)
     ORDER BY s.stall_code, s.id LIMIT 1;
    IF v_stall IS NULL THEN
      -- no post now. The clean is still written to the visit, so the car is held for it and is found next tick.
      IF NOT r.has_atom THEN PERFORM public.ottoq_cabin_stop_mark(p_sim_run_id, p_depot, r.vehicle_id, p_clock, NULL); END IF;
      v_no_post := v_no_post + 1;
      CONTINUE;
    END IF;

    v_ctx := public.ottoq_build_decision_context('task_start', 'vehicle', r.vehicle_id, p_depot, p_clock)
             || jsonb_build_object('need', 'interior_deep_clean', 'lane', 'detail', 'stall_type', 'dcfc',
                                   'purpose', 'detail', 'service', 'detail', 'requires_charging', 'false',
                                   'cabin_post_stop', true, 'stall_id', v_stall, 'wait_min', round(r.wait_min::numeric, 1),
                                   'waited_the_floor', p_floor_only);
    v_prop := jsonb_build_object('abstain', false, 'verb', 'assign_stall', 'resolved_action_context', 'stall_assignment',
                                 'source', 'cabin_post_stop', 'vehicle_id', r.vehicle_id, 'stall_type', 'dcfc',
                                 'stall_id', v_stall, 'purpose', 'detail', 'need', 'interior_deep_clean', 'requested_kw', 0);
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code', rule_code, 'passed', passed, 'reason', reason,
                                        'enforcement_taken', enforcement_taken, 'severity', severity))
      INTO v_blocks, v_codes, v_rules
      FROM public.ottoq_shield_probe('task_start', 'vehicle', r.vehicle_id, v_ctx, r.fleet_operator_id, p_depot);

    v_ok := COALESCE(v_blocks, 0) = 0;
    v_visit := NULL; v_bkg := NULL; v_cmd := NULL;
    IF v_ok THEN
      v_visit := public.ottoq_cabin_stop_mark(p_sim_run_id, p_depot, r.vehicle_id, p_clock, v_stall);
      v_ok := v_visit IS NOT NULL AND public.ottoq_reserve_stall(v_stall, r.vehicle_id, p_clock, 900);
    END IF;
    IF v_ok THEN
      v_bkg := ottoq.ottoq_record_enacted_booking(p_sim_run_id, v_stall, r.vehicle_id, p_clock, NULL, p_clock, v_until,
                                                  'detail', 'needs_card');
      v_ok := v_bkg IS NOT NULL;
    END IF;
    IF v_ok THEN
      v_cmd := ottoq.ottoq_emit_vehicle_command(p_sim_run_id, p_depot, r.vehicle_id, 'proceed_to_stall',
                 jsonb_build_object('stall_id', v_stall, 'new_state', 'charge_complete_holding', 'booking_id', v_bkg,
                                    'purpose', 'detail', 'reason', 'cabin_post_stop', 'need', 'interior_deep_clean'),
                 p_clock);
      v_ok := v_cmd IS NOT NULL
              AND EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc WHERE vc.command_id = v_cmd AND vc.status = 'issued');
    END IF;
    IF v_ok THEN
      -- the staging stall the car leaves: its booking ends now, as every move to a next leg ends one (0197)
      IF r.prev_stall IS NOT NULL AND r.prev_stall <> v_stall THEN
        UPDATE public.ottoq_stall_bookings
           SET state = 'done', released_at = p_clock, release_reason = 'vehicle_moved_to_next_leg',
               during = tstzrange(lower(during),
                                  GREATEST(lower(during) + interval '1 second', LEAST(upper(during), p_clock)), '[)')
         WHERE sim_run_id = p_sim_run_id AND stall_id = r.prev_stall AND vehicle_id = r.vehicle_id
           AND state IN ('held','active') AND lower(during) < p_clock;
      END IF;
      v_seated := v_seated + 1;
    ELSE
      IF v_visit IS NOT NULL THEN
        PERFORM public.ottoq_cabin_stop_release(p_sim_run_id, r.vehicle_id, v_visit, v_stall, p_clock);
      END IF;
      v_refused := v_refused + 1;
    END IF;

    BEGIN
      INSERT INTO public.ottoq_decisions (sim_run_id, tick_seq, sim_clock, depot_id, snapshot_id, action_context,
             resolved_action_context, entity_type, entity_id, context_frame, proposed_action, enacted_action,
             overridden, override_rule_codes, rule_results, safe_default_taken, outcome_status)
      VALUES (p_sim_run_id, p_tick, p_clock, p_depot, p_snapshot, 'task_start', 'task_start', 'vehicle', r.vehicle_id,
              v_ctx, v_prop,
              CASE WHEN v_ok THEN v_prop || jsonb_build_object('booking_id', v_bkg, 'command_id', v_cmd, 'visit_id', v_visit,
                                                               'until', v_until)
                   ELSE jsonb_build_object('verb', 'hold_no_space',
                          'reason', CASE WHEN COALESCE(v_blocks, 0) > 0 THEN 'shield_block' ELSE 'cabin_stop_not_seated' END) END,
              COALESCE(v_blocks, 0) > 0, COALESCE(v_codes, '{}'::text[]), COALESCE(v_rules, '[]'::jsonb),
              COALESCE(v_blocks, 0) > 0,
              CASE WHEN v_ok THEN 'enacted' WHEN COALESCE(v_blocks, 0) > 0 THEN 'overridden_to_default'
                   ELSE 'noop_no_candidate' END);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0817 cabin stop decision row (vehicle %): % %', r.vehicle_id, SQLSTATE, SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('on', true, 'floor_only', p_floor_only, 'bay_holds_released', v_swept,
                            'stops_ended', v_released, 'stops_dropped', v_dropped, 'seated', v_seated,
                            'no_post', v_no_post, 'not_seated', v_refused);
END;
$function$;

COMMENT ON FUNCTION public.ottoq_cabin_post_stops(uuid, uuid, timestamptz, bigint, uuid, boolean) IS
  '0817: the decide tick''s cabin-stop step, with the wash bay exterior only. A parked car with an interior deep clean '
  'to do and no charge to do stands on a free fast-charger post, not plugged in, while the post''s cleaning arm runs '
  'the deep program; the post is then freed. Also releases a wash bay held for cabin work. Called before the charge '
  'step for cars that have waited charge_wait_floor_min, and after it for the rest.';

-- ── the patches ──
CREATE TEMP TABLE _0817_patch (seq int, fn text, n int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0817_patch VALUES
-- (b) the service flow's wash lane: the flag as a reason to seat
(1, 'twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 1,
$o$              OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))$o$,
$n$              OR public.ottoq_flag_wants_wash_bay(p_sim_run_id, v.config))   -- 0817$n$),
-- (b) the service flow's wash lane: the seat's kind, its minutes and its leg
(2, 'twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)', 4,
$o$(ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))$o$,
$n$(ottoq_visit_wants_detail(v_rec.id) OR public.ottoq_flag_wants_detail_seat(p_sim_run_id, v_rec.config) /* 0817 */)$n$),
-- (a), (b) the charge disposition (4)
(3, 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)', 1,
$o$  SELECT COALESCE(v.config->>'flagged_issue_type','') IN ('minor_cosmetic','wash_due')
    INTO v_flagged FROM vehicles v WHERE v.id = p_vehicle_id;$o$,
$n$  SELECT public.ottoq_flag_wants_wash_bay(v_run, v.config)   -- 0817: minor_cosmetic takes no seat in an exterior-only bay
    INTO v_flagged FROM vehicles v WHERE v.id = p_vehicle_id;$n$),
(4, 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)', 1,
$o$         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'));$o$,
$n$         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped')
         -- 0817: a deep clean that is a post's is not a reason to seat the car in a wash bay
         AND NOT (a->>'svc' = 'interior_deep_clean'
                  AND public.ottoq_deep_clean_waits_for_post(v_run, p_vehicle_id)));$n$),
(5, 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)', 1,
$o$      v_wants_detail := v_flagged OR ottoq_visit_wants_detail(p_vehicle_id);$o$,
$n$      v_wants_detail := (v_flagged AND NOT public.ottoq_wash_bay_exterior_only(v_run))   -- 0817
                        OR ottoq_visit_wants_detail(p_vehicle_id);$n$),
-- (d) the mover's hold: a car on its cabin stop stays on the post until the arm has started
(6, 'ottoq.ottoq_uplink_transfer_holds(uuid,uuid)', 1,
$o$                AND a->>'robot_stall_id' = v.current_stall_id::text)))$o$,
$n$                AND a->>'robot_stall_id' = v.current_stall_id::text)
            -- 0817: and a car on its cabin stop, standing on the post it was sent to, whose arm has not yet started
            OR (a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status', 'pending') = 'pending'
                AND a->>'cabin_stop_stall_id' = v.current_stall_id::text)))$n$),
-- (d) the arm's starter: a car on its cabin stop
(7, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)', 1,
$o$  v_deep boolean := false; v_deep_started boolean := false; v_deep_cycle numeric; v_deep_ends timestamptz; v_deep_leg uuid;$o$,
$n$  v_deep boolean := false; v_deep_started boolean := false; v_deep_cycle numeric; v_deep_ends timestamptz; v_deep_leg uuid;
  v_cabin_stop boolean := false;   -- 0817: the car stands on a fast-charger post for the arm's program, not plugged in$n$),
(8, 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)', 1,
$o$  IF v_robot_cycle IS NOT NULL AND v_robot_left IS NOT NULL
     AND COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_deep_clean', 0), 0) >= 1$o$,
$n$  -- 0817: a cabin stop. The car was sent to this post for its deep clean (the atom carries the post), and stands on
  -- it with no charge under way. The arm's program is the same one.
  v_cabin_stop := v_robot_dial AND COALESCE(v_state, '') = 'charge_complete_holding'
                  AND EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text = 'dcfc')
                  AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) cs
                               WHERE cs->>'svc' = 'interior_deep_clean' AND COALESCE(cs->>'status','pending') = 'pending'
                                 AND cs->>'cabin_stop_stall_id' = v_stall::text);
  IF ((v_robot_cycle IS NOT NULL AND v_robot_left IS NOT NULL) OR v_cabin_stop)
     AND COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_deep_clean', 0), 0) >= 1$n$),
-- (d) the starter's cursor: a car on its cabin stop
(9, 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)', 1,
$o$            OR (v_deep_arm AND v.current_state = 'charging_dcfc'$o$,
$n$            -- 0817: a car on its cabin stop, standing on the post it was sent to
            OR (v_deep_arm AND v.current_state = 'charge_complete_holding'
                AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) cs
                             WHERE cs->>'svc' = 'interior_deep_clean' AND COALESCE(cs->>'status','pending') = 'pending'
                               AND cs->>'cabin_stop_stall_id' = v.current_stall_id::text))
            OR (v_deep_arm AND v.current_state = 'charging_dcfc'$n$),
-- (e) the decide tick: the floor's stops before the charge step, with the housekeeping
(10, 'public.ottoq_decide_tick(uuid)', 1,
$o$  -- (3) STALL ASSIGNMENT
$o$,
$n$  -- (2c) 0817 CABIN STOPS, the housekeeping and the cars that have waited the floor (public.ottoq_cabin_post_stops)
  IF public.ottoq_wash_bay_exterior_only(p_sim_run_id) THEN
    BEGIN
      PERFORM public.ottoq_cabin_post_stops(p_sim_run_id, v_depot, v_clock, v_tick, v_snapshot_id, true);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0817 cabin stops (floor): % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  -- (3) STALL ASSIGNMENT
$n$),
-- (e) the decide tick: every other stop, on a post the charge step left free
(11, 'public.ottoq_decide_tick(uuid)', 1,
$o$  -- (4) CHARGE DISPOSITION
$o$,
$n$  -- (3c) 0817 CABIN STOPS, on a post the charge step left free (public.ottoq_cabin_post_stops)
  IF public.ottoq_wash_bay_exterior_only(p_sim_run_id) THEN
    BEGIN
      PERFORM public.ottoq_cabin_post_stops(p_sim_run_id, v_depot, v_clock, v_tick, v_snapshot_id, false);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0817 cabin stops: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  -- (4) CHARGE DISPOSITION
$n$),
-- (e) the needs card's space routing: a car sent to its cabin stop this tick is not also sent to a bay
(12, 'public.ottoq_decide_tick(uuid)', 1,
$o$             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'$o$,
$n$             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
             -- 0817: nor a car this tick's cabin-stop step sent to a post, or marked for one
             AND NOT (public.ottoq_wash_bay_exterior_only(p_sim_run_id)
                      AND (EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands vc
                                    WHERE vc.vehicle_id = pk.vehicle_id AND vc.sim_run_id = p_sim_run_id
                                      AND vc.issued_at = v_clock AND vc.status = 'issued' AND vc.payload ? 'stall_id')
                           OR EXISTS (SELECT 1 FROM ottoq_visit_needs cn, jsonb_array_elements(cn.atoms) ca
                                       WHERE cn.vehicle_id = pk.vehicle_id AND cn.sim_run_id = p_sim_run_id
                                         AND cn.status IN ('open','in_progress') AND ca ? 'cabin_stop_stall_id')))$n$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0817_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> p.n THEN RAISE EXCEPTION '0817 V2: anchor % in % matches % times, not %', p.seq, p.fn, n, p.n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0817: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body with its patches reversed is its pre-image ──
DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0817_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0817_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0817_pre'
                                       AND s.schema_name || '.' || s.object_name = split_part(f.fn, '(', 1)) THEN
      RAISE EXCEPTION '0817 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── V3: the behaviour, staged on a past run, inside a block that is rolled back ──
-- Stages the twin depot's latest run as running with the three dials on, parks one full car, and reads:
-- (1) the tests: the bay is exterior only; the deep clean is a post's; the seat is not a detail seat; wash_due takes a
--     wash seat and minor_cosmetic none; with the dial at 0 all of it is as before this file;
-- (2) the step seats the car on a free fast-charger post: a command, a booking on the post, the atom marked;
-- (3) the twin confirms the command: the car stands on the post, charge_complete_holding, and the mover's hold has it;
-- (4) the arm's starter begins the deep program on that post, and the program ends done;
-- (5) the step then frees the post, and the car points at no stall;
-- (6) a wash bay held for cabin work is released by the step.
CREATE TEMP TABLE _0817_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_veh uuid; v_clock timestamptz; v_post uuid; v_visit uuid; v_atom jsonb; v_res jsonb; v_out jsonb;
  v_state text; v_stall uuid; v_bay_bkg uuid; v_bay uuid; v_bay_state text; v_bkg_state text; v_cycle numeric;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, now()) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot ORDER BY r.started_at DESC LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs n
                      WHERE n.vehicle_id = v.id AND n.sim_run_id = v_run AND n.status IN ('open','in_progress'))
   ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL THEN
    INSERT INTO _0817_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past run or no car to stage'));
    RETURN;
  END IF;
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('wash_bay_exterior_only', 'cabin_robot_deep_clean', 'stall_cabin_robot', 'cabin_found_item_rate');
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'wash_bay_exterior_only', 1, '0817 self-test', now()),
           ('run', v_run, 'cabin_robot_deep_clean', 1, '0817 self-test', now()),
           ('run', v_run, 'stall_cabin_robot', 2, '0817 self-test', now()),
           ('run', v_run, 'cabin_found_item_rate', 0, '0817 self-test', now());
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;

    -- the floor: every fast-charger post free and fit, every car off them; the staged car parked, full, on no stall
    UPDATE public.vehicles SET current_stall_id = NULL
     WHERE current_stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available',
                             reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE depot_id = c_depot AND stall_type::text = 'dcfc';
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available' WHERE current_vehicle_id = v_veh;
    UPDATE public.ottoq_ocpp_chargers ch SET station_state = 'Available', last_heartbeat_at = v_clock
      FROM public.stalls s WHERE s.ocpp_charger_id = ch.charger_id AND s.depot_id = c_depot AND s.stall_type::text = 'dcfc';
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = GREATEST(v_clock, booked_at_sim),
                                           release_reason = '0817 self-test'
     WHERE sim_run_id = v_run AND state IN ('held','active')
       AND stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_stall_id = NULL, current_soc = 100,
           last_state_change = v_clock - interval '5 minutes',
           robotic_tether_until = NULL, robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,
           robotic_tether_phase = NULL,
           config = COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type'
     WHERE id = v_veh;

    -- (1) the tests
    IF NOT public.ottoq_wash_bay_exterior_only(v_run) OR NOT public.ottoq_deep_clean_waits_for_post(v_run, v_veh) THEN
      RAISE EXCEPTION '0817 V3: with the dials on, the wash bay is not exterior only';
    END IF;
    IF NOT public.ottoq_flag_wants_wash_bay(v_run, '{"flagged_issue_type":"wash_due"}'::jsonb)
       OR public.ottoq_flag_wants_wash_bay(v_run, '{"flagged_issue_type":"minor_cosmetic"}'::jsonb)
       OR public.ottoq_flag_wants_detail_seat(v_run, '{"flagged_issue_type":"wash_due"}'::jsonb)
       OR public.ottoq_flag_wants_detail_seat(v_run, '{"flagged_issue_type":"minor_cosmetic"}'::jsonb)
       OR public.ottoq_flag_wants_wash_bay(v_run, '{}'::jsonb) THEN
      RAISE EXCEPTION '0817 V3: the flags'' doors are not wash_due to a wash seat and minor_cosmetic to none';
    END IF;
    UPDATE public.ottoq_policy_params SET param_value = 0
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'wash_bay_exterior_only';
    IF public.ottoq_wash_bay_exterior_only(v_run)
       OR NOT public.ottoq_flag_wants_wash_bay(v_run, '{"flagged_issue_type":"minor_cosmetic"}'::jsonb)
       OR NOT public.ottoq_flag_wants_detail_seat(v_run, '{"flagged_issue_type":"wash_due"}'::jsonb)
       OR public.ottoq_flag_wants_detail_seat(v_run, '{}'::jsonb)
       OR (public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, false)->>'on')::boolean THEN
      RAISE EXCEPTION '0817 V3: with the dial at 0 something is not as before this file';
    END IF;
    UPDATE public.ottoq_policy_params SET param_value = 1
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'wash_bay_exterior_only';

    -- the car's deep clean, on a visit (none is open in a run that has ended, so this opens one)
    v_visit := public.ottoq_cabin_stop_mark(v_run, c_depot, v_veh, v_clock, NULL);
    IF v_visit IS NULL OR public.ottoq_visit_wants_detail(v_veh) THEN
      RAISE EXCEPTION '0817 V3: the deep clean is not on a visit, or its seat would be a detail seat';
    END IF;

    -- (6) a wash bay held for the cabin work
    SELECT s.id INTO v_bay FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'wash_bay'
     ORDER BY s.stall_code LIMIT 1;
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = GREATEST(v_clock, booked_at_sim),
                                           release_reason = '0817 self-test'
     WHERE sim_run_id = v_run AND stall_id = v_bay AND state IN ('held','active','done','interrupted')
       AND during && tstzrange(v_clock + interval '2 hours', v_clock + interval '3 hours', '[)');
    INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, visit_id, purpose, during, state,
                                             booked_at, booked_by, booked_at_sim)
    VALUES (v_run, v_bay, v_veh, v_visit, 'detail',
            tstzrange(v_clock + interval '2 hours', v_clock + interval '2 hours 20 minutes', '[)'), 'held',
            now(), 'otto_q', v_clock)
    RETURNING booking_id INTO v_bay_bkg;

    -- (2) the step seats the car
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, true);
    v_out := public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, false);
    SELECT a INTO v_atom FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    v_post := (v_atom->>'cabin_stop_stall_id')::uuid;
    IF COALESCE((v_out->>'seated')::int, 0) < 1 OR v_post IS NULL THEN
      RAISE EXCEPTION '0817 V3: the step did not seat the parked car on a post (%; atom %)', v_out, v_atom;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_post AND s.stall_type::text = 'dcfc')
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                       WHERE b.sim_run_id = v_run AND b.stall_id = v_post AND b.vehicle_id = v_veh
                         AND b.state IN ('held','active') AND b.purpose = 'detail')
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands c
                       WHERE c.sim_run_id = v_run AND c.vehicle_id = v_veh AND c.status = 'issued'
                         AND c.command_type = 'proceed_to_stall' AND c.payload->>'stall_id' = v_post::text) THEN
      RAISE EXCEPTION '0817 V3: the stop has no fast-charger post, no booking or no command';
    END IF;
    SELECT b.state INTO v_bay_state FROM public.ottoq_stall_bookings b WHERE b.booking_id = v_bay_bkg;
    IF v_bay_state <> 'released' THEN
      RAISE EXCEPTION '0817 V3: the wash bay held for cabin work is not released (%)', v_bay_state;
    END IF;

    -- (3) the twin confirms the command
    PERFORM twin.ottoq_sim_confirm_commands(v_run, v_clock + interval '30 seconds');
    SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM public.vehicles v WHERE v.id = v_veh;
    IF v_state <> 'charge_complete_holding' OR v_stall IS DISTINCT FROM v_post
       OR NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_post AND s.current_vehicle_id = v_veh) THEN
      RAISE EXCEPTION '0817 V3: the confirmed car does not stand on its post (state %, stall %, post %)', v_state, v_stall, v_post;
    END IF;
    IF NOT ottoq.ottoq_uplink_transfer_holds(v_veh, v_run) THEN
      RAISE EXCEPTION '0817 V3: the mover''s hold does not keep the car on its post before the arm starts';
    END IF;

    -- (4) the arm's starter, then the program's end
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock + interval '1 minute');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    IF v_atom->>'status' <> 'in_progress' OR v_atom->>'performed_by' <> 'stall_cabin_robot'
       OR NOT COALESCE((v_atom->>'deep_program')::boolean, false) OR v_atom->>'robot_stall_id' <> v_post::text THEN
      RAISE EXCEPTION '0817 V3: the post''s arm did not begin the deep program (%)', v_atom;
    END IF;
    v_cycle := (v_atom->>'robot_cycle_min')::numeric;
    IF NOT ottoq.ottoq_uplink_transfer_holds(v_veh, v_run) THEN
      RAISE EXCEPTION '0817 V3: the mover''s hold does not keep the car on its post while the arm works';
    END IF;
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock + interval '5 minutes', 0, NULL, true);
    IF NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_post AND s.current_vehicle_id = v_veh) THEN
      RAISE EXCEPTION '0817 V3: the step freed the post while the arm was at work';
    END IF;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock + interval '1 minute' + make_interval(secs => (v_cycle * 60 + 30)::double precision));
    SELECT a INTO v_atom FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    IF v_atom->>'status' <> 'done' THEN
      RAISE EXCEPTION '0817 V3: the deep program did not end done (%)', v_atom;
    END IF;

    -- (5) the step frees the post
    v_out := public.ottoq_cabin_post_stops(v_run, c_depot, v_clock + interval '2 minutes' + make_interval(secs => (v_cycle * 60 + 30)::double precision), 0, NULL, true);
    SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM public.vehicles v WHERE v.id = v_veh;
    SELECT b.state INTO v_bkg_state FROM public.ottoq_stall_bookings b
     WHERE b.sim_run_id = v_run AND b.stall_id = v_post AND b.vehicle_id = v_veh ORDER BY b.booked_at DESC LIMIT 1;
    SELECT a INTO v_atom FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    IF COALESCE((v_out->>'stops_ended')::int, 0) < 1 OR v_stall IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_post AND (s.current_vehicle_id IS NOT NULL OR s.reserved_by = v_veh))
       OR v_bkg_state <> 'done' OR v_atom ? 'cabin_stop_stall_id' OR v_atom->>'cabin_stop_post' <> v_post::text THEN
      RAISE EXCEPTION '0817 V3: the ended stop did not free its post (%; car stall %, booking %, atom %)',
        v_out, v_stall, v_bkg_state, v_atom;
    END IF;

    v_res := jsonb_build_object('ran', true, 'run', v_run, 'vehicle', v_veh, 'post', v_post, 'cycle_min', v_cycle,
               'seated_on_a_free_post', true, 'held_until_the_arm_is_home', true, 'deep_program_done', true,
               'post_freed', true, 'car_state_after', v_state, 'bay_hold_released', true, 'dial_0_unchanged', true);
    RAISE EXCEPTION USING ERRCODE = 'P0817', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0817' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0817 self-test') THEN
    RAISE EXCEPTION '0817 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0817_selftest VALUES (v_res);
END $v3$;

-- ── on at the twin depot (rule 12) ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'wash_bay_exterior_only', 1,
        'Chase (delegated to Claude Code: 0817)', now());

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0817_the_wash_bay_is_exterior_only_and_cabin_work_is_done_at_a_fast_charger_post',
        false, false,
        'Behind wash_bay_exterior_only (default 0, at which the helper is false, the two flag tests return what the '
        'lines they replace returned, and no new branch is reached). At the twin depot (1): no cabin work is routed to '
        'a wash bay; wash_due takes a wash seat and minor_cosmetic none; a wash bay held for cabin work is released; '
        'and a parked car with an interior deep clean and no charge to do stands on a free fast-charger post, not '
        'plugged in, for the arm''s deep program (public.ottoq_cabin_post_stops), then goes on. No certification arm, '
        'canon cell or dial experiment sets the dial. V3 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0817_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-12 at 14:02:45 UTC (8:02 AM CT), ledger 20261112140245, through apply_migration, on the first send.
--   No run was live and nothing was in flight (P0). The text sent was this file from BEGIN to COMMIT. V3 (rolled back)
--   staged run 5480be1f with car 00cc3d0a parked and full: the step seated it on fast-charger post 765adddb (a command,
--   a booking, the atom marked); the twin's confirm stood it on the post, charge_complete_holding; the mover's hold
--   kept it there; the arm's starter began the 10.8-minute deep program and it ended done; the step then freed the
--   post and the car pointed at no stall; the wash bay held for its cabin work was released; and with the dial at 0
--   the tests read as before this file. Stored after the apply, md5(prosrc): ottoq_sim_advance_service_flow
--   02b12d958aba397731d50155c871b542, ottoq_decide_tick bf5a5bb8302ee30fa182146027a3446d,
--   ottoq_sim_advance_visit_atoms 511d72ca7a5c519c5bc8b89c0b3ecf88, ottoq_start_concurrent_atoms
--   a2da9ddc2c6c1470503f48346bfdf808, ottoq_l2_propose_charge_disposition ecb10ed6afcea74b16bb4b66b8a1608e,
--   ottoq_uplink_transfer_holds 0a2ae260e575938a2575b68895196407, ottoq_deep_clean_waits_for_post
--   56dae5a3ffb07065057550fda5c60a81, ottoq_wash_bay_exterior_only c457a88ca926a0dc80673582c58c7e37,
--   ottoq_flag_wants_wash_bay e170483d429fb564e59913f9f9d58ad0, ottoq_flag_wants_detail_seat
--   74857795f0c05fbb2c79a80d3677e995, ottoq_cabin_stop_mark 9a3b65348265bb3f95f2d440ed19ca60,
--   ottoq_cabin_stop_release 665d1ca70261404f09e6dfec4ce87c90, ottoq_cabin_post_stops
--   640bd68085d3f85258088f56f17af5c8. Demo run 56d8465f was started at 14:02:57 UTC for the check rule 12 asks for;
--   db/checks/0484 has its readings.
