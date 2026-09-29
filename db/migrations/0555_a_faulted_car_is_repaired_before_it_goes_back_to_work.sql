-- migration-version: 20260928212503
-- migration-name:    a_faulted_car_is_repaired_and_the_gate_flag_is_a_note
-- (applied 2026-09-28, 4:25 PM CT, together with 0556 in ONE transaction through apply_migration, which wrote one
--  ledger row for the two files: this version and the joint name above. 0556 carries APPLIED-NO-LEDGER-ROW and points
--  here. The ledger name has no ottoq_cert_lineage row of its own, so the recert floor reads it as forcing, which is
--  what both files' own lineage rows, 0555_... and 0556_..., also say.)
--
-- 0555  **A car with a vehicle fault is repaired in the service bay before it goes back to work.** (G290)
--
-- ══ §1 WHY (check 0410 §27, run ab8075a3) ══════════════════════════════════════════════════════════════════════════════
--
--   Waymo-AV-011 took a `steering_brake_fault` (severity critical, `immobilizing: true`) at 10:47 AM sim while it charged
--   on L2. The fault handler deferred the eviction until the charge window ended, sent the car to `tow_requested` at
--   1:07 PM and to `emergency_staged` at 1:32:35. In the same second `ottoq.ottoq_readmit_resumed_visits` put it back on
--   `staged_awaiting_service` to finish its interrupted visit. The gate staged it for departure 19 seconds later, and at
--   1:33:51 PM it deployed at 99% with the fault still in `config.exception`, repaired by nothing. Three gaps line up:
--     - the readmit paths return a faulted car to its interrupted work. They read the exception's status (the tow brought
--       the car in), never whether the fault was fixed, and `ottoq_readmit_resumed_visits` does not read `immobilizing`;
--     - nothing repairs a vehicle fault. No function marks one repaired or removes it; only the next run's seed strips it.
--       A faulted car with no cut-short visit (Waymo-AV-007, on the same run) sat in emergency staging, at 20%, until the
--       teardown;
--     - the departure test (`public.ottoq_departure_clear`, 0543), which the dispatchers, the departure recheck and 0544's
--       trigger all call, reads the charge and the card's atoms, and the fault is on neither.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `public.ottoq_vehicle_fault_open(config)`: the one answer to "does this car carry a vehicle fault that has not been
--       repaired". A fault lives in `config.exception` from the moment the fault handler raises it until (f) removes it.
--   (b) `public.ottoq_departure_clear` also requires no open fault, so nothing that asks it can send a faulted car out.
--   (c) `ottoq.ottoq_add_fault_repair(run, depot, car, clock)`: the repair as a must-do `fault_repair` atom for the service
--       bay (the catalog's est_min_default), on the car's newest open visit of the run, which is the visit the bay exit
--       reads and credits. A `fault_repair` already there is reopened and made must-do, so a visit carries one. With no
--       open visit the car gets one of its own (`F_vehicle_fault`, urgency tech_hold).
--   (d) Both readmit paths give a car whose fault is open its repair first and stage it on need_service, whatever else its
--       visit still owes. The charge and the rest follow the repair through the readiness gate, as for any car.
--   (e) `ottoq.ottoq_route_faulted_cars_to_repair(run, depot, clock)`, the fault handler's new step (6) after the readmit:
--       a car in emergency staging that the readmit did not take (it had no cut-short visit) gets the same repair and is
--       staged for the service bay, its exception marked `awaiting_repair`.
--   (f) The service bay's exit, when it credits `fault_repair` on a car whose fault is open, removes `config.exception` and
--       names the fault it closed on `twin.service_completed` (`fault_repaired`), as it names a cleared flag (0475).
--   (g) The departure recheck (0543) sends a car staged to leave with an open fault to the service bay with its repair,
--       before it looks at the charge: a catch-all for any path this file does not know about.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   The fault handler, the readmit paths, the service flow and the departure gates run in every arm.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - `SM.001`'s catalog lets only a command-center operator or a depot supervisor move a car out of `emergency_staged`.
--     The readmit has always crossed that edge as the engine, in shadow; (d) and (e) cross it on the way to a repair. In
--     production a person dispositions a faulted car (OTTO-RESPONSE); the twin's technician-in-loop stands in for that.
--   - A fault whose class makes charging unsafe (`service_incompatible`) is repaired before the car charges only because
--     the repair comes first here; nothing else yet refuses such a car a charger.
--   - The `ottoq_ops_approvals` rows the fault handler raised stay as they are.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0555 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin cars, visits, bays and bookings on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0555 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the six functions are the ones measured on 2026-09-28 (md5 of their source), and the new names are free ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)',               '5be0acbde790183d3e8f21dfacbf2d71'),
      ('ottoq.ottoq_readmit_resumed_visits(uuid,uuid,timestamp with time zone)',                  '3569e8611c820912ffdef8c1eba9c9f2'),
      ('ottoq.ottoq_readmit_reopened_needs(uuid,uuid,timestamp with time zone)',                  '96e8ee6673292d1f823b1d916c422dc8'),
      ('twin.ottoq_sim_vehicle_exception_handler(uuid,timestamp with time zone,uuid)',            '845031b774db75ec93035871e08cee37'),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',         '64694ab064894736f35b5bc13314a529'),
      ('twin.ottoq_sim_departure_recheck(uuid,timestamp with time zone,uuid)',                    '16105c7df3460c44308bd36ac60a23f7')) x(sig, md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0555 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('ottoq_vehicle_fault_open', 'ottoq_add_fault_repair',
                                                     'ottoq_route_faulted_cars_to_repair')) THEN
    RAISE EXCEPTION '0555 P2: a function this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0555_pre', 'function', p.pronamespace::regnamespace::text, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)'::regprocedure,
                 'ottoq.ottoq_readmit_resumed_visits(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'ottoq.ottoq_readmit_reopened_needs(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'twin.ottoq_sim_vehicle_exception_handler(uuid,timestamp with time zone,uuid)'::regprocedure,
                 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
                 'twin.ottoq_sim_departure_recheck(uuid,timestamp with time zone,uuid)'::regprocedure);

-- ── (a) one answer to "is this car's fault still open" ──
CREATE FUNCTION public.ottoq_vehicle_fault_open(p_config jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0555 (G290): a car carries a vehicle fault that has not been repaired while config.exception is an object. The fault
  -- handler writes it when the fault is raised; the service bay's repair (fault_repair credited) removes it, and a run's
  -- seed strips it at the start of a run. Nothing else removes it.
  SELECT COALESCE(jsonb_typeof(p_config->'exception') = 'object', false)
$fn$;
COMMENT ON FUNCTION public.ottoq_vehicle_fault_open(jsonb) IS
  '0555 (G290): true while the car carries a vehicle fault that has not been repaired (config.exception is an object). '
  'Read by the departure test, the readmit paths, the route to repair, the service bay exit and the departure recheck.';

-- ── (b) the departure test refuses a car with an open fault ──
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
$function$;
COMMENT ON FUNCTION public.ottoq_departure_clear(uuid, uuid, timestamptz, boolean) IS
  '0543 (CLAUDE.md rule 9): may this car leave the depot? Its charge is at its effective target - 1, no service on its open '
  'visit is open or in progress (the readiness check too, with p_need_readiness), and (0555, G290) it carries no vehicle '
  'fault that has not been repaired. The dispatchers, the departure recheck and 0544''s trigger all ask it.';

-- ── (c) the repair, on the card ──
CREATE FUNCTION ottoq.ottoq_add_fault_repair(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0555 (G290, CLAUDE.md rule 9): a vehicle fault is service-bay work the car owes, and the card is where the depot keeps
-- what a car owes. Returns the visit that carries the repair, or NULL when the car has no open fault.
DECLARE
  v_cfg jsonb; v_exc jsonb; v_visit uuid; v_atoms jsonb; v_min int; v_atom jsonb; v_key text;
BEGIN
  SELECT config INTO v_cfg FROM public.vehicles WHERE id = p_vehicle_id;
  IF NOT public.ottoq_vehicle_fault_open(v_cfg) THEN RETURN NULL; END IF;
  v_exc := v_cfg->'exception';
  v_min := COALESCE((SELECT round(cp.est_min_default)::int FROM public.service_cadence_policy cp
                      WHERE cp.svc = 'fault_repair' AND cp.is_active LIMIT 1), 76);
  v_atom := jsonb_build_object(
    'svc', 'fault_repair', 'must_do', true, 'deferrable', false, 'est_min', v_min, 'status', 'pending',
    'concurrency', 'bay', 'requires_bay', 'service_bay', 'raised_in_depot', true,
    'fault_class', v_exc->>'fault_class', 'fault_severity', v_exc->>'severity',
    'immobilizing', COALESCE((v_exc->>'immobilizing')::boolean, false),
    'why', format('Vehicle fault %s (%s%s), raised %s. It is repaired in the service bay before anything else, and the '
                  || 'car does not leave until it is (CLAUDE.md rule 9).',
                  COALESCE(v_exc->>'fault_class', 'unclassified'), COALESCE(v_exc->>'severity', 'severity unknown'),
                  CASE WHEN COALESCE((v_exc->>'immobilizing')::boolean, false) THEN ', immobilizing' ELSE '' END,
                  COALESCE(v_exc->>'flagged_at', 'at an unknown time')));

  -- the newest open visit of the run: the one twin.ottoq_sim_advance_service_flow's bay exit reads and credits
  SELECT n.visit_id, n.atoms INTO v_visit, v_atoms
    FROM public.ottoq_visit_needs n
   WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open', 'in_progress')
     AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
   ORDER BY n.created_at DESC, n.visit_key DESC LIMIT 1;

  IF v_visit IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_atoms, '[]'::jsonb)) a WHERE a->>'svc' = 'fault_repair') THEN
      -- one fault_repair per visit: an open one is made must-do, a done one from an earlier fault is reopened
      UPDATE public.ottoq_visit_needs n
         SET atoms = (SELECT jsonb_agg(CASE WHEN x.a->>'svc' = 'fault_repair'
                                            THEN (x.a - 'done_at' - 'closed_at' - 'started_at' - 'ends_at') || v_atom
                                            ELSE x.a END ORDER BY x.o)
                        FROM jsonb_array_elements(n.atoms) WITH ORDINALITY x(a, o))
       WHERE n.visit_id = v_visit;
    ELSE
      UPDATE public.ottoq_visit_needs n
         SET atoms = COALESCE(n.atoms, '[]'::jsonb) || jsonb_build_array(v_atom)
       WHERE n.visit_id = v_visit;
    END IF;
  ELSE
    v_key := p_vehicle_id::text || ':vf:' || to_char(p_clock AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS');
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype, urgency,
                                          atoms, status, source, meta)
    VALUES (p_vehicle_id, p_sim_run_id, p_depot_id, p_clock, v_key, 'F_vehicle_fault', 'tech_hold',
            jsonb_build_array(v_atom), 'open', 'vehicle_fault_repair',
            jsonb_build_object('generator', 'ottoq_add_fault_repair', 'fault_class', v_exc->>'fault_class'))
    ON CONFLICT (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)))
    DO UPDATE SET atoms = EXCLUDED.atoms, status = 'open', meta = EXCLUDED.meta
    RETURNING visit_id INTO v_visit;
  END IF;
  RETURN v_visit;
END
$fn$;
COMMENT ON FUNCTION ottoq.ottoq_add_fault_repair(uuid, uuid, uuid, timestamptz) IS
  '0555 (G290): puts a car''s open vehicle fault on its card as a must-do fault_repair for the service bay, on its newest '
  'open visit of the run (or a visit of its own). Returns that visit, or NULL when the car has no open fault.';

-- ── (e) a faulted car the readmit does not take goes to the service bay for its repair ──
CREATE FUNCTION ottoq.ottoq_route_faulted_cars_to_repair(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0555 (G290): a car the tow brought into emergency staging, with no cut-short visit for the readmit to resume, is not
-- left there for the rest of the day. Its repair goes on its card and it is staged for the service bay. The departure
-- test holds it until the repair is done.
DECLARE v_rec record; v_n int := 0; v_cars jsonb := '[]'::jsonb; v_visit uuid;
BEGIN
  IF p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  FOR v_rec IN
    SELECT vh.id, vh.config
      FROM public.vehicles vh
     WHERE vh.home_depot_id = p_depot_id AND vh.category = 'autonomous'
       AND vh.current_state = 'emergency_staged'
       AND COALESCE(vh.config->'exception'->>'status', '') = 'retrieved_staged'
       AND public.ottoq_vehicle_fault_open(vh.config)
     ORDER BY vh.id   -- run-stable cursor order (0050)
  LOOP
    v_visit := ottoq.ottoq_add_fault_repair(p_sim_run_id, p_depot_id, v_rec.id, p_clock);
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_clock,
           config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_service'::text))
                    || jsonb_build_object('exception', (config->'exception')
                         || jsonb_build_object('status', 'awaiting_repair', 'routed_to_repair_at', p_clock))
     WHERE id = v_rec.id;
    BEGIN
      PERFORM public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0555 route to repair: re-plan failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
    END;
    v_n := v_n + 1;
    v_cars := v_cars || jsonb_build_array(jsonb_build_object(
                'vehicle_id', v_rec.id, 'visit_id', v_visit,
                'fault_class', v_rec.config->'exception'->>'fault_class',
                'severity', v_rec.config->'exception'->>'severity',
                'immobilizing', v_rec.config->'exception'->'immobilizing'));
  END LOOP;
  IF v_n > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'route_faulted_cars_to_repair',
        p_event_type := 'ottoq.faulted_car_routed_to_repair', p_entity_type := 'depot', p_entity_id := p_depot_id,
        p_depot_id := p_depot_id,
        p_payload := jsonb_build_object('routed', v_n, 'cars', v_cars,
          'note', 'a faulted car in emergency staging goes to the service bay for its repair, and does not leave until it '
                  || 'is repaired (CLAUDE.md rule 9)'),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0555 route to repair: summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;
  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- never allowed to take the tick down (house rule 4)
  RAISE WARNING 'ottoq.ottoq_route_faulted_cars_to_repair FAILED SAFELY: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END
$fn$;
COMMENT ON FUNCTION ottoq.ottoq_route_faulted_cars_to_repair(uuid, uuid, timestamptz) IS
  '0555 (G290): step (6) of the fault handler. A car in emergency staging (retrieved_staged) that the readmit did not take '
  'gets its fault_repair on its card and is staged for the service bay (exception status awaiting_repair).';

-- ── (d) both readmit paths: the repair first ──
DO $readmit$
DECLARE v_def text; n int; f text;
  c_old CONSTANT text := $old$    v_svc_step := CASE WHEN v_needs_charge THEN 'need_charge' ELSE 'need_service' END;
$old$;
  c_new CONSTANT text := $new$    -- 0555 (G290, CLAUDE.md rule 9): the car's own fault comes first. Its repair goes on its visit as must-do
    -- service-bay work and it is staged for the service bay, whatever else the visit still owes; the charge and the rest
    -- follow the repair. Before, the car resumed its interrupted work unrepaired and could leave with the fault.
    IF public.ottoq_vehicle_fault_open(v_rec.config) THEN
      PERFORM ottoq.ottoq_add_fault_repair(p_sim_run_id, p_depot_id, v_rec.id, p_clock);
      v_needs_charge := false;
    END IF;
    v_svc_step := CASE WHEN v_needs_charge THEN 'need_charge' ELSE 'need_service' END;
$new$;
BEGIN
  FOREACH f IN ARRAY ARRAY['ottoq.ottoq_readmit_resumed_visits(uuid,uuid,timestamp with time zone)',
                           'ottoq.ottoq_readmit_reopened_needs(uuid,uuid,timestamp with time zone)'] LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
    IF n <> 1 THEN RAISE EXCEPTION '0555 readmit: the anchor matches % times in %, not 1', n, f; END IF;
    EXECUTE replace(v_def, c_old, c_new);
  END LOOP;
END $readmit$;

-- ── (e) the fault handler's step (6) ──
DO $handler$
DECLARE v_def text; n int;
  c_old CONSTANT text := $old$  v_n := v_n + COALESCE(ottoq.ottoq_readmit_resumed_visits(p_sim_run_id, p_depot_id, p_sim_clock), 0);
$old$;
  c_new CONSTANT text := $new$  v_n := v_n + COALESCE(ottoq.ottoq_readmit_resumed_visits(p_sim_run_id, p_depot_id, p_sim_clock), 0);

  -- (6) 0555 (G290): a faulted car the readmit did not take (it had no cut-short visit) goes to the service bay for its
  --     repair instead of staying in emergency staging for the rest of the day.
  v_n := v_n + COALESCE(ottoq.ottoq_route_faulted_cars_to_repair(p_sim_run_id, p_depot_id, p_sim_clock), 0);
$new$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_vehicle_exception_handler(uuid,timestamp with time zone,uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0555 handler: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $handler$;

-- ── (f) the service bay's repair closes the fault ──
DO $bayexit$
DECLARE v_def text; n int; i int;
  a_old text[] := ARRAY[
$o1$    PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
      FROM unnest(v_credit) AS s;
$o1$,
$o2$THEN COALESCE(v_rec.config->>'flagged_issue_type', 'untyped') END),
$o2$];
  a_new text[] := ARRAY[
$n1$    PERFORM ottoq_wear_mark_serviced(v_rec.id, p_sim_run_id, s, v_end_ts)
      FROM unnest(v_credit) AS s;
    -- 0555 (G290): the repair closes the car's vehicle fault. Only a service-bay exit that credits fault_repair does this,
    -- so an open fault cannot be lost any other way (a run's seed aside), and the departure test holds the car until then.
    IF 'fault_repair' = ANY (v_credit) AND public.ottoq_vehicle_fault_open(v_rec.config) THEN
      UPDATE vehicles SET config = config - 'exception' WHERE id = v_rec.id;
    END IF;
$n1$,
$n2$THEN COALESCE(v_rec.config->>'flagged_issue_type', 'untyped') END,
        -- 0555 (G290): the vehicle fault this repair closed, if any
        'fault_repaired', CASE WHEN 'fault_repair' = ANY (v_credit) AND public.ottoq_vehicle_fault_open(v_rec.config)
                               THEN v_rec.config->'exception' END),
$n2$];
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  FOR i IN 1 .. 2 LOOP
    n := (length(v_def) - length(replace(v_def, a_old[i], ''))) / length(a_old[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0555 bay exit: anchor % matches % times, not 1', i, n; END IF;
    v_def := replace(v_def, a_old[i], a_new[i]);
  END LOOP;
  EXECUTE v_def;
END $bayexit$;

-- ── (g) the departure recheck: a car staged to leave with an open fault goes for its repair ──
DO $recheck$
DECLARE v_def text; n int; i int;
  a_old text[] := ARRAY[
$o1$    SELECT v.id, v.current_soc, public.ottoq_effective_target_soc_at(v.id, p_sim_clock_now) AS tgt,
$o1$,
$o2$    v_remedy := CASE
                  WHEN v_rec.current_soc IS NULL OR v_rec.current_soc < v_rec.tgt - 1 THEN 'need_charge'
$o2$,
$o3$    CONTINUE WHEN v_remedy IS NULL;
$o3$];
  a_new text[] := ARRAY[
$n1$    SELECT v.id, v.current_soc, v.config, public.ottoq_effective_target_soc_at(v.id, p_sim_clock_now) AS tgt,
$n1$,
$n2$    v_remedy := CASE
                  -- 0555 (G290): an open vehicle fault first. The repair comes before the charge.
                  WHEN public.ottoq_vehicle_fault_open(v_rec.config)                 THEN 'need_service'
                  WHEN v_rec.current_soc IS NULL OR v_rec.current_soc < v_rec.tgt - 1 THEN 'need_charge'
$n2$,
$n3$    CONTINUE WHEN v_remedy IS NULL;
    -- 0555 (G290): the repair goes on the card before the car is staged for the service bay, so the bay has the work to
    -- do and to credit.
    IF public.ottoq_vehicle_fault_open(v_rec.config) THEN
      PERFORM ottoq.ottoq_add_fault_repair(p_sim_run_id, p_depot_id, v_rec.id, p_sim_clock_now);
    END IF;
$n3$];
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_departure_recheck(uuid,timestamp with time zone,uuid)'::regprocedure);
  FOR i IN 1 .. 3 LOOP
    n := (length(v_def) - length(replace(v_def, a_old[i], ''))) / length(a_old[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0555 recheck: anchor % matches % times, not 1', i, n; END IF;
    v_def := replace(v_def, a_old[i], a_new[i]);
  END LOOP;
  EXECUTE v_def;
END $recheck$;

-- ── V1 (comment-stripped): each change is in the live source ──
DO $verify$
DECLARE r record; v_src text; k int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)',
       'AND NOT public\.ottoq_vehicle_fault_open\(v\.config\)', 1),
      ('ottoq.ottoq_readmit_resumed_visits(uuid,uuid,timestamp with time zone)',
       'IF public\.ottoq_vehicle_fault_open\(v_rec\.config\) THEN\s+PERFORM ottoq\.ottoq_add_fault_repair\(p_sim_run_id, p_depot_id, v_rec\.id, p_clock\);\s+v_needs_charge := false;\s+END IF;\s+v_svc_step := CASE', 1),
      ('ottoq.ottoq_readmit_reopened_needs(uuid,uuid,timestamp with time zone)',
       'IF public\.ottoq_vehicle_fault_open\(v_rec\.config\) THEN\s+PERFORM ottoq\.ottoq_add_fault_repair\(p_sim_run_id, p_depot_id, v_rec\.id, p_clock\);\s+v_needs_charge := false;\s+END IF;\s+v_svc_step := CASE', 1),
      ('twin.ottoq_sim_vehicle_exception_handler(uuid,timestamp with time zone,uuid)',
       'ottoq_readmit_resumed_visits\(p_sim_run_id, p_depot_id, p_sim_clock\), 0\);\s+v_n := v_n \+ COALESCE\(ottoq\.ottoq_route_faulted_cars_to_repair\(p_sim_run_id, p_depot_id, p_sim_clock\), 0\);', 1),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       'IF ''fault_repair'' = ANY \(v_credit\) AND public\.ottoq_vehicle_fault_open\(v_rec\.config\) THEN\s+UPDATE vehicles SET config = config - ''exception'' WHERE id = v_rec\.id;', 1),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       '''fault_repaired'', CASE WHEN ''fault_repair'' = ANY \(v_credit\) AND public\.ottoq_vehicle_fault_open\(v_rec\.config\)', 1),
      ('twin.ottoq_sim_departure_recheck(uuid,timestamp with time zone,uuid)',
       'WHEN public\.ottoq_vehicle_fault_open\(v_rec\.config\)\s+THEN ''need_service''\s+WHEN v_rec\.current_soc IS NULL', 1),
      ('twin.ottoq_sim_departure_recheck(uuid,timestamp with time zone,uuid)',
       'CONTINUE WHEN v_remedy IS NULL;\s+IF public\.ottoq_vehicle_fault_open\(v_rec\.config\) THEN\s+PERFORM ottoq\.ottoq_add_fault_repair\(p_sim_run_id, p_depot_id, v_rec\.id, p_sim_clock_now\);', 1)
    ) x(sig, pat, want)
  LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    k := (SELECT count(*) FROM regexp_matches(v_src, r.pat, 'g'));
    IF k <> r.want THEN RAISE EXCEPTION '0555 V1: % matches % times in %, not %', r.pat, k, r.sig, r.want; END IF;
  END LOOP;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0555_a_faulted_car_is_repaired_before_it_goes_back_to_work', true, true,
  'G290: a car whose vehicle fault was never repaired left the depot (0410 §27: Waymo-AV-011, a critical immobilizing '
  'steering/brake fault). The departure test now refuses an open fault; the readmit paths and a new step (6) of the fault '
  'handler put a must-do fault_repair on the card and stage the car for the service bay; the bay''s credit of fault_repair '
  'removes config.exception; the departure recheck catches any car staged to leave with an open fault.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction.
--   Every other twin car is offline (the run's teardown), and the three cars below are the only ones in play:
--   F1 is Waymo-AV-011's case: towed in with a critical, immobilizing steering/brake fault, its visit cut short (the charge
--      done, the readiness check open). The fault handler's readmit (5) must stage it for the service bay with its repair.
--   F2 is Waymo-AV-007's: towed in with a major fault from a wait for a charger, at 20%, with no cut-short visit. The new
--      step (6) must stage it for the service bay with its repair.
--   F3 is a car at 100% with every atom done and staged to leave, carrying an open fault. The departure test must refuse
--      it (and pass it with the fault removed), and the departure recheck must send it for its repair.
--   Then F1 is put in service bay 1 with its timer ended, and one pass of the service flow must credit fault_repair,
--   remove its exception and name the fault on twin.service_completed.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; sb uuid[]; f1 uuid; f2 uuid; f3 uuid;
  st1 text; st2 text; st3 text; step1 text; step2 text; step3 text; xs2 text;
  fr1 int; fr2 int; fr3 int; dc_with boolean; dc_without boolean; ev jsonb; open1 boolean; done1 int;
  v_pass text;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0555 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    SELECT array_agg(id ORDER BY distance_from_entrance NULLS LAST, stall_code) INTO sb
      FROM public.stalls WHERE depot_id = v_depot AND stall_type::text = 'service_bay' AND status NOT IN ('maintenance', 'closed');
    IF coalesce(array_length(sb, 1), 0) < 1 THEN RAISE EXCEPTION '0555 V3: no open service bay'; END IF;
    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 3) q;
    IF coalesce(array_length(car, 1), 0) < 3 THEN RAISE EXCEPTION '0555 V3: fewer than three free twin cars'; END IF;
    f1 := car[1]; f2 := car[2]; f3 := car[3];

    -- only these three in play: every other twin car off the site, the service bays empty and free
    UPDATE public.vehicles SET current_state = 'offline'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND robotic_tether_until IS NULL AND current_state <> 'offline';
    UPDATE public.vehicles SET config = config - 'exception'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND config ? 'exception';
    UPDATE public.vehicles SET current_stall_id = NULL WHERE current_stall_id = ANY (sb) AND NOT (id = ANY (car));
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL,
           status = 'available' WHERE id = ANY (sb);
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = t, release_reason = 'v3_0555'
     WHERE stall_id = ANY (sb) AND sim_run_id = v_run AND state IN ('held', 'active') AND upper(during) > t - interval '1 day';
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.ottoq_ops_approvals SET status = 'expired' WHERE vehicle_id = ANY (car) AND status = 'pending';

    UPDATE public.vehicles
       SET current_depot_id = v_depot, last_state_change = t - interval '5 minutes',
           current_soc = CASE WHEN id = f2 THEN 20 ELSE 100 END, target_soc = 100,
           current_state = CASE WHEN id = f3 THEN 'staged_for_departure' ELSE 'emergency_staged' END::vehicle_state,
           config = (COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type' - 'service_ends_at' - 'svc_step'
                     - 'exception' - 'remedy_wait' - 'deploy_gate' - 'charge_wait')
                    || jsonb_build_object('exception', jsonb_build_object(
                         'type', 'vehicle_fault', 'flagged_at', t - interval '60 minutes',
                         'status', CASE WHEN id = f3 THEN 'readmitted_resume' ELSE 'retrieved_staged' END,
                         'severity', CASE WHEN id = f2 THEN 'major' ELSE 'critical' END,
                         'fault_class', CASE WHEN id = f2 THEN 'non_critical_major' ELSE 'steering_brake_fault' END,
                         'immobilizing', id <> f2))
     WHERE id = ANY (car);
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, target_soc, atoms,
                                          status, source, meta)
    VALUES
      (f1, v_run, v_depot, t - interval '3 hours', 'V3-0555-F1', 'standard', 100,
       jsonb_build_array(jsonb_build_object('svc', 'charge', 'concurrency', 'anchor', 'must_do', true, 'status', 'done',
                                            'done_at', t - interval '70 minutes'),
                         jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending')),
       'open', 'v3_0555', jsonb_build_object('reopen', jsonb_build_object('reason', 'vehicle_fault_eviction_deferred_resumed'))),
      (f2, v_run, v_depot, t - interval '4 hours', 'V3-0555-F2', 'standard', 100,
       jsonb_build_array(jsonb_build_object('svc', 'charge', 'concurrency', 'anchor', 'must_do', true, 'status', 'pending'),
                         jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending')),
       'open', 'v3_0555', '{}'::jsonb),
      (f3, v_run, v_depot, t - interval '2 hours', 'V3-0555-F3', 'standard', 100,
       jsonb_build_array(jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'done',
                                            'done_at', t - interval '10 minutes')),
       'open', 'v3_0555', '{}'::jsonb);

    -- the departure test refuses F3 because of its fault, and only because of it
    dc_with := public.ottoq_departure_clear(f3, v_run, t, true);
    UPDATE public.vehicles SET config = config - 'exception' WHERE id = f3;
    dc_without := public.ottoq_departure_clear(f3, v_run, t, true);
    UPDATE public.vehicles
       SET config = config || jsonb_build_object('exception', jsonb_build_object(
             'type', 'vehicle_fault', 'flagged_at', t - interval '60 minutes', 'status', 'readmitted_resume',
             'severity', 'critical', 'fault_class', 'steering_brake_fault', 'immobilizing', true))
     WHERE id = f3;
    IF dc_with IS DISTINCT FROM false OR dc_without IS DISTINCT FROM true THEN
      RAISE EXCEPTION '0555 V3 FAILED: the departure test read % with F3''s fault and % without it', dc_with, dc_without;
    END IF;

    -- the fault handler: its readmit (5) takes F1, its new step (6) takes F2
    PERFORM twin.ottoq_sim_vehicle_exception_handler(v_depot, t, v_run);
    SELECT current_state::text, config->>'svc_step' INTO st1, step1 FROM public.vehicles WHERE id = f1;
    SELECT current_state::text, config->>'svc_step', config->'exception'->>'status' INTO st2, step2, xs2 FROM public.vehicles WHERE id = f2;
    SELECT count(*) INTO fr1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id = f1 AND n.visit_key = 'V3-0555-F1' AND a->>'svc' = 'fault_repair' AND (a->>'must_do')::boolean
       AND COALESCE(a->>'status', 'pending') = 'pending';
    SELECT count(*) INTO fr2 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id = f2 AND n.visit_key = 'V3-0555-F2' AND a->>'svc' = 'fault_repair' AND (a->>'must_do')::boolean
       AND COALESCE(a->>'status', 'pending') = 'pending';
    IF st1 IS DISTINCT FROM 'staged_awaiting_service' OR step1 IS DISTINCT FROM 'need_service' OR fr1 <> 1 THEN
      RAISE EXCEPTION '0555 V3 FAILED: F1 (readmit) is % on step % with % open fault_repair', st1, step1, fr1;
    END IF;
    IF st2 IS DISTINCT FROM 'staged_awaiting_service' OR step2 IS DISTINCT FROM 'need_service' OR fr2 <> 1
       OR xs2 IS DISTINCT FROM 'awaiting_repair' THEN
      RAISE EXCEPTION '0555 V3 FAILED: F2 (no cut-short visit) is % on step % with % open fault_repair, exception %',
        st2, step2, fr2, xs2;
    END IF;
    IF NOT public.ottoq_vehicle_fault_open((SELECT config FROM public.vehicles WHERE id = f1)) THEN
      RAISE EXCEPTION '0555 V3 FAILED: F1 lost its fault before any repair';
    END IF;

    -- the departure recheck sends F3, staged to leave with its fault, for its repair
    PERFORM twin.ottoq_sim_departure_recheck(v_run, t, v_depot);
    SELECT current_state::text, config->>'svc_step' INTO st3, step3 FROM public.vehicles WHERE id = f3;
    SELECT count(*) INTO fr3 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id = f3 AND n.visit_key = 'V3-0555-F3' AND a->>'svc' = 'fault_repair' AND (a->>'must_do')::boolean;
    IF st3 IS DISTINCT FROM 'staged_awaiting_service' OR step3 IS DISTINCT FROM 'need_service' OR fr3 <> 1 THEN
      RAISE EXCEPTION '0555 V3 FAILED: after the recheck F3 is % on step % with % fault_repair', st3, step3, fr3;
    END IF;

    -- F1 in service bay 1 with its timer ended: one pass of the service flow repairs it
    UPDATE public.vehicles
       SET current_state = 'in_service_bay', current_stall_id = sb[1], last_state_change = t - interval '60 minutes',
           config = config || jsonb_build_object('service_ends_at', t - interval '1 minute')
     WHERE id = f1;
    UPDATE public.stalls SET current_vehicle_id = f1, status = 'occupied' WHERE id = sb[1];
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, t, 30, v_depot);
    open1 := public.ottoq_vehicle_fault_open((SELECT config FROM public.vehicles WHERE id = f1));
    SELECT count(*) INTO done1 FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
     WHERE n.vehicle_id = f1 AND n.visit_key = 'V3-0555-F1' AND a->>'svc' = 'fault_repair' AND a->>'status' = 'done';
    SELECT e.payload INTO ev FROM public.ottoq_events e
     WHERE e.sim_run_id = v_run AND e.entity_id = f1 AND e.event_type = 'twin.service_completed'
     ORDER BY e.event_seq DESC LIMIT 1;
    IF open1 OR done1 <> 1 OR NOT ('fault_repair' = ANY (ARRAY(SELECT jsonb_array_elements_text(ev->'credited'))))
       OR ev->'fault_repaired'->>'fault_class' IS DISTINCT FROM 'steering_brake_fault' THEN
      RAISE EXCEPTION '0555 V3 FAILED: after the service bay F1''s fault open=%, fault_repair done=%, event %', open1, done1, ev;
    END IF;
    IF NOT public.ottoq_vehicle_fault_open((SELECT config FROM public.vehicles WHERE id = f2))
       OR NOT public.ottoq_vehicle_fault_open((SELECT config FROM public.vehicles WHERE id = f3)) THEN
      RAISE EXCEPTION '0555 V3 FAILED: F2 or F3 lost its fault without a repair';
    END IF;

    v_pass := format('0555 V3 PASSED on run %s: the departure test refused F3 with its fault and cleared it without; the '
                     || 'readmit staged F1 (critical, immobilizing, cut short) and step (6) staged F2 (major, no cut-short '
                     || 'visit) for the service bay, each with a must-do fault_repair (F2''s exception awaiting_repair); the '
                     || 'recheck sent F3 for its repair; the service bay credited F1''s fault_repair, removed its exception '
                     || 'and named %s on twin.service_completed; F2 and F3 kept theirs',
                     v_run, ev->'fault_repaired'->>'fault_class');
    RAISE EXCEPTION '%', v_pass;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0555 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0555 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0555_pre' as it is, then DROP the three
-- functions (a), (c) and (e).

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-28 to gxdrcyphqjzjsuhxuqtg, 4:25 PM CT (ledger 20260928212503), in one transaction with 0556.
--   public.ottoq_departure_clear                 5be0acbde790183d3e8f21dfacbf2d71 -> 759448f46b88779dd4d8a9d426d865c1
--   ottoq.ottoq_readmit_resumed_visits           3569e8611c820912ffdef8c1eba9c9f2 -> 431d9e1abde3b461ca7083a56690e2cc
--   ottoq.ottoq_readmit_reopened_needs           96e8ee6673292d1f823b1d916c422dc8 -> 3ffe1581cfde47cadd5c8d52d099e886
--   twin.ottoq_sim_vehicle_exception_handler     845031b774db75ec93035871e08cee37 -> 40e06faf338a4e732b33ff5541b044f3
--   twin.ottoq_sim_advance_service_flow          64694ab064894736f35b5bc13314a529 -> 913c3bc81e2599827c1f57d9296b0202
--                                                (then 0556 in the same transaction -> 0b852abe1944dd93f8e35c9d2f6967bd)
--   twin.ottoq_sim_departure_recheck             16105c7df3460c44308bd36ac60a23f7 -> 4060e9d844d293468748c3a2d04cdd8f
--   created: public.ottoq_vehicle_fault_open (ca078b301f00f91e4bb8691dd4a37a67), ottoq.ottoq_add_fault_repair
--   (5afa406f350096aeea5e3ea88a7a456b), ottoq.ottoq_route_faulted_cars_to_repair (eb428364241f3d112ea59d4787b82e7c).
--   V1 and V3 passed: the transaction commits only if both do. A dry run of the two files together (ROLLBACK in place of
--   COMMIT) passed first and left nothing behind. ottoq_cert_recert_floor() moved to 2026-09-28 21:25:03.404508+00; the
--   sweep restarted.
