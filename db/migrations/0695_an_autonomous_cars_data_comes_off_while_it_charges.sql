-- migration-version: PENDING
-- migration-name:    an_autonomous_cars_data_comes_off_while_it_charges
--
-- 0695  **An autonomous car's logged data comes off over a wired uplink while it charges, as a required service, in
--        the twin behind a dial; the depot holds the car on its charger until the transfer ends.**
--        Part A item 3 of the twin data contract review (docs/DATA_OFFLOAD.md). Chase, 2026-10-09: model data offload
--        as a timing sequence while the car charges or during a service-bay stop.
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The robotaxi catalog (CLAUDE.md 2.4) lists data offload, 10-40 minutes, in parallel with other work, and no such
--   service exists in the engine. An AV logs on the order of a terabyte an hour (Renovo and EdgeConneX, 2018-06-12, a
--   vendor claim: 1-5 TB an hour raw), and the depot is where it comes off. Declared, not fitted (no public dataset gives
--   a fleet's volume per visit or a depot's uplink): 1 TB kept per hour out, a 10 Gbps uplink per charger or service bay
--   (4.5 TB an hour), so minutes = hours out x 60 / 4.5, between 10 and 40.
--
--   Read 2026-10-10 (docs/DATA_OFFLOAD.md, "Where the transfer can stall"): the twin's observer feeds the kernel's
--   deriver observations (ota_pending raises software_update); the concurrent starter starts every digital atom at
--   once, anywhere; STEP 1.5 of the service flow already keeps a charged car on its charger while any must-do work is
--   open; three movers take a charged car off its charger for its next work (OTTO-Q's charge disposition in
--   ottoq_decide_tick, the service flow's wash admission, the bay-booking activation); and nothing brings a full car
--   back to a charger (the charge cursor takes only cars below target minus 1).
--
-- ══ §2 WHAT THIS CHANGES (all behind twin_data_offload; 0, unset everywhere, changes nothing) ═══════════════════
--
--   (a) service_cadence_policy row data_offload (lane digital, must-do always, event-raised), and the retirable set,
--       so the vocabulary stays declared and the atoms guard does not tag it as having no executor.
--   (b) The dial twin_data_offload, a person's, per run, and twin.ottoq_twin_offload_hours(car, run, clock): the hours an
--       autonomous fleet car has been out at work on the run since its last finished transfer (0 for a car with no AV
--       logger). The twin's observer reports it as data_offload_hours when the dial is on.
--   (c) The kernel's deriver raises data_offload from that observation, as it raises software_update from ota_pending:
--       must-do, not deferrable, digital, needs_uplink, sized as in §1, on a visit that charges (the car stands on a
--       charger anyway); a visit with no charge leaves the hours for the next one.
--   (d) The starter starts a needs_uplink atom only on a charger or a service bay and records which stall
--       (performed_by stall_uplink). The completion step resets a transfer whose car left that stall before its minutes
--       ran out to pending, nothing credited (as 0519 does for the charger's sensors), and the readiness check waits for
--       it (0657's rule, extended); its catch-up does not spend one of its thirty places on a transfer whose car is off
--       an uplink stall.
--   (e) The hold: ottoq.ottoq_uplink_transfer_holds(car, run) is true while an unfinished transfer's car stands on an
--       uplink stall, and OTTO-Q's charge disposition, the wash admission and the bay-booking activation leave such a
--       car where it is. Its wash or bay follows the transfer.
--   (f) The research wing's pair, registered as a dial experiment.
--
--   Not built, and why: the way back for a car that leaves its uplink anyway (only an emergency or a fault path the
--   hold does not cover). Such a car with its battery full has no route to a charger, and the readiness gate escalates
--   it as stuck (deploy_gate_stuck, then deploy_gate_hard_cap); the pair counts these. If it finds any, the route back
--   (the departure recheck, the readiness gate and the decide tick's charge cursor, docs/DATA_OFFLOAD.md) is the next
--   build. Nor is a service bay a place a transfer starts on its own: the completion step's catch-up does not visit a
--   car in a bay, so in this build a transfer runs on a charger.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   The dial is set nowhere. At 0 the observer adds no key, so the deriver raises no transfer, and every other patched
--   path acts only on an atom marked needs_uplink, which nothing else writes (V1 raises nothing at 0). The catalog row
--   is read only by name. Setting the dial is a certified change after the pair.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the eight definitions in ottoq_schema_snapshots WHERE label = '0695_pre'; set service_cadence_policy
--   data_offload is_active false; mark the experiment created_by '0695' abandoned. The helpers stay (dropping needs a
--   person at the connector's prompt) and nothing calls them once the definitions are restored.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0695 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  -- the completion step is patched as 0657 leaves it
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0657_the_readiness_check_is_the_last_thing_a_visit_does') THEN
    RAISE EXCEPTION '0695 P1: 0657 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) <> 'f073e5be363fea71d436c34d790ff610'
     OR md5(pg_get_functiondef('twin.ottoq_sim_observe_asset(uuid,uuid,uuid,bigint,timestamptz,uuid)'::regprocedure)) <> '9f3830ec91d16ff830f1823b02ba1e12'
     OR md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure)) <> 'e4838d219782c489adc38239bba8ed10'
     OR md5(pg_get_functiondef('ottoq.ottoq_atom_retirable_set()'::regprocedure)) <> 'ca6fefa490efbce29c2696a4e55b0382'
     OR md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)) <> '8f362785be818b2d5a0794e109da2984'
     OR md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> '3767f175d775fea6f60bd8bd1c4f1322'
     OR md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'::regprocedure)) <> 'a37cfdd807d8dc338d6c5620b70bd404'
     OR md5(pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamptz)'::regprocedure)) <> 'eff1f1ab38dff9e61ad045d1dbe0d147' THEN
    RAISE EXCEPTION '0695 P1: a function this file patches is not the definition it was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.service_cadence_policy WHERE svc = 'data_offload')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_data_offload')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_data_offload')
     OR EXISTS (SELECT 1 FROM public.ottoq_dial_experiments WHERE param_key = 'twin_data_offload')
     OR to_regprocedure('twin.ottoq_twin_offload_hours(uuid,uuid,timestamptz)') IS NOT NULL
     OR to_regprocedure('ottoq.ottoq_uplink_transfer_holds(uuid,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0695 P1: an object or a key this file creates exists already';
  END IF;
  -- nothing has ever raised a needs_uplink atom, so every patched path is idle until the dial is set
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
              WHERE vn.status IN ('open', 'in_progress') AND (a ? 'needs_uplink' OR a->>'svc' = 'data_offload')) THEN
    RAISE EXCEPTION '0695 P1: an open visit already carries a data transfer';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0695 P1: a run is live; apply between runs';
  END IF;
END $premises$;

-- ── snapshots ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0695_pre', 'function', x.s, x.n, x.d, md5(x.d)
  FROM (SELECT split_part(f, '.', 1) AS s, split_part(f, '.', 2) AS n, pg_get_functiondef(f::regprocedure) AS d
          FROM unnest(ARRAY[
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)',
                 'twin.ottoq_sim_observe_asset(uuid,uuid,uuid,bigint,timestamptz,uuid)',
                 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)',
                 'ottoq.ottoq_atom_retirable_set()',
                 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)',
                 'public.ottoq_decide_tick(uuid)',
                 'twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)',
                 'ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamptz)']) f) x;

-- ── (a) the service ──
INSERT INTO public.service_cadence_policy
  (svc, display_name, category, lane, est_min_default, interval_h, interval_km, cadence_kind, must_do_at, lane_stalls,
   sequence_order, notes, is_active)
VALUES ('data_offload', 'Data offload', 'data', 'digital', 27, NULL, NULL, 'event', 'always', NULL, 52,
        '0695 (Part A item 3, docs/DATA_OFFLOAD.md). An autonomous car''s logged data, off over a wired uplink at a '
        'charger or a service bay: raised by the deriver from the observation data_offload_hours, sized hours x 60 / 4.5 '
        'minutes (1 TB an hour kept, 10 Gbps per uplink), 10 to 40. Lane digital: it takes no technician and no bay; '
        'ottoq_svc_to_stall_type maps the lane to NULL. Must-do once raised (CLAUDE.md rule 9): the car does not leave '
        'with it open, and an unfinished transfer holds its car on its uplink stall (ottoq.ottoq_uplink_transfer_holds).',
        true);

DO $p_retirable$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_atom_retirable_set()'::regprocedure);
  a text[] := ARRAY[
$a01$'remote_diagnostics','perimeter_walkaround','software_update'])$a01$];
  b text[] := ARRAY[
$b01$'remote_diagnostics','perimeter_walkaround','software_update',
                          'data_offload'])   -- 0695: completed in place, on its uplink stall$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'ca6fefa490efbce29c2696a4e55b0382' THEN
    RAISE EXCEPTION '0695: the retirable set is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the retirable set occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'c4394d5f67de33045587e6abdf182a33' THEN
    RAISE EXCEPTION '0695: the retirable set, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('ottoq.ottoq_atom_retirable_set()'::regprocedure)) <> 'c4394d5f67de33045587e6abdf182a33' THEN
    RAISE EXCEPTION '0695: the retirable set did not read back as written';
  END IF;
END $p_retirable$;

-- ── (b) the dial, and how much data a car carries ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('twin_data_offload',
        '0695: whether the twin''s autonomous cars carry logged data that comes off at the depot. 0 (unset, as before) '
        '= no data, no transfer; 1 = the twin''s observer reports each autonomous fleet car''s hours out since its last '
        'transfer, and the deriver raises data_offload on a visit that charges. A person''s dial, never the agent''s; set '
        'after the research wing''s pair, as a certified change.',
        0, 0, 1,
        'twin.ottoq_sim_observe_asset (0695); through it ottoq.ottoq_derive_visit_needs',
        false);

CREATE FUNCTION twin.ottoq_twin_offload_hours(p_vehicle uuid, p_run uuid, p_clock timestamptz)
RETURNS numeric LANGUAGE sql STABLE AS $fn$
  -- 0695: the hours of driving whose data is still on the car: its time out at work on the run since its last finished
  -- data transfer. A car with no AV logger (not autonomous, or in no fleet) carries none.
  WITH since AS (
    SELECT COALESCE(max((a->>'done_at')::timestamptz), '-infinity'::timestamptz) AS t
      FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle AND vn.sim_run_id = p_run
       AND a->>'svc' = 'data_offload' AND a->>'status' = 'done')
  SELECT CASE
    WHEN NOT EXISTS (SELECT 1 FROM public.vehicles v
                      WHERE v.id = p_vehicle AND v.category = 'autonomous' AND v.fleet_operator_id IS NOT NULL)
      THEN 0::numeric
    ELSE COALESCE((SELECT sum(extract(epoch FROM (LEAST(COALESCE(d.actual_return_at, p_clock), p_clock)
                                                  - GREATEST(d.dispatched_at, s.t))))
                     FROM public.ottoq_vehicle_dispatches d, since s
                    WHERE d.vehicle_id = p_vehicle AND d.sim_run_id = p_run AND d.dispatched_at < p_clock
                      AND LEAST(COALESCE(d.actual_return_at, p_clock), p_clock) > GREATEST(d.dispatched_at, s.t)), 0)
         / 3600.0
  END
$fn$;
COMMENT ON FUNCTION twin.ottoq_twin_offload_hours(uuid,uuid,timestamptz) IS
  '0695: the hours an autonomous fleet car has been out at work on a run since its last finished data transfer.';
REVOKE ALL ON FUNCTION twin.ottoq_twin_offload_hours(uuid,uuid,timestamptz) FROM PUBLIC, anon, authenticated;

DO $p_observe$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_observe_asset(uuid,uuid,uuid,bigint,timestamptz,uuid)'::regprocedure);
  a text[] := ARRAY[
$a01$    'charge_rate_mult', v_rate);
END;
$a01$];
  b text[] := ARRAY[
$b01$    'charge_rate_mult', v_rate)
    -- 0695: at twin_data_offload 1, how many hours of driving the car's logged data covers (docs/DATA_OFFLOAD.md)
    || CASE WHEN p_run IS NOT NULL AND COALESCE(ottoq_policy_get(p_run, 'twin_data_offload', 0), 0) >= 1
            THEN jsonb_build_object('data_offload_hours', twin.ottoq_twin_offload_hours(p_vehicle_id, p_run, p_clock))
            ELSE '{}'::jsonb END;
END;
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '9f3830ec91d16ff830f1823b02ba1e12' THEN
    RAISE EXCEPTION '0695: the twin''s observer is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the twin''s observer occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '24104d1d4e8d66ff634bd19c78d59c06' THEN
    RAISE EXCEPTION '0695: the twin''s observer, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_observe_asset(uuid,uuid,uuid,bigint,timestamptz,uuid)'::regprocedure))
       <> '24104d1d4e8d66ff634bd19c78d59c06' THEN
    RAISE EXCEPTION '0695: the twin''s observer did not read back as written';
  END IF;
END $p_observe$;

-- ── (c) the deriver raises it from the observation ──
DO $p_derive$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure);
  a text[] := ARRAY[
$a01$      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
$a01$];
  b text[] := ARRAY[
$b01$      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
  -- 0695: data offload, the robotaxi catalog's (CLAUDE.md 2.4). The car's logged data comes off over a wired uplink at
  -- a charger or a service bay, sized by the hours of driving the observation says it carries (1 TB an hour kept, 10
  -- Gbps per uplink: docs/DATA_OFFLOAD.md), between 10 and 40 minutes. Raised on a visit that charges, so the car
  -- stands on a charger anyway; a visit with no charge leaves the hours for the next one.
  IF COALESCE((p_obs->>'data_offload_hours')::numeric, 0) > 0 AND v_soc < v_visit_target - 1 THEN
    v_m := v_m || jsonb_build_object('svc','data_offload','must_do',true,'deferrable',false,
      'est_min', GREATEST(10, LEAST(40, ceil((p_obs->>'data_offload_hours')::numeric * 60.0 / 4.5)))::int,
      'concurrency','digital','needs_uplink',true,
      'hours_out', round((p_obs->>'data_offload_hours')::numeric, 2));
  END IF;
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'e4838d219782c489adc38239bba8ed10' THEN
    RAISE EXCEPTION '0695: the deriver is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the deriver occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '9ae0558f6a6ce8ca6d14ba3b9dc3c28b' THEN
    RAISE EXCEPTION '0695: the deriver, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure))
       <> '9ae0558f6a6ce8ca6d14ba3b9dc3c28b' THEN
    RAISE EXCEPTION '0695: the deriver did not read back as written';
  END IF;
END $p_derive$;

-- ── (d) the starter starts a transfer only on an uplink stall, and says which ──
DO $p_starter$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a01$  v_on_charger boolean;   -- 0521 (G246): whether that stall is a charger at all
$a01$,
$a02$  v_on_charger := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN ('dcfc','l2'));
$a02$,
$a03$      IF v_a->>'concurrency' = 'digital' OR v_sensors OR v_free > 0 THEN
$a03$,
$a04$                   || CASE WHEN v_sensors THEN jsonb_build_object('performed_by', 'charger_sensors',
                                                                  'sensor_stall_id', v_stall) ELSE '{}'::jsonb END;
$a04$];
  b text[] := ARRAY[
$b01$  v_on_charger boolean;   -- 0521 (G246): whether that stall is a charger at all
  v_uplink boolean;   -- 0695: whether that stall has a wired data uplink (a charger or a service bay)
$b01$,
$b02$  v_on_charger := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN ('dcfc','l2'));
  v_uplink := EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_stall AND s.stall_type::text IN ('dcfc','l2','service_bay'));
$b02$,
$b03$      -- 0695: a data transfer runs over a stall's wired uplink, so it starts only on a charger or a service bay
      IF COALESCE((v_a->>'needs_uplink')::boolean, false) AND NOT COALESCE(v_uplink, false) THEN
        NULL;
      ELSIF v_a->>'concurrency' = 'digital' OR v_sensors OR v_free > 0 THEN
$b03$,
$b04$                   || CASE WHEN v_sensors THEN jsonb_build_object('performed_by', 'charger_sensors',
                                                                  'sensor_stall_id', v_stall) ELSE '{}'::jsonb END
                   -- 0695: and a transfer on which uplink stall, since it runs only while its car stands there
                   || CASE WHEN COALESCE((v_a->>'needs_uplink')::boolean, false)
                           THEN jsonb_build_object('performed_by', 'stall_uplink', 'uplink_stall_id', v_stall)
                           ELSE '{}'::jsonb END;
$b04$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '8f362785be818b2d5a0794e109da2984' THEN
    RAISE EXCEPTION '0695: the starter is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the starter occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '6e0d5aacde159065832a221751f88426' THEN
    RAISE EXCEPTION '0695: the starter, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)) <> '6e0d5aacde159065832a221751f88426' THEN
    RAISE EXCEPTION '0695: the starter did not read back as written';
  END IF;
END $p_starter$;

-- ── (d) the completion step: a transfer off its stall is not done, and the readiness check waits for it ──
DO $p_atoms$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a01$                         OR (a->>'concurrency' IN ('exterior','digital')) ))
$a01$,
$a02$      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
         AND v_a->>'performed_by' = 'charger_sensors'$a02$,
$a03$                                   AND NOT (COALESCE(o->>'performed_by','') = 'charger_sensors'
                                            AND o->>'sensor_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'sensor_stall_id')::uuid),
$a03$];
  b text[] := ARRAY[
$b01$                         OR (a->>'concurrency' IN ('exterior','digital')
                             -- 0695: a data transfer waits for its car to stand on an uplink stall, and until then
                             -- takes none of this pass's thirty places
                             AND NOT (COALESCE((a->>'needs_uplink')::boolean, false)
                                      AND NOT EXISTS (SELECT 1 FROM stalls su
                                                       WHERE su.id = v.current_stall_id
                                                         AND su.stall_type::text IN ('dcfc','l2','service_bay')))) ))
$b01$,
$b02$      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock
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
         AND v_a->>'performed_by' = 'charger_sensors'$b02$,
$b03$                                   AND NOT (COALESCE(o->>'performed_by','') = 'charger_sensors'
                                            AND o->>'sensor_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'sensor_stall_id')::uuid)
                                   -- 0695: nor a transfer whose car left its uplink stall, which goes back to pending
                                   AND NOT (COALESCE(o->>'performed_by','') = 'stall_uplink'
                                            AND o->>'uplink_stall_id' IS NOT NULL
                                            AND v_rec.current_stall_id IS DISTINCT FROM (o->>'uplink_stall_id')::uuid),
$b03$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'f073e5be363fea71d436c34d790ff610' THEN
    RAISE EXCEPTION '0695: the completion step is not 0657''s, the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the completion step occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '0db32e95d09dabb9f81fe98fa4506f86' THEN
    RAISE EXCEPTION '0695: the completion step, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) <> '0db32e95d09dabb9f81fe98fa4506f86' THEN
    RAISE EXCEPTION '0695: the completion step did not read back as written';
  END IF;
END $p_atoms$;

-- ── (e) the hold ──
CREATE FUNCTION ottoq.ottoq_uplink_transfer_holds(p_vehicle uuid, p_run uuid)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
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
$fn$;
COMMENT ON FUNCTION ottoq.ottoq_uplink_transfer_holds(uuid,uuid) IS
  '0695: true while an unfinished data transfer holds its car on the uplink stall it stands on.';
REVOKE ALL ON FUNCTION ottoq.ottoq_uplink_transfer_holds(uuid,uuid) FROM PUBLIC, anon, authenticated;

DO $p_decide$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  a text[] := ARRAY[
$a01$       AND v.current_state='charge_complete_holding'
       AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
$a01$];
  b text[] := ARRAY[
$b01$       AND v.current_state='charge_complete_holding'
       AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
       -- 0695: nor a car whose data transfer holds it on its uplink stall (docs/DATA_OFFLOAD.md)
       AND NOT ottoq.ottoq_uplink_transfer_holds(v.id, p_sim_run_id)
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '3767f175d775fea6f60bd8bd1c4f1322' THEN
    RAISE EXCEPTION '0695: the decide tick is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the decide tick occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '4c9390adbe2510ce93f69c71960165d1' THEN
    RAISE EXCEPTION '0695: the decide tick, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> '4c9390adbe2510ce93f69c71960165d1' THEN
    RAISE EXCEPTION '0695: the decide tick did not read back as written';
  END IF;
END $p_decide$;

DO $p_flow$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'::regprocedure);
  a text[] := ARRAY[
$a01$       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'charge_complete_holding'
$a01$];
  b text[] := ARRAY[
$b01$       WHERE v.home_depot_id = p_depot_id AND v.current_state = 'charge_complete_holding'
         -- 0695: a car whose data transfer holds it on its charger goes to the wash after the transfer
         AND NOT ottoq.ottoq_uplink_transfer_holds(v.id, p_sim_run_id)
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'a37cfdd807d8dc338d6c5620b70bd404' THEN
    RAISE EXCEPTION '0695: the service flow is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the service flow occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'c0622bc38f68d710bbd51b70fdec49d1' THEN
    RAISE EXCEPTION '0695: the service flow, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'::regprocedure)) <> 'c0622bc38f68d710bbd51b70fdec49d1' THEN
    RAISE EXCEPTION '0695: the service flow did not read back as written';
  END IF;
END $p_flow$;

DO $p_bays$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a01$                               'service_complete_holding'::vehicle_state)
     -- CONTENTION ORDER$a01$];
  b text[] := ARRAY[
$b01$                               'service_complete_holding'::vehicle_state)
       -- 0695: and not a car whose data transfer holds it on its uplink stall: that is live work too
       AND NOT ottoq.ottoq_uplink_transfer_holds(b.vehicle_id, p_sim_run_id)
     -- CONTENTION ORDER$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'eff1f1ab38dff9e61ad045d1dbe0d147' THEN
    RAISE EXCEPTION '0695: the bay-booking activation is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0695: anchor % of the bay-booking activation occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '9feb46eb5c3778cdc8705f3875e4ff5f' THEN
    RAISE EXCEPTION '0695: the bay-booking activation, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamptz)'::regprocedure)) <> '9feb46eb5c3778cdc8705f3875e4ff5f' THEN
    RAISE EXCEPTION '0695: the bay-booking activation did not read back as written';
  END IF;
END $p_bays$;

-- ── (f) the research wing's pair ──
INSERT INTO public.ottoq_dial_experiments
  (created_by, depot_id, param_key, control_value, treatment_value, fixed_params, scenario, ticks, sim_start,
   primary_metric, primary_better, first_look_pairs, final_look_pairs, alpha, guardrail_margin_pct, min_effect_pct,
   guardrail_alpha, hypothesis, status, sim_min_per_tick, run_after)
VALUES
 ('0695', '11111111-1111-1111-1111-111111111111', 'twin_data_offload', 0, 1,
  '{}'::jsonb, 'busy_day', 90, '2026-09-01T13:00:00+00:00', 'deployed_car_hours', 'higher',
  6, 12, 0.05, 2, 0.5, 0.2,
  'A measurement, not a tuning (0695 §2). With twin_data_offload on, each autonomous fleet car''s logged data comes off '
  'over a wired uplink while it charges, sized by its hours out (10-40 minutes, declared 1 TB an hour and 10 Gbps), as a '
  'required service; a car whose transfer outlasts its charge holds its charger until the transfer ends. The pair reads '
  'what the transfers cost the depot: fast-charger and L2 minutes spent holding a charged car, the wait for a charger, '
  'turnaround, deployed car hours, and any car the readiness gate escalates as stuck (a transfer left off its uplink, '
  '§2). The dial is set by a person as a certified change; no verdict here is a recommendation. Nothing lowers a charge '
  'target or skips a service (rule 9). Arms at 6 sim-minutes a tick from 8:00 AM CT for 90 ticks, the shipped defaults '
  'in both.',
  'active', 6, NULL);

-- ── V1a: the observer reports the hours and the deriver raises the transfer at 1, nothing at 0, nothing without a charge ──
CREATE TEMP TABLE p0695 (k text PRIMARY KEY, v jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0695_raise(p_phase text, p_dial numeric, p_soc int) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_run uuid; v_clock timestamptz; v_seed bigint; v_veh uuid; v_obs jsonb; v_atoms jsonb; v_r jsonb; v_msg text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current, COALESCE(r.random_seed, 42) INTO v_run, v_clock, v_seed
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
     AND v.fleet_operator_id IS NOT NULL AND COALESCE(v.battery_capacity_kwh, 0) > 0
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s WHERE s.vehicle_id = v.id AND s.sim_run_id = v_run)
   ORDER BY v.display_name LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL THEN RAISE EXCEPTION '0695 V1: no stopped twin run or no autonomous car to probe'; END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    IF p_dial IS NOT NULL THEN
      INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
      VALUES ('run', v_run, 'twin_data_offload', p_dial, '0695_probe', now());
    END IF;
    UPDATE public.vehicles SET current_soc = p_soc, current_state = 'arrived_at_gate', current_stall_id = NULL,
           robotic_tether_until = NULL, last_state_change = v_clock
     WHERE id = v_veh;
    -- the car's last trip: three hours out, back now (a completed trip names what called it home)
    INSERT INTO public.ottoq_vehicle_dispatches
      (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at, actual_return_at, planned_duration_min,
       soc_at_dispatch_pct, status, return_trigger)
    VALUES (v_veh, v_run, v_clock - interval '3 hours', v_clock, v_clock, 180, 90, 'completed', 'scheduled');
    v_obs := twin.ottoq_sim_observe_asset(v_veh, v_run, v_run, v_seed, v_clock,
                                          '11111111-1111-1111-1111-111111111111');
    v_atoms := ottoq.ottoq_derive_visit_needs(v_veh, v_run, v_run, v_clock, '11111111-1111-1111-1111-111111111111', v_obs);
    v_r := jsonb_build_object(
      'obs_hours', v_obs -> 'data_offload_hours',
      'hours', twin.ottoq_twin_offload_hours(v_veh, v_run, v_clock),
      'charge', (SELECT count(*) FROM jsonb_array_elements(v_atoms) e WHERE e->>'svc' = 'charge'),
      'offload', (SELECT jsonb_agg(e) FROM jsonb_array_elements(v_atoms) e WHERE e->>'svc' = 'data_offload'),
      'stored', (SELECT jsonb_agg(e) FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) e
                  WHERE vn.vehicle_id = v_veh AND vn.sim_run_id = v_run AND vn.status = 'open'
                    AND e->>'svc' = 'data_offload'));
    RAISE EXCEPTION '0695 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0695 PROBED' THEN RAISE EXCEPTION '0695 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0695 VALUES (p_phase, v_r);
END $fn$;

DO $v1a$
DECLARE v_on jsonb; v_off jsonb; v_full jsonb; v_h numeric;
BEGIN
  PERFORM pg_temp.p0695_raise('on', 1, 50);
  PERFORM pg_temp.p0695_raise('off', NULL, 50);
  PERFORM pg_temp.p0695_raise('full', 1, 100);
  SELECT v INTO v_on FROM p0695 WHERE k = 'on';
  SELECT v INTO v_off FROM p0695 WHERE k = 'off';
  SELECT v INTO v_full FROM p0695 WHERE k = 'full';
  v_h := (v_on ->> 'hours')::numeric;
  -- at 1 with a charge to do: one transfer, sized from the hours the observer reported, required, digital, uplink-bound,
  -- and stored without the guard's no-executor tag
  IF v_h IS NULL OR v_h < 3 OR (v_on ->> 'obs_hours')::numeric IS DISTINCT FROM v_h
     OR COALESCE((v_on ->> 'charge')::int, 0) <> 1
     OR jsonb_typeof(v_on -> 'offload') IS DISTINCT FROM 'array' OR jsonb_array_length(v_on -> 'offload') <> 1
     OR (v_on #>> '{offload,0,est_min}')::int IS DISTINCT FROM GREATEST(10, LEAST(40, ceil(v_h * 60.0 / 4.5)))::int
     OR v_on #>> '{offload,0,needs_uplink}' IS DISTINCT FROM 'true' OR v_on #>> '{offload,0,must_do}' IS DISTINCT FROM 'true'
     OR v_on #>> '{offload,0,concurrency}' IS DISTINCT FROM 'digital'
     OR jsonb_typeof(v_on -> 'stored') IS DISTINCT FROM 'array' OR v_on #> '{stored,0}' ? 'no_executor' THEN
    RAISE EXCEPTION '0695 V1 FAILED: with the dial on the transfer was not raised as written: %', v_on;
  END IF;
  -- at 0: no observation, no transfer
  IF v_off ? 'obs_hours' AND jsonb_typeof(v_off -> 'obs_hours') <> 'null'
     OR jsonb_typeof(v_off -> 'offload') IS DISTINCT FROM 'null' THEN
    RAISE EXCEPTION '0695 V1 FAILED: with the dial unset a transfer was observed or raised: %', v_off;
  END IF;
  -- at 1 with no charge to do: the hours are observed and wait for a visit that charges
  IF jsonb_typeof(v_full -> 'obs_hours') IS DISTINCT FROM 'number' OR COALESCE((v_full ->> 'charge')::int, -1) <> 0
     OR jsonb_typeof(v_full -> 'offload') IS DISTINCT FROM 'null' THEN
    RAISE EXCEPTION '0695 V1 FAILED: a visit with no charge raised a transfer: %', v_full;
  END IF;
  RAISE NOTICE '0695 V1a PASSED: dial on, % hours out raised a % minute transfer; dial unset raised none; a full car raised none (all rolled back)',
    round(v_h, 2), v_on #>> '{offload,0,est_min}';
END $v1a$;

-- ── V1b: the transfer starts only on an uplink stall, holds its car there, is reset when its car leaves, and finishes ──
CREATE FUNCTION pg_temp.p0695_transfer() RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  v_run uuid; v_clock timestamptz; v_veh uuid; v_stage uuid; v_l2 uuid; v_visit uuid; v_r jsonb := '{}'::jsonb;
  v_msg text;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
     AND v.fleet_operator_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_owner_settings s WHERE s.vehicle_id = v.id AND s.sim_run_id = v_run)
     AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions o WHERE o.vehicle_id = v.id AND o.status = 'active')
     AND NOT EXISTS (SELECT 1 FROM public.stalls st WHERE st.current_vehicle_id = v.id OR st.reserved_by = v.id)
   ORDER BY v.display_name DESC LIMIT 1;
  SELECT s.id INTO v_stage FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'staging'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
   ORDER BY s.stall_code, s.id LIMIT 1;
  SELECT s.id INTO v_l2 FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type = 'l2'
     AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.current_stall_id = s.id)
   ORDER BY s.stall_code, s.id LIMIT 1;
  IF v_run IS NULL OR v_veh IS NULL OR v_stage IS NULL OR v_l2 IS NULL THEN
    RAISE EXCEPTION '0695 V1: no stopped twin run, no free autonomous car, staging stall or L2 stall to probe';
  END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    -- the car waiting in staging, its charge done, its transfer not yet started
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = v_veh AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_stall_id = v_stage, current_soc = 100,
           robotic_tether_until = NULL, last_state_change = v_clock,
           config = COALESCE(config, '{}'::jsonb) - 'svc_step'
     WHERE id = v_veh;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (v_veh, v_run, '11111111-1111-1111-1111-111111111111', v_clock - interval '1 hour', '0695_probe',
            '[{"svc": "charge", "status": "done", "must_do": true, "concurrency": "anchor"},
              {"svc": "data_offload", "status": "pending", "must_do": true, "deferrable": false, "est_min": 12,
               "concurrency": "digital", "needs_uplink": true, "hours_out": 2.5},
              {"svc": "readiness_check", "status": "pending", "must_do": true, "concurrency": "gate"}]'::jsonb,
            'in_progress')
    RETURNING visit_id INTO v_visit;
    -- each start is read back in a statement of its own: a statement's subqueries see the rows as the statement began,
    -- so a read beside the call that starts the transfer would see it pending whatever the call did (the first apply
    -- of this file, 2026-10-10 11:31 UTC, failed on exactly that)
    v_r := v_r || jsonb_build_object('started_in_staging', public.ottoq_start_concurrent_atoms(v_veh, v_clock));
    v_r := v_r || jsonb_build_object(
      'in_staging', (SELECT a FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                      WHERE vn.visit_id = v_visit AND a->>'svc' = 'data_offload'),
      'holds_in_staging', ottoq.ottoq_uplink_transfer_holds(v_veh, v_run));
    -- the car on an L2 charger
    UPDATE public.vehicles SET current_state = 'charge_complete_holding', current_stall_id = v_l2 WHERE id = v_veh;
    v_r := v_r || jsonb_build_object('holds_on_charger_pending', ottoq.ottoq_uplink_transfer_holds(v_veh, v_run));
    v_r := v_r || jsonb_build_object('started_on_charger', public.ottoq_start_concurrent_atoms(v_veh, v_clock));
    v_r := v_r || jsonb_build_object(
      'on_charger', (SELECT a FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                      WHERE vn.visit_id = v_visit AND a->>'svc' = 'data_offload'),
      'holds_running', ottoq.ottoq_uplink_transfer_holds(v_veh, v_run));
    -- moved off before its minutes ran out (a path the hold does not cover) and staged to leave, and the minutes pass:
    -- the readiness check would close here under 0657 alone, which reads a transfer whose minutes ran out as finishing
    UPDATE public.vehicles SET current_state = 'staged_for_departure', current_stall_id = v_stage WHERE id = v_veh;
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock + interval '13 minutes');
    v_r := v_r || jsonb_build_object(
      'after_leaving', (SELECT a FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                         WHERE vn.visit_id = v_visit AND a->>'svc' = 'data_offload'),
      'readiness_after_leaving', (SELECT a->>'status' FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                                   WHERE vn.visit_id = v_visit AND a->>'svc' = 'readiness_check'));
    -- back on the charger: it starts again and finishes there
    UPDATE public.vehicles SET current_state = 'charge_complete_holding', current_stall_id = v_l2 WHERE id = v_veh;
    PERFORM public.ottoq_start_concurrent_atoms(v_veh, v_clock + interval '13 minutes');
    PERFORM twin.ottoq_sim_advance_visit_atoms(v_run, v_clock + interval '26 minutes');
    v_r := v_r || jsonb_build_object(
      'finished', (SELECT a FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                    WHERE vn.visit_id = v_visit AND a->>'svc' = 'data_offload'),
      'holds_after', ottoq.ottoq_uplink_transfer_holds(v_veh, v_run),
      'l2', v_l2, 'clock', v_clock);
    RAISE EXCEPTION '0695 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0695 PROBED' THEN RAISE EXCEPTION '0695 transfer probe failed: %', v_msg; END IF;
  RETURN v_r;
END $fn$;

DO $v1b$
DECLARE v jsonb := pg_temp.p0695_transfer();
BEGIN
  IF v #>> '{in_staging,status}' IS DISTINCT FROM 'pending' OR v ->> 'holds_in_staging' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION '0695 V1 FAILED: a transfer started, or held its car, off an uplink stall: %', v;
  END IF;
  IF v ->> 'holds_on_charger_pending' IS DISTINCT FROM 'true' OR COALESCE((v ->> 'started_on_charger')::int, 0) < 1
     OR v #>> '{on_charger,status}' IS DISTINCT FROM 'in_progress'
     OR v #>> '{on_charger,performed_by}' IS DISTINCT FROM 'stall_uplink'
     OR v #>> '{on_charger,uplink_stall_id}' IS DISTINCT FROM v ->> 'l2'
     OR (v #>> '{on_charger,ends_at}')::timestamptz IS DISTINCT FROM (v ->> 'clock')::timestamptz + interval '12 minutes'
     OR v ->> 'holds_running' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0695 V1 FAILED: on a charger the transfer did not start there and hold its car: %', v;
  END IF;
  IF v #>> '{after_leaving,status}' IS DISTINCT FROM 'pending' OR v #> '{after_leaving}' ? 'performed_by'
     OR v #>> '{after_leaving,interrupted,0,reason}' IS DISTINCT FROM 'left_the_uplink'
     OR v ->> 'readiness_after_leaving' IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION '0695 V1 FAILED: a transfer whose car left its uplink was credited, or the readiness check did not wait: %', v;
  END IF;
  IF v #>> '{finished,status}' IS DISTINCT FROM 'done'
     OR (v #>> '{finished,done_at}')::timestamptz IS DISTINCT FROM (v ->> 'clock')::timestamptz + interval '25 minutes'
     OR v ->> 'holds_after' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION '0695 V1 FAILED: back on the charger the transfer did not finish and let its car go: %', v;
  END IF;
  RAISE NOTICE '0695 V1b PASSED: not started in staging; started on the L2 and held there; reset when the car left, with the readiness check of a car staged to leave waiting for it; finished back on the charger and released it (all rolled back)';
END $v1b$;

-- ── V2: the definitions as written, the service declared, the dial set nowhere, the experiment as written ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_visit_atoms(uuid,timestamptz)'::regprocedure)) <> '0db32e95d09dabb9f81fe98fa4506f86'
     OR md5(pg_get_functiondef('twin.ottoq_sim_observe_asset(uuid,uuid,uuid,bigint,timestamptz,uuid)'::regprocedure)) <> '24104d1d4e8d66ff634bd19c78d59c06'
     OR md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure)) <> '9ae0558f6a6ce8ca6d14ba3b9dc3c28b'
     OR md5(pg_get_functiondef('ottoq.ottoq_atom_retirable_set()'::regprocedure)) <> 'c4394d5f67de33045587e6abdf182a33'
     OR md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)) <> '6e0d5aacde159065832a221751f88426'
     OR md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> '4c9390adbe2510ce93f69c71960165d1'
     OR md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamptz,numeric,uuid)'::regprocedure)) <> 'c0622bc38f68d710bbd51b70fdec49d1'
     OR md5(pg_get_functiondef('ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamptz)'::regprocedure)) <> '9feb46eb5c3778cdc8705f3875e4ff5f' THEN
    RAISE EXCEPTION '0695 V2 FAILED: a patched definition is not as written';
  END IF;
  IF NOT ottoq.ottoq_atom_retirable('data_offload') THEN
    RAISE EXCEPTION '0695 V2 FAILED: data_offload is not retirable';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_assert_service_vocabulary() WHERE cardinality(undeclared) > 0) THEN
    RAISE EXCEPTION '0695 V2 FAILED: the service vocabulary reports an undeclared service';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_data_offload') THEN
    RAISE EXCEPTION '0695 V2 FAILED: the dial is set somewhere';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments e JOIN public.ottoq_policy_param_catalog c USING (param_key)
                  WHERE e.created_by = '0695' AND e.status = 'active' AND e.param_key = 'twin_data_offload'
                    AND e.control_value BETWEEN c.min_value AND c.max_value
                    AND e.treatment_value BETWEEN c.min_value AND c.max_value) THEN
    RAISE EXCEPTION '0695 V2 FAILED: the experiment is not active with its dial in range';
  END IF;
  IF has_function_privilege('anon', 'ottoq.ottoq_uplink_transfer_holds(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'twin.ottoq_twin_offload_hours(uuid,uuid,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION '0695 V2 FAILED: the public key can call a helper';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block') THEN
    RAISE EXCEPTION '0695 V2 FAILED: the run-scope registry reports a blocking defect, so the purge would refuse';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0695_an_autonomous_cars_data_comes_off_while_it_charges', false, false,
  'Part A item 3: data offload, behind twin_data_offload. The catalog row and the retirable set; the twin''s observer '
  'reports an autonomous car''s hours out at 1; the deriver raises a required, uplink-bound transfer on a visit that '
  'charges; the starter starts it only on a charger or a service bay; the completion step resets one whose car left its '
  'stall and the readiness check waits for it; OTTO-Q''s charge disposition, the wash admission and the bay-booking '
  'activation hold a car whose transfer is unfinished on its uplink stall; the pair registered. At 0 nothing is '
  'observed or raised and every patched path keys on an atom only the dial raises (V1): FALSE/FALSE.',
  now());

COMMIT;
