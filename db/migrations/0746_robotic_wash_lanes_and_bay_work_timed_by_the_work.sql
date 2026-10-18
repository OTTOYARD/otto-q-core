-- migration-version: 20261018111429
-- migration-name:    robotic_wash_lanes_and_bay_work_timed_by_the_work
--
-- 0746  **The twin times a car's work in a wash bay by the work, and can run the wash bays as robotic lanes.** (G460)
--       Chase, 2026-10-17 evening CT: the wash bays can be assumed robotic, both exterior and interior. The exterior is
--       a classic pull-through wash with simplified steps. For the interior, an attendant may open the doors and a robot
--       arm vacuums and wipes. Research wing, rule 10: a dial, measured in the twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 between 7:10 and 7:20 PM CT; db/checks/0452 queries (1)-(2)) ═════════════
--
--   The twin's bays do not time the work. They work for as long as the car's booking has left. Every door into a wash,
--   detail or service bay writes the car's timer from its booking: the activation pins it to the booking's end
--   (ottoq.ottoq_activate_due_bay_reservations, 0016), the command door does the same (twin.ottoq_sim_confirm_commands,
--   floored one minute ahead), and the service flow's own seats take the crews' 9 / 25 / 40 minutes. The decide books a
--   walk-in at one tick and the twin seats the car at the next, five sim-minutes later. On the 11 completed runs at the
--   twin depot since 2026-10-16 (6 normal days, 5 busy days), read from each seat's own state-change event:
--                          seats   timer: mean / p10 / p50 / p90   end = booking end   seated after booking start
--     normal, wash bay      164         4.0 /  4.0 /  4.0 /  4.0         154                 4.9 min
--     normal, detail        220        19.1 / 16.8 / 20.0 / 20.0         197                 5.5
--     normal, service bay    85        40.8 / 35.0 / 39.0 / 50.0          81                 6.0
--     busy,   wash bay      276         4.1 /  4.0 /  4.0 /  5.0         260                 4.8
--     busy,   detail        266        19.8 / 20.0 / 20.0 / 20.0         248                 4.9
--   So a wash takes 4 minutes, the 9-minute booking less the tick the command waits, and a detail takes 20 of its 25.
--   The crews' times (9 and 25 minutes, each drawn 0.7-1.3x; ottoq_variability_catalog wash_time, detail_time) never
--   apply to these seats, and nothing varies. The wash lane has been running about twice as fast as the twin's own crew
--   model says it can, and it is the line at forty posts (G457, G458).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dials, none agent-writable, all research only until certified:
--         wash_lane_physics (0..2, default 0). 0: as before. 1: the twin times each wash or detail seat by the work, at
--           the depot's crews' times (9 and 25 minutes, the same draw STEP 2 uses, keyed to the car and its seat), and
--           two wash supervisors still gate three bays. 2: robotic lanes: a pull-through exterior wash and, for the
--           interior, a door attendant and a robot arm with the exterior wash in the same bay; the lane is gated by its
--           bays alone.
--         robotic_wash_min (2..15, default 5.0) and robotic_detail_min (6..40, default 16.5): the twin's robotic cycle
--           times at 2, each car drawn within +-15% and +-20% (docs/research/direct/2026-10-17-robotic-wash-and-interior-
--           cycle-times.md §2; the robot's 10 minutes inside 16.5 is an ASSUMPTION pending R-21).
--   (b) twin.ottoq_sim_bay_work_minutes(run, car, bay state, seat): the minutes the world takes for one seat. NULL below
--       1, and always NULL for the service bay, which this file does not change.
--   (c) twin.ottoq_sim_time_bay_work(run, depot, clock): at 1 or 2, before the service flow's STEP 1, each car in a wash
--       or detail bay is timed once per seat, from the minute it entered the bay (its last_state_change), whichever door
--       seated it. Its timer and its bay need's timer are rewritten together, so STEP 1 still credits the work the seat
--       was for; the engine's planned end is kept beside it as bay_plan_ends_at. The booking stays the engine's plan. A
--       car whose work outruns its booking stays in its bay, and one that finishes early leaves early. The decide's
--       release trims the booking to the true end, so the bay is free on the calendar from that tick.
--   (d) public.ottoq_wash_lane_staff_gate(run, depot): how many cars the wash lane's staff can attend at once. Below 2,
--       the depot's wash supervisors, as before. At 2, NULL, which LEAST ignores, so the lane is gated by its bays. It
--       replaces the supervisor count at its three readers: the service flow's STEP 2, decide section (4b) and the
--       charge-off wash admission (public.ottoq_l2_propose_charge_disposition).
--   (e) Sweep robowash_normal_2026_10_18 on forty robotic posts, three cells on value_2026_09_30's first seed: the
--       control (arm 84's cell), the crews timed by the work (1), and robotic lanes (2). normal_day from 6 AM CT for 12
--       hours at 5 sim-minutes a tick, priority 14, arm budget 3,000 s.
--   Not changed: what a car needs, which bay a need goes to, what the engine books, or when a car may leave (rule 9).
--   The engine still books its usual windows, 9 and 25 minutes or the planner's leg. At 2 they are longer than the work,
--   so a seat ends early and its window is freed. A learned service clock that books what the work takes is the next
--   step, and is not this file. The twin's 5-minute tick still rounds a car's exit up to the next tick: a 5-minute
--   robotic wash holds its bay one tick or two. This understates a short robotic cycle against a real lane that turns
--   as each car leaves.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the three bodies are the ones this file patches (prosrc md5: the service flow 06d9b26b, the
--   decide 1063735e, the charge-off wash admission 9e6ca1d9); the functions the new ones call exist; no dial, function
--   or sweep of this file exists; arm 84's cell is as read. P2 not already applied. Pre-images to ottoq_schema_snapshots
--   as '0746_pre'. Each anchor matches once. V1 each body less its insertions is its pre-image. V2 at the dial's default
--   the staff gate is the depot's supervisors, the work's minutes are NULL and nothing is timed. V3 the dials are
--   catalogued as declared and the sweep's cells are arm 84's plus the dial. The new functions are executed by
--   tests/test_robotic_wash_lanes_sql.py (the charge-off wash admission as live, md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the three patched bodies do what they did
--   before (V1, V2: the gate returns the same count the replaced call returned), the timing pass returns before reading
--   a car, and no certification arm, canon cell or dial experiment sets the dials.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0746_pre'; DROP FUNCTION
--   twin.ottoq_sim_time_bay_work(uuid, uuid, timestamptz), twin.ottoq_sim_bay_work_minutes(uuid, uuid, text, timestamptz),
--   public.ottoq_wash_lane_staff_gate(uuid, uuid); if no arm has run, DELETE the sweep robowash_normal_2026_10_18 and
--   its cells and the three dials' catalog rows;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0746_robotic_wash_lanes_and_bay_work_timed_by_the_work'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0746 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, the functions called, arm 84's cell, nothing of this file ──
DO $premises$
DECLARE f text;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'))
     IS DISTINCT FROM '06d9b26bb7db293cfeb3ff5fc6e7512c' THEN
    RAISE EXCEPTION '0746 P1: twin.ottoq_sim_advance_service_flow is not the body this file patches (md5 06d9b26b)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM '1063735e0908ada638317616a7f8cc53' THEN
    RAISE EXCEPTION '0746 P1: public.ottoq_decide_tick is not the body this file patches (md5 1063735e)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'))
     IS DISTINCT FROM '9e6ca1d95a3053ce4f50901cb723c0d5' THEN
    RAISE EXCEPTION '0746 P1: public.ottoq_l2_propose_charge_disposition is not the body this file patches (md5 9e6ca1d9)';
  END IF;
  FOREACH f IN ARRAY ARRAY['public.ottoq_policy_get(uuid,text,numeric)',
                           'public.ottoq_depot_staffing_count(uuid,text)',
                           'public.ottoq_twin_deal(uuid,text,text,timestamp with time zone,integer,bigint,text)',
                           'twin.ottoq_sim_clock_salt(uuid,timestamp with time zone)',
                           'twin.ottoq_sim_service_minutes(uuid,text,numeric)'] LOOP
    IF to_regprocedure(f) IS NULL THEN
      RAISE EXCEPTION '0746 P1: % is missing', f;
    END IF;
  END LOOP;
  IF to_regprocedure('twin.ottoq_sim_bay_work_minutes(uuid,uuid,text,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_sim_time_bay_work(uuid,uuid,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_wash_lane_staff_gate(uuid,uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('wash_lane_physics', 'robotic_wash_min', 'robotic_detail_min'))
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'robowash_normal_2026_10_18') THEN
    RAISE EXCEPTION '0746 P1: a function, a dial or the sweep of this file already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_power_normal_2026_10_17' AND c.cell_code = 'dcfc40.otto_q'
                    AND c.buildout_code = 'dcfc40' AND c.seat = 'otto_q' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND s.seeds[1] = 686364201590009433
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0746 P1: arm 84''s cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0746_robotic_wash_lanes_and_bay_work_timed_by_the_work') THEN
    RAISE EXCEPTION '0746 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0746_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure,
                 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure);

-- ── (a) the dials ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('wash_lane_physics',
        '0746 (G460): how the twin''s wash and detail bays work. 0 = as before 0746: a seat works for as long as its '
        'booking has left (a walk-in wash 4 minutes, the 9-minute booking less the tick the seat waits). 1 = each seat '
        'is timed by the work at the depot''s crews'' times (9 and 25 minutes, drawn 0.7-1.3x), and two wash supervisors '
        'gate three bays. 2 = robotic lanes: a pull-through exterior wash and a door attendant with a robot arm for the '
        'interior (robotic_wash_min, robotic_detail_min), gated by the bays alone. Research days only until certified.',
        0, 0, 2, 'twin.ottoq_sim_time_bay_work, public.ottoq_wash_lane_staff_gate', false),
       ('robotic_wash_min',
        '0746: the twin''s robotic pull-through exterior wash at wash_lane_physics 2, in minutes a car: pull in 0.5, '
        'program 4.0, pull out 0.5 (docs/research/direct/2026-10-17-robotic-wash-and-interior-cycle-times.md); each car '
        'drawn within +-15%. The world''s value, never read by the engine.',
        5.0, 2, 15, 'twin.ottoq_sim_bay_work_minutes', false),
       ('robotic_detail_min',
        '0746: the twin''s robotic interior clean with the exterior wash in the same bay, at wash_lane_physics 2, in '
        'minutes a car: pull in 0.5, attendant opens the doors 1.0, robot arm vacuums and wipes 10.0 (ASSUMPTION pending '
        'R-21), doors closed 0.5, exterior program 4.0, pull out 0.5; each car drawn within +-20%. The world''s value, '
        'never read by the engine.',
        16.5, 6, 40, 'twin.ottoq_sim_bay_work_minutes', false);

-- ── (b) the world's minutes for one seat ──
CREATE FUNCTION twin.ottoq_sim_bay_work_minutes(p_sim_run_id uuid, p_vehicle_id uuid, p_state text,
                                                p_seat timestamptz)
RETURNS numeric
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0746 (G460): how long the world takes for one seat in a wash or detail bay, or NULL where the twin does not time it
-- (below wash_lane_physics 1, and the service bay always). The draw is STEP 2's own card for the car and its seat, so at 1
-- a seat the service flow made keeps the minutes it was given, and the same car seated at the same sim-minute of two
-- same-seed arms draws the same factor at 1 and at 2.
DECLARE
  v_level int; v_key text; v_f numeric;
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_seat IS NULL
     OR p_state IS NULL OR p_state NOT IN ('in_wash_bay', 'in_detail_bay') THEN
    RETURN NULL;
  END IF;
  v_level := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'wash_lane_physics', 0), 0)::int;
  IF v_level < 1 THEN
    RETURN NULL;
  END IF;
  v_key := CASE WHEN p_state = 'in_detail_bay' THEN 'detail_time' ELSE 'wash_time' END;
  v_f := COALESCE(public.ottoq_twin_deal(p_sim_run_id, v_key,
                    p_vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_seat),
                    p_seat, (p_seat::date - DATE '2020-01-01'), 0), 1.0);
  IF v_level = 1 THEN
    RETURN round(twin.ottoq_sim_service_minutes(p_sim_run_id, v_key,
                   CASE WHEN p_state = 'in_detail_bay' THEN 25 ELSE 9 END) * v_f, 3);
  END IF;
  -- robotic: the machine's cycle varies less than a crew does, so the same draw spreads half as far for the exterior
  -- (0.7-1.3 -> 0.85-1.15) and two thirds as far for the interior (-> 0.80-1.20), where the mess in a car varies
  RETURN round(GREATEST(1, CASE WHEN p_state = 'in_detail_bay'
                 THEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'robotic_detail_min', 16.5), 16.5)
                      * (1 + (v_f - 1) * 2.0 / 3.0)
                 ELSE COALESCE(public.ottoq_policy_get(p_sim_run_id, 'robotic_wash_min', 5.0), 5.0)
                      * (1 + (v_f - 1) * 0.5) END), 3);
END
$fn$;
REVOKE ALL ON FUNCTION twin.ottoq_sim_bay_work_minutes(uuid, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_bay_work_minutes(uuid, uuid, text, timestamptz) TO service_role;

-- ── (c) the world times each seat once ──
CREATE FUNCTION twin.ottoq_sim_time_bay_work(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0746 (G460): at wash_lane_physics 1 or 2, each car in a wash or detail bay is timed once per seat by the work, from
-- the minute it entered the bay, whichever door seated it. Before 0746 its timer was its booking's end, so a walk-in
-- washed for 4 minutes and a detail for 20 of 25. Its bay need's timer moves with it when the two were bound, so the
-- service flow's STEP 1 credits the work the seat was for; the engine's planned end is kept as bay_plan_ends_at.
DECLARE
  v_rec record; v_min numeric; v_end timestamptz; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL
     OR COALESCE(public.ottoq_policy_get(p_sim_run_id, 'wash_lane_physics', 0), 0) < 1 THEN
    RETURN 0;
  END IF;
  FOR v_rec IN
    SELECT v.id, v.current_state::text AS state, v.last_state_change, v.config
      FROM public.vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.current_state IN ('in_wash_bay', 'in_detail_bay')
       AND v.last_state_change IS NOT NULL AND v.last_state_change <= p_clock
       AND NULLIF(v.config ->> 'bay_work_seat', '')::timestamptz IS DISTINCT FROM v.last_state_change
       AND NOT COALESCE((v.config ->> 'service_done')::boolean, false)
     ORDER BY v.id
  LOOP
    v_min := twin.ottoq_sim_bay_work_minutes(p_sim_run_id, v_rec.id, v_rec.state, v_rec.last_state_change);
    CONTINUE WHEN v_min IS NULL;
    v_end := v_rec.last_state_change + make_interval(secs => v_min * 60);
    UPDATE public.vehicles
       SET config = jsonb_set(
                      CASE WHEN jsonb_typeof(config -> 'bay_need') = 'object'
                                AND (config -> 'bay_need' ->> 'ends_at') IS NOT DISTINCT FROM (config ->> 'service_ends_at')
                           THEN jsonb_set(config, '{bay_need,ends_at}', to_jsonb(v_end::text))
                           ELSE config END,
                      '{service_ends_at}', to_jsonb(v_end::text))
                    || jsonb_build_object('bay_work_seat', v_rec.last_state_change::text,
                                          'bay_work_min', v_min,
                                          'bay_plan_ends_at', COALESCE(v_rec.config -> 'service_ends_at', 'null'::jsonb))
     WHERE id = v_rec.id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END
$fn$;
REVOKE ALL ON FUNCTION twin.ottoq_sim_time_bay_work(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_time_bay_work(uuid, uuid, timestamptz) TO service_role;

-- ── (d) the wash lane's staff gate ──
CREATE FUNCTION public.ottoq_wash_lane_staff_gate(p_sim_run_id uuid, p_depot_id uuid)
RETURNS integer
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0746 (G460): how many cars the wash lane's staff can attend at once. Robotic lanes (wash_lane_physics 2) need a person
-- for about a minute and a half of an interior seat and none for the exterior, so the lane is gated by its bays alone:
-- NULL, which LEAST ignores. Otherwise one wash supervisor for each car in the lane, as before 0746.
BEGIN
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'wash_lane_physics', 0), 0) >= 2 THEN
    RETURN NULL;
  END IF;
  RETURN public.ottoq_depot_staffing_count(p_depot_id, 'wash_supervisor');
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_wash_lane_staff_gate(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_wash_lane_staff_gate(uuid, uuid) TO service_role;

-- ── the three readers ──
CREATE TEMP TABLE _0746_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0746_patch VALUES
  -- 1: the service flow times each new seat before STEP 1 reads its timer
  (1, 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
   $o1$  -- ───── STEP 1: complete in-progress services (elapsed timer OR null-timer stuck) ─────
$o1$,
   $n1$  -- 0746 (G460): with wash_lane_physics on, the world times each new wash or detail seat by the work, from the
  -- minute the car entered the bay, before STEP 1 reads its timer. Off, this returns at once and nothing changes.
  IF v_feed_sim THEN PERFORM twin.ottoq_sim_time_bay_work(p_sim_run_id, p_depot_id, p_sim_clock_now); END IF;
  -- ───── STEP 1: complete in-progress services (elapsed timer OR null-timer stuck) ─────
$n1$),
  -- 2: the service flow's own wash admission reads the lane's staff gate
  (2, 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
   $o2$     LIMIT GREATEST(0, LEAST(v_wash_cap, ottoq_depot_staffing_count(p_depot_id,'wash_supervisor')) - v_in_wash)$o2$,
   $n2$     LIMIT GREATEST(0, LEAST(v_wash_cap, public.ottoq_wash_lane_staff_gate(p_sim_run_id, p_depot_id)) - v_in_wash)   -- 0746$n2$),
  -- 3: decide section (4b) reads the lane's staff gate
  (3, 'public.ottoq_decide_tick(uuid)'::regprocedure,
   $o3$      LEAST(ottoq_sim_lane_capacity(p_sim_run_id,'cleaning_staff', GREATEST(COALESCE(v_wash_phys,0),1)),
            ottoq_depot_staffing_count(v_depot,'wash_supervisor'))$o3$,
   $n3$      LEAST(ottoq_sim_lane_capacity(p_sim_run_id,'cleaning_staff', GREATEST(COALESCE(v_wash_phys,0),1)),
            public.ottoq_wash_lane_staff_gate(p_sim_run_id, v_depot))   -- 0746: the supervisors, or none for robotic lanes$n3$),
  -- 4: the charge-off wash admission reads the lane's staff gate
  (4, 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure,
   $o4$  v_wash_cap := LEAST(ottoq_sim_lane_capacity(v_run, 'cleaning_staff', v_phys),
                      ottoq_depot_staffing_count(p_depot_id, 'wash_supervisor'));$o4$,
   $n4$  v_wash_cap := LEAST(ottoq_sim_lane_capacity(v_run, 'cleaning_staff', v_phys),
                      public.ottoq_wash_lane_staff_gate(v_run, p_depot_id));   -- 0746: none for robotic lanes$n4$);

DO $patch$
DECLARE p record; f regprocedure; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0746_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0746_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0746: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0746: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record; f record;
BEGIN
  FOR f IN SELECT * FROM (VALUES
             ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
              '06d9b26bb7db293cfeb3ff5fc6e7512c'),
             ('public.ottoq_decide_tick(uuid)'::regprocedure, '1063735e0908ada638317616a7f8cc53'),
             ('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure,
              '9e6ca1d95a3053ce4f50901cb723c0d5')) x(fn, pre) LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = f.fn;
    FOR p IN SELECT * FROM _0746_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM f.pre THEN
      RAISE EXCEPTION '0746 V1: % less its insertions is not its pre-image (md5 %)', f.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: at the dial's default nothing is timed and the gate is the supervisors ──
DO $v2$
DECLARE v_run uuid := '00000000-0000-0000-0000-00000000746a'; v_depot uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  IF public.ottoq_wash_lane_staff_gate(v_run, v_depot)
     IS DISTINCT FROM public.ottoq_depot_staffing_count(v_depot, 'wash_supervisor') THEN
    RAISE EXCEPTION '0746 V2: at the default the staff gate is not the depot''s wash supervisors';
  END IF;
  IF twin.ottoq_sim_bay_work_minutes(v_run, '00000000-0000-0000-0000-00000000746b', 'in_wash_bay', now()) IS NOT NULL
     OR twin.ottoq_sim_time_bay_work(v_run, v_depot, now()) <> 0 THEN
    RAISE EXCEPTION '0746 V2: at the default the twin timed a seat';
  END IF;
END $v2$;

-- ── (e) the sweep: arm 84's cell, the crews timed by the work, robotic lanes ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('robowash_normal_2026_10_18',
        'Robotic wash lanes on forty robotic posts: the depot as run, its crews timed by the work, and robotic lanes',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 14, 3000, 'active',
        '0746 (G460). Cell 1 is arm 84''s cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) on value_2026_09_30''s '
        'first seed; cells 2 and 3 differ from it only by wash_lane_physics, 1 and 2.');
-- the control first: a treatment's trigger (ottoq_throughput_sweep_cells_control) reads its control's row
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40.otto_q', 1, 'otto_q', 'dcfc40', '{"deploy_peak_fraction": 0.90}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'robowash_normal_2026_10_18';
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params, control_cell_code)
SELECT s.sweep_id, x.cell_code, x.ord, 'otto_q', 'dcfc40', x.fixed_params, 'dcfc40.otto_q'
  FROM public.ottoq_throughput_sweeps s
 CROSS JOIN (VALUES ('dcfc40.otto_q.wash_timed', 2, '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 1}'::jsonb),
                    ('dcfc40.otto_q.wash_robotic', 3, '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 2}'::jsonb))
             x(cell_code, ord, fixed_params)
 WHERE s.sweep_code = 'robowash_normal_2026_10_18';

-- ── V3: the dials and the cells ──
DO $v3$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE NOT COALESCE(agent_writable, false)
         AND ((param_key, default_value, min_value, max_value) IN (('wash_lane_physics', 0, 0, 2),
                                                                   ('robotic_wash_min', 5.0, 2, 15),
                                                                   ('robotic_detail_min', 16.5, 6, 40)))) <> 3 THEN
    RAISE EXCEPTION '0746 V3: the dials are not catalogued as declared';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'robowash_normal_2026_10_18') <> 3
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
           JOIN public.ottoq_throughput_sweeps sp ON sp.sweep_code = 'dcfc40_power_normal_2026_10_17'
           JOIN public.ottoq_throughput_sweep_cells cp ON cp.sweep_id = sp.sweep_id AND cp.cell_code = 'dcfc40.otto_q'
          WHERE s.sweep_code = 'robowash_normal_2026_10_18'
            AND c.buildout_code = cp.buildout_code AND c.seat = cp.seat
            AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
              = (sp.scenario, sp.sim_start, sp.ticks, sp.sim_min_per_tick, sp.seeds[1])
            AND c.fixed_params - 'wash_lane_physics' = cp.fixed_params
            AND COALESCE(c.fixed_params ->> 'wash_lane_physics', '0') = (c.ord - 1)::text) <> 3 THEN
    RAISE EXCEPTION '0746 V3: the sweep''s cells are not arm 84''s cell plus wash_lane_physics 0, 1 and 2';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0746_robotic_wash_lanes_and_bay_work_timed_by_the_work', false, false,
        'Dials wash_lane_physics (default 0), robotic_wash_min, robotic_detail_min. New twin.ottoq_sim_bay_work_minutes, '
        'twin.ottoq_sim_time_bay_work (called before the service flow''s STEP 1; returns at once at 0) and '
        'public.ottoq_wash_lane_staff_gate (the depot''s wash supervisors below 2, none at 2), which replaces the supervisor '
        'count in the service flow''s STEP 2, decide section (4b) and ottoq_l2_propose_charge_disposition. V1: each body '
        'less its insertions is its pre-image; V2: at the default the gate is the supervisors and nothing is timed. Sweep '
        'robowash_normal_2026_10_18 (arm 84''s cell, then 1 and 2; one seed, priority 14). No certification arm, canon '
        'cell or dial experiment sets the dials.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:14:29 UTC (6:14 AM CT), ledger version 20261018111429 ══════════════════════════════════════
--
--   Through apply_migration with nothing in flight (no run live and nothing in flight, read before and after; the file's
--   own P0 at the apply). The text sent, BEGIN through COMMIT and one newline, is 21,485 characters, md5
--   b8b1df531390f13494789806031f0ed4, equal to the ledger's statements[1] read back; its executable part is 21,469
--   characters, md5 2627e8ba20b39833b5a67dbf3bc86b47, equal to this file's. The post-images are the dry run's of
--   2026-10-17 between 7:20 and 7:37 PM CT (prosrc): twin.ottoq_sim_advance_service_flow
--   d7f2ee279455242f966492869305adb1, public.ottoq_decide_tick b90378b7b46b7adcfa4ef938a791d395,
--   public.ottoq_l2_propose_charge_disposition 7b56721a38ccd720d2919cffd5fca495. Sweep robowash_normal_2026_10_18 is
--   queued (three cells here, priority 14; 0747 adds its fourth).
--
--   End to end on live, rolled back by its own raise at 11:45:17 UTC (6:45 AM CT): a probe run at the twin depot; one
--   car in_wash_bay and one in_detail_bay (NASH-WSH-01, -02) seated three minutes before the clock, each timed to its
--   booking's end with its bay need bound; twin.ottoq_sim_advance_service_flow for the run at the clock. At
--   wash_lane_physics 0 neither timer moved (9 and 25 minutes from the seat) and the staff gate read 2; at 1 each was
--   retimed from its seat, the wash to 10.000 and the detail to 22.093 minutes (9 and 25 times the deal), the bay needs
--   moved with them, bay_plan_ends_at kept the old ends and the gate read the two supervisors; at 2 the wash took 5.278
--   and the detail 15.221 minutes and the gate was NULL. The service flow sets no search_path of its own, so a direct
--   call needs the world tick's (twin, ottoq, public, extensions); the first attempt, without it, could not find
--   twin.ottoq_sim_lane_capacity.
