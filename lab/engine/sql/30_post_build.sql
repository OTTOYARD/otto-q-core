-- lab/engine/sql/30_post_build.sql
-- Runs last. Two things: no pg_cron job may be active in the lab, and the lab
-- database records what it was built from.

-- Belt and braces: the server already runs with cron.launch_active_jobs = off,
-- so no job launches whatever this table says. Every job the baseline or a
-- migration scheduled is kept (so later code that alters a job by name finds
-- it) but marked inactive.
UPDATE cron.job SET active = false WHERE active;

CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.build_info (
  built_at        timestamptz NOT NULL DEFAULT now(),
  repo_commit     text NOT NULL,
  repo_branch     text,
  baseline_cutoff text NOT NULL,
  note            text
);
INSERT INTO lab.build_info (repo_commit, repo_branch, baseline_cutoff, note)
VALUES (:'repo_commit', :'repo_branch', :'baseline_cutoff',
        'Built by lab/engine/build_from_repo.sh from db/baseline + db/migrations. No run data, no reference data.');
