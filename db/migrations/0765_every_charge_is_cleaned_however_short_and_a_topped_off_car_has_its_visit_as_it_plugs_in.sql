-- migration-version: PENDING
-- migration-name:    every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in
--
-- 0765  **Every car that charges on a robotic post is cleaned by the post's overhead arm, however short the charge and
--       however the car came to charge.** (G484)
--
-- ══ §0 CHASE'S CALL ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-23, with 0764 on at the twin depot: "I guess the distinction is that cars populate random cleanings
--   that are essentially "alerts" of necessary cleaning that can send it back to a depot. BUT if the vehicle is
--   returning to charge anyway, it should always have a quick review and clean while it is sitting in the stall
--   already. SO random "alert cleanings" can still occur and be noted, but cars should be cleaned via overhead arm while
--   they charge always regardless. ... make sure that logic is backed into the code."
--
-- ══ §1 WHAT 0764 LEFT, MEASURED (run 3389e651, busy_day, read 2026-10-23 between 9:35 and 9:50 AM CT) ═════════════════
--
--   0764 (stall_cabin_robot 2, on since 9:19 AM CT) cleans every car charging on a post whose visit has no tidy, and it
--   works: by sim 14:31, 91 sim-minutes in, 31 routine cleans and 11 needed tidies by the arms, each routine clean
--   closing its own leg with a service record (27 of 27 done legs), and two cleans that outlasted their charge (by up
--   to 5.2 minutes) held their car and finished. Two gaps remain, and they are where every technician's tidy came from:
--   (a) A car with a visit cannot be cleaned when its charge has less than the arm's 5.8-minute cycle left: 0764 skips
--       the routine (1 visit so far), and 0758 leaves a needed tidy on such a charge to a technician after the charge.
--   (b) A car with no visit cannot be cleaned at all. A car parked at the depot when the run began is topped off by the
--       charge orchestrator (86-90% to 100%) with no visit, and the wash triage makes its visit only when the charge
--       ends; by then the car is off the charge, so the arm never sees it. At sim 13:51, 10 of the 26 cars charging had
--       no visit. Of the 14 interior tidies technicians had done by sim 14:31, 13 were on cars that charged before
--       their visit existed, and so were the 3 the triage cleared. The other 8 tidies were on cars not yet charged.
--
-- ══ §2 WHAT THIS CHANGES (all at stall_cabin_robot = 2; at 0 and 1 nothing decides differently) ════════════════════════
--
--   (a) The starter (public.ottoq_start_concurrent_atoms): at 2 the arm cleans the cabin however little of the charge
--       is left. The hold (0758 (c)) keeps the car on its post until the arm is home, at most one cycle past the end of
--       the charge, and the doors that move a car respect it (0760, 0761; 2 of 2 such cleans finished on 3389e651).
--       So a needed tidy on a short charge is the arm's (done sooner than a technician could do it after the charge,
--       and it must be done before the car leaves, rule 9), and the routine is not skipped. The one exception: an
--       owner's immediate turnaround (urgency immediate_dispatch) is not held past its charge for a routine clean it
--       did not need (rule 9: the owner's requirement, honored as asked); that visit's routine is recorded once as
--       'immediate_turnaround'. A needed tidy on that visit is still the arm's. A clean that outlasts the charge says
--       so in its record (the minutes left and the cycle). With no active session there is no charge to clean during,
--       and nothing is decided, as before.
--   (b) The routine's leg opens through the engine's own leg door, public.ottoq_itin_leg_open (as the charge sessions'
--       and the service flow's do), which finds the car's active itinerary in the run or starts one, so every routine
--       clean ends in a service record (0764 found the itinerary by the visit and wrote no leg when there was none). No
--       stall is passed to the door, so it binds no stall booking to the clean (the charge's booking stays the
--       charge's); the leg is then written to the post.
--   (c) The pre-arrival contracts (ottoq.ottoq_sim_prearrival_contracts), BACKSTOP 0, new: at 2, in the twin (the
--       depot's feed is sim), a car charging on a fast-charger post with no open visit in the run and no service list
--       gets its list now, from the same generator the wash triage calls for it when the charge ends, and with the run
--       as BACKSTOP 1 and the arrival path call it. The triage then reads this list instead of making one, as it does
--       for every car that arrived (the list is cleared only when the car is dispatched). So a topped-off car has its
--       visit, its arm's clean and its cabin and data work during the charge, as an arriving car does, once a stay. No
--       itinerary is planned: the car is on its charger already. A car with a list, a visit, a standard charger, or no
--       charge is left alone.
--   Unchanged: the completion step (twin.ottoq_sim_advance_visit_atoms) hands such a car to the starter, closes the
--   routine's leg by its id and cancels a routine whose car left the post, all as 0764 wrote it; the alert cleanings
--   (a rider's flag, a cabin found dirty, a deep clean) are still derived, recorded and done as needs, by the arm when
--   the car is charging on a post and otherwise by a technician or the detail bay; the triage and its escalations.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the bodies are those 0764 left and those read on live on 2026-10-23 (prosrc md5s: the
--   starter and the completion step as 0764 left them, the pre-arrival contracts, the leg door), the generator is
--   there, 0764 is applied and the dial is catalogued 0..2 as 0764 left it. P2 once. Pre-images to
--   ottoq_schema_snapshots as '0765_pre'. Each anchor matches once in its function, read with bare newlines whatever
--   line endings the paste carried. V1 each body less its changes is its pre-image. V3 each patched body is byte for
--   byte the one the tests ran (md5). V2 the dial is catalogued 0..2 with this file's description (this file sets no
--   dial value).
--   tests/test_every_charge_is_cleaned_sql.py runs this file on the scratch PostgreSQL over 0764's test world with the
--   live pre-arrival contracts and leg door (md5 asserted): at 0 and at 1 the same world leaves byte-identical visits,
--   legs and calls with and without 0765; at 2 a short charge is cleaned by the arm, holds its car and finishes after
--   the charge; a needed tidy on a short charge is the arm's; an immediate turnaround on a short charge is recorded and
--   not held, and its needed tidy is still the arm's; a topped-off car gets its list once, from the generator with the
--   run, no itinerary planned, and is cleaned through the completion step's own pass, its leg on the charge
--   orchestrator's itinerary (or a new one), closed by its id at the post; a car with a list, with a visit, on a
--   standard charger, en route, or at a depot whose feed is not sim is left alone; the leg binds no booking; 0765
--   pasted with Windows line endings applies to the same bodies; and it refuses a second apply, a body it did not read,
--   a database without 0764 and a dial not as 0764 left it.
--   Rehearsed on live on 2026-10-23 inside transactions rolled back: at 9:58 AM CT this file's text passed every check,
--   leaving the starter at md5 5b98fb1d and the pre-arrival contracts at 161fff04, as on the scratch PostgreSQL; at
--   10:00 AM CT the live generator, run with the run on three cars charging on posts (90%, 95% and 71%), wrote each its
--   list, cached, and an open visit with the charge to do, as it does for a car at the gate.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at 0 and 1 the starter and the pre-arrival contracts decide exactly as before (V1; every new
--   branch needs the dial at 2). forces_dial_restart FALSE: no cell, pair or experiment sets the dial to 2.
--
-- ══ §5 ON AT THE TWIN DEPOT (CLAUDE.md rule 12) ═════════════════════════════════════════════════════════════════════════
--
--   The twin depot's dial has been 2 since 0764, by Chase (2026-10-23, 9:19 AM CT), and this file changes what 2 does
--   as Chase asked, so it is on from each run's next pass after the apply. No statement is needed. Undo: the dial to 1
--   (0758's arm alone), or the rollback below.
--
-- ROLLBACK: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0765_pre'; UPDATE the catalog row's
--   description back to 0764's; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0765_every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in'. Visits, cleans and
--   legs already written stay as the record of what happened.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0765 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against, the generator, 0764, and the dial as 0764 left it ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM '002247aab125626b56e1424d79cfaa05'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)'))
       IS DISTINCT FROM 'd612cbeb5cd4f839f988b1451240dd5c' THEN
    RAISE EXCEPTION '0765 P1: a function this file patches is not the body it was written against';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM 'fb7cde232a1b8311eb2f768c812f4c9a'
     OR (SELECT md5(prosrc) FROM pg_proc
          WHERE oid = to_regprocedure('public.ottoq_itin_leg_open(uuid,uuid,uuid,timestamp with time zone,text,uuid,timestamp with time zone,jsonb,text)'))
       IS DISTINCT FROM '69effd4b79c76a99b2cb019410172164'
     OR to_regprocedure('twin.ottoq_sim_generate_service_manifest(uuid,uuid,bigint)') IS NULL THEN
    RAISE EXCEPTION '0765 P1: a function this file relies on is not the body it was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean') THEN
    RAISE EXCEPTION '0765 P1: 0764 is not applied; apply in order';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 2
         AND NOT COALESCE(agent_writable, false) AND description LIKE '%0764 (G483)%'
         AND description NOT LIKE '%0765%') <> 1 THEN
    RAISE EXCEPTION '0765 P1: stall_cabin_robot is not catalogued 0..2 as 0764 left it';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0765_every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in') THEN
    RAISE EXCEPTION '0765 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0765_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'::regprocedure,
                 'ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)'::regprocedure);

-- ── the dial's description says what 2 now does ──
UPDATE public.ottoq_policy_param_catalog
   SET description = '0758 (G476), 0764 (G483), 0765 (G484): 1 = at a fast-charger stall, its cleaning arm does the '
                     'car''s must-do interior tidy while the car charges: it starts as the charge session is active, '
                     'when the charge has at least the arm''s cycle left by the planner''s estimate; it takes no '
                     'technician; it runs 2 x cabin_robot_side_min + cabin_robot_motion_min; and the car stays on the '
                     'stall until the arm is home. 2 = every car that charges on a fast-charger post has its cabin '
                     'cleaned by the post''s arm during the charge, needed or not, however short the charge (the car '
                     'stays on the post until the arm is home, at most one cycle past the charge): a needed tidy is the '
                     'arm''s, and when the visit has no interior tidy to do, under way or done, the arm cleans it as a '
                     'routine (arm_routine) with its own itinerary leg, once a visit, except that an owner''s immediate '
                     'turnaround is not held past its charge for a routine clean; and a car charging there with no visit '
                     'and no service list (topped off) gets its list as it charges, so it is cleaned too (Chase, '
                     '2026-10-23). 0 = the interior tidy waits for a technician, as before 0758.',
       affects = 'public.ottoq_start_concurrent_atoms; ottoq.ottoq_uplink_transfer_holds; twin.ottoq_sim_advance_visit_atoms; '
                 'ottoq.ottoq_sim_prearrival_contracts'
 WHERE param_key = 'stall_cabin_robot';

-- ── the patches: (a) and (b) the starter, (c) the pre-arrival contracts ──
CREATE TEMP TABLE _0765_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0765_patch VALUES
  -- S1: the starter's variables
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 1,
   $s1o$  v_robot_every boolean := false; v_meta jsonb; v_itin uuid; v_leg uuid; v_routine jsonb;
BEGIN
$s1o$,
   $s1n$  v_robot_every boolean := false; v_meta jsonb; v_itin uuid; v_leg uuid; v_routine jsonb;
  v_robot_short boolean := false; v_urgency text;   -- 0765: a charge shorter than the arm's cycle; the visit's urgency
BEGIN
$s1n$),
  -- S2: (a) at 2 the arm cleans however little of the charge is left
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 2,
   $s2o$    v_robot := v_robot_cycle > 0 AND COALESCE(v_robot_left, 0) >= v_robot_cycle;
  END IF;
$s2o$,
   $s2n$    v_robot := v_robot_cycle > 0 AND COALESCE(v_robot_left, 0) >= v_robot_cycle;
    -- 0765: with stall_cabin_robot at 2 the arm cleans the cabin however little of the charge is left (Chase,
    -- 2026-10-23: "cars should be cleaned via overhead arm while they charge always regardless"). The hold keeps the car
    -- on its post until the arm is home, at most one cycle past the end of the charge, so a needed tidy is done sooner
    -- than a technician could do it after the charge, and the routine still happens (an owner's immediate turnaround
    -- excepted, below). With no active session there is no charge to clean during, and nothing changes.
    IF v_robot_every AND NOT v_robot AND v_robot_cycle > 0 AND v_robot_left IS NOT NULL THEN
      v_robot := true;
      v_robot_short := true;
    END IF;
  END IF;
$s2n$),
  -- S3: the visit's urgency, read with its meta
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 3,
   $s3o$    SELECT meta INTO v_meta FROM ottoq_visit_needs WHERE visit_id = v_visit;
$s3o$,
   $s3n$    SELECT meta, urgency INTO v_meta, v_urgency FROM ottoq_visit_needs WHERE visit_id = v_visit;   -- 0765: urgency
$s3n$),
  -- S4: (a) the immediate turnaround, and (b) the routine's leg through the engine's leg door
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 4,
   $s4o$      IF v_robot THEN
        SELECT i.itinerary_id INTO v_itin FROM ottoq_vehicle_itineraries i
         WHERE i.visit_id = v_visit AND i.status = 'active'
         ORDER BY i.sim_created_at DESC NULLS LAST, i.itinerary_id LIMIT 1;
        IF v_itin IS NOT NULL THEN
          INSERT INTO ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, to_stall_id,
                                            planned_start_sim, planned_end_sim, planned_duration_s, duration_basis,
                                            actual_start_sim, status)
          SELECT v_itin, v_run, p_vehicle, COALESCE(max(l.seq), 0) + 1, 'interior_tidy', v_stall,
                 p_clock, p_clock + make_interval(secs => (round(v_robot_cycle * 60))::double precision),
                 round(v_robot_cycle * 60),
                 jsonb_build_object('atom', 'interior_tidy', 'kind', 'stall_cabin_robot', 'arm_routine', true,
                                    'concurrent_with', 'charge'),
                 p_clock, 'active'
            FROM ottoq_itinerary_legs l WHERE l.itinerary_id = v_itin
          RETURNING leg_id INTO v_leg;
        END IF;
$s4o$,
   $s4n$      -- 0765: an owner's immediate turnaround is not held past its charge for a routine clean it did not need
      -- (rule 9); a needed tidy on that visit is still the arm's (0758's branch, above)
      IF v_robot AND NOT (v_robot_short AND COALESCE(v_urgency, '') = 'immediate_dispatch') THEN
        -- 0765: the leg opens through the engine's own leg door, which finds the car's active itinerary in the run or
        -- starts one (a topped-off car has only the charge orchestrator's), so every routine clean ends in a service
        -- record. No stall is passed, so the door binds no booking to the clean (the charge's stays the charge's); the
        -- leg is then written to the post.
        v_leg := public.ottoq_itin_leg_open(v_run, v_depot, p_vehicle, p_clock, 'interior_tidy', NULL,
                   p_clock + make_interval(secs => (round(v_robot_cycle * 60))::double precision),
                   jsonb_build_object('atom', 'interior_tidy', 'kind', 'stall_cabin_robot', 'arm_routine', true,
                                      'concurrent_with', 'charge'),
                   'stall_cabin_robot');
        UPDATE ottoq_itinerary_legs SET to_stall_id = v_stall WHERE leg_id = v_leg;
$s4n$),
  -- S5: what the routine records
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 5,
   $s5o$        v_routine := jsonb_build_object('at', p_clock, 'outcome', 'cleaned', 'stall_id', v_stall);
      ELSIF v_robot_left IS NOT NULL THEN
$s5o$,
   $s5n$        v_routine := jsonb_build_object('at', p_clock, 'outcome', 'cleaned', 'stall_id', v_stall)
                     -- 0765: a clean that outlasts the charge says so: the minutes the charge had left, and the cycle
                     || CASE WHEN v_robot_short THEN jsonb_build_object('charge_left_min', round(v_robot_left, 1),
                                                                         'cycle_min', v_robot_cycle)
                             ELSE '{}'::jsonb END;
      ELSIF v_robot THEN
        -- 0765: the immediate turnaround on a charge shorter than the cycle, recorded once
        v_routine := jsonb_build_object('at', p_clock, 'outcome', 'immediate_turnaround', 'stall_id', v_stall,
                                        'charge_left_min', round(v_robot_left, 1), 'cycle_min', v_robot_cycle);
      ELSIF v_robot_left IS NOT NULL THEN
$s5n$),
  -- P1: the pre-arrival contracts' variable
  ('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)', 1,
   $p1o$  v_yield_to_solver int := 0;
BEGIN
$p1o$,
   $p1n$  v_yield_to_solver int := 0;
  v_arm_every boolean := false;   -- 0765: stall_cabin_robot at 2, every car that charges is cleaned by its post's arm
BEGIN
$p1n$),
  -- P2: (c) BACKSTOP 0, a topped-off car's service list as it charges
  ('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)', 2,
   $p2o$
  -- BACKSTOP 1: en_route car with no workflow (AP-4 books at need-fire; this catches cars that
$p2o$,
   $p2n$
  -- 0765 BACKSTOP 0: with stall_cabin_robot at 2 (every car that charges is cleaned by its post's arm), in the twin, a
  -- car charging on a fast-charger post with no open visit in the run and no service list gets its list now, from the
  -- same generator the wash triage calls for it when the charge ends, with the run as BACKSTOP 1 calls it. A car parked
  -- at the depot when the run began is topped off by the charge orchestrator with no visit, so until now its visit was
  -- made after its charge and its arm never saw it (3389e651: 10 of 26 charging at sim 13:51; 13 of the 14 tidies
  -- technicians had done by sim 14:31). The triage then reads this list instead of making one, as for every car that
  -- arrived, and the list is cleared when the car is dispatched, so this is once a stay. No itinerary is planned: the
  -- car is on its charger already.
  v_arm_every := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 2
                 AND COALESCE((SELECT d.feed_mode FROM depots d WHERE d.id = v_depot), 'sim') = 'sim';
  IF v_arm_every THEN
    FOR v_rec IN
      SELECT v.id AS vehicle_id
        FROM vehicles v
        JOIN stalls s ON s.id = v.current_stall_id AND s.stall_type::text = 'dcfc'
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
         AND v.current_state = 'charging_dcfc'
         AND jsonb_typeof(v.config->'service_manifest') IS DISTINCT FROM 'array'
         AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                          WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                            AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id)
       ORDER BY v.id
       LIMIT 40
    LOOP
      PERFORM ottoq_sim_generate_service_manifest(v_rec.vehicle_id, p_sim_run_id, NULL);
      v_n := v_n + 1;
    END LOOP;
  END IF;

  -- BACKSTOP 1: en_route car with no workflow (AP-4 books at need-fire; this catches cars that
$p2n$);

-- The SQL editor delivers a paste with the line endings of the machine it came from: on 2026-10-23 at 10:26 AM CT this
-- file arrived with Windows line endings and its first anchor matched nothing, because the stored bodies end their lines
-- in a bare newline. Read with bare newlines, the anchors and their replacements are the file's whatever the paste
-- carried, and V3 holds the result to the bodies the tests ran.
UPDATE _0765_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0765_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0765_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0765: anchor % of % matches % times, not 1', p.seq, f, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0765: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body less its changes is its pre-image ──
DO $v1$
DECLARE r record; p record; v_body text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
             ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', '002247aab125626b56e1424d79cfaa05'),
             ('ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)', 'd612cbeb5cd4f839f988b1451240dd5c'))
             AS x(fn, pre) LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = r.fn::regprocedure;
    FOR p IN SELECT * FROM _0765_patch WHERE fn = r.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM r.pre THEN
      RAISE EXCEPTION '0765 V1: % less its changes is not its pre-image (md5 %)', r.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V3: the patched bodies are byte for byte the ones the scratch PostgreSQL ran and the live rehearsal produced ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '5b98fb1dbd54fb0baf9f39f77ca2660c'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '161fff049c1886a8b31794c27faa3c40' THEN
    RAISE EXCEPTION '0765 V3: a patched body is not the one the tests ran';
  END IF;
END $v3$;

-- ── V2: the dial, as declared, and set nowhere by this file ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 2
         AND NOT COALESCE(agent_writable, false) AND description LIKE '%0765 (G484)%') <> 1 THEN
    RAISE EXCEPTION '0765 V2: the dial is not catalogued 0..2 as declared';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0765_every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in', false, false,
        'G484. At stall_cabin_robot 2: public.ottoq_start_concurrent_atoms has the post''s arm clean however little of '
        'the charge is left (a needed tidy is the arm''s; a routine on an owner''s immediate turnaround with a charge '
        'shorter than the cycle is recorded once as immediate_turnaround and not held), and opens the routine''s leg '
        'through public.ottoq_itin_leg_open with no stall (no booking bound), then writes the post to it; '
        'ottoq.ottoq_sim_prearrival_contracts gains BACKSTOP 0: in the twin, a car charging on a fast-charger post '
        'with no open visit in the run and no service list gets its list from the generator with the run, no '
        'itinerary planned. At 0 and 1 none of it runs (V1). No certification arm, canon cell or dial experiment sets '
        'the dial to 2.',
        now());

COMMIT;
