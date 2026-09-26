-- migration-version: 20260926160930
-- migration-name:    the_wave_admission_edge_function_stops_moving_cars_under_the_live_tick
--
-- 0488  **The wave-admission edge function stops moving cars under the live tick (G223).** Every operator run
--       lost three to six world ticks to a deadlock, and most of its gate intake was not OTTO-Q's.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-26) ════════════════════════════════════════════════════════════════════
--
--   `ottoq_cron_tick` (cron 10, every 2 minutes) runs whenever any non-certification run is live. After the
--   production world step (which only advances a `production_live` run) it fires `ottoq-wave-admit` through
--   pg_net with `commit: true`. That edge function flips every car at the gate, up to its ingress cap, from
--   `arrived_at_gate` to `staged_awaiting_service` with one PostgREST
--   `UPDATE vehicles SET current_state = ... WHERE id = ANY(...) AND current_state = 'arrived_at_gate'`.
--   No stall, no booking, no step, no command, and on the wall clock, outside the tick.
--
--   On a demo or validation run the tick is the metronome's (cron 12), so the two write `vehicles` at once:
--     (a) THE DEADLOCK. The world tick locks the run row, then updates the depot's vehicles (the depot
--         heartbeat, `ottoq_sim_emit_depot_heartbeats`). The edge function's update locks its vehicles, then its
--         state-change trigger's shield probe inserts a rule evaluation whose foreign key takes KEY SHARE on the
--         run row. Postgres log, run 461c79fa, 13:56:11-12 UTC: process 1455259 (postgrest, the vehicles update
--         above) waits on the run row held by 1456191, and 1456191 (pg_cron, `ottoq_sim_emit_depot_heartbeats`)
--         waits on vehicle tuple (287,4) held by 1455259. The metronome's world half fails with 40P01 and the
--         tick is lost: 3 on 461c79fa, 3 on 3dbe16db, 6 on 49c45bd4, 5 on 317d4331, 2 on 689095e2, every one
--         within seconds of an even minute.
--     (b) THE BYPASS, which is the larger defect. Gate-to-staged moves, split by whether any tick event shares
--         the transaction: 33 of 51 on 461c79fa, 79 of 124 on 3dbe16db and 59 of 86 on 49c45bd4 were the edge
--         function's. On 461c79fa the kernel's 18 each came with a stall, a booking and a command. The edge
--         function's 33 came with no stall (0 of 33), a command near 3 and a booking near 8: cars declared
--         staged while still standing at the gate. Every other move out of the gate was the kernel's.
--
--   Certification arms never saw any of this: `ottoq_cron_tick` returns early for `cert_harness`, so the canon's
--   gate is the kernel's alone. Operator runs and the canon ran two different gates.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The wave-admission call now fires only while a `production_live` run is running, the one path whose world the
--   cron tick itself advances (and where the call lands after that world step commits). A demo or validation run
--   is ticked by the metronome, whose decide path owns the gate. Nothing else in the cron tick changes.
--
--   What operator runs will now show, and why it is right. The kernel's gate intake stages NO-CHARGE arrivals
--   (with a validated stall, a booking and a command). A charge-needing arrival waits at the gate until the charge
--   path gives it a charger, exactly as in every certified arm. On 461c79fa the cars the edge function moved had
--   waited a mean 9.1 sim-minutes (max 15.4). Staging a charge-waiting arrival in a real stall is a kernel change
--   with its own recert, and is recorded on G223 as the follow-up.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   The cron tick never runs for a certification arm (it returns before the change), so no certified behaviour moves.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0488 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure)) <> 'd9b3ef38b99f129dacf5aaf04380072f' THEN
    RAISE EXCEPTION '0488 P2: public.ottoq_cron_tick is not the body this file patches';
  END IF;
  -- the cron tick still skips certification arms, which is what makes this change canon-neutral
  IF position($x$COALESCE(run_by,'') <> 'cert_harness') THEN$x$
              IN pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0488 P2: the cron tick no longer returns early for certification arms';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 10 AND active AND command ILIKE '%ottoq_cron_tick()%') THEN
    RAISE EXCEPTION '0488 P2: cron 10 is not the active caller of ottoq_cron_tick';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0488_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_cron_tick()'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure);
  v_old text := $o$  PERFORM net.http_post(
    url := base || '/ottoq-wave-admit',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
    body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111','commit',true),
    timeout_milliseconds := 12000);
$o$;
  v_new text := $n$  -- 0488 (G223): ONLY WHILE A production_live RUN IS RUNNING. On a demo or validation run the metronome
  -- ticks the world and its decide path owns the gate. This call flipped cars from the gate to staged with no stall,
  -- booking, step or command, on the wall clock, and its vehicles update deadlocked the metronome's world tick.
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running' AND run_by = 'production_live') THEN
  PERFORM net.http_post(
    url := base || '/ottoq-wave-admit',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
    body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111','commit',true),
    timeout_milliseconds := 12000);
  END IF;
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0488: the wave-admission call matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure);
  v_f   regprocedure := 'public.ottoq_cron_tick()'::regprocedure;
BEGIN
  -- V1: the call is gated on a production_live run and appears once.
  IF position($x$IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running' AND run_by = 'production_live') THEN
  PERFORM net.http_post(
    url := base || '/ottoq-wave-admit',$x$ IN v_def) = 0
     OR (length(v_def) - length(replace(v_def, '/ottoq-wave-admit', ''))) / length('/ottoq-wave-admit') <> 1 THEN
    RAISE EXCEPTION '0488 V1: the wave-admission call is not gated as this file leaves it';
  END IF;
  -- V2: everything else the cron tick fires is still there.
  IF position('/ottoq-orchestrate-tick' IN v_def) = 0 OR position('/ottoq-orchestrator-agent' IN v_def) = 0
     OR position('PERFORM ottoq_world_advance()' IN v_def) = 0 THEN
    RAISE EXCEPTION '0488 V2: the cron tick lost a call it should keep';
  END IF;
  -- V3: privileges and security definer kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR has_function_privilege('anon', v_f, 'EXECUTE') OR has_function_privilege('authenticated', v_f, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_f, 'EXECUTE') THEN
    RAISE EXCEPTION '0488 V3: ottoq_cron_tick''s privileges changed';
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_cron_tick from ottoq_schema_snapshots label '0488_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0488_the_wave_admission_edge_function_stops_moving_cars_under_the_live_tick', false,
  'ottoq_cron_tick fires ottoq-wave-admit only while a production_live run is running. The cron tick returns early '
  'for certification arms, so no certified behaviour moves.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
