-- lab/engine/sql/12_cron_standin.sql
-- A stand-in for pg_cron's schema in the lab database. Run by both build scripts after 10_supabase_shims.sql.
--
-- WHY NOT THE REAL pg_cron (changed 2026-11-04). The lab first ran real pg_cron with cron.launch_active_jobs = off.
-- Its scheduler still holds a session open in the lab database, and CREATE DATABASE ... TEMPLATE refuses a template
-- anyone is connected to ("source database "ottoq_lab" is being accessed by other users", measured 2026-11-04). The
-- lab needs that statement for its parallel replicas and its long forks (docs/FRONTIER_PLAN_2026-11-03.md, E1). So the
-- server no longer loads pg_cron at all (lib/lab_server.sh), which is also the stronger guarantee: with no scheduler
-- process, no job can run, whatever cron.job says.
--
-- WHAT IS HERE. pg_cron 1.6's two tables with their columns, defaults, keys and row-security policies (read from
-- pg_cron 1.6.8 in the lab; production's pg_cron 1.6.4 has the same columns, read 2026-11-04 through the read-only
-- endpoint), the two sequences, and SQL versions of the five functions the engine and the migrations call:
-- schedule (2 forms), unschedule (2 forms), alter_job, schedule_in_database. Each records the job as pg_cron would
-- (active included, so a migration that checks its own alter_job reads what it wrote); nothing reads the table to
-- run anything, and the post-build marks every job inactive anyway. Engine code that reads cron.job / cron.job_run_details (boards,
-- the retention purge's guard, channel health) reads production's job rows, which the export inserts.
CREATE SCHEMA IF NOT EXISTS cron;

CREATE SEQUENCE IF NOT EXISTS cron.jobid_seq;
CREATE SEQUENCE IF NOT EXISTS cron.runid_seq;

CREATE TABLE IF NOT EXISTS cron.job (
  jobid    bigint  DEFAULT nextval('cron.jobid_seq'::regclass) NOT NULL,
  schedule text    NOT NULL,
  command  text    NOT NULL,
  nodename text    DEFAULT 'localhost'::text NOT NULL,
  nodeport integer DEFAULT inet_server_port() NOT NULL,
  database text    DEFAULT current_database() NOT NULL,
  username text    DEFAULT CURRENT_USER NOT NULL,
  active   boolean DEFAULT true NOT NULL,
  jobname  text,
  CONSTRAINT job_pkey PRIMARY KEY (jobid),
  CONSTRAINT jobname_username_uniq UNIQUE (jobname, username)
);
ALTER SEQUENCE cron.jobid_seq OWNED BY cron.job.jobid;

CREATE TABLE IF NOT EXISTS cron.job_run_details (
  jobid          bigint,
  runid          bigint DEFAULT nextval('cron.runid_seq'::regclass) NOT NULL,
  job_pid        integer,
  database       text,
  username       text,
  command        text,
  status         text,
  return_message text,
  start_time     timestamp with time zone,
  end_time       timestamp with time zone,
  CONSTRAINT job_run_details_pkey PRIMARY KEY (runid)
);
ALTER SEQUENCE cron.runid_seq OWNED BY cron.job_run_details.runid;

ALTER TABLE cron.job ENABLE ROW LEVEL SECURITY;
ALTER TABLE cron.job_run_details ENABLE ROW LEVEL SECURITY;
DO $p$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'cron_job_policy') THEN
    CREATE POLICY cron_job_policy ON cron.job USING (username = CURRENT_USER);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'cron_job_run_details_policy') THEN
    CREATE POLICY cron_job_run_details_policy ON cron.job_run_details USING (username = CURRENT_USER);
  END IF;
END $p$;

-- The functions. nodeport is written explicitly: inet_server_port() is NULL on the lab's unix socket.
CREATE OR REPLACE FUNCTION cron.schedule(schedule text, command text) RETURNS bigint
LANGUAGE sql AS $f$
  INSERT INTO cron.job (schedule, command, nodeport) VALUES ($1, $2, 5432) RETURNING jobid;
$f$;

CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text) RETURNS bigint
LANGUAGE plpgsql AS $f$
DECLARE v bigint;
BEGIN
  -- pg_cron: a job with the same name and user is updated in place
  UPDATE cron.job SET schedule = $2, command = $3
   WHERE jobname = $1 AND username = CURRENT_USER RETURNING jobid INTO v;
  IF v IS NULL THEN
    INSERT INTO cron.job (jobname, schedule, command, nodeport) VALUES ($1, $2, $3, 5432)
    RETURNING jobid INTO v;
  END IF;
  RETURN v;
END $f$;

CREATE OR REPLACE FUNCTION cron.schedule_in_database(job_name text, schedule text, command text, database text,
                                                    username text DEFAULT NULL::text, active boolean DEFAULT true)
RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v bigint;
BEGIN
  UPDATE cron.job SET schedule = $2, command = $3, database = $4, active = $6
   WHERE jobname = $1 AND cron.job.username = COALESCE($5, CURRENT_USER) RETURNING jobid INTO v;
  IF v IS NULL THEN
    INSERT INTO cron.job (jobname, schedule, command, database, username, nodeport, active)
    VALUES ($1, $2, $3, $4, COALESCE($5, CURRENT_USER), 5432, $6) RETURNING jobid INTO v;
  END IF;
  RETURN v;
END $f$;

CREATE OR REPLACE FUNCTION cron.unschedule(job_id bigint) RETURNS boolean
LANGUAGE plpgsql AS $f$
BEGIN
  DELETE FROM cron.job WHERE jobid = $1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'could not find valid entry for job %', $1;  -- pg_cron's message
  END IF;
  RETURN true;
END $f$;

CREATE OR REPLACE FUNCTION cron.unschedule(job_name text) RETURNS boolean
LANGUAGE plpgsql AS $f$
BEGIN
  DELETE FROM cron.job WHERE jobname = $1 AND username = CURRENT_USER;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'could not find valid entry for job ''%''', $1;
  END IF;
  RETURN true;
END $f$;

CREATE OR REPLACE FUNCTION cron.alter_job(job_id bigint, schedule text DEFAULT NULL::text, command text DEFAULT NULL::text,
                                         database text DEFAULT NULL::text, username text DEFAULT NULL::text,
                                         active boolean DEFAULT NULL::boolean)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  -- every field as pg_cron alters it (a NULL argument leaves the field as it is)
  UPDATE cron.job j SET schedule = COALESCE($2, j.schedule), command = COALESCE($3, j.command),
                        database = COALESCE($4, j.database), username = COALESCE($5, j.username),
                        active = COALESCE($6, j.active)
   WHERE j.jobid = $1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'could not find valid entry for job %', $1;
  END IF;
END $f$;
