-- migration-version: 20261019134637
-- migration-name:    a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges
--
-- 0758  **A fast charger's cleaning arm cleans the cabin while the car charges.** (G476)
--       Chase, 2026-10-19: an overhead robot arm at each robotic fast-charger stall cleans the car's cabin while it
--       charges. The doors open, the charge arm mates, the cleaning arm cleans one side, then the other, and retracts; the
--       doors close, the charge completes, the charge arm retracts, and the car goes to its next step as OTTO-Q set it.
--       "the interior cleaning should usually always finish in just a few minutes since it's basically a vacuum and a
--       Potential puffer or dusting or even blowout or something. That should only take several minutes on each side
--       while the average charge might take around 15 to 30 minutes to top off to completion." Under a dial, the interior
--       tidy of a car charging on a fast charger is that stall's arm's work: it starts as the charge is connected, takes
--       no technician, runs the arm's cycle, and the car stays on the stall until the arm is home. The renderer plays the
--       doors and both arms against the times the snapshot now publishes for each step.
--
-- ══ §1 WHAT THE TWIN DOES TODAY, MEASURED (read-only, 2026-10-19 between 8:06 and 8:26 AM CT) ═══════════════════════════
--
--   The interior tidy (service_cadence_policy interior_tidy: lane cabin, 5 minutes) is a technician's: the concurrent
--   starter (public.ottoq_start_concurrent_atoms) starts a cabin atom only while one of the depot's general_tech pool (10
--   at the twin depot) is free, and 0511 holds a charging visit's cabin work for the charger. On arm 108
--   (seeds23_normal_2026_10_17 / dcfc10.otto_q, seed 305838298283560562, run 36b8891b, the depot as built, in tick) the
--   run's 71 interior tidies went: 23 started during a fast charge, a mean 9.3 minutes after the session began (median
--   5.0, longest 15.0); 28 during a standard charge (mean 10.4); 20 outside any charge, 13 of them not started by the run's
--   end. Every one was a technician's. The arm takes the first 23 off the technicians and starts them at once.
--
-- ══ §2 WHAT THIS CHANGES (all behind stall_cabin_robot; 0, set nowhere, changes nothing) ═════════════════════════════════
--
--   (a) Three dials, a person's, not agent-writable: stall_cabin_robot (0 or 1), cabin_robot_side_min (2.5) and
--       cabin_robot_motion_min (0.8). The arm's cycle is 2 x side + motion, 5.8 minutes at the defaults.
--   (b) The starter: with the dial on, a must-do interior_tidy of a car in charging_dcfc on a fast-charger stall, with
--       its charge session active on that stall in the run, starts in the same pass with no technician: status
--       in_progress, started_at the pass's clock, ends_at started_at + the cycle, performed_by 'stall_cabin_robot',
--       robot_stall_id the stall, robot_cycle_min the cycle. Only when the charge still has at least the cycle to run by
--       the planner's own estimate (ottoq_estimate_charge_minutes from the SoC now to ottoq_effective_target_soc_at, the
--       one target rule 9 allows, as the depot cards read a charge before it has run), so the arm is home before the
--       charge ends; otherwise the tidy is left to the technicians as today. The technician pool no longer counts work
--       the arm does, exactly as it does not count the charger's sensors' (0511).
--   (c) The hold: ottoq.ottoq_uplink_transfer_holds, which 0695 gave OTTO-Q's charge disposition (ottoq_decide_tick),
--       the wash admission (twin.ottoq_sim_advance_service_flow) and the bay-booking activation
--       (ottoq.ottoq_activate_due_bay_reservations) so that live work holds its car, is also true while the arm's work
--       is in progress on the stall the car stands on. Those three are the movers that take a charged car off its
--       charger for its next work (0695 §1), and STEP 1.5 of the service flow keeps a charged car on its charger while
--       must-do work is open, so with the arm at work the car stays. The function keeps its name: three callers read it
--       by name, and 0755 (held at the connector) patches one of them.
--   (d) The completion step (twin.ottoq_sim_advance_visit_atoms) completes the arm's work at ends_at like any atom
--       (status done, done_at ends_at, the flow-contract leg closed, the need ledger credited, the task_completion
--       probe), and resets it to pending, nothing credited, the interruption recorded ('left_the_cabin_robot'), when the
--       car left the arm's stall before ends_at (only a path the hold does not cover, a charger fault or an emergency,
--       moves it), as 0519 does for the charger's sensors and 0695 for a transfer. The readiness check waits for it
--       (0657's rule, extended).
--   (e) The snapshot (public.ottoq_twin_snapshot) publishes, on every visit atom, started_at, ends_at and done_at (the
--       sim clock, as the engine wrote them; null when absent or not a JSON string) and robot_stall_id. The depot cards
--       (public.ottoq_depot_cards) publish started_at and ends_at on every need (stripped when absent, as the card's
--       other keys are). Every key either published before is unchanged. These two read for every started atom, the
--       technicians' included, so their output is new for any run, dial or no dial; nothing in the engine reads them.
--   (f) The research wing's pair, robocabin_normal_2026_10_19: the depot as built in tick (arm 108's cell on
--       value_2026_09_30's first seed), its control with stall_cabin_robot 0 and its treatment with 1, priority 18, after
--       everything already queued.
--
--   Not built, and why. The doors are not an engine object: robotaxis open and close their own powered doors (Zoox's open
--   automatically, Core77, read through search results 2026-10-19, its publication date not shown,
--   https://www.core77.com/posts/138537/Amazons-Zoox-the-Worlds-First-Purpose-Designed-Robotaxi-Launches; Waymo pays people to close doors left open and
--   says its next vehicles close their own, Fortune 2026-02-25,
--   https://fortune.com/2026/02/25/waymo-vehicles-doordash-gig-workers-close-doors/), so the renderer opens them as the
--   arm's cycle begins and closes them as it ends. ASSUMPTION: the car's doors open on the depot's command, inside the
--   cycle's motion minutes; a car without powered doors needs a person, which the twin does not model. Nor does the arm
--   work at a standard charger: the arm is a fast-charger post's, and every twin fast-charger post is robotic (it opens
--   an arm cycle on every fast charge, twin.arm_cycles).
--
-- ══ §3 THE ARM'S TIMES, AND THEIR SOURCES ══════════════════════════════════════════════════════════════════════════════
--
--   ASSUMPTION — pending R-21 (docs/research/requests/R-21-robotic-interior-cleaning-cycle-time.md): 2.5 minutes in the
--   cabin on each side, and 0.8 minutes of motion for both sides together (the doors, the swings over the roof, the
--   descents and the retracts). No public source gives a measured robot-arm interior cycle for a car. Bracketing it, each
--   read on its page on 2026-10-19: Teslarati (2026-07-13) says a robot arm could clean a Cybercab cabin between rides
--   "in under two minutes", the outlet's own framing, attributed to no one and not a Tesla specification
--   (https://www.teslarati.com/tesla-cleaning-robot-cybercab-robotaxi-service/); Aseon Labs (Robotics & Automation News,
--   2026-10-02) puts a whole robotic servicing cycle, charge connection, interior cleaning and inspection together, at
--   about 30 minutes, and a quick top-up, scan and tidy at about ten
--   (https://roboticsandautomationnews.com/2026/10/02/aseon-ceo-the-opportunity-is-to-make-vehicle-servicing-as-autonomous-as-driving/105477/);
--   US 12,686,365 B2 (GM Cruise Holdings, filed 2023-04-06, granted 2026-07-21) describes robotic cleaners at a cleaning
--   facility's parking spots that "can move along a track, such as a floor rail or an overhead gantry track", and two on
--   one vehicle cleaning it "in half the time" of one, with no time in minutes; it also has the dispatch system command
--   the car to open its doors (https://patents.google.com/patent/US12686365B2/en, read on the page 2026-10-19; the USPTO
--   PDF answered 403). R-21 now carries these, dated, as partial answers.
--   Chase's "several minutes on each side" against a 15-30 minute charge is the brief. The twin's tick is 5 sim-minutes,
--   so a 5.8-minute cycle holds its car one or two ticks past its start, as every timed atom does.
--
-- ══ §4 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the five functions are the bodies read (prosrc md5s below), 0757 is applied, no dial or
--   sweep this file creates exists, and no open visit carries the arm's performer or key. P2 not already applied.
--   Pre-images to ottoq_schema_snapshots as '0758_pre'. Each anchor matches once in its function. V1 each body less its
--   changes is its pre-image. V2 the dials are catalogued as declared and no parameter row sets them. V3 the pair is
--   queued as declared. No probe calls the starter or the completion step on live: both write the depot's visits.
--   tests/test_stall_cabin_robot_sql.py runs this file on the scratch PostgreSQL against the live bodies (md5 asserted):
--   at the default nothing moves; with the dial a fast-charging car's tidy starts at once, takes no technician and
--   leaves the pool for the rest, runs the cycle, completes at ends_at, and holds the car; a car on a standard charger, a
--   car whose charge has less than the cycle left, a non-must-do tidy, and a car with no active session are left to the
--   technicians; a car moved off the stall mid-cycle has its tidy reset and the interruption recorded; and 0758 refuses
--   a second apply, a body it did not read, and a database without 0757.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at the default the starter, the hold and the completion step decide exactly as before (V1, and
--   every new branch needs performed_by 'stall_cabin_robot', which only the dial-on starter writes); the snapshot and the
--   depot cards are read paths no certification atom digests. No certification pair, canon cell or dial experiment
--   sets the dial. forces_dial_restart FALSE for the same reason, and because moving the dial floor re-queues every
--   active sweep's cells.
--
-- ══ §6 THE LIVE DEMO ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   A demo run reads its dials at depot scope (public.ottoq_policy_get: run, then depot, then global), and so does every
--   research arm for a dial its cell does not set. So the dial is not set at depot scope by this file: the arms queued for
--   the window that opens at 11:00 PM CT on 2026-10-19 would change under it. After that window closes (6:00 AM CT on
--   2026-10-20), the twin's live demo gets the arm with one statement, a person's:
--     SELECT public.ottoq_policy_set('depot', '11111111-1111-1111-1111-111111111111', 'stall_cabin_robot', 1, '<name>');
--   and every queued cell without the key then reads 1 too, so the cells queued before it are pinned to 0 first, in the
--   same change (robocabin's two cells set it both ways already).
--
-- ROLLBACK: EXECUTE the five `definition`s in ottoq_schema_snapshots WHERE label = '0758_pre'; if no arm of
--   robocabin_normal_2026_10_19 has run, DELETE its two cells and the sweep; DELETE the three dials' catalog rows;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0758 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the five functions, the dials and the pair, as read ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM 'f7d87d5db9cf120e6e94ed802525882b'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)'))
       IS DISTINCT FROM 'e586ee275d120d70d637e3d87b2330a1'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM '3e8eb3f4babb8d3005cf383e0372f9e9'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_twin_snapshot(uuid)'))
       IS DISTINCT FROM 'ea1a4a9a28762aaf8958f05ccdc2dcc3'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_depot_cards(uuid,uuid)'))
       IS DISTINCT FROM 'c4530de93479b56241defb705fc09a63' THEN
    RAISE EXCEPTION '0758 P1: a function this file patches is not the body it was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0757_a_bay_seat_that_finished_early_is_done') THEN
    RAISE EXCEPTION '0758 P1: 0757 is not applied; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('stall_cabin_robot', 'cabin_robot_side_min', 'cabin_robot_motion_min'))
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params
                 WHERE param_key IN ('stall_cabin_robot', 'cabin_robot_side_min', 'cabin_robot_motion_min'))
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'robocabin_normal_2026_10_19') THEN
    RAISE EXCEPTION '0758 P1: a dial or the sweep this file creates exists already';
  END IF;
  -- nothing has ever written the arm's performer, so every patched path is idle until the dial is set
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
              WHERE vn.status IN ('open', 'in_progress')
                AND (a ? 'robot_stall_id' OR a->>'performed_by' = 'stall_cabin_robot')) THEN
    RAISE EXCEPTION '0758 P1: an open visit already carries the cleaning arm''s work';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges') THEN
    RAISE EXCEPTION '0758 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0758_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'::regprocedure,
                 'ottoq.ottoq_uplink_transfer_holds(uuid,uuid)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_twin_snapshot(uuid)'::regprocedure,
                 'public.ottoq_depot_cards(uuid,uuid)'::regprocedure);

-- ── (a) the dials ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('stall_cabin_robot',
        '0758 (G476): 1 = at a fast-charger stall, its cleaning arm does the car''s must-do interior tidy while the car '
        'charges: it starts as the charge session is active, when the charge has at least the arm''s cycle left by the '
        'planner''s estimate; it takes no technician; it runs 2 x cabin_robot_side_min + cabin_robot_motion_min; and the '
        'car stays on the stall until the arm is home. 0 = the interior tidy waits for a technician, as before 0758. '
        'Research days only until certified.',
        0, 0, 1,
        'public.ottoq_start_concurrent_atoms; ottoq.ottoq_uplink_transfer_holds; twin.ottoq_sim_advance_visit_atoms',
        false),
       ('cabin_robot_side_min',
        '0758 (G476): minutes the fast-charger stall''s cleaning arm spends in the cabin on each side (vacuum, air '
        'blow-out, dusting). ASSUMPTION pending R-21: no public source gives a measured robot-arm interior cycle for a car.',
        2.5, 0.5, 10, 'public.ottoq_start_concurrent_atoms', false),
       ('cabin_robot_motion_min',
        '0758 (G476): minutes of the cleaning arm''s motion outside the cabin for both sides together (the doors, the '
        'swings over the roof, the descents and the retracts). ASSUMPTION pending R-21.',
        0.8, 0.1, 5, 'public.ottoq_start_concurrent_atoms', false);

-- ── the patches: (b) the starter, (c) the hold, (d) the completion step, (e) the snapshot and the depot cards ──
CREATE TEMP TABLE _0758_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0758_patch VALUES
  -- S1: the starter's variables for the arm
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 1,
   $s1o$  v_uplink boolean;   -- 0695: whether that stall has a wired data uplink (a charger or a service bay)
BEGIN
$s1o$,
   $s1n$  v_uplink boolean;   -- 0695: whether that stall has a wired data uplink (a charger or a service bay)
  -- 0758: the cleaning arm of the car's fast-charger stall (stall_cabin_robot), and its cycle
  v_run uuid; v_robot_dial boolean := false; v_robot boolean := false; v_robot_cycle numeric; v_robot_left numeric;
BEGIN
$s1n$),
  -- S2: the technician pool does not count the arm's work
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 2,
   $s2o$             AND COALESCE(a2->>'performed_by', '') <> 'charger_sensors'))
$s2o$,
   $s2n$             AND COALESCE(a2->>'performed_by', '') <> 'charger_sensors'
             -- 0758: nor does the cleaning arm of a fast-charger stall
             AND COALESCE(a2->>'performed_by', '') <> 'stall_cabin_robot'))
$s2n$),
  -- S3: whether the arm takes this car's tidy, read once for the car
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 3,
   $s3o$  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
$s3o$,
   $s3n$  -- 0758: with stall_cabin_robot on, the interior tidy of a car charging on a fast charger is done by that stall's
  -- cleaning arm, during the charge: no technician, timed by the arm's cycle (two sides and its motion), and only when
  -- the charge still has at least the cycle to run by the planner's own estimate, so the arm is home before the charge
  -- ends. Off, nothing past the dial is read.
  SELECT r0.sim_run_id INTO v_run FROM public.ottoq_sim_runs r0
   WHERE r0.status = 'running' AND r0.depot_id = v_depot ORDER BY r0.started_at DESC LIMIT 1;
  v_robot_dial := COALESCE(public.ottoq_policy_get(v_run, 'stall_cabin_robot', 0), 0) >= 1;
  IF v_robot_dial AND COALESCE(v_state, '') = 'charging_dcfc'
     AND EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text = 'dcfc') THEN
    v_robot_cycle := 2 * GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_side_min', 2.5), 2.5))
                     + GREATEST(0, COALESCE(public.ottoq_policy_get(v_run, 'cabin_robot_motion_min', 0.8), 0.8));
    -- the minutes left on the car's active session at this stall: the planner's charge model from the SoC now to the
    -- car's own target (ottoq_effective_target_soc_at, rule 9's one answer), as the depot cards read a fresh charge
    SELECT public.ottoq_estimate_charge_minutes(
             v.current_soc, public.ottoq_effective_target_soc_at(v.id, p_clock), ch.max_kw, v.inlet_max_kw,
             v.battery_capacity_kwh, COALESCE(os.ambient_temp_c, 22) + 5,
             COALESCE((v.config->>'battery_soh_pct')::numeric, 95), 1.0)
      INTO v_robot_left
      FROM public.ocpp_sessions os
      JOIN public.stalls st ON st.id = os.stall_id
      JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
      JOIN public.vehicles v ON v.id = os.vehicle_id
     WHERE os.vehicle_id = p_vehicle AND os.stall_id = v_stall AND os.status = 'active'
       AND os.sim_run_id IS NOT DISTINCT FROM v_run
     ORDER BY os.started_at DESC LIMIT 1;
    v_robot := v_robot_cycle > 0 AND COALESCE(v_robot_left, 0) >= v_robot_cycle;
  END IF;
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
$s3n$),
  -- S4: the arm starts the tidy, and needs no technician
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 4,
   $s4o$      ELSIF v_a->>'concurrency' = 'digital' OR v_sensors OR v_free > 0 THEN
$s4o$,
   $s4n$      -- 0758: the fast-charger stall's cleaning arm does the must-do interior tidy, and needs no technician
      ELSIF v_robot AND v_a->>'svc' = 'interior_tidy' AND COALESCE((v_a->>'must_do')::boolean, false) THEN
        v_a := v_a || jsonb_build_object('status', 'in_progress',
                'started_at', to_jsonb(p_clock),
                'ends_at', to_jsonb(p_clock + make_interval(secs => (round(v_robot_cycle * 60))::double precision)),
                'performed_by', 'stall_cabin_robot', 'robot_stall_id', v_stall, 'robot_cycle_min', v_robot_cycle);
        v_started := v_started + 1;
      ELSIF v_a->>'concurrency' = 'digital' OR v_sensors OR v_free > 0 THEN
$s4n$),
  -- H1: the hold's header
  ('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)', 1,
   $h1o$  -- every car while no run raises a transfer.
$h1o$,
   $h1n$  -- every car while no run raises a transfer.
  -- 0758: the cleaning arm of the fast-charger stall a car stands on, at work in that car, holds it too (below).
$h1n$),
  -- H2: the arm's work in progress holds its car on the arm's stall
  ('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)', 2,
   $h2o$     WHERE v.id = p_vehicle AND COALESCE((a->>'needs_uplink')::boolean, false)
       AND COALESCE(a->>'status', 'pending') IN ('pending', 'in_progress'))
$h2o$,
   $h2n$     WHERE v.id = p_vehicle
       AND ((COALESCE((a->>'needs_uplink')::boolean, false)
             AND COALESCE(a->>'status', 'pending') IN ('pending', 'in_progress'))
            -- 0758: and the cleaning arm of the stall the car stands on, at work in the car (its doors open, the arm in
            -- the cabin): the car stays until the arm's cycle ends. Only 0758's dial-on starter writes this performer.
            OR (a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'in_progress'
                AND a->>'robot_stall_id' = v.current_stall_id::text)))
$h2n$),
  -- A1: the arm's work whose car left the arm's stall goes back to pending
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 1,
   $a1o$      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'charger_sensors' AND v_a->>'sensor_stall_id' IS NOT NULL
$a1o$,
   $a1n$      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'stall_cabin_robot' AND v_a->>'robot_stall_id' IS NOT NULL
         AND v_rec.current_stall_id::text IS DISTINCT FROM v_a->>'robot_stall_id' THEN
        -- 0758: a fast-charger stall's cleaning arm cleans only the car on its stall. This car left it before the arm's
        -- cycle ran out (only a path the hold does not cover moves it: a charger fault, an emergency), so the cabin was
        -- not cleaned: back to pending, for a technician or another stall's arm, the interruption recorded and nothing
        -- credited, as 0519 does for the charger's sensors.
        v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'robot_stall_id' - 'robot_cycle_min')
               || jsonb_build_object('status', 'pending',
                    'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                        'at', p_clock, 'reason', 'left_the_cabin_robot',
                        'started_at', v_a->'started_at', 'stall_id', v_a->'robot_stall_id')));
        v_changed := true;
      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'charger_sensors' AND v_a->>'sensor_stall_id' IS NOT NULL
$a1n$),
  -- A2: the readiness check does not count such work as finishing in this pass
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 2,
   $a2o$                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'uplink_stall_id')::uuid),
                                   false)) THEN
$a2o$,
   $a2n$                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'uplink_stall_id')::uuid)
                                   -- 0758: nor a cabin clean whose car left its cleaning arm's stall
                                   AND NOT (COALESCE(o->>'performed_by','') = 'stall_cabin_robot'
                                            AND o->>'robot_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id::text IS DISTINCT FROM o->>'robot_stall_id'),
                                   false)) THEN
$a2n$),
  -- N1: the snapshot publishes each atom's times and the arm's stall
  ('public.ottoq_twin_snapshot(uuid)', 1,
   $n1o$                       'est_min', CASE WHEN a.value->>'est_min' ~ '^[0-9]+(\.[0-9]+)?$'
                                       THEN (a.value->>'est_min')::numeric END)
                     ORDER BY a.ord)
$n1o$,
   $n1n$                       'est_min', CASE WHEN a.value->>'est_min' ~ '^[0-9]+(\.[0-9]+)?$'
                                       THEN (a.value->>'est_min')::numeric END,
                       -- 0758: when the work started and ends and when it was done (the sim clock, as the engine wrote
                       -- them), and the stall whose cleaning arm does it, so the renderer plays the arm on the twin's own
                       -- times. Each is null when absent; a value that is not a JSON string reads null.
                       'started_at', CASE WHEN jsonb_typeof(a.value->'started_at') = 'string' THEN a.value->'started_at' END,
                       'ends_at', CASE WHEN jsonb_typeof(a.value->'ends_at') = 'string' THEN a.value->'ends_at' END,
                       'done_at', CASE WHEN jsonb_typeof(a.value->'done_at') = 'string' THEN a.value->'done_at' END,
                       'robot_stall_id', a.value->>'robot_stall_id')
                     ORDER BY a.ord)
$n1n$),
  -- C1: the depot cards publish each need's times
  ('public.ottoq_depot_cards(uuid,uuid)', 1,
   $c1o$                                 'triage_verdict', a->>'triage_verdict')))
$c1o$,
   $c1n$                                 'triage_verdict', a->>'triage_verdict',
                                 /* 0758: when the work started and ends, the sim clock, as the engine wrote them */
                                 'started_at', a->>'started_at', 'ends_at', a->>'ends_at')))
$c1n$);

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0758_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0758_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0758: anchor % of % matches % times, not 1', p.seq, f, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0758: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each body less its changes is its pre-image ──
DO $v1$
DECLARE r record; p record; v_body text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
             ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 'f7d87d5db9cf120e6e94ed802525882b'),
             ('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)', 'e586ee275d120d70d637e3d87b2330a1'),
             ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', '3e8eb3f4babb8d3005cf383e0372f9e9'),
             ('public.ottoq_twin_snapshot(uuid)', 'ea1a4a9a28762aaf8958f05ccdc2dcc3'),
             ('public.ottoq_depot_cards(uuid,uuid)', 'c4530de93479b56241defb705fc09a63')) AS x(fn, pre) LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = r.fn::regprocedure;
    FOR p IN SELECT * FROM _0758_patch WHERE fn = r.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM r.pre THEN
      RAISE EXCEPTION '0758 V1: % less its changes is not its pre-image (md5 %)', r.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── (f) the research wing's pair, after everything already queued ──
WITH s AS (
  INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                              seeds, replicates, priority, arm_budget_s, status, run_after, notes,
                                              created_by)
  VALUES ('robocabin_normal_2026_10_19',
          'The fast chargers'' cleaning arms on the depot as built: the interior tidy by the technicians or by the arm',
          '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
          ARRAY[686364201590009433]::bigint[], 0, 18, 3000, 'active', NULL,
          '0758 (G476). Cell 1 is arm 108''s cell (seeds23_normal_2026_10_17 / dcfc10.otto_q) on value_2026_09_30''s first '
          'seed (its seed-1 partner is arm 93) with stall_cabin_robot 0 set explicitly; cell 2 differs only by '
          'stall_cabin_robot 1. Read: the technician-minutes the arm takes off the general_tech pool, the waits of the '
          'tidies the technicians still do, any car held on its charger by the arm, and the day''s throughput. Priority '
          '18: after everything already queued.',
          'research_wing')
  RETURNING sweep_id)
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params,
                                                 control_cell_code)
SELECT s.sweep_id, 'dcfc10.otto_q.cabin_crews', 1, 'otto_q', 'dcfc10',
       '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9, "stall_cabin_robot": 0}'::jsonb, NULL
  FROM s;
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params,
                                                 control_cell_code)
SELECT s.sweep_id, 'dcfc10.otto_q.cabin_robot', 2, 'otto_q', 'dcfc10',
       '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9, "stall_cabin_robot": 1}'::jsonb,
       'dcfc10.otto_q.cabin_crews'
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'robocabin_normal_2026_10_19';

-- ── V2: the dials, as declared; V3: the pair, as declared ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE NOT COALESCE(agent_writable, false)
         AND ((param_key, default_value, min_value, max_value) = ('stall_cabin_robot', 0, 0, 1)
           OR (param_key, default_value, min_value, max_value) = ('cabin_robot_side_min', 2.5, 0.5, 10)
           OR (param_key, default_value, min_value, max_value) = ('cabin_robot_motion_min', 0.8, 0.1, 5))) <> 3
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params
                 WHERE param_key IN ('stall_cabin_robot', 'cabin_robot_side_min', 'cabin_robot_motion_min')) THEN
    RAISE EXCEPTION '0758 V2: the dials are not catalogued as declared, or a parameter row sets one';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'robocabin_normal_2026_10_19' AND s.priority = 18 AND s.status = 'active'
         AND c.buildout_code = 'dcfc10' AND c.seat = 'otto_q'
         AND (c.fixed_params - 'stall_cabin_robot') = '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9}'::jsonb
         AND c.fixed_params ->> 'stall_cabin_robot' = CASE c.ord WHEN 1 THEN '0' ELSE '1' END) <> 2 THEN
    RAISE EXCEPTION '0758 V3: the pair is not queued as declared';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges', false, false,
        'G476. Dials stall_cabin_robot (default 0), cabin_robot_side_min (2.5), cabin_robot_motion_min (0.8). With the '
        'dial, public.ottoq_start_concurrent_atoms starts a must-do interior_tidy of a car in charging_dcfc on a '
        'fast-charger stall with an active session there, when the planner''s estimate of the charge left is at least '
        'the arm''s cycle (2 x side + motion): no technician, performed_by stall_cabin_robot, robot_stall_id the stall, '
        'ends_at start + cycle, and the technician pool does not count it; ottoq.ottoq_uplink_transfer_holds holds the '
        'car on that stall while it is in progress; twin.ottoq_sim_advance_visit_atoms resets it to pending, nothing '
        'credited, if the car left the stall before ends_at, and its readiness check waits for it. At 0 none of it '
        'runs (V1: each body less its changes is its pre-image). public.ottoq_twin_snapshot publishes started_at, '
        'ends_at, done_at and robot_stall_id on every visit atom, and public.ottoq_depot_cards started_at and ends_at '
        'on every need: read paths no certification atom digests. Queued robocabin_normal_2026_10_19 (priority 18). '
        'No certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-19 13:46:37 UTC (8:46 AM CT), ledger version 20261019134637 ══════════════════════════════════════
--
--   Dry-run first on live, between 8:41 and 8:45 AM CT (clocks read at 13:41:47 and 13:45:30 UTC): the executable part
--   and a test world in one execute_sql ending in a block that raises, so it rolled back. Every premise and check
--   passed, and on the live bodies: two test cars charging on NASH-DCFC-STALL-01 and -02, each with an active session;
--   the first, at the default, had its tidy started by a technician (5 minutes, no performer); the second, with the dial
--   set at its run's scope, by the arm (performed_by stall_cabin_robot, robot_stall_id the stall, sim 14:00:00 to
--   14:05:48, 5.8 minutes); the hold read false and true; the snapshot and the cards carried the new keys; the completion
--   step six sim-minutes on closed both, done_at equal to ends_at. Then through apply_migration, no run live and nothing
--   in flight (read at 13:41:47 UTC; the file's own P0 at the apply). The text sent, BEGIN through COMMIT, is 22,225
--   characters, md5 bce5c9d71c082ae05dc5ffb33179530b, equal to the ledger's statements[1] read back. After it (prosrc
--   md5s, read at 13:47:03 UTC): starter ce0a831c29f421948d2d44f966cff233, hold dfd5d9d7b68066b2e933f5056bcaaceb,
--   completion step c1741376dc7e9d9597b5e8a15aed42e5, snapshot 9677506f209abc4db0c39bc1fbb0a440, depot cards
--   8257d524058e30d39d453475f5941f84, the bodies tests/test_stall_cabin_robot_sql.py reaches on the scratch database; 5
--   pre-images under '0758_pre'; the three dials catalogued and no parameter row setting any of them; the pair queued
--   (sweep a59672a8-ef79-42fb-af54-2856329f8c11), 19th and 20th of 129 pending tasks. Nothing here called the starter or
--   the completion step on live outside the rolled-back dry run.
