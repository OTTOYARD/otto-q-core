-- migration-version: 20260926045604
-- migration-name:    the_command_door_dropped_the_step_a_gate_intake_carried_so_the_car_was_never_moved_again
--
-- 0465  **The command door dropped the step a gate-intake command carried, so the car was staged with no step and
--       nothing ever moved it again.** `db/checks/0357` §4. FINDINGS G197.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`), live, sim 8:00-11:35 AM CT on 2026-09-26 04:14-04:45 UTC:
--     - 41 gate intakes; by 11:35 AM sim NONE had got back out (0 deployed or staged for departure).
--     - 16 cars in `staged_awaiting_service` with `svc_step` NULL, 15 of them for over an hour, most since
--       8:31-8:46 AM, at 53-58% SoC against the 80% ready floor, most with every must-do atom done.
--     - `proceed_to_stall` commands carrying `svc_step: need_deploy` and `new_state: staged_awaiting_service`: 94,
--       21 executed. Not one of the 21 left a step on its car.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   0039 moved vehicle state out of `ottoq_decide_tick` and into "the twin on command confirmation". The decide
--   path's (3b) gate intake (no-charge arrivals) stages a car with `proceed_to_stall` and writes what the car should
--   do next INTO the command: `svc_step` = need_service when mechanical must-do work is pending, else need_deploy.
--   `twin.ottoq_sim_confirm_commands` implements `new_state` (the 0039 completion) and never `svc_step`: its only
--   step write is 0458's bay contract. So the car arrives in staging with no step, and nothing reads such a car:
--   every service-flow cursor keys on `svc_step`, the deploy gate on 'need_deploy', and the stranded sweeper
--   (`twin.recharge_stranded`, a re-queue per G87) requires an OPEN charge atom, which a no-charge arrival's visit
--   was derived without. The car sits in its staging stall below the ready floor until the run ends.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Where the door executes a state-changing command, a non-empty `svc_step` in the payload is written to the car's
--   config in the same UPDATE, exactly as `new_state` is. Nothing else changes: a command without a step leaves the
--   step as it was, a bay seat still writes 0458's contract (which sets its own step), and no step is invented.
--
--   On this run, only the gate intake's commands carry a step (need_deploy), so the effect is that a no-charge
--   arrival enters the deploy gate, which holds it at `soc_below_ready` and re-queues it for charge, or deploys it
--   when ready. Paired with 0464, a car held for in-place work waits in place instead of taking a service bay.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The door runs on every world tick. Staged cars now carry steps, so the deploy gate, charge queue, deploys,
--   bookings and end state move. Applied in the same recert window as 0463 and 0464.
--
--   PREDICTED on the next busy_day run: no car in `staged_awaiting_service` with no step for more than a tick or two;
--   gate intakes reach the deploy gate and either deploy or queue for charge.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0465 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (after 0458) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure))
     <> '254d10ff58785b80588a4b9a1102dd72' THEN
    RAISE EXCEPTION '0465 P2: twin.ottoq_sim_confirm_commands is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0465_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure;

DO $patch_door$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure);
  v_pat text := $p$config            = CASE WHEN v_bay_end IS NULL THEN config\n$p$;
  v_new text := $r$config            = CASE WHEN v_bay_end IS NULL THEN
                                          -- 0465 (G197): a command's svc_step is applied like its new_state.
                                          -- The gate intake stages a car with `svc_step` in the payload and
                                          -- this door dropped it, so the car had no step and nothing read it.
                                          CASE WHEN NULLIF(v_rec.payload->>'svc_step', '') IS NULL THEN config
                                               ELSE jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}',
                                                              to_jsonb(v_rec.payload->>'svc_step')) END
$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0465: the config write matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_door$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_c text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure);
BEGIN
  -- V1: the step is applied, and 0458's bay contract is still there.
  IF position('0465 (G197)' IN v_c) = 0
     OR position($x$to_jsonb(v_rec.payload->>'svc_step')$x$ IN v_c) = 0
     OR position('0458 (G191): A SEAT IN A BAY CARRIES THE BAY CONTRACT' IN v_c) = 0 THEN
    RAISE EXCEPTION '0465 V1: the door is not the body this file writes';
  END IF;
  -- V2: one overload, same ACL.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_confirm_commands') <> 1 THEN
    RAISE EXCEPTION '0465 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0465 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0465_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0465_the_command_door_dropped_the_step_a_gate_intake_carried_so_the_car_was_never_moved_again', true,
  'Tick path: twin.ottoq_sim_confirm_commands applies a command''s svc_step like its new_state. Gate-intake cars '
  'reach the deploy gate instead of sitting stepless in staging, so holds, the charge queue, deploys and end state move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
