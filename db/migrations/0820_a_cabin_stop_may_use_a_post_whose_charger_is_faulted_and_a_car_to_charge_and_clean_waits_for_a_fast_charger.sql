-- migration-version: 20261112163417
-- migration-name:    0820_a_cabin_stop_may_use_a_post_whose_charger_is_faulted_and_a_car_to_charge_and_clean_waits_for_a_fast_charger
--
-- 0820  **A cabin stop may use a post whose charger is faulted. A car with a charge and a cabin clean to do waits for
--        a fast-charger post, so both are done in one stop.**
--
-- WHY. Chase, 2026-11-12, to the question db/checks/0484 §4 put to him: "Yes, they can use faulted charging bays for
-- cleaning, as long as they do not ALSO need a charge. If they need charging as well, hold until both can be completed
-- simultaneously. That way we avoid multiple trips to the same type of service stalls (charging/interior cleaning)."
--
-- §1 WHAT WAS SO (run 56d8465f, db/checks/0484): every cabin stop waited the 90-minute floor, with up to 8 of the
--   depot's 30 fast-charger posts standing free with a Faulted charger. And a car with both a charge and a deep clean
--   to do could make two trips to a post: it took whichever charger came free, and when that was an L2 (no arm), or
--   when the needs card had raised the clean with no atom on the visit, the clean waited for a cabin stop afterwards.
--
-- §2 WHAT THIS DOES. All of it is behind wash_bay_exterior_only (0817; default 0, 1 at the twin depot).
--   (a) A CABIN STOP MAY STAND ON A POST WHOSE CHARGER IS FAULTED. The step picks its own post: a fast-charger stall
--       free on the floor, free on the calendar for the whole stop, its charger Available or Faulted, and one the
--       command door accepts. A faulted post is taken first, so a working charger is left for a car that must charge.
--       A cabin stop is only ever a car with no charge to do (0817's line), so no car that needs a charge is sent to a
--       charger that cannot give one.
--   (b) A CAR WITH A CHARGE AND A CABIN CLEAN TO DO IS SEATED ONLY ON A FAST-CHARGER POST. One test,
--       public.ottoq_charge_needs_cleaning_post: the wash bay is exterior only and the car's open visit has an
--       interior deep clean still to start. The kernel's own stall proposer offers such a car fast-charger posts only,
--       and the charge step declines any other proposer's answer that is not one (an abstention, recorded with what
--       was declined). The car waits in the charge line, where 0642's 90-minute floor still puts a long wait first.
--   (c) THE CLEAN IS ON THE VISIT BEFORE THE CHARGE. A parked car below its target whose deep clean the needs card
--       raised with no atom gets the atom now, so (b) holds for it and its charging post's arm does the clean.
--
-- §3 RULE 9, CHECKED. No service is skipped, shortened or deferred past departure, and no charge target moves. (b) is
--   queueing, which rule 9 allows, and it is the owner's-side instruction quoted above. It does lengthen one wait: a
--   car that would have taken a free L2 now waits for a fast post. That is the trade Chase chose (one stop, not two),
--   and it is stated, not hidden. RULE 14: every test reads the car's own needs, never its owner.
--
-- §4 WHAT THIS DOES NOT DO.
--   - The stranded-recharge door of the service flow and the twin's own auto-assign are not changed. A car they seat
--     on an L2 with a clean to do still takes a cabin stop afterwards (0817). Not measured how often.
--   - A deep clean still waiting on its triage verdict does not hold its car for a fast post: the need is not yet
--     confirmed.
--   - A charger that recovers while a cabin stop stands on its post is occupied until the stop ends.
--   - HW.002 is not changed. It judges a charger for a charge, and the cabin stop no longer asks it (patch 5).
--
-- §5 PRECONDITIONS AND CHECKS. P0 nothing in flight, no run live. P1 the bodies this file was written against, and
--   0819 applied. P2 once. V1 each patched body with its patches reversed is its pre-image. V2 every anchor matched
--   once. V3 the behaviour, staged on a past run inside a block that is rolled back, with the twin's wash triage run
--   between the confirm and the arm's starter (0819's lesson).
--     public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)   640bd68085d3f85258088f56f17af5c8
--     public.ottoq_decide_tick(uuid)                                             bf5a5bb8302ee30fa182146027a3446d
--     public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)                  9a222f8fc80de9e5c29adc4c97243ef7
--
-- §6 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: at wash_bay_exterior_only 0 the new test is
--   false, the proposer's new clause admits every stall it admitted, the charge step's new branch is not reached, and
--   the cabin-stop step returns before any of its body. ON at the twin depot through 0817's dial (rule 12).
--
-- ROLLBACK: EXECUTE the three `definition`s in ottoq_schema_snapshots WHERE label = '0820_pre'; DROP FUNCTION
--   public.ottoq_charge_needs_cleaning_post(uuid, uuid); DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0820_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $pre$
DECLARE r record;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0820 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0820 P0: a run is live. V3 stages a past run as running, so apply between runs';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)', '640bd68085d3f85258088f56f17af5c8'),
      ('public.ottoq_decide_tick(uuid)',                                           'bf5a5bb8302ee30fa182146027a3446d'),
      ('public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)',                '9a222f8fc80de9e5c29adc4c97243ef7')) v(fn, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0820 P1: % is not the body this file was written against', r.fn;
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_on_cabin_stop(uuid)') IS NULL THEN
    RAISE EXCEPTION '0820 P1: 0819 is not applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0820_%') THEN
    RAISE EXCEPTION '0820 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0820_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure,
                 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)'::regprocedure);

-- ── (b) the one test: this car's charge must be on a post that can also clean its cabin ──
CREATE FUNCTION public.ottoq_charge_needs_cleaning_post(p_sim_run_id uuid, p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0820: the wash bay is exterior only (0817), and this car's open visit in the run has an interior deep clean still
  -- to start, its need confirmed. Its charge is then seated only on a fast-charger post, whose arm cleans the cabin
  -- while the car charges: one stop, not two (Chase, 2026-11-12). False for every car with the dial off.
  SELECT public.ottoq_wash_bay_exterior_only(p_sim_run_id)
     AND EXISTS (
       SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
        WHERE vn.vehicle_id = p_vehicle AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress')
          AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status', 'pending') = 'pending'
          AND NOT COALESCE((a->>'confirm_required')::boolean, false));
$function$;

COMMENT ON FUNCTION public.ottoq_charge_needs_cleaning_post(uuid, uuid) IS
  '0820: with the wash bay exterior only, a car whose open visit has an interior deep clean still to start is charged '
  'only on a fast-charger post, so its arm cleans the cabin during the charge. One stop, not two.';

-- ── the patches ──
CREATE TEMP TABLE _0820_patch (seq int, fn text, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0820_patch VALUES
-- (a) the cabin stop's post: free on the floor and the calendar, its charger Available or Faulted
(1, 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)',
$o$    SELECT s.id INTO v_stall
      FROM ottoq.ottoq_stall_free_between(p_sim_run_id, p_depot, p_clock, v_until, 'dcfc', NULL, 50, NULL) f
      JOIN public.stalls s ON s.id = f.stall_id
      JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
     WHERE s.current_vehicle_id IS NULL AND s.status NOT IN ('maintenance','closed')
       AND (s.reserved_by IS NULL OR s.reserved_by = r.vehicle_id OR s.reservation_expires_at <= p_clock)
       AND ch.station_state::text = 'Available'
       AND COALESCE((ottoq.ottoq_validate_assignment(r.vehicle_id, s.id, 'proceed_to_stall', p_clock, p_sim_run_id)->>'ok')::boolean, false)
     ORDER BY s.stall_code, s.id LIMIT 1;$o$,
$n$    -- 0820: the step reads the floor and the calendar itself, because the shared candidate source leaves out every
    -- post whose charger is Faulted (0372), and a cabin stop does not use the charger (Chase, 2026-11-12). A faulted
    -- post is taken first, so a working charger is left for a car that must charge.
    SELECT s.id INTO v_stall
      FROM public.stalls s
      JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot AND s.stall_type::text = 'dcfc'
       AND s.current_vehicle_id IS NULL AND s.status NOT IN ('maintenance','closed')
       AND (s.reserved_by IS NULL OR s.reserved_by = r.vehicle_id OR s.reservation_expires_at <= p_clock)
       AND ch.station_state::text IN ('Available', 'Faulted')
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                        WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                          AND b.state IN ('held','active','done','interrupted')
                          AND b.during && tstzrange(p_clock, v_until, '[)'))
       AND COALESCE((ottoq.ottoq_validate_assignment(r.vehicle_id, s.id, 'proceed_to_stall', p_clock, p_sim_run_id)->>'ok')::boolean, false)
     ORDER BY (ch.station_state::text = 'Faulted') DESC, s.stall_code, s.id LIMIT 1;$n$),
-- (c) the clean is on the visit before the charge
(2, 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)',
$o$  -- (d), (e) the cars that wait for a stop: parked, fit to move, no charge to do, and an interior deep clean to do
$o$,
$n$  -- 0820 (c): a parked car that still has its charge to do, whose deep clean the needs card raised with no atom on
  -- the visit, gets the atom now. Its charge is then seated only on a fast-charger post
  -- (public.ottoq_charge_needs_cleaning_post), and that post's arm does the clean during the charge.
  IF NOT p_floor_only THEN
    FOR r IN
      SELECT c.vehicle_id
        FROM public.ottoq_vehicle_needs_card c
        JOIN public.vehicles v ON v.id = c.vehicle_id
       WHERE c.depot_id = p_depot AND v.home_depot_id = p_depot AND v.category = 'autonomous'
         AND v.current_state = 'staged_awaiting_service'
         AND 'interior_deep_clean' = ANY (COALESCE(c.must_do_now, '{}'::text[]))
         AND v.current_soc < COALESCE((SELECT vn.target_soc FROM public.ottoq_visit_needs vn
                 WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                   AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                       = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                 ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) - 1
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                          WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id
                            AND vn.status IN ('open','in_progress') AND a->>'svc' = 'interior_deep_clean'
                            AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
       ORDER BY c.vehicle_id
       LIMIT 20
    LOOP
      PERFORM public.ottoq_cabin_stop_mark(p_sim_run_id, p_depot, r.vehicle_id, p_clock, NULL);
    END LOOP;
  END IF;

  -- (d), (e) the cars that wait for a stop: parked, fit to move, no charge to do, and an interior deep clean to do
$n$),
-- (b) the kernel's own proposer offers such a car fast-charger posts only
(3, 'public.ottoq_l2_propose_stall_assignment(uuid,uuid,jsonb)',
$o$       AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds'
       /* 0446 (G179)$o$,
$n$       AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds'
       /* 0820: a car with a cabin clean to do is charged only on a fast-charger post, whose arm cleans it during the
          charge: one stop, not two. False for every car with wash_bay_exterior_only off. */
       AND (s.stall_type::text = 'dcfc' OR NOT public.ottoq_charge_needs_cleaning_post(v_run, p_vehicle_id))
       /* 0446 (G179)$n$),
-- (b) the charge step declines any proposer's answer that is not a fast-charger post, for such a car
(4, 'public.ottoq_decide_tick(uuid)',
$o$    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
$o$,
$n$    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
    /* 0820: a car with a charge and a cabin clean to do is seated only on a fast-charger post, so both are done in one
       stop (Chase, 2026-11-12). Any proposer's other answer is declined, as an abstention that says what it declined;
       the car keeps its place in the charge line. */
    IF NOT COALESCE((v_proposal->>'abstain')::boolean, false)
       AND public.ottoq_charge_needs_cleaning_post(p_sim_run_id, v_req.vehicle_id)
       AND NOT EXISTS (SELECT 1 FROM stalls sp WHERE sp.id = NULLIF(v_proposal->>'stall_id', '')::uuid
                                                 AND sp.stall_type::text = 'dcfc') THEN
      v_proposal := jsonb_build_object('abstain', true, 'reason', 'waits_for_a_fast_charger_post_for_its_cabin_clean',
                                       'declined_stall_id', v_proposal->>'stall_id',
                                       'declined_source', v_proposal->>'source');
    END IF;
$n$);

-- (a) the shield is not handed a charger the stop does not use. FOUND BY THIS FILE'S OWN V3 ON ITS FIRST SEND: 0817
-- put the post in the shield's context as stall_id, and HW.002.charger_state_precondition (block) reads the charger
-- of that stall and refuses a Faulted one. It is right to, for a charge. A cabin stop starts no charge, so the post
-- goes in under its own name, as the needs card's bay seats pass the shield with no stall at all.
INSERT INTO _0820_patch VALUES
(5, 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)',
$o$                                   'cabin_post_stop', true, 'stall_id', v_stall, 'wait_min', round(r.wait_min::numeric, 1),$o$,
$n$                                   'cabin_post_stop', true, 'cabin_stop_post', v_stall, 'wait_min', round(r.wait_min::numeric, 1),$n$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0820_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(to_regprocedure(p.fn));
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0820 V2: anchor % in % matches % times, not 1', p.seq, p.fn, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(p.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0820: % is not stored as patched (patch %)', p.fn, p.seq;
    END IF;
  END LOOP;
END $patch$;

DO $v1$
DECLARE f record; p record; v_def text;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0820_patch LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0820_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_def := replace(v_def, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s
                                     WHERE s.label = '0820_pre'
                                       AND s.schema_name || '.' || s.object_name = split_part(f.fn, '(', 1)) THEN
      RAISE EXCEPTION '0820 V1: % with its patches reversed is not its pre-image', f.fn;
    END IF;
  END LOOP;
END $v1$;

-- ── V3: the behaviour, staged on a past run, inside a block that is rolled back ──
-- (1) a full car with a deep clean to do, every fast charger Faulted: the step seats it on a faulted post;
-- (2) the confirm, THEN THE TWIN'S WASH TRIAGE, then the arm's starter: the car is still on its post and the deep
--     program begins;
-- (3) a car below its target with a deep clean to do: the test is true, the kernel's proposer offers it no L2 (it
--     abstains while every fast charger is Faulted), and with the dial at 0 the test is false.
CREATE TEMP TABLE _0820_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_full uuid; v_low uuid; v_post uuid; v_visit uuid; v_atom jsonb; v_out jsonb;
  v_state text; v_stall uuid; v_prop jsonb; v_res jsonb; v_post_state text;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, now()) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot ORDER BY r.started_at DESC LIMIT 1;
  SELECT v.id INTO v_full FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs n
                      WHERE n.vehicle_id = v.id AND n.sim_run_id = v_run AND n.status IN ('open','in_progress'))
   ORDER BY v.id LIMIT 1;
  SELECT v.id INTO v_low FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous' AND v.id <> v_full
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs n
                      WHERE n.vehicle_id = v.id AND n.sim_run_id = v_run AND n.status IN ('open','in_progress'))
   ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_full IS NULL OR v_low IS NULL THEN
    INSERT INTO _0820_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past run or no two cars to stage'));
    RETURN;
  END IF;
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('wash_bay_exterior_only', 'cabin_robot_deep_clean', 'stall_cabin_robot', 'cabin_found_item_rate');
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'wash_bay_exterior_only', 1, '0820 self-test', now()),
           ('run', v_run, 'cabin_robot_deep_clean', 1, '0820 self-test', now()),
           ('run', v_run, 'stall_cabin_robot', 2, '0820 self-test', now()),
           ('run', v_run, 'cabin_found_item_rate', 0, '0820 self-test', now());
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;

    -- the floor: every fast-charger post free, EVERY ONE OF THEIR CHARGERS FAULTED
    UPDATE public.vehicles SET current_stall_id = NULL
     WHERE current_stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available',
                             reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE depot_id = c_depot AND stall_type::text = 'dcfc';
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available' WHERE current_vehicle_id IN (v_full, v_low);
    UPDATE public.ottoq_ocpp_chargers ch SET station_state = 'Faulted', last_heartbeat_at = v_clock
      FROM public.stalls s WHERE s.ocpp_charger_id = ch.charger_id AND s.depot_id = c_depot AND s.stall_type::text = 'dcfc';
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = GREATEST(v_clock, booked_at_sim),
                                           release_reason = '0820 self-test'
     WHERE sim_run_id = v_run AND state IN ('held','active')
       AND stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_stall_id = NULL,
           current_soc = CASE WHEN id = v_full THEN 100 ELSE 50 END,
           last_state_change = v_clock - interval '5 minutes',
           robotic_tether_until = NULL, robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,
           robotic_tether_phase = NULL,
           config = COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type'
     WHERE id IN (v_full, v_low);
    v_visit := public.ottoq_cabin_stop_mark(v_run, c_depot, v_full, v_clock, NULL);
    PERFORM public.ottoq_cabin_stop_mark(v_run, c_depot, v_low, v_clock, NULL);

    -- (3) the car that still has its charge to do
    IF NOT public.ottoq_charge_needs_cleaning_post(v_run, v_low) THEN
      RAISE EXCEPTION '0820 V3: a car with a deep clean to start does not need a cleaning post for its charge';
    END IF;
    v_prop := public.ottoq_l2_propose_stall_assignment(v_low, c_depot,
                jsonb_build_object('current_soc', 50, 'now_ts', v_clock));
    IF NOT COALESCE((v_prop->>'abstain')::boolean, false) AND v_prop->>'stall_type' IS DISTINCT FROM 'dcfc' THEN
      RAISE EXCEPTION '0820 V3: the proposer offered a car with a cabin clean to do a charger that is not a fast post (%)', v_prop;
    END IF;

    -- (1) the full car, on a post whose charger is faulted
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, true);
    v_out := public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, false);
    SELECT a INTO v_atom FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    v_post := (v_atom->>'cabin_stop_stall_id')::uuid;
    SELECT ch.station_state::text INTO v_post_state
      FROM public.stalls s JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id WHERE s.id = v_post;
    IF v_post IS NULL OR v_post_state IS DISTINCT FROM 'Faulted' THEN
      RAISE EXCEPTION '0820 V3: the full car was not seated on a post whose charger is faulted (%; atom %; charger %)',
        v_out, v_atom, v_post_state;
    END IF;
    IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                WHERE n.vehicle_id = v_low AND n.sim_run_id = v_run AND a ? 'cabin_stop_stall_id') THEN
      RAISE EXCEPTION '0820 V3: a car that still has its charge to do was given a cabin stop';
    END IF;

    -- (2) the confirm, the twin's wash triage, then the arm's starter
    PERFORM twin.ottoq_sim_confirm_commands(v_run, v_clock + interval '30 seconds');
    PERFORM twin.ottoq_sim_wash_triage(c_depot, v_clock + interval '30 seconds');
    SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM public.vehicles v WHERE v.id = v_full;
    IF v_state <> 'charge_complete_holding' OR v_stall IS DISTINCT FROM v_post THEN
      RAISE EXCEPTION '0820 V3: after the wash triage the car does not stand on its post (state %, stall %)', v_state, v_stall;
    END IF;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock + interval '1 minute');
    SELECT a INTO v_atom FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = v_visit AND a->>'svc' = 'interior_deep_clean';
    IF v_atom->>'status' <> 'in_progress' OR v_atom->>'robot_stall_id' <> v_post::text THEN
      RAISE EXCEPTION '0820 V3: the arm of the faulted post did not begin the deep program (%)', v_atom;
    END IF;

    -- the dial at 0
    UPDATE public.ottoq_policy_params SET param_value = 0
     WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'wash_bay_exterior_only';
    IF public.ottoq_charge_needs_cleaning_post(v_run, v_low) THEN
      RAISE EXCEPTION '0820 V3: with the dial at 0 a car still needs a cleaning post';
    END IF;

    v_res := jsonb_build_object('ran', true, 'run', v_run, 'full_car', v_full, 'post', v_post, 'post_charger', v_post_state,
               'seated_on_a_faulted_post', true, 'held_through_the_wash_triage', true, 'deep_program_begun', true,
               'car_to_charge', v_low, 'offered_only_a_fast_post', true,
               'proposal_with_every_fast_charger_faulted', COALESCE(v_prop->>'reason', v_prop->>'stall_type'),
               'no_cabin_stop_for_a_car_to_charge', true, 'dial_0_unchanged', true);
    RAISE EXCEPTION USING ERRCODE = 'P0820', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0820' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0820 self-test') THEN
    RAISE EXCEPTION '0820 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0820_selftest VALUES (v_res);
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0820_a_cabin_stop_may_use_a_post_whose_charger_is_faulted_and_a_car_to_charge_and_clean_waits_for_a_fast_charger',
        false, false,
        'Behind wash_bay_exterior_only (0817; default 0, at which the new test is false and no new branch is reached). '
        'At the twin depot (1): a cabin stop may stand on a fast-charger post whose charger is Faulted, taken first; a '
        'car with a charge and an interior deep clean to do is seated only on a fast-charger post, so its arm cleans '
        'the cabin during the charge (Chase, 2026-11-12: one stop, not two); and a deep clean the needs card raised is '
        'written to the visit before the charge. V3 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0820_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-12 at 16:34:17 UTC (10:34 AM CT), ledger 20261112163417, through apply_migration, on the SECOND send.
--   No run was live and nothing was in flight (P0). The text sent was this file from BEGIN to COMMIT.
--   THE FIRST SEND WAS STOPPED BY V3, and nothing was applied: the step found a post whose charger was Faulted and
--   did not seat the car on it (not_seated 1). Read from the source: 0817 handed the shield the post as stall_id, and
--   HW.002.charger_state_precondition (block) reads that stall's charger. Patch 5 was added and the second send
--   passed, which is the evidence that the shield was the gate: nothing else changed between the sends.
--   V3 (rolled back) staged run 56d8465f with every fast charger Faulted: full car 00cc3d0a was seated on post
--   765adddb (charger Faulted), stood there through the confirm and the twin's wash triage, and the post's arm began
--   the deep program; car 02ff42a9, at 50% with a deep clean to do, was offered no charger by the kernel's proposer
--   (no_compatible_available_stall, with L2s standing free) and was given no cabin stop; and with the dial at 0 the
--   new test is false. Stored after the apply, md5(prosrc): ottoq_cabin_post_stops
--   0fd70c1d7e9a0367fd655b8537948c60, ottoq_decide_tick 6b139ccf90d5e24b900f0eb87ab802ac,
--   ottoq_l2_propose_stall_assignment 5a6e4b5469103d79c8ea80f489a1a195, ottoq_charge_needs_cleaning_post
--   ec01337f6e4ea0fc7b633feb80e61ec2. Demo run 0e3cc3c2 was started at 16:34:26 UTC for the check rule 12 asks for.
