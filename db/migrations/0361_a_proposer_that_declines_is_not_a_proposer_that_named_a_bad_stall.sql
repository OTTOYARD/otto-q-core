-- migration-version: 20260920023610
-- migration-name:    a_proposer_that_declines_is_not_a_proposer_that_named_a_bad_stall
--
-- 0361  THE DISPOSER HAS NO CONCEPT OF AN ABSTENTION, SO A PROPOSER THAT
--       CORRECTLY DECLINES IS RECORDED AS ONE THAT NAMED A MALFORMED STALL ID.
--
-- Fixes the hash-free half of G78. Found by firing CP-SAT for the first time,
-- which is the general lesson: the abstention path had never been exercised
-- because the only proposer that had ever run barely abstains.
--
-- ══ 1. WHAT WAS MEASURED ═══════════════════════════════════════════════════
--
-- The first `forward_lex` fire this engine has ever had -- fire_id 116, tick 442,
-- run `f14d5620`, twin depot (rule 8) -- submitted 16 rows, of which **11 were
-- deliberate abstentions**. Each carried `abstain: true`, no `stall_id`, and an
-- explicit rationale:
--
--   "planned to start at +111 min on l2 95fe1b50-…, beyond this tick's 30-min
--    window; re-offered when due"
--
-- That is a solver planning a horizon and offering only what is due this tick --
-- correct behaviour for the rolling re-solve CLAUDE.md 2.5 asks for, not a
-- failure. The disposer recorded one of them as
-- **`status='refused'`, `disposition_reason='invalid_stall_id'`**.
--
-- Established rather than inferred: `ottoq_dispose_external_proposals` contains
-- `invalid_stall_id` at char 1,958 and contains the string `'abstain'`
-- **zero times**. There is no abstention branch, so a row that deliberately
-- carries no stall id falls through to the malformed-stall-id arm of the
-- `disposition_reason` CASE -- the first arm that tests the stall id at all.
--
-- ══ 2. WHY THIS IS WORTH A MIGRATION RATHER THAN A SHRUG ═══════════════════
--
-- Nothing unsafe happens: an abstention is correctly not enacted, and no vehicle
-- is misplaced. The damage is to the instrument.
--
-- **The refusal tally is how proposer quality gets judged**, and it now charges a
-- proposer for declining. cuOpt largely does not abstain, so it never paid this.
-- CP-SAT abstains **11 of 16 rows by design**. So an A/B that scores refusals
-- across proposers would conclude the more careful solver is the worse one -- and
-- C5 exists precisely to run that comparison. **This must land before any
-- cross-proposer A/B or the comparison is rigged against the better solver.**
--
-- Third instance of a class this repo keeps finding: G74 (a rule reporting a PASS
-- for a check it never ran), G73 (a verdict whose only possible word was the wrong
-- one), and now this. An instrument mislabelling correct behaviour is the failure
-- mode most likely to be believed, because nothing looks broken.
--
-- ══ 3. WHY ONLY THE REASON CHANGES, WHICH IS THE DESIGN DECISION ═══════════
--
-- The obvious fix is a distinct terminal `status='abstained'`. It is deliberately
-- NOT done here, for two measured reasons.
--
--   (a) **`ottoq_hash_proposals` DIGESTS `status` AND DOES NOT DIGEST
--       `disposition_reason`** -- measured: `status` at char 477 of its source,
--       `disposition_reason` at 0. So a new status value moves the **proposals
--       atom of the fourteen-atom verdict** and forces every canon streak to
--       restart; rewording the reason costs nothing. This is exactly the split
--       G74's fix documented for `ottoq_hash_rule_evaluations`, which digests
--       `passed` and `result_payload` but not `reason`.
--
--   (b) **Two reporters enumerate outcome buckets exhaustively and would stop
--       summing.** `ottoq_agent_review` switches on
--       `empty/enacted/expired/pending/refused/superseded` and
--       `ottoq_intelligence_stack` on `enacted/expired/refused/superseded`. A new
--       status they do not know lands in none of their buckets -- which is
--       **precisely the 0341 defect**, where a view silently reported 515 of 1,676
--       rows and bucketed the other 1,161 nowhere. `ottoq_activity_feed`
--       enumerates the same four, so abstentions would also vanish from the Twin
--       decision log the UI polls every 4s.
--
-- So the split is: **the reason is fixed now, hash-free and reader-safe; the
-- status is a separate file that must teach those three reporters the new class
-- in the same change.** That ordering is the measured-before-enforced doctrine of
-- 2.9a, and doing it the other way round would trade a mislabelled refusal for an
-- uncounted one.
--
-- WHAT REMAINS HONEST ABOUT `status='refused'` AFTER THIS: the kernel did not act
-- on the row, and `refused` says that. The lie was never "refused" -- it was
-- `invalid_stall_id`, which asserts a malformed identifier where there was
-- deliberately no identifier at all. That is the part that is false, and it is the
-- part this file removes. The residual imprecision is named in G78 rather than
-- papered over.
--
-- ══ 4. THE PREDICATE, AND WHY IT IS NOT `= 'true'` ═════════════════════════
--
-- `proposal->>'abstain'` is text extracted from jsonb, so a JSON boolean `true`
-- arrives as `'true'`. But the bridge is not the only producer -- the cuOpt edge
-- function writes `abstain: false` as a JSON boolean, and a future proposer could
-- write `1` or a string. The predicate accepts `'true'`, `'t'` and `'1'` so a
-- proposer whose abstention is honestly declared is honestly recorded whichever
-- of those shapes it uses, and anything else falls through to the existing arms
-- unchanged. A fix that only recognised one spelling would leave the same defect
-- for the next proposer.
--
-- The new arm is placed FIRST in the CASE, before the stall-id regex, because an
-- abstention's defining property is that it has no stall id: any arm that tests
-- the stall id must not see it.
--
-- ══ 5. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: FALSE`, and asserted rather than asserted-by-hope: P4 below
-- proves `ottoq_hash_proposals` does not digest `disposition_reason`, so no atom
-- of the fourteen-atom verdict can move. `status` is untouched by this file.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0/P1. No certification scheduled or in flight. Follows 0358/0360's shape: the
-- "no sim run running" check is deliberately omitted, because a demo run is not a
-- certification and the measurement behind this file needs a live run.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0361 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0361 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0361 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. The disposer is the one this file was written against. 0358 and 0359 both
-- edited this function, so its md5 is recent and worth pinning tightly.
DO $guard$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_dispose_external_proposals';
  IF v_md5 IS NULL THEN
    RAISE EXCEPTION '0361 P2: ottoq_dispose_external_proposals does not exist';
  END IF;
  IF v_md5 <> 'bfd1991400f8c05560f75b015a12fb29' THEN
    RAISE EXCEPTION '0361 P2: ottoq_dispose_external_proposals changed under me '
                    '(md5 %) -- re-read it before replacing or a fix is about to '
                    'be deleted', v_md5;
  END IF;
  RAISE NOTICE '0361 P2: disposer matches the definition this file was written against';
END $guard$;

-- P3. The anchor occurs EXACTLY ONCE, and there is no abstention branch yet.
-- An anchored rewrite against an absent anchor silently does nothing; against a
-- repeated one it edits the wrong copy. Both report success and change nothing.
-- The second half also makes this file idempotent-by-refusal rather than
-- idempotent-by-accident: run twice and it stops instead of double-inserting.
DO $anchor$
DECLARE v_anchor int; v_abstain int;
BEGIN
  SELECT (SELECT count(*) FROM regexp_matches(p.prosrc, 'THEN ''invalid_stall_id''', 'g')),
         (SELECT count(*) FROM regexp_matches(p.prosrc, '''abstain''', 'g'))
    INTO v_anchor, v_abstain
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_dispose_external_proposals';

  IF v_anchor <> 1 THEN
    RAISE EXCEPTION '0361 P3: invalid_stall_id anchor occurs % time(s), expected 1', v_anchor;
  END IF;
  IF v_abstain <> 0 THEN
    RAISE EXCEPTION '0361 P3: the disposer already references ''abstain'' (% time(s)) '
                    '-- this file has already been applied, or someone else added a '
                    'branch; do not insert a second one', v_abstain;
  END IF;
  RAISE NOTICE '0361 P3: anchor unique, no abstention branch present yet';
END $anchor$;

-- P4. THE forces_recert CLAIM, ASSERTED RATHER THAN BELIEVED.
-- This file is classified forces_recert FALSE on the grounds that the proposals
-- atom cannot see disposition_reason. If that ever stops being true the
-- classification is wrong and every canon streak would be silently invalid --
-- the G28 defect class. So it is a precondition, not a comment.
DO $hash$
DECLARE v_reason int; v_status int;
BEGIN
  SELECT position('disposition_reason' in p.prosrc), position('status' in p.prosrc)
    INTO v_reason, v_status
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_hash_proposals';

  IF v_reason IS NULL THEN
    RAISE EXCEPTION '0361 P4: ottoq_hash_proposals does not exist -- the '
                    'forces_recert:FALSE classification cannot be justified';
  END IF;
  IF v_reason <> 0 THEN
    RAISE EXCEPTION '0361 P4: ottoq_hash_proposals DOES digest disposition_reason '
                    '(char %) -- this file must be reclassified forces_recert TRUE '
                    'before it is applied', v_reason;
  END IF;
  RAISE NOTICE '0361 P4: proposals atom does not digest disposition_reason '
               '(and does digest status at char %, which is why status is left alone)', v_status;
END $hash$;

-- ── SNAPSHOT BEFORE REPLACING ─────────────────────────────────────────────────
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0361_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_dispose_external_proposals';

-- ══ THE CHANGE — one new CASE arm, first, before anything reads the stall id ══
--
-- The substitution runs over pg_get_functiondef rather than prosrc, per 0360's
-- lesson: that function's real search_path is 'twin, ottoq, public, extensions'
-- and its body calls routines unqualified, so a hand-retyped CREATE OR REPLACE
-- would have silently broken it. Deriving the whole definition makes the
-- signature, search_path, volatility and security attributes impossible to get
-- wrong, because they are never retyped.
DO $wire$
DECLARE
  v_def    text;
  v_anchor text := 'WHEN COALESCE(p.proposal->>''stall_id'', '''') !~';
  v_inject text;
  v_new    text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_dispose_external_proposals';

  IF v_def IS NULL THEN
    RAISE EXCEPTION '0361: disposer not found at substitution time';
  END IF;

  IF position(v_anchor in v_def) = 0 THEN
    RAISE EXCEPTION '0361: stall_id regex anchor not present in the definition';
  END IF;

  --: 0361 (G78). FIRST arm of the reason CASE. An abstention's defining property
  --: is that it carries no stall_id, so every arm that tests the stall_id must
  --: not see it -- before this, the regex arm caught them and called a deliberate
  --: declination 'invalid_stall_id'. Accepts the three truthy spellings a jsonb
  --: producer may write, so the next proposer is recorded honestly too.
  v_inject :=
    'WHEN COALESCE(p.proposal->>''abstain'', '''') IN (''true'', ''t'', ''1'')' || E'\n' ||
    '             THEN ''proposer_abstained''' || E'\n' ||
    '           ' || v_anchor;

  v_new := replace(v_def, v_anchor, v_inject);

  IF v_new = v_def THEN
    RAISE EXCEPTION '0361: substitution produced no change';
  END IF;

  EXECUTE v_new;

  RAISE NOTICE '0361: proposer_abstained arm inserted ahead of the stall-id checks';
END $wire$;

-- P5. POST-CHECK — the arm is really there, exactly once, and ahead of the regex.
-- Order is the whole point: an abstention arm placed AFTER the stall-id test is
-- unreachable, and would look correct in a diff.
DO $post$
DECLARE v_n int; v_pos_abstain int; v_pos_regex int;
BEGIN
  SELECT (SELECT count(*) FROM regexp_matches(p.prosrc, '''proposer_abstained''', 'g')),
         position('''abstain''' in p.prosrc),
         position('invalid_stall_id' in p.prosrc)
    INTO v_n, v_pos_abstain, v_pos_regex
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_dispose_external_proposals';

  IF v_n <> 1 THEN
    RAISE EXCEPTION '0361 P5: proposer_abstained appears % time(s), expected 1', v_n;
  END IF;
  IF v_pos_abstain = 0 OR v_pos_abstain > v_pos_regex THEN
    RAISE EXCEPTION '0361 P5: the abstention arm is at % and the stall-id arm at % '
                    '-- an abstention arm after the stall-id test is unreachable',
                    v_pos_abstain, v_pos_regex;
  END IF;
  RAISE NOTICE '0361 P5: abstention arm present once, at char %, ahead of the stall-id arm at %',
               v_pos_abstain, v_pos_regex;
END $post$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0361_a_proposer_that_declines_is_not_a_proposer_that_named_a_bad_stall', false,
  'forces_recert FALSE and P4 asserts the grounds rather than assuming them: ottoq_hash_proposals '
  'digests status (char 477) and does NOT digest disposition_reason (0), so changing only the reason '
  'cannot move the proposals atom of the fourteen-atom verdict. status is untouched. Fixes the '
  'hash-free half of G78: the disposer had no abstention branch -- it contains invalid_stall_id and '
  'contained the string ''abstain'' zero times -- so a proposal deliberately carrying no stall_id fell '
  'through to the malformed-stall-id arm. Measured on the first forward_lex fire this engine ever had '
  '(fire_id 116, tick 442, run f14d5620): 16 rows submitted, 11 of them deliberate abstentions each '
  'carrying an explicit rationale ("beyond this tick''s 30-min window; re-offered when due"), and one '
  'was recorded refused/invalid_stall_id. Nothing unsafe -- but the refusal tally is how proposer '
  'quality is judged, cuOpt barely abstains and CP-SAT abstains 11 of 16 BY DESIGN, so any '
  'cross-proposer A/B scoring refusals would have concluded the more careful solver was the worse one. '
  'C5 exists to run exactly that comparison, so this had to land first. A distinct status=''abstained'' '
  'is deliberately deferred to its own file: it would move a hashed atom, and ottoq_agent_review, '
  'ottoq_intelligence_stack and ottoq_activity_feed all enumerate outcome buckets exhaustively, so a '
  'status they do not know would land in none of them -- the 0341 defect, where a view reported 515 of '
  '1,676 rows and bucketed the other 1,161 nowhere. Fixing the reason first trades nothing; fixing the '
  'status first would trade a mislabelled refusal for an uncounted one. The predicate accepts true/t/1 '
  'because jsonb producers spell booleans differently and a one-spelling fix leaves the defect for the '
  'next proposer. Third instance of the class after G74 and G73: an instrument mislabelling correct '
  'behaviour, which is the failure mode most likely to be believed.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
