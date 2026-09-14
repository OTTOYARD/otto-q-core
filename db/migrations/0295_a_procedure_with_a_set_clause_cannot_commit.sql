-- migration-version: PENDING
-- migration-name:    0295_a_procedure_with_a_set_clause_cannot_commit
--
-- 0295  A PROCEDURE WITH A SET CLAUSE CANNOT COMMIT
--
-- The third diagnosis of the same defect, and the one the database agreed with.
-- It also captures a change already made live: the RESET below was executed
-- out-of-band as a diagnostic at 09:49 UTC, before this file existed. That is
-- backwards from the house rule and is recorded here rather than tidied away.
--
-- ---------------------------------------------------------------------------
-- THE SEQUENCE, INCLUDING BOTH OF MY WRONG TURNS
--
--   09:00  job 625 fires for the first time ever. FAILS at the in-loop COMMIT.
--          proconfig NULL, cursor loop present.
--   0293   I blame the cron command's two statements. A single-statement probe
--          fails identically -> REFUTED. But 0293 also did
--          ALTER PROCEDURE ... SET statement_timeout = '10min',
--          WHICH INTRODUCED A SECOND, INDEPENDENT CAUSE.
--   0294   I remove the cursor loop. Still fails -- at line 166 instead of 152,
--          which is the SAME COMMIT displaced by fourteen lines of new comment.
--          I briefly read that as 0294 having failed. It had not.
--   09:49  RESET statement_timeout on the procedure. Nothing else changed.
--   09:50  THE PROBE SUCCEEDS. 62 seconds, return message 'CALL'.
--
-- So BOTH mechanisms were real and each was individually sufficient to break
-- it. The cursor loop was the original cause (0294 fixed it). The SET clause
-- was a cause I ADDED while trying to fix it. Removing either alone leaves the
-- job broken, which is exactly why the first two probes looked like failures of
-- the fix rather than the arrival of a new fault.
--
-- THE CONTROL ARM SAID THIS FROM THE START and I did not read it:
--
--   procedure                                 proconfig                result
--   ottoq_retention_purge_runs                statement_timeout=10min  FAILED
--   ottoq_retention_purge_worker (x2)         NULL                     succeeds
--
-- A procedure carrying a SET clause may not execute transaction control. The
-- working sibling never had one.
--
-- ---------------------------------------------------------------------------
-- AND THE TIMEOUT DOES NOT COME BACK. It was never there before 0293; the
-- sibling that works nightly does not have one; and the successful probe ran 62
-- seconds under this database's 2-minute default with room to spare. The
-- procedure already self-limits with p_time_budget_s and deletes in 2000-row
-- micro-batches. If a single batch ever approaches two minutes the answer is a
-- smaller batch, not a longer timeout -- and a longer timeout cannot be
-- expressed as a SET clause here at any price, because that is the thing that
-- stops it committing.
--
-- ---------------------------------------------------------------------------
-- THE PROBE WAS NOT THE NO-OP I CLAIMED, AND IT PURGED 20 RUNS.
--
-- I scheduled it as `CALL ottoq_retention_purge_runs(60, 2000, '999 days', false)`
-- and asserted, in 0293's banner, in db/checks/0226 and in G63, that a 999-day
-- keep window matches zero rows and so deletes nothing. I verified that: zero
-- rows are older than 999 days. THE PROCEDURE NEVER USES p_keep WHEN THE POLICY
-- TABLE HAS A ROW:
--
--   SELECT keep_interval INTO v_keep
--     FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
--   v_keep := COALESCE(v_keep, p_keep);          -- p_keep is the FALLBACK
--
-- ottoq_retention_policy has an enabled engine_rows row of 48:00:00, so the
-- probe ran the REAL retention window. It purged 20 runs.
--
-- I had read that line hours earlier, when I pulled the source for 0294, and
-- did not register it. I measured which rows MY parameter would match instead
-- of which rows THE PROCEDURE would match -- the same defect class this repo
-- has been cataloguing all night, committed by the person cataloguing it.
--
-- WHAT WAS ACTUALLY PURGED, measured afterwards rather than assumed:
--   20 runs, all started 2026-09-12 04:05-06:20, youngest 2 days 3.5 h old
--   20 of 20 had a row in ottoq_run_archives      (the procedure's own gate)
--    0 were status='running'
--    0 were run_by='production_live'
--   the three runs this session's G60 evidence rests on -- 91139ad8, 5712f828
--   and 36e5cc68 -- are NOT purged, and are well inside the 48-hour window.
--
-- So the deletion was exactly what the nightly job is designed to do, on
-- exactly the population it targets, about ten hours late. Every guard held.
-- No evidence was lost. That is the outcome, and it does not make the claim
-- correct: I said a thing deleted nothing while it deleted twenty runs' engine
-- rows, and the only reason that is not a bad outcome is luck about which rows
-- were eligible.
--
-- THE RULE THIS EARNS: never call this procedure to test it. Its keep window is
-- whatever ottoq_retention_policy says, not what the caller passes, so there is
-- no safe parameterisation. A future probe must disable the policy row inside a
-- rolled-back transaction, or run against a scratch database, or not run at all.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0295 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0295 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0295 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0295 P-: nothing in flight';
END $inflight$;

-- P0. NO PURGE IS RUNNING. This procedure deletes; do not touch it mid-pass.
DO $p0$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%retention_purge%';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0295 P0: % retention purge backend(s) active; wait for the pass to end', v_n;
  END IF;
  RAISE NOTICE '0295 P0: no purge in flight';
END $p0$;

-- P1. 0294 IS IN PLACE. This file is the second half of that fix, not a
-- replacement for it -- removing the SET clause alone would leave the cursor
-- loop and the job would still fail.
DO $p1$
DECLARE v_src text; v_forin int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  SELECT count(*) INTO v_forin FROM regexp_matches(v_src, 'FOR\s+\w+\s+IN\s+SELECT', 'g');
  IF v_forin > 0 THEN
    RAISE EXCEPTION '0295 P1: a query-driven FOR loop is back (%). 0294 must be in place '
                    'first; both causes have to be gone together', v_forin;
  END IF;
  IF position('FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP' in v_src) = 0 THEN
    RAISE EXCEPTION '0295 P1: 0294''s integer loop is not present';
  END IF;
  RAISE NOTICE '0295 P1: 0294 is in place -- no cursor loop, integer loop present';
END $p1$;

-- P2. THE SUCCESS IS ON THE RECORD. This file asserts a fix that has already
-- been demonstrated; if the demonstration is not in cron's log, do not apply it
-- on my say-so.
DO $p2$
DECLARE v_ok int; v_secs numeric;
BEGIN
  SELECT count(*), max(EXTRACT(EPOCH FROM (end_time - start_time)))
    INTO v_ok, v_secs
    FROM cron.job_run_details
   WHERE status = 'succeeded' AND start_time > now() - interval '2 hours'
     AND command ILIKE '%ottoq_retention_purge_runs%';
  IF v_ok = 0 THEN
    RAISE EXCEPTION '0295 P2: no successful run of ottoq_retention_purge_runs is on record '
                    'in the last two hours. The claim this file rests on is unproven';
  END IF;
  RAISE NOTICE '0295 P2: % successful firing(s) on record, longest % s', v_ok, round(v_secs,1);
END $p2$;

-- ---------------------------------------------------------------------------
-- THE FIX. Idempotent: the RESET was already executed live at 09:49 UTC as the
-- diagnostic that settled this, and this re-states it so the repo is the source
-- of truth rather than the database.
ALTER PROCEDURE public.ottoq_retention_purge_runs(integer, integer, interval, boolean)
  RESET statement_timeout;

-- ---------------------------------------------------------------------------
-- A1. THE PROCEDURE CARRIES NO SET CLAUSE AT ALL.
-- Not "no statement_timeout" but NO proconfig: any SET clause, on any GUC,
-- blocks transaction control, so the assertion is about the whole array.
DO $a1$
DECLARE v_config text;
BEGIN
  SELECT array_to_string(p.proconfig, ' | ') INTO v_config
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';
  IF v_config IS NOT NULL THEN
    RAISE EXCEPTION 'A1 FAILED: the procedure still carries a SET clause (%). Any SET clause '
                    'stops it committing, whatever GUC it names', v_config;
  END IF;
  RAISE NOTICE 'A1 OK: no proconfig -- the procedure may execute transaction control';
END $a1$;

-- A2. IT MATCHES THE SIBLING THAT HAS ALWAYS WORKED.
-- The control arm, asserted rather than remembered.
DO $a2$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text || ' -> ' || array_to_string(p.proconfig,','), '; ')
    INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('ottoq_retention_purge_runs','ottoq_retention_purge_worker')
     AND p.proconfig IS NOT NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'A2 FAILED: a committing purge procedure carries a SET clause: %', v_bad;
  END IF;
  RAISE NOTICE 'A2 OK: every purge procedure is free of SET clauses';
END $a2$;

-- A3. THE JOB IS STILL POINTED AT THE RIGHT THING.
DO $a3$
DECLARE v_cmd text; v_sched text; v_active boolean;
BEGIN
  SELECT command, schedule, active INTO v_cmd, v_sched, v_active FROM cron.job WHERE jobid = 625;
  IF v_cmd IS NULL THEN
    RAISE EXCEPTION 'A3 FAILED: cron job 625 has gone';
  END IF;
  IF v_cmd !~ '^\s*CALL ' OR v_cmd ~* '(^|\s)SET\s' OR v_cmd ~ ';\s*\S' THEN
    RAISE EXCEPTION 'A3 FAILED: job 625 is not a bare single-statement CALL: %', v_cmd;
  END IF;
  IF v_sched <> '0 9 * * *' OR NOT v_active THEN
    RAISE EXCEPTION 'A3 FAILED: job 625 schedule/active changed (% / %)', v_sched, v_active;
  END IF;
  RAISE NOTICE 'A3 OK: % on % , active', v_cmd, v_sched;
END $a3$;

-- A4. NO TRANSIENT PROBE JOB IS LEFT BEHIND.
-- Two were created tonight and both were unscheduled. A probe left firing every
-- minute would run the REAL retention window every minute.
DO $a4$
DECLARE v_probes text;
BEGIN
  SELECT string_agg(jobname || ' (' || schedule || ')', ', ') INTO v_probes
    FROM cron.job WHERE jobname ILIKE '%probe%' OR jobname ILIKE 'ottoq-02%';
  IF v_probes IS NOT NULL THEN
    RAISE EXCEPTION 'A4 FAILED: transient probe job(s) still scheduled: %. Given this '
                    'procedure ignores p_keep, one of those purges for real on every '
                    'firing', v_probes;
  END IF;
  RAISE NOTICE 'A4 OK: no probe jobs remain';
END $a4$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0295_a_procedure_with_a_set_clause_cannot_commit', false,
 'Removes the SET clause from public.ottoq_retention_purge_runs, the second of two independent causes that kept cron job 625 from ever running. A PostgreSQL procedure carrying a SET clause may not execute transaction control; the sibling ottoq_retention_purge_worker, which succeeds nightly, has never had one. THE SET CLAUSE WAS ADDED BY 0293 while trying to fix the first cause, so 0294 removing the cursor loop looked like a failed fix when it was really a new fault arriving. RESET was executed live at 09:49 UTC as the diagnostic that settled it and the probe succeeded at 09:50 in 62 seconds; this file re-states it idempotently so the repo is the source of truth. The timeout does not come back: it was never there before 0293, the working sibling lacks one, the successful run took 62 s under the 2-minute default, and the procedure already self-limits via p_time_budget_s in 2000-row micro-batches. ALSO RECORDS A WRONG SAFETY CLAIM: the verification probe was described in 0293, db/checks/0226 and G63 as deleting nothing because a 999-day keep window matches zero rows. The procedure reads keep_interval from ottoq_retention_policy and only falls back to p_keep when that table has no enabled row; it has one, at 48 hours, so the probe ran the real retention window and purged 20 runs. Measured afterwards: all 20 archived, none running, none production_live, youngest 2 days 3.5 h, and the three runs carrying this session G60 evidence untouched -- the intended nightly behaviour about ten hours early, with every guard holding. The rule earned: never call this procedure to test it, because no caller parameterisation makes it safe. forces_recert=false: a procedure attribute only.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
