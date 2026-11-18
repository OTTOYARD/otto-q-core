-- migration-version: 20261118184018
-- migration-name:    0848_a_service_bay_seat_proposed_from_outside_is_taken_only_while_the_car_still_owes_the_bay
--
-- 0848  **A service-bay seat proposed from outside the decide tick is taken only while the car still owes the bay
--        something: section (5) checks the proposal against its own answer at that tick, and the proposer calls a car
--        must-do only for service-bay work.** G558, CLAUDE.md rule 15.
--
-- WHY. The demo run that checked 0847 (02fca960, busy_day on 52dfc2d3's seed, 2026-11-18 12:16 to 12:28 PM CT) seated six
--   cars in the service bays in 95 sim-minutes. Two of them owed the bays nothing. Zoox-002 and Waymo-AV-027 each had an
--   interior deep clean, the only work left on their visits, done by the cleaning arm at their charger posts (0817). While
--   the cleans ran, ottoq_service_priority_propose wrote an outside 'admit_service' for each car: it proposes for any car
--   whose svc_step reads need_service, and its has_must_do counts every pending must-do service but readiness_check, so a
--   cabin clean made the car "must-do" for a service bay. Section (5) of ottoq_decide_tick takes an outside proposal as
--   it stands (COALESCE(ottoq_l2_external_proposal(...), ottoq_l2_propose_service(...))), and ottoq_l2_external_proposal
--   keeps a proposal at least 35 real minutes whatever lifetime it was given (120 seconds here), which is 4.7 sim-hours at
--   8x. Section (5) took the two proposals 2 and 72 seconds after the cleans had finished, with svc_step need_deploy and no
--   service-bay atom on either visit, and seated each car for 45 minutes. Section (5)'s own heuristic,
--   ottoq_l2_propose_service, admits only a car whose step reads need_service or whose visit holds service-bay work; it
--   would have promoted both. Hidden until 0847, because the needs card's starting must-dos kept both bays full.
--   What set the two cars' step to need_service for one tick when their charges finished is not established here: the
--   charge disposition, the gate intake and the deploy gate all require service-bay work or a technician flag, and
--   neither car had either. The service flow put them back to need_deploy the next tick.
--
-- §1 WHAT THIS DOES.
--   public.ottoq_decide_tick, section (5): an outside 'admit_service' is taken only when ottoq_l2_propose_service, asked
--     at the same tick with the same context, would also admit the car. Otherwise the heuristic's own answer is taken.
--     Any other outside verb is taken as before, and so is an outside admit the heuristic agrees with.
--   public.ottoq_service_priority_propose: has_must_do counts only pending must-do atoms whose service-cadence lane is
--     'service_bay'. A car's cabin, digital or wash work no longer ranks it as must-do for a service bay.
--   Rules: no car with service-bay work is refused a bay it is owed, and nothing a car needs is skipped (9); a car with
--   no bay work goes on with its visit as section (5) would have sent it. "Agents propose, solver disposes" (2.5): the
--   disposer checks an outside proposal against its own answer. No setting (10). One demo run (12). Rule 15 is the
--   reason for the file.
--
-- §2 PRECONDITIONS AND CHECKS. P0 no certification in flight and no run at the twin depot running, paused or pending.
--   P1 the two bodies (md5 of prosrc). P2 once. V1 each anchor matched once; each function stored as patched and, with
--   its patch reversed, its snapshot.
--   V2 a probe, rolled back, on the twin depot's newest run, with three cars whose needs cards are empty and who owe no
--   tire job, the service bays clear:
--     tick: car A waits in staging with svc_step need_deploy and no visit; car B waits with svc_step need_service and no
--       visit (the heuristic's flag path). Each has a fresh outside admit_service, as ottoq_service_priority_propose
--       writes them. Then ottoq_decide_tick. Before: both are sent to a service bay (G558 reproduced). After: A is not,
--       and its decision is the heuristic's; B still is; the tick errs nowhere.
--     propose: car C waits with svc_step need_service and a visit holding one pending must-do interior deep clean. Then
--       ottoq_service_priority_propose. Before: C's proposal reads must_do true. After: false, and C is still proposed.
--
-- §3 CLASSIFICATION. forces_recert TRUE: section (5) refuses admissions it used to take. forces_dial_restart FALSE, as
--   for 0844 and 0845. Rule 12: nothing acts on either until testing resumes.
--
-- APPLIED 2026-11-18 at 18:40:18 UTC (12:40 PM CT), ledger 20261118184018, through apply_migration, on the first send.
--   No run was live: the twin depot's newest run, 02fca960, had ended at 18:28:03 UTC. A dry run of the same statements,
--   ending in a raise that rolled everything back, ran first on 02fca960's clock (sim 9:35 AM CT). Before the patches:
--   car A, with no service-bay work, svc_step need_deploy and an outside admit_service, was sent to a service bay, and so
--   was car B (need_service); car C, owing only an interior deep clean, was proposed with must_do true. After them: A was
--   not sent and its decision was the heuristic's promote_ready; B was still sent; C was still proposed, with must_do
--   false; the tick erred nowhere. The apply's own V2a and V2b passed. The ledger holds this whole file byte for byte as
--   committed before this note (md5 8a5ba4495755ccbc6fe65fe5de85838c). Read after the apply, md5(prosrc):
--   public.ottoq_decide_tick 66a66fa24c6a1abc01d10fe7a5e6d99f (was e1ef8490217afdb498af7b8d7b7b5859),
--   public.ottoq_service_priority_propose 47beb6904c8b98b9eeb19ebbc744ea02 (was 63f81c41620680d60d1c052c1bdf2fd2).
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0848_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0848_%'.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0848 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                                                   AND status IN ('running', 'paused', 'pending')) THEN
    RAISE EXCEPTION '0848 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM 'e1ef8490217afdb498af7b8d7b7b5859' THEN
    RAISE EXCEPTION '0848 P1: public.ottoq_decide_tick is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_service_priority_propose(uuid)'))
     IS DISTINCT FROM '63f81c41620680d60d1c052c1bdf2fd2' THEN
    RAISE EXCEPTION '0848 P1: public.ottoq_service_priority_propose is not the body this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0848_%') THEN
    RAISE EXCEPTION '0848 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0848_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_decide_tick(uuid)', 'public.ottoq_service_priority_propose(uuid)']) AS f;

-- V2: the probe. It raises to roll its writes back; the answer comes back as the exception's detail.
CREATE FUNCTION pg_temp._0848_probe(p_mode text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_cars uuid[]; v_a uuid; v_b uuid; v_c uuid; v_r jsonb := '{}'; v_detail text;
BEGIN
  BEGIN
    SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
      FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot
     ORDER BY (r.status = 'running') DESC, r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0848 V2: no run at the twin depot to probe with'; END IF;
    -- three cars whose needs cards ask for nothing and who owe no tire job, so no other section of the tick acts first
    SELECT array_agg(c.vehicle_id ORDER BY c.display_name) INTO v_cars
      FROM public.ottoq_vehicle_needs_card c
     WHERE c.depot_id = c_depot AND cardinality(c.must_do_now) = 0
       AND NOT public.ottoq_tire_job_owed(c.vehicle_id, v_clock);
    v_a := v_cars[1]; v_b := v_cars[2]; v_c := v_cars[3];
    IF v_c IS NULL THEN RAISE EXCEPTION '0848 V2: fewer than three cars with an empty needs card'; END IF;
    -- the service bays clear, and the three cars charged and waiting in staging with no open visit
    UPDATE public.ottoq_stall_bookings b SET state = 'released'
      FROM public.stalls s WHERE s.id = b.stall_id AND s.depot_id = c_depot AND s.stall_type::text = 'service_bay'
       AND b.state IN ('held', 'active') AND b.during && tstzrange(v_clock - interval '2 hours', v_clock + interval '4 hours');
    UPDATE public.vehicles SET current_state = 'staged_for_departure'
     WHERE home_depot_id = c_depot AND current_state = 'in_service_bay';
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id IN (v_a, v_b, v_c) AND status IN ('open', 'in_progress');
    UPDATE public.vehicles
       SET current_state = 'staged_awaiting_service', current_soc = 100,
           last_state_change = v_clock - CASE WHEN id = v_a THEN interval '20 minutes' WHEN id = v_b THEN interval '15 minutes'
                                              ELSE interval '10 minutes' END,
           config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}',
                              to_jsonb(CASE WHEN id = v_a THEN 'need_deploy' ELSE 'need_service' END))
     WHERE id = ANY (CASE WHEN p_mode = 'tick' THEN ARRAY[v_a, v_b] ELSE ARRAY[v_c] END);
    IF p_mode = 'tick' THEN
      PERFORM public.ottoq_submit_external_proposal(v_run, c_depot, 'service_sequencing', 'vehicle', x,
                jsonb_build_object('abstain', false, 'resolved_action_context', 'task_start', 'verb', 'admit_service',
                                   'vehicle_id', x, 'requested_kw', 0, 'l2_engine', 'ottoq_service_priority',
                                   'rationale', jsonb_build_object('probe', '0848')),
                'ottoq_service_priority', 120)
        FROM unnest(ARRAY[v_a, v_b]) AS x;
      v_r := jsonb_build_object('tick', (SELECT to_jsonb(t) FROM public.ottoq_decide_tick(v_run) t));
      v_r := v_r || jsonb_build_object(
        'a_sent', EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.vehicle_id = v_a
                            AND c.command_type = 'enter_service' AND c.issued_at = v_clock),
        'b_sent', EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands c WHERE c.sim_run_id = v_run AND c.vehicle_id = v_b
                            AND c.command_type = 'enter_service' AND c.issued_at = v_clock),
        'a_verb', (SELECT d.enacted_action ->> 'verb' FROM public.ottoq_decisions d
                    WHERE d.sim_run_id = v_run AND d.entity_id = v_a AND d.sim_clock = v_clock AND d.action_context = 'task_start'
                    ORDER BY d.decision_seq DESC LIMIT 1),
        'b_verb', (SELECT d.enacted_action ->> 'verb' FROM public.ottoq_decisions d
                    WHERE d.sim_run_id = v_run AND d.entity_id = v_b AND d.sim_clock = v_clock AND d.action_context = 'task_start'
                    ORDER BY d.decision_seq DESC LIMIT 1));
    ELSIF p_mode = 'propose' THEN
      INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status, source)
      VALUES (v_c, v_run, c_depot, v_clock - interval '30 minutes', '0848_probe',
              '[{"svc": "interior_deep_clean", "must_do": true, "status": "pending", "concurrency": "bay",
                 "requires_bay": "detail", "est_min": 16}]'::jsonb, 'open', 'twin_generator');
      PERFORM public.ottoq_service_priority_propose(v_run);
      v_r := jsonb_build_object(
        'c_atom_must_do', (SELECT a ->> 'must_do' FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                            WHERE n.vehicle_id = v_c AND n.visit_key = '0848_probe'),
        'c_must', (SELECT p.proposal -> 'rationale' ->> 'must_do' FROM public.ottoq_external_proposals p
                    WHERE p.sim_run_id = v_run AND p.entity_id = v_c AND p.action_context = 'service_sequencing'
                    ORDER BY p.created_at DESC, p.tick_seq DESC NULLS LAST LIMIT 1));
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OQ848', MESSAGE = '0848 V2 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ848' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

CREATE TEMP TABLE _0848_out (phase text, r jsonb) ON COMMIT DROP;

DO $v2a$
DECLARE v_r jsonb := jsonb_build_object('tick', pg_temp._0848_probe('tick'), 'propose', pg_temp._0848_probe('propose'));
BEGIN
  INSERT INTO _0848_out VALUES ('before', v_r);
  IF NOT COALESCE((v_r #>> '{tick,a_sent}')::boolean, false) OR NOT COALESCE((v_r #>> '{tick,b_sent}')::boolean, false) THEN
    RAISE EXCEPTION '0848 V2a tick: G558 was not reproduced as this file was written against: %', v_r;
  END IF;
  IF (v_r #>> '{propose,c_must}') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION '0848 V2a propose: the proposer did not call a cabin clean must-do as this file was written against: %', v_r;
  END IF;
  RAISE NOTICE '0848 V2a (before): %', v_r;
END $v2a$;

CREATE TEMP TABLE _0848_patch (fn text, ord int, n_expected int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0848_patch VALUES
('public.ottoq_decide_tick(uuid)', 1, 1,
$o$    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx));$o$,
$n$    -- 0848 (G558): an outside admit_service is taken only when this block's own heuristic would admit the car now. A
    -- proposal outlives its reason (ottoq_l2_external_proposal keeps it at least 35 real minutes, 4.7 sim-hours at 8x):
    -- made while a car's cabin clean ran at its charger post, it seated the car in a service bay for 45 minutes after the
    -- clean was done, with no service-bay work and its step need_deploy (run 02fca960, twice in 95 sim-minutes). Any other
    -- outside verb, and an outside admit the heuristic agrees with, is taken as before.
    v_proposal := ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id);
    IF v_proposal IS NULL
       OR (v_proposal->>'verb' = 'admit_service'
           AND (ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx))->>'verb' IS DISTINCT FROM 'admit_service') THEN
      v_proposal := ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx);
    END IF;$n$),
('public.ottoq_service_priority_propose(uuid)', 1, 1,
$o$AND a->>'svc' <> 'readiness_check'$o$,
$n$AND a->>'svc' IN (SELECT cp.svc FROM service_cadence_policy cp WHERE cp.lane = 'service_bay' AND cp.is_active)  -- 0848 (G558): only service-bay work makes a car must-do for a service-bay seat$n$);

DO $fns$
DECLARE f text; p record; v_def text; v_back text; n int;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.ottoq_decide_tick(uuid)', 'public.ottoq_service_priority_propose(uuid)'] LOOP
    v_def := pg_get_functiondef(to_regprocedure(f));
    FOR p IN SELECT * FROM _0848_patch WHERE fn = f ORDER BY ord LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> p.n_expected THEN
        RAISE EXCEPTION '0848 V1: anchor % of % matches % times, not %', p.ord, f, n, p.n_expected;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(f)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0848 V1: % is not stored as patched', f;
    END IF;
    v_back := v_def;
    FOR p IN SELECT * FROM _0848_patch WHERE fn = f ORDER BY ord DESC LOOP
      v_back := replace(v_back, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_back) IS DISTINCT FROM
       (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0848_pre' AND object_name = f
         ORDER BY snapshot_id DESC LIMIT 1) THEN
      RAISE EXCEPTION '0848 V1: % with its patch reversed is not its snapshot', f;
    END IF;
  END LOOP;
END $fns$;

DO $v2b$
DECLARE v_r jsonb := jsonb_build_object('tick', pg_temp._0848_probe('tick'), 'propose', pg_temp._0848_probe('propose'));
BEGIN
  INSERT INTO _0848_out VALUES ('after', v_r);
  IF COALESCE((v_r #>> '{tick,a_sent}')::boolean, true) OR (v_r #>> '{tick,a_verb}') = 'admit_service'
     OR NOT COALESCE((v_r #>> '{tick,b_sent}')::boolean, false)
     OR COALESCE((v_r #>> '{tick,tick,errored}')::int, -1) <> 0 THEN
    RAISE EXCEPTION '0848 V2b tick: a car with no service-bay work was still seated, or a car the heuristic admits was not: %', v_r;
  END IF;
  IF (v_r #>> '{propose,c_must}') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION '0848 V2b propose: a cabin clean still makes a car must-do for a service bay: %', v_r;
  END IF;
  RAISE NOTICE '0848 V2b (after): %', v_r;
END $v2b$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0848_a_service_bay_seat_proposed_from_outside_is_taken_only_while_the_car_still_owes_the_bay', true, false,
        'G558: section (5) of ottoq_decide_tick takes an outside admit_service only when ottoq_l2_propose_service would '
        || 'admit the car at the same tick, and ottoq_service_priority_propose counts only service-bay must-dos. Two cars '
        || 'with no service-bay work were seated for 45 minutes each on run 02fca960. Pre-image 0848_pre.', now());
COMMIT;
