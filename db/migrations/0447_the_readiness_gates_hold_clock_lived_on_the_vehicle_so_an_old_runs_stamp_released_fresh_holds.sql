-- migration-version: PENDING
-- migration-name:    the_readiness_gates_hold_clock_lived_on_the_vehicle_so_an_old_runs_stamp_released_fresh_holds
--
-- 0447  **The readiness gate's hold clock lived on the vehicle, not the run, so a stamp an earlier run left behind
--       made a fresh hold look three weeks old and released the vehicle past the gate at once.**
--       `twin.ottoq_sim_advance_service_flow` holds a vehicle that is not ready (SoC under its ready SoC, or must-do
--       work open) and keeps the hold's start in `vehicles.config -> deploy_gate -> held_since`. At
--       `deploy_gate_hard_cap_min` (240 sim-min) it releases the vehicle anyway ("escape hatch 3 ... this is a DEFECT
--       to investigate, not a normal path"). The certification harness strips `deploy_gate` between arms
--       (`ottoq_benchmark_reset`, 0053); a demo run's boot does not, and nothing ties a stamp to the run that wrote
--       it. FINDINGS G182.
--
-- ══ §1 MEASURED 2026-09-23, RUN 324eb0f1 (busy_day) ═══════════════════════════════════════════════════════════
--
--   - 25 of the twin's 116 vehicles carried `config.deploy_gate`; 7 were stamped before the run began, the oldest at
--     sim 2026-09-01 14:00 (a certification date), 20.8 days before this run's clock.
--   - Escape hatch 3 fired 10 times by sim 13:00 CT. One logged `held_min` 29,949.6 against the 240 cap: a hold that
--     started on this run's clock would have been minutes old.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The hold stamp carries the run that wrote it: `deploy_gate.run` beside `held_since`.
--   (2) A stamp is read only if its `run` is this run; any other stamp, including one written before this migration,
--       counts as absent, so the hold starts now. A stale stamp therefore costs at most the first hold tick.
--   Unchanged: the hard cap, the patience flag, the release path (which already records the `missing` atoms it
--   overrode), and the queue order (`last_state_change` stays untouched on a hold, as before).
--
-- ══ §3 forces_recert TRUE ════════════════════════════════════════════════════════════════════════════════════
--
--   The service flow is on the certified path and the held vehicle's `config` gains a key. Certification arms are
--   reset between arms, so no verdict should move, but the recert floor is moving in this window anyway (0445,
--   0446) and this rides it rather than asserting that no atom reads `vehicles.config`.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0447 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%'
          OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0447 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0447 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the service flow as read on 2026-09-23, both anchors unique ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_service_flow'::regproc;
  IF md5(v_src) <> 'd211e8250d75157016118b8be0a4b393' THEN
    RAISE EXCEPTION '0447 P1: twin.ottoq_sim_advance_service_flow md5 is %', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'          v_since    := COALESCE((v_rec.config #>> ''{deploy_gate,held_since}'')::timestamptz, p_sim_clock_now);\n',
      E'                          || jsonb_build_object(''deploy_gate'', jsonb_build_object(\n'
      || E'                               ''held_since'', v_since, ''held_min'', round(v_held_min,1),\n']
  LOOP
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0447 P1: anchor matched % times: %', v_n, left(v_a, 70); END IF;
  END LOOP;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'held_since', 'g')) <> 2 THEN
    RAISE EXCEPTION '0447 P1: held_since is read or written somewhere this file does not cover';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0447_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_service_flow'::regproc;

-- ── (1)+(2) THE STAMP IS THE RUN'S ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_service_flow'::regproc);
  v_new := replace(v_def,
    E'          v_since    := COALESCE((v_rec.config #>> ''{deploy_gate,held_since}'')::timestamptz, p_sim_clock_now);\n',
    E'          /* 0447 (G182): a hold stamp is this run''s or it is absent. An earlier run''s stamp made a fresh hold\n'
    || E'             read three weeks old and released the vehicle past the gate on its first tick. */\n'
    || E'          v_since    := CASE WHEN (v_rec.config #>> ''{deploy_gate,run}'') = p_sim_run_id::text\n'
    || E'                             THEN COALESCE((v_rec.config #>> ''{deploy_gate,held_since}'')::timestamptz, p_sim_clock_now)\n'
    || E'                             ELSE p_sim_clock_now END;\n');
  v_new := replace(v_new,
    E'                          || jsonb_build_object(''deploy_gate'', jsonb_build_object(\n'
    || E'                               ''held_since'', v_since, ''held_min'', round(v_held_min,1),\n',
    E'                          || jsonb_build_object(''deploy_gate'', jsonb_build_object(\n'
    || E'                               ''held_since'', v_since, ''run'', p_sim_run_id, ''held_min'', round(v_held_min,1),   /* 0447 */\n');
  IF v_new = v_def OR position('(v_rec.config #>> ''{deploy_gate,run}'') = p_sim_run_id::text' IN v_new) = 0
     OR position('''held_since'', v_since, ''run'', p_sim_run_id,' IN v_new) = 0 THEN
    RAISE EXCEPTION '0447: the service-flow splices did not both apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: what shipped is what the header says (comment-stripped) ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_service_flow'::regproc;
  IF position('(v_rec.config #>> ''{deploy_gate,run}'') = p_sim_run_id::text' IN v_src) = 0
     OR position('''run'', p_sim_run_id' IN v_src) = 0
     OR position('''run'', p_sim_run_id' IN v_src) < position('(v_rec.config #>> ''{deploy_gate,run}'')' IN v_src) THEN
    RAISE EXCEPTION '0447 V1: the gate does not read and write the run-scoped stamp as the header says';
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0447_the_readiness_gates_hold_clock_lived_on_the_vehicle_so_an_old_runs_stamp_released_fresh_holds',
   true,
   'G182: twin.ottoq_sim_advance_service_flow stamps deploy_gate.run beside held_since and reads a stamp only if it '
   'is this run''s, so a hold starts on this run''s clock and an earlier run''s stamp cannot trip the 240-minute '
   'escape hatch. TRUE: the certified service flow changes and a held vehicle''s config gains a key.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE. Live proof: on the next demo run no `twin.deploy_gate_override` logs a held_min above the run's
-- own elapsed sim time. Rollback: restore the service flow from ottoq_schema_snapshots label '0447_pre'.
