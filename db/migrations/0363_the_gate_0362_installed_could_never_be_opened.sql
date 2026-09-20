-- migration-version: 20260920025230
-- migration-name:    the_gate_0362_installed_could_never_be_opened
--
-- 0363  0362 SHIPPED A POLICY GATE THAT CANNOT BE SET. REGISTER THE KEY.
--
-- ══ 1. THE DEFECT, WHICH IS MINE AND WAS FOUND BY TRYING TO USE IT ══════════
--
-- `0362` installed the G79 rank guard behind
-- `proposer_rank_protects_supersede`, default 0, deliberately measured-not-
-- enforced. Turning it on for run `f14d5620` raised:
--
--   23503  insert or update on table "ottoq_policy_params" violates foreign key
--          constraint "ottoq_policy_params_param_key_fkey"
--   DETAIL: Key (param_key)=(proposer_rank_protects_supersede) is not present in
--           table "ottoq_policy_param_catalog".
--
-- `ottoq_policy_params.param_key` has an FK to `ottoq_policy_param_catalog`, so a
-- policy key that is not registered **can never be set at any scope**. 0362's
-- gate was therefore permanently closed and unopenable: `ottoq_policy_get` would
-- return the default 0 forever, `NOT (false AND …)` stays `true`, and the guard
-- is dead code that reads as installed.
--
-- **That is the exact failure class this build track keeps convicting** -- G74 (a
-- rule reporting a pass for a check it never ran), G73 (a verdict whose only
-- possible word was wrong), G78 (an abstention recorded as a bad stall id), and
-- 0349 (an attestation reading "armed" while its rank-0 proposer was
-- unreachable). A mechanism that looks present and cannot act. The FK is the hero
-- here: it refused the write instead of letting the key sit in a table nothing
-- validates, which is why this was caught in minutes rather than surviving as a
-- gate someone later "turns on" with no effect.
--
-- 0362 is left applied and is not rewritten. It is correct; it was incomplete,
-- and the completion is a separate concern with its own record.
--
-- ══ 2. WHY agent_writable IS false, WHICH IS THE ONE JUDGEMENT HERE ════════
--
-- The catalog carries `agent_writable` plus agent min/max/drift columns, so some
-- keys may be moved by the Nemotron agent within bounds. This key is **not** one
-- of them, and the reason is structural rather than cautious: it governs **which
-- proposer's plan survives to be judged**. CLAUDE.md 2.5 puts the constraint set
-- on the hold-constant side -- the L1 shield defines which actions are feasible
-- and a policy chooses among them -- and `db/checks/0146` is the retraction that
-- established the same point for the A/B: swapping the policy must not swap the
-- constraint set. A key that lets an advisory agent decide whose proposals are
-- even eligible is a key that lets the agent edit the contest rather than compete
-- in it. It stays operator-set.
--
-- Bounds are 0..1 because the guard reads `>= 1`; anything above 1 would be
-- indistinguishable from 1 and inviting a reader to think there are tiers.
--
-- ══ 3. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: FALSE`. This inserts one catalog row and sets no parameter
-- anywhere, so no run's behaviour changes and no atom can move. P3 asserts that
-- no scope holds the key at >= 1 after this file runs, so "registered but still
-- off" is a checked fact. **The run where the key is first set to 1 is the run
-- that needs a fresh canon** -- that belongs to the policy write, exactly as
-- 0362 recorded.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0/P1. No certification scheduled or in flight.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0363 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0363 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0363 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. THE GATE THIS KEY OPENS MUST EXIST. Registering a key for a gate that is
-- not installed would be the mirror image of 0362's defect -- a catalog entry an
-- operator can set that nothing reads. Either half alone is inert; the pair is
-- the fix, so each asserts the other.
DO $gate$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(p.prosrc, 'proposer_rank_protects_supersede', 'g') AS m
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_submit_external_proposal';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0363 P2: ottoq_submit_external_proposal references the gate key '
                    '% time(s), expected 1 -- apply 0362 first, or this registers a '
                    'key nothing reads', v_n;
  END IF;
  RAISE NOTICE '0363 P2: 0362''s guard is present and reads this key';
END $gate$;

-- P3. Not already registered, and not already set anywhere.
DO $notyet$
DECLARE v_cat int; v_set int;
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'proposer_rank_protects_supersede';
  IF v_cat <> 0 THEN
    RAISE EXCEPTION '0363 P3: the key is already registered -- this file has already been applied';
  END IF;

  SELECT count(*) INTO v_set FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_rank_protects_supersede';
  IF v_set <> 0 THEN
    RAISE EXCEPTION '0363 P3: % policy_params row(s) already carry this key, which the '
                    'FK should have made impossible -- investigate before proceeding', v_set;
  END IF;
  RAISE NOTICE '0363 P3: key unregistered and unset, as expected';
END $notyet$;

-- ══ THE CHANGE — one catalog row ═════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('proposer_rank_protects_supersede',
        '0362/0363 (G79): 1 = ottoq_submit_external_proposal will NOT supersede a pending proposal '
        'whose source ranks STRICTLY BETTER in ottoq_proposer_precedence than the incoming one, so the '
        'better-ranked candidate stays in the pool and ottoq_l2_external_proposal''s existing rank sort '
        'decides on merit. Exists because rank governed SELECTION (that ORDER BY works) and not '
        'SUPERSESSION, and supersession moves rows out of ''pending'' -- the only status the sort can see '
        '-- so cuOpt (rank 10, a declared service-failure fallback) firing every 30-second tick removed '
        'forward_lex (rank 0, the declared primary CP-SAT proposer) from the pool before ranking '
        'happened. Measured on run f14d5620: 12 of 26 superseded forward_lex rows had a later cuopt '
        'proposal for the same entity. Equal ranks, including two proposals from the same source, still '
        'supersede on recency -- a proposer must be able to refresh its own plan or a stale plan '
        'outlives the world it was computed against (G62/G71). Unlisted sources take the 2147483647 '
        'sentinel that selection already uses. DEFAULT 0 and deliberately so: this is the supersede '
        'predicate on the assignment path, and a protected proposal that never resolves would be worse '
        'than the defect, so it is measured-not-enforced per 2.9a. NOT agent_writable: it governs whose '
        'plan is eligible to be judged, and per 2.5 / db/checks/0146 the contest is hold-constant -- an '
        'agent may compete in it, never edit it.',
        0, 0, 1,
        'ottoq_submit_external_proposal supersede predicate (0362), read via ottoq_policy_get; the '
        'ranking it defers to lives in ottoq_l2_external_proposal''s ORDER BY on '
        'ottoq_proposer_precedence.rank',
        false);

-- P4. POST-CHECK — registered, settable, and STILL OFF everywhere.
-- The settability half is the one that matters: 0362's whole defect was a gate
-- that could not be opened, so proving the FK now accepts the key is the point of
-- this file. Proven by a write that is rolled back rather than by inference.
DO $post$
DECLARE v_cat int; v_set int; v_default numeric;
BEGIN
  SELECT count(*), max(default_value) INTO v_cat, v_default
    FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'proposer_rank_protects_supersede';
  IF v_cat <> 1 THEN
    RAISE EXCEPTION '0363 P4: expected exactly 1 catalog row, found %', v_cat;
  END IF;
  IF v_default IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION '0363 P4: catalog default is % -- must be 0, the gate ships closed', v_default;
  END IF;

  --: prove the FK now accepts it, then undo. If this raises 23503 the fix did not
  --: work and the gate is still unopenable.
  BEGIN
    INSERT INTO public.ottoq_policy_params(scope_type, scope_id, param_key, param_value)
    VALUES ('global', '00000000-0000-0000-0000-000000000000', 'proposer_rank_protects_supersede', 0);
    DELETE FROM public.ottoq_policy_params
     WHERE scope_type = 'global'
       AND scope_id = '00000000-0000-0000-0000-000000000000'
       AND param_key = 'proposer_rank_protects_supersede';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '0363 P4: the key is registered but still not settable (% %) '
                    '-- the gate remains closed', SQLSTATE, SQLERRM;
  END;

  SELECT count(*) INTO v_set FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_rank_protects_supersede';
  IF v_set <> 0 THEN
    RAISE EXCEPTION '0363 P4: % row(s) left behind -- the probe did not clean up', v_set;
  END IF;

  RAISE NOTICE '0363 P4: key registered, default 0, settable (probe inserted and removed), off everywhere';
END $post$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0363_the_gate_0362_installed_could_never_be_opened', false,
  'forces_recert FALSE: inserts one ottoq_policy_param_catalog row, sets no parameter at any scope, so '
  'no run''s behaviour changes and no atom of the fourteen-atom verdict can move. P4 asserts the key is '
  'still unset everywhere after this file runs. THE RUN WHERE IT IS FIRST SET TO 1 IS THE RUN THAT NEEDS '
  'A FRESH CANON. Fixes a defect in my own 0362: ottoq_policy_params.param_key has an FK to '
  'ottoq_policy_param_catalog, so the unregistered gate key proposer_rank_protects_supersede could never '
  'be set at any scope -- ottoq_policy_get would return the default 0 forever and 0362''s G79 rank guard '
  'was dead code that read as installed. Caught within minutes by trying to enable it (23503), and the '
  'FK deserves the credit: it refused the write rather than letting the key sit somewhere nothing '
  'validates. Same failure class this track keeps convicting -- G73, G74, G78 and 0349 are all a '
  'mechanism that looks present and cannot act. 0362 is left applied and unrewritten: it was correct and '
  'incomplete, and the completion gets its own record. agent_writable is FALSE by judgement, not '
  'caution: the key governs WHICH PROPOSER''S PLAN SURVIVES TO BE JUDGED, and per 2.5 and '
  'db/checks/0146 the contest is on the hold-constant side -- an agent may compete in it, never edit it. '
  'Bounds 0..1 because the guard reads >= 1 and a wider range would imply tiers that do not exist. P2 '
  'asserts 0362''s guard is present, so neither half can ship inert without the other: a catalog row '
  'nothing reads is the mirror image of a gate nothing can open.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
