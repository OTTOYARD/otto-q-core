-- tests/fixtures/charge_batch_order_stub.sql: just enough of the engine for db/migrations/0570 to apply and for its batch
-- order to be EXECUTED. ottoq_l2_optimize_assignments below is the live function, its source byte for byte as measured on
-- 2026-09-29 (md5 653762a5a7f1445c8f65c763779137db), so 0570's P1 premise and both of its patches meet the real text.
-- Everything else is a stub shaped like the columns that function and 0570 read.

CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS twin;
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, home_depot_id uuid NOT NULL, category text NOT NULL DEFAULT 'autonomous',
  current_state text NOT NULL DEFAULT 'arrived_at_gate', current_soc numeric NOT NULL, target_soc numeric,
  inlet_type text, inlet_max_kw numeric, fleet_operator_id uuid, battery_capacity_kwh numeric);
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, station_state text NOT NULL DEFAULT 'Available',
  last_heartbeat_at timestamptz NOT NULL);
CREATE TABLE public.stalls (
  id uuid PRIMARY KEY, depot_id uuid NOT NULL, stall_type text NOT NULL, stall_code text NOT NULL,
  current_vehicle_id uuid, reserved_by uuid, reservation_expires_at timestamptz, ocpp_charger_id uuid,
  connector_type text, supported_inlet_types text[], connector_max_kw numeric, distance_from_entrance numeric);
CREATE TABLE public.ottoq_external_proposals (
  proposal_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, sim_run_id uuid, depot_id uuid, action_context text,
  entity_type text, entity_id uuid, proposal jsonb, source text, status text, created_at timestamptz, expires_at timestamptz);
CREATE TABLE public.ottoq_proposer_precedence (source text PRIMARY KEY, greedy_yields boolean NOT NULL);
INSERT INTO public.ottoq_proposer_precedence VALUES ('cuopt', true), ('greedy_constrained', false);
CREATE TABLE public.ottoq_visit_needs (
  visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL, sim_run_id uuid, status text NOT NULL,
  urgency text, dispatch_due_at timestamptz, target_soc numeric, created_at timestamptz NOT NULL DEFAULT now(),
  visit_key text NOT NULL DEFAULT 'v');
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid NOT NULL);
CREATE TABLE public.ottoq_policy_param_catalog (
  param_key text PRIMARY KEY, min_value numeric, max_value numeric, default_value numeric, min_exclusive numeric,
  max_exclusive numeric, agent_writable boolean NOT NULL DEFAULT false, agent_min_value numeric, agent_max_value numeric,
  agent_max_drift_pct numeric, affects text, description text);
CREATE TABLE public.ottoq_policy_params (
  scope_type text NOT NULL, scope_id uuid NOT NULL, param_key text NOT NULL, param_value numeric NOT NULL, updated_by text,
  PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL, note text, classified_at timestamptz);
CREATE TABLE public.ottoq_schema_snapshots (label text, object_kind text, schema_name text, object_name text,
  definition text, def_md5 text);

-- the in-flight probe (0513), driven by a table so a test can make a pair be running
CREATE TABLE public.stub_in_flight (n int NOT NULL);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean) RETURNS integer LANGUAGE sql STABLE AS
  $$ SELECT n FROM public.stub_in_flight $$;

-- rule 9's one answer (0539), per car from a table so a test can give an owner a lower limit
CREATE TABLE public.stub_owner_target (vehicle_id uuid PRIMARY KEY, pct numeric NOT NULL);
CREATE FUNCTION public.ottoq_default_target_soc() RETURNS numeric LANGUAGE sql IMMUTABLE AS $$ SELECT 100::numeric $$;
CREATE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_as_of timestamptz) RETURNS numeric
  LANGUAGE sql STABLE AS
  $$ SELECT COALESCE((SELECT pct FROM public.stub_owner_target WHERE vehicle_id = p_vehicle_id), 100::numeric) $$;

-- the calendar gate the optimizer asks (0495): yes, unless a test has promised the stall to someone else
CREATE TABLE public.stub_refused (vehicle_id uuid, stall_id uuid);
CREATE FUNCTION ottoq.ottoq_validate_assignment(p_vehicle uuid, p_stall uuid, p_verb text, p_at timestamptz, p_run uuid)
  RETURNS jsonb LANGUAGE sql STABLE AS
  $$ SELECT jsonb_build_object('ok', NOT EXISTS (SELECT 1 FROM public.stub_refused r
                                                  WHERE r.vehicle_id = p_vehicle AND r.stall_id = p_stall)) $$;

-- the dial reader, the live source's tiers (run, then depot, then global), without 0533's read witness
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
  LANGUAGE plpgsql STABLE AS $$
DECLARE v numeric; v_depot uuid;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END $$;

-- the live batch optimizer, byte for byte
CREATE FUNCTION public.ottoq_l2_optimize_assignments(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_n int := 0; v_veh RECORD; v_stall_id uuid; v_stall_type text; v_conn_max numeric;
  v_used uuid[] := ARRAY[]::uuid[];
BEGIN
  -- fresh start each tick: clear this run's prior local proposals (avoid stale accumulation)
  DELETE FROM ottoq_external_proposals
   WHERE sim_run_id = p_sim_run_id AND source = 'greedy_constrained' AND action_context = 'stall_assignment';

  FOR v_veh IN
    SELECT v.id, v.current_soc, v.target_soc, v.inlet_type, v.inlet_max_kw, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate' AND v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 0.5
       -- FR-3: yield to a fresh cuOpt proposal for this vehicle (cuOpt owns it this tick)
       AND NOT EXISTS (
         SELECT 1 FROM ottoq_external_proposals p
          WHERE p.sim_run_id = p_sim_run_id AND p.action_context = 'stall_assignment'
            AND p.entity_type = 'vehicle' AND p.entity_id = v.id
            -- 0259: yield to every source that DECLARES greedy_yields, not to one
            -- name. Seed: cuopt only, so this is FR-3 unchanged until a row says otherwise.
            AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                              WHERE pp.greedy_yields)
            AND p.status = 'pending'
            AND COALESCE(p.expires_at, p.created_at + interval '35 minutes') >= now())
     ORDER BY v.current_soc ASC, v.id              -- urgency: most depleted vehicle picks first
  LOOP
    SELECT s.id, s.stall_type, s.connector_max_kw
      INTO v_stall_id, v_stall_type, v_conn_max
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND NOT (s.id = ANY(v_used))
       /* 0067: SIM domain. reservation_expires_at is stamped by ottoq_reserve_stall
          from the sim clock at every call site; comparing it to the REAL clock only worked while
          the cert's sim clock equalled the arming minute. Since 0065 pinned that clock the
          two domains sit up to ~22h apart and an expired sim reservation read as live
          forever, suppressing capacity (conservative direction -- it never stole a stall). */
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_sim_clock)
       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= p_sim_clock - INTERVAL '90 seconds'
       /* 0495 (G226): the calendar is a gate here too. This pick read the pointer and the charger only, so a
          charger promised to an arriving car looked free, and the charge step honoured the proposal and was refused
          at the emission gate (every refusal of its begin_charge on the canon under 0494). A candidate is now a
          charger the gate accepts for this car at this clock, as 0494 made the per-car proposer ask. */
       AND COALESCE((ottoq.ottoq_validate_assignment(v_veh.id, s.id, 'begin_charge', p_sim_clock, p_sim_run_id)->>'ok')::boolean, false)
       AND ( v_veh.inlet_type IS NULL
          OR s.connector_type = v_veh.inlet_type
          OR (s.connector_type = 'Multi' AND v_veh.inlet_type = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
          OR (s.connector_type = 'NACS'  AND v_veh.inlet_type IN ('NACS','Tesla_Proprietary')) )
     ORDER BY
       -- DCFC FIRST, L2 OVERFLOW. Lower score wins. The fast plug scores 0 for
       -- every vehicle; L2 carries a penalty large enough that no amount of
       -- distance advantage can outbid a free fast plug. L2 is therefore only
       -- ever chosen when no DCFC stall survives the filters above.
       ( CASE WHEN s.stall_type = 'dcfc' THEN 0
              ELSE ottoq_policy_get(p_sim_run_id, 'l2_overflow_penalty', 100) END )
       + COALESCE(s.distance_from_entrance, 50) * 0.1
     ASC,
       /* 0067: RUN-STABLE TIEBREAK. The score above is byte-identical for two stalls of the
          same type at the same distance, so LIMIT 1 returned heap order. Measured in re-cert
          #19 at tick 10: stalls NASH-L2-STALL-03 and NASH-L2-STALL-29 (both l2, Multi,
          distance 176) were handed to the same two vehicles in OPPOSITE order across two
          same-seed arms, and by tick 18 fifty vehicles had diverged. This depot has four such
          (type, distance) pairs, all l2 and none dcfc -- which is why #19's DCFC session count
          matched exactly (18/18) while the residue lived entirely in the L2 path. The score
          still dominates, so DCFC-first and the L2 overflow penalty are unaffected: this only
          decides among stalls that were already indistinguishable. stall_code is the idiom
          ottoq.ottoq_stall_free_between already uses; s.id closes the order absolutely. */
       s.distance_from_entrance ASC, s.stall_code ASC, s.id ASC
     LIMIT 1;

    IF v_stall_id IS NULL THEN CONTINUE; END IF;
    v_used := array_append(v_used, v_stall_id);

    INSERT INTO ottoq_external_proposals
      (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal, source, status, created_at, expires_at)
    VALUES (p_sim_run_id, p_depot_id, 'stall_assignment', 'vehicle', v_veh.id,
      jsonb_build_object('abstain', false, 'resolved_action_context', 'stall_assignment', 'verb', 'assign_stall',
        'vehicle_id', v_veh.id, 'stall_id', v_stall_id, 'stall_type', v_stall_type,
        'requested_kw', ROUND((LEAST(COALESCE(v_conn_max,50), COALESCE(v_veh.inlet_max_kw,250))
            * CASE WHEN COALESCE(v_conn_max,50) <= 50 THEN 1.0
                   WHEN v_veh.current_soc < 55 THEN 0.85 WHEN v_veh.current_soc < 75 THEN 0.55 ELSE 0.30 END)::numeric, 1),
        'l2_engine', 'greedy_constrained',
        'rationale', jsonb_build_object('soc', v_veh.current_soc, 'optimizer', 'greedy_constrained', 'inlet', v_veh.inlet_type)),
      'greedy_constrained', 'pending', now(), now() + INTERVAL '120 seconds');
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;
