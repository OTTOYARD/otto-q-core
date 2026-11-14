-- migration-version: 20261114062842
-- migration-name:    0835_the_grades_view_drops_a_mark_a_stored_answer_never_carries
--
-- 0835  **The grades view drops a column that is NULL on every row by construction.** (G545; my own correction of 0834)
--
--   0834's view carried by_fallback_model, read from each action of the stored answer. The agent's edge function
--   writes that mark on the directive it APPLIES (edge-functions/ottoq-orchestrator-agent/index.ts, the push at
--   "by_fallback_model: modelUsed"), not into the answer it stores on the pass. Read 2026-11-14 06:28 UTC, right after
--   0834's apply: 0 of the 56 directives a fallback model wrote carry it in public.ottoq_agent_directive_grades. A
--   column that is always NULL reads as "no fallback wrote this". The pass's own model_answered is the truth and is
--   already a column of the view. Found reading the view back after the apply, before anything read the column.
--
--   The view is otherwise 0834's, word for word. forces_recert FALSE, forces_dial_restart FALSE: a view no engine
--   function reads.
--
--   P0 nothing in flight. P1 0834 is applied and the view has the column. V1 the view has 0834's columns less that one,
--   the same rows as before, and no browser role reads it.
--
-- APPLIED 2026-11-14 06:28:42 UTC (12:28 AM CT), ledger 20261114062842: 550 directives and 4 contradicted, before and
--   after.
--
-- ROLLBACK: re-create the view from 0834's file.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0835 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $p1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0834_an_agents_directive_is_graded_against_the_brief_it_answered') THEN
    RAISE EXCEPTION '0835 P1: 0834 is not classified; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0835_the_grades_view_drops_a_mark_a_stored_answer_never_carries')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'ottoq_agent_directive_grades'
                       AND column_name = 'by_fallback_model') THEN
    RAISE EXCEPTION '0835 P1: already applied, or the view is not 0834''s';
  END IF;
END $p1$;

CREATE TEMP TABLE _0835_before ON COMMIT DROP AS
SELECT count(*) AS n, count(*) FILTER (WHERE verdict = 'contradicted') AS bad, COALESCE(sum(claims), 0) AS claims
  FROM public.ottoq_agent_directive_grades;

DROP VIEW public.ottoq_agent_directive_grades;

CREATE VIEW public.ottoq_agent_directive_grades WITH (security_invoker = true) AS
SELECT e.pass_id, e.sim_run_id, e.depot_id, e.recorded_at, e.sim_clock, e.agent_version, e.source_kind,
       e.model_answered, a.ord::integer AS directive_no,
       g.grade ->> 'verdict' AS verdict,
       (g.grade ->> 'claims')::integer AS claims,
       g.grade -> 'contradictions' AS contradictions,
       a.value ->> 'text' AS directive
  FROM public.ottoq_agent_pass_evidence e
  CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(e.answer -> 'actions') = 'array'
                                               THEN e.answer -> 'actions' ELSE '[]'::jsonb END)
                     WITH ORDINALITY AS a(value, ord)
  CROSS JOIN LATERAL (SELECT public.ottoq_agent_directive_grade(e.wake -> 'brief', a.value ->> 'text') AS grade) g
 WHERE e.consulted AND e.answer IS NOT NULL
   AND jsonb_typeof(e.wake #> '{brief,subjects,charges_cut_by_fault,cars}') = 'array'
   AND jsonb_array_length(e.wake #> '{brief,subjects,charges_cut_by_fault,cars}') > 0
   AND COALESCE(a.value ->> 'text', '') <> '';

REVOKE ALL ON public.ottoq_agent_directive_grades FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_agent_directive_grades TO service_role;

COMMENT ON VIEW public.ottoq_agent_directive_grades IS
  '0834, 0835 (G545): one row per directive of a consulted, answered agent pass whose wake brief lists a charge a '
  'fault cut, graded by public.ottoq_agent_directive_grade against that brief. model_answered is the model that wrote '
  'it: group by it before quoting a rate, and count the distinct runs behind it (0339). A verdict covers the claims '
  'it could read, never the whole text.';

DO $v1$
DECLARE v_cols text; v_b record; v_a record;
BEGIN
  SELECT string_agg(column_name, ',' ORDER BY ordinal_position) INTO v_cols FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'ottoq_agent_directive_grades';
  IF v_cols IS DISTINCT FROM 'pass_id,sim_run_id,depot_id,recorded_at,sim_clock,agent_version,source_kind,'
                             'model_answered,directive_no,verdict,claims,contradictions,directive' THEN
    RAISE EXCEPTION '0835 V1 FAILED: the view''s columns are %', v_cols;
  END IF;
  SELECT * INTO v_b FROM _0835_before;
  SELECT count(*) AS n, count(*) FILTER (WHERE verdict = 'contradicted') AS bad, COALESCE(sum(claims), 0) AS claims
    INTO v_a FROM public.ottoq_agent_directive_grades;
  IF v_a.n < v_b.n OR v_a.bad < v_b.bad OR v_a.claims < v_b.claims THEN
    RAISE EXCEPTION '0835 V1 FAILED: the view lost rows (% -> %)', v_b.n, v_a.n;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants g
              WHERE g.table_schema = 'public' AND g.table_name = 'ottoq_agent_directive_grades'
                AND g.grantee IN ('anon', 'authenticated', 'PUBLIC'))
     OR NOT has_table_privilege('service_role', 'public.ottoq_agent_directive_grades', 'SELECT') THEN
    RAISE EXCEPTION '0835 V1 FAILED: the view''s grants are not 0834''s';
  END IF;
  RAISE NOTICE '0835 V1 PASSED: % directives, % contradicted, before and after', v_a.n, v_a.bad;
END $v1$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0835_the_grades_view_drops_a_mark_a_stored_answer_never_carries', false, false,
        'G545. public.ottoq_agent_directive_grades re-created without by_fallback_model, which a stored answer never '
        'carries (the edge function writes it on the applied directive). A view no engine function reads.',
        now());

COMMIT;
