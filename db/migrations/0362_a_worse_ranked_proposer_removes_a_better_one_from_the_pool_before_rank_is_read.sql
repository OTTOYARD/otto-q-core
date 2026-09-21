-- migration-version: 20260920024530
-- migration-name:    a_worse_ranked_proposer_removes_a_better_one_from_the_pool_before_rank_is_read
--
-- 0362  RANK DECIDES WHICH PENDING PROPOSAL WINS. SUPERSESSION DECIDES WHICH
--       PROPOSALS ARE STILL PENDING, AND IT DOES NOT LOOK AT RANK.
--
-- Fixes G79, installed MEASURED-NOT-ENFORCED behind a policy key that defaults
-- to 0. At the default this file changes no behaviour at all -- which is the
-- point, because it sits on the assignment path.
--
-- ══ 1. THE HALF THAT WORKS, STATED FIRST ═══════════════════════════════════
--
-- `ottoq_l2_external_proposal` -- the function that selects which pending
-- proposal to honour -- already sorts on declared data, rank first:
--
--   ORDER BY COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp
--                       WHERE pp.source = p.source), 2147483647) ASC,
--            p.created_at DESC, ...
--
-- Rank first, unlisted sources at the maximum, recency only as a tie-break. That
-- is correct and well built, and **the first version of G79 wrongly claimed rank
-- was not enforced at all.** It is. This file does not touch that ordering.
--
-- The same correction applies to `holds_tick`, which the first draft read as
-- "outranks other proposers". It does not: 0259's own comment says *"every source
-- that declares holds_tick releases the hold"* -- it marks sources whose pending
-- proposal satisfies the right of first refusal against the LOCAL path. A
-- different axis entirely, and untouched here.
--
-- ══ 2. THE DEFECT, WHICH IS AN INTERACTION RATHER THAN A MISSING CHECK ═════
--
-- That `ORDER BY` only ever sees rows with `status = 'pending'`.
--
-- `ottoq_submit_external_proposal` supersedes unconditionally:
--
--   UPDATE public.ottoq_external_proposals
--      SET status='superseded', disposition_reason='newer_proposal_same_entity', ...
--    WHERE sim_run_id=... AND action_context=... AND entity_type=...
--      AND entity_id=... AND status='pending';
--
-- No rank term, no source term. Measured: the string `ottoq_proposer_precedence`
-- does not occur in that function (position 0), and `ottoq_decide_tick`, which
-- writes `entity_decided_by_other_proposal` at char 81,347, does not read it
-- either.
--
-- So supersession moves a proposal OUT of `pending`. When cuOpt (**rank 10**,
-- *"NVIDIA cuOpt specialist and service-failure fallback. Lower priority than
-- CP-SAT."*) submits after `forward_lex` (**rank 0**, *"Primary deterministic
-- CP-SAT assignment proposer"*), the CP-SAT proposal is **not out-ranked -- it is
-- removed from the candidate pool before ranking happens.** cuOpt fires
-- automatically every 30-second tick, so it wins on cadence against a proposer
-- the precedence table says it should lose to.
--
-- **The defect is a pool filtered by recency before a correct ranking is applied.**
--
-- Measured on run `f14d5620`, and scoped rather than inflated: of **26** superseded
-- `forward_lex` rows, **12** have a later `cuopt` proposal for the same entity --
-- consistent with displacement. The other 14 carry
-- `entity_decided_by_other_proposal` with no later cuOpt row and are **not**
-- claimed as cuOpt's doing. The source-level finding does not depend on either.
--
-- ══ 3. WHY IT IS GATED OFF, AND WHY THAT IS NOT TIMIDITY ═══════════════════
--
-- This is the supersede predicate on the **assignment path**. Getting it wrong
-- does not produce a wrong number -- it can leave a vehicle holding a pending
-- proposal that never resolves, which is worse than the defect being fixed.
--
-- The reasoning that says it is safe: a pending proposal is **not** a block. It is
-- a candidate that `ottoq_l2_external_proposal` selects by rank and the disposer
-- then enacts or refuses. A protected proposal therefore gets ACTED ON rather
-- than ignored, and starvation requires a proposal that is neither enactable nor
-- refusable -- which the disposer's predicate is built to prevent, and which
-- `0361` just widened with an abstention arm.
--
-- But that is an argument, not a measurement, and the cost of it being wrong is
-- an unserved asset. So the guard ships behind
-- **`proposer_rank_protects_supersede`, default 0**, and at that default
-- `NOT (false AND ...)` is `true`, so every row that qualified before still
-- qualifies and behaviour is byte-identical. P5 asserts the key is unset at every
-- scope so "default off" is a fact rather than a hope.
--
-- This is 2.9a's blind-spot promotion doctrine applied to a write path instead of
-- an atom: install MEASURED, turn it on for one run, watch for a vehicle whose
-- protected proposal outlives a few ticks, and only then consider it enforced.
--
-- ══ 4. THE FIX REUSES THE ORDERING THAT ALREADY WORKS ══════════════════════
--
-- Rule 5 -- verify, consolidate, extend, never rebuild. The guard does NOT decide
-- who wins; it only declines to DELETE a strictly better-ranked candidate from the
-- pool, leaving `ottoq_l2_external_proposal`'s existing rank sort to decide on
-- merit. Building a second ranking mechanism next to a working one is exactly what
-- the first, wrong version of G79 would have justified.
--
-- Strictly better only (`<`, not `<=`): equal ranks -- including two proposals
-- from the SAME source -- still supersede on recency, which is correct. A proposer
-- refreshing its own proposal must replace it, or a stale plan would outlive the
-- world it was computed against, which is G62/G71's defect.
--
-- Unlisted sources sort at 2147483647, the same sentinel
-- `ottoq_l2_external_proposal` uses, so an unregistered proposer cannot displace a
-- declared one and two unregistered proposers still supersede each other. Reusing
-- the sentinel rather than inventing one keeps the two places consistent.
--
-- ══ 5. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: FALSE`, and P5 asserts the grounds: the key is unset at run,
-- depot and global scope, so the predicate evaluates exactly as before and no
-- atom of the fourteen-atom verdict can move. **When the key is first turned on,
-- THAT run is the one that needs a fresh canon** -- the change in behaviour
-- belongs to the policy write, not to this file.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0/P1. No certification scheduled or in flight. Follows 0358/0360/0361's shape:
-- the "no sim run running" check is omitted because a demo run is not a
-- certification and the measurement behind this file needs a live run.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0362 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0362 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0362 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. The function is the one this file was written against.
DO $guard$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_submit_external_proposal';
  IF v_md5 IS NULL THEN
    RAISE EXCEPTION '0362 P2: ottoq_submit_external_proposal does not exist';
  END IF;
  IF v_md5 <> '826c002c59e428a0c80632d90d54fac3' THEN
    RAISE EXCEPTION '0362 P2: ottoq_submit_external_proposal changed under me (md5 %)', v_md5;
  END IF;
  RAISE NOTICE '0362 P2: submit function matches the definition this file was written against';
END $guard$;

-- P3. The anchor occurs exactly once, and the guard is not already installed.
-- The second half makes re-application refuse rather than insert a second copy.
DO $anchor$
DECLARE v_anchor int; v_existing int;
BEGIN
  SELECT (SELECT count(*) FROM regexp_matches(p.prosrc,
            'AND entity_type=p_entity_type AND entity_id=p_entity_id AND status=''pending''', 'g')),
         (SELECT count(*) FROM regexp_matches(p.prosrc, 'proposer_rank_protects_supersede', 'g'))
    INTO v_anchor, v_existing
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_submit_external_proposal';

  IF v_anchor <> 1 THEN
    RAISE EXCEPTION '0362 P3: supersede anchor occurs % time(s), expected 1', v_anchor;
  END IF;
  IF v_existing <> 0 THEN
    RAISE EXCEPTION '0362 P3: the guard is already present (% reference(s)) -- '
                    'this file has already been applied', v_existing;
  END IF;
  RAISE NOTICE '0362 P3: anchor unique, guard not yet present';
END $anchor$;

-- P4. THE HALF THAT WORKS MUST STILL WORK. This file's whole justification is
-- that ottoq_l2_external_proposal already ranks pending proposals, so the guard
-- only has to stop them being deleted. If that ORDER BY is ever removed, this
-- guard protects a candidate nothing will prefer, and the fix becomes a no-op
-- that looks installed -- so the dependency is asserted rather than assumed.
DO $ranks$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(p.prosrc, 'ORDER BY COALESCE\(\(SELECT pp\.rank', 'g') AS m
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_external_proposal';
  IF v_n < 1 THEN
    RAISE EXCEPTION '0362 P4: ottoq_l2_external_proposal no longer orders by '
                    'ottoq_proposer_precedence.rank -- this guard would protect a '
                    'candidate that nothing prefers';
  END IF;
  RAISE NOTICE '0362 P4: the rank-ordered selection is present (% occurrence(s))', v_n;
END $ranks$;

-- P5. THE forces_recert:FALSE GROUNDS, ASSERTED. The classification depends on
-- the gate being off everywhere, so that is checked rather than believed -- the
-- G28 defect class is a canon called green by a narrower test than the one that
-- matters.
DO $gate$
DECLARE v_set int;
BEGIN
  SELECT count(*) INTO v_set
    FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_rank_protects_supersede'
     AND param_value >= 1;
  IF v_set > 0 THEN
    RAISE EXCEPTION '0362 P5: proposer_rank_protects_supersede is already >= 1 at '
                    '% scope(s) -- this file cannot be classified forces_recert FALSE '
                    'because applying it would change behaviour immediately', v_set;
  END IF;
  RAISE NOTICE '0362 P5: gate unset at every scope, so behaviour is byte-identical at default';
END $gate$;

-- ── SNAPSHOT BEFORE REPLACING ─────────────────────────────────────────────────
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0362_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_submit_external_proposal';

-- ══ THE CHANGE ═══════════════════════════════════════════════════════════════
-- Derived from pg_get_functiondef rather than retyped, per 0360's lesson: this
-- function's real search_path is 'twin, ottoq, public, extensions' and a
-- hand-written CREATE OR REPLACE with search_path=public would have left its
-- unqualified calls unresolvable while the migration reported success.
DO $wire$
DECLARE
  v_def    text;
  v_anchor text := 'AND entity_type=p_entity_type AND entity_id=p_entity_id AND status=''pending'';';
  v_inject text;
  v_new    text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_submit_external_proposal';

  IF v_def IS NULL THEN
    RAISE EXCEPTION '0362: submit function not found at substitution time';
  END IF;
  IF position(v_anchor in v_def) = 0 THEN
    RAISE EXCEPTION '0362: supersede anchor not present in the definition';
  END IF;

  --: 0362 (G79). Do not DELETE a strictly better-ranked candidate from the pool;
  --: ottoq_l2_external_proposal's existing rank sort decides who wins. Strictly
  --: better only, so a proposer refreshing its OWN proposal still replaces it --
  --: a stale plan outliving its world is G62/G71's defect. Unlisted sources take
  --: the same 2147483647 sentinel that selection uses, so the two agree.
  --: Gated by proposer_rank_protects_supersede (default 0): at the default this
  --: reads NOT (false AND ...) = true and every row that qualified still does.
  v_inject :=
    'AND entity_type=p_entity_type AND entity_id=p_entity_id AND status=''pending''' || E'\n' ||
    '     AND NOT (' || E'\n' ||
    '           public.ottoq_policy_get(p_sim_run_id, ''proposer_rank_protects_supersede'', 0) >= 1' || E'\n' ||
    '       AND COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp' || E'\n' ||
    '                      WHERE pp.source = public.ottoq_external_proposals.source), 2147483647)' || E'\n' ||
    '         < COALESCE((SELECT pp.rank FROM public.ottoq_proposer_precedence pp' || E'\n' ||
    '                      WHERE pp.source = v_source), 2147483647));';

  v_new := replace(v_def, v_anchor, v_inject);
  IF v_new = v_def THEN
    RAISE EXCEPTION '0362: substitution produced no change';
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0362: rank guard installed on the supersede predicate, gated off by default';
END $wire$;

-- P6. POST-CHECK — installed once, and the gate reference is really there.
DO $post$
DECLARE v_guard int; v_gate int;
BEGIN
  SELECT (SELECT count(*) FROM regexp_matches(p.prosrc, 'ottoq_proposer_precedence', 'g')),
         (SELECT count(*) FROM regexp_matches(p.prosrc, 'proposer_rank_protects_supersede', 'g'))
    INTO v_guard, v_gate
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_submit_external_proposal';

  IF v_guard <> 2 THEN
    RAISE EXCEPTION '0362 P6: expected 2 precedence references (pending + incoming), found %', v_guard;
  END IF;
  IF v_gate <> 1 THEN
    RAISE EXCEPTION '0362 P6: expected exactly 1 gate reference, found %', v_gate;
  END IF;
  RAISE NOTICE '0362 P6: guard present with % precedence lookups behind % gate', v_guard, v_gate;
END $post$;

COMMENT ON FUNCTION public.ottoq_submit_external_proposal(uuid, uuid, text, text, uuid, jsonb, text, integer) IS
'Submits an external proposal, superseding any pending proposal for the same (run, action_context, entity). 0362 added a rank guard to that supersede, for G79. The defect: ottoq_l2_external_proposal already SELECTS the winning pending proposal by ottoq_proposer_precedence.rank (rank first, unlisted at 2147483647, recency only as a tie-break) -- that half works -- but this supersede was unconditional on source, and it moves rows OUT of ''pending'', which is the only status that ORDER BY can see. So a later-submitting worse-ranked proposer removed a better-ranked candidate from the pool BEFORE ranking happened: cuOpt (rank 10, declared a service-failure fallback) fires every 30-second tick and displaced forward_lex (rank 0, the declared primary CP-SAT proposer) on cadence. Measured on run f14d5620: of 26 superseded forward_lex rows, 12 had a later cuopt proposal for the same entity. The guard declines to delete a STRICTLY better-ranked pending row and lets the existing rank sort decide on merit -- it does not rank anything itself (rule 5: extend what works). Strictly better only, so a proposer refreshing its own proposal still replaces it, because a stale plan outliving its world is the G62/G71 defect. GATED by policy key proposer_rank_protects_supersede, DEFAULT 0, at which the predicate is byte-identical to before -- this sits on the assignment path and a protected proposal that never resolves would be worse than the defect, so it ships measured-not-enforced per 2.9a. The run where the key is first set to 1 is the run that needs a fresh canon.';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0362_a_worse_ranked_proposer_removes_a_better_one_from_the_pool_before_rank_is_read', false,
  'forces_recert FALSE and P5 asserts the grounds rather than assuming them: the gate key '
  'proposer_rank_protects_supersede is unset at run, depot and global scope, so NOT (false AND ...) is '
  'true, every row that qualified for supersession still qualifies, and no atom of the fourteen-atom '
  'verdict can move. THE RUN WHERE THE KEY IS FIRST SET TO 1 IS THE RUN THAT NEEDS A FRESH CANON -- the '
  'behaviour change belongs to the policy write, not to this file. Fixes G79. Rank IS enforced where '
  'pending proposals are SELECTED (ottoq_l2_external_proposal orders by pp.rank first, unlisted at '
  '2147483647, recency as tie-break) and was NOT consulted where they are SUPERSEDED '
  '(ottoq_submit_external_proposal, unconditional on source; the string ottoq_proposer_precedence did '
  'not occur in it). Because supersession moves a row out of ''pending'' -- the only status that ORDER BY '
  'sees -- a later-submitting worse-ranked proposer removed a better-ranked candidate from the pool '
  'before ranking happened. cuOpt (rank 10, declared a service-failure fallback) fires every 30-second '
  'tick and displaced forward_lex (rank 0, the declared primary) on cadence; measured on run f14d5620, '
  '12 of 26 superseded forward_lex rows had a later cuopt proposal for the same entity, and the other 14 '
  'are NOT claimed as cuOpt''s doing. THIS CORRECTS THE FIRST VERSION OF G79, which claimed rank was not '
  'enforced at all and mis-read holds_tick as meaning "outranks other proposers" -- it marks sources '
  'whose pending proposal releases the LOCAL right-of-first-refusal hold (0259). That wrong reading '
  'would have justified building a second ranking mechanism beside a working one; the guard instead only '
  'declines to delete a candidate and leaves the existing sort to judge it. Strictly better only, so a '
  'proposer refreshing its own proposal still replaces it. Blocks C5 until enabled: a CP-SAT vs cuOpt '
  'comparison run with the gate off measures submission cadence, not solver quality.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
