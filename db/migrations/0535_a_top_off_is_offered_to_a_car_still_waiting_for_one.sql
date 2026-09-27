-- migration-version: 20260927175201
-- migration-name:    a_top_off_is_offered_to_a_car_still_waiting_for_one
--
-- 0535  **G259: an approved top-off moved a car out of the wash bay it was being washed in, and the tick failed. The
--       first experiment arm to charge a daytime DCFC to 85% (0533) found it. And an engine error in one arm threw away
--       the whole pair and would have been retried all night.**
--
-- ══ §1 WHAT HAPPENED ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The probe pair of experiment 08262943 after 0533 (cron 766, 12:15 PM CT) ended 16.7 minutes in with
--   `duplicate key value violates unique constraint "idx_stalls_one_vehicle_per_stall"`, and wrote no ledger row.
--   The treatment arm, replayed alone one tick at a time (cron 767, rolled back), failed at tick 75 (3:24 PM sim):
--     1. At about 3:18 PM sim a Tesla's DCFC session ended at the cap: 84.5%, below the top-off threshold of 90.
--        `ottoq_plan_opportunistic_charges` raised an opportunistic-charge approval for it.
--     2. One tick later the car was demated and in the wash bay (`in_wash_bay`, svc_step `washing`). The bay's stall
--        pointer held it; its own `current_stall_id` was null.
--     3. At tick 75 the simulated technician approved the top-off. `twin.ottoq_opportunistic_scan` moved the car to
--        a charger with no look at where it now was:
--          - it released the car's other stall;
--          - `trg_reassignment_guard` refused to vacate a bay mid-wash, silently (`NEW := OLD`);
--          - it claimed the charger.
--     4. The index refused a car in two places, and the tick raised.
--   The scan's own state update already named the states a top-off is for (`staged_awaiting_service`,
--   `staged_for_departure`, `charge_complete_holding`), and moved a car in any other state anyway.
--   At the 90% cap a DCFC session ended at 89.5, a hair under the threshold. So the window between the ask and the
--   verdict almost never held a car that had since moved on. At 85 it holds one on a busy afternoon.
--   The bug is the engine's, not the experiment's: a depot that lowered its day cap, or a car whose session stopped
--   early for any reason, meets it.
--
--   The second defect is the harness's. `ottoq_dial_pair` ran each arm's ticks bare, so one engine error aborted the
--   whole pair, and the ledger recorded nothing. The runner picks the experiment with the fewest pairs and the first
--   seed not yet paired, so it would have re-run the same failing seed every twenty minutes until the window closed.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The scan enacts an approved top-off only for a car still in one of those three states. Otherwise the approval
--       expires with `expired_reason = vehicle_moved_on` and the state the car was found in. The technician said yes;
--       the car had gone. Nothing else in the scan changes.
--   (b) `ottoq_dial_pair` runs each tick in its own subtransaction:
--         - an engine error ends that arm, and only that arm;
--         - the error, its detail, where it was raised, the tick and the sim clock go into the arm's metrics as
--           `arm_error`;
--         - the arm is incomplete, so the pair is recorded as invalid, not counted;
--         - the next seed runs next time.
--       The return value names each arm's error.
--   (c) The verdict ends an experiment whose pairs keep crashing: two pairs since the dial floor with an arm error is
--       `engine_error`, terminal, naming the latest error. A pair that crashes says something about the engine, not the
--       dial, and the window's remaining pairs would repeat it.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   (a) is on every run's tick path. On the canon's runs it can only change something if an approval is decided for a
--   car that has left the three states, and the canon passing says that never ended in this failure. It may still
--   have ended as an unnoticed move, so the canon re-certifies rather than being assumed. The dial arms change too.

BEGIN;

-- ── P0: no pair in flight (0513's one probe): this file replaces the dial pair and a tick-path function ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0535 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_scan text; v_pair text; v_verdict text;
BEGIN
  v_scan    := pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure);
  v_pair    := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  v_verdict := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  IF position($p$           AND current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding');

        v_enact := ottoq_enact_opportunistic_charge(p_sim_run_id, v_rec.vehicle_id,$p$ IN v_scan) = 0 THEN
    RAISE EXCEPTION '0535 P2: the scan does not enact its top-off as measured';
  END IF;
  -- the guard that refuses to vacate a bay mid-wash, silently: the reason the scan must not try
  IF position('NEW.current_vehicle_id := OLD.current_vehicle_id;'
              IN pg_get_functiondef('public.ottoq_trg_reassignment_guard()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0535 P2: the reassignment guard does not keep the pointer as measured';
  END IF;
  IF position(E'      PERFORM public.ottoq_sim_advance_tick(v_run);\n    END LOOP;\n' IN v_pair) = 0
     OR position('v_reads boolean[] := ''{}'';' IN v_pair) = 0 THEN
    RAISE EXCEPTION '0535 P2: the dial pair''s tick loop is not as 0533 left it';
  END IF;
  IF position('ELSIF v_unread > 0 THEN' IN v_verdict) = 0 THEN
    RAISE EXCEPTION '0535 P2: the verdict is not as 0533 left it';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0535_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('twin',   'ottoq_opportunistic_scan',      'twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'),
               ('public', 'ottoq_dial_pair',               'public.ottoq_dial_pair(uuid,bigint,integer)'),
               ('public', 'ottoq_dial_experiment_verdict', 'public.ottoq_dial_experiment_verdict(uuid)')) AS f(sch, obj, sig);

-- ── (a) a top-off is enacted only for a car still waiting for one ──
DO $scan$
DECLARE
  v_def text; n int;
  v_old text := $o$           AND current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding');

        v_enact := ottoq_enact_opportunistic_charge(p_sim_run_id, v_rec.vehicle_id,$o$;
  v_new text := $n$           AND current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding');
        -- 0535 (G259): ONLY A CAR STILL WAITING GETS THE TOP-OFF. The approval was raised when the car was waiting and
        -- decided later; a car that has since moved on (into a bay, onto the road) is not moved again. It was: into a
        -- charger out of the wash bay it was being washed in, which the reassignment guard will not vacate, and the tick
        -- failed on idx_stalls_one_vehicle_per_stall (db/checks/0399 §2). The state update above is the test.
        IF NOT FOUND THEN
          UPDATE ottoq_ops_approvals
             SET status = 'expired',
                 payload = COALESCE(payload, '{}'::jsonb)
                        || jsonb_build_object('expired_reason', 'vehicle_moved_on', 'expired_at', p_clock,
                                              'vehicle_state', (SELECT v.current_state::text FROM vehicles v WHERE v.id = v_rec.vehicle_id))
           WHERE approval_id = v_rec.approval_id;
          CONTINUE;
        END IF;

        v_enact := ottoq_enact_opportunistic_charge(p_sim_run_id, v_rec.vehicle_id,$n$;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0535 (a): the scan''s enact matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $scan$;

-- ── (b) an engine error ends its arm, not the pair ──
DO $pair$
DECLARE
  v_def text; v_new text; n int; i int;
  p text[][] := ARRAY[
    ARRAY[E'  v_reads boolean[] := ''{}'';   -- 0533 (G258): whether each arm read its own value of the dial\n',
          E'  v_reads boolean[] := ''{}'';   -- 0533 (G258): whether each arm read its own value of the dial\n'
          || E'  v_err jsonb; v_err_msg text; v_err_detail text; v_err_ctx text;   -- 0535 (G259): an arm''s engine error\n'],
    ARRAY[E'    PERFORM set_config(''ottoq.run_scope_reads'', '''', true);\n    v_t0 := clock_timestamp();\n',
          E'    PERFORM set_config(''ottoq.run_scope_reads'', '''', true);\n    v_err := NULL;\n    v_t0 := clock_timestamp();\n'],
    ARRAY[E'      PERFORM public.ottoq_sim_advance_tick(v_run);\n    END LOOP;\n',
          E'      -- 0535 (G259): each tick in its own subtransaction. An engine error ends this arm and is recorded with it;\n'
          || E'      -- it no longer aborts the pair, which wrote nothing and was retried on the same seed until the window closed.\n'
          || E'      BEGIN\n'
          || E'        PERFORM public.ottoq_sim_advance_tick(v_run);\n'
          || E'      EXCEPTION WHEN OTHERS THEN\n'
          || E'        GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT, v_err_detail = PG_EXCEPTION_DETAIL, v_err_ctx = PG_EXCEPTION_CONTEXT;\n'
          || E'        v_err := jsonb_build_object(''error'', v_err_msg, ''detail'', v_err_detail, ''where'', left(v_err_ctx, 800),\n'
          || E'                                    ''tick'', v_ticks + 1, ''sim_clock'', v_clock);\n'
          || E'        EXIT;\n'
          || E'      END;\n'
          || E'    END LOOP;\n'],
    ARRAY[E'                                         ''complete'', v_h->''complete'', ''wall_s'', v_h->''wall_s''));\n',
          E'                                         ''complete'', v_h->''complete'', ''wall_s'', v_h->''wall_s'')\n'
          || E'                   || CASE WHEN v_err IS NULL THEN ''{}''::jsonb ELSE jsonb_build_object(''arm_error'', v_err) END);\n'],
    ARRAY[E'    ''dial_read'', jsonb_build_object(''control'', v_reads[1], ''treatment'', v_reads[2]),\n',
          E'    ''dial_read'', jsonb_build_object(''control'', v_reads[1], ''treatment'', v_reads[2]),\n'
          || E'    ''arm_errors'', jsonb_strip_nulls(jsonb_build_object(''control'', v_m[1]->''arm_error'', ''treatment'', v_m[2]->''arm_error'')),\n']];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  v_new := v_def;
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_new) - length(replace(v_new, p[i][1], ''))) / length(p[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0535 (b): dial pair patch % matched % times, not once', i, n; END IF;
    v_new := replace(v_new, p[i][1], p[i][2]);
  END LOOP;
  EXECUTE v_new;
END $pair$;

-- ── (c) an experiment whose pairs keep crashing ends, and says why ──
DO $verdict$
DECLARE
  v_def text; v_new text; n int; i int;
  p text[][] := ARRAY[
    ARRAY[E'  v_unread int := 0; v_witnessed int := 0; v_unmeasured int := 0;   -- 0533 (G258): the arms'' read witness\n',
          E'  v_unread int := 0; v_witnessed int := 0; v_unmeasured int := 0;   -- 0533 (G258): the arms'' read witness\n'
          || E'  v_crashed int := 0; v_crash jsonb;   -- 0535 (G259): pairs an engine error cut short\n'],
    ARRAY[E'    JOIN public.ottoq_dial_pair_ledger l ON l.pair_id = c.pair_id;\n',
          E'    JOIN public.ottoq_dial_pair_ledger l ON l.pair_id = c.pair_id;\n\n'
          || E'  -- 0535 (G259): pairs since the floor in which an arm ended on an engine error (0535 records them; before, a\n'
          || E'  -- crashed pair wrote nothing). They are invalid and never counted; two of them end the experiment.\n'
          || E'  SELECT count(*), (array_agg(COALESCE(l.metrics_b->''arm_error'', l.metrics_a->''arm_error'') ORDER BY l.pair_id DESC))[1]\n'
          || E'    INTO v_crashed, v_crash\n'
          || E'    FROM public.ottoq_dial_pair_ledger l\n'
          || E'   WHERE l.experiment_id = p_experiment_id AND l.ran_at >= v_floor\n'
          || E'     AND (l.metrics_a ? ''arm_error'' OR l.metrics_b ? ''arm_error'');\n'],
    ARRAY[E'  ELSIF v_unread > 0 THEN\n',
          E'  ELSIF v_crashed >= 2 THEN\n'
          || E'    -- 0535 (G259): the engine, not the dial, is what these pairs measured\n'
          || E'    v_outcome := ''engine_error'';\n'
          || E'    v_why := format(''%s pairs since the dial floor ended with an engine error in an arm (the latest: %s, at tick %s); '
          || E'what these pairs measure is the engine, not the dial. Fix the engine and register the experiment again'', '
          || E'v_crashed, v_crash->>''error'', v_crash->>''tick'');\n'
          || E'  ELSIF v_unread > 0 THEN\n'],
    ARRAY[E'    ''dial_reads'', jsonb_build_object(''witnessed'', v_witnessed, ''unread'', v_unread, ''unmeasured'', v_unmeasured),   -- 0533 (G258)\n',
          E'    ''crashed_pairs'', v_crashed,   -- 0535 (G259)\n'
          || E'    ''dial_reads'', jsonb_build_object(''witnessed'', v_witnessed, ''unread'', v_unread, ''unmeasured'', v_unmeasured),   -- 0533 (G258)\n']];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure);
  v_new := v_def;
  FOR i IN 1 .. array_length(p, 1) LOOP
    n := (length(v_new) - length(replace(v_new, p[i][1], ''))) / length(p[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0535 (c): verdict patch % matched % times, not once', i, n; END IF;
    v_new := replace(v_new, p[i][1], p[i][2]);
  END LOOP;
  EXECUTE v_new;
END $verdict$;

DO $verify$
DECLARE v_scan text; v_pair text; v_verdict text;
BEGIN
  -- V1 (read with comments stripped)
  v_scan    := regexp_replace(pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure), '--[^\n]*', '', 'g');
  v_pair    := regexp_replace(pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure), '--[^\n]*', '', 'g');
  v_verdict := regexp_replace(pg_get_functiondef('public.ottoq_dial_experiment_verdict(uuid)'::regprocedure), '--[^\n]*', '', 'g');
  IF position('''expired_reason'', ''vehicle_moved_on''' IN v_scan) = 0
     OR position('IF NOT FOUND THEN' IN v_scan) > position('v_enact := ottoq_enact_opportunistic_charge' IN v_scan)
     OR position('IF NOT FOUND THEN' IN v_scan) = 0 THEN
    RAISE EXCEPTION '0535 V1: the scan does not gate its top-off as intended';
  END IF;
  IF position('EXCEPTION WHEN OTHERS THEN' IN v_pair) = 0
     OR position('EXCEPTION WHEN OTHERS THEN' IN v_pair) < position('PERFORM public.ottoq_sim_advance_tick(v_run);' IN v_pair)
     OR position('jsonb_build_object(''arm_error'', v_err)' IN v_pair) = 0
     OR position('v_err := NULL;' IN v_pair) > position('PERFORM public.ottoq_sim_advance_tick(v_run);' IN v_pair) THEN
    RAISE EXCEPTION '0535 V1: the dial pair does not survive an arm''s error as intended';
  END IF;
  IF position('v_outcome := ''engine_error'';' IN v_verdict) = 0
     OR position('ELSIF v_crashed >= 2 THEN' IN v_verdict) > position('ELSIF v_unread > 0 THEN' IN v_verdict) THEN
    RAISE EXCEPTION '0535 V1: the verdict does not end a crashing experiment as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0535_a_top_off_is_offered_to_a_car_still_waiting_for_one', true, true,
  'G259: twin.ottoq_opportunistic_scan enacts an approved top-off only for a car still staged or holding; otherwise the '
  'approval expires (vehicle_moved_on). It moved a car out of the wash bay it was in, and the tick failed on '
  'idx_stalls_one_vehicle_per_stall. On every run''s tick path, so the canon re-certifies. The dial pair records an '
  'arm''s engine error instead of aborting, and the verdict ends an experiment after two such pairs.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back.
--   (a) The failing case, planted: a car in the wash bay, its bay stall holding it, and an opportunistic-charge approval
--       the crew approved and that is due now. The scan raises nothing. The approval expires as vehicle_moved_on,
--       naming in_wash_bay. The bay still holds the car, and no charger does.
--   (b) Its control: the same approval for a car staged and waiting is approved and not expired (the gate lets a
--       waiting car through).
--   (c) The verdict: an experiment with one crashed pair since the floor is still collecting; with two it is
--       engine_error, terminal, naming the error.
--   The dial pair's subtransaction is this file's check (db/checks/0399 §2): the arm replayed with the fix, and a pair.
DO $v3$
DECLARE
  v_msg text; v_run uuid := '9f025b02-0e0f-436d-92b2-368aef9225f5'; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz := '2026-09-01 20:30:00+00'; v_car uuid; v_car2 uuid; v_bay uuid; v_ap uuid; v_ap2 uuid;
  r record; v_x uuid; v1 jsonb; v2 jsonb; v_chargers int;
BEGIN
  BEGIN
    SELECT id INTO v_bay FROM public.stalls WHERE depot_id = v_depot AND stall_type = 'wash_bay' AND current_vehicle_id IS NULL
     ORDER BY stall_code LIMIT 1;
    SELECT id INTO v_car FROM public.vehicles WHERE home_depot_id = v_depot AND category = 'autonomous' AND current_stall_id IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id) ORDER BY id LIMIT 1;
    SELECT id INTO v_car2 FROM public.vehicles WHERE home_depot_id = v_depot AND category = 'autonomous' AND current_stall_id IS NULL
       AND id <> v_car AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id) ORDER BY id LIMIT 1;
    IF v_bay IS NULL OR v_car IS NULL OR v_car2 IS NULL OR NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run) THEN
      RAISE EXCEPTION '0535 V3 FAILED: no free wash bay, no two free cars, or no run row to scan under';
    END IF;
    -- the car is in the wash bay: the bay holds it (the way the twin's bay path does), its own stall pointer is empty
    UPDATE public.vehicles SET current_state = 'in_wash_bay', current_soc = 84.5, last_state_change = v_clock WHERE id = v_car;
    UPDATE public.stalls SET current_vehicle_id = v_car, status = 'occupied' WHERE id = v_bay;
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_soc = 70, last_state_change = v_clock WHERE id = v_car2;
    INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, status, payload, requested_at, decide_after, expires_at)
    VALUES ('opportunistic_charge', v_car, v_run, v_depot, 'pending',
            jsonb_build_object('operator_verdict', jsonb_build_object('verdict', 'approved', 'by', '0535_v3')),
            v_clock - interval '6 minutes', v_clock - interval '1 minute', v_clock + interval '30 minutes')
    RETURNING approval_id INTO v_ap;

    -- (a) the failing case
    PERFORM twin.ottoq_opportunistic_scan(v_run, v_clock);
    SELECT a.status, a.payload->>'expired_reason' AS why, a.payload->>'vehicle_state' AS st INTO r
      FROM public.ottoq_ops_approvals a WHERE a.approval_id = v_ap;
    SELECT count(*) INTO v_chargers FROM public.stalls WHERE current_vehicle_id = v_car AND stall_type IN ('dcfc', 'l2');
    IF r.status IS DISTINCT FROM 'expired' OR r.why IS DISTINCT FROM 'vehicle_moved_on' OR r.st IS DISTINCT FROM 'in_wash_bay'
       OR (SELECT current_vehicle_id FROM public.stalls WHERE id = v_bay) IS DISTINCT FROM v_car OR v_chargers <> 0 THEN
      RAISE EXCEPTION '0535 V3 FAILED (a): approval %, reason %, state %, bay holds the car %, chargers holding it %',
        r.status, r.why, r.st, (SELECT current_vehicle_id FROM public.stalls WHERE id = v_bay) = v_car, v_chargers;
    END IF;

    -- (b) the control: a waiting car's approval is approved, not expired
    INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, status, payload, requested_at, decide_after, expires_at)
    VALUES ('opportunistic_charge', v_car2, v_run, v_depot, 'pending',
            jsonb_build_object('operator_verdict', jsonb_build_object('verdict', 'approved', 'by', '0535_v3')),
            v_clock - interval '6 minutes', v_clock - interval '1 minute', v_clock + interval '30 minutes')
    RETURNING approval_id INTO v_ap2;
    PERFORM twin.ottoq_opportunistic_scan(v_run, v_clock);
    IF (SELECT status FROM public.ottoq_ops_approvals WHERE approval_id = v_ap2) IS DISTINCT FROM 'approved' THEN
      RAISE EXCEPTION '0535 V3 FAILED (b): the waiting car''s approval reads %, not approved',
        (SELECT status FROM public.ottoq_ops_approvals WHERE approval_id = v_ap2);
    END IF;

    -- (c) the verdict
    INSERT INTO public.ottoq_dial_experiments (created_by, depot_id, param_key, control_value, treatment_value, scenario, ticks,
                                               sim_start, primary_metric, primary_better, hypothesis, sim_min_per_tick)
    VALUES ('0535_v3', v_depot, 'l2_target_soc', 100, 95, 'busy_day', 90, '2026-09-01 13:00:00+00',
            'unmet_demand_car_hours', 'lower', '0535 V3 plant', 6)
    RETURNING experiment_id INTO v_x;
    INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                               world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
    VALUES (v_x, 535, '0535_v3', public.ottoq_dial_pair_floor() + interval '1 second', v_run, v_run, gen_random_uuid(), false, true, true,
            true, '[]'::jsonb, '{"unmet_demand_car_hours": 336.3}'::jsonb,
            '{"arm_error": {"error": "duplicate key value violates unique constraint \"idx_stalls_one_vehicle_per_stall\"", "tick": 75}}'::jsonb,
            '{}'::jsonb, 0);
    v1 := public.ottoq_dial_experiment_verdict(v_x);
    INSERT INTO public.ottoq_dial_pair_ledger (experiment_id, seed, engine_hash, ran_at, run_a, run_b, ab_group_id, complete,
                                               world_identical, both_paid_shield, differs, moved, metrics_a, metrics_b, delta, wall_s)
    VALUES (v_x, 536, '0535_v3', public.ottoq_dial_pair_floor() + interval '2 seconds', v_run, v_run, gen_random_uuid(), false, true, true,
            true, '[]'::jsonb, '{"unmet_demand_car_hours": 336.3}'::jsonb,
            '{"arm_error": {"error": "duplicate key value violates unique constraint \"idx_stalls_one_vehicle_per_stall\"", "tick": 81}}'::jsonb,
            '{}'::jsonb, 0);
    v2 := public.ottoq_dial_experiment_verdict(v_x);
    IF v1->>'outcome' IS DISTINCT FROM 'collecting' OR (v1->>'crashed_pairs')::int IS DISTINCT FROM 1
       OR v2->>'outcome' IS DISTINCT FROM 'engine_error' OR NOT COALESCE((v2->>'terminal')::boolean, false)
       OR position('at tick 81' IN v2->>'why') = 0 THEN
      RAISE EXCEPTION '0535 V3 FAILED (c): one crashed pair: % (crashed %); two: % (terminal %): %',
        v1->>'outcome', v1->>'crashed_pairs', v2->>'outcome', v2->>'terminal', v2->>'why';
    END IF;

    RAISE EXCEPTION '0535 V3 PASSED: the car in the wash bay kept it and its top-off expired as vehicle_moved_on; the waiting car''s was approved; one crashed pair is %, two are %: %',
      v1->>'outcome', v2->>'outcome', v2->>'why';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0535 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0535 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the three `definition`s in ottoq_schema_snapshots WHERE label = '0535_pre' as they are.
COMMIT;
