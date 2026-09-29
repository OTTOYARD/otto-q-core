-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    the_gates_patience_flag_is_a_note_for_a_person_not_service_work
-- (applied 2026-09-28, 4:25 PM CT, in the same transaction as 0555 through apply_migration, which wrote ONE ledger row
--  for the two files: version 20260928212503, name a_faulted_car_is_repaired_and_the_gate_flag_is_a_note, carried by
--  0555's header. This file has no row of its own; its APPLIED footer is its record.)
--
-- 0556  **The readiness gate's patience flag is a note for a person, not service work.** (G289)
--
-- ══ §1 WHY (check 0410 §26, run ab8075a3) ══════════════════════════════════════════════════════════════════════════════
--
--   The readiness gate flags a car it has held past 45 minutes (`deploy_gate_stuck`) or 240 (`deploy_gate_hard_cap`)
--   with `flagged_issue`, so that a person sees it. A car the gate holds for its wash or deep clean leaves through that
--   bay's exit, not through the gate's release, and the exit read `flagged_issue` as service work
--   (`v_needs_svc` in `twin.ottoq_sim_advance_service_flow`). The car was staged on need_service with nothing on its card,
--   and only a service-bay visit took the flag off (0475). 0546 (b) drops the flag at the gate's release (G273); the bay
--   exit was the other door, and G273 named it. On ab8075a3 6 of the 25 service-bay visits credited nothing and only
--   cleared the flag: 268.1 of 974.2 bay-minutes. 36.7 of the 70.2 car-hours staged for a bay were cars carrying it, at
--   100% with every atom done, and 4 of the day's 5 `waiting_for_the_service_bay` escalations were these cars. Before
--   0554 the service lane seated them by staff count in no bay (G286), so the cost was staff time; under 0554 they queue
--   for the depot's two service bays.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `public.ottoq_flag_needs_service(config)`: a technician flag sends a car to the service bay unless the readiness
--       gate raised it (`deploy_gate_stuck`, `deploy_gate_hard_cap`). The gate's flag says the car waited; it is not work.
--   (b) The wash and detail bays' exit reads it, and drops a gate-raised flag, as the release does (0546 (b)): the bay did
--       the work the gate held the car for. The car goes back to the gate, which flags it again if it waits again.
--   (c) The service lane's need gate (0468) reads it, so a car already staged on need_service for the gate's flag alone
--       goes back to the gate.
--   (d) `ottoq_l2_propose_charge_disposition` reads it: a car leaving a charger with the gate's flag and no service work
--       is not routed to the service bay.
--   A flag anything else raised routes to the service bay as before. The escalation events stay in the signed stream.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   The service flow and the charge disposition run in every arm.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The gate's flag still shows in the cockpits while the car waits. The escalation at 240 minutes is the one that asks
--     a person to act.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0556 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run at the twin depot (V3 edits twin cars, visits and bays on an ended run) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0556 P1: a run is live at the twin depot';
  END IF;
END $live$;

-- ── P2: the two functions are the ones measured (the service flow as 0555 leaves it), and the new name is free ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure)
     <> '913c3bc81e2599827c1f57d9296b0202' THEN
    RAISE EXCEPTION '0556 P2: twin.ottoq_sim_advance_service_flow is not the function 0555 leaves';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure)
     <> '990e49fbfad08850a3cbbcc8eb5e5d42' THEN
    RAISE EXCEPTION '0556 P2: public.ottoq_l2_propose_charge_disposition is not the function measured';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_flag_needs_service') THEN
    RAISE EXCEPTION '0556 P2: public.ottoq_flag_needs_service already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0556_pre', 'function', p.pronamespace::regnamespace::text, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure,
                 'public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure);

-- ── (a) one answer to "does this flag send the car to the service bay" ──
CREATE FUNCTION public.ottoq_flag_needs_service(p_config jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0556 (G289): a technician flag (config.flagged_issue) is service-bay work, unless the readiness gate raised it for a
  -- car that waited too long (deploy_gate_stuck, deploy_gate_hard_cap). That flag is a note for a person, not work.
  SELECT COALESCE((p_config->>'flagged_issue')::boolean, false)
     AND COALESCE(p_config->>'flagged_issue_type', '') NOT IN ('deploy_gate_stuck', 'deploy_gate_hard_cap')
$fn$;
COMMENT ON FUNCTION public.ottoq_flag_needs_service(jsonb) IS
  '0556 (G289): true when the car carries a technician flag that asks for the service bay. The readiness gate''s own '
  'patience flags (deploy_gate_stuck, deploy_gate_hard_cap) are a note that the car waited, not service work.';

-- ── (b) + (c): the wash and detail exit, and the service lane's need gate ──
DO $flow$
DECLARE v_def text; n int; i int;
  a_old text[] := ARRAY[
$o1$v_needs_svc := COALESCE((v_rec.config->>'flagged_issue')::boolean, FALSE);
$o1$,
$o2$'{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion' - 'bay_need'
       WHERE id = v_rec.id;
    ELSE
$o2$,
$o3$     AND NOT COALESCE((v.config->>'flagged_issue')::boolean, false)
$o3$];
  a_new text[] := ARRAY[
$n1$v_needs_svc := public.ottoq_flag_needs_service(v_rec.config);   -- 0556 (G289): the gate's own flag is a note, not work
$n1$,
$n2$'{service_ends_at}', 'null'::jsonb) - 'service_done' - 'awaiting_external_completion' - 'bay_need'
                    -- 0556 (G289): the bay did the work the gate held the car for, so the gate's flag goes too (0546 (b))
                    - (CASE WHEN config->>'flagged_issue_type' IN ('deploy_gate_stuck', 'deploy_gate_hard_cap')
                            THEN ARRAY['flagged_issue', 'flagged_issue_type'] ELSE ARRAY[]::text[] END)
       WHERE id = v_rec.id;
    ELSE
$n2$,
$n3$     AND NOT public.ottoq_flag_needs_service(v.config)   -- 0556 (G289): but not the readiness gate's own flag
$n3$];
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  FOR i IN 1 .. 3 LOOP
    n := (length(v_def) - length(replace(v_def, a_old[i], ''))) / length(a_old[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0556 service flow: anchor % matches % times, not 1', i, n; END IF;
    v_def := replace(v_def, a_old[i], a_new[i]);
  END LOOP;
  EXECUTE v_def;
END $flow$;

-- ── (d) the charge disposition ──
DO $disposition$
DECLARE v_def text; n int;
  c_old CONSTANT text := $old$    OR COALESCE((SELECT v.config->>'flagged_issue' FROM vehicles v WHERE v.id = p_vehicle_id),'false')
       IN ('true','t','1');$old$;
  c_new CONSTANT text := $new$    -- 0556 (G289): a technician flag routes to the service bay, but not the readiness gate's own
    OR COALESCE((SELECT public.ottoq_flag_needs_service(v.config) FROM vehicles v WHERE v.id = p_vehicle_id), false);$new$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0556 charge disposition: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $disposition$;

-- ── V1 (comment-stripped): each change is in the live source ──
DO $verify$
DECLARE r record; v_src text; k int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       'v_needs_svc := public\.ottoq_flag_needs_service\(v_rec\.config\);', 1),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       '''bay_need''\s+- \(CASE WHEN config->>''flagged_issue_type'' IN \(''deploy_gate_stuck'', ''deploy_gate_hard_cap''\)\s+THEN ARRAY\[''flagged_issue'', ''flagged_issue_type''\] ELSE ARRAY\[\]::text\[\] END\)\s+WHERE id = v_rec\.id;', 1),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       'AND NOT public\.ottoq_flag_needs_service\(v\.config\)', 1),
      ('public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb)',
       'OR COALESCE\(\(SELECT public\.ottoq_flag_needs_service\(v\.config\) FROM vehicles v WHERE v\.id = p_vehicle_id\), false\);', 1)
    ) x(sig, pat, want)
  LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    k := (SELECT count(*) FROM regexp_matches(v_src, r.pat, 'g'));
    IF k <> r.want THEN RAISE EXCEPTION '0556 V1: % matches % times in %, not %', r.pat, k, r.sig, r.want; END IF;
  END LOOP;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0556_the_gates_patience_flag_is_a_note_for_a_person_not_service_work', true, true,
  'G289: the readiness gate''s own patience flag (deploy_gate_stuck, deploy_gate_hard_cap) sent finished cars to the '
  'service bay through the wash and detail exit (0410 §26: 6 of 25 service-bay visits credited nothing but the flag). '
  'public.ottoq_flag_needs_service reads a technician flag as service work unless the gate raised it; the exit drops the '
  'gate''s flag, and the service lane''s need gate and the charge disposition read the same answer.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the latest ended operator run at the twin depot, pinned as the active run for this transaction.
--   Every other twin car is offline (the run's teardown). Five cars:
--   G1 leaves a detail bay with its deep clean done, carrying the gate's `deploy_gate_stuck`: it must not be staged for
--      the service bay, and the flag must go;
--   G2 leaves a detail bay the same way carrying a flag the gate did not raise (`sensor_anomaly`): it must be staged for
--      the service bay with the flag kept, as before;
--   G3 is staged on need_service with the gate's flag and no service work on its card: the need gate must send it back;
--   G4 and G5 are off a charger with no wash or service work, carrying the gate's flag and `sensor_anomaly`: the charge
--      disposition must send G4 to the gate and G5 to the service bay.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  t timestamptz; car uuid[]; wb uuid[]; g1 uuid; g2 uuid; g3 uuid; g4 uuid; g5 uuid;
  s1 text; s2 text; s3 text; f1 boolean; f2 text; d4 jsonb; d5 jsonb; v_pass text;
BEGIN
  BEGIN
    SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
     WHERE r.depot_id = v_depot AND r.run_by = 'operator_demo' AND r.status NOT IN ('initializing', 'running', 'paused')
     ORDER BY r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0556 V3: no ended operator run at the twin depot'; END IF;
    SELECT sim_clock_current + interval '1 day' INTO t FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = t, tick_count = tick_count + 1 WHERE sim_run_id = v_run;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('search_path', 'twin, ottoq, public, extensions', true);

    SELECT array_agg(id ORDER BY distance_from_entrance NULLS LAST, stall_code) INTO wb
      FROM public.stalls WHERE depot_id = v_depot AND stall_type::text = 'wash_bay' AND status NOT IN ('maintenance', 'closed');
    IF coalesce(array_length(wb, 1), 0) < 2 THEN RAISE EXCEPTION '0556 V3: fewer than two open wash bays'; END IF;
    SELECT array_agg(id ORDER BY id) INTO car FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.current_stall_id IS NULL
         AND v.robotic_tether_until IS NULL
         AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = v.id OR s.reserved_by = v.id)
       ORDER BY v.id LIMIT 5) q;
    IF coalesce(array_length(car, 1), 0) < 5 THEN RAISE EXCEPTION '0556 V3: fewer than five free twin cars'; END IF;
    g1 := car[1]; g2 := car[2]; g3 := car[3]; g4 := car[4]; g5 := car[5];

    -- only these five in play: every other twin car off the site, the wash bays empty and free
    UPDATE public.vehicles SET current_state = 'offline'
     WHERE home_depot_id = v_depot AND NOT (id = ANY (car)) AND robotic_tether_until IS NULL AND current_state <> 'offline';
    UPDATE public.vehicles SET current_stall_id = NULL WHERE current_stall_id = ANY (wb) AND NOT (id = ANY (car));
    UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL,
           status = 'available' WHERE id = ANY (wb);
    UPDATE public.ottoq_stall_bookings SET state = 'released', released_at = t, release_reason = 'v3_0556'
     WHERE stall_id = ANY (wb) AND sim_run_id = v_run AND state IN ('held', 'active') AND upper(during) > t - interval '1 day';
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (car) AND sim_run_id = v_run AND status IN ('open', 'in_progress');

    UPDATE public.vehicles
       SET current_depot_id = v_depot, current_soc = 100, target_soc = 100, last_state_change = t - interval '30 minutes',
           current_stall_id = CASE WHEN id = g1 THEN wb[1] WHEN id = g2 THEN wb[2] END,
           current_state = CASE WHEN id IN (g1, g2) THEN 'in_detail_bay'
                                WHEN id = g3 THEN 'staged_awaiting_service'
                                ELSE 'charge_complete_holding' END::vehicle_state,
           config = (COALESCE(config, '{}'::jsonb) - 'flagged_issue' - 'flagged_issue_type' - 'service_ends_at' - 'svc_step'
                     - 'exception' - 'remedy_wait' - 'deploy_gate' - 'charge_wait' - 'bay_need')
                    || jsonb_build_object('flagged_issue', true,
                         'flagged_issue_type', CASE WHEN id IN (g2, g5) THEN 'sensor_anomaly' ELSE 'deploy_gate_stuck' END)
                    || CASE WHEN id IN (g1, g2) THEN jsonb_build_object('service_ends_at', t - interval '1 minute', 'svc_step', 'washing')
                            WHEN id = g3 THEN jsonb_build_object('svc_step', 'need_service')
                            ELSE '{}'::jsonb END
     WHERE id = ANY (car);
    UPDATE public.stalls SET current_vehicle_id = CASE WHEN id = wb[1] THEN g1 ELSE g2 END, status = 'occupied'
     WHERE id IN (wb[1], wb[2]);
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, target_soc, atoms,
                                          status, source)
    SELECT x.vid, v_run, v_depot, t - interval '2 hours', 'V3-0556-' || x.tag, 'standard', 100, x.atoms, 'open', 'v3_0556'
      FROM (VALUES
        (g1, 'G1', jsonb_build_array(jsonb_build_object('svc', 'interior_deep_clean', 'concurrency', 'bay', 'must_do', true, 'status', 'in_progress'),
                                     jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending'))),
        (g2, 'G2', jsonb_build_array(jsonb_build_object('svc', 'interior_deep_clean', 'concurrency', 'bay', 'must_do', true, 'status', 'in_progress'),
                                     jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending'))),
        (g3, 'G3', jsonb_build_array(jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending'))),
        (g4, 'G4', jsonb_build_array(jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending'))),
        (g5, 'G5', jsonb_build_array(jsonb_build_object('svc', 'readiness_check', 'concurrency', 'gate', 'must_do', true, 'status', 'pending')))
      ) x(vid, tag, atoms);

    -- the charge disposition, before the service flow moves anything
    d4 := public.ottoq_l2_propose_charge_disposition(g4, v_depot, jsonb_build_object('sim_run_id', v_run));
    d5 := public.ottoq_l2_propose_charge_disposition(g5, v_depot, jsonb_build_object('sim_run_id', v_run));
    IF d4->>'next_step' IS DISTINCT FROM 'need_deploy' OR d5->>'next_step' IS DISTINCT FROM 'need_service' THEN
      RAISE EXCEPTION '0556 V3 FAILED: the charge disposition sent G4 (the gate''s flag) to % and G5 (sensor_anomaly) to %',
        d4->>'next_step', d5->>'next_step';
    END IF;

    -- one pass of the service flow: G1 and G2 leave the detail bays, the need gate reads G3
    PERFORM twin.ottoq_sim_advance_service_flow(v_run, t, 30, v_depot);
    SELECT config->>'svc_step', COALESCE((config->>'flagged_issue')::boolean, false) INTO s1, f1 FROM public.vehicles WHERE id = g1;
    SELECT config->>'svc_step', config->>'flagged_issue_type' INTO s2, f2 FROM public.vehicles WHERE id = g2;
    SELECT config->>'svc_step' INTO s3 FROM public.vehicles WHERE id = g3;
    IF s1 = 'need_service' OR f1 THEN
      RAISE EXCEPTION '0556 V3 FAILED: G1 (the gate''s flag) left the detail bay on step % with the flag %', s1, f1;
    END IF;
    IF s2 IS DISTINCT FROM 'need_service' OR f2 IS DISTINCT FROM 'sensor_anomaly' THEN
      RAISE EXCEPTION '0556 V3 FAILED: G2 (sensor_anomaly) left the detail bay on step % with flag %', s2, f2;
    END IF;
    IF s3 = 'need_service' THEN
      RAISE EXCEPTION '0556 V3 FAILED: G3 (the gate''s flag, no service work) is still staged for the service bay';
    END IF;

    v_pass := format('0556 V3 PASSED on run %s: out of the detail bay G1 (deploy_gate_stuck) went to step %s with the flag '
                     || 'dropped, G2 (sensor_anomaly) to need_service with its flag; the need gate moved G3 to %s; the '
                     || 'charge disposition sent G4 (the gate''s flag) to need_deploy and G5 (sensor_anomaly) to need_service',
                     v_run, s1, s3);
    RAISE EXCEPTION '%', v_pass;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0556 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0556 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0556_pre' as it is, then DROP FUNCTION
-- public.ottoq_flag_needs_service(jsonb).

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-28 to gxdrcyphqjzjsuhxuqtg, 4:25 PM CT, in one transaction with 0555 (ledger 20260928212503).
--   twin.ottoq_sim_advance_service_flow          913c3bc81e2599827c1f57d9296b0202 -> 0b852abe1944dd93f8e35c9d2f6967bd
--   public.ottoq_l2_propose_charge_disposition   990e49fbfad08850a3cbbcc8eb5e5d42 -> 9e6ca1d95a3053ce4f50901cb723c0d5
--   created: public.ottoq_flag_needs_service (4a4b34dbc25397403462a492c1827546).
--   P2 read the service flow as 0555 leaves it (913c3bc8...), so the premise held in the joint transaction. V1 and V3
--   passed: the transaction commits only if both do.
