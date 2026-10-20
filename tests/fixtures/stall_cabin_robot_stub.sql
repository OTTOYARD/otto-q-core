-- tests/fixtures/stall_cabin_robot_stub.sql -- the engine 0758 patches, as far as 0758 touches it. Loaded after
-- tests/fixtures/agent_charge_order_stub.sql (the base: vehicles, stalls, visits, runs, the dial tables, ottoq_policy_get).
-- The five functions 0758 patches are pg_get_functiondef's output, byte for byte, read from the live catalog on 2026-10-19
-- (prosrc md5: starter f7d87d5d, hold e586ee27, completion step 3e8eb3f4, snapshot ea1a4a9a, depot cards c4530de9), so
-- 0758's premises pass against them; ottoq_depot_staffing_count is the live body. The rest are stand-ins, noted where they
-- are defined: the charge estimate reads a test setting so a test can say how much charge is left, and the ledger credit,
-- the leg close and the shield probe record or do nothing. Tables carry the columns these functions read. The snapshot is
-- loaded for 0758's premises and patch only; its own reads (energy, weather, legs...) are not stood up here, so it is
-- exercised on live, rolled back (db/migrations/0758 header).
SET client_min_messages = warning;
CREATE TABLE IF NOT EXISTS public.depots (id uuid PRIMARY KEY, feed_mode text);
CREATE TABLE IF NOT EXISTS public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid, stall_id uuid,
  vehicle_id uuid, status text DEFAULT 'active', started_at timestamp with time zone, ended_at timestamp with time zone,
  soc_start integer, ambient_temp_c numeric, sim_run_id uuid);
CREATE TABLE IF NOT EXISTS public.ottoq_depot_staffing (depot_id uuid, role text, headcount integer);
CREATE TABLE IF NOT EXISTS public.ottoq_vehicle_itineraries (itinerary_id uuid, vehicle_id uuid, sim_run_id uuid, status text,
  sim_created_at timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.ottoq_itinerary_legs (leg_id uuid DEFAULT gen_random_uuid(), itinerary_id uuid, vehicle_id uuid,
  sim_run_id uuid, seq integer, leg_type text, duration_basis jsonb, status text, from_stall_id uuid, to_stall_id uuid,
  planned_start_sim timestamp with time zone, planned_end_sim timestamp with time zone,
  actual_start_sim timestamp with time zone, actual_end_sim timestamp with time zone, planned_duration_s numeric,
  deviation_s numeric);
CREATE TABLE IF NOT EXISTS public.ottoq_ops_approvals (approval_id uuid DEFAULT gen_random_uuid(), approval_type text,
  vehicle_id uuid, visit_id uuid, sim_run_id uuid, depot_id uuid, payload jsonb, requested_at timestamp with time zone,
  decide_after timestamp with time zone, expires_at timestamp with time zone, priority text, status text DEFAULT 'pending',
  decided_at timestamp with time zone);
CREATE TABLE IF NOT EXISTS public.ottoq_throughput_sweeps (sweep_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sweep_code text NOT NULL, title text NOT NULL, depot_id uuid NOT NULL, scenario text NOT NULL,
  sim_start timestamp with time zone NOT NULL, ticks integer NOT NULL, sim_min_per_tick numeric NOT NULL,
  seeds bigint[] NOT NULL, replicates integer NOT NULL DEFAULT 1, priority integer NOT NULL DEFAULT 100,
  arm_budget_s integer, status text NOT NULL DEFAULT 'active', run_after timestamp with time zone, notes text,
  created_by text NOT NULL DEFAULT 'research_wing', created_at timestamp with time zone NOT NULL DEFAULT now(),
  concluded_at timestamp with time zone, fleet_code text);
CREATE TABLE IF NOT EXISTS public.ottoq_throughput_sweep_cells (cell_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sweep_id uuid NOT NULL, cell_code text NOT NULL, ord integer NOT NULL, seat text NOT NULL, buildout_code text NOT NULL,
  fixed_params jsonb NOT NULL DEFAULT '{}'::jsonb, control_cell_code text);
-- what the stand-ins record, for the tests to read
CREATE TABLE IF NOT EXISTS public._test_leg_closes (vehicle_id uuid, svc text, started timestamp with time zone,
  ended timestamp with time zone);
CREATE TABLE IF NOT EXISTS public._test_credits (vehicle_id uuid, svc text, at timestamp with time zone);

-- STAND-IN: the planner's charge estimate. The test says how many minutes the charge has left (setting
-- test.charge_left_min, default 30), so the gate's boundary can be put on either side of the arm's cycle.
CREATE OR REPLACE FUNCTION public.ottoq_estimate_charge_minutes(p_start_soc numeric, p_target_soc numeric,
  p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_temp_c numeric,
  p_battery_soh_pct numeric, p_rate_mult numeric) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('test.charge_left_min', true), '')::numeric, 30)
$$;
-- STAND-IN: depot cards read it; a constant 100 here.
CREATE OR REPLACE FUNCTION public.ottoq_target_soc_cap(p_stall_type text, p_at timestamp with time zone)
  RETURNS numeric LANGUAGE sql STABLE AS $$ SELECT 100::numeric $$;
-- STAND-INS: the completion step's three side calls, recorded or ignored.
CREATE OR REPLACE FUNCTION public.ottoq_close_atom_leg(p_sim_run_id uuid, p_vehicle uuid, p_svc text,
  p_started timestamp with time zone, p_ended timestamp with time zone) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public._test_leg_closes VALUES (p_vehicle, p_svc, p_started, p_ended)
$$;
CREATE OR REPLACE FUNCTION public.ottoq_wear_mark_serviced(p_vehicle_id uuid, p_sim_run_id uuid, p_service text,
  p_clock timestamp with time zone) RETURNS boolean LANGUAGE sql AS $$
  INSERT INTO public._test_credits VALUES (p_vehicle_id, p_service, p_clock) RETURNING true
$$;
CREATE OR REPLACE FUNCTION public.ottoq_probe_task_completion(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid,
  p_svc text, p_started_at timestamp with time zone, p_ends_at timestamp with time zone)
  RETURNS TABLE(rule_code text, passed boolean, reason text, severity text, enforcement text, would_block boolean,
                had_a_stall boolean) LANGUAGE sql AS $$ SELECT NULL::text, true, NULL::text, NULL::text, NULL::text, false, false WHERE false $$;
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text) RETURNS numeric LANGUAGE sql
  IMMUTABLE AS $$ SELECT 0.5::numeric $$;

-- ══ the live bodies ══
CREATE OR REPLACE FUNCTION public.ottoq_depot_staffing_count(p_depot_id uuid, p_role text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE((SELECT headcount FROM ottoq_depot_staffing
                    WHERE depot_id = p_depot_id AND role = p_role),
                  CASE p_role WHEN 'general_tech' THEN 10
                              WHEN 'wash_supervisor' THEN 2
                              WHEN 'service_tech' THEN 3 ELSE 1 END);
$function$
;
CREATE OR REPLACE FUNCTION public.ottoq_start_concurrent_atoms(p_vehicle uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_visit uuid; v_atoms jsonb; v_depot uuid;
  v_new jsonb := '[]'::jsonb; v_a jsonb; v_free int; v_started int := 0;
  v_needs_triage boolean; v_has_triage boolean;
  v_state text; v_charging_visit boolean; v_sensors boolean; v_cabin_triage boolean;   -- 0511
  v_stall uuid;   -- 0519 (G245): the stall whose sensors start the work
  v_on_charger boolean;   -- 0521 (G246): whether that stall is a charger at all
  v_uplink boolean;   -- 0695: whether that stall has a wired data uplink (a charger or a service bay)
BEGIN
  SELECT home_depot_id INTO v_depot FROM vehicles WHERE id = p_vehicle;
  SELECT visit_id, atoms INTO v_visit, v_atoms FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle AND status IN ('open','in_progress') AND COALESCE(ottoq_visit_needs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = v_depot ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
   ORDER BY created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN RETURN 0; END IF;

  SELECT
    EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a
             WHERE COALESCE((a->>'confirm_required')::boolean,false)
               AND COALESCE(a->>'status','pending') = 'pending'),
    EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) a WHERE a->>'svc' = 'triage_check')
  INTO v_needs_triage, v_has_triage;
  IF v_needs_triage AND NOT v_has_triage THEN
    v_atoms := v_atoms || jsonb_build_array(jsonb_build_object(
      'svc','triage_check','must_do',true,'deferrable',false,'est_min',3,'concurrency','cabin'));
  END IF;

  -- general_tech_pool (founder spec: ~10 techs in the charging zones). Each tech
  -- handles ONE vehicle at a time: plug in -> 3-5 min interior clean -> inspect.
  -- Cars in a wash bay are deliberately NOT subtracted here — the automatic wash is
  -- supervised by the wash_supervisor pool, it does not consume a charging-zone tech.
  SELECT GREATEST(0, ottoq_depot_staffing_count(v_depot, 'general_tech')
      - (SELECT count(*) FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
           WHERE vn2.depot_id = v_depot AND vn2.status = 'in_progress' AND COALESCE(vn2.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = v_depot ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
             AND a2->>'status' = 'in_progress' AND a2->>'concurrency' IN ('cabin','exterior')
             -- 0511 (G236): work the charger's sensors perform (an inspection, a cabin triage) takes no technician
             AND COALESCE(a2->>'performed_by', '') <> 'charger_sensors'))
    INTO v_free;
  -- 0511 (G236, decided 2026-09-27): a visit that still has its charge to do does its cabin work at the charger,
  -- during the charge, not before the car is plugged in. The twin starter's two catch-ups stay (still on the charger
  -- after the charge; staged for departure) so nothing waits forever. An interior inspection done while the car is on
  -- the charger is the charger's sensors' job (robotic charging), and so is a triage check that judges only the cabin:
  -- each takes no technician and says so.
  SELECT v.current_state::text, v.current_stall_id INTO v_state, v_stall FROM vehicles v WHERE v.id = p_vehicle;
  -- 0521 (G246): the sensors are a charger's, so the car must be on one. The state alone does not say so:
  -- `charge_complete_holding` is also a car the gate intake holds on staging with no charge to do, and a car that has
  -- left its charger for a bay, and on c4afb873 six sensor starts were on such cars.
  v_on_charger := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN ('dcfc','l2'));
  v_uplink := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN ('dcfc','l2','service_bay'));
  v_charging_visit := EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) c
                               WHERE c->>'svc' = 'charge' AND COALESCE(c->>'status','pending') NOT IN ('done','cancelled'));
  -- the triage check confirms, clears or escalates the visit's uncertain needs; when every one of them is in the
  -- cabin (an uncertain interior tidy), the charger's sensors can see all it judges
  v_cabin_triage := NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) c
                                 WHERE COALESCE((c->>'confirm_required')::boolean, false)
                                   AND COALESCE(c->>'status','pending') = 'pending'
                                   AND c->>'concurrency' IS DISTINCT FROM 'cabin');
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF COALESCE(v_a->>'status','pending') = 'pending'
       AND v_a->>'concurrency' IN ('cabin','exterior','digital')
       AND v_a->>'svc' <> 'readiness_check'
       AND (NOT COALESCE((v_a->>'confirm_required')::boolean,false))
       AND NOT (v_a->>'concurrency' = 'cabin' AND v_charging_visit
                -- 0521 (G246): a charging state excuses the hold only on a charger; staged for departure always does
                AND NOT (COALESCE(v_state, '') = 'staged_for_departure'
                         OR (COALESCE(v_state, '') IN ('charging_dcfc','charging_l2','charge_complete_holding') AND v_on_charger))) THEN
      v_sensors := (v_a->>'svc' = 'interior_inspection' OR (v_a->>'svc' = 'triage_check' AND v_cabin_triage))
                   AND COALESCE(v_state, '') IN ('charging_dcfc','charging_l2','charge_complete_holding')
                   AND v_on_charger;   -- 0521 (G246)
      -- 0695: a data transfer runs over a stall's wired uplink, so it starts only on a charger or a service bay
      IF COALESCE((v_a->>'needs_uplink')::boolean, false) AND NOT COALESCE(v_uplink, false) THEN
        NULL;
      ELSIF v_a->>'concurrency' = 'digital' OR v_sensors OR v_free > 0 THEN
        IF v_a->>'concurrency' <> 'digital' AND NOT v_sensors THEN v_free := v_free - 1; END IF;
        v_a := v_a || jsonb_build_object('status','in_progress',
                'started_at', to_jsonb(p_clock),
                'ends_at', to_jsonb(p_clock + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval))
                   -- 0519 (G245): and on which stall, since the sensors are that stall's and see only a car on it
                   || CASE WHEN v_sensors THEN jsonb_build_object('performed_by', 'charger_sensors',
                                                                  'sensor_stall_id', v_stall) ELSE '{}'::jsonb END
                   -- 0695: and a transfer on which uplink stall, since it runs only while its car stands there
                   || CASE WHEN COALESCE((v_a->>'needs_uplink')::boolean, false)
                           THEN jsonb_build_object('performed_by', 'stall_uplink', 'uplink_stall_id', v_stall)
                           ELSE '{}'::jsonb END;
        v_started := v_started + 1;
      END IF;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_started > 0 OR (v_needs_triage AND NOT v_has_triage) THEN
    UPDATE ottoq_visit_needs SET atoms = v_new, status = 'in_progress' WHERE visit_id = v_visit;
  END IF;
  RETURN v_started;
END; $function$
;
CREATE OR REPLACE FUNCTION ottoq.ottoq_uplink_transfer_holds(p_vehicle uuid, p_run uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 0695: an unfinished data transfer holds its car on the uplink stall it stands on (a charger or a service bay), as
  -- live work does: the car is not moved to its next work until the transfer ends (docs/DATA_OFFLOAD.md). False for
  -- every car while no run raises a transfer.
  SELECT EXISTS (
    SELECT 1
      FROM public.vehicles v
      JOIN public.stalls s ON s.id = v.current_stall_id AND s.stall_type::text IN ('dcfc', 'l2', 'service_bay')
      JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.sim_run_id IS NOT DISTINCT FROM p_run
                                      AND vn.status IN ('open', 'in_progress')
      CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
     WHERE v.id = p_vehicle AND COALESCE((a->>'needs_uplink')::boolean, false)
       AND COALESCE(a->>'status', 'pending') IN ('pending', 'in_progress'))
$function$
;
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_visit_atoms(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_rec RECORD; v_new jsonb; v_a jsonb; v_b jsonb;
  v_changed boolean; v_total int := 0;
  v_triage_done boolean; v_conf numeric; v_roll numeric; v_verdict text;
  v_escalations jsonb; v_tick bigint; v_feed_sim boolean := true;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42), tick_count INTO v_depot, v_seed, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = v_depot;
  v_feed_sim := COALESCE(v_feed_sim, true);

  FOR v_rec IN
    SELECT vn.vehicle_id
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND v.current_state IN ('charging_dcfc','charging_l2','charge_complete_holding',
                               'staged_awaiting_service','staged_for_departure','arrived_at_gate')
       -- M3_cabin_at_charger: cabin work (interior tidy) is performed BY A
       -- TECHNICIAN AT THE CHARGER during the session, so it may only start while the
       -- vehicle is plugged in. Previously it could start in any of six states —
       -- including at the gate and while staged for departure — which is why only 5.8%
       -- of interior cleans actually overlapped a charge. charge_complete_holding is
       -- kept ONLY as a catch-up: without it a vehicle whose charge finished before the
       -- tech arrived would never be cleaned and SLA.004 would block its deploy forever.
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE COALESCE(a->>'status','pending') = 'pending'
                      AND a->>'svc' <> 'readiness_check'
                      AND ( (a->>'concurrency' = 'cabin'
                               AND v.current_state IN ('charging_dcfc','charging_l2',
                                                       'charge_complete_holding',
                                                       -- 0385: the second catch-up. The
                                                       -- comment above added
                                                       -- charge_complete_holding for
                                                       -- exactly this failure and stopped
                                                       -- one state short.
                                                       'staged_for_departure'))
                         -- 0526 (G251): a visit with no charge left to do has no charger to wait for. Its car, parked
                         -- for its bay work, has its cabin work done where it stands, by a technician (the starter's
                         -- hold binds only a charging visit, and its sensors only a car on a charger). Without this the
                         -- work waited for the deploy gate's 240-minute escape hatch.
                         OR (a->>'concurrency' = 'cabin' AND v.current_state = 'staged_awaiting_service'
                             AND v.current_stall_id IS NOT NULL
                             AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) c
                                              WHERE c->>'svc' = 'charge'
                                                AND COALESCE(c->>'status','pending') NOT IN ('done','cancelled')))
                         OR (a->>'concurrency' IN ('exterior','digital')
                             -- 0695: a data transfer waits for its car to stand on an uplink stall, and until then
                             -- takes none of this pass's thirty places
                             AND NOT (COALESCE((a->>'needs_uplink')::boolean, false)
                                      AND NOT EXISTS (SELECT 1 FROM stalls su
                                                       WHERE su.id = v.current_stall_id
                                                         AND su.stall_type::text IN ('dcfc','l2','service_bay')))) ))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
              (v.current_state IN ('charging_dcfc','charging_l2')) DESC,
              v.last_state_change ASC,
              vn.vehicle_id   /* 0108: run-stable tail; same-tick transitions tie */
     LIMIT 30
  LOOP
    PERFORM ottoq_start_concurrent_atoms(v_rec.vehicle_id, p_clock);
  END LOOP;

  FOR v_rec IN
    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state, v.current_stall_id,   /* 0519 */
           COALESCE(v.config->>'svc_step','ready') AS svc_step   /* 0437 */
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND (EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE a->>'status' = 'in_progress' AND (a->>'ends_at')::timestamptz <= p_clock)
         OR ((v.current_state = 'staged_for_departure'
              /* 0437: the dispatcher's second door, by its own predicate */
              OR (v.current_state = 'staged_awaiting_service' AND COALESCE(v.config->>'svc_step','ready') IN ('ready')))
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'readiness_check' AND COALESCE(a->>'status','pending') = 'pending')))
     ORDER BY vn.vehicle_id   /* 0054: run-stable cursor order */
  LOOP
    v_new := '[]'::jsonb; v_changed := false; v_triage_done := false; v_escalations := '[]'::jsonb;
    FOR v_a IN SELECT * FROM jsonb_array_elements(v_rec.atoms) LOOP
      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'stall_uplink' AND v_a->>'uplink_stall_id' IS NOT NULL
         AND v_rec.current_stall_id IS DISTINCT FROM (v_a->>'uplink_stall_id')::uuid THEN
        -- 0695: a data transfer runs over its stall's wired uplink. This car left that stall before the minutes ran out
        -- (only a path the transfer's hold does not cover moves it), so the data did not all come off: back to pending
        -- for its next uplink stall, the interruption recorded and nothing credited, as 0519 does for the sensors.
        v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'uplink_stall_id')
               || jsonb_build_object('status', 'pending',
                    'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                        'at', p_clock, 'reason', 'left_the_uplink',
                        'started_at', v_a->'started_at', 'stall_id', v_a->'uplink_stall_id')));
        v_changed := true;
      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'charger_sensors' AND v_a->>'sensor_stall_id' IS NOT NULL
         AND v_rec.current_stall_id IS DISTINCT FROM (v_a->>'sensor_stall_id')::uuid THEN
        -- 0519 (G245): the charger's sensors see only a car on their stall. This car left it (a charge cut by a fault
        -- sends it to staging or another charger) before the work's minutes ran out, so the work was not done: it
        -- goes back to pending, the interruption recorded, and nothing is credited, closed or probed for it.
        v_a := (v_a - 'started_at' - 'ends_at' - 'performed_by' - 'sensor_stall_id')
               || jsonb_build_object('status', 'pending',
                    'interrupted', COALESCE(v_a->'interrupted', '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
                        'at', p_clock, 'reason', 'left_the_charger',
                        'started_at', v_a->'started_at', 'stall_id', v_a->'sensor_stall_id')));
        v_changed := true;
      ELSIF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');
        v_changed := true; v_total := v_total + 1;
        -- N2/M4c: close the matching flow-contract leg with real times
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc',
                (v_a->>'started_at')::timestamptz, (v_a->>'ends_at')::timestamptz);

        -- ══════════ 0005: CREDIT THE LEDGER THE DEPOT ACTUALLY READS ══════════
        -- This is the line whose absence meant 90 inspections, 26 cabin tidies, 5 sensor
        -- cleans and 5 item retrievals in run 909 moved nothing at all. Shared function,
        -- shared with the real-telemetry seam -- see §3 header. Fully qualified so
        -- search_path can never resolve it somewhere else. Own handler: a ledger failure
        -- must never unwind the atom close, the leg close, or the tick.
        BEGIN
          PERFORM public.ottoq_wear_mark_serviced(
                    v_rec.vehicle_id, p_sim_run_id, v_a->>'svc',
                    COALESCE((v_a->>'ends_at')::timestamptz, p_clock));
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_sim_advance_visit_atoms: need-ledger credit FAILED SAFELY vehicle=% svc=% %: %',
            v_rec.vehicle_id, v_a->>'svc', SQLSTATE, SQLERRM;
        END;

        -- 0422: PROBE task_completion -- the one unprobed context the engine actually performs.
        -- 0418 built and proved this probe and left it unwired because `rules` is one of the fourteen
        -- determinism atoms. This is that line. Own handler, exactly like the ledger credit above: a
        -- shield READ must never unwind the atom close. ottoq_shield_probe does not block -- it returns
        -- would_block and leaves enforcement to its caller, and this caller enforces nothing.
        BEGIN
          PERFORM public.ottoq_probe_task_completion(
                    p_sim_run_id, v_depot, v_rec.vehicle_id, v_a->>'svc',
                    (v_a->>'started_at')::timestamptz,
                    COALESCE((v_a->>'ends_at')::timestamptz, p_clock));
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_sim_advance_visit_atoms: task_completion probe FAILED SAFELY vehicle=% svc=% %: %',
            v_rec.vehicle_id, v_a->>'svc', SQLSTATE, SQLERRM;
        END;

        IF v_a->>'svc' = 'triage_check' THEN v_triage_done := true; END IF;
        IF COALESCE((v_a->>'requires_tech_greenlight')::boolean,false) THEN
          INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, visit_id, sim_run_id, depot_id,
                 payload, requested_at, decide_after, expires_at, priority)
          SELECT 'tech_greenlight', v_rec.vehicle_id, v_rec.visit_id, p_sim_run_id, v_depot,
                 jsonb_build_object('svc', v_a->>'svc', 'est_min', v_a->>'est_min'),
                 p_clock,
                 p_clock + ((15 + floor(ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':glDelay') * 45))::text || ' minutes')::interval,
                 p_clock + interval '120 minutes', 'high'
          WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                             WHERE ap.vehicle_id = v_rec.vehicle_id AND ap.approval_type = 'tech_greenlight'
                               AND ap.sim_run_id = p_sim_run_id  /* 0108: a prior run's approval must not suppress this run's raise */
                               AND (ap.status = 'pending' OR ap.decided_at > p_clock - interval '60 minutes'));
        END IF;
      ELSIF v_a->>'svc' = 'readiness_check' AND COALESCE(v_a->>'status','pending') = 'pending'
         AND (v_rec.current_state = 'staged_for_departure'
              OR (v_rec.current_state = 'staged_awaiting_service' AND v_rec.svc_step IN ('ready')))   /* 0437 */
         -- 0657 (G398): the readiness check is the LAST atom of its visit. Every other atom is done or cancelled, as
         -- ottoq_departure_clear reads them, or finishes in this very pass by the branch above (read off the visit as
         -- the pass began; a triage check that finishes now is waited for, since what it finds is added after this
         -- loop). A car staged before its work is done, or with no svc_step yet, no longer has its check closed for it.
         AND NOT EXISTS (
               SELECT 1 FROM jsonb_array_elements(v_rec.atoms) o
                WHERE o->>'svc' <> 'readiness_check'
                  AND COALESCE(o->>'status','pending') NOT IN ('done','cancelled')
                  AND NOT COALESCE(v_feed_sim AND o->>'svc' <> 'triage_check'
                                   AND o->>'status' = 'in_progress' AND (o->>'ends_at')::timestamptz <= p_clock
                                   AND NOT (COALESCE(o->>'performed_by','') = 'charger_sensors'
                                            AND o->>'sensor_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'sensor_stall_id')::uuid)
                                   -- 0695: nor a transfer whose car left its uplink stall, which goes back to pending
                                   AND NOT (COALESCE(o->>'performed_by','') = 'stall_uplink'
                                            AND o->>'uplink_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'uplink_stall_id')::uuid),
                                   false)) THEN
        -- 0005 NOTE: deliberately NOT credited. A readiness check confirms the vehicle is
        -- fit to leave; it restores nothing, and there is no column it may honestly move.
        v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
        v_changed := true; v_total := v_total + 1;
        -- 0504 (G232): its own leg, by its atom. 'inspect' took whichever inspect leg came first, which
        -- was the interior inspection's whenever that one was still open.
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, 'readiness_check',
                p_clock - interval '3 minutes', p_clock);
      END IF;
      v_new := v_new || jsonb_build_array(v_a);
    END LOOP;

    IF v_triage_done AND v_feed_sim THEN
      v_b := v_new; v_new := '[]'::jsonb;
      FOR v_a IN SELECT * FROM jsonb_array_elements(v_b) LOOP
        IF COALESCE((v_a->>'confirm_required')::boolean,false)
           AND COALESCE(v_a->>'status','pending') = 'pending' THEN
          v_conf := COALESCE((v_a->>'confidence')::numeric, 0.6);
          v_roll := ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':' || (v_a->>'svc') || ':verdict');
          v_verdict := CASE WHEN v_roll < v_conf THEN 'confirm'
                            WHEN v_roll < v_conf + (1 - v_conf) * 0.7 THEN 'clear'
                            ELSE 'escalate' END;
          IF v_verdict = 'confirm' THEN
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'confirm');
          ELSIF v_verdict = 'clear' THEN
            -- 0005 NOTE: deliberately NOT credited. Cleared by triage means the work was
            -- never performed, so no ledger column may move. Cancellation is not completion.
            v_a := v_a || jsonb_build_object('status','cancelled','confirm_required',false,
                     'triage_verdict','clear','cleared_by_triage',true);
            PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc', p_clock, p_clock);
          ELSE
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'escalate');
            IF v_a->>'svc' = 'interior_tidy' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','interior_deep_clean','must_do',true,'deferrable',true,'est_min',20,
                'concurrency','bay','requires_bay','detail','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'sensor_clean' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','sensor_calibration','must_do',true,'deferrable',true,'est_min',30,
                'concurrency','bay','requires_bay','service_bay','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'cosmetic_repair' THEN
              v_a := v_a || jsonb_build_object('requires_tech_greenlight', true);
            END IF;
          END IF;
          INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,action_context,resolved_action_context,
                 entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
          VALUES (p_sim_run_id, v_tick, p_clock, v_depot, 'task_start', 'triage_verdict',
                 'vehicle', v_rec.vehicle_id,
                 jsonb_build_object('svc', v_a->>'svc', 'confidence', v_conf),
                 jsonb_build_object('verb','triage'),
                 jsonb_build_object('verb','triage_' || v_verdict, 'svc', v_a->>'svc'),
                 'enacted', 0, 0);
        END IF;
        v_new := v_new || jsonb_build_array(v_a);
      END LOOP;
      IF jsonb_array_length(v_escalations) > 0 THEN
        FOR v_a IN SELECT * FROM jsonb_array_elements(v_escalations) LOOP
          IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) e WHERE e->>'svc' = v_a->>'svc') THEN
            v_new := v_new || jsonb_build_array(v_a);
          END IF;
        END LOOP;
      END IF;
      v_changed := true;
    END IF;

    IF v_changed THEN UPDATE ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_rec.visit_id; END IF;
  END LOOP;

  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
         THEN 'carried_over' ELSE 'complete' END
  FROM vehicles v
  WHERE v.id = vn.vehicle_id AND vn.depot_id = v_depot
    AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
    AND v.current_state IN ('deployed','en_route_to_deployment');
  RETURN v_total;
END; $function$
;
CREATE OR REPLACE FUNCTION public.ottoq_twin_snapshot(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run     ottoq_sim_runs%ROWTYPE;
  v_depot   UUID;
  v_clock   TIMESTAMPTZ;
  v_out     JSONB;
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'sim_run not found', 'sim_run_id', p_sim_run_id);
  END IF;
  v_depot := v_run.depot_id;
  v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(

    'run', jsonb_build_object(
      'sim_run_id',  v_run.sim_run_id,
      'scenario',    v_run.scenario_code,
      'status',      v_run.status,
      'sim_clock',   v_clock,
      'tick_count',  v_run.tick_count,
      'time_scale',  v_run.time_scale,
      'seed',        v_run.random_seed::text,
      -- PLAYBACK CONTRACT for the renderer.
      -- 'live'  => 1 real second advances the sim clock by speed_x sim seconds (true 1:1 at 1x)
      -- 'fixed' => historical tick_interval_seconds * time_scale behaviour (certs/benchmarks)
      'playback_mode', COALESCE(v_run.payload->>'playback_mode','fixed'),
      'speed_x',       COALESCE((v_run.payload->>'speed_x')::numeric, 1.0),
      -- T5: MEASURED, not configured. NULL until >=2 ticks are logged.
      'clock_measured', (
         SELECT jsonb_build_object(
                  'ratio',            f.ratio,
                  'target',           f.target_ratio,
                  'ticks',            f.ticks_measured,
                  'p50_tick_ms',      f.p50_tick_ms,
                  'p95_tick_ms',      f.p95_tick_ms,
                  'max_speed',        f.max_sustainable_speed,
                  'within_tolerance', f.within_tolerance,
                  'verdict',          f.verdict)
           FROM ottoq_clock_fidelity(v_run.sim_run_id, 20) f),
      -- present ONLY while a fast-forward is in flight; drives the planning pause + progress
      'jump',             v_run.payload->'jump',
      -- pacing inputs: elapsed-since-last-tick and clock skew
      'last_tick_at',     v_run.last_tick_at,
      'next_tick_due_at', v_run.next_tick_due_at,
      'server_now',       now()
    ),

    -- T3 RENDER CONTRACT: timed legs. The renderer INTERPOLATES these; it must
    -- never invent motion the contract did not specify.
    'legs', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'leg_id',      l.leg_id,
        'vehicle_id',  l.vehicle_id,
        'seq',         l.seq,
        'leg_type',    l.leg_type,
        'intent',      l.duration_basis->>'intent',
        'kind',        COALESCE(l.duration_basis->>'kind','dwell'),
        'from_stall',  l.from_stall_id,
        'to_stall',    l.to_stall_id,
        'from_x',      fs.relative_x, 'from_y', fs.relative_y,
        'to_x',        ts.relative_x, 'to_y',   ts.relative_y,
        'start_sim',   l.planned_start_sim,
        'end_sim',     l.planned_end_sim,
        'duration_s',  l.planned_duration_s,
        'status',      l.status,
        'geometry',    COALESCE(l.duration_basis->>'geometry','n/a'))
        ORDER BY l.vehicle_id, l.seq)
        FROM ottoq_itinerary_legs l
        LEFT JOIN stalls fs ON fs.id = l.from_stall_id
        LEFT JOIN stalls ts ON ts.id = l.to_stall_id
       WHERE l.sim_run_id = v_run.sim_run_id
         AND (
           CASE WHEN COALESCE(l.duration_basis->>'kind','dwell') = 'travel'
                -- TRAVEL: covered until CLOSED. ottoq_itin_close_travel_legs bounds
                -- it (arrived / superseded / stale), so a drive that overruns its
                -- estimate stays covered instead of falling off a time cliff.
                THEN l.status NOT IN ('done','amended','skipped')
                -- DWELL: durations are authoritative, keep the time window.
                ELSE l.status <> 'done'
                     AND l.planned_end_sim   >= v_clock - interval '10 minutes'
                     AND l.planned_start_sim <= v_clock + interval '10 minutes'
           END)
    ), '[]'::jsonb),

    -- #173 (D): server half of the CONTRACT COVERAGE ratio. The renderer knows
    -- how many cars are physically taxiing; only it can close the ratio. Publish
    -- the denominator so coverage is measurable instead of assumed.
    'legs_meta', jsonb_build_object(
      'open_travel_legs', (
        SELECT count(*) FROM ottoq_itinerary_legs l2
         WHERE l2.sim_run_id = v_run.sim_run_id
           AND l2.duration_basis->>'kind' = 'travel'
           AND l2.status NOT IN ('done','amended','skipped')),
      'vehicles_with_open_leg', (
        SELECT count(DISTINCT l3.vehicle_id) FROM ottoq_itinerary_legs l3
         WHERE l3.sim_run_id = v_run.sim_run_id
           AND l3.duration_basis->>'kind' = 'travel'
           AND l3.status NOT IN ('done','amended','skipped')),
      'closed_this_run', (
        SELECT count(*) FROM ottoq_itinerary_legs l4
         WHERE l4.sim_run_id = v_run.sim_run_id
           AND l4.duration_basis->>'kind' = 'travel'
           AND l4.status = 'done'),
      'median_deviation_s', (
        SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY l5.deviation_s)::numeric, 1)
          FROM ottoq_itinerary_legs l5
         WHERE l5.sim_run_id = v_run.sim_run_id
           AND l5.duration_basis->>'kind' = 'travel'
           AND l5.deviation_s IS NOT NULL)),

    'fleet', jsonb_build_object(
      'counts', (
        SELECT jsonb_object_agg(state, n) FROM (
          SELECT current_state::text AS state, COUNT(*) AS n
            FROM vehicles WHERE category = 'autonomous' AND home_depot_id = v_depot
           GROUP BY current_state
        ) c
      ),
      'total', (SELECT COUNT(*) FROM vehicles WHERE category = 'autonomous' AND home_depot_id = v_depot),
      'vehicles', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'id', v.id, 'av_id', v.av_api_vehicle_id, 'make', v.make,
          'platform', v.platform, 'state', v.current_state,
          'soc', ROUND(v.current_soc::numeric, 1), 'stall_id', v.current_stall_id,
          -- VISIT WORKFLOW. What OTTO-Q decided this car needs THIS visit, and
          -- how far through it the car is. NULL when there is no open visit for
          -- this run — the renderer must show that as "no workflow published",
          -- never as an empty checklist meaning "nothing needed".
          -- Selection mirrors ottoq_mark_visit_atoms_done (open/in_progress,
          -- newest first) and is additionally scoped to THIS run so a snapshot
          -- of a finished run can never borrow a live run's workflow.
          'visit', vn.card
        ) ORDER BY v.av_api_vehicle_id)
        FROM vehicles v
        LEFT JOIN LATERAL (
          SELECT jsonb_build_object(
            'visit_id',       n.visit_id,
            'visit_status',   n.status,
            'archetype',      n.archetype,
            'urgency',        n.urgency,
            'arrived_at',     n.arrived_at,
            'target_soc',     n.target_soc,
            -- SoC the car ENTERED on, stamped by the needs generator.
            'soc_at_arrival', CASE WHEN n.meta->>'soc_at_arrival' ~ '^-?[0-9]+(\.[0-9]+)?$'
                                   THEN (n.meta->>'soc_at_arrival')::numeric END,
            -- OTTO-Q's OWN charge estimate, lifted from the charge atom, not a
            -- re-derivation. NULL when this visit has no charge atom.
            'est_charge_min', (
              SELECT CASE WHEN ca.value->>'est_min' ~ '^[0-9]+(\.[0-9]+)?$'
                          THEN round((ca.value->>'est_min')::numeric)::int END
                FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) ca
               WHERE ca.value->>'svc' = 'charge'
               LIMIT 1),
            -- THE BULLET LIST, in the order OTTO-Q wrote it. An atom with no
            -- status key reads 'pending' — the same COALESCE decide_tick uses.
            -- est_min is regex-guarded before its cast so one malformed atom
            -- cannot abort the whole snapshot.
            'atoms', COALESCE((
              SELECT jsonb_agg(jsonb_build_object(
                       'svc',     a.value->>'svc',
                       'status',  lower(COALESCE(a.value->>'status','pending')),
                       'must_do', COALESCE((a.value->>'must_do')::boolean, false),
                       -- 0512 (G236): who performed it (charger_sensors; absent for a technician), whether it waits
                       -- on the triage check's verdict, and the verdict once given
                       'performed_by', a.value->>'performed_by',
                       'awaiting_triage', COALESCE((a.value->>'confirm_required')::boolean, false)
                                          AND lower(COALESCE(a.value->>'status','pending')) = 'pending',
                       'triage_verdict', a.value->>'triage_verdict',
                       'est_min', CASE WHEN a.value->>'est_min' ~ '^[0-9]+(\.[0-9]+)?$'
                                       THEN (a.value->>'est_min')::numeric END)
                     ORDER BY a.ord)
                FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb))
                     WITH ORDINALITY AS a(value, ord)
            ), '[]'::jsonb)
          ) AS card
            FROM ottoq_visit_needs n
           WHERE n.vehicle_id = v.id
             AND n.sim_run_id = v_run.sim_run_id
             AND n.status IN ('open','in_progress')
           ORDER BY n.created_at DESC
           LIMIT 1
        ) vn ON TRUE
        WHERE v.category = 'autonomous' AND v.home_depot_id = v_depot
      ), '[]'::jsonb)
    ),

    -- Live stall status only (geometry comes from layout, cached once)
    -- 0011-TETHER: 'tethered' is what lets the cockpit draw a CONNECTED CABLE. The car is
    -- no longer charging and no longer points at the stall, so without this flag the
    -- renderer has nothing to distinguish "robot still mated" from "stall simply busy".
    -- 'tether_until' is the sim-clock demate deadline, so the arm retract can be animated
    -- against the same clock the legs use. The LEFT JOIN is filtered on v_clock, so an
    -- expired tether reads as false even in the beat before the sweep clears it.
    -- The status filter gains an OR: a tethered stall must stay in the payload even if
    -- something flips its status to 'available' mid-window, or the cable would vanish.
    'stalls_status', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', st.id,
        -- 0612: a stall whose charger is Faulted reads 'faulted' until the drawn repair ends, so the twin draws it down
        -- and its assignment pool drops it. The engine's own candidate source refuses it already (0372).
        'status', CASE WHEN oc.station_state = 'Faulted' THEN 'faulted' ELSE st.status::text END,
        'vehicle_id', st.current_vehicle_id,
        'charger_state', oc.station_state,
        'fault_code', CASE WHEN oc.station_state = 'Faulted' THEN oc.last_fault_code END,
        'fault_until', CASE WHEN oc.station_state = 'Faulted' THEN oc.station_state_changed_at
                              + ((oc.last_fault_payload ->> 'repair_minutes')::numeric || ' minutes')::interval END,
        -- WHO the stall is held for, so the renderer can drive the car to the
        -- stall OTTO-Q actually chose instead of picking one itself. Without
        -- this the cockpit knew only that a stall was 'reserved' and fell back
        -- to its own nearest-the-gate pool, which is the south perimeter — so a
        -- car parked on the ring while a short-term spot sat held for it.
        -- Scoped to LIVE reservations against the SIM clock, which is the clock
        -- ottoq_reserve_stall stamps the expiry in. An expired hold is not an
        -- instruction.
        'reserved_by', CASE WHEN st.reservation_expires_at IS NULL
                                OR st.reservation_expires_at > v_clock
                           THEN st.reserved_by END,
        'reserved_until', st.reservation_expires_at,
        'tethered', (tv.id IS NOT NULL),
        'tether_until', tv.robotic_tether_until,
        -- WHICH WAY the robot is going, and where it has got to. 'tethered' alone
        -- cannot distinguish an arm reaching in from an arm pulling out, and the
        -- renderer has to animate those in opposite directions.
        'tether_direction', tv.robotic_tether_direction,
        'tether_phase', tv.robotic_tether_phase
      ))
      FROM stalls st
      LEFT JOIN public.ottoq_ocpp_chargers oc ON oc.charger_id = st.ocpp_charger_id   -- 0612
      LEFT JOIN vehicles tv
        ON tv.robotic_tether_stall_id = st.id
       AND tv.robotic_tether_until IS NOT NULL
       AND tv.robotic_tether_until > v_clock
      WHERE st.depot_id = v_depot
        AND (st.status::text <> 'available'       -- only occupied/charging/faulted (light payload)
             OR oc.station_state = 'Faulted'      -- 0612: ...plus any stall whose charger is down
             OR tv.id IS NOT NULL                 -- ...plus any stall a robot is still holding
             OR (st.reserved_by IS NOT NULL       -- ...plus any stall HELD for an inbound car,
                 AND (st.reservation_expires_at IS NULL
                      OR st.reservation_expires_at > v_clock)))  -- which is usually still 'available'
    ), '[]'::jsonb),

    'energy', (
      SELECT jsonb_build_object(
        'grid_import_kw', se.grid_import_kw, 'grid_export_kw', se.grid_export_kw,
        'solar_kw', se.solar_generation_kw, 'bess_output_kw', se.bess_output_kw,
        'ev_charging_kw', se.total_ev_charging_kw, 'building_kw', se.building_load_kw,
        'peak_15min_kw', se.peak_demand_kw_15min,
        'tariff', se.current_tariff_label, 'rate_per_kwh', se.current_rate_per_kwh,
        'at', se.timestamp
      )
      FROM site_energy_snapshots se WHERE se.depot_id = v_depot
        AND se.sim_run_id = v_run.sim_run_id
        AND se.timestamp <= v_clock
        AND se.timestamp >= v_run.sim_clock_start   -- scope to THIS run's sim-time window
      ORDER BY se.timestamp DESC LIMIT 1
    ),

    'bess', (
      SELECT jsonb_build_object(
        'soc_pct', b.current_soc_pct, 'power_kw', b.current_power_kw,
        'state', b.current_state, 'temp_c', b.current_temperature_c,
        'soh_pct', b.current_soh_pct
      )
      FROM ottoq_bess_units b WHERE b.depot_id = v_depot LIMIT 1
    ),

    'weather', (
      SELECT jsonb_build_object(
        'temp_c', w.ambient_temp_c, 'cloud_pct', w.cloud_cover_pct,
        'conditions', w.conditions_label, 'precip', w.precip_state,
        'ghi_wm2', w.ghi_wm2, 'wind_kmh', w.wind_speed_kmh,
        'solar_elev_deg', w.solar_elevation_deg, 'at', w.sim_clock_at,
        'humidity_pct', w.relative_humidity_pct
      )
      FROM ottoq_weather_snapshots w WHERE w.sim_run_id = p_sim_run_id
      ORDER BY w.sim_clock_at DESC, w.snapshot_id DESC  /* 0134 */ LIMIT 1
    ),

    'grid', (
      SELECT jsonb_build_object(
        'lmp_usd_mwh', g.lmp_usd_per_mwh, 'tariff', g.current_tariff_label,
        'carbon_gco2_kwh', g.carbon_intensity_gco2_per_kwh,
        'voltage_status', g.voltage_status, 'frequency_hz', g.frequency_hz,
        'reserve_margin_pct', g.reserve_margin_pct,
        'dr_active', (g.active_dr_call_id IS NOT NULL),
        'dr_cap_kw', g.dr_required_load_cap_kw, 'at', g.sim_clock_at
      )
      FROM ottoq_grid_snapshots g WHERE g.sim_run_id = p_sim_run_id
      ORDER BY g.sim_clock_at DESC LIMIT 1
    ),

    'counters', jsonb_build_object(
      'dispatches_active', (SELECT COUNT(*) FROM ottoq_vehicle_dispatches
                             WHERE sim_run_id = p_sim_run_id AND status IN ('active','returning')),
      'dispatches_total',  (SELECT COUNT(*) FROM ottoq_vehicle_dispatches WHERE sim_run_id = p_sim_run_id),
      'telemetry_packets', (SELECT COUNT(*) FROM ottoq_telemetry_packets WHERE sim_run_id = p_sim_run_id),
      'charge_sessions',   (SELECT COUNT(*) FROM ocpp_sessions cs WHERE cs.sim_run_id = p_sim_run_id),
      'events_total',      (SELECT COUNT(*) FROM ottoq_events WHERE sim_run_id = p_sim_run_id),
      'open_incidents',    (SELECT COUNT(*) FROM ottoq_vehicle_incidents
                             WHERE sim_run_id = p_sim_run_id AND resolution_status = 'open')
    ),

    'recent_events', COALESCE((
      SELECT jsonb_agg(e) FROM (
        SELECT jsonb_build_object(
          'type', event_type, 'severity', severity,
          'at', occurred_at, 'entity', entity_type,
          'payload', payload
        ) AS e
        FROM ottoq_events
        WHERE sim_run_id = p_sim_run_id
          AND event_type NOT IN (
            'twin.bess_dispatch','twin.weather_tick','twin.solar_tick','twin.grid_tick',
            'twin.sim_tick_advanced','twin.telemetry_emitted','twin.bess_soh_degradation'
          )
        ORDER BY occurred_at DESC LIMIT 15
      ) sub
    ), '[]'::jsonb),

    -- THE ARM CONTRACT. armStateMachine.ts in ottoyarddepot-sim used to DEFINE
    -- these numbers; it now READS them here, so retuning the arm is one edit to
    -- ottoq_policy_params and both worlds move together. demate_seconds is what
    -- OTTO-Q reserves the plug for; connect_seconds is the inbound mate window.
    -- SCALE AND UNITS, so a renderer never has to guess them. See
    -- the_site_geometry_contract_has_one_home.
    'geometry', public.ottoq_site_geometry(p_sim_run_id),
    'arm', jsonb_build_object(
      'timings', public.ottoq_arm_timings(p_sim_run_id),
      -- REGISTRATION ACCURACY. Millimetres between where the arm believed the
      -- inlet was and where it actually was, and how often that was close
      -- enough on the first reach. Empty reads as "nothing measured", never as
      -- a perfect score.
      'accuracy', twin.ottoq_arm_accuracy(p_sim_run_id),
      -- THE INBOUND HALF, which the cockpit could not see at all before: the arm
      -- reaching, aligning, inserting and latching, plus any retry it is on.
      -- Open cycles only — a closed one is history and belongs in the event log.
      'cycles', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'cycle_id', ac.cycle_id, 'stall_id', ac.stall_id, 'vehicle_id', ac.vehicle_id,
          'direction', ac.direction, 'phase', ac.phase,
          'phase_deadline', ac.phase_deadline, 'started_at', ac.started_at,
          'retry_count', ac.retry_count))
          FROM twin.arm_cycles ac
         WHERE ac.sim_run_id = p_sim_run_id AND ac.ended_at IS NULL
      ), '[]'::jsonb)),

    'variability', COALESCE((
      SELECT knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id
    ), '{}'::jsonb)

  ) INTO v_out;

  RETURN v_out;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.ottoq_depot_cards(p_depot_id uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
WITH run AS (
  SELECT sim_run_id, sim_clock_current, status AS run_status
  FROM ottoq_sim_runs
  WHERE depot_id = p_depot_id
    AND status IN ('running','paused')
  ORDER BY started_at DESC
  LIMIT 1
),
veh AS (
  SELECT v.id, v.display_name, v.make, v.model,
         v.fleet_operator_id, f.name AS operator_name,
         v.current_state::text AS state, v.current_soc, v.target_soc,
         v.current_stall_id
  FROM vehicles v
  LEFT JOIN fleet_operators f ON f.id = v.fleet_operator_id
  WHERE v.current_depot_id = p_depot_id
    AND (p_fleet_operator_id IS NULL OR v.fleet_operator_id = p_fleet_operator_id)
),
card AS (
  SELECT vh.id AS vehicle_id,
         (SELECT to_jsonb(n) - 'meta'
            FROM ottoq_visit_needs n
           WHERE n.vehicle_id = vh.id AND n.sim_run_id = r.sim_run_id
           ORDER BY n.created_at DESC LIMIT 1)               AS need,
         (SELECT i.itinerary_id
            FROM ottoq_vehicle_itineraries i
           WHERE i.vehicle_id = vh.id AND i.sim_run_id = r.sim_run_id
             AND i.status = 'active'
           ORDER BY i.sim_created_at DESC LIMIT 1)           AS itinerary_id
  FROM veh vh CROSS JOIN run r
),
seq AS (
  SELECT c.vehicle_id,
         jsonb_agg(s.step ORDER BY s.ord) AS steps
  FROM card c
  CROSS JOIN LATERAL (
    (SELECT l.seq AS ord, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'atom', l.duration_basis->>'atom', 'status', 'done',
        /* 1.5 (0592): the station this step is at */
        'to_stall_code', (SELECT st.stall_code FROM stalls st WHERE st.id = l.to_stall_id),
        'to_stall_kind', (SELECT st.stall_kind::text FROM stalls st WHERE st.id = l.to_stall_id),
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        'actual_start', l.actual_start_sim,  'actual_end', l.actual_end_sim) AS step
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'done'
      ORDER BY l.seq DESC LIMIT 12)
    UNION ALL
    (SELECT l.seq, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'atom', l.duration_basis->>'atom', 'status', 'current',
        'to_stall_code', (SELECT st.stall_code FROM stalls st WHERE st.id = l.to_stall_id),
        'to_stall_kind', (SELECT st.stall_kind::text FROM stalls st WHERE st.id = l.to_stall_id),
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        'actual_start', l.actual_start_sim,
        /* 0507 (G232), 0509 (G238): when the step will end. A running charge ends when the charge physics says it
           will from the car's SoC now; any other step when it started plus its planned duration. */
        'expected_end', CASE WHEN eta.min_left IS NOT NULL
                             THEN (SELECT sim_clock_current FROM run) + make_interval(secs => eta.min_left * 60)
                             WHEN l.actual_start_sim IS NOT NULL AND l.planned_duration_s IS NOT NULL
                             THEN l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                             ELSE l.planned_end_sim END,
        'eta_source', CASE WHEN eta.min_left IS NOT NULL THEN 'charge_physics' ELSE 'plan' END,
        'over_plan_min', CASE WHEN l.actual_start_sim IS NOT NULL AND l.planned_duration_s IS NOT NULL
                               AND (SELECT sim_clock_current FROM run) > l.actual_start_sim + make_interval(secs => l.planned_duration_s)
                              THEN floor(EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run)
                                     - (l.actual_start_sim + make_interval(secs => l.planned_duration_s)))) / 60)::int END,
        'progress_pct', CASE WHEN eta.min_left IS NOT NULL THEN
             LEAST(100, GREATEST(0, round(
               100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                     / NULLIF(EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                              + eta.min_left * 60, 0))))
           ELSE LEAST(100, GREATEST(0, round(
           100.0 * EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.actual_start_sim))
                 / NULLIF(l.planned_duration_s,0)))) END)
       FROM ottoq_itinerary_legs l
       /* 0509 (G238): the minutes left on the car's running charge. The planner's charge model from the SoC now to the
          target, scaled by how this session has actually run against the same model: the minutes it has taken over
          the minutes the model gives for the SoC it has gained (1 until it has gained 2 points; held in [0.5, 5]). */
       LEFT JOIN LATERAL (
         SELECT public.ottoq_estimate_charge_minutes(
                  x.soc_now, x.target, x.charger_kw, x.inlet_kw, x.pack_kwh, x.temp_c, x.soh, x.ratio) AS min_left
           FROM (
             SELECT y.*,
                    CASE WHEN y.soc_now - y.soc_start >= 2 AND y.model_min_done > 0
                         THEN LEAST(5, GREATEST(0.5, y.elapsed_min / y.model_min_done)) ELSE 1 END AS ratio
               FROM (
                 SELECT v.current_soc AS soc_now, os.soc_start,
                        LEAST(COALESCE(v.target_soc, public.ottoq_default_target_soc()),
                              public.ottoq_target_soc_cap(st.stall_type::text, os.started_at)) AS target,
                        ch.max_kw AS charger_kw, v.inlet_max_kw AS inlet_kw, v.battery_capacity_kwh AS pack_kwh,
                        COALESCE(os.ambient_temp_c, 22) + 5 AS temp_c,
                        COALESCE((v.config->>'battery_soh_pct')::numeric, 95) AS soh,
                        EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - os.started_at)) / 60 AS elapsed_min,
                        public.ottoq_estimate_charge_minutes(os.soc_start, v.current_soc, ch.max_kw, v.inlet_max_kw,
                          v.battery_capacity_kwh, COALESCE(os.ambient_temp_c, 22) + 5,
                          COALESCE((v.config->>'battery_soh_pct')::numeric, 95), 1.0) AS model_min_done
                   FROM ocpp_sessions os
                   JOIN stalls st ON st.id = os.stall_id
                   JOIN ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
                   JOIN vehicles v ON v.id = os.vehicle_id
                  WHERE l.leg_type IN ('charge_dcfc','charge_l2')
                    AND os.vehicle_id = l.vehicle_id AND os.sim_run_id = l.sim_run_id AND os.status = 'active'
                  ORDER BY os.started_at DESC LIMIT 1) y) x) eta ON true
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'active'
      ORDER BY l.seq LIMIT 1)
    UNION ALL
    (SELECT l.seq, jsonb_build_object(
        'seq', l.seq, 'leg_type', l.leg_type, 'atom', l.duration_basis->>'atom', 'status', 'upcoming',
        'to_stall_code', (SELECT st.stall_code FROM stalls st WHERE st.id = l.to_stall_id),
        'to_stall_kind', (SELECT st.stall_kind::text FROM stalls st WHERE st.id = l.to_stall_id),
        'planned_start', l.planned_start_sim, 'planned_end', l.planned_end_sim,
        /* 0506 (G232): a planned start already behind the run's clock is overdue, not ahead */
        'overdue_min', CASE WHEN l.planned_start_sim < (SELECT sim_clock_current FROM run)
                            THEN floor(EXTRACT(EPOCH FROM ((SELECT sim_clock_current FROM run) - l.planned_start_sim)) / 60)::int
                       END)
       FROM ottoq_itinerary_legs l
      WHERE l.itinerary_id = c.itinerary_id AND l.status = 'planned'
      ORDER BY l.seq LIMIT 5)
  ) s(ord, step)
  WHERE c.itinerary_id IS NOT NULL
  GROUP BY c.vehicle_id
),
--: 0460 — reservations of THIS run, for the vehicles in scope.
bk AS (
  SELECT b.booking_id, b.vehicle_id, b.purpose, b.state,
         lower(b.during) AS starts_at, upper(b.during) AS ends_at,
         b.why, b.need_atom, b.booked_by,
         st.stall_code, st.stall_kind::text AS stall_kind
    FROM ottoq_stall_bookings b
    JOIN run r ON r.sim_run_id = b.sim_run_id
    JOIN veh vh ON vh.id = b.vehicle_id
    LEFT JOIN stalls st ON st.id = b.stall_id
   WHERE b.state IN ('held','active')
),
bk_json AS (
  SELECT bk.vehicle_id,
         jsonb_agg(jsonb_build_object(
           'booking_id', bk.booking_id, 'purpose', bk.purpose, 'state', bk.state,
           'stall_code', bk.stall_code, 'stall_kind', bk.stall_kind,
           'starts_at', bk.starts_at, 'ends_at', bk.ends_at,
           'why', bk.why, 'need_atom', bk.need_atom, 'booked_by', bk.booked_by)
           ORDER BY bk.starts_at NULLS LAST) AS items
    FROM bk GROUP BY bk.vehicle_id
),
--: 1.5 (0592) — this visit's bookings OTTO-Q replaced, or let go before use (not by the run stopping).
chg AS (
  SELECT x.vehicle_id,
         jsonb_agg(jsonb_build_object(
           'purpose', x.purpose, 'need_atom', x.need_atom, 'stall_code', x.stall_code, 'stall_kind', x.stall_kind,
           'starts_at', x.starts_at, 'ends_at', x.ends_at, 'state', x.state, 'release_reason', x.release_reason,
           'booked_at', x.booked_at_sim) ORDER BY x.booked_at_sim, x.booking_id) AS items
    FROM (
      SELECT b.vehicle_id, b.booking_id, b.purpose, b.need_atom, b.state, b.release_reason, b.booked_at_sim,
             lower(b.during) AS starts_at, upper(b.during) AS ends_at,
             st.stall_code, st.stall_kind::text AS stall_kind,
             row_number() OVER (PARTITION BY b.vehicle_id ORDER BY b.booked_at_sim DESC, b.booking_id DESC) AS rn
        FROM card c
        JOIN run r ON true
        JOIN ottoq_stall_bookings b ON b.sim_run_id = r.sim_run_id AND b.vehicle_id = c.vehicle_id
                                   AND b.visit_id = (c.need->>'visit_id')::uuid
        LEFT JOIN stalls st ON st.id = b.stall_id
       WHERE b.state = 'superseded'
          OR (b.state = 'released' AND COALESCE(b.release_reason, '') NOT LIKE '%run_stopped%')
    ) x
   WHERE x.rn <= 12
   GROUP BY x.vehicle_id
),
--: 0460 — the newest decision of THIS run per vehicle in scope.
dec AS (
  SELECT DISTINCT ON (d.entity_id)
         d.entity_id AS vehicle_id,
         jsonb_build_object(
           'at',        d.sim_clock,
           'action',    COALESCE(d.resolved_action_context, d.action_context),
           'verb',      COALESCE(d.enacted_action->>'verb', d.proposed_action->>'verb'),
           'outcome',   d.outcome_status,
           'engine',    d.l2_engine,
           'rationale', COALESCE(d.enacted_action->'rationale', d.proposed_action->'rationale')) AS last_decision
    FROM ottoq_decisions d
    JOIN run r ON r.sim_run_id = d.sim_run_id
   WHERE d.entity_type = 'vehicle'
     AND d.entity_id IN (SELECT id FROM veh)
   ORDER BY d.entity_id, d.decision_seq DESC
)
SELECT jsonb_build_object(
  'endpoint', 'ottoq.depot_cards',
  'contract_version', '1.5',
  'depot_id', p_depot_id,
  'fleet_operator_id', p_fleet_operator_id,
  'sim_run_id', (SELECT sim_run_id FROM run),
  'run_status', (SELECT run_status FROM run),
  'sim_clock',  (SELECT sim_clock_current FROM run),
  'vehicles', COALESCE((
     SELECT jsonb_agg(jsonb_build_object(
       'vehicle_id', vh.id,
       'display_name', vh.display_name,
       'oem', vh.make, 'model', vh.model,
       'operator', jsonb_build_object('id', vh.fleet_operator_id, 'name', vh.operator_name),
       'state', vh.state, 'soc', vh.current_soc, 'target_soc', vh.target_soc,
       'stall', CASE WHEN vh.current_stall_id IS NULL THEN NULL ELSE (
          SELECT jsonb_build_object('id', st.id, 'code', st.stall_code, 'kind', st.stall_kind::text)
            FROM stalls st WHERE st.id = vh.current_stall_id) END,
       'reservations', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN '[]'::jsonb
                            ELSE COALESCE(bj.items, '[]'::jsonb) END,
       'last_decision', dc.last_decision,
       'plan_changes', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN '[]'::jsonb
                            ELSE COALESCE(ch.items, '[]'::jsonb) END,
       'card', CASE WHEN (SELECT sim_run_id FROM run) IS NULL THEN NULL ELSE jsonb_build_object(
          'urgency',         c.need->>'urgency',
          'dispatch_due_at', c.need->>'dispatch_due_at',
          'needs',           COALESCE((
                               SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                 'svc', a->>'svc', 'status', a->>'status',
                                 'done_at', a->>'done_at', 'must_do', (a->>'must_do')::boolean,
                                 /* 1.4 (0512, G236): who did it, whether it waits on the triage's verdict, the verdict */
                                 'performed_by', a->>'performed_by',
                                 'awaiting_triage', CASE WHEN COALESCE((a->>'confirm_required')::boolean, false)
                                                          AND COALESCE(a->>'status','pending') = 'pending' THEN true END,
                                 'triage_verdict', a->>'triage_verdict')))
                               FROM jsonb_array_elements(c.need->'atoms') a), '[]'::jsonb),
          'steps',           COALESCE(s.steps,'[]'::jsonb),
          'current_step',    (SELECT st FROM jsonb_array_elements(COALESCE(s.steps,'[]'::jsonb)) st
                               WHERE st->>'status'='current' LIMIT 1),
          'next_step',       (SELECT st FROM jsonb_array_elements(COALESCE(s.steps,'[]'::jsonb)) st
                               WHERE st->>'status'='upcoming' LIMIT 1)
       ) END
     ) ORDER BY vh.display_name)
     FROM veh vh
     LEFT JOIN card c     ON c.vehicle_id  = vh.id
     LEFT JOIN seq  s     ON s.vehicle_id  = vh.id
     LEFT JOIN bk_json bj ON bj.vehicle_id = vh.id
     LEFT JOIN dec  dc    ON dc.vehicle_id = vh.id
     LEFT JOIN chg  ch    ON ch.vehicle_id = vh.id
  ), '[]'::jsonb),
  'reservation_ledger', COALESCE((
     SELECT jsonb_object_agg(x.state, x.n) FROM (
       SELECT b.state, count(*) AS n
         FROM ottoq_stall_bookings b
         JOIN run r ON r.sim_run_id = b.sim_run_id
         JOIN veh vh ON vh.id = b.vehicle_id
        GROUP BY b.state) x
  ), '{}'::jsonb)
);
$function$
;
