-- migration-version: PENDING
-- migration-name:    rider_flag_holds_the_vehicle
--
-- 0019_rider_flag_holds_the_vehicle.sql
-- ============================================================================
-- A RIDER-FLAGGED CAR IS TAKEN OFF THE ROAD, WHICH IS THE CLAIM THE DEMO MAKES
-- ============================================================================
--
-- WHAT 0018 ACTUALLY ACHIEVED, MEASURED.  0018 made a rider-flagged cleaning
-- recall reach a wash bay reliably: 18 flags drawn, 16 actioned, 7 of 7 got a
-- bay in the contended run, 0 ever deferred.  That part stands and this file
-- does not touch it.
--
-- WHAT IT DID NOT ACHIEVE.  It did not take the car off the road.
--   * 9 of 10 flag-linked dispatches were SENT OUT with the flag ALREADY due
--     (flag age at dispatch 43 -> 1,349 min) and recalled one tick later.
--     Only 1 was a genuine mid-deployment recall.
--   * 2 of 18 flags never fired at all.  They matured while the vehicle was
--     parked; one car arrived 02:04, its flag matured 02:24, and it then sat
--     in `staged_for_departure` for 15 more sim-hours.
--   * 1 flag recalled the same car TWICE over 16 sim-hours before it was served.
--
-- THE MECHANISM, READ FROM THE SOURCE RATHER THAN ASSUMED.
--   public.ottoq_evaluate_return_need opens with a SELECT for a dispatch with
--   status='active' and returns should_return=false ("no active dispatch in
--   run") when there is none.  So the rider-flag rung is structurally
--   unreachable for a vehicle sitting in the depot -- and nothing anywhere
--   stopped that same vehicle being dispatched a moment later.  That is the
--   whole of the defect: the flag could only be honoured by first sending the
--   car away.
--
-- ══ WHICH OF THE BRIEFING'S PREMISES SURVIVED CONTACT WITH THE CODE ══
--
--  CONFIRMED.  ottoq_evaluate_return_need really does require an ACTIVE
--  dispatch, and really does return should_return=false without one.
--
--  CONFIRMED, with a correction to the route.  The dispatch path is
--  twin.ottoq_sim_auto_dispatch_tick -> ottoq.ottoq_plan_dispatch_tick
--  ('deploy_plan' phase, which is where the candidate cursor and every
--  eligibility clause live) -> twin.ottoq_sim_dispatch_vehicle (which writes
--  the ottoq_vehicle_dispatches row).  ottoq_plan_dispatch_tick is not a
--  separate third path as the briefing's ordering suggested; it is the
--  planner the first calls and the only place a candidate can be excluded.
--
--  FALSIFIED.  "ALWAYS HOLD already says this" -- meaning
--  SLA.004.required_services_complete would already cover a due rider flag.
--  It does not, and this was checked rather than assumed.  Every ALWAYS HOLD
--  clause in this codebase is written against ottoq_visit_needs.atoms:
--    * ottoq.ottoq_plan_dispatch_tick deploy_plan requires no open/in_progress
--      visit carrying a must_do atom outside ('done','cancelled');
--    * public.ottoq_decide_tick section (2) requires the same for
--      status IN ('pending','in_progress').
--  A rider flag is NOT an atom until a visit is generated for the vehicle, and
--  0018 generates that visit only on ARRIVAL.  A flag maturing on a parked car
--  therefore has no atom, no visit, and nothing for either clause to hold on.
--  The hold mechanism is extended here rather than duplicated -- the new clause
--  sits inside the same cursor, immediately after the atom clause -- but the
--  claim that it was already covered is false.
--
--  FALSIFIED.  "Add md5 guards on any function you replace -- 0018 did not."
--  The gap is real and is closed here (section 1), but note what a guard can
--  and cannot do: it proves the pre-image this file was written against is the
--  pre-image that is live.  It does not prove the post-image, which is what the
--  drift manifest and the ledger md5 are for.
--
-- ══ WHAT THIS FILE CHANGES ══
--
--  (i)  A vehicle carrying a DUE rider flag is not dispatched.  One predicate,
--       public.ottoq_rider_flag_due, used in both the planner's candidate
--       cursor and at the door in twin.ottoq_sim_dispatch_vehicle.  A flag that
--       is drawn but NOT YET DUE does not gate anything -- that car deploys
--       normally and is recalled mid-deployment when its moment arrives, which
--       is the genuine scene the demo is about.
--
--  (ii) A flag that comes due on a PARKED car gets a path.  A new stage,
--       ottoq.ottoq_rider_flag_indepot_sweep, runs once per dispatch tick
--       BEFORE the deploy cursor.  A parked car needs no recall; it needs the
--       cleaning atom added to the visit it is already having (or a visit
--       opened for it), and to be put back into the state the bay-routing
--       cursor reads.  Nothing is "re-routed": a car in a bay, on a charger or
--       under a tech hold is never touched.
--
-- (iii) JUDGEMENT CALL -- the flag clears ON CONSUMPTION, not on service.
--       THE CHOICE.  public.ottoq_evaluate_return_need now reads
--       public.ottoq_rider_cleaning_flags.status = 'pending' instead of
--       public.vehicle_need_profile.rider_flag_pending.  0018 already advances
--       that status to 'recalled' the moment a visit takes the atom, so the
--       recall rung now fires exactly once per raise.
--       WHY, AND WHY NOT THE ALTERNATIVE.  Clearing on SERVICE would keep the
--       trigger armed while the work sits on the visit, and the car would be
--       recalled again every time it went out -- which is precisely the
--       observed double-recall, dressed up as a policy.  Clearing on
--       CONSUMPTION is safe only because ownership of the work does not lapse:
--       at that instant the flag has become a must_do atom on an open visit,
--       and both ALWAYS HOLD clauses hold the car until that atom is done or
--       cancelled.  The handoff is total -- there is no window in which nobody
--       owns the cleaning.  public.vehicle_need_profile.rider_flag_pending is
--       demoted to what it truthfully is, a record of the run-start DRAW, and
--       its COMMENT is rewritten to say so rather than left to mislead.
--
-- ══ WHAT THIS FILE DOES NOT DO ══
--   Nothing is dropped.  No VACUUM FULL.  No cron job is created, altered or
--   disabled -- cron 12 is the START engine and is not touched.  No run is
--   started by this file.  The wash rotation (0018 PATH 1), the interior /
--   exterior mapping, and twin.ottoq_sim_generate_service_manifest are all left
--   exactly as 0018 left them.
--
-- ══ SINGLE TRANSACTION ══
--   BEGIN is on the next line and the only COMMIT is the last line of the file,
--   so a failing guard or assertion rolls back every function replacement here.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. PRE-IMAGE GUARDS.  0018 replaced three functions with no guard at all,
--    which was flagged as a gap for this migration.  Each md5 below is
--    pg_get_functiondef() of the LIVE object as read on 2026-08-08, before a
--    byte of this file ran.  If any of them has moved, someone has changed the
--    object underneath this file and the edits it makes are no longer
--    guaranteed to be edits to the thing that was reviewed.  Abort, do not
--    "adapt".
-- ============================================================================
DO $guard$
DECLARE
  v_want text; v_got text; v_fn text; v_bad int := 0; v_msg text := '';
BEGIN
  FOR v_fn, v_want IN
    SELECT * FROM (VALUES
      ('ottoq.ottoq_plan_dispatch_tick(text,uuid,uuid,timestamptz,integer,bigint,integer,integer,integer,integer,integer,numeric,jsonb,boolean)',
       '4ac5af7de0e8f4cc12c56b1385280424'),
      ('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)',
       '0cbd66cb8b492ab4ad39cb781e7a6dcc'),
      ('twin.ottoq_sim_auto_dispatch_tick(uuid,timestamptz,numeric)',
       '1681f0111746db331f47369e85319f70'),
      ('public.ottoq_evaluate_return_need(uuid,uuid,timestamptz,numeric,numeric)',
       '9d9f0f92e105a889d2d7965cf479f72b')
    ) AS t(fn, want)
  LOOP
    BEGIN
      v_got := md5(pg_get_functiondef(v_fn::regprocedure));
    EXCEPTION WHEN OTHERS THEN
      v_got := '(not found: ' || SQLERRM || ')';
    END;
    IF v_got IS DISTINCT FROM v_want THEN
      v_bad := v_bad + 1;
      v_msg := v_msg || E'\n  ' || v_fn || E'\n    expected ' || v_want || E'\n    found    ' || COALESCE(v_got,'(null)');
    END IF;
  END LOOP;

  IF v_bad > 0 THEN
    RAISE EXCEPTION
      'GUARD FAILED: % of 4 pre-images do not match what 0019 was written against.%',
      v_bad, v_msg;
  END IF;
  RAISE NOTICE '0019 guard: all 4 pre-images match.';
END
$guard$;

-- ============================================================================
-- 2. THE PREDICATE.  One definition of "this vehicle owes a rider-flagged
--    cleaning right now", used by the planner, by the dispatch door, and by the
--    in-depot sweep, so the three can never disagree.
--
--    AUTHORITY.  public.ottoq_rider_cleaning_flags is the lifecycle table 0018
--    created: one row per raise, per run, unique on (sim_run_id, vehicle_id),
--    status pending -> recalled -> served.  'pending' means "raised and not yet
--    taken onto a visit".  public.vehicle_need_profile.rider_flag_pending is
--    NOT consulted: it is the run-start draw and is never cleared, which is
--    exactly what made the 0018 rung re-triggerable.
--
--    TOTAL.  STABLE, no writes, no exceptions, and false for every argument it
--    cannot resolve -- a NULL run, a NULL vehicle, a vehicle with no flag row.
--    A predicate that can raise inside a candidate cursor would abort a
--    dispatch tick, which is the 2026-08-01 leg_type lesson restated.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_rider_flag_due(
  p_vehicle_id  uuid,
  p_sim_run_id  uuid,
  p_clock       timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  SELECT COALESCE((
    SELECT true
      FROM public.ottoq_rider_cleaning_flags f
     WHERE f.vehicle_id = p_vehicle_id
       AND f.sim_run_id = p_sim_run_id
       AND f.status     = 'pending'
       AND f.raised_at_sim_clock <= p_clock
     LIMIT 1), false)
  AND p_vehicle_id IS NOT NULL
  AND p_sim_run_id IS NOT NULL
  AND p_clock      IS NOT NULL;
$fn$;

COMMENT ON FUNCTION public.ottoq_rider_flag_due(uuid, uuid, timestamptz) IS
  '0019: true when this vehicle owes a rider-flagged cleaning that has come due and '
  'has not yet been taken onto a visit. Reads ottoq_rider_cleaning_flags.status, which '
  'is the lifecycle, NOT vehicle_need_profile.rider_flag_pending, which is the run-start '
  'draw and is never cleared. Total: false rather than an error for any argument it '
  'cannot resolve, because it is evaluated inside dispatch candidate cursors.';

-- The draw column, told the truth about. It was never wrong; it was being read
-- as though it were a lifecycle, and a stale COMMENT would let that happen again.
COMMENT ON COLUMN public.vehicle_need_profile.rider_flag_pending IS
  '0018 draw, 0019 clarification: TRUE if the run-start draw raised a rider cleaning '
  'flag for this vehicle in the run named by drawn_for_run. This is a record of the '
  'DRAW and is deliberately never cleared. It is NOT the lifecycle and must not be '
  'used to decide whether work is still owed -- ottoq_rider_cleaning_flags.status is '
  'the lifecycle (pending -> recalled -> served), and public.ottoq_rider_flag_due is '
  'the one predicate that reads it.';

-- ============================================================================
-- 3. (ii) THE IN-DEPOT PATH.  What a parked, flagged vehicle actually needs.
--
--    A recall is a thing you do to a car that is out.  A car that is already
--    here needs the cleaning put on its visit and needs to be standing in the
--    state the bay router reads.  This stage does exactly those two things and
--    nothing else.
--
--    WHERE THE ATOM GOES.  public.ottoq_visit_needs is the authority -- it is
--    what public.ottoq_plan_visit_itinerary reads, and what
--    public.ottoq_vehicle_needs_card (the view behind ottoq_decide_tick section
--    4b, the only door into a wash bay for a holding vehicle) reads.  The atom
--    is written in the SAME SHAPE 0018 writes it in the arrival manifest, so
--    every downstream reader sees one kind of row, not two.
--
--    THE MAPPING IS TOTAL, AND UNCHANGED.  'exterior' takes exterior_wash;
--    interior AND anything unrecognised (including NULL) takes
--    interior_deep_clean.  Both resolve through ottoq.ottoq_svc_to_stall_type,
--    which folds the 'detail' lane onto 'wash_bay' because there are ZERO
--    detail_bay stalls in either depot.  An unknown word can never drop the
--    work on the floor -- the 2026-08-01 leg_type lesson.
--
--    WHO IS NEVER TOUCHED.  Only HOLDING states are moved:
--    staged_for_departure, charge_complete_holding, service_complete_holding,
--    staged_awaiting_service and offline.  A vehicle that is charging, in a
--    bay, at the gate, deployed, en route, towed, in an emergency stage or out
--    of service keeps its state and its work: it still GETS the atom (the work
--    is owed either way) but this stage does not move it, so it can never
--    interrupt work in progress and never needs the in-depot reassignment gate.
--    A vehicle with an ACTIVE or RETURNING dispatch is excluded outright -- it
--    is not in the depot, and the recall rung owns it.
--
--    SELF-SILENCING.  It returns a count and swallows its own errors. It runs
--    inside the twin's dispatch tick and must never be able to abort one.
-- ============================================================================
CREATE OR REPLACE FUNCTION ottoq.ottoq_rider_flag_indepot_sweep(
  p_sim_run_id uuid,
  p_depot_id   uuid,
  p_clock      timestamptz)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_rec RECORD;
  v_n int := 0; v_opened int := 0; v_appended int := 0;
  v_svc text; v_min int; v_bay text; v_stall_type text;
  v_visit_id uuid; v_visit_key text; v_atoms jsonb; v_has boolean;
  v_atom jsonb; v_holding boolean;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  FOR v_rec IN
    SELECT f.flag_id, f.vehicle_id, f.flag_kind, f.raised_at_sim_clock,
           v.current_state::text AS vstate
      FROM public.ottoq_rider_cleaning_flags f
      JOIN public.vehicles v ON v.id = f.vehicle_id
     WHERE f.sim_run_id = p_sim_run_id
       AND f.status     = 'pending'
       AND f.raised_at_sim_clock <= p_clock
       AND v.home_depot_id = p_depot_id
       -- NOT ON THE ROAD. This is the exact complement of the condition
       -- public.ottoq_evaluate_return_need requires, so between the two of them
       -- every flagged vehicle is owned by exactly one path and never by both.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                        WHERE d.vehicle_id = f.vehicle_id
                          AND d.sim_run_id = p_sim_run_id
                          AND d.status IN ('active','returning'))
       AND v.current_state NOT IN ('deployed','en_route_to_deployment','en_route_to_depot')
     ORDER BY f.raised_at_sim_clock, f.vehicle_id
     LIMIT 40
  LOOP
    -- TOTAL MAPPING. Identical to the one 0018 uses in the arrival manifest.
    IF v_rec.flag_kind = 'exterior' THEN
      v_svc := 'exterior_wash';        v_min := 25; v_bay := 'wash_bay';
    ELSE
      v_svc := 'interior_deep_clean';  v_min := 35; v_bay := 'detail';
    END IF;

    -- Resolve through the same total resolver the booker uses, so an atom that
    -- names a stall type this depot does not have is impossible rather than
    -- discovered at booking time. NULL here would mean "no bay", which for a
    -- cleaning atom is wrong, so fall back to the wash lane explicitly.
    v_stall_type := COALESCE(ottoq.ottoq_svc_to_stall_type(v_svc, p_depot_id), 'wash_bay');

    v_atom := jsonb_build_object(
      'svc', v_svc, 'must_do', true, 'deferrable', false,
      'est_min', v_min, 'concurrency', 'bay',
      'requires_bay', v_bay,
      'stall_type_required', v_stall_type,
      'carryover_eligible', false,
      'rider_flagged', true,
      'rider_flag_kind', COALESCE(v_rec.flag_kind, 'interior'),
      'return_trigger', 'rider_flag_cleaning',
      'raised_in_depot', true,
      'why', 'Rider-reported ' || COALESCE(v_rec.flag_kind,'interior')
             || ' cleanliness issue. The vehicle was already in the depot when the '
             || 'report matured, so the cleaning was added to this visit rather than '
             || 'triggering a recall.');

    -- The newest OPEN / IN_PROGRESS visit for this vehicle in this run.
    SELECT n.visit_id, n.visit_key, n.atoms
      INTO v_visit_id, v_visit_key, v_atoms
      FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = v_rec.vehicle_id
       AND n.status IN ('open','in_progress')
       AND (n.sim_run_id = p_sim_run_id OR n.sim_run_id IS NULL)
     ORDER BY n.created_at DESC
     LIMIT 1;

    IF v_visit_id IS NOT NULL THEN
      -- PROMOTE-OR-APPEND, exactly as 0018 does on arrival: if the routine draw
      -- already put this atom on the visit, make it must_do rather than adding a
      -- duplicate the sequencer would try to work twice.
      SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_atoms,'[]'::jsonb)) e
                      WHERE e->>'svc' = v_svc) INTO v_has;
      IF v_has THEN
        UPDATE public.ottoq_visit_needs n
           SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = v_svc
                                 THEN a || jsonb_build_object(
                                        'must_do', true, 'deferrable', false,
                                        'carryover_eligible', false,
                                        'rider_flagged', true,
                                        'rider_flag_kind', COALESCE(v_rec.flag_kind,'interior'),
                                        'return_trigger', 'rider_flag_cleaning',
                                        'raised_in_depot', true)
                                 ELSE a END)
                          FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a),
               meta  = COALESCE(n.meta,'{}'::jsonb)
                       || jsonb_build_object('rider_flagged', true,
                                             'rider_flag_kind', v_rec.flag_kind,
                                             'rider_flag_path', 'indepot_sweep')
         WHERE n.visit_id = v_visit_id;
      ELSE
        UPDATE public.ottoq_visit_needs n
           SET atoms = COALESCE(n.atoms,'[]'::jsonb) || v_atom,
               meta  = COALESCE(n.meta,'{}'::jsonb)
                       || jsonb_build_object('rider_flagged', true,
                                             'rider_flag_kind', v_rec.flag_kind,
                                             'rider_flag_path', 'indepot_sweep')
         WHERE n.visit_id = v_visit_id;
      END IF;
      v_appended := v_appended + 1;
    ELSE
      -- NO OPEN VISIT. This is the 15-sim-hour case: the car finished its visit,
      -- the flag matured afterwards, and there was nothing left to attach work
      -- to. Open a visit whose whole content is the cleaning. urgency
      -- 'standard' on purpose -- 'overnight_hold' carries a dispatch_due_at gate
      -- in ottoq_decide_tick (2) that would hold the car past the work.
      v_visit_key := v_rec.vehicle_id::text || ':rf:' || to_char(p_clock, 'YYYYMMDDHH24MISS');
      INSERT INTO public.ottoq_visit_needs
        (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype,
         urgency, atoms, status, source, meta)
      VALUES
        (v_rec.vehicle_id, p_sim_run_id, p_depot_id, p_clock, v_visit_key,
         'R_rider_flag_cleaning', 'standard', jsonb_build_array(v_atom), 'open',
         'rider_flag_indepot_sweep',
         jsonb_build_object('rider_flagged', true,
                            'rider_flag_kind', v_rec.flag_kind,
                            'rider_flag_path', 'indepot_sweep',
                            'generator', 'ottoq_rider_flag_indepot_sweep'))
      ON CONFLICT (vehicle_id, visit_key) DO UPDATE
        SET atoms = EXCLUDED.atoms, status = 'open', meta = EXCLUDED.meta
      RETURNING visit_id INTO v_visit_id;
      v_opened := v_opened + 1;
    END IF;

    -- THE FLAG IS NOW CONSUMED. Ownership has moved to the must_do atom above.
    -- Same transition 0018's arrival manifest performs, same columns.
    UPDATE public.ottoq_rider_cleaning_flags
       SET status                = 'recalled',
           recalled_at_sim_clock = COALESCE(recalled_at_sim_clock, p_clock),
           recalled_visit_key    = v_visit_key,
           stall_type_required   = COALESCE(stall_type_required, v_stall_type)
     WHERE flag_id = v_rec.flag_id;

    -- Put the car where the bay router can see it, but ONLY if it is holding.
    v_holding := v_rec.vstate IN ('staged_for_departure','charge_complete_holding',
                                  'service_complete_holding','staged_awaiting_service','offline');
    IF v_holding AND v_rec.vstate <> 'staged_awaiting_service' THEN
      UPDATE public.vehicles
         SET current_state     = 'staged_awaiting_service'::vehicle_state,
             last_state_change = p_clock,
             config            = jsonb_set(COALESCE(config,'{}'::jsonb),
                                           '{svc_step}', to_jsonb('need_service'::text))
       WHERE id = v_rec.vehicle_id;
    END IF;

    -- Give the visit an itinerary so the bay leg exists. Never fatal: section
    -- 4b of ottoq_decide_tick can place the vehicle from the needs card alone.
    IF v_holding THEN
      BEGIN
        PERFORM public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.vehicle_id, p_clock);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'rider flag in-depot replan failed for %: % %', v_rec.vehicle_id, SQLSTATE, SQLERRM;
      END;
    END IF;

    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick. Event-write amplification is the known tick-cost
  -- driver on this instance (0012), so this stage never writes per vehicle.
  IF v_n > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'rider_flag_indepot_sweep',
        p_event_type := 'ottoq.rider_flag_serviced_in_depot',
        p_entity_type := 'depot', p_entity_id := p_depot_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object(
          'flags_actioned', v_n, 'visits_opened', v_opened, 'visits_appended', v_appended,
          'sim_clock', p_clock,
          'doctrine', 'a parked car needs no recall, it needs the atom on its visit'),
        p_severity := 'info', p_ingest_source := 'ottoq', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'rider flag sweep summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_rider_flag_indepot_sweep FAILED SAFELY: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_rider_flag_indepot_sweep(uuid, uuid, timestamptz) IS
  '0019: the path a rider flag takes when it comes due while the vehicle is already in '
  'the depot. ottoq_evaluate_return_need cannot see such a vehicle (it requires an ACTIVE '
  'dispatch), so before 0019 those flags sat unserved -- one for 15 sim-hours. Adds the '
  'cleaning atom to the open visit, or opens a visit if there is none, marks the flag '
  'consumed, and returns a holding vehicle to staged_awaiting_service so the bay router '
  'in ottoq_decide_tick (4b) can place it. Never moves a vehicle that is charging, in a '
  'bay, or under an exception. Self-silencing.';

-- ============================================================================
-- 4. (i) THE PLANNER DECLINES TO SELECT A FLAGGED VEHICLE.
--    Byte-for-byte the live pre-image (md5 guarded in section 1) with ONE new
--    clause added to the deploy_plan candidate cursor, immediately after the
--    existing ALWAYS HOLD atom clause it extends. Nothing else in this function
--    is touched: the recall phase, the hold phase, the caps and the ordering are
--    all unchanged.
-- ============================================================================
CREATE OR REPLACE FUNCTION ottoq.ottoq_plan_dispatch_tick(p_phase text, p_sim_run_id uuid, p_depot_id uuid, p_sim_clock_now timestamp with time zone, p_hour integer DEFAULT NULL::integer, p_seed bigint DEFAULT 0, p_to_dispatch integer DEFAULT 0, p_to_recall integer DEFAULT 0, p_holdout_pct integer DEFAULT 1, p_win_start integer DEFAULT 22, p_win_end integer DEFAULT 3, p_tick_minutes_actual numeric DEFAULT 30, p_vehicles jsonb DEFAULT '[]'::jsonb, p_forced boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_release_cap int; v_forced boolean;
  v_release jsonb := '[]'::jsonb; v_hold jsonb := '[]'::jsonb; v_secured jsonb := '[]'::jsonb;
  v_released int := 0; v_valved int := 0;
  v_vehicle RECORD; v_rc RECORD;
  v_free_intake int; v_cap int; v_book jsonb; v_eta numeric;
BEGIN
  IF p_phase = 'deploy_plan' THEN
    v_release_cap := GREATEST(1, ottoq_policy_get(p_sim_run_id,'deploy_release_per_tick_cap', 6)::int);
    v_forced      := ottoq_policy_get(p_sim_run_id,'rush_valve_forced', 0) > 0;
    IF v_forced THEN v_release_cap := GREATEST(1, v_release_cap / 2); END IF;

    IF COALESCE(p_to_dispatch, 0) > 0 THEN
      FOR v_vehicle IN
        SELECT v.id FROM vehicles v
         WHERE v.category = 'autonomous' AND v.home_depot_id = p_depot_id AND v.current_soc >= 80
           AND ( v.current_state = 'en_route_to_deployment'
              OR v.current_state = 'staged_for_departure'
              OR (v.current_state = 'staged_awaiting_service' AND COALESCE(v.config->>'svc_step','ready') IN ('ready'))
              OR (v.current_state = 'offline'))
           AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
              WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'))
           AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open','in_progress')
                AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                             WHERE COALESCE((a->>'must_do')::boolean, false) = true AND a->>'svc' <> 'readiness_check'
                               AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')))
           -- ═══════════ 0019: ALWAYS HOLD, EXTENDED TO THE RIDER FLAG ═══════════
           -- The clause above holds a vehicle that owes a must_do atom on an OPEN
           -- visit. A rider flag that has come due is known work too, but it is not
           -- an atom yet -- the atom is only written when a visit is generated. So
           -- this is the SAME rule applied one step earlier, not a second gate.
           -- public.ottoq_rider_flag_due is STABLE, NULL-safe and never raises, so
           -- it can only ever remove a candidate, never abort the plan.
           AND NOT public.ottoq_rider_flag_due(v.id, p_sim_run_id, p_sim_clock_now)
         ORDER BY ottoq_brain_deploy_rank(p_sim_run_id, v.id) ASC NULLS LAST,
                  v.current_soc DESC, ottoq_sim_seeded_random(p_seed, 'pick:' || v.id::text)
         LIMIT p_to_dispatch
      LOOP
        IF v_released < v_release_cap THEN
          v_release  := v_release || to_jsonb(v_vehicle.id); v_released := v_released + 1;
        ELSIF v_valved < v_release_cap THEN
          v_hold := v_hold || to_jsonb(v_vehicle.id); v_valved := v_valved + 1;
        ELSE
          EXIT;
        END IF;
      END LOOP;
    END IF;

    RETURN jsonb_build_object('phase','deploy_plan','release',v_release,'hold',v_hold,
                              'cap',v_release_cap,'forced',v_forced);

  ELSIF p_phase = 'deploy_hold' THEN
    FOR v_vehicle IN
      SELECT t.value::uuid AS id
        FROM jsonb_array_elements_text(COALESCE(p_vehicles,'[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
       ORDER BY t.ord
    LOOP
      BEGIN
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, p_depot_id, v_vehicle.id, 'stage',
          jsonb_build_object('reason','rush_valve_hold','held_at',p_sim_clock_now,
                             'release_expected','next_dispatch_window','forced_by_technician',p_forced),
          p_sim_clock_now);
        PERFORM ottoq_comms_send_command(p_sim_run_id, v_vehicle.id, 'stage',
          jsonb_build_object('reason','rush_valve_hold','release_expected','next_dispatch_window'),
          p_sim_clock_now, false);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
      v_valved := v_valved + 1;
    END LOOP;

    RETURN jsonb_build_object('phase','deploy_hold','held',v_valved);

  ELSIF p_phase = 'recall' THEN
    SELECT count(*) INTO v_free_intake FROM stalls s
      WHERE s.depot_id = p_depot_id AND s.current_vehicle_id IS NULL
        AND (s.reserved_by IS NULL OR COALESCE(s.reservation_expires_at, p_sim_clock_now) <= p_sim_clock_now)
        AND s.stall_type IN ('dcfc','l2','staging');

    v_cap := LEAST(p_to_recall, GREATEST(0, v_free_intake),
                   GREATEST(1, CEIL(
                     ottoq_policy_get(p_sim_run_id,'overnight_recall_max_per_tick',24)
                     * COALESCE(p_tick_minutes_actual, 30) / 30.0))::int);

    FOR v_rc IN
      SELECT v.id AS vehicle_id, v.current_soc, d.dispatch_id
        FROM vehicles v
        JOIN ottoq_vehicle_dispatches d
          ON d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status = 'active'
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND v.current_state = 'deployed'
         AND ((p_hour >= p_win_end AND p_hour < p_win_start)
              OR NOT ottoq_is_overnight_holdout(v.id, p_sim_run_id, p_sim_clock_now, p_holdout_pct))
         AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                          WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id
                            AND vn.status IN ('open','in_progress'))
       ORDER BY v.current_soc ASC, v.id
       LIMIT GREATEST(0, v_cap)
    LOOP
      v_eta := ottoq_return_eta_minutes(v_rc.vehicle_id, p_depot_id, p_sim_run_id);
      BEGIN
        v_book := ottoq_book_appointment(v_rc.vehicle_id, p_sim_run_id, p_sim_clock_now,
                  'surplus_to_demand', 'overnight_hold', true, v_eta, v_rc.current_soc, p_depot_id);
      EXCEPTION WHEN OTHERS THEN v_book := jsonb_build_object('secured', false, 'reason', 'booking_error');
      END;
      -- LIVE-FAITHFUL GATE: an unsecured booking is skipped entirely, so the twin
      -- never flips a vehicle to en_route_to_depot without a reserved stall.
      IF COALESCE((v_book->>'secured')::boolean, false) THEN
        v_secured := v_secured || jsonb_build_array(jsonb_build_object(
                       'vehicle_id', v_rc.vehicle_id, 'dispatch_id', v_rc.dispatch_id,
                       'soc_at_decision', v_rc.current_soc, 'eta_minutes', v_eta,
                       'appointment', v_book));
      END IF;
    END LOOP;

    RETURN jsonb_build_object('phase','recall','secured',v_secured,
                              'cap',COALESCE(v_cap,0),'free_intake',COALESCE(v_free_intake,0));
  END IF;

  RETURN jsonb_build_object('phase', p_phase, 'error', 'unknown_phase');
END;
$function$;

-- ============================================================================
-- 5. (i, continued) THE SAME RULE AT THE DOOR.
--    Byte-for-byte the live pre-image with the refusal added before any state is
--    written. Placed here as well as in the planner because this function is
--    what actually writes the ottoq_vehicle_dispatches row, clears the stall and
--    supersedes the visit -- a future caller that skipped the planner would
--    otherwise walk straight past the hold.
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dispatch_vehicle(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_dispatch_id     UUID := gen_random_uuid();
  v_vehicle         RECORD;
  v_planned_min     NUMERIC;
  v_seed            BIGINT;
BEGIN
  SELECT current_soc, fleet_operator_id, current_state INTO v_vehicle
    FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'vehicle % not found', p_vehicle_id;
  END IF;

  -- ═══════════════════ 0019: THE DOOR, NOT JUST THE QUEUE ═══════════════════
  -- ottoq.ottoq_plan_dispatch_tick already declines to SELECT a flagged vehicle.
  -- This is the same rule stated where the dispatch row is actually written, so
  -- that no present or future caller of this function can route around it. Under
  -- normal operation the planner filters first and this branch is never taken;
  -- if it is ever taken, the event below says so out loud rather than silently.
  IF public.ottoq_rider_flag_due(p_vehicle_id, p_sim_run_id, p_sim_clock_now) THEN
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type    := 'ottoq_engine',
        p_actor_id      := 'rider_flag_hold',
        p_event_type    := 'twin.dispatch_refused_rider_flag',
        p_entity_type   := 'vehicle',
        p_entity_id     := p_vehicle_id,
        p_payload       := jsonb_build_object(
          'reason', 'vehicle owes a due rider-flagged cleaning',
          'doctrine', 'always_hold_no_vehicle_leaves_owing_known_work',
          'sim_clock', p_sim_clock_now),
        p_severity      := 'warning',
        p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id    := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN NULL;
  END IF;

  v_seed := abs(hashtextextended(p_vehicle_id::text || p_sim_clock_now::text, 42));

  -- Sample trip duration from NYC TLC trip_duration_minutes distribution
  -- (For deployment durations longer than typical taxi trips, scale up.)
  v_planned_min := COALESCE(
    ottoq_sample_calibrated('trip_duration_minutes', 'global', v_seed, 'dispatch'),
    30
  );
  -- AV deployments are continuous shifts of multiple trips. Scale up.
  v_planned_min := v_planned_min * (2 + ottoq_sim_seeded_random(v_seed, 'multiplier') * 6)
                 * ottoq_profile_rate_mult(p_sim_run_id, 'trip_duration');   -- A.10 trip_duration knob (×)

  INSERT INTO ottoq_vehicle_dispatches (
    dispatch_id, vehicle_id, sim_run_id, fleet_operator_id,
    dispatched_at, scheduled_return_at,
    planned_duration_min, soc_at_dispatch_pct, status
  ) VALUES (
    v_dispatch_id, p_vehicle_id, p_sim_run_id, v_vehicle.fleet_operator_id,
    p_sim_clock_now,
    p_sim_clock_now + (v_planned_min || ' minutes')::INTERVAL,
    v_planned_min, v_vehicle.current_soc, 'active'
  );

  -- T3 RENDER CONTRACT: the taxi OUT to the gate. Emitted before the state write
  -- while current_stall_id still holds the origin. Never aborts the dispatch.
  BEGIN
    PERFORM ottoq_itin_travel_leg(
      p_sim_run_id,
      (SELECT home_depot_id FROM vehicles WHERE id = p_vehicle_id),
      p_vehicle_id,
      (SELECT current_stall_id FROM vehicles WHERE id = p_vehicle_id),
      (SELECT s.id FROM stalls s
        WHERE s.depot_id = (SELECT home_depot_id FROM vehicles WHERE id = p_vehicle_id)
          AND s.stall_type = 'staging'::stall_type
        ORDER BY s.relative_x DESC, s.id LIMIT 1),   -- exit is west/high-x per lane doctrine
      p_sim_clock_now, 'taxi_to_gate', 'twin_dispatcher');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (dispatch): %', SQLERRM;
  END;

  UPDATE vehicles
     SET current_state = 'deployed'::vehicle_state,
           -- feed-agent service_manifest: clear at deployment so the NEXT
           -- visit rolls a fresh per-visit manifest (frozen-manifest fix)
           config = (COALESCE(config, '{}'::jsonb) - 'service_manifest' - 'service_manifest_meta'),
         last_state_change = p_sim_clock_now,
         current_stall_id = NULL
   WHERE id = p_vehicle_id;

  -- the visit is over: close its itinerary, supersede unserviced needs and
  -- release any stall this car was still holding (AP-1b / B5)
  BEGIN PERFORM ottoq_release_visit_artifacts(p_vehicle_id, p_sim_run_id, p_sim_clock_now, 'redeployed');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release visit artifacts: %', SQLERRM; END;

  PERFORM ottoq_record_event(
    p_actor_type    := 'oem_dispatch_webhook',
    p_actor_id      := 'twin_dispatch_sim',
    p_event_type    := 'twin.vehicle_arrived',  -- reusing arrival type for dispatch logging
    p_entity_type   := 'vehicle',
    p_entity_id     := p_vehicle_id,
    p_fleet_operator_id := v_vehicle.fleet_operator_id,
    p_payload       := jsonb_build_object(
      'dispatch_id', v_dispatch_id,
      'planned_duration_min', v_planned_min,
      'soc_at_dispatch', v_vehicle.current_soc,
      'mode', 'deployment_start'
    ),
    p_severity      := 'info',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id
  );

  RETURN v_dispatch_id;
END;
$function$;

-- ============================================================================
-- 6. (ii, continued) THE SWEEP IS WIRED IN, AND THE DISPATCH COUNT STOPS LYING.
--    Byte-for-byte the live pre-image with two edits:
--      * the sweep runs once, at the top, before the deploy cursor, so a flag
--        that matures on this tick is already must_do work by the time the
--        dispatcher looks at the vehicle;
--      * the emit event counts a dispatch only when one occurred. A refusal
--        returns NULL and previously would have been counted as a departure.
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_auto_dispatch_tick(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE; v_scenario ottoq_sim_scenarios%ROWTYPE;
  v_hour INTEGER; v_dispatch_mult NUMERIC := 1.0; v_target_deployed_pct NUMERIC := 0.90;
  v_total_fleet INTEGER; v_currently_deployed INTEGER; v_desired_deployed INTEGER;
  v_to_dispatch INTEGER; v_vehicle RECORD; v_count INTEGER := 0; v_seed BIGINT;
  v_recall_on boolean; v_win_start int; v_win_end int; v_hyst int; v_holdout_pct int;
  v_to_recall int; v_cap int; v_recalled int := 0;
  v_sec RECORD; v_eta numeric;
  v_release_cap int; v_valved int := 0; v_forced boolean;
  v_plan jsonb;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  -- ══════════════ 0019: THE IN-DEPOT PATH FOR A RIDER FLAG ══════════════
  -- A flag that comes due while the car is PARKED can never reach
  -- public.ottoq_evaluate_return_need, because that function reads an ACTIVE
  -- dispatch and returns should_return=false when there is none. A parked car
  -- does not need recalling -- it needs the atom put on the visit it is already
  -- having. This runs BEFORE the deploy cursor below, so a flag that matures
  -- this tick becomes must_do work this tick and the same tick's dispatcher
  -- then declines to send the car out. Self-silencing: it must never cost the
  -- depot a dispatch.
  BEGIN
    PERFORM ottoq.ottoq_rider_flag_indepot_sweep(p_sim_run_id, v_run.depot_id, p_sim_clock_now);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rider flag in-depot sweep failed safely: % %', SQLSTATE, SQLERRM;
  END;

  SELECT s.* INTO v_scenario FROM ottoq_sim_scenarios s
   WHERE s.scenario_code = COALESCE(v_run.scenario_code, 'normal_day') LIMIT 1;
  IF v_scenario.scenario_code IS NULL THEN
    SELECT * INTO v_scenario FROM ottoq_sim_scenarios WHERE scenario_code = 'normal_day';
  END IF;
  v_dispatch_mult       := COALESCE((v_scenario.fleet_overrides->>'dispatch_rate_multiplier')::numeric, 1.0);
  v_target_deployed_pct := COALESCE((v_scenario.fleet_overrides->>'target_deployed_fraction')::numeric, 0.90);

  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_seed := abs(hashtextextended(COALESCE(v_run.random_seed, 42)::text || p_sim_clock_now::text || 'disp', 7));

  SELECT COUNT(*) INTO v_total_fleet FROM vehicles
   WHERE category = 'autonomous' AND home_depot_id = v_run.depot_id;
  SELECT COUNT(*) INTO v_currently_deployed
    FROM ottoq_vehicle_dispatches
   WHERE sim_run_id = p_sim_run_id AND status IN ('active', 'returning');

  v_desired_deployed := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(
      v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction', v_target_deployed_pct)) * v_dispatch_mult);

  v_to_dispatch := GREATEST(0, v_desired_deployed - v_currently_deployed);

  -- (1) DEPLOY toward the target. OTTO-Q ranks and paces; the twin departs them.
  IF v_to_dispatch > 0 THEN
    v_plan := ottoq_plan_dispatch_tick(
                'deploy_plan', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                p_hour := v_hour, p_seed := v_seed, p_to_dispatch := v_to_dispatch);
    v_release_cap := COALESCE((v_plan->>'cap')::int, 1);
    v_forced      := COALESCE((v_plan->>'forced')::boolean, false);

    FOR v_vehicle IN
      SELECT t.value::uuid AS id
        FROM jsonb_array_elements_text(COALESCE(v_plan->'release','[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
       ORDER BY t.ord
    LOOP
      -- 0019: count a dispatch only when one actually happened. The refusal in
      -- twin.ottoq_sim_dispatch_vehicle returns NULL, and an emit event that
      -- counted refusals as departures would be a false number.
      IF ottoq_sim_dispatch_vehicle(v_vehicle.id, p_sim_run_id, p_sim_clock_now) IS NOT NULL THEN
        v_count := v_count + 1;
      END IF;
    END LOOP;

    IF jsonb_array_length(COALESCE(v_plan->'hold','[]'::jsonb)) > 0 THEN
      v_valved := COALESCE((ottoq_plan_dispatch_tick(
                    'deploy_hold', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                    p_vehicles := v_plan->'hold', p_forced := v_forced)->>'held')::int, 0);
    END IF;

    IF v_valved > 0 THEN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'rush_valve',
        p_event_type := 'twin.rush_valve_hold', p_entity_type := 'system',
        p_payload := jsonb_build_object('held', v_valved, 'released', v_count,
          'cap', v_release_cap, 'forced', v_forced, 'hour_cst', v_hour),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    END IF;

    IF v_count > 0 THEN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'twin_auto_dispatcher',
        p_event_type := 'twin.auto_dispatch_emit', p_entity_type := 'system',
        p_payload := jsonb_build_object('count', v_count, 'hour_cst', v_hour, 'scenario', v_scenario.scenario_code,
          'total_fleet', v_total_fleet, 'desired', v_desired_deployed, 'deployed', v_currently_deployed),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- (2) OVERNIGHT SURPLUS RECALL. Twin measures the surplus (a demand fact) and
  -- applies the world writes; OTTO-Q ranks it and secures the appointments.
  v_recall_on   := ottoq_policy_get(p_sim_run_id,'overnight_recall_enabled',1) > 0;
  v_win_start   := ottoq_policy_get(p_sim_run_id,'overnight_recall_start_hour',22)::int;
  v_win_end     := ottoq_policy_get(p_sim_run_id,'overnight_recall_end_hour',3)::int;
  v_hyst        := ottoq_policy_get(p_sim_run_id,'overnight_recall_hysteresis',2)::int;
  v_holdout_pct := ottoq_policy_get(p_sim_run_id,'overnight_holdout_pct',1)::int;

  IF v_recall_on AND (v_hour >= v_win_start OR v_hour < 6) THEN
    v_to_recall := GREATEST(0, v_currently_deployed - v_desired_deployed - v_hyst);
    IF v_to_recall > 0 THEN
      v_plan := ottoq_plan_dispatch_tick(
                  'recall', p_sim_run_id, v_run.depot_id, p_sim_clock_now,
                  p_hour := v_hour, p_to_recall := v_to_recall, p_holdout_pct := v_holdout_pct,
                  p_win_start := v_win_start, p_win_end := v_win_end,
                  p_tick_minutes_actual := COALESCE((v_run.payload->>'tick_minutes_actual')::numeric,
                                                    (v_run.tick_interval_seconds::numeric * COALESCE(v_run.time_scale,1))/60.0,
                                                    30));
      v_cap := COALESCE((v_plan->>'cap')::int, 0);

      FOR v_sec IN
        SELECT t.value AS d
          FROM jsonb_array_elements(COALESCE(v_plan->'secured','[]'::jsonb)) WITH ORDINALITY AS t(value, ord)
         ORDER BY t.ord
      LOOP
        v_eta := (v_sec.d->>'eta_minutes')::numeric;
        UPDATE ottoq_vehicle_dispatches
           SET status='returning', return_trigger='surplus_to_demand',
               returning_started_at = p_sim_clock_now,
               return_eta_minutes = v_eta,
               scheduled_return_at = p_sim_clock_now + (v_eta || ' minutes')::interval,
               return_evidence = jsonb_build_object('decided_at',p_sim_clock_now,
                 'soc_at_decision',(v_sec.d->>'soc_at_decision')::int,'hour_cst',v_hour,
                 'reason','overnight_surplus_to_demand','appointment',v_sec.d->'appointment',
                 'desired_deployed',v_desired_deployed,'currently_deployed',v_currently_deployed)
         WHERE dispatch_id = (v_sec.d->>'dispatch_id')::uuid;
        UPDATE vehicles SET current_state='en_route_to_depot'::vehicle_state, last_state_change=p_sim_clock_now
         WHERE id = (v_sec.d->>'vehicle_id')::uuid;
        v_recalled := v_recalled + 1;
      END LOOP;

      IF v_recalled > 0 THEN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='overnight_recall',
          p_event_type:='twin.overnight_surplus_recall', p_entity_type:='system',
          p_payload:=jsonb_build_object('recalled',v_recalled,'hour_cst',v_hour,
            'desired',v_desired_deployed,'deployed_before',v_currently_deployed,'cap',v_cap,
            'holdout_active', NOT (v_hour >= v_win_end AND v_hour < v_win_start)),
          p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      END IF;
    END IF;
  END IF;

  RETURN v_count;
END;
$function$;

-- ============================================================================
-- 7. (iii) THE RECALL RUNG FIRES ONCE PER RAISE.
--    Byte-for-byte the live pre-image with ONE edit: the rider-flag lookup reads
--    the lifecycle table instead of the run-start draw. The rung itself, its
--    position below the safety and reserve rungs and above the contention gate,
--    its urgency, its non-deferrability and its evidence payload are unchanged.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric DEFAULT 30, p_soc_pct numeric DEFAULT NULL::numeric)
 RETURNS TABLE(should_return boolean, return_trigger text, urgency text, rung smallint, is_deferrable boolean, lead_ticks smallint, projected_eta_min numeric, evidence jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_v RECORD; v_pkt RECORD; v_w RECORD;
  v_soc numeric; v_reserve numeric; v_floor numeric; v_eta_min numeric;
  v_hour int; v_depot uuid;
  v_burn_per_min numeric; v_burn_guard numeric; v_reserve_margin numeric;
  v_dtc_debt int; v_comms_stale int; v_wait_cap int; v_backstop_ticks int;
  v_wash_soil numeric; v_sensor_soil numeric; v_pm_km numeric; v_calib_h numeric;
  v_free_chargers int; v_inbound int; v_wait_ticks int; v_max_wait_min numeric;
  v_in_window boolean; v_slot int; v_slot_open boolean; v_holdout boolean;
  v_pkt_age_min numeric; v_has_service_need boolean; v_overnight_need boolean;
  v_ev jsonb;
  v_rf RECORD;   -- 0018
BEGIN
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_evaluate_return_need requires a run scope';
  END IF;

  SELECT d.dispatch_id, d.scheduled_return_at, d.dispatched_at, v.home_depot_id, v.config,
         v.current_soc, v.min_soc_threshold
    INTO v_v
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
   WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = p_sim_run_id AND d.status = 'active'
   ORDER BY d.dispatched_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean,
                        NULL::smallint, NULL::numeric,
                        jsonb_build_object('reason','no active dispatch in run');
    RETURN;
  END IF;
  v_depot := v_v.home_depot_id;

  SELECT tp.soc_pct, tp.sim_clock_at
    INTO v_pkt
    FROM ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at <= p_sim_clock_now AND tp.soc_pct IS NOT NULL
   ORDER BY tp.sim_clock_at DESC, tp.packet_seq DESC LIMIT 1;

  SELECT w.worst_open_dtc_rank, w.open_dtc_count, w.soil_index,
         w.drive_km_total, w.km_at_last_pm, w.drive_hours_total,
         w.hours_at_last_calibration, w.calibrated_at
    INTO v_w
    FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  v_soc     := COALESCE(p_soc_pct, v_pkt.soc_pct, v_v.current_soc);
  v_reserve := ottoq_effective_reserve_soc(p_vehicle_id, p_sim_clock_now);
  v_floor   := ottoq_effective_deploy_floor_at(p_vehicle_id, p_sim_clock_now);
  v_eta_min := ottoq_return_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id);
  v_hour    := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_burn_per_min   := ottoq_policy_get(p_sim_run_id,'p99_burn_pct_per_min',0.25);
  v_reserve_margin := ottoq_policy_get(p_sim_run_id,'reserve_margin_pct',15);
  v_dtc_debt       := ottoq_policy_get(p_sim_run_id,'dtc_debt_threshold',3)::int;
  v_comms_stale    := ottoq_policy_get(p_sim_run_id,'comms_stale_ticks',3)::int;
  v_wait_cap       := ottoq_policy_get(p_sim_run_id,'contention_wait_cap_min',
                        ottoq_policy_get(p_sim_run_id,'contention_wait_cap_ticks',4) * 30)::int;
  v_backstop_ticks := ottoq_policy_get(p_sim_run_id,'timer_backstop_min',
                        ottoq_policy_get(p_sim_run_id,'timer_backstop_ticks',48) * 30)::int;
  v_wash_soil      := ottoq_policy_get(p_sim_run_id,'wash_soil_threshold',0.50);
  v_sensor_soil    := ottoq_policy_get(p_sim_run_id,'sensor_soil_threshold',0.35);
  v_pm_km          := COALESCE((v_v.config->>'pm_interval_km')::numeric, ottoq_policy_get(p_sim_run_id,'pm_interval_km',8000));
  v_calib_h        := COALESCE((v_v.config->>'calib_interval_h')::numeric, ottoq_policy_get(p_sim_run_id,'calib_interval_h',250));

  v_burn_guard := v_burn_per_min * (v_eta_min + p_horizon_min);

  SELECT count(*) INTO v_free_chargers FROM stalls s
   WHERE s.depot_id = v_depot AND s.stall_kind = 'charging'
     AND s.status = 'available' AND s.current_vehicle_id IS NULL;
  SELECT count(*) INTO v_inbound FROM vehicles vv
   WHERE vv.home_depot_id = v_depot AND vv.category='autonomous'
     AND vv.current_state IN ('en_route_to_depot','arrived_at_gate');

  v_wait_ticks := CASE WHEN v_free_chargers >= v_inbound + 1 THEN 0
         ELSE CEIL((v_inbound + 1 - v_free_chargers)/GREATEST(v_free_chargers,1)::numeric) END;
  v_max_wait_min := COALESCE((SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
     JOIN vehicles vv ON vv.id=p_vehicle_id AND vv.fleet_operator_id=s.fleet_operator_id
     WHERE s.status='active' ORDER BY s.version DESC LIMIT 1), 30);

  v_pkt_age_min := CASE WHEN v_pkt.sim_clock_at IS NULL THEN NULL
                        ELSE EXTRACT(EPOCH FROM (p_sim_clock_now - v_pkt.sim_clock_at))/60.0 END;

  v_has_service_need := COALESCE(v_w.soil_index,0) >= v_sensor_soil
     OR COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
     OR (COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3));
  v_overnight_need := v_has_service_need OR v_soc < v_floor;

  -- 0018: the rider flag, read (never drawn) from the run-start draw. Read-only on
  -- the hot path. NULL-safe: a vehicle with no flag row simply has no flag.
  --
  -- ═════════ 0019: READ THE LIFECYCLE, NOT THE DRAW ═════════
  -- 0018 read public.vehicle_need_profile.rider_flag_pending, which is written ONCE
  -- at run start and never cleared. That made the rung re-triggerable: one raise
  -- recalled the same vehicle twice over 16 sim-hours before it was served.
  -- public.ottoq_rider_cleaning_flags.status is the lifecycle -- pending -> recalled
  -- (a visit has taken the atom) -> served -- so reading it makes the rung fire
  -- exactly once per raise. Ownership of the work does not lapse at that moment: it
  -- transfers to the must_do atom on the visit, which the ALWAYS HOLD clauses in
  -- ottoq_decide_tick (2) and ottoq.ottoq_plan_dispatch_tick already enforce.
  -- Shape kept identical so the rung below is unchanged.
  SELECT (f.status = 'pending')  AS rider_flag_pending,
         f.flag_kind             AS rider_flag_kind,
         f.raised_at_sim_clock   AS rider_flag_due_at
    INTO v_rf
    FROM public.ottoq_rider_cleaning_flags f
   WHERE f.vehicle_id = p_vehicle_id
     AND f.sim_run_id = p_sim_run_id;

  v_ev := jsonb_build_object(
    'soc', v_soc, 'reserve', v_reserve, 'deploy_floor', v_floor, 'target_absent_from_loop', true,
    'burn_guard', round(v_burn_guard,2), 'reserve_margin', v_reserve_margin,
    'eta_min', v_eta_min, 'free_chargers', v_free_chargers, 'inbound', v_inbound,
    'wait_ticks', v_wait_ticks, 'reserved_by_bias', 'supply overcounted (reserved_by not consulted)',
    'worst_dtc_rank', v_w.worst_open_dtc_rank, 'soil', v_w.soil_index, 'hour_local', v_hour);

  IF v_soc <= v_reserve + v_burn_guard THEN
    RETURN QUERY SELECT true,'critical_reserve','critical',0::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 0 THEN
    RETURN QUERY SELECT true,'fault_safety_critical','critical',1::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 1 OR COALESCE(v_w.open_dtc_count,0) >= v_dtc_debt THEN
    RETURN QUERY SELECT true,'fault_major','urgent',2::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF v_soc <= v_reserve + v_reserve_margin THEN
    RETURN QUERY SELECT true,'low_soc_reserve','urgent',3::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  -- ===== 0018: RIDER-FLAGGED CLEANING RECALL =====
  -- Below safety and reserve, above everything routine, and NOT behind the
  -- contention gate. is_deferrable = false, lead_ticks = 0: the vehicle turns for
  -- the depot on this tick.
  IF COALESCE(v_rf.rider_flag_pending, false)
     AND v_rf.rider_flag_due_at IS NOT NULL
     AND p_sim_clock_now >= v_rf.rider_flag_due_at THEN
    RETURN QUERY SELECT true,'rider_flag_cleaning','urgent',4::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object(
                          'rider_flag_kind', COALESCE(v_rf.rider_flag_kind,'interior'),
                          'rider_flag_raised_at', v_rf.rider_flag_due_at,
                          'why', 'A ridehail rider reported a '
                                 || COALESCE(v_rf.rider_flag_kind,'interior')
                                 || ' cleanliness issue. Recalled to depot now rather '
                                 || 'than at its next natural return.'); RETURN;
  END IF;

  IF (v_pkt_age_min IS NULL
        AND EXTRACT(EPOCH FROM (p_sim_clock_now - v_v.dispatched_at))/60.0 >= v_comms_stale * p_horizon_min)
     OR (v_pkt_age_min IS NOT NULL AND v_pkt_age_min >= v_comms_stale * p_horizon_min) THEN
    RETURN QUERY SELECT true,'comms_stale','urgent',8::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object('pkt_age_min', v_pkt_age_min); RETURN;
  END IF;
  IF v_v.scheduled_return_at IS NOT NULL
     AND p_sim_clock_now >= v_v.scheduled_return_at + (v_backstop_ticks || ' minutes')::interval THEN
    RETURN QUERY SELECT true,'timer_backstop','anomaly',9::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  IF LEAST(v_wait_ticks * 30.0, v_wait_cap) <= v_max_wait_min THEN
    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN
      RETURN QUERY SELECT true,'service_interval_due','routine',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    IF COALESCE(v_w.soil_index,0) >= v_sensor_soil THEN
      RETURN QUERY SELECT true,'sensor_soil','routine',5::smallint,true,1::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    v_in_window := (v_hour >= 22 OR v_hour < 4);
    v_slot      := LEAST(3, width_bucket(v_soc, 0, 100, 3));
    v_slot_open := (v_hour >= 22 AND v_hour - 22 >= v_slot - 1) OR v_hour < 4;
    v_holdout := ottoq_is_overnight_holdout(p_vehicle_id, p_sim_run_id, p_sim_clock_now, ottoq_policy_get(p_sim_run_id, 'overnight_holdout_pct', 1)::int);
    IF v_in_window AND v_slot_open AND v_overnight_need AND (NOT v_holdout OR (v_hour >= 3 AND v_hour < 22)) THEN
      RETURN QUERY SELECT true,'overnight_prestage','scheduled',6::smallint,true,1::smallint,v_eta_min,
                          v_ev || jsonb_build_object('slot', v_slot); RETURN;
    END IF;
    IF (COALESCE(v_w.soil_index,0) >= v_wash_soil
        OR COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3))
       AND (v_hour < 7 OR v_hour >= 21) THEN
      RETURN QUERY SELECT true,'wash_cadence','routine',7::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean, NULL::smallint, NULL::numeric,
                      v_ev || jsonb_build_object('decision','no need; stay deployed');
END;
$function$;

-- ============================================================================
-- 8. ASSERTIONS.  These run inside the transaction. Any failure rolls back
--    every function replacement above.
--
--    A NOTE ON WHAT THEY CAN PROVE.  Four of the five are behavioural: they
--    exercise the real predicate against real rows and then remove those rows.
--    The two that are structural say so in their own message rather than
--    claiming more than they check -- a still-held or late-returning row must
--    never be dressed as a success.
-- ============================================================================
DO $assert$
DECLARE
  v_run uuid := gen_random_uuid();     -- a run id that cannot collide with a real one
  v_veh uuid; v_depot uuid; v_clock timestamptz := timestamptz '2026-01-01 12:00:00+00';
  v_flag uuid;
  v_bad int; v_n int; v_txt text; v_st text; v_svc text;
BEGIN
  SELECT v.id, v.home_depot_id INTO v_veh, v_depot
    FROM public.vehicles v
   WHERE v.category = 'autonomous' AND v.is_active
   ORDER BY v.id LIMIT 1;
  IF v_veh IS NULL THEN RAISE EXCEPTION 'A0 FAILED: no autonomous vehicle to assert against'; END IF;

  -- ── A1. NO VEHICLE WITH A DUE FLAG CAN BE DISPATCHED ──────────────────────
  -- Behavioural half: the predicate the two gates share must say true for a due
  -- pending flag, false before it is due, and false once it is consumed.
  INSERT INTO public.ottoq_rider_cleaning_flags
    (sim_run_id, vehicle_id, depot_id, flag_kind, status, why, service_atom,
     stall_type_required, raised_at_sim_clock)
  VALUES (v_run, v_veh, v_depot, 'exterior', 'pending',
          '0019 assertion probe; removed before COMMIT', 'exterior_wash',
          'wash_bay', v_clock)
  RETURNING flag_id INTO v_flag;

  IF NOT public.ottoq_rider_flag_due(v_veh, v_run, v_clock) THEN
    RAISE EXCEPTION 'A1 FAILED: a due, pending rider flag does not read as due';
  END IF;
  IF public.ottoq_rider_flag_due(v_veh, v_run, v_clock - interval '1 minute') THEN
    RAISE EXCEPTION 'A1 FAILED: a flag reads as due one minute BEFORE it was raised';
  END IF;
  IF public.ottoq_rider_flag_due(NULL, v_run, v_clock)
     OR public.ottoq_rider_flag_due(v_veh, NULL, v_clock)
     OR public.ottoq_rider_flag_due(v_veh, v_run, NULL) THEN
    RAISE EXCEPTION 'A1 FAILED: the predicate is not total over NULL arguments';
  END IF;

  -- Structural half: both dispatch gates must actually consult it. Stated as a
  -- text check and labelled as one -- it proves the clause is present, not that
  -- a live run declined a dispatch. That is measured on a run, not here.
  SELECT count(*) INTO v_bad FROM (VALUES
      ('ottoq.ottoq_plan_dispatch_tick(text,uuid,uuid,timestamptz,integer,bigint,integer,integer,integer,integer,integer,numeric,jsonb,boolean)'),
      ('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)')
    ) AS t(fn)
   WHERE pg_get_functiondef(t.fn::regprocedure) NOT LIKE '%ottoq_rider_flag_due%';
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'A1 FAILED (structural): % of 2 dispatch gates do not consult ottoq_rider_flag_due', v_bad;
  END IF;

  -- ── A3. A FLAG CANNOT FIRE TWICE FOR ONE RAISE ────────────────────────────
  -- Consuming the flag must make the predicate false, and the recall rung must
  -- be reading the lifecycle rather than the never-cleared draw column.
  UPDATE public.ottoq_rider_cleaning_flags SET status = 'recalled' WHERE flag_id = v_flag;
  IF public.ottoq_rider_flag_due(v_veh, v_run, v_clock) THEN
    RAISE EXCEPTION 'A3 FAILED: a consumed (recalled) flag still reads as due -- it can fire twice';
  END IF;
  UPDATE public.ottoq_rider_cleaning_flags SET status = 'served' WHERE flag_id = v_flag;
  IF public.ottoq_rider_flag_due(v_veh, v_run, v_clock) THEN
    RAISE EXCEPTION 'A3 FAILED: a served flag still reads as due';
  END IF;

  v_txt := pg_get_functiondef('public.ottoq_evaluate_return_need(uuid,uuid,timestamptz,numeric,numeric)'::regprocedure);
  IF v_txt NOT LIKE '%ottoq_rider_cleaning_flags%' THEN
    RAISE EXCEPTION 'A3 FAILED: the recall rung does not read the flag lifecycle table';
  END IF;
  IF v_txt LIKE '%p.rider_flag_pending%' THEN
    RAISE EXCEPTION 'A3 FAILED: the recall rung still reads vehicle_need_profile.rider_flag_pending, which is never cleared';
  END IF;

  DELETE FROM public.ottoq_rider_cleaning_flags WHERE flag_id = v_flag;
  IF EXISTS (SELECT 1 FROM public.ottoq_rider_cleaning_flags WHERE sim_run_id = v_run) THEN
    RAISE EXCEPTION 'A1/A3 FAILED: the assertion probe row was not removed';
  END IF;

  -- ── A2. A PARKED VEHICLE WITH A DUE FLAG ACQUIRES THE ATOM ────────────────
  -- The stage must exist, must be wired into the dispatch tick, and must run
  -- BEFORE the deploy cursor -- a sweep that ran after it would let the car out
  -- for one tick, which is the exact defect being closed.
  IF to_regprocedure('ottoq.ottoq_rider_flag_indepot_sweep(uuid,uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'A2 FAILED: the in-depot sweep does not exist';
  END IF;
  v_txt := pg_get_functiondef('twin.ottoq_sim_auto_dispatch_tick(uuid,timestamptz,numeric)'::regprocedure);
  IF v_txt NOT LIKE '%ottoq_rider_flag_indepot_sweep%' THEN
    RAISE EXCEPTION 'A2 FAILED: the in-depot sweep is never called';
  END IF;
  IF position('ottoq_rider_flag_indepot_sweep' in v_txt) > position('deploy_plan' in v_txt) THEN
    RAISE EXCEPTION 'A2 FAILED: the sweep runs AFTER the deploy plan, so a maturing flag would still leave the depot';
  END IF;
  -- and the sweep must be the complement of the recall rung, never its rival
  v_txt := pg_get_functiondef('ottoq.ottoq_rider_flag_indepot_sweep(uuid,uuid,timestamptz)'::regprocedure);
  IF v_txt NOT LIKE '%ottoq_vehicle_dispatches%' THEN
    RAISE EXCEPTION 'A2 FAILED: the sweep does not exclude vehicles that are out on a dispatch';
  END IF;

  -- ── A4. THE INTERIOR / EXTERIOR MAPPING IS STILL TOTAL ────────────────────
  -- Both kinds must resolve to a stall type that EXISTS at every depot that has
  -- vehicles, and interior must still fold onto the wash lane because there are
  -- zero detail_bay stalls. Checked per depot, not globally.
  FOR v_depot IN SELECT DISTINCT home_depot_id FROM public.vehicles
                  WHERE category = 'autonomous' AND home_depot_id IS NOT NULL
  LOOP
    FOREACH v_svc IN ARRAY ARRAY['exterior_wash','interior_deep_clean'] LOOP
      v_st := ottoq.ottoq_svc_to_stall_type(v_svc, v_depot);
      IF v_st IS NULL THEN
        RAISE EXCEPTION 'A4 FAILED: % resolves to NO stall type at depot %', v_svc, v_depot;
      END IF;
      SELECT count(*) INTO v_n FROM public.stalls s
       WHERE s.depot_id = v_depot AND s.stall_type::text = v_st;
      IF v_n = 0 THEN
        RAISE EXCEPTION 'A4 FAILED: % resolves to stall type % which does not exist at depot %',
          v_svc, v_st, v_depot;
      END IF;
    END LOOP;
  END LOOP;
  -- the unrecognised-kind branch: the sweep must have an ELSE that takes the
  -- interior lane, so a flag_kind nobody has seen before still gets cleaned.
  v_txt := pg_get_functiondef('ottoq.ottoq_rider_flag_indepot_sweep(uuid,uuid,timestamptz)'::regprocedure);
  IF v_txt NOT LIKE '%IF v_rec.flag_kind = ''exterior'' THEN%' OR v_txt NOT LIKE '%ELSE%' THEN
    RAISE EXCEPTION 'A4 FAILED: the sweep mapping is not total (no ELSE branch for an unrecognised kind)';
  END IF;

  -- ── A5. EVERY DRAWABLE BAY ATOM RESOLVES TO A STALL TYPE THAT EXISTS ──────
  -- Not just the two cleaning atoms: every service in the catalogue whose lane
  -- asks for a space. One unresolvable name here is the 2026-08-01 leg_type
  -- failure waiting to happen.
  v_bad := 0; v_txt := '';
  FOR v_depot IN SELECT DISTINCT home_depot_id FROM public.vehicles
                  WHERE category = 'autonomous' AND home_depot_id IS NOT NULL
  LOOP
    FOR v_svc IN SELECT p.svc FROM public.service_cadence_policy p
                  WHERE p.is_active AND p.lane IN ('wash_bay','detail','service_bay')
    LOOP
      v_st := ottoq.ottoq_svc_to_stall_type(v_svc, v_depot);
      SELECT count(*) INTO v_n FROM public.stalls s
       WHERE s.depot_id = v_depot AND s.stall_type::text = COALESCE(v_st,'__none__');
      IF v_st IS NULL OR v_n = 0 THEN
        v_bad := v_bad + 1;
        v_txt := v_txt || E'\n  ' || v_svc || ' @ ' || v_depot::text || ' -> ' || COALESCE(v_st,'(null)');
      END IF;
    END LOOP;
  END LOOP;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % catalogue atom/depot pairs resolve to a stall type that does not exist:%', v_bad, v_txt;
  END IF;

  RAISE NOTICE '0019 assertions A1-A5 passed.';
END
$assert$;

COMMIT;
