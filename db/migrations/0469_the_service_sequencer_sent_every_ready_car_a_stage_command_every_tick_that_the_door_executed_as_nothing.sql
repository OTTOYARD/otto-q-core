-- migration-version: 20260926060017
-- migration-name:    the_service_sequencer_sent_every_ready_car_a_stage_command_every_tick_that_the_door_executed_as_nothing
--
-- 0469  **The service sequencer sent every ready car a `stage` command every tick, and the command door executed each
--       one as nothing.** `db/checks/0358` §4. FINDINGS G200.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`, 574 ticks, sim 8:00 AM-12:34 PM CT), read after its stop:
--   7,686 `stage` commands with payload `{ready: true}` executed for 74 cars, up to 262 for one car. No stall, no
--   `new_state`. They were the largest single family in the run's command ledger.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_decide_tick` (5) SERVICE SEQUENCING reads up to 40 `staged_awaiting_service` cars every tick. When the
--   service proposer finds no service-bay work its verdict is `promote_ready`, and the ELSE branch emits
--   `stage {ready: true}` under a comment from 0039: "vehicle state update handled by twin on 'stage' command
--   confirmation". The twin never implemented that half for `stage`: `twin.ottoq_sim_confirm_commands` maps it to no
--   transition ("stage / hold / dispatch / proceed_to_stall carry no transition") and, with no stall in the payload,
--   touches nothing but the command row. The release it was meant to cause happens elsewhere, in the service flow's
--   readiness gate, which reads the car's step and not this command. So the same car was told the same nothing
--   every tick until it left.
--
--   Nothing reads these rows: `ottoq.ottoq_react_to_refusals` is the one function that reads `stage` commands, and
--   only refused ones; a stall-less command cannot be refused for occupancy. `otto-twin-control` counts commands.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The emit is removed. The decision row is unchanged: it still records the sequencer's verdict for this car on
--   this tick, which is what the Decisions stream shows.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The command stream is a determinism atom, and the door does less work per tick.
--
--   PREDICTED on the next busy_day run: no `stage {ready: true}` commands; every other command family unchanged in
--   kind.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0469 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (after 0467) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> 'cf133fb12a702cd65f1839590be26f76' THEN
    RAISE EXCEPTION '0469 P2: public.ottoq_decide_tick is not the body this file patches';
  END IF;
  -- the door still maps `stage` to no transition; if it ever learns one, this emit is not vestigial any more
  IF position($x$ELSE NULL          -- stage / hold / dispatch / proceed_to_stall carry no transition$x$
              IN pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0469 P2: the command door no longer says stage carries no transition';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0469_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

DO $patch_sequencer$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  v_pat text := $p$-- 0039: vehicle state update handled by twin on 'stage' command confirmation\s+PERFORM ottoq_emit_vehicle_command\(p_sim_run_id, v_depot, v_req\.vehicle_id, 'stage', jsonb_build_object\('ready', true\), v_clock\);$p$;
  v_new text := $r$-- 0469 (G200): no command. This emitted stage {ready: true} every tick for every ready car (7,686 on
        -- 317d4331) and the door maps stage to no transition; the release happens in the service flow's
        -- readiness gate, which reads the car's step. The decision row below still records the verdict.
        NULL;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0469: the sequencer emit matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_sequencer$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_d text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
BEGIN
  -- V1: the emit is gone, and 0467's intake is still there.
  IF v_d ~ $x$'stage', jsonb_build_object\('ready', true\)$x$
     OR position('0469 (G200): no command.' IN v_d) = 0
     OR position($x$'reason', 'gate_intake',   -- 0467 (G199)$x$ IN v_d) = 0 THEN
    RAISE EXCEPTION '0469 V1: the decide tick is not the body this file writes';
  END IF;
  -- V2: one overload, same grants.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'public' AND p.proname = 'ottoq_decide_tick') <> 1 THEN
    RAISE EXCEPTION '0469 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_decide_tick(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0469 V2: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0469_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0469_the_service_sequencer_sent_every_ready_car_a_stage_command_every_tick_that_the_door_executed_as_nothing', true,
  'Tick path: ottoq_decide_tick (5) no longer emits stage {ready: true} for a promote_ready verdict; the door mapped '
  'it to no transition. The command stream (a determinism atom) moves.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
