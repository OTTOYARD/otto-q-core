-- ============================================================================
-- 0250 — **THIS FILE'S ORIGINAL FINDING WAS WRONG IN ITS PREMISE.** THE START
--        WAS NEVER SLOW. IT WAS BLOCKED, BY ANOTHER SESSION'S JOB, ON A
--        DATABASE I WAS TREATING AS IF I WERE ITS ONLY WRITER.
-- ============================================================================
-- The original version of this file, committed at 2ed48d2, is reproduced in
-- outline below so the mistake is legible. It claimed: "starting a twin run now
-- takes over fifteen minutes; four days ago the identical call returned in
-- seconds", and attributed the lock set to the prior-run purge. Every load-
-- bearing part of that is false. What follows is what actually happened.
--
-- ── THE MISIDENTIFICATION, WHICH IS THE WHOLE ERROR ────────────────────────
-- I issued `SELECT public.ottoq_sim_run_scenario('busy_day', 771771,
-- 'claude_0330_treatment')`. The client timed out at 60 s. I then queried
-- pg_stat_activity and found TWO backends:
--
--   pid 623704  active, 833 s, no wait event
--               query: "SET statement_timeout = 0; DO $inner$ BEGIN IF NOT
--                       EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE
--                       status = ..."
--   pid 626564  active, 79 s, waiting on Lock: transactionid
--               query: "SELECT public.ottoq_sim_run_scenario('busy_day',
--                       771771, 'claude_0330_treatment')"
--
-- I read 623704 as "my first attempt, still running with statement_timeout
-- disabled" and 626564 as "my duplicate retry, queued behind it". EXACTLY
-- BACKWARDS ON THE FIRST ONE. 626564 IS my call -- its query text says so
-- verbatim. 623704 is not mine at all: I never sent `SET statement_timeout = 0`
-- and I never sent a DO block. That is a pg_cron command shape, and
-- cron.job_run_details confirms it -- jobid 727 ran 16:01:00 -> 16:17:48,
-- 1008.4 s, status FAILED, and its cron.job row has since been deleted so its
-- name reads NULL. The sibling job 728 is named `ottoq-0345-start-probe` and
-- carries the same `SET statement_timeout = 0;` + `DO $inner$` prefix.
--
-- So my run start was never slow. It sat on `Lock: transactionid` for its
-- entire life, behind a job belonging to somebody else's work. And I cancelled
-- BOTH backends: first 626564 -- my own real call, which I labelled "the
-- duplicate" -- and then 623704, which was their running job.
--
-- I CANCELLED ANOTHER SESSION'S IN-FLIGHT JOB. That is recorded here plainly
-- because it is the kind of thing that must not be discovered later from a
-- failed-job row.
--
-- ── WHY I COULD NOT SEE IT, AND THIS IS THE DURABLE PART ───────────────────
-- Migration 0345 does not exist in this branch. It does exist in the database.
-- supabase_migrations.schema_migrations shows a second stream of work applied
-- to gxdrcyphqjzjsuhxuqtg since 2026-09-16, none of it in this repo:
--
--   20260916000638  the_agent_hands_one_solver_request_to_the_kernel
--   20260916144203  every_solver_proposal_gets_a_deterministic_disposition
--   20260916194021  cp_sat_becomes_the_primary_agent_solver
--   20260919042514  the_charge_stall_was_reserved_before_any_solver_could_see_it
--   20260919154650  the_purge_cannot_complete_and_the_twin_start_door_has_no_handler
--   20260919155936  the_purge_deletes_engine_tables_alphabetically_not_by_dependency
--   20260919161259  the_cockpits_solver_join_has_never_matched_a_row
--
-- Note the two at 15:46 and 15:59. Another session had ALREADY FOUND that the
-- purge cannot complete, twenty-five minutes before I started inventing an
-- explanation for a symptom it was causing. My 0330 landed at 16:11:29,
-- between their 15:59 and their 16:12.
--
-- THE PROTOCOL FAILURE: every migration in this thread ran a "quiesce check"
-- of the form `count(*) FROM pg_stat_activity WHERE state='active' AND
-- pid <> pg_backend_pid()`, and I read 0 as "the database is quiet" and later
-- read 1 as "that is me". BOTH READINGS ASSUME I AM THE ONLY WRITER. On a
-- database with a second agent applying migrations and scheduling cron jobs,
-- a single point-in-time count of active backends does not establish quiesce;
-- it establishes that nothing was running in the instant I looked. 0328, 0329
-- and 0330 were each applied on that assumption. They are narrow, additive and
-- dial-gated, so the exposure is small -- but the assumption was unearned, and
-- it was unearned every time.
--
-- ── WHAT SURVIVES FROM THE ORIGINAL FILE ───────────────────────────────────
-- The table measurements stand AS MEASUREMENTS. They explain nothing about the
-- 1008 s, because that was a lock wait, but they are true and were taken
-- carefully, including the correction inside the original file where I first
-- wrote "massive dead-tuple bloat, autovacuum is not keeping up" and withdrew
-- it on finding pct_dead of 0.0-11.2 with autovacuum_count 213-1241:
--
--   table                    heap    total   live_tup   dead_tup  %dead
--   ottoq_decisions        2238 MB  2955 MB  2,385,592   161,248    6.3
--   ottoq_events           1225 MB  2099 MB     35,925       794    2.2
--   ottoq_comms_messages    498 MB   549 MB     22,709         0    0.0
--   ottoq_stall_bookings    398 MB  1039 MB      8,214       437    5.1
--   ottoq_rule_evaluations  317 MB  1270 MB     24,059        62    0.3
--
-- That is free-space bloat, not dead-tuple bloat, and autovacuum will never
-- return it to the filesystem. Whether it matters is now an OPEN question, not
-- a claim: the evidence I had for "it matters" was the 1008 s, and the 1008 s
-- was somebody else's job.
--
-- Also surviving, and independently useful: `SET statement_timeout = 0`
-- backends do not stop when the client gives up, and a second identical call
-- QUEUES rather than failing. Anyone retrying a timed-out engine call is
-- enqueueing a second one, not retrying the first. That was true when I wrote
-- it and is true now -- it is just that in this instance the long-running
-- backend was not mine.
-- ============================================================================

-- A. Who is actually running, and is any of it mine? Read the QUERY TEXT, not
--    the elapsed time. A `SET statement_timeout = 0` + `DO $inner$` prefix is
--    a pg_cron command, not a client call.
SELECT pid, state, wait_event_type, wait_event,
       round(extract(epoch FROM (now()-xact_start))::numeric,0) AS xact_age_s,
       left(regexp_replace(query,'\s+',' ','g'), 110) AS q
  FROM pg_stat_activity
 WHERE datname=current_database() AND pid<>pg_backend_pid() AND state='active'
 ORDER BY xact_start;

-- B. Is a cron job running right now? This is the question the quiesce check
--    never asked, and it is how 1008 s of lock wait looked like a slow start.
SELECT d.jobid, COALESCE(j.jobname,'(job row deleted)') AS jobname, d.status,
       d.start_time,
       round(extract(epoch FROM (COALESCE(d.end_time,now()) - d.start_time))::numeric,1) AS secs
  FROM cron.job_run_details d LEFT JOIN cron.job j ON j.jobid = d.jobid
 WHERE d.start_time > now() - interval '2 hours'
   AND (d.end_time IS NULL OR d.end_time > now() - interval '2 hours')
 ORDER BY d.start_time DESC LIMIT 20;

-- C. AM I THE ONLY WRITER? Compare the applied migration stream against this
--    repo. Any name here that is not a file in db/migrations/ belongs to
--    somebody else and they are working right now.
SELECT version, name
  FROM supabase_migrations.schema_migrations
 WHERE version > '20260915'
 ORDER BY version DESC LIMIT 30;
-- On 2026-09-19 this returned 14 rows that are NOT in this branch.

-- D. The table measurements, kept because they are true. Read a LOW pct_dead
--    with a LARGE heap as free-space bloat that autovacuum cannot fix; a HIGH
--    pct_dead would be a different problem. Do NOT read either as an
--    explanation for a slow call until a lock wait has been ruled out first.
SELECT relname,
       pg_size_pretty(pg_relation_size(relid)) AS heap,
       n_live_tup, n_dead_tup,
       CASE WHEN n_live_tup+n_dead_tup>0
            THEN round(100.0*n_dead_tup/(n_live_tup+n_dead_tup),1) END AS pct_dead,
       autovacuum_count
  FROM pg_stat_user_tables
 WHERE schemaname='public' AND pg_relation_size(relid) > 100*1024*1024
 ORDER BY pg_relation_size(relid) DESC;
