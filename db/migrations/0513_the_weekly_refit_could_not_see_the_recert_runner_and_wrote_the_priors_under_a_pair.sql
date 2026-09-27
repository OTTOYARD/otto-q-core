-- migration-version: 20260927050506
-- migration-name:    the_weekly_refit_could_not_see_the_recert_runner_and_wrote_the_priors_under_a_pair
--
-- 0513  **G243: the weekly calibration refit cannot write the priors while a certification rig is running, the job
--       that asks for it can see the recert runner, and a refit that is deferred or refused is retried within the
--       hour instead of waiting a week.** `db/checks/0384`.
--
-- ══ §1 WHAT WAS WRONG ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Verdict 474 (busy_day/171717/48, the last column of the 0511 sweep) failed on `calibration` alone: its first arm
--   booted on priors cc798e04 and its second on bb7fb6fa, where every verdict from 457 to 473 had booted on c5fbb56e.
--   The weekly refit (cron 2, `ottoq_twin_ingest_refresh()`, Sundays 04:00 UTC) was held until 04:03:38.83 by the
--   previous pair and launched 21 ms after the runner started 474. Its rows landed 04:03:39.70-04:03:47.07.
--   Two separate defects let that happen:
--   (a) The refresh's guard (0201) looks for `ottoq_determinism_pair` in `pg_stat_activity.query`, which keeps the
--       first 1 kB of a query, and the recert runner (cron 746) names the pair at byte 1,542. That is G194's probe,
--       in one of the two copies inside a database function that G194's fix never reached. The guard can never see
--       a pair the runner holds.
--   (b) The refresh does not write the priors. It posts two requests to the `ottoq-twin-ingest` edge function and
--       returns in about 50 ms; the edge function fetches NOAA and EIA and writes the rows one to nine seconds later,
--       through `ottoq_twin_refit_distribution` and a PATCH on `ottoq_calibration_profiles`, with no guard at all.
--       A pair that starts after a correct check still gets the failure.
--   And a deferral, when the guard did fire, lost the week: the job runs once, and a deferred refit waited seven
--   days for the next Sunday.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `public.ottoq_certification_rig_matches(text, boolean)`: one query text, is it a certification rig? The pair
--       and rig names, plus `ottoq_recert_runner`, the runner's advisory-lock key, which sits in its first 100
--       characters. That is the G194 fix, made into one predicate so the next copy of the probe cannot drift.
--       IMMUTABLE, so V3 proves it on the runner's own visible text.
--   (2) `public.ottoq_certification_in_flight(boolean)`: how many other backends are running a rig. SECURITY
--       DEFINER because only a pg_read_all_stats member can read another role's query text, and the edge function
--       writes the calibration tables as service_role, which is not one. `ottoq.simulate_certification_in_flight = on`
--       adds one, so the guards can be proven without a second backend. The flag can only report a rig, never hide
--       one, so setting it can block a refit and nothing else.
--   (3) `ottoq_twin_ingest_refresh()` asks (2) instead of its own probe. It also skips a source that was refit in the
--       last six days (the dataset row ingested, and for EIA its hourly profile fitted), so it can safely run hourly.
--   (4) A statement-level BEFORE INSERT/UPDATE/DELETE trigger on the four calibration tables refuses while (2) reads
--       non-zero. The guard now sits where the rows are written, not only where the job starts. A rig's own writes
--       pass, since (2) never counts the caller, and nothing in a certified run writes these tables: the refit RPC
--       is their only writer.
--   (5) cron 2: '0 4 * * 0' -> '0 4-23 * * 0'. The first attempt is at the same moment, and a deferred or refused
--       refit is retried every hour through Sunday UTC. A refused edge-function write leaves its source stale, so
--       the next attempt asks for it again.
--
-- ══ §3 WHAT THIS DOES NOT DO ═══════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_retention_purge_runs` (cron 625) carries the other blind copy of the probe, and it is left alone on
--   purpose. Its probe is unreachable: the check above it ("a certification round is scheduled") matches any active
--   cron job whose command contains `ottoq_determinism_pair`, and cron 746 always does, so the purge has returned
--   early every night since the runner was created (by 2026-09-20). Nothing is lost today, because the demo start's
--   `ottoq_purge_prior_runs` keeps every non-production run younger than 48 hours. But unblocking it would purge the
--   nine operator runs G240's calibration is measured on, the oldest from 2026-09-25 19:12 UTC. So it waits for
--   G240's evidence ledger, and the two checks are fixed together when it is switched back on (db/checks/0384 §4).
--   Nor does this close the last millisecond: a pair that starts between the trigger's check and the refit's
--   commit still sees one write. Closing that needs a lock the runner holds for the pair's whole transaction,
--   which touches the certified harness and waits for a recert window.
--
-- ══ §4 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   No function a run or a pair calls changes. The new trigger fires only on writes to the calibration priors,
--   which nothing in a certified run makes, and the refit is a job, not a run.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0513 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body, the job and the tables this file changes, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_ingest_refresh()'::regprocedure)) <> '66a94e5141493b0b2dd8ab7febf9db63' THEN
    RAISE EXCEPTION '0513 P2: public.ottoq_twin_ingest_refresh is not the body this file patches';
  END IF;
  IF (SELECT schedule || '|' || command || '|' || active FROM cron.job WHERE jobid = 2)
       IS DISTINCT FROM '0 4 * * 0|SELECT ottoq_twin_ingest_refresh()|true' THEN
    RAISE EXCEPTION '0513 P2: cron job 2 is not the weekly refit this file reschedules';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger
              WHERE NOT tgisinternal
                AND tgrelid IN ('public.ottoq_calibration_distributions'::regclass, 'public.ottoq_calibration_profiles'::regclass,
                                'public.ottoq_calibration_correlations'::regclass, 'public.ottoq_calibration_datasets'::regclass))
     OR to_regprocedure('public.ottoq_certification_in_flight(boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_certification_rig_matches(text,boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_calibration_write_guard()') IS NOT NULL THEN
    RAISE EXCEPTION '0513 P2: a calibration trigger or one of this file''s functions already exists';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure))
       <> '890d2de189d638c1622a53efc863fb66' THEN
    RAISE EXCEPTION '0513 P2: public.ottoq_retention_purge_runs is not the body 0384 read; §3''s reasoning must be redone';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0513_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure;

-- (1) one query text: is it a certification rig?
CREATE FUNCTION public.ottoq_certification_rig_matches(p_query text, p_with_dial boolean DEFAULT true)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path = pg_catalog
AS $fn$
  -- 0513 (G243). pg_stat_activity keeps the first 1 kB of a query (track_activity_query_size), and the recert runner
  -- (cron 746) names ottoq_determinism_pair past it (G194). Its advisory-lock key, ottoq_recert_runner, is in its
  -- first 100 characters, so that is what identifies it.
  SELECT COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_determinism_pair%', '%ottoq_ab_pair%', '%ottoq_recert_runner%'])
      OR (COALESCE(p_with_dial, true)
          AND COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_dial_pair%', '%ottoq_dial_experiment_runner%']));
$fn$;

-- (2) how many other backends are running one
CREATE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
RETURNS integer
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  -- 0513 (G243). SECURITY DEFINER: only a pg_read_all_stats member reads another role's query text, and the
  -- calibration tables are written by service_role, which is not one. The caller is never counted.
  -- ottoq.simulate_certification_in_flight = on adds one, so the guards can be proven without a second backend. It
  -- can only report a rig, never hide one.
  SELECT (SELECT count(*)::int FROM pg_stat_activity a
           WHERE a.pid <> pg_backend_pid() AND a.state IS DISTINCT FROM 'idle'
             AND public.ottoq_certification_rig_matches(a.query, p_with_dial))
       + CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END;
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_certification_rig_matches(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_certification_in_flight(boolean) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.ottoq_certification_in_flight(boolean) IS
  '0513 (G243). Backends other than the caller running a certification rig: a determinism, A/B or dial pair, the '
  'dial experiment runner, or the recert runner (matched by its lock key, since it names the pair past the 1 kB of '
  'query text pg_stat_activity keeps, G194). p_with_dial=false leaves out the dial rigs. Use this, not a copy.';

-- (3) the refresh asks the shared probe, and skips a source refit in the last six days
DO $patch1$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_twin_ingest_refresh()'::regprocedure);
  v_pairs text[][] := ARRAY[
    [$o1$  v_anon text; v_eia text; v_noaa text;
$o1$,
     $n1$  v_anon text; v_eia text; v_noaa text;
  v_eia_fresh boolean; v_noaa_fresh boolean;   -- 0513
$n1$],
    [$o2$  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE WARNING 'twin_ingest_refresh: deferred -- a certification round is scheduled or in flight (0201)';$o2$,
     $n2$  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     -- 0513 (G243): the recert runner names the pair past the 1 kB of query text pg_stat_activity keeps (G194), so the
     -- probe that stood here never saw it. The shared one does. The calibration tables also refuse writes while a rig
     -- runs, because the refit itself lands seconds after this function returns.
     OR public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE WARNING 'twin_ingest_refresh: deferred -- a certification round is scheduled or in flight (0201, 0513)';$n2$],
    [$o3$  IF v_anon IS NULL THEN RAISE WARNING 'twin_ingest_refresh: anon key missing from vault'; RETURN; END IF;
$o3$,
     $n3$  IF v_anon IS NULL THEN RAISE WARNING 'twin_ingest_refresh: anon key missing from vault'; RETURN; END IF;

  -- 0513 (G243): cron 2 retries hourly through Sunday, so a source refit in the last six days is not asked for again.
  -- A refit that was deferred, refused by the calibration tables' guard, or failed upstream leaves its source stale.
  v_eia_fresh  := EXISTS (SELECT 1 FROM public.ottoq_calibration_datasets d
                           WHERE d.dataset_code = 'eia_grid' AND d.ingested_at > now() - interval '6 days')
                  AND NOT EXISTS (SELECT 1 FROM public.ottoq_calibration_profiles p
                                   WHERE p.dataset_code = 'eia_grid' AND p.fitted_at <= now() - interval '6 days');
  v_noaa_fresh := EXISTS (SELECT 1 FROM public.ottoq_calibration_datasets d
                           WHERE d.dataset_code = 'noaa_nws' AND d.ingested_at > now() - interval '6 days');
$n3$],
    [$o4$  IF v_eia IS NOT NULL THEN
$o4$,
     $n4$  IF v_eia IS NOT NULL AND NOT v_eia_fresh THEN
$n4$],
    [$o5$  IF v_noaa IS NOT NULL THEN
$o5$,
     $n5$  IF v_noaa IS NOT NULL AND NOT v_noaa_fresh THEN
$n5$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0513: refresh patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch1$;

-- (4) the priors refuse a write while a rig runs
CREATE FUNCTION public.ottoq_calibration_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
BEGIN
  -- 0513 (G243): a certification pair's two arms must boot on the same priors. The weekly refit writes these tables
  -- from an edge function, seconds after the job that asked for it has checked and returned, so the check is made
  -- here too. A refused refit is retried at cron 2's next hourly attempt.
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION 'G243: % on % refused -- a certification rig is running and reads the calibration priors; the weekly refit retries next hour',
      TG_OP, TG_TABLE_NAME
      USING ERRCODE = '55P03';
  END IF;
  RETURN NULL;
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_calibration_write_guard() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_calibration_distributions
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_calibration_profiles
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_calibration_correlations
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();
CREATE TRIGGER ottoq_calibration_write_guard BEFORE INSERT OR UPDATE OR DELETE ON public.ottoq_calibration_datasets
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_calibration_write_guard();

-- (5) the weekly refit retries hourly through Sunday UTC
SELECT cron.alter_job(job_id := 2, schedule := '0 4-23 * * 0');

DO $verify$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_twin_ingest_refresh()'::regprocedure);
BEGIN
  -- V1: the body carries its change once and the old probe is gone; four statement-level guards; the job moved;
  --     the purge untouched.
  IF (length(v_def) - length(replace(v_def, 'public.ottoq_certification_in_flight(true) > 0', '')))
       / length('public.ottoq_certification_in_flight(true) > 0') <> 1
     OR position('a.query ILIKE ''%ottoq_determinism_pair%''' IN v_def) > 0
     OR (length(v_def) - length(replace(v_def, 'AND NOT v_eia_fresh', ''))) / length('AND NOT v_eia_fresh') <> 1
     OR (length(v_def) - length(replace(v_def, 'AND NOT v_noaa_fresh', ''))) / length('AND NOT v_noaa_fresh') <> 1
     OR (SELECT count(*) FROM pg_trigger t
          WHERE t.tgname = 'ottoq_calibration_write_guard' AND NOT t.tgisinternal AND t.tgenabled = 'O'
            AND (t.tgtype & 1) = 0                -- statement-level
            AND (t.tgtype & 2) = 2                -- BEFORE
            AND (t.tgtype & 28) = 28              -- INSERT, DELETE and UPDATE
            AND t.tgrelid IN ('public.ottoq_calibration_distributions'::regclass, 'public.ottoq_calibration_profiles'::regclass,
                              'public.ottoq_calibration_correlations'::regclass, 'public.ottoq_calibration_datasets'::regclass)) <> 4
     OR (SELECT schedule || '|' || command || '|' || active FROM cron.job WHERE jobid = 2)
          IS DISTINCT FROM '0 4-23 * * 0|SELECT ottoq_twin_ingest_refresh()|true'
     OR md5(pg_get_functiondef('public.ottoq_retention_purge_runs(integer,integer,interval,boolean)'::regprocedure))
          <> '890d2de189d638c1622a53efc863fb66' THEN
    RAISE EXCEPTION '0513 V1: a body, a trigger or the job is not what this file leaves';
  END IF;
  -- V2: the refresh keeps its privileges and settings; the new functions are the definer's, closed to the browser.
  IF (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure)
       <> 'postgres=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'public.ottoq_twin_ingest_refresh()'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_certification_in_flight(boolean)'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_calibration_write_guard()'::regprocedure)
     OR has_function_privilege('anon', 'public.ottoq_certification_in_flight(boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_certification_in_flight(boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_certification_rig_matches(text,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_certification_rig_matches(text,boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_calibration_write_guard()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_calibration_write_guard()', 'EXECUTE') THEN
    RAISE EXCEPTION '0513 V2: a function''s privileges or settings are not what this file leaves';
  END IF;
END $verify$;

-- V3: proven inside a block that is rolled back. The flag stands in for a second backend running a pair; the queued
--     edge-function requests it plants are rolled back with it and never reach pg_net's worker.
DO $v3$
DECLARE
  v_msg text; v_vis text; v_q0 bigint; v_refused boolean; n int; v_src text;
  c_url constant text := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-twin-ingest';
BEGIN
  BEGIN
    -- (a) the predicate sees what the old probe could not: the runner's own visible text
    -- pg_stat_activity keeps track_activity_query_size - 1 bytes of a query (pg_settings holds it in bytes)
    SELECT left(j.command, s.setting::int - 1) INTO v_vis
      FROM cron.job j, pg_settings s
     WHERE j.jobname = 'ottoq-recert-runner' AND s.name = 'track_activity_query_size';
    IF v_vis IS NULL
       OR NOT public.ottoq_certification_rig_matches(v_vis, false)
       OR v_vis ILIKE '%ottoq_determinism_pair%'
       OR NOT public.ottoq_certification_rig_matches('SELECT public.ottoq_determinism_pair(p_seed => 1)', false)
       OR NOT public.ottoq_certification_rig_matches('SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();', true)
       OR public.ottoq_certification_rig_matches('SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();', false)
       OR public.ottoq_certification_rig_matches('SELECT public.ottoq_cron_tick()', true)
       OR public.ottoq_certification_rig_matches(NULL, true) THEN
      RAISE EXCEPTION '0513 V3 FAILED (a): the predicate does not match the runner''s visible text, or matches what it should not (visible text % chars)',
        length(v_vis);
    END IF;

    -- (b) a rig in flight: a write to the priors is refused, and the refresh defers without asking for a refit
    PERFORM set_config('ottoq.simulate_certification_in_flight', 'on', true);
    IF public.ottoq_certification_in_flight(false) < 1 THEN
      RAISE EXCEPTION '0513 V3 FAILED (b): the flag did not register as a rig in flight';
    END IF;
    v_refused := false;
    BEGIN
      UPDATE public.ottoq_calibration_correlations SET method = method WHERE false;
    EXCEPTION WHEN SQLSTATE '55P03' THEN v_refused := SQLERRM LIKE 'G243: UPDATE on ottoq_calibration_correlations refused%';
    END;
    IF NOT v_refused THEN RAISE EXCEPTION '0513 V3 FAILED (b): a write to the priors went through with a rig in flight'; END IF;
    SELECT COALESCE(max(id), 0) INTO v_q0 FROM net.http_request_queue;
    PERFORM public.ottoq_twin_ingest_refresh();
    SELECT count(*) INTO n FROM net.http_request_queue WHERE id > v_q0 AND url = c_url;
    IF n <> 0 THEN RAISE EXCEPTION '0513 V3 FAILED (b): the refresh asked for % refit(s) with a rig in flight', n; END IF;

    -- (c) nothing in flight: a write goes through, and with both sources refit today the refresh asks for nothing
    PERFORM set_config('ottoq.simulate_certification_in_flight', 'off', true);
    UPDATE public.ottoq_calibration_correlations SET method = method WHERE false;
    IF NOT EXISTS (SELECT 1 FROM public.ottoq_calibration_datasets WHERE dataset_code = 'noaa_nws' AND ingested_at > now() - interval '6 days')
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_calibration_datasets WHERE dataset_code = 'eia_grid' AND ingested_at > now() - interval '6 days') THEN
      RAISE EXCEPTION '0513 V3 FAILED (c): the premise that both sources were refit this week does not hold';
    END IF;
    SELECT COALESCE(max(id), 0) INTO v_q0 FROM net.http_request_queue;
    PERFORM public.ottoq_twin_ingest_refresh();
    SELECT count(*) INTO n FROM net.http_request_queue WHERE id > v_q0 AND url = c_url;
    IF n <> 0 THEN RAISE EXCEPTION '0513 V3 FAILED (c): the refresh asked for % refit(s) of sources refit today', n; END IF;

    -- (d) a stale source is asked for again, and only that one
    UPDATE public.ottoq_calibration_datasets SET ingested_at = ingested_at - interval '7 days' WHERE dataset_code = 'noaa_nws';
    SELECT COALESCE(max(id), 0) INTO v_q0 FROM net.http_request_queue;
    PERFORM public.ottoq_twin_ingest_refresh();
    SELECT count(*), max(convert_from(body, 'UTF8')::jsonb->>'source') INTO n, v_src
      FROM net.http_request_queue WHERE id > v_q0 AND url = c_url;
    IF n <> 1 OR v_src IS DISTINCT FROM 'noaa' THEN
      RAISE EXCEPTION '0513 V3 FAILED (d): a stale NOAA source produced % request(s), source %', n, COALESCE(v_src, 'none');
    END IF;

    RAISE EXCEPTION '0513 V3 PASSED: (a) the runner''s visible text (% chars) is a rig to the predicate and invisible to the old probe; (b) with a rig in flight a write to the priors is refused and the refresh asks for nothing; (c) with none, writes go through and two fresh sources are skipped; (d) a stale NOAA source is asked for again, alone',
      length(v_vis);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0513 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0513 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore public.ottoq_twin_ingest_refresh from ottoq_schema_snapshots label '0513_pre' (CREATE OR REPLACE
-- keeps the ACL); DROP TRIGGER ottoq_calibration_write_guard ON each of the four tables; DROP the three functions;
-- SELECT cron.alter_job(2, schedule := '0 4 * * 0').

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0513_the_weekly_refit_could_not_see_the_recert_runner_and_wrote_the_priors_under_a_pair', false,
  'The weekly calibration refit asks a shared probe that sees the recert runner (G194) instead of its own blind copy, '
  'the four calibration tables refuse writes while a certification rig runs, the refit skips a source refit in the last '
  'six days, and cron 2 retries hourly through Sunday. No function a run or a pair calls changes, and nothing in a '
  'certified run writes the priors.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
