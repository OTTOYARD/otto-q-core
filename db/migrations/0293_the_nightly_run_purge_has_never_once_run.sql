-- migration-version: PENDING
-- migration-name:    0293_the_nightly_run_purge_has_never_once_run
--
-- 0293  THE NIGHTLY RUN PURGE HAS NEVER ONCE RUN
--
-- Task #87 recorded G23 as "CLOSED: 0269 applied + proven, run purge scheduled
-- (jobid 625)". The scheduling was real. The purge was not. Its first and only
-- automated firing, this morning, FAILED:
--
--   jobid 625  2026-09-14 09:00:00.191+00 -> 09:00:00.450+00   status: failed
--   ERROR:  invalid transaction termination
--   CONTEXT:  PL/pgSQL function ottoq_retention_purge_runs(...) line 152 at COMMIT
--
-- 0.26 seconds, nothing purged. public.ottoq_sim_runs still shows 939 rows with
-- purged_at set, exactly the figure recorded when the job was scheduled, and 37
-- completed runs are now eligible and untouched.
--
-- ---------------------------------------------------------------------------
-- AND THE CHECK THAT WAS SUPPOSED TO CATCH THIS WOULD HAVE PASSED IT.
--
-- The verification procedure written for this firing named
-- ottoq_retention_state.updated_at as "THE DISCRIMINATOR", on the grounds that
-- it moves only when the purge runs past its guard. Last known value before the
-- firing: 2026-09-13 21:10:56. Value when checked after: 2026-09-14 08:00:01.
-- It moved. By that test, G23 was closed end to end.
--
-- IT MOVED AT 08:00, AND THE RUN PURGE FIRES AT 09:00. The 08:00 write came
-- from jobid 11, ottoq-retention-nightly, a DIFFERENT job that purges events and
-- writes the SAME table. The discriminator does not discriminate: two jobs share
-- one state row, so a reader cannot tell which of them moved it. The honest
-- signal for this job is cron.job_run_details.status for jobid 625, plus the
-- count of ottoq_sim_runs.purged_at, and that is what the check file uses now.
--
-- ---------------------------------------------------------------------------
-- THE CAUSE, as an A/B measured on this database on this night rather than as
-- a claim about PostgreSQL:
--
--   jobid  command                                     stmts  result
--   11     CALL ottoq_retention_purge_worker(...);         1  succeeded 08:00,
--                                                             ran 71 seconds
--   625    SET statement_timeout TO '10min';               2  FAILED at the
--          CALL ottoq_retention_purge_runs(...);              first COMMIT
--
-- Both call a PROCEDURE that COMMITs (prokind 'p'; the worker has COMMIT
-- statements too). The one submitted as a SINGLE statement works. The one
-- prefixed with a SET does not, and fails precisely at COMMIT with 2D000.
--
-- THE CONFOUND, named rather than hidden: they are different procedures, so
-- this is one uncontrolled variable away from a clean experiment. What makes it
-- convincing anyway is WHERE it fails -- at the COMMIT, which is exactly the
-- statement a procedure may not execute inside an enclosing transaction block,
-- and a multi-statement submission is one. The fix is correct under either
-- reading, because a single-statement command is what the working sibling uses.
--
-- ---------------------------------------------------------------------------
-- WHY THE SET CANNOT SIMPLY BE DROPPED. It was not decoration: this database's
-- statement_timeout reset_val is 120000 ms -- TWO MINUTES -- so a long purge
-- statement really could be killed. The timeout moves onto the procedure
-- instead, where it belongs and where it travels with every caller.
--
--   ALTER PROCEDURE ... SET statement_timeout = '10min'
--
-- AND ONE RESIDUAL UNCERTAINTY, stated because it is not resolved. A
-- procedure-level SET is restored around the call, and this procedure COMMITs
-- internally; whether the setting survives its own COMMITs was NOT verified,
-- because it cannot be verified from the channel available here (see below).
-- The worst case is that the timeout reverts to the 2-minute default after the
-- first COMMIT -- which is survivable and already proven survivable: jobid 11
-- runs the same micro-batched shape under that exact 2-minute default and
-- completes in 71 seconds. The procedure also self-limits via p_time_budget_s
-- (300 s), so a 10-minute per-statement ceiling can never bind the job as a
-- whole, only one pathological statement.
--
-- WHAT COULD NOT BE TESTED HERE, and why the proof is a firing rather than a
-- call. The Supabase management SQL channel wraps every submission in a
-- transaction -- a bare CALL of a COMMIT-ing procedure raises the same 2D000 --
-- and it pools connections, so pg_temp objects do not survive between
-- statements. A COMMIT-ing procedure therefore cannot be exercised through it
-- at all. The verification for this file is db/checks/0226: a transient cron
-- probe that calls the real procedure with a 999-day keep window, which matches
-- ZERO rows (measured: 0) and so deletes nothing, while still reaching the
-- COMMIT -- because the loop's COMMIT sits BEFORE its `EXIT WHEN v_n = 0`.
--
-- NOT FIXED HERE, deliberately: the 37 eligible runs are left for the job to
-- purge on its own schedule. Purging them by hand would mix a data operation
-- into a defect fix, and the whole point is that the scheduled path works.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0293 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0293 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0293 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0293 P-: nothing in flight';
END $inflight$;

-- P0. THE JOB IS THE ONE THIS FILE WAS WRITTEN AGAINST -----------------------
DO $p0$
DECLARE v_md5 text; v_sched text; v_active boolean; v_db text; v_user text;
BEGIN
  SELECT md5(command), schedule, active, database, username
    INTO v_md5, v_sched, v_active, v_db, v_user
    FROM cron.job WHERE jobid = 625;
  IF v_md5 IS NULL THEN
    RAISE EXCEPTION '0293 P0: cron job 625 does not exist';
  END IF;
  IF v_md5 <> 'b82e46b903263331ad297f7ff17bf8f6' THEN
    RAISE EXCEPTION '0293 P0: job 625 no longer carries the two-statement command this '
                    'file replaces (live md5 %). Someone changed it since; re-read it', v_md5;
  END IF;
  IF v_sched <> '0 9 * * *' OR NOT v_active THEN
    RAISE EXCEPTION '0293 P0: job 625 schedule/active changed (% / %). This file changes '
                    'ONLY the command and must not paper over another edit', v_sched, v_active;
  END IF;
  RAISE NOTICE '0293 P0: job 625 is the failing two-statement command, % as %, active',
               v_sched, v_user;
END $p0$;

-- P1. THE FAILURE IS ON THE RECORD -------------------------------------------
-- The premise of this file is a measured failure, not a suspicion. If cron has
-- no failed row for 625, the premise is wrong and the file must not apply.
DO $p1$
DECLARE v_failed int; v_msg text;
BEGIN
  SELECT count(*), max(return_message) INTO v_failed, v_msg
    FROM cron.job_run_details
   WHERE jobid = 625 AND status = 'failed'
     AND return_message ILIKE '%invalid transaction termination%';
  IF v_failed = 0 THEN
    RAISE EXCEPTION '0293 P1: no failed run of job 625 with an invalid-transaction-termination '
                    'error is on record. This file exists to fix that failure; if it did not '
                    'happen, re-diagnose before changing the job';
  END IF;
  RAISE NOTICE '0293 P1: % failed firing(s) on record', v_failed;
END $p1$;

-- P2. THE TARGET IS A COMMIT-ING PROCEDURE WITH NO TIMEOUT OF ITS OWN --------
DO $p2$
DECLARE v_kind char; v_commits int; v_config text;
BEGIN
  SELECT p.prokind,
         (SELECT count(*) FROM regexp_matches(p.prosrc, '(?m)^\s*COMMIT\s*;', 'g')),
         array_to_string(p.proconfig, ' | ')
    INTO v_kind, v_commits, v_config
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  IF v_kind IS NULL THEN
    RAISE EXCEPTION '0293 P2: public.ottoq_retention_purge_runs does not exist';
  END IF;
  IF v_kind <> 'p' THEN
    RAISE EXCEPTION '0293 P2: ottoq_retention_purge_runs is prokind %, expected a PROCEDURE. '
                    'ALTER PROCEDURE below would fail', v_kind;
  END IF;
  IF v_commits < 1 THEN
    RAISE EXCEPTION '0293 P2: the procedure has no COMMIT. The whole diagnosis rests on it '
                    'committing internally; re-read it';
  END IF;
  IF v_config IS NOT NULL THEN
    RAISE EXCEPTION '0293 P2: the procedure already carries proconfig (%). This file sets '
                    'statement_timeout and must not silently replace an existing setting',
                    v_config;
  END IF;
  RAISE NOTICE '0293 P2: procedure with % COMMIT statements and no proconfig', v_commits;
END $p2$;

-- P3. THE CONTROL ARM STILL LOOKS LIKE A CONTROL ARM -------------------------
-- The A/B this file's diagnosis rests on: jobid 11 is a SINGLE-statement CALL
-- of a COMMIT-ing procedure and it succeeds. If that stops being true, the
-- comparison in the header is stale.
DO $p3$
DECLARE v_cmd text; v_ok int;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobid = 11;
  IF v_cmd IS NULL OR v_cmd !~ '^\s*CALL ' OR v_cmd ~ ';\s*\S' THEN
    RAISE EXCEPTION '0293 P3: job 11 is no longer a single-statement CALL (%). The control '
                    'arm of this file''s A/B is gone; re-measure before applying', v_cmd;
  END IF;
  SELECT count(*) INTO v_ok FROM cron.job_run_details
   WHERE jobid = 11 AND status = 'succeeded' AND start_time > now() - interval '48 hours';
  IF v_ok = 0 THEN
    RAISE EXCEPTION '0293 P3: job 11 has not succeeded in 48 hours, so it is not evidence '
                    'that a single-statement CALL of a committing procedure works here';
  END IF;
  RAISE NOTICE '0293 P3: control arm intact -- job 11 single-statement, % success(es) in 48h', v_ok;
END $p3$;

-- ---------------------------------------------------------------------------
-- THE FIX, both halves. The timeout moves onto the procedure so the command can
-- be a single statement.
ALTER PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean)
  SET statement_timeout = '10min';

SELECT cron.alter_job(
  job_id  => 625,
  command => 'CALL public.ottoq_retention_purge_runs(300, 2000, ''48 hours'', false);'
);

-- ---------------------------------------------------------------------------
-- A1. THE COMMAND IS NOW ONE STATEMENT AND CARRIES NO SET.
DO $a1$
DECLARE v_cmd text;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobid = 625;
  IF v_cmd !~ '^\s*CALL ' THEN
    RAISE EXCEPTION 'A1 FAILED: job 625 does not start with CALL: %', v_cmd;
  END IF;
  IF v_cmd ~* '(^|\s)SET\s' THEN
    RAISE EXCEPTION 'A1 FAILED: job 625 still contains a SET, which is what broke it: %', v_cmd;
  END IF;
  --: exactly one terminating semicolon, nothing after it
  IF v_cmd ~ ';\s*\S' THEN
    RAISE EXCEPTION 'A1 FAILED: job 625 still has more than one statement: %', v_cmd;
  END IF;
  IF v_cmd !~ 'ottoq_retention_purge_runs\(300, 2000, ''48 hours'', false\)' THEN
    RAISE EXCEPTION 'A1 FAILED: the arguments changed; they must stay (300, 2000, 48 hours, '
                    'false): %', v_cmd;
  END IF;
  RAISE NOTICE 'A1 OK: %', v_cmd;
END $a1$;

-- A2. THE TIMEOUT SURVIVED THE MOVE.
DO $a2$
DECLARE v_config text;
BEGIN
  SELECT array_to_string(p.proconfig, ' | ') INTO v_config
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  IF v_config IS NULL OR v_config !~ 'statement_timeout=10min' THEN
    RAISE EXCEPTION 'A2 FAILED: the procedure does not carry statement_timeout=10min (%). '
                    'The cron SET was removed, so without this the purge runs under the '
                    '2-minute default', COALESCE(v_config,'NULL');
  END IF;
  RAISE NOTICE 'A2 OK: procedure carries %', v_config;
END $a2$;

-- A3. NOTHING ELSE ABOUT THE JOB MOVED.
DO $a3$
DECLARE v_sched text; v_active boolean; v_db text; v_user text; v_name text;
BEGIN
  SELECT schedule, active, database, username, jobname
    INTO v_sched, v_active, v_db, v_user, v_name FROM cron.job WHERE jobid = 625;
  IF v_sched <> '0 9 * * *' OR NOT v_active OR v_db <> 'postgres'
     OR v_user <> 'postgres' OR v_name <> 'ottoq-run-purge-nightly' THEN
    RAISE EXCEPTION 'A3 FAILED: something other than the command changed on job 625 '
                    '(% / % / % / % / %)', v_name, v_sched, v_active, v_db, v_user;
  END IF;
  RAISE NOTICE 'A3 OK: schedule, active, database, user and name all unchanged';
END $a3$;

-- A4. NOTHING WAS PURGED BY THIS FILE.
-- It changes a schedule entry and a procedure attribute. If the purged count
-- moved, something ran that should not have.
DO $a4$
DECLARE v_purged int;
BEGIN
  SELECT count(*) INTO v_purged FROM public.ottoq_sim_runs WHERE purged_at IS NOT NULL;
  IF v_purged <> 939 THEN
    RAISE EXCEPTION 'A4 FAILED: purged run count is % , was 939 when this file was written. '
                    'This migration must not purge anything', v_purged;
  END IF;
  RAISE NOTICE 'A4 OK: 939 purged runs, unchanged -- this file moved no data';
END $a4$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0293_the_nightly_run_purge_has_never_once_run', false,
 'Fixes cron job 625 (ottoq-run-purge-nightly), whose first and only automated firing on 2026-09-14 09:00 UTC failed in 0.26 s with "invalid transaction termination ... ottoq_retention_purge_runs line 152 at COMMIT", purging nothing. Its command was two statements -- a SET statement_timeout followed by a CALL -- and a procedure cannot COMMIT inside an enclosing transaction block. Measured A/B on the same database the same night: jobid 11 calls a COMMIT-ing procedure as a SINGLE statement and succeeded at 08:00 in 71 seconds. Confound named in the file: they are different procedures. The fix moves the timeout onto the procedure (ALTER PROCEDURE ... SET statement_timeout = 10min, needed because this database resets statement_timeout to 2 minutes) so the cron command becomes a single CALL. Also records that the verification written for this firing would have PASSED it: ottoq_retention_state.updated_at was named the discriminator but is written by BOTH purge jobs, and the 08:00 events purge moved it an hour before the 09:00 run purge failed. Residual uncertainty stated and not resolved: whether a procedure-level SET survives the procedure own COMMITs was not testable from the available channel, which wraps every submission in a transaction and pools connections; worst case the timeout reverts to the 2-minute default, which jobid 11 already proves survivable for this shape. forces_recert=false: touches no engine function, no frame, no decide path -- only a cron command and a procedure attribute, and A4 asserts no rows were purged.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
