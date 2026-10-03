-- ============================================================================================================
-- tests/fixtures/owner_agent_stub_engine.sql
--
-- What db/migrations/0605 reads, replaces and patches, loaded AFTER tests/fixtures/agent_gateway_stub_engine.sql
-- (which 0559 and 0560 need) on a throwaway PostgreSQL. NOT the engine, NOT a migration, NEVER applied anywhere real:
-- the guard refuses a database that has ottoq_events or a supabase_migrations schema.
--
--   * COPIED VERBATIM from the live catalog (gxdrcyphqjzjsuhxuqtg, read-only, 2026-10-03 ~01:00 UTC); the test asserts
--     md5(pg_get_functiondef()) of each against the md5 read from the live catalog the same night:
--       public.ottoq_sim_advance_tick_world        5f1cf65bd306f57e338d1f729e63f86a   (0605 patches one line in)
--       public.ottoq_effective_target_soc_at       e937cb1b8ede9f4ba37b17f0291c47ea   (0605 replaces)
--       public.ottoq_departure_clear               1ebf41c502acf3d9eaf1f2aedf2ca1cc   (0605 replaces)
--       public.ottoq_effective_target_soc          93158a2ab19cc8a15da3e043a3051507
--       public.ottoq_default_target_soc            a380d18a6a63d9a956ff3a3841a89b00
--       public.ottoq_vehicle_fault_open            b8149139faa6333a3f329d68f2d0c565
--       public.ottoq_close_run_needs               05ba4e6a825fe7d27a1009fa95b84475
--       public.ottoq_tg_close_run_needs_on_terminal 3fdcdb80d931c3f496e971681426f63e
--       ottoq.ottoq_svc_to_stall_type              06545b6b3bfd2082adc678b146285481
--       ottoq.ottoq_atom_retirable_set             ca6fefa490efbce29c2696a4e55b0382
--       ottoq.ottoq_atom_retirable                 e4bc934bab8659f3804f56a8c0bf55c5
--       ottoq.ottoq_bay_purpose_atoms              0ddc48dd5c1177b1950a13041e5964c1
--     The world step is loaded, patched and checked, never executed here: everything it calls after its first
--     statements is absent on purpose. 0605's own tick step is executed directly.
--   * STUBBED, with the live signature: ottoq_plan_visit_itinerary (records that it was asked), ottoq_record_event
--     (records the event in stub_events, so a test can count them), ottoq_certification_in_flight (0582's stub).
--   * service_cadence_policy carries the live catalog's 16 services (lane, minutes, names, 2026-10-03) and
--     ottoq_fleet_operator_slas the live terms of the three operators seeded here (80-100%, nothing blocked).
-- ============================================================================================================

DO $guard$
BEGIN
  IF to_regclass('public.ottoq_events') IS NOT NULL OR EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'supabase_migrations') THEN
    RAISE EXCEPTION 'owner_agent_stub_engine.sql is a TEST STUB and this looks like a real engine. Refusing.';
  END IF;
  IF to_regclass('public.ottoq_sim_runs') IS NULL THEN
    RAISE EXCEPTION 'load tests/fixtures/agent_gateway_stub_engine.sql first';
  END IF;
END $guard$;

-- ── the columns 0559's stub did not need and 0605 reads ──
ALTER TABLE public.vehicles ADD COLUMN av_api_vehicle_id text, ADD COLUMN config jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN last_state_change timestamptz;
ALTER TABLE public.ottoq_sim_runs ADD COLUMN sim_clock_end timestamptz, ADD COLUMN ended_at timestamptz,
  ADD COLUMN failure_reason text, ADD COLUMN next_tick_due_at timestamptz, ADD COLUMN payload jsonb,
  ADD COLUMN tick_interval_seconds integer DEFAULT 30, ADD COLUMN time_scale numeric DEFAULT 10, ADD COLUMN last_tick_at timestamptz;

-- ── tables ──
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigint GENERATED ALWAYS AS IDENTITY, label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text, taken_at timestamptz DEFAULT now());
CREATE TABLE public.ottoq_event_types_catalog (
  event_type text PRIMARY KEY, category text NOT NULL, description text NOT NULL, payload_schema jsonb, emitter text,
  default_severity text NOT NULL DEFAULT 'info', introduced_in text, deprecated boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_fleet_operator_slas (
  sla_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), fleet_operator_id uuid NOT NULL, contract_reference text,
  effective_from timestamptz NOT NULL, effective_until timestamptz, status text NOT NULL, version integer NOT NULL,
  min_soc_at_deployment_pct numeric, preferred_soc_at_deployment_pct numeric, max_charge_target_pct numeric,
  min_charge_target_pct numeric, required_services_before_deploy text[], blocked_services text[]);
CREATE TABLE public.service_cadence_policy (
  svc text PRIMARY KEY, display_name text, category text, lane text, est_min_default integer, is_active boolean NOT NULL DEFAULT true);
CREATE TABLE public.service_definitions (code text, depot_id uuid, stall_type_required text, is_active boolean);
CREATE TABLE public.ottoq_visit_needs (
  visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL,
  sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id), depot_id uuid, arrived_at timestamptz NOT NULL,
  visit_key text NOT NULL, archetype text, urgency text NOT NULL DEFAULT 'standard', dispatch_due_at timestamptz,
  target_soc numeric, atoms jsonb NOT NULL DEFAULT '[]'::jsonb, status text NOT NULL DEFAULT 'open',
  source text NOT NULL DEFAULT 'twin_generator', meta jsonb, created_at timestamptz NOT NULL DEFAULT now());
CREATE UNIQUE INDEX ottoq_visit_needs_key_idx ON public.ottoq_visit_needs
  (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)));
CREATE TABLE public.ottoq_vehicle_dispatches (
  dispatch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid NOT NULL,
  sim_run_id uuid REFERENCES public.ottoq_sim_runs(sim_run_id), dispatched_at timestamptz NOT NULL, status text NOT NULL DEFAULT 'active');
CREATE TABLE public.stub_events (event_type text, entity_id uuid, payload jsonb, sim_run_id uuid, recorded_at timestamptz DEFAULT clock_timestamp());
CREATE TABLE public.stub_itinerary_calls (sim_run_id uuid, vehicle_id uuid, at_sim timestamptz);
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
  ('public','ottoq_visit_needs','sim_run_id','engine','stub'),
  ('public','ottoq_vehicle_dispatches','sim_run_id','engine','stub'),
  ('public','stub_events','sim_run_id','evidence','stub'),
  ('public','stub_itinerary_calls','sim_run_id','evidence','stub');

-- ── STUBS (live signatures) ──
CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true) RETURNS integer
LANGUAGE sql STABLE AS $$ SELECT CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END $$;
CREATE OR REPLACE FUNCTION public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid DEFAULT NULL::uuid, p_payload jsonb DEFAULT '{}'::jsonb, p_actor_id text DEFAULT NULL::text, p_actor_metadata jsonb DEFAULT '{}'::jsonb, p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_previous_state jsonb DEFAULT NULL::jsonb, p_new_state jsonb DEFAULT NULL::jsonb, p_severity text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_parent_event_id uuid DEFAULT NULL::uuid, p_related_task_id uuid DEFAULT NULL::uuid, p_related_schedule_id uuid DEFAULT NULL::uuid, p_related_decision_id uuid DEFAULT NULL::uuid, p_outcome text DEFAULT NULL::text, p_latency_ms integer DEFAULT NULL::integer, p_ingest_source text DEFAULT 'app'::text, p_signing_key_id text DEFAULT 'system:v1'::text, p_data_source text DEFAULT 'production'::text, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS uuid LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO public.stub_events (event_type, entity_id, payload, sim_run_id) VALUES (p_event_type, p_entity_id, p_payload, p_sim_run_id);
  RETURN gen_random_uuid();
END $f$;
CREATE OR REPLACE FUNCTION public.ottoq_plan_visit_itinerary(p_sim_run_id uuid, p_vehicle uuid, p_clock timestamp with time zone)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'twin', 'ottoq', 'public', 'extensions' AS $f$
BEGIN
  INSERT INTO public.stub_itinerary_calls (sim_run_id, vehicle_id, at_sim) VALUES (p_sim_run_id, p_vehicle, p_clock);
  RETURN 0;
END $f$;

-- ═════════════ VERBATIM COPIES (bodies exactly as pg_get_functiondef printed them, 2026-10-03) ═════════════

CREATE OR REPLACE FUNCTION public.ottoq_default_target_soc()
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  -- THE one answer to "how full is full". Every fallback in the codebase points
  -- here. Takes no run id on purpose: this is the fleet-wide default, and a run or
  -- depot that wants something else sets vehicles.target_soc or the visit's
  -- target_soc, both of which win over this.
  SELECT public.ottoq_policy_get(NULL, 'vehicle_target_soc_default', 100);
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_vehicle_fault_open(p_config jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- 0555 (G290): a car carries a vehicle fault that has not been repaired while config.exception is an object. The fault
  -- handler writes it when the fault is raised; the service bay's repair (fault_repair credited) removes it, and a run's
  -- seed strips it at the start of a run. Nothing else removes it.
  SELECT COALESCE(jsonb_typeof(p_config->'exception') = 'object', false)
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc_at(p_vehicle_id uuid, p_as_of timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0539 (Chase 2026-09-27, CLAUDE.md rule 9): HOW FULL THIS CAR CHARGES, AND IT IS THE OWNER'S ANSWER. The fleet
  -- default (public.ottoq_default_target_soc(), 100) under the owner's contract ceiling
  -- (ottoq_fleet_operator_slas.max_charge_target_pct, 100 in all four contracts). Nothing the depot decides enters it.
  -- A per-vehicle limit an owner sets from an app, verified and confirmed ("that would permanently save to their
  -- vehicle settings, and OTTO-Q would acknowledge that"), is read here when it exists, and no caller changes.
  -- This read vehicles.target_soc first, the engine's own stamp of the car's last plan and not the owner's; then the
  -- contract's PREFERRED deployment SoC (90), the bar for leaving and not a charge target; then 90. It had no caller.
  SELECT LEAST(
    public.ottoq_default_target_soc(),
    COALESCE((SELECT s.max_charge_target_pct FROM ottoq_fleet_operator_slas s
               WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
                 AND s.effective_from <= p_as_of
                 AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
               ORDER BY s.version DESC LIMIT 1), 100))
  FROM vehicles v WHERE v.id = p_vehicle_id;
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_effective_target_soc(p_vehicle_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ottoq_effective_target_soc_at(p_vehicle_id, now());
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_departure_clear(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_need_readiness boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 0543 (CLAUDE.md rule 9, Chase 2026-09-27): a car leaves only when nothing it needs is left. Its charge is at its
  -- effective target - 1 (G244's one rule), and no service on its open visit is open or in progress. With
  -- p_need_readiness the readiness check must be done too (the dispatchers). Without it (the recheck) the readiness
  -- check is left to the staging it is done in. A car with no SoC on record is not clear.
  -- 0555 (G290): and it carries no vehicle fault that has not been repaired. The fault lives in config.exception, which
  -- neither the charge nor the card shows, so Waymo-AV-011 left with a steering/brake fault on 0410's run.
  SELECT COALESCE(v.current_soc >= public.ottoq_effective_target_soc_at(v.id, p_clock) - 1, false)
     AND NOT public.ottoq_vehicle_fault_open(v.config)
     AND NOT EXISTS (
           SELECT 1
             FROM public.ottoq_visit_needs vn
             CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
            WHERE vn.vehicle_id = v.id
              AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              AND vn.status IN ('open', 'in_progress')
              AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')
              AND (p_need_readiness OR a->>'svc' <> 'readiness_check'))
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id;
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_close_run_needs(p_sim_run_id uuid, p_reason text DEFAULT 'run_terminated'::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE n integer;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  UPDATE public.ottoq_visit_needs vn
     SET status = 'superseded',
         meta   = COALESCE(vn.meta,'{}'::jsonb)
                  || jsonb_build_object('closed_by','ottoq_close_run_needs',
                                        'close_reason', p_reason,
                                        'closed_at', now())
   WHERE vn.sim_run_id = p_sim_run_id
     AND vn.status IN ('open','in_progress');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_tg_close_run_needs_on_terminal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE n integer;
BEGIN
  -- No EXCEPTION handler on purpose. A swallowed failure here would silently
  -- restore the exact defect this migration removes: a run reaching terminal
  -- with its needs still open, for the NEXT run to clean up.
  n := public.ottoq_close_run_needs(NEW.sim_run_id, 'run_' || NEW.status);
  RETURN NULL;
END;
$function$
;

CREATE TRIGGER ottoq_sim_runs_close_needs AFTER UPDATE OF status ON public.ottoq_sim_runs FOR EACH ROW WHEN (((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text])) AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text, 'aborted'::text])))) EXECUTE FUNCTION ottoq_tg_close_run_needs_on_terminal();

CREATE OR REPLACE FUNCTION ottoq.ottoq_bay_purpose_atoms(p_purpose text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- MUST MIRROR twin.ottoq_sim_advance_service_flow STEP 1, which is what marks these atoms
  -- done on bay exit. TOTAL: an unknown purpose returns '{}' and re-plans nothing, it never
  -- raises. (Twin vocabulary is OPEN; OTTO-Q's is CLOSED.)
  SELECT CASE COALESCE(p_purpose,'')
    WHEN 'wash'    THEN ARRAY['exterior_wash','sensor_clean']
    WHEN 'detail'  THEN ARRAY['interior_deep_clean','exterior_wash','interior_tidy']
    WHEN 'service' THEN ARRAY['mechanical_pm','sensor_calibration','fault_repair','cosmetic_repair']
    WHEN 'inspect' THEN ARRAY['interior_inspection']
    ELSE '{}'::text[]
  END;
$function$
;

CREATE OR REPLACE FUNCTION ottoq.ottoq_atom_retirable_set()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
  SELECT ARRAY(
    SELECT DISTINCT s FROM (
      SELECT unnest(ottoq.ottoq_bay_purpose_atoms(p)) AS s
        FROM unnest(ARRAY['wash','detail','service','inspect']) p
      UNION ALL
      -- The non-bay retirables: completed in place by ottoq_start_concurrent_atoms ->
      -- twin.ottoq_sim_advance_visit_atoms, or by the charge-session and departure seams.
      -- 0383 adds perimeter_walkaround, which became completable in the same transaction
      -- when derive stopped writing it into the orphan 'hold' concurrency class. Adding it
      -- here WITHOUT that change would stop ottoq_atoms_guard demoting it and turn 63
      -- harmless atoms into permanent must_do blockers.
      SELECT unnest(ARRAY['charge','readiness_check','triage_check',
                          'interior_inspection','item_retrieval',
                          'remote_diagnostics','perimeter_walkaround','software_update'])
    ) u ORDER BY s);
$function$
;

CREATE OR REPLACE FUNCTION ottoq.ottoq_atom_retirable(p_svc text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(p_svc, '') = ANY (ottoq.ottoq_atom_retirable_set());
$function$
;

CREATE OR REPLACE FUNCTION ottoq.ottoq_svc_to_stall_type(p_svc text, p_depot_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_lane text; v_req text;
BEGIN
  IF p_svc IS NULL THEN RETURN NULL; END IF;

  SELECT lane INTO v_lane
    FROM public.service_cadence_policy
   WHERE svc = p_svc AND is_active
   LIMIT 1;

  IF v_lane IS NOT NULL THEN
    RETURN CASE v_lane
      WHEN 'wash_bay'    THEN 'wash_bay'
      -- No detail_bay stalls are seeded (0010: 3 wash_bay, 2 service_bay). Detail shares the
      -- wash lane, exactly as ottoq_book_workflow and ottoq_decide_tick (4b) already do.
      WHEN 'detail'      THEN 'wash_bay'
      WHEN 'service_bay' THEN 'service_bay'
      ELSE NULL          -- anchor / cabin / exterior / digital / gate, and anything new
    END;
  END IF;

  -- Fallback: the catalogue table named in the brief. Only trusted when the type exists.
  SELECT sd.stall_type_required::text INTO v_req
    FROM public.service_definitions sd
   WHERE sd.code = p_svc AND sd.is_active
     AND (p_depot_id IS NULL OR sd.depot_id = p_depot_id)
   ORDER BY sd.depot_id = p_depot_id DESC NULLS LAST
   LIMIT 1;

  IF v_req IS NULL THEN RETURN NULL; END IF;
  IF v_req IN ('dcfc','l2','staging') THEN RETURN NULL; END IF;   -- not a bay
  IF NOT EXISTS (SELECT 1 FROM public.stalls s
                  WHERE s.stall_type::text = v_req
                    AND (p_depot_id IS NULL OR s.depot_id = p_depot_id)) THEN
    -- Requirement names a stall type the depot does not have. Route cleaning work to the
    -- wash lane; anything else to the service lane. Never return an unbookable type.
    RETURN CASE WHEN v_req LIKE '%detail%' OR v_req LIKE '%wash%' THEN 'wash_bay' ELSE 'service_bay' END;
  END IF;
  RETURN v_req;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;   -- TOTAL: a requirement we cannot resolve costs no bay, never a transaction
END
$function$
;

-- the world step, as the catalog held it (loaded and patched by 0605, never executed here)
CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_tick_world(p_sim_run_id uuid)
 RETURNS TABLE(out_sim_clock_after timestamp with time zone, out_tick_minutes numeric, out_telemetry_emitted integer, out_charge_advanced integer, out_completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_ids uuid[];
  v_wear_written int;
  v_run ottoq_sim_runs%ROWTYPE;
  v_tick_minutes numeric; v_new_sim_clock timestamptz; v_completed boolean := FALSE;
  v_telemetry_count int; v_tick_t0 timestamptz; v_charge_adv int; v_feed_sim boolean := true;
BEGIN
  v_tick_t0 := clock_timestamp();   -- T0 instrument: whole-tick wall clock
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id FOR UPDATE;
  IF NOT FOUND OR v_run.status NOT IN ('running') THEN out_completed:=TRUE; RETURN NEXT; RETURN; END IF;

  SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_feed_sim FROM depots d WHERE d.id = v_run.depot_id;
  v_feed_sim := COALESCE(v_feed_sim, true);
  -- PLAYBACK CLOCK. 'live' = TRUE 1:1 (sim advances by REAL elapsed x speed_x, so
  -- one real second is one sim second at 1x). 'fixed' (default) keeps the historical
  -- tick_interval_seconds * time_scale behaviour so certs/benchmarks stay deterministic.
  -- The 0.05..10 clamp keeps a stalled metronome or a long GC pause from teleporting
  -- the world; it never applies in fixed mode.
  /* 0258: THE COMMENT ABOVE STATES THE INVARIANT AND NOTHING HELD IT. In 'live' mode
     v_tick_minutes is REAL ELAPSED TIME, so the sim clock itself -- not merely a stamp --
     would differ between two arms of one pair, and every duration, deadline, booking and
     charge interval downstream with it. A cert run got 'fixed' only because
     twin.ottoq_sim_start_run never writes the key: held shut by a NULL. The key is read
     EVERY tick, so it can also be set on a run already in flight, which is why the guard
     is here at the point of use rather than in the pair's pre-flight (and why a
     pre-flight read of the SCENARIO would have asserted nothing -- ottoq_scenarios has
     no such column). It REFUSES rather than coercing: a certification whose clock is not
     the clock its payload claims must not produce a verdict. Scope is exactly the two run
     classes the comment names; production and demo keep 'live' untouched.
     db/checks/0182 section 5. Measured: 0 of 980 cert/benchmark runs have ever carried it. */
  IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live'
     AND COALESCE(v_run.run_by,'') IN ('cert_harness','benchmark') THEN
    RAISE EXCEPTION 'ottoq_sim_advance_tick_world: run % is run_by=% with '
                    'playback_mode=live. A cert or benchmark run may not advance on the '
                    'wall clock -- the tick SIZE would be real elapsed time and the two '
                    'arms of a pair could never agree. Refused rather than coerced to '
                    'fixed, so the run cannot disagree with its own payload. 0258.',
                    p_sim_run_id, v_run.run_by USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(v_run.payload->>'playback_mode','fixed') = 'live' THEN
    -- TRUE 1:1. clock_timestamp() (NOT now(), which is transaction time and does
    -- not advance inside a transaction). Floor 0 -- a zero advance is correct when
    -- no real time has elapsed. The 10-minute ceiling stays as the anti-teleport guard.
    v_tick_minutes := LEAST(10.0, GREATEST(0.0,
      (EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.last_tick_at, clock_timestamp())))
       * COALESCE((v_run.payload->>'speed_x')::numeric, 1.0)) / 60.0));
  ELSE
    v_tick_minutes := (v_run.tick_interval_seconds::numeric * v_run.time_scale) / 60.0;
  END IF;
  v_new_sim_clock := v_run.sim_clock_current + (v_tick_minutes || ' minutes')::interval;
  IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;
  PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|' || v_new_sim_clock::text, true);  /* 0204: publish the tick's clock for ottoq.ottoq_run_now() */

  PERFORM ottoq_sim_advance_visit_atoms(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_opportunistic_scan(p_sim_run_id, v_new_sim_clock);
  PERFORM ottoq_sim_advance_flow_contract(p_sim_run_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_prearrival_contracts(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
  END IF;
  -- 0445 (G178): the battery is dispatched below, after reconciliation starts this tick's sessions

  IF v_feed_sim THEN
    -- THE ARM MOVES — AND IT MOVES FIRST. This ran after the charge block until
    -- the live run of 2026-08-12 showed why that cannot work: a mate opened in the
    -- previous tick is only walkable in this one, and the charge block below can
    -- stop the session and open a demate over the top of it before the advancer
    -- ever sees it. The mate was clobbered every time, 'align' was never reached,
    -- and no registration was ever recorded. Walking the arm first settles any
    -- pending mate — writing its registration — before anything can end the charge
    -- underneath it. Physics, so it belongs in the world half; wrapped because the
    -- tick must survive anything the robot does.
    BEGIN PERFORM twin.ottoq_arm_advance_cycles(p_sim_run_id, v_new_sim_clock);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'arm advance: %', SQLERRM; END;
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock
     WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);
  END IF;
  /* 0445 (G178): THE BATTERY ANSWERS THE LOAD IT WILL SEE. The orchestrator sums the ACTIVE sessions' rates,
     so it must run after reconciliation has started this tick's sessions and before energy is delivered;
     above the charge block it answered one tick late (a whole billing interval at 30 sim-min per tick). */
  IF (v_run.policy IS NULL OR v_run.policy = 'otto_q') AND ottoq_policy_get(p_sim_run_id,'energy_orchestration_enabled',1) > 0 THEN
    PERFORM ottoq_energy_orchestrate(p_sim_run_id, v_run.depot_id, v_new_sim_clock, v_run.tick_count + 1);
  END IF;
  IF v_feed_sim THEN
    PERFORM ottoq_sim_energy_controller(p_sim_run_id, v_run.depot_id, v_new_sim_clock);
  END IF;
  IF v_feed_sim THEN
    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);
    PERFORM ottoq_sim_advance_all_energy(v_run.depot_id, p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  ELSE
    v_charge_adv := 0;
  END IF;
  IF v_feed_sim THEN
  -- AP-2 R1: snapshot the in-flight dispatch set BEFORE telemetry mutates it
  SELECT array_agg(d.dispatch_id) INTO v_wear_ids
    FROM ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning');
  SELECT COUNT(*) INTO v_telemetry_count FROM ottoq_sim_advance_deployed_telemetry(p_sim_run_id, v_new_sim_clock, v_tick_minutes);
  v_wear_written := -1;
  BEGIN
    v_wear_written := ottoq_sim_advance_wear_counters(
      p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.tick_count + 1, COALESCE(v_wear_ids, ARRAY[]::uuid[]));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'wear_counters: %', SQLERRM; END;
  BEGIN
    INSERT INTO ottoq_wear_tick_status (sim_run_id, tick_seq, sim_clock, attempted, written, note)
    VALUES (p_sim_run_id, v_run.tick_count + 1, v_new_sim_clock,
            COALESCE(array_length(v_wear_ids,1),0), GREATEST(v_wear_written,0),
            CASE WHEN v_wear_written < 0 THEN 'advancer raised' ELSE NULL END)
    ON CONFLICT (sim_run_id, tick_seq) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    v_telemetry_count := 0;
  END IF;
  BEGIN PERFORM ottoq_comms_advance(p_sim_run_id, v_new_sim_clock); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'comms_advance: %', SQLERRM; END;
  PERFORM ottoq_sim_advance_service_flow(p_sim_run_id, v_new_sim_clock, v_tick_minutes, v_run.depot_id);
  IF v_feed_sim THEN PERFORM ottoq_sim_overnight_service_drain(v_run.depot_id, v_new_sim_clock, p_sim_run_id); END IF;

  UPDATE ottoq_sim_runs SET sim_clock_current=v_new_sim_clock, last_tick_at=v_tick_t0,
         -- LIVE-CLOCK COUPLING FIX 2026-08-01: publish the ACTUAL elapsed sim-minutes
         -- so every per-tick RATE cap downstream scales with the real tick size.
         -- Fixed mode writes exactly 30 = the historical fallback (no behaviour change).
         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('tick_minutes_actual', v_tick_minutes),  -- anchor at tick START so the tick's own compute is inside the next elapsed
         next_tick_due_at=clock_timestamp()+(v_run.tick_interval_seconds||' seconds')::interval,
         tick_count=tick_count+1, status=CASE WHEN v_completed THEN 'completed' ELSE status END,
         ended_at=CASE WHEN v_completed THEN NOW() ELSE ended_at END
   WHERE sim_run_id=p_sim_run_id;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_emit_depot_heartbeats(v_run.depot_id, v_new_sim_clock);
    UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_new_sim_clock WHERE depot_id = v_run.depot_id AND station_state <> 'Faulted';
    PERFORM ottoq_sim_recover_chargers(v_run.depot_id, v_new_sim_clock, 50);
  END IF;
  -- ═══════════ 0011-TETHER: THE ROBOT HAS FINISHED DEMATING ═══════════
  -- Single releaser for the robotic tether: clears the deadline AND frees the stall the
  -- arm was holding. Deliberately placed BEFORE the charger reconcile so a plug freed
  -- here is healed to Available in the SAME tick instead of lagging one behind. Called
  -- from the world tick, not the decide tick, because it is physics, not a decision --
  -- and because the world tick runs every metronome beat while decide runs on alternate
  -- beats. Self-contained: the sweep never raises, and this wrapper is belt-and-braces.
  BEGIN PERFORM public.ottoq_release_expired_tethers(v_new_sim_clock);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tether release: %', SQLERRM; END;
  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'charger reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_oem_webhook_collect_responses();
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'webhook reconcile: %', SQLERRM; END;
  BEGIN PERFORM ottoq_admit_stranded_vehicles(v_run.depot_id, p_sim_run_id, v_new_sim_clock, 80, 12);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'admit stranded: %', SQLERRM; END;

  UPDATE vehicles SET current_state='charge_complete_holding'::vehicle_state, last_state_change=v_new_sim_clock
   WHERE home_depot_id=v_run.depot_id AND category='autonomous'
     AND current_state='arrived_at_gate' AND current_soc>=85;

  IF v_feed_sim THEN
    PERFORM ottoq_sim_generate_arrival_manifests(v_run.depot_id, p_sim_run_id);
  END IF;
  PERFORM ottoq_sim_wash_triage(v_run.depot_id, v_new_sim_clock);
  IF v_feed_sim THEN
    PERFORM ottoq_sim_vehicle_exception_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
    PERFORM ottoq_sim_bay_fault_handler(v_run.depot_id, v_new_sim_clock, p_sim_run_id);
  END IF;

  -- T0 instrument: authoritative wall-clock + compute cost, one row per tick.
  -- clock_timestamp() (not now()) so batch-stepped ticks are individually timed.
  BEGIN
    INSERT INTO ottoq_tick_clock_log (
      sim_run_id, tick_seq, real_started_at, real_ended_at,
      sim_clock_before, sim_clock_after, tick_compute_ms, sim_advance_s,
      playback_mode, speed_x)
    VALUES (
      p_sim_run_id, COALESCE(v_run.tick_count,0) + 1, v_tick_t0, clock_timestamp(),
      v_run.sim_clock_current, v_new_sim_clock,
      round(EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0))::numeric * 1000, 1),
      round(EXTRACT(EPOCH FROM (v_new_sim_clock - v_run.sim_clock_current))::numeric, 1),
      COALESCE(v_run.payload->>'playback_mode','fixed'),
      COALESCE((v_run.payload->>'speed_x')::numeric, 1.0))
    ON CONFLICT (sim_run_id, tick_seq) DO UPDATE
      SET real_ended_at   = EXCLUDED.real_ended_at,
          tick_compute_ms = EXCLUDED.tick_compute_ms;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'tick clock log: %', SQLERRM;
  END;

  out_sim_clock_after:=v_new_sim_clock; out_tick_minutes:=v_tick_minutes;
  out_telemetry_emitted:=v_telemetry_count; out_charge_advanced:=v_charge_adv; out_completed:=v_completed;
  RETURN NEXT;
END;
$function$
;

-- the live grants on the two functions 0605 replaces (measured 2026-10-03): the departure test is executable by every
-- client role, the effective target by authenticated and service_role
REVOKE ALL ON FUNCTION public.ottoq_effective_target_soc_at(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_effective_target_soc_at(uuid, timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_sim_advance_tick_world(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_departure_clear(uuid, uuid, timestamptz, boolean) TO anon, authenticated, service_role;

-- ═════════════ SEED: the live catalog's services and the three contracts ═════════════
INSERT INTO public.service_cadence_policy (svc, display_name, category, lane, est_min_default) VALUES
  ('charge', 'Charge to target', 'energy', 'anchor', 25),
  ('cosmetic_repair', 'Cosmetic repair', 'cosmetic', 'service_bay', 60),
  ('exterior_wash', 'Exterior wash', 'cleanliness', 'wash_bay', 10),
  ('fault_repair', 'Fault repair', 'mechanical', 'service_bay', 76),
  ('interior_deep_clean', 'Interior deep clean', 'cleanliness', 'detail', 20),
  ('interior_inspection', 'Interior inspection', 'cleanliness', 'cabin', 4),
  ('interior_tidy', 'Interior tidy', 'cleanliness', 'cabin', 5),
  ('item_retrieval', 'Passenger item retrieval', 'items', 'cabin', 4),
  ('mechanical_pm', 'Mechanical PM', 'mechanical', 'service_bay', 40),
  ('perimeter_walkaround', 'Perimeter walkaround', 'inspection', 'exterior', 12),
  ('readiness_check', 'Readiness gate', 'gate', 'gate', 3),
  ('remote_diagnostics', 'Remote diagnostics', 'diagnostic', 'digital', 5),
  ('sensor_calibration', 'Sensor calibration', 'sensor', 'service_bay', 60),
  ('sensor_clean', 'Sensor clean', 'sensor', 'exterior', 5),
  ('software_update', 'Software update', 'software', 'digital', 30),
  ('triage_check', 'Triage', 'diagnostic', 'cabin', 3);
INSERT INTO public.ottoq_fleet_operator_slas (fleet_operator_id, contract_reference, effective_from, status, version,
  min_soc_at_deployment_pct, preferred_soc_at_deployment_pct, max_charge_target_pct, min_charge_target_pct,
  required_services_before_deploy, blocked_services) VALUES
  ('22222222-2222-2222-2222-222222222222', 'WAYMO-NASH-v1', '2026-07-19 23:07:56+00', 'active', 1, 80, 90, 100, 80, '{}', '{}'),
  ('33333333-3333-3333-3333-333333333333', 'TESLA-TN-v1', '2026-07-19 23:07:56+00', 'active', 1, 80, 90, 100, 80, '{}', '{}'),
  ('44444444-4444-4444-4444-444444444444', 'ZOOX-SE-v1', '2026-07-19 23:07:56+00', 'active', 1, 80, 90, 100, 80, '{}', '{}');
