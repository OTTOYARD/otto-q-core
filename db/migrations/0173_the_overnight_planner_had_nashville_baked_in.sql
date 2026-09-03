-- 0173  The overnight planner had Nashville baked in. forces_recert = FALSE, provably.
--
-- WHY THIS IS SAFE TO APPLY WITHOUT A ROUND, and the proof rather than the
-- assurance: public.ottoq_plan_overnight_wave has ZERO callers. No engine
-- function, no twin function, no edge function references it, and
-- ottoq_wave_plan has zero rows. A function nothing calls cannot participate in
-- a run, so it cannot move a canon. Re-check before trusting this:
--
--   SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--    WHERE p.prokind='f' AND n.nspname IN ('public','twin')
--      AND p.proname <> 'ottoq_plan_overnight_wave'
--      AND pg_get_functiondef(p.oid) ILIKE '%ottoq_plan_overnight_wave%';   -- 0
--
-- If that ever returns non-zero, this migration's classification is wrong and
-- the change belongs to a forces_recert round instead.
--
--
-- CONTEXT. Chase ratified the overnight model on 2026-09-02: vehicles return
-- home nightly for charge, cleaning, inspection and service, and non-urgent work
-- queues for that window unless it is needed sooner or a daytime reservation is
-- free. docs/DECISION_BOUNDARY.md places the window, the must-by, the escalation
-- and the opportunistic fill in the deterministic core.
--
-- This planner is the deterministic slot for exactly that, already written and
-- never wired in. It is a real planner - earliest-deadline-first, L2 preferred
-- so scarce DCFC is saved for assets that need it, slot-based capacity
-- reservation, and infeasible assets recorded with a reason rather than dropped.
-- Its own comments call the per-vehicle deploy time a "founder-ratify item";
-- Chase has now ratified the common-morning-deploy shape, so the assumption is
-- answered and the planner can be corrected before it is connected.
--
-- Three defects fixed here. Wiring it into the decide path is deliberately NOT
-- done here - that is an engine change, forces_recert, and its own round.
--
--
-- 1. NASHVILLE WAS HARDCODED
--    The deadline was computed in a literal 'America/Chicago', in a kernel that
--    CLAUDE.md 2.2 requires to be sector- and site-agnostic. depots already
--    carries operating_timezone and timezone; both existing depots are
--    America/Chicago, which is precisely why a hardcoded literal survived - a
--    constant that matches every row of your data is invisible until there is a
--    second timezone. The first depot in another zone would have planned its
--    overnight wave against Nashville's clock.
--
-- 2. THE MORNING DEPLOY HOUR WAS A MAGIC NUMBER
--    5am local, expressed as a 5h/29h interval branch. Both depots run
--    00:00-23:59 operational hours, so it cannot be derived from the depot's own
--    hours - it is a genuine policy choice and becomes a policy parameter at its
--    current value. Same treatment 0159 gave the wait-vs-slower-charger choice
--    and 0169 drafts for the seating batch.
--
-- 3. A WALL CLOCK FALLBACK
--    COALESCE(v_run.sim_clock_current, now()) would silently plan against real
--    time if a run had no sim clock. Today's 0172 was exactly this failure mode
--    in another column - transaction now() landing in a sim-clock field and
--    surviving unnoticed because the pair harness cannot see it. A planner with
--    no clock now REFUSES rather than inventing one.
--
-- Everything else is byte-for-byte the original: the EDF ordering, the L2-first
-- preference, the slot reservation arithmetic, the stranded accounting and the
-- returned CapEx signal are untouched.

INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES ('overnight_deploy_hour_local',
        'Local hour at which the overnight wave must have every asset ready for morning deployment. Replaces a hardcoded 5am in ottoq_plan_overnight_wave (0173). Local to the depot''s operating_timezone, not to the server.',
        5, 0, 23, 'ottoq_plan_overnight_wave')
ON CONFLICT (param_key) DO UPDATE
  SET description = EXCLUDED.description, default_value = EXCLUDED.default_value,
      min_value = EXCLUDED.min_value, max_value = EXCLUDED.max_value, affects = EXCLUDED.affects;

CREATE OR REPLACE FUNCTION public.ottoq_plan_overnight_wave(p_sim_run_id uuid, p_morning_deploy_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_slot_min integer DEFAULT 15, p_dcfc_kw numeric DEFAULT 150, p_l2_kw numeric DEFAULT 19)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run ottoq_sim_runs%ROWTYPE;
  v_now timestamptz; v_deadline timestamptz; v_slots int;
  v_dcfc_cap int; v_l2_cap int;
  v_dcfc_free int[]; v_l2_free int[];
  v_rec RECORD;
  v_need_kwh numeric; v_min_l2 numeric; v_min_dcfc numeric;
  v_s int; v_ok boolean; v_class text; v_start int; v_kslots int;
  v_planned int := 0; v_stranded int := 0; v_dcfc_used int := 0; v_l2_used int := 0;
  j int;
  v_tz text; v_deploy_hour int;   -- 0173
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'run_not_found'); END IF;

  -- 0173: no sim clock means no plan. Never fall back to now() - a wall clock in
  -- a sim-clock computation is the 0172 defect, and it hides.
  IF v_run.sim_clock_current IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'run_has_no_sim_clock');
  END IF;
  v_now := v_run.sim_clock_current;

  -- 0173: the depot's own timezone, not the author's.
  SELECT COALESCE(d.operating_timezone, d.timezone, 'UTC') INTO v_tz
    FROM depots d WHERE d.id = v_run.depot_id;
  v_tz := COALESCE(v_tz, 'UTC');

  v_deploy_hour := GREATEST(0, LEAST(23,
      COALESCE(public.ottoq_policy_get(p_sim_run_id, 'overnight_deploy_hour_local', 5), 5)::int));

  v_deadline := COALESCE(p_morning_deploy_at,
    ((date_trunc('day', (v_now AT TIME ZONE v_tz))
      + CASE WHEN EXTRACT(HOUR FROM (v_now AT TIME ZONE v_tz)) < v_deploy_hour
             THEN make_interval(hours => v_deploy_hour)
             ELSE make_interval(hours => v_deploy_hour + 24) END) AT TIME ZONE v_tz));

  v_slots := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (v_deadline - v_now)) / (p_slot_min*60.0))::int);
  IF v_slots > 200 THEN v_slots := 200; END IF;   -- guard

  SELECT COUNT(*) FILTER (WHERE stall_type::text='dcfc'),
         COUNT(*) FILTER (WHERE stall_type::text='l2')
    INTO v_dcfc_cap, v_l2_cap
    FROM stalls WHERE depot_id = v_run.depot_id;

  v_dcfc_free := array_fill(v_dcfc_cap, ARRAY[v_slots]);
  v_l2_free   := array_fill(v_l2_cap,   ARRAY[v_slots]);

  DELETE FROM ottoq_wave_plan WHERE sim_run_id = p_sim_run_id;

  -- worklist: returning / en-route / at-depot-awaiting vehicles that need charge.
  -- FOUNDER WALL: vehicles already IN a charger/bay are NOT rescheduled here.
  -- EDF order: earliest due first; deepest-drained first as the tiebreak.
  FOR v_rec IN
    SELECT v.id, v.current_soc, COALESCE(v.target_soc, public.ottoq_default_target_soc()) AS target_soc,
           COALESCE(v.battery_capacity_kwh, 75) AS cap_kwh,
           -- 0173: common morning deploy, ratified by Chase 2026-09-02 (vehicles
           -- return home nightly). A staggered per-vehicle deploy distribution
           -- remains open and would replace this expression, not the ordering.
           v_deadline AS due_at
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category='autonomous'
       AND v.current_state IN ('deployed','en_route_to_depot','arrived_at_gate',
                               'staged_awaiting_service','charge_complete_holding')
       AND v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 2
     ORDER BY due_at ASC, v.current_soc ASC, v.id  /* 0130 */
  LOOP
    v_need_kwh := GREATEST(0, (v_rec.target_soc - v_rec.current_soc)/100.0 * v_rec.cap_kwh);
    v_min_l2   := v_need_kwh / p_l2_kw * 60.0;
    v_min_dcfc := v_need_kwh / p_dcfc_kw * 60.0;

    v_class := NULL; v_start := NULL;
    -- PREFER L2 (save scarce DCFC for who truly needs it) IF it finishes by deadline;
    -- else DCFC; else stranded. Earliest feasible start (fill the valley from wave onset).
    v_kslots := GREATEST(1, CEIL(v_min_l2 / p_slot_min)::int);
    IF v_kslots <= v_slots THEN
      FOR v_s IN 1 .. (v_slots - v_kslots + 1) LOOP
        v_ok := true;
        FOR j IN v_s .. (v_s + v_kslots - 1) LOOP
          IF v_l2_free[j] <= 0 THEN v_ok := false; EXIT; END IF;
        END LOOP;
        IF v_ok THEN v_class := 'l2'; v_start := v_s; EXIT; END IF;
      END LOOP;
    END IF;
    IF v_class IS NULL THEN
      v_kslots := GREATEST(1, CEIL(v_min_dcfc / p_slot_min)::int);
      IF v_kslots <= v_slots THEN
        FOR v_s IN 1 .. (v_slots - v_kslots + 1) LOOP
          v_ok := true;
          FOR j IN v_s .. (v_s + v_kslots - 1) LOOP
            IF v_dcfc_free[j] <= 0 THEN v_ok := false; EXIT; END IF;
          END LOOP;
          IF v_ok THEN v_class := 'dcfc'; v_start := v_s; EXIT; END IF;
        END LOOP;
      END IF;
    END IF;

    IF v_class IS NULL THEN
      INSERT INTO ottoq_wave_plan (sim_run_id, vehicle_id, want_class, target_soc, due_at, feasible, reason)
      VALUES (p_sim_run_id, v_rec.id, 'none', v_rec.target_soc, v_rec.due_at, false, 'no_charger_block_meets_deadline');
      v_stranded := v_stranded + 1;
      CONTINUE;
    END IF;

    -- reserve the block
    FOR j IN v_start .. (v_start + v_kslots - 1) LOOP
      IF v_class='l2' THEN v_l2_free[j] := v_l2_free[j] - 1; ELSE v_dcfc_free[j] := v_dcfc_free[j] - 1; END IF;
    END LOOP;
    IF v_class='l2' THEN v_l2_used := v_l2_used + 1; ELSE v_dcfc_used := v_dcfc_used + 1; END IF;

    INSERT INTO ottoq_wave_plan (sim_run_id, vehicle_id, want_class, charge_start_at, charge_end_at,
      charge_minutes, target_soc, due_at, feasible, reason)
    VALUES (p_sim_run_id, v_rec.id, v_class,
      v_now + ((v_start-1)*p_slot_min || ' minutes')::interval,
      v_now + ((v_start-1+v_kslots)*p_slot_min || ' minutes')::interval,
      ROUND(CASE WHEN v_class='l2' THEN v_min_l2 ELSE v_min_dcfc END,1),
      v_rec.target_soc, v_rec.due_at, true, 'scheduled');
    v_planned := v_planned + 1;
  END LOOP;

  -- peak concurrent chargers (energy proxy for the infeasibility/CapEx signal)
  RETURN jsonb_build_object(
    'ok', true, 'sim_run_id', p_sim_run_id, 'generator', 'edf_v1',
    'horizon_slots', v_slots, 'slot_min', p_slot_min, 'deadline', v_deadline,
    'timezone', v_tz, 'deploy_hour_local', v_deploy_hour,   /* 0173 */
    'resources', jsonb_build_object('dcfc', v_dcfc_cap, 'l2', v_l2_cap),
    'planned', v_planned, 'stranded', v_stranded,
    'dcfc_used', v_dcfc_used, 'l2_used', v_l2_used,
    'peak_dcfc_concurrent', v_dcfc_cap - (SELECT COALESCE(MIN(x),v_dcfc_cap) FROM unnest(v_dcfc_free) x),
    'peak_l2_concurrent',   v_l2_cap   - (SELECT COALESCE(MIN(x),v_l2_cap)   FROM unnest(v_l2_free) x),
    'feasible_all', (v_stranded = 0));
END;
$function$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_overnight_planner_had_nashville_baked_in', false,
        'ottoq_plan_overnight_wave has zero callers and ottoq_wave_plan zero rows, so it cannot participate in a run or move a canon - the classification is checkable, and the query to re-check is in the migration header. Fixes a hardcoded America/Chicago (depots carry operating_timezone), a magic 5am morning-deploy hour (now the policy param overnight_deploy_hour_local at its current value), and a COALESCE to now() that would plan against wall clock. EDF ordering, L2-first preference and slot arithmetic untouched. Wiring it into the decide path is a separate forces_recert change.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
