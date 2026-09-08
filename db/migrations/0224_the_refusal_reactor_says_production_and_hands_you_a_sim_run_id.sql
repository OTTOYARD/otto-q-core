-- migration-version: PENDING
-- migration-name:    the_refusal_reactor_says_production_and_hands_you_a_sim_run_id
--
-- ---------------------------------------------------------------------------
-- 0224 — 71,944 signed events assert `data_source = 'production'` while
--        carrying a sim run id. A row cannot be both. Convicted in
--        db/checks/0132.
--
-- ottoq.ottoq_react_to_refusals escalates a refused vehicle command it cannot
-- reroute, and writes the escalation like this, at BOTH call sites:
--
--     p_ingest_source:='production', p_data_source:='production',
--     p_sim_run_id:=p_sim_run_id);
--
-- Two consecutive lines, one of which says the row is production and the other
-- of which hands it a simulation run. The state-change triggers on the same
-- stream get it right and have all along:
--
--     p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END
--
-- SIZE: 71,944 rows across 494 distinct sim runs, the largest
-- production-labelled event type in this database. With 0131's 26,856 that is
-- 98,800 of the 98,834 production-labelled rows in a 2.28-million-row stream —
-- **the production half of the signed event stream is 99.97% harness.**
-- CLAUDE.md 2.8 makes data_source the one thing separating twin from real
-- telemetry in shared tables; this is that separator, inverted, under an HMAC
-- signature that attests to it.
--
-- WHY NO ATOM CAN MOVE, and it is provable rather than hoped. h_evt hashes
--
--     event_type || '|' || <entity_id, blinded for three entity types> || '|'
--                || COALESCE(sim_clock_at, '-')
--
-- over `WHERE e.sim_run_id = v_run`, ordered by the same three fields.
-- data_source appears in neither the hashed content, nor the ORDER BY, nor the
-- row-set predicate — and this migration changes nothing else. A1 asserts that
-- against the live body rather than trusting this paragraph.
--
-- WHAT THIS DELIBERATELY DOES NOT TOUCH: `p_ingest_source:='production'` on the
-- same two lines, which is equally untrue — the writer is the engine.
--
--   A CORRECTION, because the first draft of this header gave a reason that was
--   an artefact of my own sloppy regex. It said two functions BRANCH on
--   ingest_source (ottoq_emit_sdr, ottoq_trg_attribution_attach) and both are
--   on the enforced SDR path. They do not branch on it. Both merely WRITE
--   `p_ingest_source => 'kernel'`, and the pattern `ingest_source\s*(=|IN|<>)`
--   matched the `=` of the named-parameter `=>`. Tightened to
--   `\mingest_source\M\s*(=[^>]|IN|<>|!=)`, the answer is ZERO functions.
--
-- The real reason to leave it alone is better than the wrong one. ingest_source
-- has no CHECK constraint and its live vocabulary is:
--
--     trigger 1,781,838 · twin 272,761 · kernel 130,843 · production 71,944 ·
--     ottoq 15,159 · otto_q 6,804 · app 2,923 · engine 4
--
-- Eight values, including two spellings of the same word, and 'production'
-- appears there ONLY from this one function — 71,944, exactly the
-- refusal_escalated count. Choosing the right value is a vocabulary decision on
-- an unconstrained column, which is the shape of G17 (KPI-4's actor vocabulary,
-- fixed by pinning a table to the live CHECK), not a typo fix. This migration
-- does not guess at it.
--
-- data_source is the opposite case in every respect: it HAS a CHECK
-- ('production','twin','replay','shadow'), CLAUDE.md 2.8 names it as the one
-- separator between twin and real telemetry, and nothing branches on it either
-- so the change is inert downstream. See 0132 Q6.
--
-- AND WHAT IT CANNOT FIX: the 71,944 rows already written. They are signed and
-- the signature covers the mislabel. Relabelling breaks the signature; deleting
-- is a deletion from an audit ledger. Founder call, with 0131's 26,856.
-- ---------------------------------------------------------------------------

BEGIN;

-- P-. NO CERTIFICATION IS IN FLIGHT -----------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0224 P-: certification jobs are still scheduled (%) — migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0224 P-: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN RAISE EXCEPTION '0224 P-: % sim run(s) are in flight', v_runs; END IF;
  RAISE NOTICE '0224 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0224_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_react_to_refusals';

-- P0. THE BODY IS THE ONE THIS WAS WRITTEN AGAINST, WITH BOTH CALL SITES ------
DO $p0$
DECLARE v_md5 text; v_hits int; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_react_to_refusals';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0224 P0: % overloads of ottoq.ottoq_react_to_refusals, want 1', v_n;
  END IF;

  -- counted as a LITERAL, not a regex: regexp_matches would treat the anchor as
  -- a pattern, and a defect that turns on punctuation is the wrong place to
  -- introduce pattern semantics.
  SELECT left(md5(pg_get_functiondef(p.oid)),8),
         (length(pg_get_functiondef(p.oid))
          - length(replace(pg_get_functiondef(p.oid),
                           $f$p_ingest_source:='production', p_data_source:='production',$f$, '')))
         / length($f$p_ingest_source:='production', p_data_source:='production',$f$)
    INTO v_md5, v_hits
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_react_to_refusals';

  IF v_md5 IS DISTINCT FROM '4d46d5e5' THEN
    RAISE EXCEPTION '0224 P0: ottoq.ottoq_react_to_refusals is %, pinned 4d46d5e5',
                    COALESCE(v_md5,'(absent)');
  END IF;
  IF v_hits <> 2 THEN
    RAISE EXCEPTION '0224 P0: the anchor appears % times, want exactly 2 (one escalation branch '
                    'each). A rewrite that hits one and misses the other leaves half the defect '
                    'and no sign of it.', v_hits;
  END IF;
  RAISE NOTICE '0224 P0: body 4d46d5e5, anchor present exactly twice';
END $p0$;

-- P1. h_evt DOES NOT HASH data_source — the hash-neutrality claim, asserted ---
-- against the live verdict function rather than against this file's prose. If
-- someone widens h_evt to cover data_source (which would be a reasonable thing
-- to want), this migration must be re-argued, not re-run.
DO $p1$
DECLARE v_src text; v_frag text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_src IS NULL THEN RAISE EXCEPTION '0224 P1: ottoq_determinism_pair not found'; END IF;
  -- the h_evt sub-select, from its key to the start of the next atom
  v_frag := substr(v_src, position('''h_evt''' in v_src),
                   GREATEST(0, position('''h_bkg''' in v_src) - position('''h_evt''' in v_src)));
  IF v_frag = '' THEN RAISE EXCEPTION '0224 P1: could not isolate the h_evt expression'; END IF;
  IF position('data_source' in v_frag) <> 0 THEN
    RAISE EXCEPTION '0224 P1: h_evt now references data_source — this migration''s '
                    'hash-neutrality argument no longer holds:%', E'\n'||v_frag;
  END IF;
  IF position('e.sim_run_id = v_run' in v_frag) = 0 THEN
    RAISE EXCEPTION '0224 P1: h_evt no longer selects by sim_run_id; the row-set argument '
                    'no longer holds:%', E'\n'||v_frag;
  END IF;
  RAISE NOTICE '0224 P1: h_evt hashes event_type/entity/sim_clock over one run scope, and does '
               'not reference data_source';
END $p1$;

-- P2. NOTHING BRANCHES ON ottoq_events.data_source ---------------------------
-- The blast-radius check. Writers are fine; a READER would mean the change can
-- move a downstream number. 0132 Q6 found three candidates by grep and all
-- three turned out to be writes; this asserts the conclusion rather than
-- inheriting it.
DO $p2$
DECLARE v_bad text;
BEGIN
  -- scoped to functions that also mention ottoq_events. Without that scope this
  -- fires on public.ottoq_hw_vehicle_status, which does compare
  -- `data_source = 'production'` — but against ottoq_telemetry_packets, a
  -- different table this migration does not touch. A guard that cries wolf on
  -- the only run where anyone reads it is a guard that gets ignored.
  SELECT string_agg(obj, ', ' ORDER BY obj) INTO v_bad FROM (
    SELECT n.nspname||'.'||p.proname AS obj
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
       AND p.prosrc LIKE '%ottoq_events%'
       AND p.prosrc ~* '(WHERE|AND|OR)[^;]{0,80}\mdata_source\M\s*(=|IN|<>|!=)\s*'''
    UNION ALL
    -- views too: a KPI view filtering on data_source would move a SHIPPED
    -- NUMBER without moving an atom, which is the quietest way for this change
    -- to be wrong. (Measured 2026-09-08: none do.)
    SELECT n.nspname||'.'||c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE c.relkind IN ('v','m')
       AND pg_get_viewdef(c.oid) LIKE '%ottoq_events%'
       AND pg_get_viewdef(c.oid) ~* '\mdata_source\M\s*(=|IN|<>|!=)\s*'''
  ) s;
  IF v_bad IS NOT NULL THEN
    RAISE WARNING '0224 P2: these functions compare data_source against a literal — check each '
                  'before trusting the neutrality claim: %', v_bad;
  ELSE
    RAISE NOTICE '0224 P2: no function branches on a data_source literal';
  END IF;
END $p2$;

-- THE REWRITE, derived from the catalog rather than retyped. The body is 6.4 kB
-- of scheduling logic that this migration has no business restating; retyping it
-- is how an unrelated line gets changed by accident.
DO $rw$
DECLARE
  v_def text;
  v_old text := $f$p_ingest_source:='production', p_data_source:='production',$f$;
  v_new text := $f$p_ingest_source:='production', p_data_source:=CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,$f$;
  v_hits int; v_len_before int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_react_to_refusals';

  v_hits := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_hits <> 2 THEN
    RAISE EXCEPTION '0224 rewrite: anchor count changed to % between P0 and here', v_hits;
  END IF;

  v_len_before := length(v_def);
  v_def := replace(v_def, v_old, v_new);

  v_hits := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_hits <> 0 THEN
    RAISE EXCEPTION '0224 rewrite: % occurrences of the old form survive the replace', v_hits;
  END IF;
  v_hits := (length(v_def) - length(replace(v_def, v_new, ''))) / length(v_new);
  IF v_hits <> 2 THEN
    RAISE EXCEPTION '0224 rewrite: the new form appears % times, want 2', v_hits;
  END IF;
  -- the length must have moved by exactly two substitutions and no more. This
  -- is the check that catches a replace which also hit something it should not
  -- have, and it does not depend on how Postgres re-renders the body.
  IF length(v_def) - v_len_before <> 2 * (length(v_new) - length(v_old)) THEN
    RAISE EXCEPTION '0224 rewrite: length moved by %, expected % — something other than the two '
                    'substitutions changed', length(v_def) - v_len_before,
                    2 * (length(v_new) - length(v_old));
  END IF;

  EXECUTE v_def;
  RAISE NOTICE '0224: rewritten from the catalog, both call sites';
END $rw$;

-- A1. BOTH CALL SITES CARRY THE CONDITIONAL, AND NOTHING ELSE MOVED ----------
DO $a1$
DECLARE v_def text; v_cond int; v_lit int; v_pre text; v_post text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_react_to_refusals';

  v_cond := (length(v_def) - length(replace(v_def,
    $f$p_data_source:=CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END$f$, '')))
    / length($f$p_data_source:=CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END$f$);
  IF v_cond <> 2 THEN
    RAISE EXCEPTION '0224 A1: the conditional appears % times, want 2', v_cond;
  END IF;
  v_lit := (length(v_def) - length(replace(v_def, $f$p_data_source:='production'$f$, '')))
           / length($f$p_data_source:='production'$f$);
  IF v_lit <> 0 THEN
    RAISE EXCEPTION '0224 A1: % hardcoded p_data_source:=''production'' survive', v_lit;
  END IF;

  -- Nothing else moved: the pre-image with the substitution applied must equal
  -- the post-image exactly. This is the assertion that a catalog-derived rewrite
  -- can make and a retyped body cannot.
  SELECT definition INTO v_pre FROM public.ottoq_schema_snapshots
   WHERE label='0224_pre' AND object_name='ottoq_react_to_refusals'
   ORDER BY 1 DESC LIMIT 1;
  IF v_pre IS NULL THEN RAISE EXCEPTION '0224 A1: the pre-image snapshot is missing'; END IF;
  v_post := replace(v_pre,
    $f$p_ingest_source:='production', p_data_source:='production',$f$,
    $f$p_ingest_source:='production', p_data_source:=CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,$f$);
  -- compared with whitespace flattened, because pg_get_functiondef re-renders a
  -- body it did not itself produce and a difference in indentation would abort
  -- a correct migration. 0219 hit exactly that and the technique comes from its
  -- A1. Anything that is not whitespace still fires.
  IF regexp_replace(v_post, '\s+', ' ', 'g') IS DISTINCT FROM regexp_replace(v_def, '\s+', ' ', 'g') THEN
    RAISE EXCEPTION '0224 A1: the deployed body is not the pre-image with only the two '
                    'substitutions applied — something else changed';
  END IF;
  RAISE NOTICE '0224 A1: two conditionals, no hardcoded literal, and the body is the pre-image '
               'plus exactly those two substitutions';
END $a1$;

-- A2. THE EXPRESSION DOES WHAT IT CLAIMS, on both branches of its own CASE ----
-- Not a test of the function (running it would react to real refused commands
-- and write to the calendar). A test of the expression that replaced the
-- literal, which is the only thing this migration changed.
DO $a2$
DECLARE v_run uuid; v_a text; v_b text;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0224 A2: no sim run to test the expression with'; END IF;
  SELECT CASE WHEN NULL::uuid IS NULL THEN 'production' ELSE 'twin' END INTO v_a;
  SELECT CASE WHEN v_run     IS NULL THEN 'production' ELSE 'twin' END INTO v_b;
  IF v_a <> 'production' OR v_b <> 'twin' THEN
    RAISE EXCEPTION '0224 A2: the expression gives % for a null run and % for a real one', v_a, v_b;
  END IF;
  RAISE NOTICE '0224 A2: null run -> production, sim run -> twin';
END $a2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0224_the_refusal_reactor_says_production_and_hands_you_a_sim_run_id', FALSE,
        'db/checks/0132. ottoq.ottoq_react_to_refusals hardcoded p_data_source:=''production'' at '
        'both escalation call sites while passing p_sim_run_id on the next line, producing 71,944 '
        'signed events across 494 sim runs that assert production provenance and carry a '
        'simulation run id. With 0131''s 26,856 fleet-reset events, 98,800 of this database''s '
        '98,834 production-labelled rows are the certification harness — 99.97%% of the '
        '''production'' half of a 2.28M-row signed stream. Replaced with the CASE the '
        'state-change triggers already use. forces_recert FALSE is PROVEN, not predicted: P1 '
        'asserts against the live ottoq_determinism_pair that h_evt hashes event_type, entity and '
        'sim_clock_at over a sim_run_id-scoped row set and never reads data_source. '
        'p_ingest_source is deliberately left wrong: ottoq_emit_sdr and ottoq_trg_attribution_attach '
        'both branch on ingest_source and both are on the SDR path, whose h_sdr is enforced since '
        '0219 — that fix needs its own round. The rows already written are signed and stay as they '
        'are; what to do about them is a founder call.',
        now());

COMMIT;
