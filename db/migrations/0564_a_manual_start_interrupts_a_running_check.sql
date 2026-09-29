-- migration-version: PENDING
-- migration-name:    a_manual_start_interrupts_a_running_check
--
-- 0564  **A manual start from the depot simulation always interrupts a running check.** Chase, 2026-09-28, 9:33 PM
--       CT: "A manual start from the depot simulation should always interrupt a running check."
--
-- ══ §1 WHY (measured 2026-09-28 from function_edge_logs and postgres_logs) ══════════════════════════════════════════
--
--   Every cockpit Start in the 24 hours read failed: 8 of 8 POST /otto-twin-control/scenarios/start returned 500 after
--   8.14-8.27 s, at 7:19-7:20 PM CT (3) and 8:51-9:00 PM CT (5). Postgres logged "canceling statement due to lock
--   timeout" 20-35 ms before each 500. Both windows were recertification sweeps (after 0558, then after 0561): a
--   determinism pair holds the twin depot's world rows in ONE transaction for up to ~10 minutes (the 48-tick cell), the
--   start must rewrite the same rows, and the API role's lock_timeout (authenticator: 8 s) cancelled it. The console
--   then showed no Stop button because no run ever existed. Six forced sweeps on 2026-09-28 made that ~2.5-3 hours.
--
-- ══ §2 WHAT THIS BUILDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_operator_start_run(p_scenario_code, p_seed, p_run_by, p_start_clock) -> jsonb: the cockpit's start
--   door. otto-twin-control POST /scenarios/start calls it instead of ottoq_sim_run_scenario. In one transaction it:
--     1. CANCELS every running check -- each backend holding the WORLD LOCK (advisory key hashtext('ottoq_recert_runner'),
--        which the recertification runner takes, and the dial experiment runner and ottoq_dial_pair take through
--        ottoq_try_world_lock), and each active query that CALLS ottoq_determinism_pair, ottoq_dial_pair or
--        ottoq_ab_pair (a pair run by hand holds no lock). A query that only NAMES them is not a call and is left alone
--        (a migration's P0 matches '%ottoq_determinism_pair%', a monitor reads pg_stat_activity), and anything carrying
--        a migration-version header is never cancelled.
--     2. TAKES the world lock itself. That waits for the cancelled check to roll back, and it closes the race a cancel
--        alone leaves open: the recertification runner fires every minute and would start the next pair between the
--        cancel and this run's commit. Once this transaction commits the run is live, and both runners yield to a live
--        run (P1 asserts both read status IN ('running','paused') before they start anything).
--     3. STARTS the run through ottoq_sim_run_scenario, unchanged, with lock_timeout raised to 15 s for this
--        transaction so a hand-run pair's rollback can finish; the API role's 20 s statement_timeout still bounds it.
--     4. RECORDS what it interrupted on the new run's notes, and returns {ok, sim_run_id, interrupted: [...]}.
--
-- ══ §3 WHAT THIS DOES NOT CHANGE ════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_sim_run_scenario: ottoq_dial_pair calls it for its arms, so the interrupt cannot live inside it -- a check
--   would cancel checks. The runners: an interrupted pair rolls back whole, its canon cell stays below the recert floor,
--   and the runner re-runs it once the operator's run has ended. A certification is postponed, never lost or faked.
--   Nothing else calls this function, and it is executable by service_role only (the control edge); anon and
--   authenticated cannot reach it, because it can cancel backends.
--
-- ══ §4 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Any time: it creates one function and one lineage row, touches no existing object, and no engine path calls it, so
--   forces_recert and forces_dial_restart are FALSE (an unclassified migration would force a sweep -- the very thing
--   this file routes around). There is no P0: nothing here conflicts with a running pair or a live run. Apply it
--   BEFORE deploying the otto-twin-control that calls it.

BEGIN;

-- ── P1: the facts the door is built on, read from the catalog rather than assumed ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_sim_run_scenario(text,bigint,text,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0564 P1: ottoq_sim_run_scenario(text, bigint, text, timestamptz) is not the start this wraps';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_try_world_lock'
                    AND prosrc ~ $re$pg_try_advisory_xact_lock\(hashtext\('ottoq_recert_runner'\)::bigint\)$re$) THEN
    RAISE EXCEPTION '0564 P1: ottoq_try_world_lock no longer takes hashtext(''ottoq_recert_runner'') -- the world lock moved';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'ottoq-recert-runner' AND username = 'postgres'
                    AND command ~ $re$pg_try_advisory_xact_lock\(hashtext\('ottoq_recert_runner'\)::bigint\)$re$
                    AND command ~ $re$status IN \('running','paused'\)$re$) THEN
    RAISE EXCEPTION '0564 P1: the recertification runner no longer takes the world lock and yields to a live run as postgres';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_dial_experiment_runner'
                    AND prosrc ~ 'ottoq_try_world_lock\(' AND prosrc ~ $re$status IN \('running','paused'\)$re$) THEN
    RAISE EXCEPTION '0564 P1: the dial experiment runner no longer takes the world lock and yields to a live run';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_dial_pair' AND prosrc ~ 'ottoq_try_world_lock\(') THEN
    RAISE EXCEPTION '0564 P1: ottoq_dial_pair no longer takes the world lock';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname IN ('ottoq-recert-runner', 'ottoq-dial-experiment-runner')
                AND username <> 'postgres') THEN
    RAISE EXCEPTION '0564 P1: a check runner no longer runs as postgres, so this door (owned by postgres) cannot cancel it';
  END IF;
  IF NOT pg_has_role('postgres', 'pg_signal_backend', 'MEMBER') THEN
    RAISE EXCEPTION '0564 P1: postgres cannot signal backends (pg_signal_backend)';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF to_regprocedure('public.ottoq_operator_start_run(text,bigint,text,timestamptz)') IS NOT NULL THEN
    RAISE EXCEPTION '0564 P2: public.ottoq_operator_start_run already exists; this file has already been applied';
  END IF;
END $fresh$;

CREATE FUNCTION public.ottoq_operator_start_run(
  p_scenario_code text,
  p_seed          bigint      DEFAULT NULL,
  p_run_by        text        DEFAULT 'operator_demo',
  p_start_clock   timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $fn$
DECLARE
  c_world  constant bigint := hashtext('ottoq_recert_runner')::bigint;   -- the key ottoq_try_world_lock takes
  v_int    jsonb := '[]'::jsonb;
  v_ok     boolean;
  v_run    uuid;
  v_t0     timestamptz := clock_timestamp();
  v_waited numeric;
  r        record;
BEGIN
  IF p_scenario_code IS NULL OR btrim(p_scenario_code) = '' THEN
    RAISE EXCEPTION 'ottoq_operator_start_run: scenario_code required';
  END IF;

  -- A hand-run pair holds no lock this door can wait on, only the rows it has written; give its rollback longer than
  -- the API role's 8 s. Transaction-local, and ottoq_sim_run_scenario restores whatever it finds here.
  PERFORM set_config('lock_timeout', '15s', true);

  -- 1. Cancel every running check.
  FOR r IN
    SELECT a.pid, a.application_name, a.query_start,
           CASE WHEN a.query ~* 'ottoq_recert_runner'                 THEN 'recertification pair'
                WHEN a.query ~* 'ottoq_dial_(experiment_runner|pair)' THEN 'dial experiment pair'
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
      v_ok := false;   -- e.g. a superuser's backend: reported, and the start below still tries
    END;
    v_int := v_int || jsonb_build_object(
      'pid', r.pid, 'kind', r.kind, 'application', r.application_name,
      'running_s', round(extract(epoch FROM (v_t0 - r.query_start))::numeric, 1),
      'cancelled', COALESCE(v_ok, false));
  END LOOP;

  -- 2. Take the world lock: waits for a cancelled holder's rollback, and no check can begin until this run is live.
  PERFORM pg_advisory_xact_lock(c_world);
  v_waited := round((extract(epoch FROM (clock_timestamp() - v_t0)) * 1000)::numeric);

  -- 3. Start the run through the one start there is.
  v_run := public.ottoq_sim_run_scenario(p_scenario_code => p_scenario_code, p_seed => p_seed,
                                         p_run_by => COALESCE(p_run_by, 'operator_demo'),
                                         p_start_clock => p_start_clock);
  IF v_run IS NULL THEN
    RAISE EXCEPTION 'ottoq_operator_start_run: the scenario start returned no run for %', p_scenario_code;
  END IF;

  -- 4. Say what the start interrupted, where the run is read.
  IF jsonb_array_length(v_int) > 0 THEN
    UPDATE public.ottoq_sim_runs
       SET notes = COALESCE(notes, '') || ' | operator start interrupted '
                   || COALESCE((SELECT string_agg(COALESCE(e->>'kind', 'check') || ' (pid ' || (e->>'pid') || ', '
                                                  || COALESCE(e->>'running_s', '?') || ' s'
                                                  || CASE WHEN (e->>'cancelled')::boolean THEN '' ELSE ', NOT cancelled' END
                                                  || ')', '; ' ORDER BY (e->>'pid')::int)
                                  FROM jsonb_array_elements(v_int) e), 'a check')
                   || '; it re-runs after this run ends'
     WHERE sim_run_id = v_run;
  END IF;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', v_run, 'interrupted', v_int, 'waited_ms', v_waited);
END;
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_operator_start_run(text, bigint, text, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_operator_start_run(text, bigint, text, timestamptz) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_operator_start_run(text, bigint, text, timestamptz) TO service_role;

COMMENT ON FUNCTION public.ottoq_operator_start_run(text, bigint, text, timestamptz) IS
'0564. The cockpit''s start door (otto-twin-control POST /scenarios/start). A manual start always interrupts a running '
'check: it cancels each backend holding the world lock (hashtext(''ottoq_recert_runner'')) or calling '
'ottoq_determinism_pair / ottoq_dial_pair / ottoq_ab_pair (never a migration), takes the world lock so no check starts '
'before the run is live, then starts through ottoq_sim_run_scenario unchanged. An interrupted pair rolls back whole and '
're-runs after the run ends. Returns {ok, sim_run_id, interrupted, waited_ms}. service_role only.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_fn   constant text := 'public.ottoq_operator_start_run(text,bigint,text,timestamptz)';
  v_src  text;
  v_mine boolean;
BEGIN
  -- V1: SECURITY DEFINER owned by postgres with a pinned search_path, reachable by service_role and nobody else
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = v_fn::regprocedure AND p.prosecdef
                    AND pg_get_userbyid(p.proowner) = 'postgres'
                    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%')) THEN
    RAISE EXCEPTION '0564 V1: not a postgres-owned SECURITY DEFINER with a pinned search_path';
  END IF;
  IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION '0564 V1: service_role cannot execute the start door';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION '0564 V1: anon or authenticated can execute a function that cancels backends';
  END IF;

  -- V2: the body cancels, takes the same world lock the runners take, and starts through the one start there is
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_fn::regprocedure;
  IF v_src !~ 'pg_cancel_backend\(' OR v_src !~ 'pg_advisory_xact_lock\(c_world\)'
     OR v_src !~ $re$hashtext\('ottoq_recert_runner'\)::bigint$re$
     OR (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_sim_run_scenario\(', 'g')) <> 1 THEN
    RAISE EXCEPTION '0564 V2: the start door does not cancel, lock the world and start exactly once';
  END IF;

  -- V3: the world-lock key the door compares in pg_locks is the key the runners take. Read back on this session's own
  -- lock -- TRY only, never wait: if a check holds it right now, read the holder's lock row instead of blocking the apply.
  -- The lock is taken in its own statement: pg_locks is read once when a scan starts, so a lock taken inside the same
  -- query would not be in it.
  v_mine := pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint);
  IF NOT EXISTS (SELECT 1 FROM pg_locks l
                  WHERE l.locktype = 'advisory' AND l.granted AND l.objsubid = 1
                    AND (NOT v_mine OR l.pid = pg_backend_pid())
                    AND ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('ottoq_recert_runner')::bigint) THEN
    RAISE EXCEPTION '0564 V3: pg_locks does not show the world lock under the key the door compares';
  END IF;
  RAISE NOTICE '0564: ottoq_operator_start_run is in place; the world-lock key reads back from pg_locks';
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_operator_start_run(text, bigint, text, timestamptz); redeploy the otto-twin-control
-- that calls ottoq_sim_run_scenario directly (1.9.2-charge-wait) FIRST; and
-- DELETE FROM public.ottoq_cert_lineage WHERE name = '0564_a_manual_start_interrupts_a_running_check'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0564_a_manual_start_interrupts_a_running_check', false, false,
  'A new service_role-only function, ottoq_operator_start_run, the cockpit start door: it cancels a running check (world-lock holder or a pair call), takes the world lock, then starts through ottoq_sim_run_scenario unchanged. No engine path, runner or determinism pair calls it, so no certified digest can move and no dial experiment spans a changed engine.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
