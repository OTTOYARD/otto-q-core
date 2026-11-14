-- migration-version: 20261114062710
-- migration-name:    0834_an_agents_directive_is_graded_against_the_brief_it_answered
--
-- 0834  **An agent's directive is graded against the wake brief it answered.** (db/checks/0492 (6)(b), G545)
--
-- ══ §1 WHY (measured 2026-11-14 06:40-07:10 UTC, 12:40-1:10 AM CT, read-only, the twin depot) ═══════════════════════════
--
--   db/checks/0492 §2 replayed a stored pass through the agent's fallback model. Its directive named every car and
--   post the brief named and paired them wrongly, and the coverage view of 0823 scored it 4 of 4. 0492 (6)(b):
--   "Nothing grades whether a directive is right."
--   The grader below, run as a session-local copy (pg_temp, nothing created) over every stored consult at the twin
--   depot whose brief lists a charge a fault cut: 154 passes on 11 runs, 560 actions (10 of them carry no text, and
--   the view leaves those out: it read 550 at the apply), 574 claims read.
--     no claim it could read       349
--     consistent with the brief    207
--     contradicted                   4    all four written by a fallback model (nvidia/nemotron-3.5-lightning-30b-a3b)
--   The four, each read against its brief: three say Waymo-AV-026's charge was cut "at SoC 48%" (passes 9796, 9809,
--   9823) where the brief has it cut at 99% and at 48% now (the car left and came home); two give a place in the
--   line the brief does not (9823: 37 against 22, the place its own earlier directive gave; 10317: 21 against 18).
--   The primary model: 0 contradictions.
--   The first draft read "Check charging again on available DCFC." as a claim that the car is charging again, 16
--   times. It is an order, not a claim. The pattern was narrowed and an instruction is not graded; that count is why
--   the function was measured before it was applied.
--
-- ══ §2 WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_agent_directive_grade(brief jsonb, directive text) -> jsonb. Pure (IMMUTABLE; it reads its two
--       arguments and no table), never raises. A claim is graded only where its subject is certain; see the body's
--       comment for the four kinds. verdict: no_claim, consistent, contradicted, or error.
--   (b) public.ottoq_agent_directive_grades: one row per directive of each consulted, answered pass whose brief lists
--       a cut charge, with the grade. security_invoker; service_role only.
--   WHAT IT IS NOT. "consistent" is not "right": the grade covers four kinds of claim about cut charges and nothing
--   else in a directive, and its truth is the brief, the engine's read at the pass's clock. It changes no lever and
--   nothing in the engine reads it (CLAUDE.md rule 10: the engine grades its own decisions read-only).
--
-- ══ §3 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 0823 is classified and the columns the view reads exist. P2 once. V1 the function is
--   IMMUTABLE, executable by service_role and by no browser role, and its body reads no table and writes nothing
--   (comment-stripped); no browser role reads the view. V2 the function on six cases inside the file: 0492's wrong
--   pairing is contradicted on the post and on "charging again"; a correct directive is consistent; an instruction
--   and a sentence naming two cars are not graded; a wrong cut percentage and a wrong place are contradicted; NULL
--   arguments return no_claim. V3 the body is the one the tests ran (md5). V4 the view reads every stored pass here
--   without an error verdict. tests/test_agent_directive_grade_sql.py runs this file on the scratch PostgreSQL.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: a new pure function and a new view; no engine function, trigger or atom reads either.
--   forces_dial_restart FALSE: no dial.
--
-- APPLIED 2026-11-14 06:27:10 UTC (12:27 AM CT), ledger 20261114062710, P0-P2 and V1-V4 passing inside the file; the
--   ledger holds this file from BEGIN to COMMIT under a three-line header. 0835 then took by_fallback_model out of the
--   view: a stored answer never carries it.
--
-- ROLLBACK: DROP VIEW public.ottoq_agent_directive_grades; DROP FUNCTION public.ottoq_agent_directive_grade(jsonb, text);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0834_an_agents_directive_is_graded_against_the_brief_it_answered'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0834 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file reads is there ──
DO $p1$
DECLARE v_missing text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last') THEN
    RAISE EXCEPTION '0834 P1: 0823 is not classified; apply in order';
  END IF;
  SELECT string_agg(w.c, ', ') INTO v_missing
    FROM (VALUES ('pass_id'), ('sim_run_id'), ('depot_id'), ('recorded_at'), ('sim_clock'), ('agent_version'),
                 ('source_kind'), ('model_answered'), ('wake'), ('answer'), ('consulted')) AS w(c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns ic
                      WHERE ic.table_schema = 'public' AND ic.table_name = 'ottoq_agent_pass_evidence'
                        AND ic.column_name = w.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0834 P1: public.ottoq_agent_pass_evidence lacks: %', v_missing;
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0834_an_agents_directive_is_graded_against_the_brief_it_answered')
     OR to_regprocedure('public.ottoq_agent_directive_grade(jsonb,text)') IS NOT NULL
     OR to_regclass('public.ottoq_agent_directive_grades') IS NOT NULL THEN
    RAISE EXCEPTION '0834 P2: already applied';
  END IF;
END $once$;

-- ── (a) the grade of one directive ──
CREATE FUNCTION public.ottoq_agent_directive_grade(p_brief jsonb, p_text text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
SET search_path = public, pg_temp
AS $fn$
/* 0834 (db/checks/0492 (6)(b)): does one directive agree with the wake brief it answered, on the cars whose charge a
   fault cut? The brief (0823) is the engine's own read at the pass's clock; the directive is a model's text. A claim
   is graded only where its subject is certain: a sentence that names exactly one car, that car one of the brief's
   cut charges, or a sentence that names no car and follows such a sentence. Four kinds of claim:
     cut_post    a sentence that says "cut" and names a post: the post is the one the brief says the charge was cut on
                 (or the one the car charges on again);
     cut_soc     the first percentage after "cut": the brief's cut_at_soc, to one point;
     again       "is / was / now / already charging again", "resumed charging", in a sentence with no negation and no
                 instruction ("Check charging again on ..." is not a claim): the brief has the car charging again;
                 and "resumed charging on <post>": that post is the brief's;
     line_pos    "position N" / "pos N": the brief's place in the line for a car still waiting.
   A car the brief lists twice (cut twice) agrees with a claim if either entry does. Everything else in the text is
   not graded: the grade says "contradicted" or "consistent" about the claims it could read, never that a directive is
   right. Pure: reads its two arguments and nothing else; never raises (an error comes back as {error}). */
DECLARE
  v_cut jsonb; v_sub jsonb;
  v_car_names text[]; v_cut_names text[]; v_post_names text[];
  v_car_re text; v_post_re text;
  v_sent text; v_low text;
  v_cars_here text[]; v_posts_here text[]; v_cut_posts text[];
  v_subject text; v_carry text;
  v_entries jsonb; v_claims integer := 0; v_sentences integer := 0;
  v_bad jsonb := '[]'::jsonb;
  v_m text[]; v_said integer; v_ok boolean; v_again_post text;
BEGIN
  IF p_text IS NULL OR btrim(p_text) = '' OR p_brief IS NULL OR jsonb_typeof(p_brief) <> 'object' THEN
    RETURN jsonb_build_object('v', 1, 'verdict', 'no_claim', 'claims', 0, 'sentences', 0, 'contradictions', '[]'::jsonb);
  END IF;
  v_sub := p_brief -> 'subjects';
  v_cut := CASE WHEN jsonb_typeof(v_sub #> '{charges_cut_by_fault,cars}') = 'array'
                THEN v_sub #> '{charges_cut_by_fault,cars}' ELSE '[]'::jsonb END;
  SELECT array_agg(DISTINCT lower(c ->> 'car')) INTO v_cut_names
    FROM jsonb_array_elements(v_cut) c WHERE COALESCE(c ->> 'car', '') <> '';
  IF v_cut_names IS NULL THEN
    RETURN jsonb_build_object('v', 1, 'verdict', 'no_claim', 'claims', 0, 'sentences', 0, 'contradictions', '[]'::jsonb);
  END IF;

  -- every car and every post the brief names, lower case; their shapes (the name with its trailing number taken off)
  -- are how a car or a post the brief does NOT name is still recognised as one in the text
  SELECT array_agg(DISTINCT lower(x)) INTO v_car_names
    FROM jsonb_path_query(v_sub, '$.**.car') AS q(j), LATERAL (SELECT q.j #>> '{}' AS x) y
   WHERE jsonb_typeof(q.j) = 'string' AND (q.j #>> '{}') ~ '[0-9]$';
  SELECT array_agg(DISTINCT lower(x)) INTO v_post_names
    FROM (SELECT q.j #>> '{}' AS x FROM jsonb_path_query(v_sub, '$.**.post') AS q(j) WHERE jsonb_typeof(q.j) = 'string'
          UNION ALL
          SELECT q.j #>> '{}' FROM jsonb_path_query(v_sub, '$.**.charging_again_on') AS q(j)
           WHERE jsonb_typeof(q.j) = 'string') z
   WHERE x ~ '[0-9]$';
  SELECT '(?:^|[^a-z0-9-])((?:' || string_agg(DISTINCT regexp_replace(regexp_replace(n, '[0-9]+$', ''),
                                                                    '([^a-z0-9])', '\\\1', 'g'), '|')
         || ')[0-9]+)(?![a-z0-9-])'
    INTO v_car_re FROM unnest(v_car_names || v_cut_names) n;
  IF v_post_names IS NOT NULL THEN
    SELECT '(?:^|[^a-z0-9-])((?:' || string_agg(DISTINCT regexp_replace(regexp_replace(n, '[0-9]+$', ''),
                                                                      '([^a-z0-9])', '\\\1', 'g'), '|')
           || ')[0-9]+)(?![a-z0-9-])'
      INTO v_post_re FROM unnest(v_post_names) n;
  END IF;

  FOR v_sent IN SELECT s FROM regexp_split_to_table(p_text, '(?<=[.!?;])\s+|\n+') AS s WHERE btrim(s) <> '' LOOP
    v_sentences := v_sentences + 1;
    v_low := lower(v_sent);
    SELECT array_agg(DISTINCT m[1]) INTO v_cars_here FROM regexp_matches(v_low, v_car_re, 'g') AS m;
    IF v_post_re IS NOT NULL THEN
      SELECT array_agg(DISTINCT m[1]) INTO v_posts_here FROM regexp_matches(v_low, v_post_re, 'g') AS m;
    ELSE
      v_posts_here := NULL;
    END IF;

    -- whose sentence this is: one car, a cut charge; or no car at all, and the sentence before had one
    IF v_cars_here IS NULL THEN
      v_subject := v_carry;
    ELSIF cardinality(v_cars_here) = 1 AND v_cars_here[1] = ANY (v_cut_names) THEN
      v_subject := v_cars_here[1];
    ELSE
      v_subject := NULL;
    END IF;
    v_carry := v_subject;
    CONTINUE WHEN v_subject IS NULL;

    SELECT jsonb_agg(c) INTO v_entries FROM jsonb_array_elements(v_cut) c WHERE lower(c ->> 'car') = v_subject;

    -- the post of a "resumed charging on <post>" phrase is a claim about where the car charges again, not about
    -- where it was cut
    v_m := regexp_match(v_low, '(?:resumed(?: charging)?|charging again|recharging)\s+(?:on|at)\s+([a-z0-9-]*[0-9])(?![a-z0-9-])');
    v_again_post := CASE WHEN v_m IS NOT NULL AND v_m[1] = ANY (COALESCE(v_posts_here, '{}'::text[])) THEN v_m[1] END;
    v_cut_posts := array_remove(v_posts_here, v_again_post);

    -- cut_post
    IF v_low ~ '\mcut\M' AND cardinality(v_cut_posts) > 0 THEN
      v_claims := v_claims + 1;
      SELECT bool_or(lower(COALESCE(c ->> 'post', '')) = ANY (v_cut_posts)
                     OR lower(COALESCE(c ->> 'charging_again_on', '')) = ANY (v_cut_posts))
        INTO v_ok FROM jsonb_array_elements(v_entries) c;
      IF NOT COALESCE(v_ok, false) THEN
        v_bad := v_bad || jsonb_build_object('car', v_subject, 'kind', 'cut_post', 'said', to_jsonb(v_cut_posts),
                   'brief', (SELECT jsonb_agg(c -> 'post') FROM jsonb_array_elements(v_entries) c));
      END IF;
    END IF;

    -- cut_soc: the first percentage after the word
    v_m := regexp_match(v_low, '\mcut\M[^%]{0,80}?([0-9]{1,3})\s*%');
    IF v_m IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_entries) c
                                    WHERE jsonb_typeof(c -> 'cut_at_soc') = 'number') THEN
      v_claims := v_claims + 1;
      v_said := v_m[1]::integer;
      SELECT bool_or(abs((c ->> 'cut_at_soc')::numeric - v_said) <= 1) INTO v_ok
        FROM jsonb_array_elements(v_entries) c WHERE jsonb_typeof(c -> 'cut_at_soc') = 'number';
      IF NOT COALESCE(v_ok, false) THEN
        v_bad := v_bad || jsonb_build_object('car', v_subject, 'kind', 'cut_soc', 'said', v_said,
                   'brief', (SELECT jsonb_agg(c -> 'cut_at_soc') FROM jsonb_array_elements(v_entries) c));
      END IF;
    END IF;

    -- again: said to be charging again, with no negation and no instruction in the sentence (measured on the stored
    -- passes before the apply: "Check charging again on available DCFC." read as a claim 16 times; it is an order)
    IF v_low ~ '(\m(is|was|now|already|has|since)\M\s+(been\s+)?(charging again|recharging|resumed)|\mresumed charging\M)'
       AND v_low !~ '(\mnot\M|n''t|\mnever\M|\myet\M|\mmust\M|\mshould\M|\mwill\M|\mwhen\M|\monce\M|\muntil\M|\mif\M|\mto resume\M|\mneeds?\M|^\s*(check|ensure|verify|confirm|monitor|watch|route|send|seat|priorit))' THEN
      v_claims := v_claims + 1;
      SELECT bool_or(COALESCE(c ->> 'charging_again_on', '') <> '') INTO v_ok FROM jsonb_array_elements(v_entries) c;
      IF NOT COALESCE(v_ok, false) THEN
        v_bad := v_bad || jsonb_build_object('car', v_subject, 'kind', 'again', 'said', 'charging again',
                   'brief', (SELECT jsonb_agg(COALESCE(c -> 'state', 'null'::jsonb)) FROM jsonb_array_elements(v_entries) c));
      ELSIF v_again_post IS NOT NULL THEN
        v_claims := v_claims + 1;
        SELECT bool_or(lower(COALESCE(c ->> 'charging_again_on', '')) = v_again_post) INTO v_ok
          FROM jsonb_array_elements(v_entries) c;
        IF NOT COALESCE(v_ok, false) THEN
          v_bad := v_bad || jsonb_build_object('car', v_subject, 'kind', 'again_post', 'said', v_again_post,
                     'brief', (SELECT jsonb_agg(c -> 'charging_again_on') FROM jsonb_array_elements(v_entries) c));
        END IF;
      END IF;
    END IF;

    -- line_pos: a place in the line, for a car the brief has waiting
    v_m := regexp_match(v_low, '\mpos(?:ition)?\.?\s*#?\s*([0-9]{1,3})(?![0-9%])');
    IF v_m IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_entries) c
                                    WHERE jsonb_typeof(c -> 'waiting_in_line_pos') = 'number') THEN
      v_claims := v_claims + 1;
      v_said := v_m[1]::integer;
      SELECT bool_or((c ->> 'waiting_in_line_pos')::numeric = v_said) INTO v_ok
        FROM jsonb_array_elements(v_entries) c WHERE jsonb_typeof(c -> 'waiting_in_line_pos') = 'number';
      IF NOT COALESCE(v_ok, false) THEN
        v_bad := v_bad || jsonb_build_object('car', v_subject, 'kind', 'line_pos', 'said', v_said,
                   'brief', (SELECT jsonb_agg(c -> 'waiting_in_line_pos') FROM jsonb_array_elements(v_entries) c));
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'v', 1,
    'verdict', CASE WHEN v_claims = 0 THEN 'no_claim' WHEN jsonb_array_length(v_bad) > 0 THEN 'contradicted'
                    ELSE 'consistent' END,
    'claims', v_claims, 'sentences', v_sentences, 'contradictions', v_bad);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('v', 1, 'verdict', 'error', 'error', SQLERRM, 'claims', 0, 'sentences', 0,
                            'contradictions', '[]'::jsonb);
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_directive_grade(jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_directive_grade(jsonb, text) TO service_role;

COMMENT ON FUNCTION public.ottoq_agent_directive_grade(jsonb, text) IS
  '0834 (G545): does one agent directive agree with the wake brief it answered, on the cars whose charge a fault cut '
  '(the post, the percentage at the cut, charging again or not, the place in the line). Graded only where the '
  'sentence''s subject is certain. verdict no_claim / consistent / contradicted / error. "consistent" is not "right": '
  'everything else in the text is not graded. IMMUTABLE, reads no table, never raises.';

-- ── (b) every stored directive that answered a brief with a cut charge, graded ──
CREATE VIEW public.ottoq_agent_directive_grades WITH (security_invoker = true) AS
SELECT e.pass_id, e.sim_run_id, e.depot_id, e.recorded_at, e.sim_clock, e.agent_version, e.source_kind,
       e.model_answered, a.ord::integer AS directive_no,
       (a.value ->> 'by_fallback_model') AS by_fallback_model,
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
  '0834 (G545): one row per directive of a consulted, answered agent pass whose wake brief lists a charge a fault cut, '
  'graded by public.ottoq_agent_directive_grade against that brief. Group by model_answered before quoting a rate, '
  'and count the distinct runs behind it (0339). A verdict covers the claims it could read, never the whole text.';

-- ── V1: who may run it, that it is pure, and who may read the view ──
DO $v1$
DECLARE v_p record;
BEGIN
  SELECT p.proacl::text AS acl, p.provolatile, p.prosecdef,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
    INTO v_p FROM pg_proc p WHERE p.oid = 'public.ottoq_agent_directive_grade(jsonb,text)'::regprocedure;
  IF v_p.acl IS NULL OR v_p.acl ~ '(^|[{,])=X' OR v_p.acl ~ '(^|[{,])(anon|authenticated)=' OR v_p.acl !~ 'service_role=X' THEN
    RAISE EXCEPTION '0834 V1 FAILED: the grade''s ACL is %', v_p.acl;
  END IF;
  IF v_p.provolatile <> 'i' OR v_p.prosecdef THEN
    RAISE EXCEPTION '0834 V1 FAILED: the grade is not IMMUTABLE, or is SECURITY DEFINER';
  END IF;
  IF v_p.src ~* '(INSERT\s+INTO|UPDATE\s+[a-z_\.]+\s+SET|DELETE\s+FROM|PERFORM\s|EXECUTE\s|\m(public|ottoq|twin)\.)' THEN
    RAISE EXCEPTION '0834 V1 FAILED: the grade''s body writes, performs, or names a schema object';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants g
              WHERE g.table_schema = 'public' AND g.table_name = 'ottoq_agent_directive_grades'
                AND g.grantee IN ('anon', 'authenticated', 'PUBLIC')) THEN
    RAISE EXCEPTION '0834 V1 FAILED: a browser role can read the grades view';
  END IF;
END $v1$;

-- ── V2: six cases ──
DO $v2$
DECLARE
  v_b jsonb := '{"subjects":{"charges_cut_by_fault":{"cars":[
      {"car":"Tesla-AV-055","post":"NASH-DCFC-STALL-28","cut_at_soc":74,"waiting_in_line_pos":1,"state":"staged_awaiting_service"},
      {"car":"Waymo-AV-004","post":"NASH-DCFC-STALL-11","cut_at_soc":99,"waiting_in_line_pos":9,"state":"arrived_at_gate"},
      {"car":"Zoox-AV-093","post":"NASH-DCFC-STALL-03","cut_at_soc":52,"charging_again_on":"NASH-DCFC-STALL-04"}]},
      "chargers_faulted":{"chargers":[{"post":"NASH-DCFC-STALL-28"}]},
      "past_contract_wait":{"longest":[{"car":"Waymo-003"}]}}}'::jsonb;
  v_g jsonb;
BEGIN
  -- db/checks/0492 (2): the fallback's wrong pairing
  v_g := public.ottoq_agent_directive_grade(v_b,
           'NASH-DCFC-STALL-28''s fault cut Waymo-AV-004 at 99% and the car is charging again.');
  IF v_g ->> 'verdict' <> 'contradicted'
     OR (SELECT array_agg(c ->> 'kind' ORDER BY c ->> 'kind') FROM jsonb_array_elements(v_g -> 'contradictions') c)
          IS DISTINCT FROM ARRAY['again', 'cut_post'] THEN
    RAISE EXCEPTION '0834 V2 FAILED (wrong pairing): %', v_g;
  END IF;
  v_g := public.ottoq_agent_directive_grade(v_b,
           'Zoox-AV-093 charge cut by fault at 52% on NASH-DCFC-STALL-03 (thermal_emergency, 6 min ago). '
           'Resumed charging on NASH-DCFC-STALL-04 after 1 min. Full target 100% still required.');
  IF v_g ->> 'verdict' <> 'consistent' OR (v_g ->> 'claims')::integer <> 4 THEN
    RAISE EXCEPTION '0834 V2 FAILED (a correct directive): %', v_g;
  END IF;
  v_g := public.ottoq_agent_directive_grade(v_b,
           'Tesla-AV-055 charge cut at 74% (target 100%), now waiting in line pos 1. Check charging again on available DCFC.');
  IF v_g ->> 'verdict' <> 'consistent' OR (v_g ->> 'claims')::integer <> 2 THEN
    RAISE EXCEPTION '0834 V2 FAILED (an instruction is not a claim): %', v_g;
  END IF;
  v_g := public.ottoq_agent_directive_grade(v_b,
           '3 findings: Tesla-AV-055 (pos 2, 31 min), Waymo-AV-004 (pos 4), Zoox-AV-093 cut at 10%.');
  IF v_g ->> 'verdict' <> 'no_claim' THEN
    RAISE EXCEPTION '0834 V2 FAILED (a sentence naming three cars): %', v_g;
  END IF;
  v_g := public.ottoq_agent_directive_grade(v_b, 'Tesla-AV-055: charge cut 151 min ago at SoC 48%. Car waiting in line at pos 37.');
  IF v_g ->> 'verdict' <> 'contradicted'
     OR (SELECT array_agg(c ->> 'kind' ORDER BY c ->> 'kind') FROM jsonb_array_elements(v_g -> 'contradictions') c)
          IS DISTINCT FROM ARRAY['cut_soc', 'line_pos'] THEN
    RAISE EXCEPTION '0834 V2 FAILED (a wrong percentage and a wrong place): %', v_g;
  END IF;
  IF public.ottoq_agent_directive_grade(NULL, 'x') ->> 'verdict' <> 'no_claim'
     OR public.ottoq_agent_directive_grade(v_b, NULL) ->> 'verdict' <> 'no_claim'
     OR public.ottoq_agent_directive_grade('[]'::jsonb, 'x') ->> 'verdict' <> 'no_claim' THEN
    RAISE EXCEPTION '0834 V2 FAILED: a missing argument is not no_claim';
  END IF;
END $v2$;

-- ── V3: the body is the one the scratch PostgreSQL ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_directive_grade(jsonb,text)'::regprocedure)
       IS DISTINCT FROM '9998f2ee1c22e1426762729e89800f61' THEN
    RAISE EXCEPTION '0834 V3 FAILED: the grade''s body is not the one the tests ran';
  END IF;
END $v3$;

-- ── V4: the view reads every stored pass here, and none comes back as an error ──
DO $v4$
DECLARE v_n bigint; v_err bigint; v_bad bigint;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE verdict = 'error' OR verdict IS NULL),
         count(*) FILTER (WHERE verdict = 'contradicted')
    INTO v_n, v_err, v_bad FROM public.ottoq_agent_directive_grades;
  IF v_err > 0 THEN RAISE EXCEPTION '0834 V4 FAILED: % of % directives graded to an error', v_err, v_n; END IF;
  RAISE NOTICE '0834 V4 PASSED: % directives graded, % contradicted, 0 errors', v_n, v_bad;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0834_an_agents_directive_is_graded_against_the_brief_it_answered', false, false,
        'G545 (db/checks/0492 (6)(b)). public.ottoq_agent_directive_grade (new, IMMUTABLE, reads no table, never '
        'raises) and the view public.ottoq_agent_directive_grades over the agent''s stored passes. No engine function, '
        'trigger or atom reads either, and there is no dial.',
        now());

COMMIT;
