-- migration-version: 20260819220000
-- migration-name:    twin_service_flow_admit_order_and_deal_salts
-- 0048 — C7 FOLLOW-UP #2, found by re-certification #2 (post-0047 arm 44252690):
-- a cert tick died with a unique violation on idx_stalls_one_vehicle_per_stall.
--
-- TWO DEFECTS, ONE FUNCTION (twin.ottoq_sim_advance_service_flow):
--
-- (1) ADMIT ORDER. Both bay-admit blocks (wash/detail and service) flipped the
--     vehicle's state to the in-bay state BEFORE vacating the stall it was
--     standing on. trg_reassignment_guard protects in-bay states: it saw the
--     new state, vetoed the release (silently restoring OLD.current_vehicle_id),
--     and the following place-statement violated the one-stall-per-vehicle
--     index — aborting the entire tick. This is the mechanism behind the open
--     B1 double-stall finding (TWIN_CORE.md §1). Fix: stall handoff first,
--     state write second. Statements are byte-identical; only order changed.
--
-- (2) DEAL SCOPES. Three ottoq_twin_deal scopes (wash_time / detail_time /
--     maintenance_time duration multipliers) were keyed
--     v_rec.id || ':' || p_sim_clock_now::text — the ABSOLUTE clock, the exact
--     0045/0047 defect class: same-seed runs deal different duration cards.
--     Fix: run-relative offset via twin.ottoq_sim_clock_salt.
--
-- Body otherwise byte-identical to the 2026-08-19 capture in db/fn_current/
-- (md5 a972827df8f098fded8278c5842d00ed).

CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_service_flow(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric, p_depot_id uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
 RETURNS TABLE(out_washing integer, out_servicing integer, out_staged integer, out_ready integer, out_overflow integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wash_cap    INT;  v_svc_cap     INT;  v_deploy_cap  INT;
  v_wash_dur    NUMERIC; v_detail_dur NUMERIC; v_svc_dur NUMERIC;
  v_in_wash     INT;  v_in_svc      INT;  v_admitted    INT;
  v_order       TEXT;  v_rec         RECORD;  v_needs_svc   BOOLEAN;  v_overflow    INT := 0;
  v_hour        INT;  v_fleet       INT;  v_deployed    INT;  v_target      INT;
  v_pressure    BOOLEAN := FALSE;  v_fasttracked INT := 0;  v_recharged   INT := 0;
  v_floor       NUMERIC;  v_end_ts      TIMESTAMPTZ;  v_feed_sim BOOLEAN := TRUE;
  -- DEPARTURE READINESS GATE (2026-08-02)
  v_ncand       INT := 0;  v_gate_on BOOLEAN := TRUE;
  v_patience_dep NUMERIC;  v_hardcap NUMERIC;  v_relcap INT;
  v_held        INT := 0;  v_esc_gate INT := 0;  v_override INT := 0;
  -- 0009 (DEFECT 1) HONEST COMPLETION CREDIT. Four working sets and three counters.
  -- v_bay_caps    = what this bay is PHYSICALLY ABLE to do (unchanged from the pre-image).
  -- v_outstanding = what THIS VEHICLE actually still had open on THIS visit, read before
  --                 the atoms are marked done.
  -- v_flag_svcs   = the technician flag that admitted it, where the flag names the work.
  -- v_credit      = v_bay_caps INTERSECT (v_outstanding UNION v_flag_svcs)  <-- the fix.
  v_bay_caps    TEXT[];  v_outstanding TEXT[];  v_flag_svcs TEXT[];  v_credit TEXT[];
  v_credited    INT := 0;  v_suppressed  INT := 0;  v_credit_none INT := 0;
BEGIN
  v_wash_cap   := ottoq_sim_lane_capacity(p_sim_run_id, 'cleaning_staff', 3);
  v_svc_cap    := ottoq_sim_lane_capacity(p_sim_run_id, 'service_staff', 2);
  v_deploy_cap := ottoq_sim_lane_capacity(p_sim_run_id, 'deploy_staff', 20);
  v_wash_dur   := ottoq_sim_service_minutes(p_sim_run_id, 'wash_time', 9);
  v_detail_dur := ottoq_sim_service_minutes(p_sim_run_id, 'detail_time', 25);
  v_svc_dur    := ottoq_sim_service_minutes(p_sim_run_id, 'maintenance_time', 40);
  v_floor      := ottoq_policy_get(p_sim_run_id, 'deploy_floor_soc', 80);
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = p_depot_id;
  v_feed_sim := COALESCE(v_feed_sim, TRUE);

  SELECT COALESCE((knobs #>> ARRAY['_policy','scheduling_algorithm']), 'calibrated')
    INTO v_order FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  v_order := COALESCE(v_order, 'calibrated');

  -- ───── STEP 0: re-charge stranded under-floor vehicles (deadlock breaker) ─────
  FOR v_rec IN
    SELECT v.id FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
       AND v.current_state IN ('charge_complete_holding','staged_awaiting_service','staged_for_departure')
       AND v.current_soc < v_floor
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
              WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
                AND a->>'svc' = 'charge' AND COALESCE(a->>'status','open') <> 'done')
       AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
              WHERE d.vehicle_id = v.id AND d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning'))
  LOOP
    -- DOCTRINE (Chase 2026-07-28): never bounce a vehicle to the gate.
    -- SPLIT 2026-07-29: the CHOICE (re-queue for charge + pick/hold/reserve the temp
    -- stall) moved to ottoq_replan_stranded_undercharge. The twin only executes the
    -- returned plan: the flag write and the physical occupancy write.
    DECLARE v_dec jsonb; v_s uuid;
    BEGIN
      v_dec := ottoq_replan_stranded_undercharge(v_rec.id, p_sim_run_id, p_depot_id, p_sim_clock_now);

      UPDATE vehicles
         SET current_state = 'staged_awaiting_service'::vehicle_state,
             last_state_change = p_sim_clock_now,
             config = jsonb_set(config, '{svc_step}',
                                to_jsonb(COALESCE(v_dec->>'svc_step', 'need_charge')))
       WHERE id = v_rec.id;

      v_s := NULLIF(v_dec->>'stall_id', '')::uuid;
      -- ASK THE ARM FIRST. 'charge_complete_holding' is one of this loop's
      -- candidate states and it is also the demate window, so a car can be
      -- re-placed here with the arm still attached to it.
      IF v_s IS NOT NULL
         AND twin.ottoq_arm_refuse_move(v_rec.id, 'service_flow.stranded_recharge',
                                        v_s, p_sim_run_id, p_sim_clock_now) THEN
        v_s := NULL;
      END IF;
      IF v_s IS NOT NULL THEN
        -- ONE STALL PER VEHICLE, RELEASE BEFORE CLAIM. See the migration header.
        UPDATE stalls SET current_vehicle_id = NULL,
               status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
         WHERE current_vehicle_id = v_rec.id AND id <> v_s;
        UPDATE vehicles SET current_stall_id = v_s WHERE id = v_rec.id;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_s;
      END IF;
    END;
    v_recharged := v_recharged + 1;
  END LOOP;
  IF v_recharged > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.recharge_stranded',
      p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('recharged', v_recharged, 'floor', v_floor),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;

  -- ───── STEP 1: complete in-progress services (elapsed timer OR null-timer stuck) ─────
  FOR v_rec IN
    SELECT id, current_state, config FROM vehicles
     WHERE home_depot_id = p_depot_id
       AND current_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
       AND ( COALESCE((config->>'service_done')::boolean, FALSE)
          OR ( v_feed_sim AND (
                 (config->>'service_ends_at') IS NULL
              OR (config->>'service_ends_at')::timestamptz <= p_sim_clock_now ) ) )
  LOOP
    v_end_ts := COALESCE((v_rec.config->>'service_ends_at')::timestamptz, p_sim_clock_now);
    -- T3 RENDER CONTRACT: the drive OUT of the bay to staging. Origin left NULL so the
    -- emitter resolves it from leg history to the bay the entry leg targeted, closing
    -- the route. Destination is a render target only; staged_awaiting_service holds no
    -- stall. Never allowed to abort the transition.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        (SELECT s.id FROM stalls s
          WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging'::stall_type
          ORDER BY (s.current_vehicle_id IS NOT NULL), s.stall_code
          OFFSET (abs(hashtext(v_rec.id::text)) % 20) LIMIT 1),
        p_sim_clock_now,
        CASE WHEN v_rec.current_state IN ('in_wash_bay','in_detail_bay')
             THEN 'exit_wash_to_staging' ELSE 'exit_service_to_staging' END,
        'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (bay exit): %', SQLERRM;
    END;
    IF v_rec.current_state IN ('in_wash_bay','in_detail_bay') THEN
      v_needs_svc := COALESCE((v_rec.config->>'flagged_issue')::boolean, FALSE);
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb(CASE WHEN v_needs_svc THEN 'need_service' ELSE 'need_deploy' END)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion'
       WHERE id = v_rec.id;
    ELSE
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('need_deploy'::text)), '{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion'
       WHERE id = v_rec.id;
    END IF;
    PERFORM ottoq_itin_leg_close(p_sim_run_id, v_rec.id, ARRAY['wash','detail','service'], v_end_ts);

    -- ═══════ 0009 FIX (DEFECT 1) — CREDIT ONLY THE WORK THIS VEHICLE ACTUALLY HAD ═══════
    -- WAS: every bay exit credited a FIXED array regardless of why the car was in the bay,
    -- so a vehicle in for ONE job was recorded as having had up to FOUR. The exact pre-image
    -- line is quoted in this file's header, not here, so §POST can grep the live body for it.
    -- Registered as GAP 5 by 0005 and left open; this is that pass.
    --
    -- STEP A — the bay's CAPABILITY set. Byte-for-byte the three arrays from the pre-image.
    -- 0009 does not retune what a bay can do; it only stops claiming the bay did all of it.
    v_bay_caps := CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
                       WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
                       ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END;

    -- STEP B — what the vehicle ACTUALLY had outstanding, from its own visit record.
    -- ORDER IS LOAD-BEARING: this must be read BEFORE ottoq_mark_visit_atoms_done below,
    -- which flips these same atoms to 'done'. Read it after and the answer is always empty.
    -- The visit selector is IDENTICAL to ottoq_mark_visit_atoms_done's own (vehicle +
    -- status open/in_progress + newest created_at), so the wear ledger and the visit ledger
    -- can never disagree about WHICH visit they are discussing. "Outstanding" uses the
    -- depot's own existing definition, already live in STEP 2 of this same function:
    --     COALESCE(status,'pending') NOT IN ('done','cancelled','skipped')
    -- No new vocabulary is invented anywhere in this block.
    SELECT COALESCE(array_agg(DISTINCT a->>'svc'), ARRAY[]::text[])
      INTO v_outstanding
      FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.visit_id = (SELECT n2.visit_id FROM ottoq_visit_needs n2
                          WHERE n2.vehicle_id = v_rec.id
                            AND n2.status IN ('open','in_progress')
                          ORDER BY n2.created_at DESC LIMIT 1)
       AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped');
    v_outstanding := COALESCE(v_outstanding, ARRAY[]::text[]);

    -- STEP C — THE TECHNICIAN FLAG IS REAL WORK TOO, AND IGNORING IT WOULD BE A NEW LIE.
    -- STEP 2 of this function admits a vehicle to the wash/detail lane on
    -- `flagged_issue_type` ALONE, with no atom required. Atoms-only credit would leave that
    -- car's body soil never reset -- and post-0008 ONLY an exterior_wash may reset it -- so
    -- the depot would wash it, still grade it dirty, and wash it again, forever. ONE mapping,
    -- and only where the flag NAMES the work: 'wash_due' -> exterior_wash.
    -- 'minor_cosmetic' is deliberately NOT mapped (GAP 1): a detail does not repair cosmetic
    -- damage, and inventing that equivalence would be the same disease this file removes.
    v_flag_svcs := CASE WHEN v_rec.config->>'flagged_issue_type' = 'wash_due'
                        THEN ARRAY['exterior_wash'] ELSE ARRAY[]::text[] END;

    -- STEP D — THE CREDIT SET: what this bay CAN do  ∩  what this vehicle ACTUALLY had.
    -- If a vehicle genuinely had all four due it still gets all four: the bug being fixed is
    -- unconditionality, not breadth.
    v_credit := ARRAY(SELECT t.svc FROM unnest(v_bay_caps) AS t(svc)
                       WHERE t.svc = ANY(v_outstanding || v_flag_svcs));

    PERFORM ottoq_mark_visit_atoms_done(v_rec.id,
      CASE WHEN v_rec.current_state = 'in_wash_bay' THEN ARRAY['exterior_wash','sensor_clean']
           WHEN v_rec.current_state = 'in_detail_bay' THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
           ELSE ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair'] END, v_end_ts);
    -- wear truth follows completion (mark_serviced was dead: soil/PM/calibration never reset)
    -- 0009: the fixed array is gone. One call per service the vehicle REALLY had -- the same
    -- one-real-atom-per-call shape 0005 §3 uses on the non-bay path, and the same shape the
    -- real-telemetry seam public.ottoq_ingest_service_complete uses (FOREACH over the codes
    -- the OEM actually reported). An empty credit set yields zero rows from unnest, so the
    -- PERFORM makes NO call at all: total, never an error, never able to abort decide_tick.
    -- ottoq_mark_visit_atoms_done above is left BYTE-FOR-BYTE UNCHANGED on purpose. It is
    -- already correctly intersected -- it only touches atoms that exist on the visit -- so it
    -- was never part of this defect, and narrowing it would be scope creep.
    PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
      FROM unnest(v_credit) AS s;
    v_credited    := v_credited + COALESCE(array_length(v_credit, 1), 0);
    v_suppressed  := v_suppressed + COALESCE(array_length(v_bay_caps, 1), 0)
                                  - COALESCE(array_length(v_credit, 1), 0);
    IF COALESCE(array_length(v_credit, 1), 0) = 0 THEN v_credit_none := v_credit_none + 1; END IF;
    PERFORM ottoq_record_event(p_actor_type := 'av_vehicle', p_actor_id := v_rec.id::text, p_event_type := 'twin.service_completed',
      p_entity_type := 'vehicle', p_entity_id := v_rec.id, p_payload := jsonb_build_object('from', v_rec.current_state, 'self_healed', (v_rec.config->>'service_ends_at') IS NULL,
        -- 0009 RUNTIME PROOF, carried on an event that was already being written, so the
        -- write-rate budget (~852-960 B/event) is not disturbed by a new event type.
        'bay_capable', to_jsonb(v_bay_caps), 'credited', to_jsonb(v_credit),
        'suppressed_n', COALESCE(array_length(v_bay_caps,1),0) - COALESCE(array_length(v_credit,1),0)),
      p_severity := 'debug', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END LOOP;

  -- 0009: ONE summary event per CALL, and only when a bay exit credited NOTHING -- i.e. a
  -- vehicle sat in a bay yet no outstanding work and no naming flag could be found for it.
  -- That is a gap a human should see, not something to paper over with a false credit.
  -- Silent in the normal case, so the event budget is unchanged on the happy path.
  IF v_credit_none > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow',
      p_event_type := 'twin.bay_credit_none', p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('exits_crediting_nothing', v_credit_none,
        'services_credited', v_credited, 'services_suppressed', v_suppressed,
        'note', 'a bay exit found no outstanding work and no naming flag; nothing was credited, which is the honest answer -- investigate why the car was admitted'),
      p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;

  -- ───── STEP 1.5: deploy-pressure fast-track past OPTIONAL wash ─────
  v_hour     := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_fleet    := (SELECT COUNT(*) FROM vehicles WHERE category='autonomous' AND home_depot_id=p_depot_id);
  v_deployed := (SELECT COUNT(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id=p_sim_run_id AND status IN ('active','returning'));
  v_target   := FLOOR(v_fleet * ottoq_deploy_target_fraction(v_hour, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.55)));
  v_pressure := v_deployed < v_target;
  IF v_pressure THEN
    FOR v_rec IN
      SELECT v.id FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND v.current_state = 'charge_complete_holding' AND v.current_soc >= v_floor
         AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
             WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
               AND (a->>'must_do')::boolean = TRUE AND a->>'svc' NOT IN ('charge','readiness_check')
               AND COALESCE(a->>'status','open') <> 'done')
    LOOP
      UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
             config = jsonb_set(config, '{svc_step}', to_jsonb('need_deploy'::text)) WHERE id = v_rec.id;
      v_fasttracked := v_fasttracked + 1;
    END LOOP;
    IF v_fasttracked > 0 THEN
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.deploy_pressure_fasttrack',
        p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('fasttracked', v_fasttracked, 'deployed', v_deployed, 'target', v_target, 'hour_cst', v_hour),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- ───── STEP 2: admit waiting vehicles into lanes (capacity-gated, ordered) ─────
  SELECT COUNT(*) INTO v_in_wash FROM vehicles WHERE home_depot_id = p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay');
  v_admitted := 0;
  FOR v_rec IN
    -- M1_need_gated_wash: admit ONLY vehicles that actually have wash/detail
    -- work outstanding. Previously any holding vehicle was admitted to fill capacity.
    -- BOOKING-AWARE (2026-08-02), same reasoning as the service cursor below: the wash
    -- lane also ignored the forward calendar and picked a bay by OFFSET n % 3. The need
    -- gate and the ordering expression are preserved EXACTLY; a booking-holder key is
    -- prepended, and the vehicle's own reserved bay is surfaced for the travel leg.
    SELECT q.id, q.config, q.booked_stall FROM (
      SELECT v.id, v.config,
             (SELECT b2.stall_id
                FROM ottoq_stall_bookings b2 JOIN stalls sb ON sb.id = b2.stall_id
               WHERE b2.sim_run_id = p_sim_run_id AND b2.vehicle_id = v.id
                 AND b2.state = 'held' AND b2.purpose IN ('wash','detail')
                 AND sb.depot_id = p_depot_id AND sb.stall_type = 'wash_bay'::stall_type
                 AND sb.status NOT IN ('maintenance','closed')
                 AND lower(b2.during) <= p_sim_clock_now AND upper(b2.during) > p_sim_clock_now
               ORDER BY lower(b2.during) LIMIT 1) AS booked_stall,
             CASE v_order WHEN 'soc_optimized' THEN v.current_soc WHEN 'priority_weighted' THEN -COALESCE((v.config->>'seed_idx')::numeric, 0) ELSE EXTRACT(EPOCH FROM v.last_state_change) END AS ord
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'charge_complete_holding'
         AND (EXISTS (SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                       WHERE n.vehicle_id = v.id AND n.status IN ('open','in_progress')
                         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
              OR v.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
    ) q
     ORDER BY (q.booked_stall IS NULL), q.ord
     -- wash_supervisor_pool: the 8-10 min exterior wash needs a supervisor as well
     -- as a free lane (founder spec: "a couple of wash bay supervisors").
     LIMIT GREATEST(0, LEAST(v_wash_cap, ottoq_depot_staffing_count(p_depot_id,'wash_supervisor')) - v_in_wash)
  LOOP
    -- T3 RENDER CONTRACT: the drive to the wash building. Render-only; picks a
    -- door for the leg, claims nothing. Origin left NULL on purpose (it is NULL on
    -- every path into charge_complete_holding) so the emitter resolves it from leg history.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        COALESCE(v_rec.booked_stall,
        (SELECT s.id FROM stalls s WHERE s.depot_id = p_depot_id
          AND s.stall_type = 'wash_bay'::stall_type
          ORDER BY (s.status IN ('maintenance','closed')), (s.current_vehicle_id IS NOT NULL), (EXISTS (SELECT 1 FROM ottoq_stall_bookings b3 WHERE b3.stall_id = s.id AND b3.sim_run_id = p_sim_run_id AND b3.state IN ('held','active','done') AND b3.during && tstzrange(p_sim_clock_now, p_sim_clock_now + make_interval(mins => GREATEST(v_wash_dur, v_detail_dur)::int), '[)'))), s.stall_code LIMIT 1)),
        p_sim_clock_now, 'taxi_to_wash', 'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (wash): %', SQLERRM;
    END;
    -- 0048 REORDER: PHYSICAL TRUTH BEFORE THE STATE FLIP. This vehicle-state
    -- UPDATE used to run BEFORE the stall handoff below. That made
    -- trg_reassignment_guard (BEFORE UPDATE ON stalls) see the vehicle already
    -- in a protected in-bay state while it was still standing on its OLD stall,
    -- so the guard vetoed the release, silently restored the old pointer, and
    -- the very next place-statement violated idx_stalls_one_vehicle_per_stall
    -- and killed the whole tick (measured: cert arm 44252690, vehicle a6e9c009,
    -- charge_complete_holding on a wash bay, admitted to its booked service
    -- bay). Handoff first -- while the state is still a holding state the guard
    -- does not protect -- then the state write. Both statements byte-identical
    -- to the pre-image; only their order changed.

    IF v_rec.booked_stall IS NOT NULL
       AND NOT twin.ottoq_arm_refuse_move(v_rec.id, 'service_flow.bay_admit',
                                          v_rec.booked_stall, p_sim_run_id, p_sim_clock_now) THEN
      -- CLAIMABILITY IS CHECKED BEFORE THE RELEASE, not after. The original guard
      -- below defends the TARGET bay from a second vehicle, which is the opposite
      -- direction from idx_stalls_one_vehicle_per_stall -- that index is
      -- UNIQUE(current_vehicle_id), i.e. one STALL per VEHICLE. Both directions now
      -- hold: the bay cannot be stolen, and the car cannot be in two places.
      -- Hoisted ahead of the release so a bay we cannot claim never leaves the car
      -- standing in no stall at all.
      IF EXISTS (SELECT 1 FROM stalls s
                  WHERE s.id = v_rec.booked_stall
                    AND (s.current_vehicle_id IS NULL OR s.current_vehicle_id = v_rec.id)) THEN
        UPDATE stalls SET current_vehicle_id = NULL,
               status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
         WHERE current_vehicle_id = v_rec.id AND id <> v_rec.booked_stall;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_rec.booked_stall
           AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
        IF FOUND THEN
          UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
        END IF;
      END IF;
    END IF;
    UPDATE vehicles
       SET current_state = (CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'in_detail_bay' ELSE 'in_wash_bay' END)::vehicle_state,
           last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('washing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now +
               ((CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due'))
                      THEN v_detail_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'detail_time', v_rec.id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)
                      ELSE v_wash_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'wash_time', v_rec.id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0) END) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
    PERFORM ottoq_itin_leg_open(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now,
      CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN 'detail' ELSE 'wash' END,
      NULL, (SELECT (config->>'service_ends_at')::timestamptz FROM vehicles WHERE id = v_rec.id),
      jsonb_build_object('kind', 'distribution', 'corpus', 'service_ops', 'base_min', CASE WHEN (ottoq_visit_wants_detail(v_rec.id) OR v_rec.config->>'flagged_issue_type' IN ('minor_cosmetic','wash_due')) THEN v_detail_dur ELSE v_wash_dur END),
      'service_flow');
    v_admitted := v_admitted + 1;
  END LOOP;

  SELECT COUNT(*) INTO v_in_svc FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'in_service_bay';
  -- BOOKING-AWARE ADMISSION (2026-08-02). This cursor was blind to the forward calendar:
  -- it ordered purely by last_state_change and sent the car to an ARBITRARY bay
  -- (OFFSET n % 2), so a vehicle holding a live reservation got no priority and was often
  -- not even routed to the bay it had been promised. Reservations then rotted to
  -- no_show_grace_elapsed (37.3% of bay bookings). It now surfaces the vehicle's own open
  -- booking and admits booking-holders FIRST. Capacity is still staff-gated byte-for-byte:
  -- this changes WHO gets the slot and WHICH bay, never HOW MANY.
  FOR v_rec IN
    SELECT * FROM (
      SELECT v.id,
             (SELECT b2.stall_id
                FROM ottoq_stall_bookings b2 JOIN stalls sb ON sb.id = b2.stall_id
               WHERE b2.sim_run_id = p_sim_run_id AND b2.vehicle_id = v.id
                 AND b2.state = 'held' AND b2.purpose = 'service'
                 AND sb.depot_id = p_depot_id AND sb.stall_type = 'service_bay'::stall_type
                 AND sb.status NOT IN ('maintenance','closed')
                 AND lower(b2.during) <= p_sim_clock_now AND upper(b2.during) > p_sim_clock_now
               ORDER BY lower(b2.during) LIMIT 1) AS booked_stall,
             v.last_state_change AS lsc
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
         AND v.config->>'svc_step' = 'need_service'
    ) q
     ORDER BY (q.booked_stall IS NULL), q.lsc LIMIT GREATEST(0, v_svc_cap - v_in_svc)
  LOOP
    -- T3 RENDER CONTRACT: the drive to the service bays (OFFICE-01 complex, far west).
    -- Render-only; claims no bay. Capacity remains staff-gated exactly as before.
    BEGIN
      PERFORM ottoq_itin_travel_leg(p_sim_run_id, p_depot_id, v_rec.id, NULL,
        COALESCE(v_rec.booked_stall,
        (SELECT s.id FROM stalls s WHERE s.depot_id = p_depot_id
          AND s.stall_type = 'service_bay'::stall_type
          ORDER BY (s.status IN ('maintenance','closed')), (s.current_vehicle_id IS NOT NULL), (EXISTS (SELECT 1 FROM ottoq_stall_bookings b3 WHERE b3.stall_id = s.id AND b3.sim_run_id = p_sim_run_id AND b3.state IN ('held','active','done') AND b3.during && tstzrange(p_sim_clock_now, p_sim_clock_now + make_interval(mins => v_svc_dur::int), '[)'))), s.stall_code LIMIT 1)),
        p_sim_clock_now, 'taxi_to_service', 'twin_service_flow');
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'travel leg (service): %', SQLERRM;
    END;
    -- 0048 REORDER: PHYSICAL TRUTH BEFORE THE STATE FLIP. This vehicle-state
    -- UPDATE used to run BEFORE the stall handoff below. That made
    -- trg_reassignment_guard (BEFORE UPDATE ON stalls) see the vehicle already
    -- in a protected in-bay state while it was still standing on its OLD stall,
    -- so the guard vetoed the release, silently restored the old pointer, and
    -- the very next place-statement violated idx_stalls_one_vehicle_per_stall
    -- and killed the whole tick (measured: cert arm 44252690, vehicle a6e9c009,
    -- charge_complete_holding on a wash bay, admitted to its booked service
    -- bay). Handoff first -- while the state is still a holding state the guard
    -- does not protect -- then the state write. Both statements byte-identical
    -- to the pre-image; only their order changed.

    -- HONOUR THE RESERVATION PHYSICALLY. Claiming the booked bay is what lets
    -- ottoq.ottoq_activate_present_bookings flip the row held -> active next tick -- the
    -- RUNTIME proof the reservation was kept rather than silently expired. Guarded so it
    -- can never steal a bay another vehicle is standing in, so it cannot double-book.
    IF v_rec.booked_stall IS NOT NULL
       AND NOT twin.ottoq_arm_refuse_move(v_rec.id, 'service_flow.bay_admit',
                                          v_rec.booked_stall, p_sim_run_id, p_sim_clock_now) THEN
      -- CLAIMABILITY IS CHECKED BEFORE THE RELEASE, not after. The original guard
      -- below defends the TARGET bay from a second vehicle, which is the opposite
      -- direction from idx_stalls_one_vehicle_per_stall -- that index is
      -- UNIQUE(current_vehicle_id), i.e. one STALL per VEHICLE. Both directions now
      -- hold: the bay cannot be stolen, and the car cannot be in two places.
      -- Hoisted ahead of the release so a bay we cannot claim never leaves the car
      -- standing in no stall at all.
      IF EXISTS (SELECT 1 FROM stalls s
                  WHERE s.id = v_rec.booked_stall
                    AND (s.current_vehicle_id IS NULL OR s.current_vehicle_id = v_rec.id)) THEN
        UPDATE stalls SET current_vehicle_id = NULL,
               status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
         WHERE current_vehicle_id = v_rec.id AND id <> v_rec.booked_stall;
        UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
         WHERE id = v_rec.booked_stall
           AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id);
        IF FOUND THEN
          UPDATE vehicles SET current_stall_id = v_rec.booked_stall WHERE id = v_rec.id;
        END IF;
      END IF;
    END IF;
    UPDATE vehicles SET current_state = 'in_service_bay'::vehicle_state, last_state_change = p_sim_clock_now,
           config = jsonb_set(jsonb_set(config, '{svc_step}', to_jsonb('servicing'::text)), '{service_ends_at}', to_jsonb((p_sim_clock_now + ((v_svc_dur * COALESCE(ottoq_twin_deal(p_sim_run_id, 'maintenance_time', v_rec.id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), p_sim_clock_now, (p_sim_clock_now::date - DATE '2020-01-01'), 0), 1.0)) || ' minutes')::interval)::text))
     WHERE id = v_rec.id;
    PERFORM ottoq_itin_leg_open(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now, 'service', NULL,
      (SELECT (config->>'service_ends_at')::timestamptz FROM vehicles WHERE id = v_rec.id),
      jsonb_build_object('kind', 'distribution', 'corpus', 'service_ops', 'base_min', v_svc_dur), 'service_flow');
  END LOOP;

  -- ═════ STEP 3: RELEASE TO DEPARTURE — READINESS GATE (2026-08-02) ═════
  -- DOCTRINE (full-service visit): a visit is ATOMIC. 'staged_for_departure' must mean
  -- "this vehicle would be dispatched if asked" — nothing weaker. Before this gate the
  -- transition was UNCONDITIONAL, so vehicles at 28-29% SoC were staged as READY.
  -- That is not merely cosmetic: 'staged_for_departure' is NOT in ottoq_decide_tick's
  -- charging cursor (which reads 'arrived_at_gate' and 'staged_awaiting_service'), so
  -- staging an undercharged car REMOVED IT FROM THE CHARGE QUEUE, while
  -- ottoq_plan_dispatch_tick(deploy_plan) would refuse it anyway (soc >= 80 + no open
  -- must-do work). Dead inventory that could never leave and could never be fixed.
  --
  -- THE GATE IS THE DISPATCHER'S OWN ADMISSION PREDICATE, MOVED ONE STEP EARLIER.
  -- It is therefore never stricter than what the dispatcher accepts, so it cannot
  -- create a new deadlock class:
  --     soc >= ready_soc   AND   no open must-do work left in this run's visit
  -- ready_soc comes from the NEEDS CARD (ottoq_vehicle_needs_card.min_ready_soc_pct),
  -- not a bare SoC literal, so it follows the per-vehicle need profile; it falls back
  -- to the deploy_floor_soc policy when the card has no row for the vehicle — a TOTAL
  -- function: a missing card must never block a vehicle. The card also supplies
  -- must_do_now / fits_window / minutes_to_deploy as EVIDENCE on the hold receipt.
  -- The card is read ONCE per call for the whole candidate set: the view materialises
  -- the entire fleet regardless of its WHERE clause (measured 192 ms for a
  -- single-vehicle probe), so a per-vehicle read would cost seconds per tick.
  --
  -- NOT AN ENERGY GATE. Vehicle-first doctrine is untouched — nothing is held back for
  -- price or grid reasons. This is READINESS only: the vehicle is not finished.
  --
  -- ESCAPE HATCHES — nothing can sit forever:
  --   0. policy deploy_ready_gate_enabled = 0  → gate off, pre-2026-08-02 behaviour.
  --   1. a held vehicle is ROUTED TO THE REMEDY, never parked: svc_step := 'need_charge'
  --      (ottoq_decide_tick's charge cursor consumes staged_awaiting_service on SoC
  --      alone — no atom required) or 'need_service' (STEP 2 above consumes it).
  --      Both consumers verified in live source. The loop closes: charge →
  --      charge_complete_holding → STEP 1.5/STEP 2 → need_deploy → re-gated.
  --   2. deploy_gate_patience_min (default 45 sim-min) → config.flagged_issue +
  --      flagged_issue_type='deploy_gate_stuck' so a technician sees it, counted in a
  --      WARNING summary event.
  --   3. deploy_gate_hard_cap_min (default 240 sim-min — longer than any bounded demo)
  --      → released anyway, stamped config.deploy_gate_override with a CRITICAL audit
  --      event. Loud and countable, never silent.
  -- Event budget: ONE summary event per call (plus one per rare override), not one per
  -- vehicle — event-write amplification is the known tick-cost driver.
  v_gate_on      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_ready_gate_enabled',1),1) > 0;
  v_patience_dep := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_gate_patience_min',45),45);
  v_hardcap      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_gate_hard_cap_min',240),240);
  v_relcap       := GREATEST(1, CEIL(v_deploy_cap * COALESCE(p_tick_minutes, 30) / 30.0))::int;
  v_admitted := 0;

  SELECT COUNT(*) INTO v_ncand FROM vehicles v
   WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
     AND v.config->>'svc_step' = 'need_deploy';

  IF v_ncand > 0 THEN
    FOR v_rec IN
      WITH cand AS (
        SELECT v.id, v.current_soc, v.config, v.last_state_change
          FROM vehicles v
         WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
           AND v.current_state = 'staged_awaiting_service'
           AND v.config->>'svc_step' = 'need_deploy'
      ), card AS (
        SELECT c.vehicle_id, c.min_ready_soc_pct, c.must_do_now, c.fits_window, c.minutes_to_deploy
          FROM ottoq_vehicle_needs_card c
         WHERE v_gate_on
      ), ev AS (
        SELECT cd.id, cd.current_soc, cd.config, cd.last_state_change,
               GREATEST(v_floor, COALESCE(k.min_ready_soc_pct, v_floor)) AS ready_soc,
               COALESCE(k.must_do_now, '{}'::text[])                     AS card_must,
               k.fits_window, k.minutes_to_deploy,
               -- IDENTICAL predicate to ottoq_plan_dispatch_tick(deploy_plan)
               EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = cd.id AND vn.sim_run_id = p_sim_run_id
                          AND vn.status IN ('open','in_progress')
                          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE COALESCE((a->>'must_do')::boolean,false) = true
                                         AND a->>'svc' <> 'readiness_check'
                                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')))
                                                                          AS work_open
          FROM cand cd LEFT JOIN card k ON k.vehicle_id = cd.id
      )
      SELECT ev.*,
             ((NOT v_gate_on) OR (ev.current_soc >= ev.ready_soc AND NOT ev.work_open)) AS ready
        FROM ev
       ORDER BY (CASE WHEN (NOT v_gate_on) OR (ev.current_soc >= ev.ready_soc AND NOT ev.work_open) THEN 0 ELSE 1 END),
                ev.last_state_change, ev.id
    LOOP
      IF v_rec.ready THEN
        -- deploy_cap_per_minute: v_deploy_cap is calibrated as releases per 30-MINUTE
        -- tick; rescale to the real tick length so throughput cannot change with tick size.
        IF v_admitted < v_relcap THEN
          UPDATE vehicles SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock_now,
                 config = jsonb_set(config, '{svc_step}', to_jsonb('ready'::text)) - 'deploy_gate'
           WHERE id = v_rec.id;
          v_admitted := v_admitted + 1;
        END IF;   -- over cap: stays need_deploy, retried next tick (unchanged behaviour)
      ELSE
        DECLARE
          v_since TIMESTAMPTZ; v_reason TEXT; v_missing TEXT[]; v_held_min NUMERIC; v_remedy TEXT;
        BEGIN
          v_since    := COALESCE((v_rec.config #>> '{deploy_gate,held_since}')::timestamptz, p_sim_clock_now);
          v_held_min := GREATEST(0, EXTRACT(EPOCH FROM (p_sim_clock_now - v_since))/60.0);
          v_reason   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'soc_below_ready' ELSE 'must_do_work_open' END;
          v_remedy   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'need_charge'     ELSE 'need_service' END;
          v_missing  := (CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN ARRAY['charge'] ELSE ARRAY[]::text[] END)
                        || COALESCE(v_rec.card_must, ARRAY[]::text[]);

          IF v_held_min >= v_hardcap THEN
            UPDATE vehicles SET current_state = 'staged_for_departure'::vehicle_state, last_state_change = p_sim_clock_now,
                   config = (jsonb_set(config, '{svc_step}', to_jsonb('ready'::text)) - 'deploy_gate')
                          || jsonb_build_object('deploy_gate_override', jsonb_build_object(
                               'at', p_sim_clock_now, 'held_min', round(v_held_min,1), 'reason', v_reason,
                               'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                               'missing', to_jsonb(v_missing), 'hard_cap_min', v_hardcap))
             WHERE id = v_rec.id;
            v_override := v_override + 1;
            PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
              p_event_type := 'twin.deploy_gate_override', p_entity_type := 'vehicle', p_entity_id := v_rec.id,
              p_payload := jsonb_build_object('held_min', round(v_held_min,1), 'hard_cap_min', v_hardcap,
                'reason', v_reason, 'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                'missing', to_jsonb(v_missing),
                'note', 'escape hatch 3: released past the readiness gate so the twin cannot wedge; this is a DEFECT to investigate, not a normal path'),
              p_severity := 'critical', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
          ELSE
            UPDATE vehicles
               SET config = jsonb_set(config, '{svc_step}', to_jsonb(v_remedy))
                          || jsonb_build_object('deploy_gate', jsonb_build_object(
                               'held_since', v_since, 'held_min', round(v_held_min,1),
                               'reason', v_reason, 'remedy', v_remedy,
                               'soc', v_rec.current_soc, 'ready_soc', v_rec.ready_soc,
                               'missing', to_jsonb(v_missing),
                               'card_must_do_now', to_jsonb(COALESCE(v_rec.card_must, ARRAY[]::text[])),
                               'fits_window', v_rec.fits_window,
                               'minutes_to_deploy', v_rec.minutes_to_deploy))
                          || CASE WHEN v_held_min >= v_patience_dep
                                  THEN jsonb_build_object('flagged_issue', true,
                                                          'flagged_issue_type', 'deploy_gate_stuck')
                                  ELSE '{}'::jsonb END
             WHERE id = v_rec.id;   -- last_state_change deliberately UNTOUCHED (queue order + patience metric)
            v_held := v_held + 1;
            IF v_held_min >= v_patience_dep THEN v_esc_gate := v_esc_gate + 1; END IF;
          END IF;
        END;
      END IF;
    END LOOP;

    IF v_held > 0 OR v_override > 0 THEN
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'deploy_ready_gate',
        p_event_type := 'twin.deploy_gate_summary', p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('candidates', v_ncand, 'released', v_admitted,
          'held', v_held, 'escalated', v_esc_gate, 'overridden', v_override,
          'floor', v_floor, 'patience_min', v_patience_dep, 'hard_cap_min', v_hardcap,
          'gate_enabled', v_gate_on),
        p_severity := CASE WHEN v_override > 0 THEN 'critical'
                           WHEN v_esc_gate > 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END IF;
  END IF;

  -- overflow now counts need_charge too: a vehicle held by the readiness gate is still
  -- waiting in staging and must not vanish from the queue telemetry.
  SELECT COUNT(*) INTO v_overflow FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'staged_awaiting_service' AND config->>'svc_step' IN ('need_service','need_deploy','need_charge');
  IF v_overflow > 0 THEN
    DECLARE v_patience NUMERIC := GREATEST(1, 10 + ottoq_apply_profile(p_sim_run_id, 'queue_patience', 0, 0)); v_escalated INT;
    BEGIN
      SELECT COUNT(*) INTO v_escalated FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'staged_awaiting_service'
         AND config->>'svc_step' IN ('need_service','need_deploy','need_charge') AND EXTRACT(EPOCH FROM (p_sim_clock_now - last_state_change))/60.0 > v_patience;
      PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'service_flow', p_event_type := 'twin.staging_overflow',
        p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_payload := jsonb_build_object('overflow', v_overflow, 'escalated', v_escalated, 'patience_min', ROUND(v_patience,1), 'wash_cap', v_wash_cap, 'svc_cap', v_svc_cap, 'deploy_cap', v_deploy_cap, 'gate_held', v_held),
        p_severity := CASE WHEN v_escalated > 0 THEN 'warning' ELSE 'info' END, p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    END;
  END IF;

  out_washing   := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay'));
  out_servicing := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='in_service_bay');
  out_staged    := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='staged_awaiting_service');
  out_ready     := (SELECT COUNT(*) FROM vehicles WHERE home_depot_id=p_depot_id AND current_state='staged_for_departure');
  out_overflow  := v_overflow;
  RETURN NEXT;
END;
$function$

;
