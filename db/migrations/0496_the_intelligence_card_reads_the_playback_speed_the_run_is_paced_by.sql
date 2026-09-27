-- migration-version: 20260926200223
-- migration-name:    the_intelligence_card_reads_the_playback_speed_the_run_is_paced_by
--
-- 0496  **The Intelligence tab's run card said "1x" on a run playing at 8x.** `db/checks/0368` §12.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_intelligence_stack` reports the run's speed from `ottoq_sim_runs.demo_speed_x`. The speed a run is
--   played at lives in `payload->>'speed_x'`: `ottoq_set_playback` writes it there (the cockpit's speed slider), and
--   `ottoq_demo_metronome` paces the run by `COALESCE((payload->>'speed_x')::numeric, demo_speed_x, 1.0)`.
--   `demo_speed_x` is not updated by the slider, and it read 1.0 on both `461c79fa` and `394e1e83`, each played at 8x.
--   So on validation run `394e1e83` the Intelligence card read "busy day · tick 191 · running · 1x" while the header,
--   the Control tab ("8x on the run", from the snapshot) and the sim clock (about 8 sim-minutes a real minute) all
--   said 8x.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The stack reads the speed the way the metronome does. Read-only; no caller in the database (the cockpit calls it),
--   so forces_recert FALSE.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0496 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure))
     <> '151e1be6bd09cd41fdbcec7d2eb0e35e' THEN
    RAISE EXCEPTION '0496 P2: public.ottoq_intelligence_stack is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0496_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure;

DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure);
  v_old1 text := $o$         depot_id, demo_speed_x, started_at, run_by
$o$;
  v_new1 text := $n$         depot_id,
         -- 0496: the speed the run is played at, read as the metronome paces it (the slider writes the payload).
         COALESCE((payload->>'speed_x')::numeric, demo_speed_x) AS speed_x, started_at, run_by
$n$;
  v_old2 text := $o$'speed_x', v_run.demo_speed_x,$o$;
  v_new2 text := $n$'speed_x', v_run.speed_x,$n$;
  n1 int; n2 int;
BEGIN
  n1 := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  n2 := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n1 <> 1 OR n2 <> 1 THEN
    RAISE EXCEPTION '0496: the run select matched % times and the speed key % times, not once each', n1, n2;
  END IF;
  EXECUTE replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_intelligence_stack(uuid,boolean)'::regprocedure);
  v_run uuid;
  v_want numeric; v_got numeric;
BEGIN
  -- V1: demo_speed_x is read only as the fallback.
  IF (length(v_def) - length(replace(v_def, 'demo_speed_x', ''))) / length('demo_speed_x') <> 1
     OR position('COALESCE((payload->>''speed_x'')::numeric, demo_speed_x) AS speed_x' IN v_def) = 0 THEN
    RAISE EXCEPTION '0496 V1: the stack does not read the playback speed first';
  END IF;
  -- V2: still STABLE and security definer, privileges kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT provolatile FROM pg_proc WHERE oid = v_f) <> 's' OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> '=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0496 V2: ottoq_intelligence_stack changed volatility or privileges';
  END IF;
  -- V3: on the newest operator run, the stack reports the speed the metronome paces it by.
  SELECT sim_run_id, COALESCE((payload->>'speed_x')::numeric, demo_speed_x) INTO v_run, v_want
    FROM public.ottoq_sim_runs WHERE run_by = 'operator_demo' ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NOT NULL THEN
    v_got := (public.ottoq_intelligence_stack(v_run, false)->'run'->>'speed_x')::numeric;
    IF v_got IS DISTINCT FROM v_want THEN
      RAISE EXCEPTION '0496 V3: the stack reports % for run %, the metronome paces it at %', v_got, v_run, v_want;
    END IF;
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_intelligence_stack from ottoq_schema_snapshots label '0496_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0496_the_intelligence_card_reads_the_playback_speed_the_run_is_paced_by', false,
  'ottoq_intelligence_stack reports the run''s speed from payload speed_x, as the metronome paces it; demo_speed_x '
  'is only the fallback. Read-only, called by the cockpit only.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
