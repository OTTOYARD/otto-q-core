-- migration-version: 20260921012521
-- migration-name:    my_one_shot_cron_guard_read_before_it_wrote_and_started_two_runs_fourteen_seconds_apart
--
-- 0395  I GUARDED A ONE-SHOT CRON JOB WITH `IF EXISTS (SELECT ...)` AND IT **STARTED TWO DEMO RUNS
--       FOURTEEN SECONDS APART**. EVERY DEMO RUN PURGES PRIOR RUNS, SO AN UNGUARDED MINUTELY JOB
--       DESTROYS A RUN A MINUTE. THIS REPLACES THE PATTERN WITH ONE THAT CANNOT DOUBLE-FIRE.
--
-- `forces_recert` **FALSE**. A claim table and one helper function, both operator tooling. No
-- enacting path, no frame, no tick, no KPI. Safe while a run is live, and one is (`c9b0a87e`).
--
-- ══ 1. WHAT HAPPENED, MEASURED ═════════════════════════════════════════════
--
-- `ottoq_start_demo_run` exceeds the Management API's 120-second statement ceiling, so a run must
-- be started **detached**, via `cron.schedule`. I scheduled `'* * * * *'`, meaning to let it fire
-- once and unschedule itself. Receipts, verbatim:
--
--     id 1  01:23:14  sim_run_id 0c298ae6-fe07-4459-98e0-1ad27284ae54
--     id 2  01:23:28  sim_run_id c9b0a87e-0d39-4bd8-9a91-12837b2995a3
--
-- **Fourteen seconds apart, and the second purged the first.** I had added a guard between the two
-- firings — `IF EXISTS (SELECT 1 FROM receipt) THEN unschedule; RETURN; END IF;` — and it did not
-- hold, for the plainest possible reason: **the first firing's receipt row was not committed when
-- the second firing read for it.** A read-then-write claim across two transactions is not a claim.
--
-- **AND THE ASSUMPTION UNDER IT WAS MINE AND WAS WRONG.** Earlier in the same session I had
-- established, correctly, that *pg_cron does not write a `job_run_details` row until a firing
-- COMPLETES* — and I generalised that into *"pg_cron will not overlap firings of the same job"*,
-- which is a different claim and is false here. **The correct lesson is the narrow one: absence of
-- a completion record proves nothing about what is in flight.** `pg_stat_activity` is the only
-- authority for "in flight", and I wrote that down and then reasoned past it.
--
-- **The cost was one wasted run and nothing else, and only because of a discipline that had already
-- paid off twice tonight:** run `e8b8eb3e`'s five KPIs were recorded into `db/checks/0294` §6
-- BEFORE this start, precisely because `ottoq_kpi_five` reads `class='engine'` tables. Had I
-- launched first and written up after, the whole measurement would have been unrecoverable. **Cite
-- the run, not the table — and write it down before you touch the table.**
--
-- ══ 2. THE PATTERN THAT CANNOT DOUBLE-FIRE ═════════════════════════════════
--
-- The claim must be the write, not a read before it. `ottoq_run_once_claim` has the tag as its
-- PRIMARY KEY, so a second firing's `INSERT` raises `23505` **atomically**, whatever any other
-- transaction has or has not committed. There is no window, because there is no read.
--
-- Three further properties, each earned from something in this file:
--
--   - **It unschedules itself first, before doing the work.** Belt and braces: even if the body
--     raises, the job is already gone, so a failure cannot become a loop.
--   - **It records the receipt and the error in the same row**, so `err IS NOT NULL` is the only
--     thing an operator needs to read to know a start failed. `0388`'s lesson about a log whose
--     words must mean what they say.
--   - **It never swallows the claim collision into a success.** A refused second firing writes
--     nothing and returns; it does not report having started a run it did not start.
--
-- **The scratch objects from the incident are dropped here**, rather than left in `public`. Part 3
-- names ~100 scratch tables in `public` as a standing hazard; adding two more while writing the
-- file about not losing track of things would be its own small joke.

BEGIN;

-- ══ P0. PREFLIGHT ══════════════════════════════════════════════════════════
DO $p0$
BEGIN
  IF to_regprocedure('public.ottoq_start_busy_run(numeric,integer,bigint)') IS NULL THEN
    RAISE EXCEPTION '0395 P0: ottoq_start_busy_run(numeric,integer,bigint) is absent; the helper '
                    'below would have nothing to call' USING ERRCODE='42883';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE EXCEPTION '0395 P0: pg_cron is not installed' USING ERRCODE='42704';
  END IF;
END $p0$;

-- ══ P1. THE CLAIM TABLE — THE PRIMARY KEY *IS* THE MUTEX ═══════════════════
CREATE TABLE IF NOT EXISTS public.ottoq_run_once_claim (
  tag          text PRIMARY KEY,
  claimed_at   timestamptz NOT NULL DEFAULT now(),
  finished_at  timestamptz,
  receipt      jsonb,
  err          text
);

COMMENT ON TABLE public.ottoq_run_once_claim IS
  '0395. One row per detached one-shot, tag as PRIMARY KEY so the INSERT itself is the mutex. '
  'Built after a `* * * * *` cron guarded by IF EXISTS (SELECT ...) started two demo runs 14 '
  'seconds apart -- the first firing''s receipt was not committed when the second read for it, and '
  'a read-then-write claim across two transactions is not a claim. Every demo run purges prior '
  'runs, so the failure mode is destructive: one run destroyed per minute. Rows are kept after the '
  'fact deliberately: a tag that cannot be re-claimed is the point, and an operator re-running a '
  'one-shot should have to say so by deleting its row.';

-- ══ P2. THE HELPER ═════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_start_busy_run_once(
  p_tag text, p_speed numeric DEFAULT 8.0, p_days integer DEFAULT 1,
  p_seed bigint DEFAULT NULL) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE v jsonb;
BEGIN
  --: THE CLAIM IS THE WRITE. A second firing raises 23505 here and leaves without starting
  --: anything -- no read, so no window, whatever any other transaction has committed.
  INSERT INTO public.ottoq_run_once_claim(tag) VALUES (p_tag);

  --: UNSCHEDULE BEFORE THE WORK, not after: if the start raises, the job is already gone and a
  --: failure cannot become a loop. Missing job is not an error worth failing the start over.
  BEGIN
    PERFORM cron.unschedule(p_tag);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  v := public.ottoq_start_busy_run(p_speed, p_days, p_seed);
  UPDATE public.ottoq_run_once_claim
     SET receipt = v, finished_at = now(),
         err = CASE WHEN v ? 'sim_run_id' THEN NULL
                    ELSE 'start returned no sim_run_id' END
   WHERE tag = p_tag;

EXCEPTION
  WHEN unique_violation THEN
    --: ALREADY CLAIMED. Write nothing and report nothing: a refused firing must never look like
    --: a start that happened.
    RETURN;
  WHEN OTHERS THEN
    UPDATE public.ottoq_run_once_claim
       SET err = SQLSTATE || ': ' || SQLERRM, finished_at = now()
     WHERE tag = p_tag;
END $fn$;

COMMENT ON FUNCTION public.ottoq_start_busy_run_once(text,numeric,integer,bigint) IS
  '0395. Start ONE busy_day run from a detached pg_cron job, at most once per tag, ever. Usage: '
  'SELECT cron.schedule(''<tag>'', ''* * * * *'', $$SELECT public.ottoq_start_busy_run_once('
  '''<tag>'', 8.0, 1, 100020)$$); then read public.ottoq_run_once_claim for the sim_run_id or the '
  'error. Detached because ottoq_start_demo_run exceeds the Management API''s 120-second ceiling. '
  'At-most-once because it purges prior runs, so a repeat is destructive rather than merely '
  'wasteful -- and the mutex is the PRIMARY KEY insert, not a read.';

-- ══ P3. DROP THE SCRATCH FROM THE INCIDENT ═════════════════════════════════
DROP FUNCTION IF EXISTS public.g102_start_once();
DROP TABLE IF EXISTS public.g102_run_receipt;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0395_my_one_shot_cron_guard_read_before_it_wrote_and_started_two_runs_fourteen_seconds_apart',
  false,
  'Adds public.ottoq_run_once_claim (tag as PRIMARY KEY, so the INSERT is the mutex) and '
  'public.ottoq_start_busy_run_once, and drops the two scratch objects from the incident. FALSE: '
  'operator tooling only -- no enacting path, frame, tick or KPI. Built because a `* * * * *` cron '
  'guarded by IF EXISTS (SELECT 1 FROM receipt) started two demo runs 14 seconds apart '
  '(0c298ae6 at 01:23:14, c9b0a87e at 01:23:28), the second purging the first: the first firing''s '
  'row was not committed when the second read for it, so a read-then-write claim across two '
  'transactions is not a claim. The assumption underneath was my own and was wrong -- I had '
  'correctly established that pg_cron writes no job_run_details row until a firing COMPLETES, then '
  'generalised that into "pg_cron will not overlap firings of the same job", which is false. The '
  'narrow lesson: absence of a completion record proves nothing about what is in flight, and '
  'pg_stat_activity is the only authority for that. Cost was one wasted run and nothing else, '
  'because run e8b8eb3e''s five KPIs had been recorded into db/checks/0294 s6 BEFORE the start -- '
  'ottoq_kpi_five reads class=engine tables, so launching first would have made the whole '
  'measurement unrecoverable.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ══ P4. POSTFLIGHT — the mutex must actually refuse a second claim ══════════
DO $p4$
DECLARE v_refused boolean := false;
BEGIN
  INSERT INTO public.ottoq_run_once_claim(tag) VALUES ('0395_postflight_probe');
  BEGIN
    INSERT INTO public.ottoq_run_once_claim(tag) VALUES ('0395_postflight_probe');
  EXCEPTION WHEN unique_violation THEN
    v_refused := true;
  END;
  DELETE FROM public.ottoq_run_once_claim WHERE tag = '0395_postflight_probe';
  IF NOT v_refused THEN
    RAISE EXCEPTION '0395 P4: a second claim on the same tag was NOT refused; the mutex this '
                    'whole file exists for does not work' USING ERRCODE='23514';
  END IF;

  IF to_regprocedure('public.ottoq_start_busy_run_once(text,numeric,integer,bigint)') IS NULL THEN
    RAISE EXCEPTION '0395 P4: the helper did not compile' USING ERRCODE='42883';
  END IF;
  IF to_regclass('public.g102_run_receipt') IS NOT NULL THEN
    RAISE EXCEPTION '0395 P4: the incident scratch table is still in public' USING ERRCODE='23514';
  END IF;
  RAISE NOTICE '0395 P4: mutex refuses a duplicate claim; helper compiled; scratch dropped';
END $p4$;

COMMIT;
