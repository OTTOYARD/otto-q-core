-- migration-version: 20261112202531
-- migration-name:    0821_a_car_to_charge_has_its_cabin_clean_on_its_visit_before_it_is_seated_and_a_cabin_stop_records_its_posts_charger
--
-- 0821  **A car to charge has its cabin clean on its visit before it is seated. A cabin stop's decision records its
--        post's charger.**
--
-- WHY. Chase, 2026-11-12 (afternoon): "Go ahead and close those open items. Also, I thought we switched all chargers
-- from L2 to DCFC Robotic arm chargers?" He is right, and the correction comes first.
--
-- §1 A READING OF MINE, CORRECTED: THE TWIN DEPOT HAS NO L2. 0763 (2026-10-23) retired them. Read today: 30 fast-charger
--   posts, 0 L2 stalls, 10 retired parking stalls. 0820, db/checks/0485 and both PRs spoke of a car "that would have
--   taken a free L2", of "L2s standing free" in 0820's staged test, and of two doors that "can still seat on an L2".
--   NONE OF THAT CAN HAPPEN AT THE TWIN DEPOT. 0820's two L2 guards (the proposer's, the charge step's) are not reached
--   there, which is why the run showed 0 declines. I wrote the words from 0820's own source without reading the
--   depot's stalls. The one-stop rule costs no car an L2 it could have had, because there is none.
--
-- §2 WHAT THE RUN DID SHOW, READ TO ITS END (0e3cc3c2, 540 sim minutes): 10 cabin stops, all done, waits 0.3 to 8.7
--   minutes (mean 1.5), none at the 90-minute floor. AND 6 OF THE 10 WERE A SECOND TRIP, the thing Chase's rule is
--   there to prevent. Each of the six cars charged on a fast-charger post and, 0.3 to 0.5 minutes after its charge
--   ended, was sent to a different post for its cabin clean (cars 9e209f49, db9d7b6e, bfbaf0b2, c8ae20e3, da022fb5,
--   72ccc3d4). THE CAUSE, read from each car's own state changes: the car went from arrived_at_gate straight to
--   charging_dcfc. Its visit had no deep-clean atom (the needs card raised the clean), and 0820 (c) wrote the atom
--   only for a car in staged_awaiting_service, and only after the charge step had run. So the charging post's arm had
--   nothing to do, and the clean was found when the car was full.
--   Where 0820 (c) did reach a car, it worked: 7 card-raised cleans were done by the charging post's arm with no stop,
--   and 7 more were under way at the run's end.
--
-- §3 WHAT THIS DOES. Behind wash_bay_exterior_only (0817; default 0, 1 at the twin depot).
--   (a) The clean is written to the visit BEFORE the charge step, for a car at the gate, a parked car and a car
--       already charging on a fast-charger post. The block moves to the step's first call in the tick (before the
--       charge cursor and the gate intake) and reads three states, not one.
--   (b) A cabin stop's decision row carries its post's charger state at the moment of seating
--       (context_frame.cabin_stop_post_charger). db/checks/0485 §2 could not say whether a stop was on a faulted post.
--
-- §4 RULE 9, CHECKED. Nothing is skipped, shortened or deferred. The clean is found sooner and done during the charge.
--   RULE 14: the test reads the car's own needs card, never its owner.
--
-- §5 WHAT THIS DOES NOT DO.
--   - A clean written to a car late in its charge may not finish before the charge does. 0816 (e) then puts it back
--     to pending and the car takes a cabin stop, as today. Not measured how often.
--   - 0820's L2 guards stay. They are correct for a depot that has L2s and are not reached at this one.
--
-- §6 PRECONDITIONS AND CHECKS. P0 nothing in flight, no run live. P1 the body this file was written against (md5 of
--   prosrc 0fd70c1d7e9a0367fd655b8537948c60). P2 once. V1 the patched body with its patches reversed is its pre-image.
--   V2 every anchor matched once. V3 the behaviour, staged on a past run inside a block that is rolled back.
--
-- §7 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: with wash_bay_exterior_only at 0 the step returns
--   before any of its body.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0821_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0821_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0821 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0821 P0: a run is live. V3 stages a past run as running, so apply between runs';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure)
       IS DISTINCT FROM '0fd70c1d7e9a0367fd655b8537948c60' THEN
    RAISE EXCEPTION '0821 P1: public.ottoq_cabin_post_stops is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0821_%') THEN
    RAISE EXCEPTION '0821 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0821_pre', 'function', 'public', 'ottoq_cabin_post_stops',
       pg_get_functiondef('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure));

CREATE TEMP TABLE _0821_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0821_patch VALUES
-- (a) the block runs in the step's first call of the tick, before the charge step
(1,
$o$  IF NOT p_floor_only THEN
    FOR r IN
      SELECT c.vehicle_id
        FROM public.ottoq_vehicle_needs_card c$o$,
$n$  -- 0821: in the step's FIRST call of the tick, before the charge cursor and the gate intake, and for a car at the
  -- gate or already charging as well as a parked one. On run 0e3cc3c2 six cars went from the gate straight to a
  -- charger with no atom, and each made a second trip to a post for the clean.
  IF p_floor_only THEN
    FOR r IN
      SELECT c.vehicle_id
        FROM public.ottoq_vehicle_needs_card c$n$),
-- (a) the three states
(2,
$o$         AND v.current_state = 'staged_awaiting_service'
         AND 'interior_deep_clean' = ANY (COALESCE(c.must_do_now, '{}'::text[]))$o$,
$n$         AND v.current_state::text IN ('staged_awaiting_service', 'arrived_at_gate', 'charging_dcfc')
         AND 'interior_deep_clean' = ANY (COALESCE(c.must_do_now, '{}'::text[]))$n$),
-- (b) the decision row carries the post's charger state
(3,
$o$                                   'cabin_post_stop', true, 'cabin_stop_post', v_stall, 'wait_min', round(r.wait_min::numeric, 1),$o$,
$n$                                   'cabin_post_stop', true, 'cabin_stop_post', v_stall, 'wait_min', round(r.wait_min::numeric, 1),
                                   -- 0821: the charger of the post, as it reads when the car is seated
                                   'cabin_stop_post_charger',
                                   (SELECT ch.station_state::text FROM public.stalls sp
                                      JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = sp.ocpp_charger_id
                                     WHERE sp.id = v_stall),$n$);

DO $patch$
DECLARE
  c_fn constant regprocedure := 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure;
  p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0821_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(c_fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0821 V2: anchor % matches % times, not 1', p.seq, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(c_fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0821: the function is not stored as patched (patch %)', p.seq;
    END IF;
  END LOOP;
  v_def := pg_get_functiondef(c_fn);
  FOR p IN SELECT * FROM _0821_patch ORDER BY seq DESC LOOP
    v_def := replace(v_def, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s WHERE s.label = '0821_pre') THEN
    RAISE EXCEPTION '0821 V1: the patched body with its patches reversed is not its pre-image';
  END IF;
END $patch$;

-- ── V3: the behaviour, staged on a past run, inside a block that is rolled back ──
-- (1) a car at the gate at 50%, its cabin soiled, no clean on any visit: after the step's FIRST call it has the atom,
--     and its charge needs a cleaning post;
-- (2) a full car with a clean to do, every fast charger Faulted: it is seated, and its decision row reads Faulted;
-- (3) neither car that still has its charge to do is given a cabin stop.
CREATE TEMP TABLE _0821_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_full uuid; v_gate uuid; v_late uuid; v_visit uuid; v_res jsonb;
  v_frame jsonb; v_n int;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, now()) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot ORDER BY r.started_at DESC LIMIT 1;
  SELECT (array_agg(v.id ORDER BY v.id))[1], (array_agg(v.id ORDER BY v.id))[2], (array_agg(v.id ORDER BY v.id))[3]
    INTO v_full, v_gate, v_late
    FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous'
     AND EXISTS (SELECT 1 FROM public.vehicle_need_profile p WHERE p.vehicle_id = v.id)
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs n
                      WHERE n.vehicle_id = v.id AND n.sim_run_id = v_run AND n.status IN ('open','in_progress'));
  IF v_run IS NULL OR v_late IS NULL THEN
    INSERT INTO _0821_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past run or no three cars to stage'));
    RETURN;
  END IF;
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('wash_bay_exterior_only', 'cabin_robot_deep_clean', 'stall_cabin_robot', 'cabin_found_item_rate');
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'wash_bay_exterior_only', 1, '0821 self-test', now()),
           ('run', v_run, 'cabin_robot_deep_clean', 1, '0821 self-test', now()),
           ('run', v_run, 'stall_cabin_robot', 2, '0821 self-test', now()),
           ('run', v_run, 'cabin_found_item_rate', 0, '0821 self-test', now());
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = v_clock WHERE sim_run_id = v_run;

    UPDATE public.vehicles SET current_stall_id = NULL
     WHERE current_stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available',
                             reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE depot_id = c_depot AND stall_type::text = 'dcfc';
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available'
     WHERE current_vehicle_id IN (v_full, v_gate, v_late);
    UPDATE public.ottoq_ocpp_chargers ch SET station_state = 'Faulted', last_heartbeat_at = v_clock
      FROM public.stalls s WHERE s.ocpp_charger_id = ch.charger_id AND s.depot_id = c_depot AND s.stall_type::text = 'dcfc';
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = GREATEST(v_clock, booked_at_sim),
                                           release_reason = '0821 self-test'
     WHERE sim_run_id = v_run AND state IN ('held','active')
       AND stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.vehicles
       SET current_state = CASE WHEN id = v_gate THEN 'arrived_at_gate' ELSE 'staged_awaiting_service' END::public.vehicle_state,
           current_stall_id = NULL,
           current_soc = CASE WHEN id = v_full THEN 100 ELSE 50 END,
           last_state_change = v_clock - interval '5 minutes',
           robotic_tether_until = NULL, robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,
           robotic_tether_phase = NULL,
           config = COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type'
     WHERE id IN (v_full, v_gate, v_late);
    -- the needs card raises the clean for the two cars that still have a charge to do
    UPDATE public.vehicle_need_profile SET cabin_condition = 'soiled' WHERE vehicle_id IN (v_gate, v_late);
    IF (SELECT count(*) FROM public.ottoq_vehicle_needs_card c
         WHERE c.vehicle_id IN (v_gate, v_late) AND 'interior_deep_clean' = ANY (c.must_do_now)) <> 2 THEN
      RAISE EXCEPTION '0821 V3: the needs card does not raise the clean for the staged cars';
    END IF;
    v_visit := public.ottoq_cabin_stop_mark(v_run, c_depot, v_full, v_clock, NULL);

    -- (1) the first call: the car at the gate, and the parked car, have the clean on a visit
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, true);
    SELECT count(DISTINCT n.vehicle_id) INTO v_n
      FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id IN (v_gate, v_late) AND n.sim_run_id = v_run AND n.status IN ('open','in_progress')
       AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status','pending') = 'pending';
    IF v_n <> 2 THEN
      RAISE EXCEPTION '0821 V3: after the first call % of the 2 cars to charge have the clean on a visit', v_n;
    END IF;
    IF NOT public.ottoq_charge_needs_cleaning_post(v_run, v_gate) THEN
      RAISE EXCEPTION '0821 V3: the car at the gate does not need a cleaning post for its charge';
    END IF;

    -- (2) the full car is seated on a faulted post, and its decision row says so
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, false);
    SELECT d.context_frame INTO v_frame FROM public.ottoq_decisions d
     WHERE d.sim_run_id = v_run AND d.entity_id = v_full AND d.sim_clock = v_clock
       AND d.proposed_action->>'source' = 'cabin_post_stop' AND d.outcome_status = 'enacted';
    IF v_frame IS NULL OR v_frame->>'cabin_stop_post_charger' IS DISTINCT FROM 'Faulted' THEN
      RAISE EXCEPTION '0821 V3: the stop''s decision row does not read its post''s charger as Faulted (%)',
        v_frame->>'cabin_stop_post_charger';
    END IF;
    -- (3) and neither car to charge was given a cabin stop
    IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                WHERE n.vehicle_id IN (v_gate, v_late) AND n.sim_run_id = v_run AND a ? 'cabin_stop_stall_id') THEN
      RAISE EXCEPTION '0821 V3: a car that still has its charge to do was given a cabin stop';
    END IF;

    v_res := jsonb_build_object('ran', true, 'run', v_run, 'gate_car', v_gate, 'parked_car', v_late, 'full_car', v_full,
               'clean_on_the_visit_before_the_charge_step', 2, 'gate_car_needs_a_cleaning_post', true,
               'decision_row_post_charger', v_frame->>'cabin_stop_post_charger',
               'no_cabin_stop_for_a_car_to_charge', true);
    RAISE EXCEPTION USING ERRCODE = 'P0821', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0821' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0821 self-test') THEN
    RAISE EXCEPTION '0821 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0821_selftest VALUES (v_res);
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0821_a_car_to_charge_has_its_cabin_clean_on_its_visit_before_it_is_seated_and_a_cabin_stop_records_its_posts_charger',
        false, false,
        'Behind wash_bay_exterior_only (0817; default 0, at which the step returns before its body). A clean the needs '
        'card raises is written to the visit in the step''s first call of the tick, before the charge step, for a car '
        'at the gate, parked or already charging: on run 0e3cc3c2 six of ten cabin stops were a second trip by a car '
        'that went from the gate straight to a charger with no atom. A cabin stop''s decision row carries its post''s '
        'charger state. V3 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0821_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-12 at 20:25:31 UTC (2:25 PM CT), ledger 20261112202531, through apply_migration, on the first send.
--   No run was live and nothing was in flight (P0). The text sent was this file from BEGIN to COMMIT.
--   V3 (rolled back) staged run 0e3cc3c2 with every fast charger Faulted: gate car 02ff42a9 and parked car 03726c33,
--   both at 50% with a soiled cabin and no clean on any visit, had the clean on a visit after the step's first call;
--   the gate car's charge needs a cleaning post; full car 00cc3d0a was seated and its decision row reads its post's
--   charger as Faulted; neither car to charge was given a cabin stop. Stored after the apply, md5(prosrc):
--   ottoq_cabin_post_stops cfcf0e515c3b7e7c3e7758b72aa12277. Demo run 02ca304f was started at 20:25 UTC for the
--   check rule 12 asks for (db/checks/0486).
