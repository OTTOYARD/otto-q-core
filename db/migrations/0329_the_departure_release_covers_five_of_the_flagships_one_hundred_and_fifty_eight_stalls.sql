-- migration-version: PENDING
-- migration-name:    0329_the_departure_release_covers_five_of_the_flagships_one_hundred_and_fifty_eight_stalls
-- ============================================================================
-- 0329 — A BOOKING ENDS WHEN ITS WINDOW RUNS OUT, NOT WHEN THE VEHICLE LEAVES,
--        BECAUSE THE DEPARTURE-RELEASE PATH ONLY EVER LOOKS AT BAYS.
-- ============================================================================
-- HOW THIS WAS FOUND, and it is worth recording because the finding refuted the
-- hypothesis that produced it. 0328 added `present_vehicle_state` to the
-- conflict ledger to separate two theories of the wait problem: "the blocker
-- finished and has not left" (fix the release path) from "the blocker is
-- mid-service" (fix the selection predicate). Measured on twin run c9b05a04
-- (busy_day, seed 771771, flagship, 29 ticks, 134 conflicts), the answer was
-- NEITHER, and the ledger said so on the first run it was live for:
--
--   * 100% of `assignment_refused_occupied` come from source 3 of
--     ottoq.ottoq_validate_assignment — THE CALENDAR. Zero came from
--     stalls.current_vehicle_id, zero from reserved_by. In this engine's
--     traffic, "target_occupied" has never once meant occupied.
--   * The blocker is somewhere else entirely: arrived_at_gate,
--     en_route_to_depot, staged_awaiting_service, charging_l2, charging_dcfc,
--     staged_for_departure. 47 of the first 50 were not in the stall at all.
--   * By who booked it: 53% otto_q (planner intent, avg window 163 min),
--     47% otto_q_enacted (avg window 184 min). BOTH halves refuse, so a story
--     about speculative planner bookings explains only half of it.
--
-- THE ONE CAUSE UNDERNEATH BOTH HALVES. A booking is closed when its WINDOW
-- ELAPSES, not when the vehicle leaves. Across the whole run, release_reason
-- reads: window_elapsed 24, window_elapsed_occupied 5, superseded_by_enacted_*
-- for the charge bookings — and `vehicle_moved_to_next_leg` exactly ONCE.
--
-- WHY ONCE. ottoq.ottoq_release_vacated_spaces is the departure-release path,
-- and every one of its three phases is filtered to
-- `stall_type IN ('wash_bay','service_bay')`. Phase (b) carries the comment
-- "Never dcfc/l2/staging." The flagship depot has 158 stalls — 113 staging,
-- 30 L2, 10 DCFC, 3 wash bays, 2 service bays — so the path that frees a space
-- when its occupant leaves covers FIVE STALLS, 3.2% of the depot. The other
-- 153 wait out their nominal window no matter what the vehicle does.
--
-- (Counted at the depot. An earlier draft of this header said "12 of 330",
-- which is the wash+service and total stall counts for the WHOLE DATABASE
-- applied to one depot — the same class of error this file exists to fix, so
-- it is recorded rather than quietly repaired.)
--
-- THE COST, measured two independent ways on the same run:
--   * at one instant mid-run: 94 bookings covered the sim clock, 64 of them
--     held by a vehicle that was not in that stall — 4,780 dead stall-minutes,
--     avg 70 min open, max 270. perimeter_hold was worst: 67 open, 0 of 67
--     with the vehicle present, avg 154-240 min.
--   * from the run's own KPI audit block, which was already counting this and
--     nobody had read it: `released_never_occupied` = 380. The depot issued
--     1,009 stall claims to complete 332 turns. 380 claims were held against
--     a vehicle that never came.
--
-- NOT AN INSTRUMENT ARTIFACT. "0 of 67 present" would be guaranteed if
-- vehicles.current_stall_id could never point at a staging stall. It can:
-- 65 vehicles had exactly that at the moment of measurement, and 54 of 113
-- flagship staging stalls carried an occupant. The zero is real.
--
-- ── WHAT THIS FILE DOES, AND THE THREE LINES IT WILL NOT CROSS ─────────────
-- It adds ottoq.ottoq_release_departed_spaces: a CALENDAR-ONLY sweep for
-- dcfc / l2 / staging, called from inside ottoq_release_vacated_spaces in the
-- same self-contained, exception-wrapped way that function already calls
-- ottoq_activate_due_bay_reservations.
--
--   1. IT NEVER WRITES `stalls` OR `vehicles`. The bay path's phases (a) and
--      (b) hard-free the physical rows; that is why they are restricted to
--      bays, and the restriction is right. Hard-freeing a DCFC row out from
--      under a live charge session would be a far worse defect than the one
--      being fixed. This sweep touches ottoq_stall_bookings and nothing else,
--      so the worst it can do is retire a calendar claim.
--   2. IT REQUIRES TWO INDEPENDENT WITNESSES that the vehicle is not there,
--      never one: the VEHICLE must say it is positively in a different stall,
--      AND the STALL must disown it. Plus a third guard on charge places —
--      no open ocpp_sessions row — because a live charging session is the
--      authority on whether a charge place is in use, and the calendar is not.
--      That is the standing "assignment plus verification" rule applied to a
--      release rather than to an assignment.
--   3. IT SHIPS INERT. Gated on a new dial `space_departure_release_enabled`,
--      registered in ottoq_policy_param_catalog with default 0. Nothing
--      changes until the dial is set, which makes the before/after a paired
--      run on one seed rather than an argument.
--
-- Control baseline already captured, seed 771771 / busy_day / flagship /
-- 29 ticks, config_hash b69927c08b83cfa3eda1285556b701bf:
--   p95_time_to_service 243 min · p50 60 · max 840 · returns_unserved 0
--   conflicts 134 · turns/point/day 2.13 · released_never_occupied 380
--
-- ── WHY ottoq_booking_interrupted IS REFACTORED HERE, AND HOW IT IS PROVED ──
-- The sweep must classify a departure as `interrupted` (cut short) or `done`
-- (finished). The existing test, ottoq.ottoq_booking_interrupted, opens with
-- ottoq.ottoq_is_bay_purpose(p_purpose) and so returns FALSE for every charge
-- and staging purpose — reusing it would stamp `done` on every cut-short
-- charge, which is precisely the defect BUILD 2 fixed for bays when it made
-- `done` MEAN FINISHED. Copying the 80%/120s constants into a second function
-- would let the two drift apart. So the rule moves into ONE function,
-- ottoq.ottoq_occupancy_cut_short(planned_s, actual_s), and
-- ottoq_booking_interrupted becomes the bay gate over it. The calibration is
-- not retuned and the bay behaviour is not changed: E1 proves the new
-- composition returns the identical answer to the old body across a 200-row
-- grid of purposes x planned x actual, INCLUDING the NULL and zero edges.
-- ============================================================================

DO $pre$
DECLARE v_src text; v_n int;
BEGIN
  -- P1. The release path exists and is still bay-scoped in all three phases —
  --     i.e. the defect this file is written against is still the live one.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_release_vacated_spaces';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0329 P1: ottoq.ottoq_release_vacated_spaces not found';
  END IF;
  IF position('Never dcfc/l2/staging' in v_src) = 0 THEN
    RAISE EXCEPTION '0329 P1: the bay-only restriction is not where this file expects it';
  END IF;
  IF position('ottoq_release_departed_spaces' in v_src) > 0 THEN
    RAISE EXCEPTION '0329 P1: the departed sweep is already wired; nothing to do';
  END IF;
  RAISE NOTICE '0329 P1: release path found, still bay-only, sweep not yet wired';

  -- P2. `released` must be outside EVERY overlap constraint, or sweep 2 would
  --     retire a claim without freeing the range and achieve nothing.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid='public.ottoq_stall_bookings'::regclass AND contype='x'
     AND pg_get_constraintdef(oid) LIKE '%''released''%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0329 P2: an EXCLUDE constraint counts released bookings; sweep 2 would not free the range';
  END IF;

  -- P3. ...and `done`/`interrupted` must be INSIDE v3, or sweep 1's clip is
  --     pointless. The two preconditions are opposite halves of one fact.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conrelid='public.ottoq_stall_bookings'::regclass AND contype='x'
     AND conname='ottoq_stall_bookings_no_overlap_v3'
     AND pg_get_constraintdef(oid) LIKE '%''interrupted''%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0329 P3: v3 does not cover interrupted; sweep 1 clip assumption is wrong';
  END IF;
  RAISE NOTICE '0329 P2-P3: released frees the range, done/interrupted still hold it';

  -- P4. The dial catalogue is the gate (0302/0305), so the dial must be
  --     registerable before any scope row can reference it.
  SELECT count(*) INTO v_n FROM information_schema.tables
   WHERE table_schema='public' AND table_name='ottoq_policy_param_catalog';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0329 P4: ottoq_policy_param_catalog missing';
  END IF;

  -- P5. The gap, measured rather than asserted.
  SELECT count(*) INTO v_n FROM public.stalls s
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
     AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type,'staging'::stall_type);
  RAISE NOTICE '0329 P5: % flagship stalls are dcfc/l2/staging and have no departure release today', v_n;
END $pre$;

-- PRE-SNAPSHOTS: two live bodies are rewritten below, so both are captured
-- first. Columns read from information_schema, not remembered (0328's lesson).
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0329 pre: '||p.proname||' before the departure-release sweep',
       'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ottoq'
   AND p.proname IN ('ottoq_release_vacated_spaces','ottoq_booking_interrupted');

-- ── THE DIAL, registered before it can be set ──────────────────────────────
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES ('space_departure_release_enabled',
        '0329. When 1, ottoq_release_departed_spaces retires a dcfc/l2/staging '
        'calendar claim once the vehicle has demonstrably left (two independent '
        'witnesses plus no live OCPP session), and retires a held claim the '
        'vehicle never took after booking_no_show_grace_min. Calendar only: it '
        'never writes stalls or vehicles. Default 0 so the change ships inert '
        'and its effect is a paired run on one seed, not an argument.',
        0, 0, 1, 'ottoq.ottoq_release_departed_spaces')
ON CONFLICT (param_key) DO NOTHING;

-- ── ONE RULE, ONE PLACE: the cut-short test without the bay gate ───────────
CREATE OR REPLACE FUNCTION ottoq.ottoq_occupancy_cut_short(
  p_planned_s numeric, p_actual_s numeric)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
  -- The rule, verbatim from ottoq_booking_interrupted's BUILD 2 calibration on
  -- run 6b22906b (busy_day/424242): actual < 80% of planned AND shortfall >=
  -- 120 s. The 80% sits inside the widest gap in that run's bimodal completion
  -- distribution (17 rows <= 0.630, 7 rows >= 0.828), so the split is a
  -- structural break and not a tuned knob; the 120 s floor is a guard rail for
  -- short bays and was inert on the calibration run. NOT retuned here — this
  -- function exists so the constants live in exactly one place now that a
  -- non-bay caller needs them too.
  SELECT p_planned_s IS NOT NULL AND p_planned_s > 0
     AND p_actual_s  IS NOT NULL
     AND p_actual_s < 0.80 * p_planned_s
     AND (p_planned_s - p_actual_s) >= 120;
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_occupancy_cut_short(numeric, numeric) IS
  '0329. Was this occupancy materially shorter than planned? The 80%/120s rule '
  'calibrated in ottoq_booking_interrupted BUILD 2, lifted out so the bay test '
  'and the departure sweep share one definition instead of two that can drift.';

CREATE OR REPLACE FUNCTION ottoq.ottoq_booking_interrupted(
  p_purpose text, p_planned_s numeric, p_actual_s numeric)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
  -- 0329: unchanged in behaviour — the bay gate over the shared rule. E1 in
  -- the migration proves this composition equals the previous inline body on a
  -- 200-row grid including the NULL and zero edges.
  SELECT ottoq.ottoq_is_bay_purpose(p_purpose)
     AND ottoq.ottoq_occupancy_cut_short(p_planned_s, p_actual_s);
$fn$;

-- E1. EQUIVALENCE, over a grid rather than over one example.
DO $e1$
DECLARE v_diff int;
BEGIN
  WITH purposes AS (
    SELECT unnest(ARRAY['wash','service','detail','charge_l2','charge_dcfc',
                        'staging','perimeter_hold','temp_hold']) AS purpose
  ), planned AS (SELECT unnest(ARRAY[NULL,0,100,600,3600]::numeric[]) AS planned_s),
    actual  AS (SELECT unnest(ARRAY[NULL,0,79,500,3600]::numeric[]) AS actual_s),
  grid AS (SELECT * FROM purposes, planned, actual)
  SELECT count(*) INTO v_diff FROM grid g
   WHERE ottoq.ottoq_booking_interrupted(g.purpose, g.planned_s, g.actual_s)
         IS DISTINCT FROM
         -- the previous body, written out literally
         (ottoq.ottoq_is_bay_purpose(g.purpose)
          AND g.planned_s IS NOT NULL AND g.planned_s > 0
          AND g.actual_s  IS NOT NULL
          AND g.actual_s < 0.80 * g.planned_s
          AND (g.planned_s - g.actual_s) >= 120);
  IF v_diff <> 0 THEN
    RAISE EXCEPTION '0329 E1: the refactored bay test differs from the original on % of 200 grid rows', v_diff;
  END IF;
  RAISE NOTICE '0329 E1: bay test identical to its previous body across the whole grid';
END $e1$;

-- ── THE SWEEP ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_departed_spaces(
  p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE v_enabled int; v_grace int; v_dep int := 0; v_nos int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  -- INERT BY DEFAULT. The dial is read per run, so one arm of a pair can carry
  -- it and the other not, which is how its effect gets measured.
  v_enabled := COALESCE(public.ottoq_policy_get(p_sim_run_id,'space_departure_release_enabled',0),0)::int;
  IF v_enabled <> 1 THEN RETURN 0; END IF;

  v_grace := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'booking_no_show_grace_min',15),15)::int, 0);

  -- ── SWEEP 1: DEPARTURE. An `active` claim whose vehicle has left.
  -- Two independent witnesses, never one:
  --   W1 the VEHICLE says it is positively in a DIFFERENT stall. Not merely
  --      "not here" -- current_stall_id IS NULL is in transit or lost
  --      bookkeeping, and absence of evidence must not free a space.
  --   W2 the STALL disowns it.
  -- W3 on top, for charge places: no open OCPP session. A live session is the
  --    authority on whether a charge place is in use; the calendar is not.
  WITH cand AS (
    SELECT b.booking_id,
           lower(b.during) AS lo,
           upper(b.during) AS hi,
           GREATEST(lower(b.during) + interval '1 second',
                    LEAST(upper(b.during), p_clock)) AS clip_hi
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND s.depot_id   = p_depot_id
       AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type,'staging'::stall_type)
       AND b.state      = 'active'
       AND b.during @> p_clock
       AND v.current_stall_id IS NOT NULL                    -- W1
       AND v.current_stall_id <> b.stall_id                  -- W1
       AND s.current_vehicle_id IS DISTINCT FROM b.vehicle_id -- W2
       AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os  -- W3
                        WHERE os.sim_run_id = b.sim_run_id
                          AND os.stall_id   = b.stall_id
                          AND os.vehicle_id = b.vehicle_id
                          AND os.ended_at IS NULL)
  ), upd AS (
    UPDATE public.ottoq_stall_bookings b
       SET state = CASE WHEN ottoq.ottoq_occupancy_cut_short(
                               EXTRACT(epoch FROM (c.hi - c.lo))::numeric,
                               EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric)
                        THEN 'interrupted' ELSE 'done' END,
           released_at    = p_clock,
           release_reason = CASE WHEN ottoq.ottoq_occupancy_cut_short(
                                       EXTRACT(epoch FROM (c.hi - c.lo))::numeric,
                                       EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric)
                                 THEN 'departed_before_planned_end'
                                 ELSE 'departed_stall' END,
           -- done/interrupted REMAIN inside no_overlap_v3, so the window must be
           -- clipped to now or the claim keeps the rest of its range.
           during = tstzrange(c.lo, c.clip_hi, '[)')
      FROM cand c WHERE b.booking_id = c.booking_id
    RETURNING 1 AS one
  ) SELECT count(*) INTO v_dep FROM upd;

  -- ── SWEEP 2: NO-SHOW. A `held` claim whose window has opened, whose grace
  -- has elapsed, and which nobody took. Mirrors the bay path's own no-show
  -- semantics and reuses its dial rather than inventing a second one.
  -- W1 is relaxed to "not in THIS stall" here, deliberately: a held booking
  -- has by definition not been activated, so there is no occupancy to protect
  -- -- but W2 still stands, because a held booking CAN have its vehicle
  -- present (measured: charge_l2/held, 4 of 6 present), and W2 is what sees
  -- that. `released` sits outside every overlap constraint, so no clip.
  WITH cand AS (
    SELECT b.booking_id
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND s.depot_id   = p_depot_id
       AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type,'staging'::stall_type)
       AND b.state      = 'held'
       AND b.during @> p_clock
       AND lower(b.during) + make_interval(mins => v_grace) <= p_clock
       AND v.current_stall_id IS DISTINCT FROM b.stall_id
       AND s.current_vehicle_id IS DISTINCT FROM b.vehicle_id
       AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os
                        WHERE os.sim_run_id = b.sim_run_id
                          AND os.stall_id   = b.stall_id
                          AND os.vehicle_id = b.vehicle_id
                          AND os.ended_at IS NULL)
  ), upd AS (
    UPDATE public.ottoq_stall_bookings b
       SET state='released', released_at=p_clock, release_reason='no_show_grace_elapsed'
      FROM cand c WHERE b.booking_id = c.booking_id
    RETURNING 1 AS one
  ) SELECT count(*) INTO v_nos FROM upd;

  RETURN v_dep + v_nos;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_release_departed_spaces: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END $fn$;

COMMENT ON FUNCTION ottoq.ottoq_release_departed_spaces(uuid, uuid, timestamptz) IS
  '0329. Calendar-only departure release for dcfc/l2/staging, the 153 of 158 '
  'flagship stalls ottoq_release_vacated_spaces deliberately does not cover. '
  'Never writes stalls or vehicles: the worst it can do is retire a calendar '
  'claim. Requires two independent witnesses that the vehicle has left, plus '
  'no open OCPP session on charge places. Gated on '
  'space_departure_release_enabled, default 0.';

-- ── WIRING: one more self-contained block inside the existing release path,
-- exactly as that function already calls ottoq_activate_due_bay_reservations.
DO $sub$
DECLARE v_def text; v_new text;
  a_old text := E'\nDECLARE v_n int := 0; v_m int := 0; v_grace int; v_rec record; v_reopened int;\n';
  a_new text := E'\nDECLARE v_n int := 0; v_m int := 0; v_grace int; v_rec record; v_reopened int;\n'
             || E'        v_departed int := 0;   -- 0329\n';
  b_old text := E'  RETURN v_n + v_m + v_activated;\n';
  b_new text := E'  -- ══════════ 0329: THE OTHER 153 STALLS ══════════\n'
             || E'  -- Everything above this line is bay-only by design and that design is\n'
             || E'  -- right: phases (a) and (b) hard-free physical rows. This call is\n'
             || E'  -- calendar-only and self-contained, so a failure in it can never cost\n'
             || E'  -- the bay logic above. Inert unless space_departure_release_enabled=1.\n'
             || E'  BEGIN\n'
             || E'    v_departed := ottoq.ottoq_release_departed_spaces(p_sim_run_id, p_depot_id, p_clock);\n'
             || E'  EXCEPTION WHEN OTHERS THEN\n'
             || E'    v_departed := 0;\n'
             || E'    RAISE WARNING ''release_departed_spaces FAILED sqlstate=% msg=% run=%'',\n'
             || E'      SQLSTATE, SQLERRM, p_sim_run_id;\n'
             || E'  END;\n\n'
             || E'  RETURN v_n + v_m + v_activated + v_departed;\n';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_release_vacated_spaces';

  v_new := replace(v_def, a_old, a_new);
  IF v_new = v_def THEN RAISE EXCEPTION '0329 S1: DECLARE substitution changed nothing'; END IF;
  v_def := v_new;

  v_new := replace(v_def, b_old, b_new);
  IF v_new = v_def THEN RAISE EXCEPTION '0329 S2: RETURN substitution changed nothing'; END IF;

  EXECUTE v_new;
  RAISE NOTICE '0329: departure sweep wired into ottoq_release_vacated_spaces';
END $sub$;

DO $post$
DECLARE v_src text; v_n int; v_b boolean;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_release_vacated_spaces';

  -- A1. The sweep is called, and its result reaches the return value. A call
  --     whose count is dropped on the floor is a call nobody can audit.
  IF position('ottoq_release_departed_spaces' in v_src) = 0 THEN
    RAISE EXCEPTION '0329 A1: the sweep is not called';
  END IF;
  IF position('RETURN v_n + v_m + v_activated + v_departed;' in v_src) = 0 THEN
    RAISE EXCEPTION '0329 A1: the sweep result is discarded rather than returned';
  END IF;

  -- A2. THE BAY PATH IS UNTOUCHED. This file adds a sweep; it must not have
  --     quietly widened, narrowed or reordered the three phases that existed.
  IF position('Never dcfc/l2/staging' in v_src) = 0
     OR position('ottoq_activate_due_bay_reservations' in v_src) = 0
     OR position('bay_exit_before_planned_end' in v_src) = 0
     OR position('no_show_grace_elapsed' in v_src) = 0 THEN
    RAISE EXCEPTION '0329 A2: the bay release path changed; this file must only add to it';
  END IF;

  -- A3. THE SWEEP CANNOT TOUCH PHYSICAL STATE. This is the assertion that
  --     matters most: it is what makes the change safe to ship at all. A
  --     calendar sweep that learns to write `stalls` becomes the thing phases
  --     (a) and (b) are restricted for.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_release_departed_spaces';
  IF v_src ~* 'UPDATE\s+public\.stalls' OR v_src ~* 'UPDATE\s+public\.vehicles' THEN
    RAISE EXCEPTION '0329 A3: the departure sweep writes physical state; it must write the calendar only';
  END IF;
  IF position('ottoq_stall_bookings' in v_src) = 0 THEN
    RAISE EXCEPTION '0329 A3: the departure sweep does not write the calendar either';
  END IF;

  -- A4. BOTH WITNESSES PRESENT. One witness is how a space gets freed out from
  --     under a vehicle that is still in it.
  IF position('v.current_stall_id IS NOT NULL' in v_src) = 0
     OR position('s.current_vehicle_id IS DISTINCT FROM b.vehicle_id' in v_src) = 0
     OR position('os.ended_at IS NULL' in v_src) = 0 THEN
    RAISE EXCEPTION '0329 A4: a witness is missing from the departure sweep';
  END IF;

  -- A5. INERT: the dial is registered, defaults to 0, and no scope row sets it.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key='space_departure_release_enabled' AND default_value=0
     AND min_value=0 AND max_value=1;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0329 A5: the dial is not registered with default 0 / range 0..1';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key='space_departure_release_enabled';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0329 A5: something already sets the dial; this file must ship inert';
  END IF;

  -- A6. And prove inertness by CALLING it, rather than by reading the code:
  --     against the completed control run, with the dial unset, it must
  --     return 0 and change nothing.
  SELECT ottoq.ottoq_release_departed_spaces(
           'c9b05a04-678f-4d27-9bb6-f93d2e501d64'::uuid,
           '11111111-1111-1111-1111-111111111111'::uuid,
           now()) = 0 INTO v_b;
  IF NOT v_b THEN
    RAISE EXCEPTION '0329 A6: the sweep did something with its dial unset';
  END IF;

  RAISE NOTICE '0329 A1-A6: wired, bay path intact, calendar-only, both witnesses, inert and proven inert by call';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0329_the_departure_release_covers_five_of_the_flagships_one_hundred_and_fifty_eight_stalls', true,
   'Adds ottoq.ottoq_release_departed_spaces, a calendar-only departure release for '
   'dcfc/l2/staging, wired into ottoq_release_vacated_spaces whose three phases are all '
   'restricted to wash_bay/service_bay -- 5 of the flagship''s 158 stalls. Measured on run '
   'c9b05a04: 100% of assignment_refused_occupied come from the calendar (0 from physical '
   'occupancy, 0 from reservations), release_reason vehicle_moved_to_next_leg fired ONCE in '
   'the run against window_elapsed 24, and the run''s own KPI audit reports '
   'released_never_occupied=380 out of 1,009 claims for 332 turns. Ships INERT behind '
   'space_departure_release_enabled default 0; A6 proves inertness by calling the function '
   'rather than by reading it. Also lifts the 80%/120s cut-short rule out of '
   'ottoq_booking_interrupted into ottoq_occupancy_cut_short so a non-bay caller cannot fork '
   'the constants; E1 proves the refactored bay test identical across a 200-row grid '
   'including NULL and zero edges. With the dial at 0 this SHOULD move no canon. Classified '
   'TRUE anyway on 0320''s rule: "should change nothing" is a prediction for a round to '
   'judge, not a classification.',
   now())
ON CONFLICT (name) DO NOTHING;
