-- migration-version: 20260923021253
-- migration-name:    the_dial_runner_lost_its_lock_to_the_recert_heartbeat_on_every_minute_they_share
--
-- 0440  **The dial-experiment runner takes one shot at a lock that the recertification heartbeat holds for a
--       fifth of a second at the top of every minute, and pg_cron starts both jobs in the same instant.** So the
--       first real call of `ottoq_dial_pair` lost the race and refused, and the runner (0439, `*/10`) would lose
--       it on the minutes it shares with job 746, which is every one of them. FINDINGS G161.
--
-- ══ §1 WHAT HAPPENED, MEASURED 2026-09-23 ════════════════════════════════════════════════════════════════════
--
--   - Job 746 (`ottoq-recert-runner`, `* * * * *`) opens with `pg_try_advisory_xact_lock(hashtext(
--     'ottoq_recert_runner')::bigint)` and, with every canon column current, returns within its own transaction.
--     Over its 24 short firings in the 30 minutes to 02:12 UTC it held that lock for 0.120 s on average, 0.182 s
--     at p95 and 0.235 s at most.
--   - 0439's `ottoq_dial_pair` and `ottoq_dial_experiment_runner` take the same lock with ONE try each, which is
--     what makes a dial pair and a determinism pair unable to share the world. That exclusion is right; the
--     single try is not.
--   - The first real execution of `ottoq_dial_pair` (a rolled-back 12-tick smoke, one-off cron job 756 at
--     02:10 UTC) started at 02:10:00.266 and was refused at 02:10:00.297: "the recertification runner (or
--     another pair) holds the world". Job 746 had fired at the same moment. pg_cron launches every job due in
--     a minute together, so the two meet on every shared minute rather than by chance, and the runner fires
--     only on shared minutes.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `public.ottoq_try_world_lock(attempts, sleep_s)`: the same transaction-scoped try, repeated up to 20
--       times 0.5 s apart. Ten seconds is about forty times the heartbeat's longest hold. A pair in progress
--       holds the lock for minutes, and the helper still gives up and returns false, so both callers keep their
--       answer to a busy world unchanged.
--   (2) Both callers use it in place of the single try, one splice each. Inside the runner the pair re-takes a
--       lock its own transaction already holds, which succeeds at once (advisory locks are re-entrant within a
--       session).
--
-- ══ §3 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   No engine function changes: only the two 0439 harness functions, which no tick and no certification arm
--   calls. Job 746 is untouched. It still takes one try and returns, because it runs every minute and a missed
--   minute costs it nothing.
--
-- ══ §4 NOT DONE ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   - The runner's cadence stays `*/10`. A 48-tick pair measured 9 minutes as a determinism pair, so the runner
--     is close to back to back while it is on. That is why its switch stays 0 outside a chosen quiet window
--     (0439 §5, G141).

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0440 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0440 P0: a determinism or dial pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0440 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the two callers as 0439 left them, one single-shot try each; the helper does not exist ──
DO $$
DECLARE v_src text; v_n int;
  c_try CONSTANT text := 'pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint)';
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure;
  IF md5(v_src) <> '311389d56593e35bd578c84397a78f88' THEN RAISE EXCEPTION '0440 P1: ottoq_dial_pair md5 is %', md5(v_src); END IF;
  v_n := (length(v_src) - length(replace(v_src, 'IF NOT ' || c_try || ' THEN', ''))) / length('IF NOT ' || c_try || ' THEN');
  IF v_n <> 1 THEN RAISE EXCEPTION '0440 P1: ottoq_dial_pair holds % single-shot tries, expected 1', v_n; END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_dial_experiment_runner()'::regprocedure;
  IF md5(v_src) <> '8645566d28ec573e79dca62eb5adcd92' THEN RAISE EXCEPTION '0440 P1: ottoq_dial_experiment_runner md5 is %', md5(v_src); END IF;
  v_n := (length(v_src) - length(replace(v_src, 'IF NOT ' || c_try || ' THEN', ''))) / length('IF NOT ' || c_try || ' THEN');
  IF v_n <> 1 THEN RAISE EXCEPTION '0440 P1: ottoq_dial_experiment_runner holds % single-shot tries, expected 1', v_n; END IF;
  IF to_regprocedure('public.ottoq_try_world_lock(integer,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0440 P1: ottoq_try_world_lock already exists';
  END IF;
END $$;

-- ── P2: the premise -- the heartbeat still takes this lock with one try, in the same words ──
DO $$
DECLARE v_cmd text;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobid = 746 AND jobname = 'ottoq-recert-runner' AND schedule = '* * * * *';
  IF v_cmd IS NULL OR position('IF NOT pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint) THEN RETURN; END IF;' IN v_cmd) = 0 THEN
    RAISE EXCEPTION '0440 P2: job 746 is not the every-minute single-try heartbeat this file was measured against';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0440_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname IN ('ottoq_dial_pair', 'ottoq_dial_experiment_runner');

-- ── (1) THE PATIENT TRY ──
CREATE OR REPLACE FUNCTION public.ottoq_try_world_lock(p_attempts integer DEFAULT 20, p_sleep_s numeric DEFAULT 0.5)
 RETURNS boolean
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO 'public'
AS $function$
/* 0440: the recertification lock (the one that keeps a dial pair and a determinism pair out of each other's world),
   tried up to p_attempts times, p_sleep_s apart. Job 746 holds it for about 0.12 s at the top of every minute even
   when there is nothing to certify (0.235 s at most, measured 2026-09-23), and pg_cron starts every job due in a
   minute together, so a single try from another cron job loses on every shared minute. A pair in progress holds it
   for minutes; this still returns false then. Transaction-scoped, exactly like the try it replaces. */
DECLARE v_i int := 0;
BEGIN
  LOOP
    IF pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint) THEN RETURN true; END IF;
    v_i := v_i + 1;
    EXIT WHEN v_i >= GREATEST(1, p_attempts);
    PERFORM pg_sleep(GREATEST(0, p_sleep_s));
  END LOOP;
  RETURN false;
END
$function$;
REVOKE ALL ON FUNCTION public.ottoq_try_world_lock(integer, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_try_world_lock(integer, numeric) TO service_role;

-- ── (2) BOTH CALLERS USE IT ──
DO $splice$
DECLARE v_def text; v_new text; r record;
  c_old CONSTANT text := 'IF NOT pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint) THEN';
  c_new CONSTANT text := 'IF NOT public.ottoq_try_world_lock() THEN   /* 0440: patient, not single-shot */';
BEGIN
  FOR r IN SELECT p.oid FROM pg_proc p
            WHERE p.oid IN ('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure,
                            'public.ottoq_dial_experiment_runner()'::regprocedure) LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(v_def, c_old, c_new);
    IF v_new = v_def OR position(c_old IN v_new) > 0 THEN
      RAISE EXCEPTION '0440 (2): the splice did not apply to %', r.oid::regprocedure;
    END IF;
    EXECUTE v_new;
  END LOOP;
END $splice$;

-- ── V1: the helper takes a free lock, and a held one is re-entrant for its own transaction ──
DO $$
BEGIN
  IF NOT public.ottoq_try_world_lock(40, 0.5) THEN
    RAISE EXCEPTION '0440 V1: the world lock could not be taken in 20 s with nothing in flight';
  END IF;
  IF NOT public.ottoq_try_world_lock(1, 0) THEN
    RAISE EXCEPTION '0440 V1: re-taking a lock this transaction holds failed';
  END IF;
END $$;

-- ── V2: neither caller keeps a single-shot try, in comment-stripped source ──
DO $$
DECLARE r record; v_src text;
BEGIN
  FOR r IN SELECT p.oid, p.prosrc FROM pg_proc p
            WHERE p.oid IN ('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure,
                            'public.ottoq_dial_experiment_runner()'::regprocedure) LOOP
    v_src := regexp_replace(regexp_replace(r.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g');
    IF position('pg_try_advisory_xact_lock' IN v_src) > 0 OR position('ottoq_try_world_lock()' IN v_src) = 0 THEN
      RAISE EXCEPTION '0440 V2: % still takes the lock single-shot', r.oid::regprocedure;
    END IF;
  END LOOP;
END $$;

-- ── V3: the runner's switch is still read first, so nothing waits while it is off ──
DO $$
DECLARE r jsonb;
BEGIN
  r := public.ottoq_dial_experiment_runner();
  IF COALESCE((r->>'ran')::boolean, true) OR r->>'why' <> 'dial_experiment_runner_enabled is 0' THEN
    RAISE EXCEPTION '0440 V3: the runner with its switch off answered %', r;
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0440_the_dial_runner_lost_its_lock_to_the_recert_heartbeat_on_every_minute_they_share',
   false,
   'ottoq_try_world_lock: the recertification advisory lock tried 20 x 0.5 s. ottoq_dial_pair and '
   'ottoq_dial_experiment_runner use it instead of a single try, which lost to job 746''s 0.12 s hold on shared '
   'minutes. Harness only: no tick or certification arm calls either function.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. Rollback: restore both functions from ottoq_schema_snapshots label '0440_pre'.
