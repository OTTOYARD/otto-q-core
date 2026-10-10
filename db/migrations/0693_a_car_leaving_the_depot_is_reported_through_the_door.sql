-- migration-version: PENDING
-- migration-name:    a_car_leaving_the_depot_is_reported_through_the_door
--
-- 0693  **A car leaving the depot is reported through the v2 door, and the door releases what the depot held for it.**
--        Stage 3 of the twin's sending side (docs/TWIN_SENDING_SIDE.md), step 4 of the twin data contract review.
--        Chase, 2026-10-09: route the twin's sending signals through the door first, full separation later.
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Contract rule 8: "Leaving is the operator's own act, reported as vehicle.departed, and OTTO-Q records what was still
--   open if it left early." Until this file the door keeps com.ottoyard.vehicle.departed in its inbox and does nothing
--   with it, so a real operator's car that left would keep its itinerary, its visit and its stall reservations at the
--   depot. The twin never sends one: twin.ottoq_sim_dispatch_vehicle writes the car away and then releases OTTO-Q's
--   holds itself (ottoq.ottoq_release_visit_artifacts: the legs of its active itinerary skipped, the itinerary
--   completed, its open visit superseded, its stall reservations released), inside OTTO-Q's transaction.
--
--   Read 2026-10-10, comment-stripped: the dispatcher's only caller is twin.ottoq_sim_auto_dispatch_tick, which the
--   orchestrator (ottoq_sim_decide_and_dispatch, after the policy's decide tick) and ottoq_greedy_tick call. It asks
--   OTTO-Q's planner (ottoq_plan_dispatch_tick 'deploy_plan') which finished cars to release toward the scenario's
--   deploy target, and dispatches those. ottoq_decide_tick names the dispatcher only in a comment (its decision row is
--   the deploy signal the planner ranks by); docs/TWIN_SENDING_SIDE.md said it called it and is corrected with this
--   file. The release function's only caller is the dispatcher. No departure has ever reached the door (the inbox,
--   2026-10-10), and no production or shadow key carries the arrival stream, so the door's new effect changes no
--   stored outcome.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The door's com.ottoyard.vehicle.departed, for a production, shadow or twin key (a replay key's departure is
--       history and is still only kept): checks departed_at and the reason (the contract's four); reads whether the
--       car was finished with the dispatchers' own departure test (public.ottoq_departure_clear, readiness included)
--       and, when it was not, records vehicle.departed_with_open_work in the signed event stream with the open
--       services, the charge against its target, an unrepaired fault and an owner hold; marks the car away (deployed,
--       or out_of_service when towed; its stall cleared) only when OTTO-Q's own record still has it at the depot; and
--       makes the release the dispatcher makes. A car the arm still holds cannot be marked away (the interlock refuses
--       the write), so the door refuses that event with the interlock's message and nothing moves.
--   (b) The event type vehicle.departed_with_open_work (audit, warning).
--   (c) The flag twin_operator_departures (0 = the dispatcher releases, as today; 1 = the car's operator reports the
--       departure through the door, which releases), a person's dial, per run.
--   (d) twin.ottoq_twin_operator_depart(run, clock, car): sends com.ottoyard.vehicle.departed (reason dispatched, the
--       car's charge) under the car's operator's key, in the operator's per-car sequence, on the run's clock; false
--       for a car no operator speaks for. A departure the door does not apply is a warning, not a fallback: a real
--       operator's refused report would leave the holds held too.
--   (e) twin.ottoq_sim_dispatch_vehicle calls it in place of its own release when the run's flag is on, and keeps the
--       direct release for a car no operator speaks for, or if the call itself fails.
--   (f) The research wing's pair, registered as a dial experiment (as 0656 and 0692).
--
--   The twin's own writes stay the twin's until full separation: the dispatch row, the car's state, stall and
--   manifest, the taxi leg and the dispatch event. The door's state write is a no-op for a twin car, whose shared row
--   the dispatcher has already written. So with the flag on, OTTO-Q's holds are released by the same function, on the
--   same rows, at the same point of the same tick, and V1 shows it on one dispatch.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   The flag is set nowhere, and at 0 the dispatcher takes its old body (V1). The door's new effect fires only on a
--   departure, which nothing sends today (§1). Setting the flag is a certified change after the pair.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the two definitions in ottoq_schema_snapshots WHERE label = '0693_pre'; mark the experiment created_by
--   '0693' abandoned. The function, the flag's catalog row and the event type stay (dropping needs a person at the
--   connector's prompt), and nothing calls the function once the definitions are restored.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0693 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0692_the_twins_operators_send_telemetry_and_faults_through_the_door') THEN
    RAISE EXCEPTION '0693 P1: 0692 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> 'ed2895cacce4fe27325f7648ed2f208a' THEN
    RAISE EXCEPTION '0693 P1: the door''s apply is not 0691''s, the definition this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)'::regprocedure))
       <> '184c118f2cf5f4ffbf30808b7199e5f3' THEN
    RAISE EXCEPTION '0693 P1: twin.ottoq_sim_dispatch_vehicle is not the definition this file patches';
  END IF;
  -- the release both paths make, unchanged: what V1's equivalence rests on
  IF md5(pg_get_functiondef('ottoq.ottoq_release_visit_artifacts(uuid,uuid,timestamptz,text)'::regprocedure))
       <> 'a4e4174d0ecec0200614d153f9d96088' THEN
    RAISE EXCEPTION '0693 P1: ottoq.ottoq_release_visit_artifacts is not the release this file was written against';
  END IF;
  IF to_regprocedure('twin.ottoq_twin_operator_depart(uuid,timestamptz,uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_operator_departures')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_departures')
     OR EXISTS (SELECT 1 FROM public.ottoq_dial_experiments WHERE param_key = 'twin_operator_departures')
     OR EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog WHERE event_type = 'vehicle.departed_with_open_work') THEN
    RAISE EXCEPTION '0693 P1: an object or a key this file creates exists already';
  END IF;
  -- the door has never applied a departure, so its new effect changes no stored outcome (§3)
  IF EXISTS (SELECT 1 FROM public.ottoq_v2_inbox WHERE ce_type = 'com.ottoyard.vehicle.departed') THEN
    RAISE EXCEPTION '0693 P1: the door has taken a departure before; this file was written when none had arrived';
  END IF;
  IF (SELECT count(*) FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
       WHERE k.is_active AND k.data_source = 'twin' AND 'arrival' = ANY (k.streams)) < 2 THEN
    RAISE EXCEPTION '0693 P1: the twin''s two operators do not both hold active twin keys with the arrival stream';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0693 P1: a run is live; apply between runs';
  END IF;
END $premises$;

-- ── snapshots ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0693_pre', 'function', x.s, x.n, x.d, md5(x.d)
  FROM (VALUES
          ('ottoq', 'ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)',
           pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure)),
          ('twin', 'ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)',
           pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)'::regprocedure))
       ) AS x(s, n, d);

-- ── (b) the record of a car that left with work open ──
INSERT INTO public.ottoq_event_types_catalog (event_type, category, description, emitter, default_severity, introduced_in)
VALUES ('vehicle.departed_with_open_work', 'audit',
        'An operator reported a car gone (com.ottoyard.vehicle.departed) while OTTO-Q still had work open on it: a '
        'service open or in progress, its charge short of its target, an unrepaired fault, or an owner hold. Contract '
        'rule 8: leaving is the operator''s own act, and OTTO-Q records what was still open.',
        'ottoq.ottoq_v2_apply (0693)', 'warning', '0693');

-- ── (c) the flag ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('twin_operator_departures',
        '0693: who reports a twin car leaving the depot. 0 (unset, as before) = the twin''s dispatcher releases what '
        'the depot held for the car itself; 1 = the car''s operator (sim-a, sim-b) sends com.ottoyard.vehicle.departed '
        'through the v2 door, and the door makes the release. A person''s dial, never the agent''s; set after the '
        'research wing''s pair, as a certified change.',
        0, 0, 1,
        'twin.ottoq_sim_dispatch_vehicle, twin.ottoq_twin_operator_depart (0693)',
        false);

-- ── (a) the door's departure ──
DO $p_apply$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure);
  a text[] := ARRAY[
$a01$  v_exc uuid;
$a01$,
$a02$  WHEN 'com.ottoyard.vehicle.departed' THEN
    RETURN jsonb_build_object('effect', 'kept_in_inbox_only',
      'why', 'the depot''s release of what it held for the car is wired when the twin sends departures (step 4)');
$a02$];
  b text[] := ARRAY[
$b01$  v_exc uuid;
  -- departed (0693)
  v_dep_at timestamptz; v_dep_reason text; v_dep_clear boolean; v_dep_open jsonb; v_dep_event uuid; v_dep_release jsonb;
$b01$,
$b02$  WHEN 'com.ottoyard.vehicle.departed' THEN
    -- 0693 (contract rule 8): leaving is the operator's own act. OTTO-Q records what was still open if the car left
    -- early, marks it away when its own record still has it at the depot, and releases what it held for it.
    IF k.data_source NOT IN ('production', 'shadow', 'twin') THEN
      RETURN jsonb_build_object('effect', 'kept_in_inbox_only', 'why', 'a ' || k.data_source || ' key''s departure is history');
    END IF;
    v_dep_at := ottoq.ottoq_v2_tstz(d ->> 'departed_at');
    IF v_dep_at IS NULL THEN
      RAISE EXCEPTION 'departed_at is not an RFC 3339 time' USING ERRCODE = 'OQ001';
    END IF;
    v_dep_reason := d ->> 'reason';
    IF v_dep_reason IS NULL OR v_dep_reason NOT IN ('dispatched', 'owner_recall', 'towed', 'other') THEN
      RAISE EXCEPTION 'departed_reason' USING ERRCODE = 'OQ001';
    END IF;
    -- what was still open, read as the dispatchers' departure door reads it (0543, 0544), before the release below
    -- supersedes the visit
    v_dep_clear := COALESCE(public.ottoq_departure_clear(p_vehicle, p_engine_run, v_dep_at, true), false);
    IF NOT v_dep_clear THEN
      SELECT COALESCE(jsonb_agg(DISTINCT a ->> 'svc'), '[]'::jsonb) INTO v_dep_open
        FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
       WHERE vn.vehicle_id = p_vehicle AND vn.sim_run_id IS NOT DISTINCT FROM p_engine_run
         AND vn.status IN ('open', 'in_progress') AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled');
      v_dep_event := public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'v2_door', p_event_type := 'vehicle.departed_with_open_work',
        p_entity_type := 'vehicle', p_entity_id := p_vehicle, p_fleet_operator_id := v_veh.fleet_operator_id,
        p_depot_id := k.depot_id,
        p_payload := jsonb_strip_nulls(jsonb_build_object(
          'operator', k.source_name, 'ce_id', p_ev ->> 'id', 'departed_at', v_dep_at, 'reason', v_dep_reason,
          'open_services', v_dep_open, 'soc', v_veh.current_soc, 'soc_reported', d -> 'soc_pct',
          'target_soc', public.ottoq_effective_target_soc_at(p_vehicle, v_dep_at),
          'fault_open', public.ottoq_vehicle_fault_open(v_veh.config),
          'owner_hold', public.ottoq_owner_departure_blocked(p_vehicle, p_engine_run, v_dep_at))),
        p_severity := 'warning', p_ingest_source := 'v2:' || k.source_name, p_data_source := k.data_source,
        p_sim_run_id := CASE WHEN v_run_scoped THEN p_engine_run END);
    END IF;
    -- the car is away, in OTTO-Q's own record of it, when that record still has it at the depot (a twin car's shared
    -- row was written by the twin's dispatcher already, until full separation)
    UPDATE public.vehicles
       SET current_state = CASE v_dep_reason WHEN 'towed' THEN 'out_of_service' ELSE 'deployed' END::vehicle_state,
           current_stall_id = NULL, last_state_change = v_dep_at
     WHERE id = p_vehicle
       AND (current_stall_id IS NOT NULL
            OR current_state::text NOT IN ('deployed', 'en_route_to_depot', 'tow_requested', 'out_of_service', 'offline'));
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    -- what the depot held for the car: its itinerary, its visit and its stall reservations (AP-1b / B5)
    v_dep_release := ottoq.ottoq_release_visit_artifacts(p_vehicle, p_engine_run, v_dep_at, 'departed_' || v_dep_reason);
    RETURN jsonb_strip_nulls(jsonb_build_object(
      'effect', 'released', 'departed_at', v_dep_at, 'reason', v_dep_reason, 'marked_away', v_rows > 0,
      'left_with_open_work', NOT v_dep_clear, 'open_services', v_dep_open, 'open_event', v_dep_event,
      'release', v_dep_release,
      'kept_in_inbox_only', CASE WHEN d ? 'soc_pct' THEN jsonb_build_array('soc_pct') END));
$b02$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'ed2895cacce4fe27325f7648ed2f208a' THEN
    RAISE EXCEPTION '0693: the door''s apply is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0693: anchor % of the door''s apply occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'd06c41eb8ffd9b600f8246ccbaf5a04d' THEN
    RAISE EXCEPTION '0693: the door''s apply, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> 'd06c41eb8ffd9b600f8246ccbaf5a04d' THEN
    RAISE EXCEPTION '0693: the door''s apply did not read back as written';
  END IF;
END $p_apply$;

-- ── (d) the operator's report ──
CREATE FUNCTION twin.ottoq_twin_operator_depart(p_run uuid, p_clock timestamptz, p_vehicle uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = twin, ottoq, public, extensions, pg_temp AS $fn$
DECLARE
  v_veh public.vehicles%ROWTYPE; v_depot uuid; op record; v_seq bigint; v_ts text; v_take jsonb;
  c_dep constant text := 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.departed.json';
BEGIN
  /* 0693. A twin car leaving the depot, reported by its operator through the v2 door (docs/TWIN_SENDING_SIDE.md,
     stage 3). The door's com.ottoyard.vehicle.departed releases what the depot held for the car. */
  SELECT * INTO v_veh FROM public.vehicles WHERE id = p_vehicle;
  SELECT depot_id INTO v_depot FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  SELECT o.source_name, k.key_hash INTO op
    FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
   WHERE o.depot_id = v_depot AND k.is_active AND k.data_source = 'twin' AND 'arrival' = ANY (k.streams)
     AND v_veh.fleet_operator_id = ANY (k.fleet_operator_ids)
   ORDER BY o.source_name LIMIT 1;
  IF op.source_name IS NULL THEN
    RETURN false;   -- a car no operator speaks for: the dispatcher releases it itself
  END IF;
  INSERT INTO twin.ottoq_twin_operator_sequences (sim_run_id, source_name, vehicle_ref, last_seq)
  VALUES (p_run, op.source_name, v_veh.display_name, 1)
  ON CONFLICT (sim_run_id, source_name, vehicle_ref) DO UPDATE SET last_seq = twin.ottoq_twin_operator_sequences.last_seq + 1
  RETURNING last_seq INTO v_seq;
  v_ts := ottoq.ottoq_v2_rfc3339(p_clock);
  PERFORM set_config('ottoq.v2_twin_run', p_run::text, true);
  v_take := public.ottoq_v2_take_events(op.key_hash, jsonb_build_array(jsonb_build_object(
    'specversion', '1.0', 'id', 'dep-' || lpad(v_seq::text, 20, '0'),
    'source', 'urn:ottoq:src:' || op.source_name || ':' || v_veh.display_name, 'subject', v_veh.display_name,
    'type', 'com.ottoyard.vehicle.departed', 'time', v_ts, 'datacontenttype', 'application/json',
    'dataschema', c_dep, 'sequence', lpad(v_seq::text, 20, '0'),
    'data', jsonb_strip_nulls(jsonb_build_object('departed_at', v_ts, 'reason', 'dispatched',
                                                 'soc_pct', v_veh.current_soc)))), false);
  PERFORM set_config('ottoq.v2_twin_run', '', true);
  IF NOT COALESCE((v_take ->> 'ok')::boolean, false) OR COALESCE((v_take ->> 'applied')::int, 0) <> 1 THEN
    RAISE WARNING 'twin operator %: the door did not apply the departure of % at %: %', op.source_name,
      v_veh.display_name, p_clock, v_take;
  END IF;
  RETURN true;
END $fn$;
COMMENT ON FUNCTION twin.ottoq_twin_operator_depart(uuid,timestamptz,uuid) IS
  '0693: a twin car leaving the depot, reported by its operator through the v2 door as com.ottoyard.vehicle.departed '
  '(reason dispatched); the door releases what the depot held for it. False when no operator speaks for the car.';
REVOKE ALL ON FUNCTION twin.ottoq_twin_operator_depart(uuid,timestamptz,uuid) FROM PUBLIC, anon, authenticated;

-- ── (e) the dispatcher reports instead of releasing when the run's flag is on ──
DO $p_dispatch$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a01$  v_seed            BIGINT;
$a01$,
$a02$  BEGIN PERFORM ottoq_release_visit_artifacts(p_vehicle_id, p_sim_run_id, p_sim_clock_now, 'redeployed');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release visit artifacts: %', SQLERRM; END;
$a02$];
  b text[] := ARRAY[
$b01$  v_seed            BIGINT;
  v_door            BOOLEAN := false;  -- 0693: the car's operator reported the departure through the v2 door
$b01$,
$b02$  -- 0693: at twin_operator_departures 1 the car's operator reports the departure through the v2 door, whose
  -- com.ottoyard.vehicle.departed makes this same release (contract rule 8); a car no operator speaks for, or a
  -- report that could not be sent, keeps the release here
  IF ottoq_policy_get(p_sim_run_id, 'twin_operator_departures', 0) >= 1 THEN
    BEGIN v_door := twin.ottoq_twin_operator_depart(p_sim_run_id, p_sim_clock_now, p_vehicle_id);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'operator departure: %', SQLERRM; v_door := false;
    END;
  END IF;
  IF NOT v_door THEN
  BEGIN PERFORM ottoq_release_visit_artifacts(p_vehicle_id, p_sim_run_id, p_sim_clock_now, 'redeployed');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'release visit artifacts: %', SQLERRM; END;
  END IF;
$b02$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '184c118f2cf5f4ffbf30808b7199e5f3' THEN
    RAISE EXCEPTION '0693: the dispatcher is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0693: anchor % of the dispatcher occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'b55ea62b8533bca8021eb3330ad0af85' THEN
    RAISE EXCEPTION '0693: the dispatcher, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)'::regprocedure))
       <> 'b55ea62b8533bca8021eb3330ad0af85' THEN
    RAISE EXCEPTION '0693: the dispatcher did not read back as written';
  END IF;
END $p_dispatch$;

-- ── (f) the research wing's pair ──
INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES
 ('0693', '11111111-1111-1111-1111-111111111111', 'twin_operator_departures', 0, 1,
  '{}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher',
  6, 12, 0.05, 2, 0.5, 0.2,
  'A measurement, not a tuning (0693 §2). With twin_operator_departures on, each car''s operator reports its departure '
  'through the v2 door, and the door releases what the depot held for the car (its itinerary, its visit and its stall '
  'reservations) where the dispatcher released it itself. It is the same release, on the same rows, at the same point '
  'of the tick, so the arms should not differ; the pair shows the treatment runs a whole day with every departure '
  'applied by the door and none recorded as leaving with work open. The flag is set by a person as a certified change; '
  'no verdict here is a recommendation. Nothing changes a charge target or a service (rule 9). Arms at 6 sim-minutes a '
  'tick from 8:00 AM CT for 90 ticks, the shipped defaults in both.',
  'active', 6, NULL);

-- ── V1a: one finished car dispatched with the flag unset and at 1, each in a block that rolls back ──
CREATE TEMP TABLE p0693 (phase text PRIMARY KEY, r jsonb) ON COMMIT DROP;

-- what the depot holds for a car, and what a release has done to it
CREATE FUNCTION pg_temp.p0693_holds(p_veh uuid) RETURNS jsonb LANGUAGE sql AS $fn$
  SELECT jsonb_build_object(
    'legs_open', (SELECT count(*) FROM public.ottoq_itinerary_legs l
                    JOIN public.ottoq_vehicle_itineraries i ON i.itinerary_id = l.itinerary_id
                   WHERE i.vehicle_id = p_veh AND i.status = 'active' AND l.status IN ('planned', 'active')),
    'legs_skipped', (SELECT count(*) FROM public.ottoq_itinerary_legs l
                       JOIN public.ottoq_vehicle_itineraries i ON i.itinerary_id = l.itinerary_id
                      WHERE i.vehicle_id = p_veh AND l.status = 'skipped'),
    'itineraries_active', (SELECT count(*) FROM public.ottoq_vehicle_itineraries WHERE vehicle_id = p_veh AND status = 'active'),
    'needs_open', (SELECT count(*) FROM public.ottoq_visit_needs
                    WHERE vehicle_id = p_veh AND status IN ('open', 'in_progress', 'carried_over')),
    'needs_superseded', (SELECT count(*) FROM public.ottoq_visit_needs WHERE vehicle_id = p_veh AND status = 'superseded'),
    'reservations', (SELECT count(*) FROM public.stalls WHERE reserved_by = p_veh))
$fn$;

CREATE FUNCTION pg_temp.p0693_dispatch(p_phase text, p_flag numeric) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_run uuid; v_clock timestamptz; v_veh uuid; v_ref text; v_stage uuid; v_hold uuid; v_itin uuid; v_disp uuid;
  v_before jsonb; v_r jsonb; v_msg text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  -- a car sim-a speaks for, with nothing on that run that keeps it at the depot
  SELECT v.id, v.display_name INTO v_veh, v_ref
    FROM public.vehicles v
    JOIN public.ottow_api_keys k ON v.fleet_operator_id = ANY (k.fleet_operator_ids) AND k.is_active
    JOIN twin.ottoq_twin_operators o ON o.key_id = k.id AND o.source_name = 'sim-a'
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
     AND NOT public.ottoq_vehicle_fault_open(v.config)
     AND NOT public.ottoq_rider_flag_due(v.id, v_run, v_clock)
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s
                      WHERE s.vehicle_id = v.id AND s.sim_run_id = v_run AND s.status = 'active')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                      WHERE vn.vehicle_id = v.id AND vn.sim_run_id = v_run AND vn.status IN ('open', 'in_progress')
                        AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled'))
   ORDER BY v.display_name LIMIT 1;
  -- two free staging stalls: one the car stands on, one it holds a reservation on
  SELECT s.id INTO v_stage FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'staging'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
   ORDER BY s.stall_code, s.id LIMIT 1;
  SELECT s.id INTO v_hold FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'staging' AND s.id <> v_stage
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
   ORDER BY s.stall_code, s.id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL OR v_stage IS NULL OR v_hold IS NULL THEN
    RAISE EXCEPTION '0693 V1: no stopped twin run, no free sim-a car or no two free staging stalls to probe';
  END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    IF p_flag IS NOT NULL THEN
      INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
      VALUES ('run', v_run, 'twin_operator_departures', p_flag, '0693_probe', now());
    END IF;
    -- the car finished and staged to leave, holding what a visit holds: an itinerary with a planned leg, its visit
    -- (every service done) and a reservation on a second stall
    UPDATE public.vehicles
       SET current_state = 'staged_for_departure', current_stall_id = v_stage, current_soc = 100,
           robotic_tether_until = NULL, last_state_change = v_clock
     WHERE id = v_veh;
    INSERT INTO public.ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, status, sim_created_at)
    VALUES (v_run, '11111111-1111-1111-1111-111111111111', v_veh, 'active', v_clock)
    RETURNING itinerary_id INTO v_itin;
    INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, from_stall_id, status)
    VALUES (v_itin, v_run, v_veh, 1, 'depart', v_stage, 'planned');
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (v_veh, v_run, '11111111-1111-1111-1111-111111111111', v_clock - interval '2 hours', '0693_probe',
            '[{"svc": "exterior_wash", "status": "done", "must_do": true},
              {"svc": "readiness_check", "status": "done", "must_do": true}]'::jsonb, 'in_progress');
    UPDATE public.stalls SET reserved_by = v_veh, reserved_at = v_clock, reservation_expires_at = v_clock + interval '1 hour'
     WHERE id = v_hold;
    IF NOT COALESCE(public.ottoq_departure_clear(v_veh, v_run, v_clock, true), false) THEN
      RAISE EXCEPTION '0693 V1: the probe car is not departure-clear after its setup';
    END IF;
    v_before := pg_temp.p0693_holds(v_veh);
    v_disp := twin.ottoq_sim_dispatch_vehicle(v_veh, v_run, v_clock);
    v_r := jsonb_build_object(
      'run', v_run, 'car', v_ref, 'dispatched', v_disp IS NOT NULL,
      'before', v_before, 'after', pg_temp.p0693_holds(v_veh),
      'state', (SELECT current_state::text FROM public.vehicles WHERE id = v_veh),
      'stall', (SELECT current_stall_id FROM public.vehicles WHERE id = v_veh),
      'inbox', (SELECT jsonb_agg(jsonb_build_object(
                         'disposition', i.disposition, 'effect', i.detail ->> 'effect',
                         'marked_away', i.detail -> 'marked_away', 'left_with_open_work', i.detail -> 'left_with_open_work',
                         'release', i.detail -> 'release'))
                  FROM public.ottoq_v2_inbox i
                 WHERE i.sim_run_id = v_run AND i.vehicle_id = v_veh AND i.ce_type = 'com.ottoyard.vehicle.departed'),
      'open_work_events', (SELECT count(*) FROM public.ottoq_events e
                            WHERE e.entity_id = v_veh AND e.sim_run_id = v_run
                              AND e.event_type = 'vehicle.departed_with_open_work'));
    RAISE EXCEPTION '0693 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0693 PROBED' THEN RAISE EXCEPTION '0693 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0693 VALUES (p_phase, v_r);
END $fn$;

DO $v1a$
DECLARE v_off jsonb; v_on jsonb;
BEGIN
  PERFORM pg_temp.p0693_dispatch('off', NULL);
  PERFORM pg_temp.p0693_dispatch('on', 1);
  SELECT r INTO v_off FROM p0693 WHERE phase = 'off';
  SELECT r INTO v_on FROM p0693 WHERE phase = 'on';
  -- the probe held something of each kind, the same in both arms
  IF (v_off -> 'before') IS DISTINCT FROM (v_on -> 'before')
     OR COALESCE((v_off #>> '{before,legs_open}')::int, 0) < 1
     OR COALESCE((v_off #>> '{before,itineraries_active}')::int, 0) < 1
     OR COALESCE((v_off #>> '{before,needs_open}')::int, 0) < 1
     OR COALESCE((v_off #>> '{before,reservations}')::int, 0) < 1 THEN
    RAISE EXCEPTION '0693 V1 FAILED: the probe did not hold the same things in both arms: off % on %', v_off, v_on;
  END IF;
  -- unset: dispatched, released, and the door never asked
  IF v_off ->> 'dispatched' IS DISTINCT FROM 'true' OR jsonb_typeof(v_off -> 'inbox') IS DISTINCT FROM 'null'
     OR v_off ->> 'state' IS DISTINCT FROM 'deployed' OR jsonb_typeof(v_off -> 'stall') IS DISTINCT FROM 'null'
     OR COALESCE((v_off #>> '{after,legs_open}')::int, -1) <> 0
     OR COALESCE((v_off #>> '{after,itineraries_active}')::int, -1) <> 0
     OR COALESCE((v_off #>> '{after,needs_open}')::int, -1) <> 0
     OR COALESCE((v_off #>> '{after,reservations}')::int, -1) <> 0
     OR COALESCE((v_off ->> 'open_work_events')::int, -1) <> 0 THEN
    RAISE EXCEPTION '0693 V1 FAILED: with the flag unset the dispatcher did not take its old path: %', v_off;
  END IF;
  -- at 1: one departure, applied by the door as the release, the car not marked again (its dispatcher had), nothing
  -- recorded open, and every hold exactly as the old path left it
  IF v_on ->> 'dispatched' IS DISTINCT FROM 'true'
     OR jsonb_typeof(v_on -> 'inbox') IS DISTINCT FROM 'array' OR jsonb_array_length(v_on -> 'inbox') <> 1
     OR v_on #>> '{inbox,0,disposition}' IS DISTINCT FROM 'applied'
     OR v_on #>> '{inbox,0,effect}' IS DISTINCT FROM 'released'
     OR v_on #>> '{inbox,0,marked_away}' IS DISTINCT FROM 'false'
     OR v_on #>> '{inbox,0,left_with_open_work}' IS DISTINCT FROM 'false'
     OR (v_on -> 'after') IS DISTINCT FROM (v_off -> 'after')
     OR v_on ->> 'state' IS DISTINCT FROM v_off ->> 'state'
     OR jsonb_typeof(v_on -> 'stall') IS DISTINCT FROM 'null'
     OR COALESCE((v_on ->> 'open_work_events')::int, -1) <> 0 THEN
    RAISE EXCEPTION '0693 V1 FAILED: with the flag on: % (off: %)', v_on, v_off;
  END IF;
  RAISE NOTICE '0693 V1a PASSED: flag unset, the dispatcher released % itself; flag on, its operator reported the departure and the door released the same, % (all rolled back)',
    v_off -> 'before', v_on -> 'inbox';
END $v1a$;

-- ── V1b: a car that leaves before its wash, reported straight through the door, in a block that rolls back ──
CREATE FUNCTION pg_temp.p0693_early() RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_run uuid; v_clock timestamptz; v_veh uuid; v_ref text; v_stage uuid; v_hash text; v_seq numeric; v_ts text;
  v_ev jsonb; v_bad jsonb; v_good jsonb; v_r jsonb; v_msg text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  -- a car sim-b speaks for, with no owner setting on that run, and sim-b's key
  SELECT v.id, v.display_name, k.key_hash INTO v_veh, v_ref, v_hash
    FROM public.vehicles v
    JOIN public.ottow_api_keys k ON v.fleet_operator_id = ANY (k.fleet_operator_ids) AND k.is_active AND k.data_source = 'twin'
    JOIN twin.ottoq_twin_operators o ON o.key_id = k.id AND o.source_name = 'sim-b'
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s
                      WHERE s.vehicle_id = v.id AND s.sim_run_id = v_run AND s.status = 'active')
   ORDER BY v.display_name LIMIT 1;
  SELECT s.id INTO v_stage FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'staging'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
   ORDER BY s.stall_code, s.id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL OR v_stage IS NULL THEN
    RAISE EXCEPTION '0693 V1: no stopped twin run, no sim-b car or no free staging stall to probe';
  END IF;
  -- the next number in the car's sequence on that run, past anything its operator already sent
  v_seq := greatest(
    COALESCE((SELECT last_seq FROM twin.ottoq_twin_operator_sequences
               WHERE sim_run_id = v_run AND source_name = 'sim-b' AND vehicle_ref = v_ref), 0),
    COALESCE((SELECT last_sequence::numeric FROM public.ottoq_v2_cursors
               WHERE sim_run_id = v_run AND source_name = 'sim-b' AND ce_source = 'urn:ottoq:src:sim-b:' || v_ref), 0)) + 1;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    -- the car waiting in staging for a wash it has not had, at 60%
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_stall_id = v_stage, current_soc = 60,
           robotic_tether_until = NULL, last_state_change = v_clock
     WHERE id = v_veh;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (v_veh, v_run, '11111111-1111-1111-1111-111111111111', v_clock - interval '30 minutes', '0693_probe_early',
            '[{"svc": "exterior_wash", "status": "pending", "must_do": true}]'::jsonb, 'open');
    v_ts := ottoq.ottoq_v2_rfc3339(v_clock);
    v_ev := jsonb_build_object(
      'specversion', '1.0', 'source', 'urn:ottoq:src:sim-b:' || v_ref, 'subject', v_ref,
      'type', 'com.ottoyard.vehicle.departed', 'time', v_ts, 'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.departed.json');
    PERFORM set_config('ottoq.v2_twin_run', v_run::text, true);
    -- a reason off the contract's list is refused and moves nothing
    v_bad := public.ottoq_v2_take_events(v_hash, jsonb_build_array(v_ev || jsonb_build_object(
      'id', 'dep-probe-0693-bad', 'sequence', lpad(v_seq::text, 20, '0'),
      'data', jsonb_build_object('departed_at', v_ts, 'reason', 'teleported'))), false);
    -- the owner takes the car before its wash
    v_good := public.ottoq_v2_take_events(v_hash, jsonb_build_array(v_ev || jsonb_build_object(
      'id', 'dep-probe-0693-good', 'sequence', lpad((v_seq + 1)::text, 20, '0'),
      'data', jsonb_build_object('departed_at', v_ts, 'reason', 'owner_recall', 'soc_pct', 60))), false);
    PERFORM set_config('ottoq.v2_twin_run', '', true);
    v_r := jsonb_build_object(
      'car', v_ref, 'bad', v_bad -> 'results' -> 0, 'good', v_good -> 'results' -> 0,
      'state', (SELECT current_state::text FROM public.vehicles WHERE id = v_veh),
      'stall', (SELECT current_stall_id FROM public.vehicles WHERE id = v_veh),
      'needs_open', (SELECT count(*) FROM public.ottoq_visit_needs WHERE vehicle_id = v_veh AND sim_run_id = v_run
                       AND status IN ('open', 'in_progress', 'carried_over')),
      'event', (SELECT jsonb_build_object('n', count(*), 'open', min(e.payload ->> 'open_services'),
                                          'soc', min(e.payload ->> 'soc'), 'target', min(e.payload ->> 'target_soc'),
                                          'reason', min(e.payload ->> 'reason'), 'data_source', min(e.data_source))
                  FROM public.ottoq_events e
                 WHERE e.entity_id = v_veh AND e.sim_run_id = v_run AND e.event_type = 'vehicle.departed_with_open_work'));
    RAISE EXCEPTION '0693 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0693 PROBED' THEN RAISE EXCEPTION '0693 early-departure probe failed: %', v_msg; END IF;
  RETURN v_r;
END $fn$;

DO $v1b$
DECLARE v jsonb := pg_temp.p0693_early();
BEGIN
  IF v #>> '{bad,disposition}' IS DISTINCT FROM 'refused' OR v #>> '{bad,reason}' IS DISTINCT FROM 'departed_reason'
     OR v #>> '{good,disposition}' IS DISTINCT FROM 'applied'
     OR v #>> '{good,detail,effect}' IS DISTINCT FROM 'released'
     OR v #>> '{good,detail,marked_away}' IS DISTINCT FROM 'true'
     OR v #>> '{good,detail,left_with_open_work}' IS DISTINCT FROM 'true'
     OR COALESCE(v #>> '{good,detail,open_services}', '') NOT LIKE '%exterior_wash%'
     OR v ->> 'state' IS DISTINCT FROM 'deployed' OR jsonb_typeof(v -> 'stall') IS DISTINCT FROM 'null'
     OR COALESCE((v ->> 'needs_open')::int, -1) <> 0
     OR COALESCE((v #>> '{event,n}')::int, 0) <> 1
     OR COALESCE(v #>> '{event,open}', '') NOT LIKE '%exterior_wash%'
     OR (v #>> '{event,soc}')::numeric IS DISTINCT FROM 60 OR (v #>> '{event,target}')::numeric IS DISTINCT FROM 100
     OR v #>> '{event,reason}' IS DISTINCT FROM 'owner_recall' OR v #>> '{event,data_source}' IS DISTINCT FROM 'twin' THEN
    RAISE EXCEPTION '0693 V1 FAILED: a car leaving before its wash, reported through the door: %', v;
  END IF;
  RAISE NOTICE '0693 V1b PASSED: an unknown reason refused; a car taken before its wash marked away, released, and recorded as leaving with % open at 60%% of 100%% (all rolled back)',
    v #>> '{event,open}';
END $v1b$;

-- ── V2: the definitions as written, the flag set nowhere, the experiment as written, the purge's check still passes ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> 'd06c41eb8ffd9b600f8246ccbaf5a04d'
     OR md5(pg_get_functiondef('twin.ottoq_sim_dispatch_vehicle(uuid,uuid,timestamptz)'::regprocedure))
       <> 'b55ea62b8533bca8021eb3330ad0af85' THEN
    RAISE EXCEPTION '0693 V2 FAILED: a patched definition is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_departures') THEN
    RAISE EXCEPTION '0693 V2 FAILED: the flag is set somewhere';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c USING (param_key)
                  WHERE e.created_by = '0693' AND e.status = 'active' AND e.param_key = 'twin_operator_departures'
                    AND e.control_value BETWEEN c.min_value AND c.max_value
                    AND e.treatment_value BETWEEN c.min_value AND c.max_value) THEN
    RAISE EXCEPTION '0693 V2 FAILED: the experiment is not active with its dial in range';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_v2_inbox WHERE ce_type = 'com.ottoyard.vehicle.departed') THEN
    RAISE EXCEPTION '0693 V2 FAILED: a probe''s departure outlived its rollback';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block') THEN
    RAISE EXCEPTION '0693 V2 FAILED: the run-scope registry reports a blocking defect, so the purge would refuse';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0693_a_car_leaving_the_depot_is_reported_through_the_door', false, false,
  'Stage 3 of the twin''s sending side: the door''s com.ottoyard.vehicle.departed records what was still open (contract '
  'rule 8), marks the car away when OTTO-Q still has it at the depot, and makes the release the dispatcher made; the '
  'flag twin_operator_departures and twin.ottoq_twin_operator_depart; the dispatcher reads the flag; the pair '
  'registered. The flag is set nowhere, at 0 the dispatcher takes its old body (V1), and no departure has ever reached '
  'the door: FALSE/FALSE. Setting the flag is a certified change after the pair.',
  now());

COMMIT;
