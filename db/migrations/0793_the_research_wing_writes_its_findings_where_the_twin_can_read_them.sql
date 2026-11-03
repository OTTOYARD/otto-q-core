-- migration-version: 20261103155140
-- migration-name:    the_research_wing_writes_its_findings_where_the_twin_can_read_them
--
-- 0793  **The research wing writes its findings where the twin can read them.**
--
-- WHY. Chase, 2026-11-03, on the frontier plan's lab: "You'll have full control for now and just feed the results into
-- a 'Research' tab in the twin?", then "Okay BEGIN". The plan (docs/FRONTIER_PLAN_2026-11-03.md, agreed the same day)
-- keeps the lab's raw data out of production and puts only its results here: "Results: a small 'research' area in the
-- otto-q-core database, plus reports in the repo." This file is that area and nothing else.
--
-- WHAT.
--   - public.ottoq_research_findings: one row per finding, keyed by a stable slug per depot. A finding is what the
--     research wing measured, built or recommends, in plain words, with its numbers (metrics), where the evidence lives
--     (a check file, a PR), the runs it read, and when its numbers were read. Re-measuring a finding updates its row
--     (the repo keeps the history: lab/research/findings/). Retracted findings stay, marked 'retracted', and the feed
--     leaves them out.
--   - public.ottoq_research_feed(p_depot): the twin's Research tab reads this, as it reads its KPI aggregate (an RPC
--     granted to anon, src/lib/ottoTwin.ts rpc()). It returns the depot's findings, newest first within each phase.
--   - Row-level security is on and the table has no policy, so anon and signed-in users cannot read or write it
--     directly; the feed (SECURITY DEFINER) is the only read path. Writes are the research wing's, as postgres.
--
-- WHAT IT DOES NOT DO. Nothing in the engine reads this table: no tick, decide path, check, grader, dial or
-- certification. It holds no run-scoped column and is not in ottoq_run_scope_registry, so ottoq_purge_prior_runs never
-- touches it (findings outlive the runs they read; the evidence they cite is in evidence-class ledgers and the repo).
-- Rule 10: a recommendation here changes nothing until a person ships it as a certified change.
--
-- LINEAGE. forces_recert FALSE, forces_dial_restart FALSE: no function, table or dial the engine or any atom reads is
-- touched.
--
-- ROLLBACK: DROP FUNCTION public.ottoq_research_feed(uuid); DROP TABLE public.ottoq_research_findings;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0793_the_research_wing_writes_its_findings_where_the_twin_can_read_them'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0793 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0793_the_research_wing_writes_its_findings_where_the_twin_can_read_them') THEN
    RAISE EXCEPTION '0793 P1: already applied';
  END IF;
  IF to_regclass('public.ottoq_research_findings') IS NOT NULL THEN
    RAISE EXCEPTION '0793 P1: public.ottoq_research_findings already exists';
  END IF;
END $premises$;

CREATE TABLE public.ottoq_research_findings (
  finding_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug        text NOT NULL CHECK (slug ~ '^[a-z0-9][a-z0-9-]{2,79}$'),
  depot_id    uuid NOT NULL DEFAULT '11111111-1111-1111-1111-111111111111',
  phase       text NOT NULL CHECK (phase ~ '^P[0-9]$'),
  item        text NOT NULL CHECK (item ~ '^(E[0-9]{1,2}|P[0-9]\.[0-9])$'),
  kind        text NOT NULL CHECK (kind IN ('measurement', 'build', 'safety', 'recommendation', 'lab')),
  status      text NOT NULL CHECK (status IN ('in_progress', 'measured', 'built', 'recommended', 'shipped',
                                              'not_verified', 'retracted')),
  title       text NOT NULL CHECK (length(title) BETWEEN 8 AND 200),
  summary     text NOT NULL CHECK (length(summary) BETWEEN 8 AND 2000),
  metrics     jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metrics) = 'object'),
  evidence    text,
  run_ids     text[] NOT NULL DEFAULT '{}',
  measured_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (depot_id, slug)
);

COMMENT ON TABLE public.ottoq_research_findings IS
  '0793: the research wing''s findings for the twin''s Research tab (read through public.ottoq_research_feed). Nothing in '
  'the engine reads it; it is not run-scoped and the demo-run purge never touches it. A recommendation here changes '
  'nothing until a person ships it as a certified change (CLAUDE.md rule 10).';

ALTER TABLE public.ottoq_research_findings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_research_findings FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.ottoq_research_feed(p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111')
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  SELECT jsonb_build_object(
    'depot_id', p_depot,
    'read_at', now(),
    'findings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'slug', f.slug, 'phase', f.phase, 'item', f.item, 'kind', f.kind, 'status', f.status,
               'title', f.title, 'summary', f.summary, 'metrics', f.metrics, 'evidence', f.evidence,
               'run_ids', to_jsonb(f.run_ids), 'measured_at', f.measured_at, 'updated_at', f.updated_at)
             ORDER BY f.phase, f.updated_at DESC, f.slug)
        FROM public.ottoq_research_findings f
       WHERE f.depot_id = p_depot AND f.status <> 'retracted'), '[]'::jsonb))
$fn$;

COMMENT ON FUNCTION public.ottoq_research_feed(uuid) IS
  '0793: the twin''s Research tab. Read-only; the only read path to public.ottoq_research_findings.';

REVOKE ALL ON FUNCTION public.ottoq_research_feed(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_research_feed(uuid) TO anon, authenticated, service_role;

-- ── V1: the feed runs and answers an empty list for a depot with no findings ──
DO $v1$
DECLARE j jsonb;
BEGIN
  j := public.ottoq_research_feed('11111111-1111-1111-1111-111111111111');
  IF jsonb_typeof(j->'findings') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION '0793 V1: the feed did not answer a findings array: %', j;
  END IF;
END $v1$;

-- ── V2: anon reaches the feed and not the table ──
DO $v2$
BEGIN
  IF NOT has_function_privilege('anon', 'public.ottoq_research_feed(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0793 V2: anon cannot execute the feed';
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_research_findings', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_research_findings', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_research_findings', 'INSERT')
     OR has_table_privilege('authenticated', 'public.ottoq_research_findings', 'INSERT') THEN
    RAISE EXCEPTION '0793 V2: anon or authenticated can reach the table directly';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0793_the_research_wing_writes_its_findings_where_the_twin_can_read_them', false, false,
        'Frontier plan Phase 0 (Chase, 2026-11-03: "Okay BEGIN"). A findings table for the research wing and a read-only '
        'feed for the twin''s Research tab, granted to anon like the KPI aggregate. Nothing in the engine reads either; '
        'the table is not run-scoped and the purge never touches it.',
        now());

COMMIT;

-- APPLIED 2026-11-03 at 15:51:40 UTC (9:51 AM CT), ledger 20261103155140, through apply_migration, with nothing in
--   flight (P0 read 0 and no run live or paused at 15:51:13 UTC). The text sent was this file before its version line
--   and this footer were set: 7,592 bytes, md5 b0ca5aa7da7b8963933e8c1005beed1a, equal to the ledger's statements[1]
--   read back. Read back at 15:51:48 UTC: the feed answers an empty findings list; anon can execute it and cannot select
--   the table; row-level security is on; the feed's prosrc md5 a0287f573a55674f4f61549572212e2a; the lineage row
--   false/false.
