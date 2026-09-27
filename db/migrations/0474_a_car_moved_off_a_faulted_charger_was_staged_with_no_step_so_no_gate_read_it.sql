-- migration-version: 20260926112238
-- migration-name:    a_car_moved_off_a_faulted_charger_was_staged_with_no_step_so_no_gate_read_it
--
-- 0474  **A car moved off a charger that faulted under it was staged with no step, so no gate read it.**
--       `db/checks/0359` §5b and §8. FINDINGS G209.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run 49c45bd4 (busy_day, twin depot `11111111-…`), read live at sim 11:41 AM CT: Waymo-AV-015 and
--   Tesla-AV-065 went from `charging_l2` to `staged_awaiting_service` on a staging stall at 10:36 and 10:46 with no
--   `svc_step`, and were still there, still step-less, 55 and 65 sim-minutes later. Both sessions ended `faulted`
--   ("Calibrated fault injection per ChargerHelp mix: fault.session_aborted_other") at 91% and 86% SoC. Both visits
--   still owed a must-do charge (visit target 100%), and Tesla-AV-065 a must-do exterior wash.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_stop_charge_session`'s fault-requeue path (the founder's malfunction case: the arm releases and
--   the car goes to a temp stall "and OTTO-Q re-routes it to a healthy charger from there") writes the state and the
--   stall and no step, in both of its branches (temp stall booked; staging full). Every other writer of
--   `staged_awaiting_service` sets `svc_step`. The service flow's gates select by step, and so does its queue
--   telemetry (`twin.staging_overflow` counts `need_service`, `need_deploy` and `need_charge`). So the car is read
--   only by `ottoq_decide_tick` (3), which takes a staged car for charge while its SoC is below its visit target and
--   a charger is free. That is the re-route the doctrine asks for, and the two cars waited for it as any `need_charge`
--   car would. But they were not counted as waiting, the deploy gate never recorded what held them, and the gate is
--   the only path that releases a car once its owed work is done.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Both requeue writes also set `svc_step = need_deploy`, the step every bay exit gets: the deploy gate then decides.
--   A car that still owes a must-do charge is routed `need_charge` by the gate's own remedy (0464), with `missing`
--   naming the work, and (3) takes it for charge exactly as before; the difference is that it is counted and its
--   hold is explained. A car at or above its ready floor that owes nothing goes out.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Tick path: a faulted car's step, and so the gate's holds, events and releases, move. Charger faults are drawn by
--   the seeded fault injector, so the canon's commands, decisions, events and end state can move.
--
--   PREDICTED on the next busy_day run: no car in `staged_awaiting_service` with no step after a `faulted` session;
--   each fault-requeued car that owes a charge reads `need_charge` with `deploy_gate.missing` containing `charge`.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0474 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure))
     <> '2ec16828e331c348ff9ce0f2e13eee74' THEN
    RAISE EXCEPTION '0474 P2: twin.ottoq_sim_stop_charge_session is not the body this file patches';
  END IF;
  -- the deploy gate still routes an unready car by its open work (0464), so need_deploy is a safe step to hand it
  IF position($x$WHEN v_open_svc_bay                     THEN 'need_service'$x$
              IN pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0474 P2: the deploy gate no longer routes by open work';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0474_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure;

DO $patch_requeue$
DECLARE
  v_def  text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);
  v_pat1 text := $p$UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,\s+current_stall_id = v_temp_stall, last_state_change = v_clock\s+WHERE id = v_session\.vehicle_id;$p$;
  v_new1 text := $r$UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               current_stall_id = v_temp_stall, last_state_change = v_clock,
               -- 0474 (G209): a step, so the deploy gate sees the car and routes it by its open work
               config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_deploy'::text))
         WHERE id = v_session.vehicle_id;$r$;
  v_pat2 text := $p$UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,\s+current_stall_id = NULL, last_state_change = v_clock\s+WHERE id = v_session\.vehicle_id;$p$;
  v_new2 text := $r$UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               current_stall_id = NULL, last_state_change = v_clock,
               -- 0474 (G209): as above
               config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb('need_deploy'::text))
         WHERE id = v_session.vehicle_id;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat1, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0474: the temp-stall requeue matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat2, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0474: the staging-full requeue matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat1, v_new1);
  v_def := regexp_replace(v_def, v_pat2, v_new2);
  EXECUTE v_def;
END $patch_requeue$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);
BEGIN
  -- V1: both requeue writes set the step, and no write of staged_awaiting_service in this function is step-less.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$current_state = 'staged_awaiting_service'::vehicle_state,[^;]*'\{svc_step\}', to_jsonb\('need_deploy'::text\)\)[^;]*;$x$, 'g')) <> 2
     OR (SELECT count(*) FROM regexp_matches(v_s, $x$current_state = 'staged_awaiting_service'::vehicle_state$x$, 'g')) <> 2 THEN
    RAISE EXCEPTION '0474 V1: the charge stop is not the body this file writes';
  END IF;
  -- V2: one overload, the ACL unchanged.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_stop_charge_session') <> 1 THEN
    RAISE EXCEPTION '0474 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0474 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0474_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0474_a_car_moved_off_a_faulted_charger_was_staged_with_no_step_so_no_gate_read_it', true,
  'Tick path: twin.ottoq_sim_stop_charge_session gives a fault-requeued car svc_step need_deploy, so the deploy gate '
  'routes it. Faulted cars'' next steps move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
