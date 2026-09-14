-- migration-version: 20260914214102
-- migration-name:    0327_the_ledger_comment_claims_a_protection_that_has_never_existed
-- ============================================================================
-- 0327 — THE cuOpt LEDGER'S OWN COMMENT ASSERTS A PROTECTION THAT HAS NEVER
--        EXISTED, AND IT IS THE SENTENCE A READER TRUSTS MOST.
-- ============================================================================
-- CLAUDE.md rule 6 already carries this finding (db/checks/0231) and says the
-- fix "belongs in the cuOpt cut window". This is the half of it that is pure
-- metadata and carries no behavioural risk. The reclassification half is
-- DELIBERATELY NOT HERE -- see the note at the bottom.
--
-- THE FALSE SENTENCE, live on the table today:
--
--   "Deliberately NOT named ottoq* so ottoq_purge_prior_runs cannot delete
--    prior-run evidence."
--
-- It is a naming convention relied upon to defeat a mechanism that does not
-- read names. ottoq_purge_prior_runs deletes every table registered
-- class='engine' by REGISTRY LOOKUP with dynamic SQL; the string 'cuopt' does
-- not occur in its source. Measured, and re-measured for this file at
-- 2026-09-14 20:36 UTC:
--
--   registry class for cuopt_invocation_log.sim_run_id ......... engine
--     with the note ..... "run-scoped working data; must not outlive its run"
--   n_tup_ins ................................................. 50,152
--   n_tup_del ................................................. 63,755
--   earliest surviving called_at .............................. 2026-08-02
--   sibling ottoq_cuopt_fire_log still holds firings from ..... 2026-07-18
--
-- The deletes are the proof; the missing fortnight is the independent witness.
--
-- AND THE NUMBER THE COMMENT INVITES A READER TO QUOTE MOVED AGAIN WHILE THIS
-- WINDOW WAS OPEN, in exactly the direction rule 6 warns about:
--
--                          rows      answered (http_status IS NOT NULL)
--   db/checks/0220, ~12:00 UTC      20,533                16
--   this file,       20:36 UTC      21,756                16
--
-- 1,223 more rows in an afternoon; the count of actual calls to the NVIDIA
-- endpoint did not move at all, and has not since 2026-08-30.
--
-- WHAT THE NEW COMMENT MUST DO. Not merely drop the false clause -- a comment
-- that goes quiet where it used to be wrong teaches nothing. It states the
-- grain, states that the table IS purged, and gives the reader the one sentence
-- that is safe to quote.
--
-- THE READER AUDIT rule 6 ASKS FOR, done before touching anything. Three
-- functions read this table; the predicate beside each read was inspected, not
-- inferred from whether the body mentions sim_run_id somewhere:
--
--   public.workload_harness_metrics   WHERE cl.stage='edge'
--                                       AND cl.sim_run_id = p_sim_run_id   SCOPED
--   twin.ottoq_grid_assert            WHERE sim_run_id = p_run             SCOPED
--   public.ottoq_intelligence_status  (no WHERE at all)                  UNSCOPED
--
-- The third is a real finding and is recorded in db/checks/0246. It does not
-- block this file: today it reads a purged table and under-reports, and this
-- file changes no row and no class, so its behaviour is byte-identical before
-- and after. It WOULD block the reclassification, which is why that is not here.
-- ============================================================================

DO $pre$
DECLARE
  v_comment text;
  v_class   text;
BEGIN
  -- P1  The table exists and still carries the false clause. If someone has
  --     already corrected it, this migration has nothing to do and must say so
  --     rather than overwrite a better sentence with this one.
  IF to_regclass('public.cuopt_invocation_log') IS NULL THEN
    RAISE EXCEPTION '0327 P1: public.cuopt_invocation_log not found';
  END IF;

  v_comment := obj_description('public.cuopt_invocation_log'::regclass, 'pg_class');
  IF v_comment IS NULL THEN
    RAISE EXCEPTION '0327 P1: the table carries no comment; the premise has changed';
  END IF;
  IF position('cannot delete prior-run evidence' in v_comment) = 0 THEN
    RAISE EXCEPTION '0327 P1: the false clause is already gone; refusing to overwrite. Live comment: %',
                    left(v_comment, 200);
  END IF;
  RAISE NOTICE '0327 P1: false clause present, % chars', length(v_comment);

  -- P2  The registry still classifies it engine. This file does NOT change that
  --     -- it asserts it, because the new comment says so and a comment that
  --     describes a class it no longer has is the same defect in a new coat.
  SELECT class INTO v_class
    FROM public.ottoq_run_scope_registry
   WHERE table_schema='public' AND table_name='cuopt_invocation_log'
     AND column_name='sim_run_id';
  IF v_class IS DISTINCT FROM 'engine' THEN
    RAISE EXCEPTION '0327 P2: expected registry class engine, found %; the new comment would be wrong',
                    COALESCE(v_class, '(unregistered)');
  END IF;
  RAISE NOTICE '0327 P2: registry class is engine, as the new comment states';

  -- P3  The purge really does select by class rather than by name, which is the
  --     whole basis of the correction. Assert it from the live source.
  IF to_regprocedure('public.ottoq_purge_prior_runs(uuid)') IS NULL
     AND to_regprocedure('public.ottoq_purge_prior_runs(uuid,boolean)') IS NULL THEN
    RAISE NOTICE '0327 P3: ottoq_purge_prior_runs not found under either signature; skipping the source assertion';
  ELSE
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                WHERE n.nspname='public' AND p.proname='ottoq_purge_prior_runs'
                  AND p.prosrc ~* 'cuopt') THEN
      RAISE EXCEPTION '0327 P3: ottoq_purge_prior_runs mentions cuopt; the by-class premise has changed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='ottoq_purge_prior_runs'
                      AND p.prosrc ~* 'ottoq_run_scope_registry') THEN
      RAISE EXCEPTION '0327 P3: ottoq_purge_prior_runs does not read the registry; the premise has changed';
    END IF;
    RAISE NOTICE '0327 P3: the purge selects by registry class and never by name';
  END IF;
END $pre$;

-- The old comment, preserved verbatim so this change is reversible from the
-- file alone (there is no pg_comment history to restore from):
--
--   Append-only per-invocation cuOpt supply log. Grain: one row per entry into
--   the cuOpt fire path. stage='sql_gate' rows are invocations that
--   ottoq_cuopt_refresh refused BEFORE posting (no HTTP call was made);
--   stage='edge' rows are one-per-execution of the ottoq-cuopt-propose edge
--   function. Together they make "never invoked" distinguishable from "invoked
--   N times, abstained M". http_status = the NVIDIA endpoint status (NULL means
--   NVIDIA was never reached); the function's own return status is in
--   detail->>'fn_http_status'. Deliberately NOT named ottoq* so
--   ottoq_purge_prior_runs cannot delete prior-run evidence.

COMMENT ON TABLE public.cuopt_invocation_log IS
'Per-entry cuOpt supply log. Grain: one row per entry into the cuOpt fire path. '
'stage=''sql_gate'' rows are entries that ottoq_cuopt_refresh refused BEFORE posting '
'(no HTTP call was made); stage=''edge'' rows are one-per-execution of the '
'ottoq-cuopt-propose edge function. http_status = the NVIDIA endpoint status, and '
'NULL means NVIDIA was never reached; the function''s own return status is in '
'detail->>''fn_http_status''. '
'THIS TABLE IS NOT A LIFETIME RECORD AND IS NOT APPEND-ONLY IN PRACTICE. It is '
'registered in ottoq_run_scope_registry with class=''engine'' (''run-scoped working '
'data; must not outlive its run''), and ottoq_purge_prior_runs deletes every '
'class=''engine'' table by REGISTRY LOOKUP with dynamic SQL -- never by name. An '
'earlier version of this comment claimed the opposite, that being named cuopt* '
'rather than ottoq* protected it; that was never true and is corrected here (0327, '
'from db/checks/0231). Measured 2026-09-14: n_tup_ins 50,152 against n_tup_del '
'63,755, and no surviving row older than 2026-08-02 while ottoq_cuopt_fire_log '
'still holds firings from 2026-07-18. '
'A ROW IS NOT AN INVOCATION, and the gap is three orders of magnitude: of 21,756 '
'rows on 2026-09-14, 16 carry an http_status. THE SENTENCE THAT IS SAFE TO QUOTE: '
'"Sixteen calls to the NVIDIA endpoint survive in the invocation ledger, the last '
'on 2026-08-30. The true lifetime count is at least sixteen and is not recoverable '
'from this table." That cuts BOTH ways -- ''cuOpt has barely been used'' is exactly '
'as unsupported as ''cuOpt is heavily used''.';

DO $post$
DECLARE
  v_comment text;
BEGIN
  v_comment := obj_description('public.cuopt_invocation_log'::regclass, 'pg_class');

  -- A1  The false clause is gone.
  IF position('cannot delete prior-run evidence' in v_comment) > 0 THEN
    RAISE EXCEPTION '0327 A1: the false clause survived the replacement';
  END IF;

  -- A2  It did not merely go quiet. The replacement must carry the three facts
  --     a reader needs, or this migration deleted a wrong sentence and left a
  --     hole -- which is how the original defect got written in the first place.
  IF position('class=''engine''' in v_comment) = 0 THEN
    RAISE EXCEPTION '0327 A2: the new comment does not state the registry class';
  END IF;
  IF position('A ROW IS NOT AN INVOCATION' in v_comment) = 0 THEN
    RAISE EXCEPTION '0327 A2: the new comment does not carry the row-vs-invocation warning';
  END IF;
  IF position('SAFE TO QUOTE' in v_comment) = 0 THEN
    RAISE EXCEPTION '0327 A2: the new comment does not carry the quotable sentence';
  END IF;
  RAISE NOTICE '0327 A2: replacement carries class, the row/invocation warning and the quotable sentence';

  -- A3  NOTHING ELSE MOVED. This file writes one comment. If a row, a class or
  --     a function body changed, something ran that should not have.
  IF (SELECT class FROM public.ottoq_run_scope_registry
       WHERE table_schema='public' AND table_name='cuopt_invocation_log'
         AND column_name='sim_run_id') IS DISTINCT FROM 'engine' THEN
    RAISE EXCEPTION '0327 A3: the registry class changed; this file must not change it';
  END IF;
  RAISE NOTICE '0327 A3: registry class still engine -- reclassification is deliberately NOT in this file';
END $post$;

-- ============================================================================
-- WHAT IS DELIBERATELY NOT HERE, and the number that decides it.
--
-- db/checks/0231 proposed reclassifying this table to 'evidence' so the purge
-- stops deleting it. That is the right end state and it is NOT safe to do in
-- this file, for two reasons measured rather than supposed:
--
--   1. public.ottoq_intelligence_status reads this table with NO run predicate.
--      Today that under-reports against a purged table. Reclassify first and it
--      silently becomes a lifetime row count on a growing table -- the 0145/0146
--      defect class, arriving through a fix. The reader is fixed first, or the
--      reclassification is not made.
--
--   2. GROWTH. The table took 1,223 rows in one afternoon, essentially all of
--      them stage='sql_gate' -- the gate recording that it declined to call
--      anything. Unpinned from the purge with no retention in its place, that is
--      roughly 800k rows a month of the least informative rows in the database.
--      The end state is therefore evidence-class PLUS a retention rule that ages
--      out gate rows and keeps edge rows, not reclassification alone. Note the
--      nightly ottoq_retention_purge_runs allowlist holds 7 tables and not this
--      one, so that rule has to be written, not merely pointed at.
--
-- Both belong in the cuOpt cut window with the rest of the sequence, sized with
-- these numbers in hand. This file closes the falsehood, which needed no design
-- decision at all.
-- ============================================================================

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0327_the_ledger_comment_claims_a_protection_that_has_never_existed', false,
   'COMMENT ON TABLE only. Replaces cuopt_invocation_log''s comment, which claimed that '
   'being named cuopt* rather than ottoq* stopped ottoq_purge_prior_runs deleting it. The '
   'purge selects by ottoq_run_scope_registry class with dynamic SQL and never by name, so '
   'the protection never existed: n_tup_ins 50,152 against n_tup_del 63,755, no surviving '
   'row older than 2026-08-02 while ottoq_cuopt_fire_log still holds 2026-07-18. The new '
   'comment states the class, warns that a row is not an invocation (21,756 rows, 16 with '
   'an http_status) and carries the sentence that is safe to quote. No row, class or '
   'function body is touched, so no canon can move: forces_recert false.',
   now())
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- APPLIED 2026-09-14 21:41:02 UTC as 20260914214102.
--
-- HEADER CONDENSED AT THE APPLY STEP: the explanatory header was omitted and
-- every executable line submitted verbatim. This file creates no function, so
-- nothing is stored that could drift from the text here; the COMMENT itself is
-- the artefact, and A1/A2/A3 verified it after the write.
--
-- VERIFIED AFTER APPLY:
--   false clause "cannot delete prior-run evidence" .............. GONE
--   "A ROW IS NOT AN INVOCATION" present in the new comment ...... yes
--   registry class for cuopt_invocation_log.sim_run_id ........... engine
--     (unchanged -- A3's whole point; reclassification is a later file)
--   ottoq_cert_lineage row ....................................... written
-- ============================================================================
