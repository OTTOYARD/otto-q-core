-- lab/engine/sql/31_post_build_prod.sql
-- Runs last in build_from_prod.sh. No pg_cron job may be active in the lab, and the lab
-- database records which production export (and which repository commit) it was built from.

-- Belt and braces: the server runs with cron.launch_active_jobs = off, so no job launches
-- whatever this table says. The export's jobs are kept (code that reads cron.job by name
-- finds them) and were inserted inactive; this makes sure nothing turned one on.
UPDATE cron.job SET active = false WHERE active;

CREATE SCHEMA IF NOT EXISTS lab;
CREATE TABLE IF NOT EXISTS lab.build_info (
  built_at        timestamptz NOT NULL DEFAULT now(),
  repo_commit     text NOT NULL,
  repo_branch     text,
  baseline_cutoff text NOT NULL,
  note            text
);
ALTER TABLE lab.build_info ADD COLUMN IF NOT EXISTS source text;
ALTER TABLE lab.build_info ADD COLUMN IF NOT EXISTS export_dir text;
ALTER TABLE lab.build_info ADD COLUMN IF NOT EXISTS data_dir text;
ALTER TABLE lab.build_info ADD COLUMN IF NOT EXISTS export_manifest jsonb;

INSERT INTO lab.build_info (repo_commit, repo_branch, baseline_cutoff, note, source, export_dir, data_dir, export_manifest)
VALUES (:'repo_commit', :'repo_branch',
        'export:' || ((:'manifest')::jsonb #>> '{production,ledger_max_version}'),
        'Built by lab/engine/build_from_prod.sh from an export of production''s catalog (what ran), '
        'plus the twin depot''s reference data when a data directory is given. No run data.',
        'production_export', :'export_dir', :'data_dir', (:'manifest')::jsonb);
