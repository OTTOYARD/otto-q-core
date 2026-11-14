-- migration-version: 20261113003556
-- migration-name:    0822_a_due_cabin_clean_is_done_during_the_charge_and_a_cabin_stop_takes_its_turn_in_the_charge_line
--
-- 0822  **A cabin clean that is due is done during the charge. A car waiting for a cabin stop takes its turn in the
--        charge line.**
--
-- WHY. Chase, 2026-11-12 (evening), to the four items db/checks/0486 §6 left open: "Go ahead and close those open
-- items". Two of the four are measured away or seen (db/checks/0487). Two are real, and are these.
--
-- §1 THE TWO SECOND TRIPS THAT REMAINED (run 02ca304f). Cars c3333333-0003 and c8c7cd10 each charged for about an hour
--   with no clean on the visit, and took a cabin stop 95 to 113 minutes after the charge ended. Read from the source:
--   nothing in a run changes a cabin's condition but the run's start and a finished clean, so a clean that appears in
--   the middle of a day is the calendar: the car passed the needs card's must-do line, 1.08 of its 336-hour interval
--   (service_cadence_policy: must_do_at 'overdue', overdue_ratio 1.08). Read at the run's end, 2 of the depot's 116
--   cars would pass that line in the next 9 hours, which is the rate seen. NOT ESTABLISHED for these two cars
--   themselves: their profiles were rewritten when the clean was done.
--   The catalog already has an earlier line: 'due', at 1.00 of the interval. A car past it has gone its full interval
--   without a deep clean. The card does not force the clean for another 27 hours, and that is the gap the car fell in.
--
-- §2 THE LONG WAITS FOR A CABIN STOP (run 02ca304f): 29.8, 42.2, 46.9, 41.9, 92.7 and 112.7 minutes. Each tick the
--   charge step took every free post with a working charger, and the cabin-stop step read what was left: one faulted
--   post, which the waiting cars took one after another. A car with no charge to do stood behind EVERY car with a
--   charge to do, until the 90-minute floor. That is not the kernel's own order. Its line (0642) ranks by
--   (minutes waited + minutes of work) / minutes of work, so that a short job that has waited goes ahead of a long one
--   that has not. A cabin stop is 10.8 minutes of work.
--
-- §3 WHAT THIS DOES. Behind wash_bay_exterior_only (0817) and two new dials, both default 0 and both 1 at the twin depot.
--   (a) cabin_clean_when_due_at_charge: a car that still has its charge to do, and whose deep clean is DUE on the
--       needs card (not yet must-do), has the clean written to its visit before it is seated. Its charging post's arm
--       does it during the charge. Nothing changes for a car with no charge to do.
--   (b) cabin_stop_in_charge_line: in the step's first call of the tick, before the charge step, a car waiting for a
--       cabin stop is seated when its ratio, (minutes waited + the arm's program) / the arm's program, is at least
--       the highest ratio in the charge line (public.ottoq_charge_order_keys.minutes_key). Never ahead of a car on
--       immediate dispatch or a car at the floor: with either in the line, nothing changes. A faulted post is still
--       taken first (0820), so a working charger is used only when no faulted post is free.
--   (c) the decision row says which it was: waited_the_floor, or in_its_turn_in_the_charge_line.
--
-- §4 RULE 9, CHECKED. (a) does a needed service sooner, during a charge the car is taking anyway. (b) is ordering of
--   who is served next, which rule 9 names as an answer to site pressure. It can hold a working post for one arm's
--   program (about 15 minutes with the moves) while a car waits to charge. No charge is shortened or stopped.
--   RULE 14, CHECKED. (b) uses the kernel's own neutral ratio, reads no owner, and gives a cabin car the place that
--   ratio gives every car. It does not reorder within or across owners by anything else.
--   RULE 10: both dials are switched on here, at depot scope, under Chase's instruction to close the items.
--
-- §5 WHAT THIS DOES NOT DO.
--   - (a) makes the clean a must-do once it is written. If the arm cannot do it during the charge (the arm is down),
--     the car takes a cabin stop before it leaves, a day earlier than it would have.
--   - The check's futures (0620) do not know (b). They project the charge line without the cabin stops in it.
--
-- §6 PRECONDITIONS AND CHECKS. P0 nothing in flight, no run live. P1 the body this file was written against (md5 of
--   prosrc cfcf0e515c3b7e7c3e7758b72aa12277). P2 once. V1 the patched body with its patches reversed is its pre-image.
--   V2 every anchor matched once. V3 the behaviour, staged on a past run inside a block that is rolled back.
--
-- §7 CLASSIFICATION. forces_recert FALSE, forces_dial_restart FALSE: with wash_bay_exterior_only at 0 the step returns
--   before any of its body, and with the two new dials at 0 every new branch is false.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0822_pre'; DELETE the two dials' rows
--   from ottoq_policy_params and ottoq_policy_param_catalog; DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0822_%'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0822 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0822 P0: a run is live. V3 stages a past run as running, so apply between runs';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure)
       IS DISTINCT FROM 'cfcf0e515c3b7e7c3e7758b72aa12277' THEN
    RAISE EXCEPTION '0822 P1: public.ottoq_cabin_post_stops is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0822_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('cabin_clean_when_due_at_charge', 'cabin_stop_in_charge_line')) THEN
    RAISE EXCEPTION '0822 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0822_pre', 'function', 'public', 'ottoq_cabin_post_stops',
       pg_get_functiondef('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure));

-- ── the dials ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('cabin_clean_when_due_at_charge',
   '0822: 1 = a car that still has its charge to do, and whose interior deep clean is due on the needs card (its full '
   'interval has passed, though the card does not yet force it), has the clean written to its visit before it is '
   'seated, so its charging post''s arm does it during the charge. 0 = only a clean the card forces is written. Needs '
   'wash_bay_exterior_only at 1.',
   0, 0, 1, 'public.ottoq_cabin_post_stops', false),
  ('cabin_stop_in_charge_line',
   '0822: 1 = a car waiting for a cabin stop is seated before the charge step when its ratio, (minutes waited + the '
   'arm''s program) / the arm''s program, is at least the highest ratio in the charge line, and no car in that line is '
   'on immediate dispatch or at the wait floor. 0 = a cabin stop takes a post the charge step left free, or waits the '
   'floor (0817). Needs wash_bay_exterior_only at 1.',
   0, 0, 1, 'public.ottoq_cabin_post_stops', false);

CREATE TEMP TABLE _0822_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0822_patch VALUES
(1,
$o$  v_swept int := 0; v_released int := 0; v_dropped int := 0; v_seated int := 0; v_no_post int := 0; v_refused int := 0;$o$,
$n$  v_swept int := 0; v_released int := 0; v_dropped int := 0; v_seated int := 0; v_no_post int := 0; v_refused int := 0;
  v_due_clean boolean := false; v_in_line boolean := false; v_head_key numeric; v_head_first boolean;   -- 0822$n$),
(2,
$o$  IF v_floor <= 0 THEN v_floor := 90; END IF;
$o$,
$n$  IF v_floor <= 0 THEN v_floor := 90; END IF;

  -- 0822: read once, in the step's first call of the tick. (a) is a clean that is due done during the charge.
  -- (b) is the head of the charge line as the kernel's own order holds it: with no car on immediate dispatch or at
  -- the floor in it, a waiting cabin car whose ratio is at least the line's highest goes before the charge step.
  IF p_floor_only THEN
    BEGIN
      v_due_clean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_clean_when_due_at_charge', 0), 0) >= 1;
      IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_stop_in_charge_line', 0), 0) >= 1 THEN
        SELECT COALESCE(bool_or(o.immediate OR k.floor_key IS NOT NULL), false),
               max(k.minutes_key) FILTER (WHERE NOT o.immediate AND k.floor_key IS NULL)
          INTO v_head_first, v_head_key
          FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot, p_clock) o
          JOIN public.ottoq_charge_order_keys(p_sim_run_id, p_depot, p_clock) k ON k.vehicle_id = o.vehicle_id
         WHERE NOT COALESCE(o.holds_charger, false);
        v_in_line := NOT COALESCE(v_head_first, false) AND v_head_key IS NOT NULL AND v_cycle > 0;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0822 cabin stop, the charge line''s head: % %', SQLSTATE, SQLERRM;
      v_due_clean := false; v_in_line := false;
    END;
  END IF;
$n$),
(3,
$o$         AND v.current_state::text IN ('staged_awaiting_service', 'arrived_at_gate', 'charging_dcfc')
         AND 'interior_deep_clean' = ANY (COALESCE(c.must_do_now, '{}'::text[]))$o$,
$n$         AND v.current_state::text IN ('staged_awaiting_service', 'arrived_at_gate', 'charging_dcfc')
         AND ('interior_deep_clean' = ANY (COALESCE(c.must_do_now, '{}'::text[]))
              -- 0822 (a): or the clean is due, and the car is going to a post to charge anyway
              OR (v_due_clean AND c.cabin_urgency IN ('due', 'overdue', 'critical')))$n$),
(4,
$o$    WHERE (NOT p_floor_only OR q.wait_min >= v_floor)
      AND (q.has_atom$o$,
$n$    WHERE (NOT p_floor_only OR q.wait_min >= v_floor
           -- 0822 (b): or it is this car's turn by the charge line's own ratio
           OR (v_in_line AND (q.wait_min + v_cycle) / v_cycle >= v_head_key))
      AND (q.has_atom$n$),
(5,
$o$                                   'waited_the_floor', p_floor_only);$o$,
$n$                                   'waited_the_floor', (p_floor_only AND r.wait_min >= v_floor),
                                   'in_its_turn_in_the_charge_line', (p_floor_only AND r.wait_min < v_floor));$n$);

DO $patch$
DECLARE
  c_fn constant regprocedure := 'public.ottoq_cabin_post_stops(uuid,uuid,timestamptz,bigint,uuid,boolean)'::regprocedure;
  p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0822_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(c_fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0822 V2: anchor % matches % times, not 1', p.seq, n; END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(c_fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0822: the function is not stored as patched (patch %)', p.seq;
    END IF;
  END LOOP;
  v_def := pg_get_functiondef(c_fn);
  FOR p IN SELECT * FROM _0822_patch ORDER BY seq DESC LOOP
    v_def := replace(v_def, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_def) IS DISTINCT FROM (SELECT s.def_md5 FROM public.ottoq_schema_snapshots s WHERE s.label = '0822_pre') THEN
    RAISE EXCEPTION '0822 V1: the patched body with its patches reversed is not its pre-image';
  END IF;
END $patch$;

-- ── V3: the behaviour, staged on a past run, inside a block that is rolled back ──
-- Every fast-charger post free, its charger Available. Three cars: one full with a clean to do, parked 30 minutes;
-- one at 50% parked 5 minutes (the charge line); one at 50% at the gate whose clean is due and not yet must-do.
-- (1) both new dials at 0: the first call seats no cabin stop and writes no clean for the due car;
-- (2) both at 1: the first call writes the due car's clean, and seats the full car in its turn in the charge line.
CREATE TEMP TABLE _0822_selftest (result jsonb) ON COMMIT DROP;
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_full uuid; v_chg uuid; v_due uuid; v_res jsonb; v_frame jsonb;
  v_urg text; v_must boolean; v_head numeric; v_n int;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, now()) INTO v_run, v_clock
    FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot ORDER BY r.started_at DESC LIMIT 1;
  SELECT (array_agg(v.id ORDER BY v.id))[1], (array_agg(v.id ORDER BY v.id))[2], (array_agg(v.id ORDER BY v.id))[3]
    INTO v_full, v_chg, v_due
    FROM public.vehicles v
   WHERE v.home_depot_id = c_depot AND v.category = 'autonomous'
     AND EXISTS (SELECT 1 FROM public.vehicle_need_profile p WHERE p.vehicle_id = v.id)
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs n
                      WHERE n.vehicle_id = v.id AND n.sim_run_id = v_run AND n.status IN ('open','in_progress'));
  IF v_run IS NULL OR v_due IS NULL THEN
    INSERT INTO _0822_selftest VALUES (jsonb_build_object('ran', false, 'why', 'no past run or no three cars to stage'));
    RETURN;
  END IF;
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('wash_bay_exterior_only', 'cabin_robot_deep_clean', 'stall_cabin_robot', 'cabin_found_item_rate',
                         'cabin_clean_when_due_at_charge', 'cabin_stop_in_charge_line');
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'wash_bay_exterior_only', 1, '0822 self-test', now()),
           ('run', v_run, 'cabin_robot_deep_clean', 1, '0822 self-test', now()),
           ('run', v_run, 'stall_cabin_robot', 2, '0822 self-test', now()),
           ('run', v_run, 'cabin_found_item_rate', 0, '0822 self-test', now()),
           ('run', v_run, 'cabin_clean_when_due_at_charge', 0, '0822 self-test', now()),
           ('run', v_run, 'cabin_stop_in_charge_line', 0, '0822 self-test', now());
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = v_clock WHERE sim_run_id = v_run;

    -- the floor: the three cars are the only cars waiting, every post free with a working charger
    UPDATE public.vehicles SET current_state = 'deployed', current_stall_id = NULL
     WHERE home_depot_id = c_depot AND category = 'autonomous' AND id NOT IN (v_full, v_chg, v_due)
       AND current_state::text IN ('arrived_at_gate', 'staged_awaiting_service', 'charging_dcfc', 'charge_complete_holding');
    UPDATE public.vehicles SET current_stall_id = NULL
     WHERE current_stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available',
                             reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE depot_id = c_depot AND stall_type::text = 'dcfc';
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available'
     WHERE current_vehicle_id IN (v_full, v_chg, v_due);
    UPDATE public.ottoq_ocpp_chargers ch SET station_state = 'Available', last_heartbeat_at = v_clock
      FROM public.stalls s WHERE s.ocpp_charger_id = ch.charger_id AND s.depot_id = c_depot AND s.stall_type::text = 'dcfc';
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = GREATEST(v_clock, booked_at_sim),
                                           release_reason = '0822 self-test'
     WHERE sim_run_id = v_run AND state IN ('held','active')
       AND stall_id IN (SELECT s.id FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type::text = 'dcfc');
    UPDATE public.vehicles
       SET current_state = CASE WHEN id = v_due THEN 'arrived_at_gate' ELSE 'staged_awaiting_service' END::public.vehicle_state,
           current_stall_id = NULL,
           current_soc = CASE WHEN id = v_full THEN 100 ELSE 50 END,
           last_state_change = v_clock - CASE WHEN id = v_full THEN interval '30 minutes' ELSE interval '5 minutes' END,
           robotic_tether_until = NULL, robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,
           robotic_tether_phase = NULL,
           config = COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type'
     WHERE id IN (v_full, v_chg, v_due);
    UPDATE public.vehicle_need_profile
       SET cabin_condition = 'clean',
           last_deep_clean_at = v_clock - make_interval(secs => (CASE WHEN vehicle_id = v_due THEN 1.02 ELSE 0.2 END
                                                                  * deep_clean_interval_h * 3600)::double precision)
     WHERE vehicle_id IN (v_full, v_chg, v_due);
    SELECT c.cabin_urgency, 'interior_deep_clean' = ANY (c.must_do_now) INTO v_urg, v_must
      FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_due;
    IF v_urg IS DISTINCT FROM 'due' OR v_must THEN
      RAISE EXCEPTION '0822 V3: the staged car''s clean is not due-and-not-forced on the card (urgency %, must-do %)', v_urg, v_must;
    END IF;
    PERFORM public.ottoq_cabin_stop_mark(v_run, c_depot, v_full, v_clock, NULL);
    SELECT max(k.minutes_key) INTO v_head
      FROM public.ottoq_charge_queue_kernel_order(v_run, c_depot, v_clock) o
      JOIN public.ottoq_charge_order_keys(v_run, c_depot, v_clock) k ON k.vehicle_id = o.vehicle_id;
    IF v_head IS NULL THEN
      RAISE EXCEPTION '0822 V3: the staged charge line has no ratio to compare with';
    END IF;

    -- (1) the dials at 0
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, true);
    IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                WHERE n.sim_run_id = v_run AND n.status IN ('open','in_progress')
                  AND ((n.vehicle_id = v_full AND a ? 'cabin_stop_stall_id')
                       OR (n.vehicle_id = v_due AND a->>'svc' = 'interior_deep_clean'))) THEN
      RAISE EXCEPTION '0822 V3: with the dials at 0 the first call seated a stop or wrote a due clean';
    END IF;

    -- (2) the dials at 1
    UPDATE public.ottoq_policy_params SET param_value = 1
     WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('cabin_clean_when_due_at_charge', 'cabin_stop_in_charge_line');
    PERFORM public.ottoq_cabin_post_stops(v_run, c_depot, v_clock, 0, NULL, true);
    SELECT count(*) INTO v_n FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id = v_due AND n.sim_run_id = v_run AND n.status IN ('open','in_progress')
       AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status','pending') = 'pending';
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0822 V3: the due clean of the car at the gate is not on its visit (% atoms)', v_n;
    END IF;
    SELECT d.context_frame INTO v_frame FROM public.ottoq_decisions d
     WHERE d.sim_run_id = v_run AND d.entity_id = v_full AND d.sim_clock = v_clock
       AND d.proposed_action->>'source' = 'cabin_post_stop' AND d.outcome_status = 'enacted';
    IF v_frame IS NULL OR NOT COALESCE((v_frame->>'in_its_turn_in_the_charge_line')::boolean, false)
       OR COALESCE((v_frame->>'waited_the_floor')::boolean, true) THEN
      RAISE EXCEPTION '0822 V3: the full car was not seated in its turn in the charge line (head ratio %, frame %)',
        v_head, v_frame;
    END IF;

    v_res := jsonb_build_object('ran', true, 'run', v_run, 'full_car', v_full, 'car_to_charge', v_chg, 'due_car', v_due,
               'charge_line_head_ratio', round(v_head, 2), 'cabin_car_ratio', round((30 + 10.8) / 10.8, 2),
               'dials_0_first_call_changes_nothing', true, 'due_clean_written_before_the_charge', true,
               'cabin_stop_seated_in_its_turn', true, 'post_charger', v_frame->>'cabin_stop_post_charger');
    RAISE EXCEPTION USING ERRCODE = 'P0822', MESSAGE = v_res::text;       -- undo everything the test wrote
  EXCEPTION WHEN SQLSTATE 'P0822' THEN
    v_res := SQLERRM::jsonb;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE updated_by = '0822 self-test') THEN
    RAISE EXCEPTION '0822 V3: the self-test left something behind';
  END IF;
  INSERT INTO _0822_selftest VALUES (v_res);
END $v3$;

-- ── on at the twin depot (rule 12) ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'cabin_clean_when_due_at_charge', 1,
        'Chase (delegated to Claude Code: 0822)', now()),
       ('depot', '11111111-1111-1111-1111-111111111111', 'cabin_stop_in_charge_line', 1,
        'Chase (delegated to Claude Code: 0822)', now());

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0822_a_due_cabin_clean_is_done_during_the_charge_and_a_cabin_stop_takes_its_turn_in_the_charge_line',
        false, false,
        'Behind wash_bay_exterior_only (0817) and two new dials, default 0 and 1 at the twin depot. '
        'cabin_clean_when_due_at_charge: a car with a charge to do whose deep clean is due on the needs card has the '
        'clean written before it is seated. cabin_stop_in_charge_line: a car waiting for a cabin stop is seated before '
        'the charge step when its ratio is at least the charge line''s highest, never ahead of immediate dispatch or '
        'the floor. V3 self-test at apply (rolled back): '
        || COALESCE((SELECT result::text FROM _0822_selftest LIMIT 1), 'no result'),
        now());

COMMIT;

-- APPLIED 2026-11-13 at 00:35:56 UTC (6:35 PM CT on 2026-11-12), ledger 20261113003556, through apply_migration, on
--   the first send. No run was live and nothing was in flight (P0). The text sent was this file from BEGIN to COMMIT.
--   V3 (rolled back) staged run 02ca304f with every fast charger Available: with both dials at 0 the step's first
--   call seated no stop and wrote no clean; with both at 1 it wrote the due clean of gate car 03726c33 (due on the
--   card, not forced) to its visit, and seated full car 00cc3d0a, parked 30 minutes (ratio 3.78), ahead of the charge
--   line (car 02ff42a9, head ratio 1.10), its decision row reading in_its_turn_in_the_charge_line. Stored after the
--   apply, md5(prosrc): ottoq_cabin_post_stops 67fee5903960ab8732cd6f07dda46d73.
