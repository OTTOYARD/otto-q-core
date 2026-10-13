-- migration-version: 20261013211005
-- migration-name:    production_start_takes_the_world_as_the_operator_door_does
--
-- 0719  **A production start takes the world from research work, as the operator door does.** (G437; the study's
--        DC-4 step 3; CLAUDE.md rule 10.)
--
-- ══ §1 WHY (measured 2026-10-13, read-only, db/checks/0448) ═════════════════════════════════════════════════════════
--
--   pg_cron runs one job at a time here (cron.use_background_workers = off), so a research arm that holds the world
--   blocks every other cron job for as long as it runs, the production tick (job 10, */2) included (G141). Over the
--   7 days to 20:41 UTC today the throughput sweep (job 783) ran 21 arms longer than two minutes, 43.25 hours in all,
--   the longest 2 h 26 m; the recert runner (job 746) 19, 1.45 hours. Every research arm takes the world lock
--   (public.ottoq_try_world_lock: the sweep runner and arm, the dial pair and experiment runner, the recert runner).
--
--   public.ottoq_operator_start_run cancels every running check and then takes that lock before it starts a run, so an
--   operator's demo never waits on research. public.ottoq_production_start does neither. A production session started
--   inside a sweep arm would get no tick until the arm ended: up to two and a half hours of a live depot with no decide
--   path, no agent and no world step. Rule 10: production decides in real time; research belongs to the research wing.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   1. public.ottoq_world_yield_to_start(p_who text): the operator door's steps 1 and 2, as one SECURITY DEFINER
--      function. It cancels every backend holding the world lock and every hand-run pair (the door's own predicate,
--      verbatim; V2 asserts the two stay identical), then takes the world lock, which waits for their rollback and
--      keeps any check from beginning before the caller's transaction commits. It returns what it interrupted.
--      EXECUTE: postgres and service_role only.
--   2. public.ottoq_production_start (md5-guarded on c0ae7ec68b695cd76c22268852568bea) calls it after its two refusals,
--      re-checks that no run started at the depot meanwhile, and reports what it interrupted in its event and its
--      reply. Nothing else in it moves. Its grants are not touched (they are the 0701 family's, held for Chase).
--   The operator door keeps its own copy of the same two steps; folding it onto the helper is a separate change.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   Neither function is reached by a pair, a dial arm, a sweep or a demo run: ottoq_production_start is called by a
--   person, and the helper only by it. A research arm the start cancels re-runs after the session ends, as one the
--   operator door cancels does.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0719_pre';
--   DROP FUNCTION public.ottoq_world_yield_to_start(text);
--   DELETE FROM ottoq_cert_lineage WHERE name = '0719_production_start_takes_the_world_as_the_operator_door_does'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0719 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the definitions this file was written against ──
DO $premises$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef('public.ottoq_production_start(uuid)'::regprocedure)) INTO v_md5;
  IF v_md5 IS DISTINCT FROM 'c0ae7ec68b695cd76c22268852568bea' THEN
    RAISE EXCEPTION '0719 P1: ottoq_production_start is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  IF to_regprocedure('public.ottoq_world_yield_to_start(text)') IS NOT NULL THEN
    RAISE EXCEPTION '0719 P1: ottoq_world_yield_to_start already exists';
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_operator_start_run(text,bigint,text,timestamptz)'::regprocedure),
            'c_world  constant bigint := hashtext(''ottoq_recert_runner'')::bigint') = 0 THEN
    RAISE EXCEPTION '0719 P1: the operator door no longer names the world lock as this file expects';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0719_pre', 'function', 'public', 'ottoq_production_start', pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p WHERE p.oid = 'public.ottoq_production_start(uuid)'::regprocedure;

-- ── 1. the helper: the operator door's steps 1 and 2 ──
CREATE FUNCTION public.ottoq_world_yield_to_start(p_who text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  c_world  constant bigint := hashtext('ottoq_recert_runner')::bigint;   -- the key ottoq_try_world_lock takes
  v_int    jsonb := '[]'::jsonb;
  v_ok     boolean;
  v_t0     timestamptz := clock_timestamp();
  r        record;
BEGIN
  -- 0719 (G437). What ottoq_operator_start_run does before it starts a run, for a start that is not a scenario run.
  -- A hand-run pair holds no lock this can wait on, only the rows it has written; give its rollback longer than the
  -- API role's 8 s. Transaction-local.
  PERFORM set_config('lock_timeout', '15s', true);

  -- 1. Cancel every running check.
  FOR r IN
    SELECT a.pid, a.application_name, a.query_start,
           CASE WHEN a.query ~* 'ottoq_recert_runner'                 THEN 'recertification pair'
                WHEN a.query ~* 'ottoq_dial_(experiment_runner|pair)' THEN 'dial experiment pair'
                WHEN a.query ~* 'ottoq_throughput_sweep'              THEN 'throughput sweep arm'
                WHEN a.query ~* 'ottoq_ab_pair'                       THEN 'A/B pair'
                ELSE 'determinism pair' END AS kind
      FROM pg_stat_activity a
     WHERE a.pid <> pg_backend_pid()
       AND a.datname = current_database()
       AND COALESCE(a.query, '') !~* 'migration-version:'
       AND (   a.pid IN (SELECT l.pid FROM pg_locks l
                          WHERE l.locktype = 'advisory' AND l.granted AND l.objsubid = 1
                            AND ((l.classid::bigint << 32) | l.objid::bigint) = c_world)
            OR (a.state = 'active' AND a.query ~* 'ottoq_(determinism|dial|ab)_pair\s*\('))
     ORDER BY a.query_start, a.pid
  LOOP
    BEGIN
      v_ok := pg_cancel_backend(r.pid);
    EXCEPTION WHEN OTHERS THEN
      v_ok := false;   -- e.g. a superuser's backend: reported, and the start still tries
    END;
    v_int := v_int || jsonb_build_object(
      'pid', r.pid, 'kind', r.kind, 'application', r.application_name,
      'running_s', round(extract(epoch FROM (v_t0 - r.query_start))::numeric, 1),
      'cancelled', COALESCE(v_ok, false), 'by', p_who);
  END LOOP;

  -- 2. Take the world lock: waits for a cancelled holder's rollback, and no check can begin until the caller commits.
  PERFORM pg_advisory_xact_lock(c_world);

  RETURN v_int;
END;
$function$;

REVOKE ALL ON FUNCTION public.ottoq_world_yield_to_start(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_world_yield_to_start(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_world_yield_to_start(text) TO service_role;

COMMENT ON FUNCTION public.ottoq_world_yield_to_start(text) IS
  '0719 (G437): cancel every running check (the world-lock holder and any hand-run pair) and take the world lock, as '
  'ottoq_operator_start_run does; returns what it interrupted. Called by ottoq_production_start.';

-- ── 2. production start calls it, re-checks, and says what it interrupted ──
DO $sub$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_production_start(uuid)'::regprocedure);
  v_a1 constant text := $a$v_ps jsonb; v_inherited jsonb;
BEGIN$a$;
  v_n1 constant text := $n$v_ps jsonb; v_inherited jsonb;
  v_int jsonb;
BEGIN$n$;
  v_a2 constant text := $a$    RETURN jsonb_build_object('ok', false, 'error', 'production_scenario_missing');
  END IF;
$a$;
  v_n2 constant text := $n$    RETURN jsonb_build_object('ok', false, 'error', 'production_scenario_missing');
  END IF;

  -- 0719 (G437). Production takes the world as the operator door does: every running check is cancelled, and the world
  -- lock waits for their rollback. Without it a session started inside a sweep arm got no tick until the arm ended
  -- (pg_cron runs one job at a time here, G141). A check cancelled here re-runs after the session ends.
  v_int := public.ottoq_world_yield_to_start('production_start');
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing, 'interrupted', v_int);
  END IF;
$n$;
  v_a3 constant text := $a$'agent_written_settings_in_force', v_inherited,
$a$;
  v_n3 constant text := $n$'agent_written_settings_in_force', v_inherited, 'interrupted', v_int,
$n$;
  v_a4 constant text := $a$'agent_written_settings_in_force', v_inherited);$a$;
  v_n4 constant text := $n$'agent_written_settings_in_force', v_inherited, 'interrupted', v_int);$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1
     OR (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1
     OR (length(v_def) - length(replace(v_def, v_a3, ''))) / length(v_a3) <> 1
     OR (length(v_def) - length(replace(v_def, v_a4, ''))) / length(v_a4) <> 1 THEN
    RAISE EXCEPTION '0719: an anchor does not match exactly once';
  END IF;
  EXECUTE replace(replace(replace(replace(v_def, v_a1, v_n1), v_a2, v_n2), v_a3, v_n3), v_a4, v_n4);
END $sub$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE
  v_ps   text := pg_get_functiondef('public.ottoq_production_start(uuid)'::regprocedure);
  v_help text := pg_get_functiondef('public.ottoq_world_yield_to_start(text)'::regprocedure);
  v_door text := pg_get_functiondef('public.ottoq_operator_start_run(text,bigint,text,timestamptz)'::regprocedure);
  v_where constant text := $w$     WHERE a.pid <> pg_backend_pid()
       AND a.datname = current_database()
       AND COALESCE(a.query, '') !~* 'migration-version:'
       AND (   a.pid IN (SELECT l.pid FROM pg_locks l
                          WHERE l.locktype = 'advisory' AND l.granted AND l.objsubid = 1
                            AND ((l.classid::bigint << 32) | l.objid::bigint) = c_world)
            OR (a.state = 'active' AND a.query ~* 'ottoq_(determinism|dial|ab)_pair\s*\('))$w$;
  v_src text;
BEGIN
  --: V1 production start calls the helper once, before it inserts the run, and re-checks after it
  v_src := regexp_replace(v_ps, '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_world_yield_to_start\s*\(', 'g')) <> 1
     OR strpos(v_src, 'ottoq_world_yield_to_start(') > strpos(v_src, 'INSERT INTO ottoq_sim_runs')
     OR (SELECT count(*) FROM regexp_matches(v_src, 'depot_already_has_running_run', 'g')) <> 2 THEN
    RAISE EXCEPTION '0719 V1 FAILED: production start does not take the world before it inserts the run';
  END IF;

  --: V2 the helper cancels exactly what the operator door cancels: the same WHERE, byte for byte, in both
  IF strpos(v_help, v_where) = 0 OR strpos(v_door, v_where) = 0 THEN
    RAISE EXCEPTION '0719 V2 FAILED: the helper''s cancel predicate is not the operator door''s';
  END IF;

  --: V3 nothing else in production start moved: taking the four insertions out gives back the snapshot
  IF replace(replace(replace(v_ps,
       $n$
  v_int jsonb;$n$, ''),
       $n$

  -- 0719 (G437). Production takes the world as the operator door does: every running check is cancelled, and the world
  -- lock waits for their rollback. Without it a session started inside a sweep arm got no tick until the arm ended
  -- (pg_cron runs one job at a time here, G141). A check cancelled here re-runs after the session ends.
  v_int := public.ottoq_world_yield_to_start('production_start');
  SELECT sim_run_id INTO v_existing FROM ottoq_sim_runs
   WHERE depot_id = p_depot AND status = 'running' LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'depot_already_has_running_run',
                              'running_run', v_existing, 'interrupted', v_int);
  END IF;$n$, ''),
       $n$, 'interrupted', v_int$n$, '')
     <> (SELECT s.definition FROM public.ottoq_schema_snapshots s
          WHERE s.label = '0719_pre' AND s.object_name = 'ottoq_production_start' ORDER BY s.snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0719 V3 FAILED: production start changed by more than the insertions';
  END IF;

  --: V4 the helper is SECURITY DEFINER and only postgres and the service role may run it
  IF NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = 'public.ottoq_world_yield_to_start(text)'::regprocedure)
     OR has_function_privilege('anon', 'public.ottoq_world_yield_to_start(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_world_yield_to_start(text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_world_yield_to_start(text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0719 V4 FAILED: the helper''s privileges are not service-role only';
  END IF;
  RAISE NOTICE '0719 V1-V4 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0719_production_start_takes_the_world_as_the_operator_door_does', false, false,
  'G437: ottoq_production_start did not cancel running checks or take the world lock, as the operator door does, so a '
  'session started inside a sweep arm (43.25 h of the last 7 days, the longest 2 h 26 m) got no tick until the arm '
  'ended. A new service-role helper carries the door''s two steps (its cancel predicate asserted identical to the '
  'door''s) and production start calls it before it inserts the run. Called by a person only; no pair, arm, sweep or '
  'demo run reaches either function: FALSE/FALSE.',
  now());

COMMIT;
