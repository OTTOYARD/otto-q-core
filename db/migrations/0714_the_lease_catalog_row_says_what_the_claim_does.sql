-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    the_lease_catalog_row_says_what_the_claim_does
-- (applied by Chase in the Supabase dashboard's SQL editor, which writes no supabase_migrations row; the APPLIED footer
--  at the end of this file is the record. See task G18.)
--
-- 0714  **The lease's catalog row says what the claim does.** 0713 raised the agent claim's lease from 45 s to 130 s by
--        changing the literal inside ottoq_agent_chain_claim, because public.ottoq_policy_get never reads the catalog's
--        default_value (G429). This brings the catalog row in step: default 130, and a ceiling of 180 so a person's
--        run-scoped lease can cover a pass's worst case (about 125 s). It is its own file because it is an UPDATE, and
--        the database connector holds an UPDATE for a person's confirmation: apply it from the SQL editor, or confirm it
--        when the connector asks.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The catalog is what a person reads to learn a dial's default and range, and what ottoq_policy_set clamps a write to.
--   After 0713 it documents 45 for a lease that runs 130, and refuses a person's run-scoped 150. G429's census (db/checks
--   0440 §11): of 201 dials read with a literal, the catalog disagrees with the code on 4 (7 call sites), all masked
--   today by a global or depot row; this would be the fifth, and the only one with nothing masking it.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   The catalog row agent_chain_inflight_timeout_s: default 45 → 130, max 120 → 180, the description says why. No
--   function changes; no run's behaviour changes (the claim already runs 130 since 0713).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   Documentation and a write clamp for a dial only the agent's claim reads.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   UPDATE public.ottoq_policy_param_catalog SET default_value = 45, max_value = 120
--    WHERE param_key = 'agent_chain_inflight_timeout_s';

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0713_one_agent_pass_holds_its_claim_for_as_long_as_a_pass_can_take') THEN
    RAISE EXCEPTION '0714 P1: 0713 is not classified; apply in order';
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_agent_chain_claim(uuid,text)'::regprocedure),
            '''agent_chain_inflight_timeout_s'',130)') = 0 THEN
    RAISE EXCEPTION '0714 P1: the claim does not run 130; the catalog would document something untrue';
  END IF;
END $premises$;

UPDATE public.ottoq_policy_param_catalog
   SET default_value = 130,
       max_value     = 180,
       description   = 'Real-second lease for one in-flight agent pass per run. A later FIRE beat starts a new pass only '
                       'after the prior pass''s decision is recorded or this lease expires. 0713: 130 s, because a pass '
                       'can run about 125 s (a 90 s model budget across two models, a 30 s solver window, the board); '
                       'at 0338''s 45 s, 58 of 79 passes on run 176b2912 started while another was still running.'
 WHERE param_key = 'agent_chain_inflight_timeout_s';

DO $v$
BEGIN
  IF (SELECT default_value::int || '/' || max_value::int FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'agent_chain_inflight_timeout_s') <> '130/180' THEN
    RAISE EXCEPTION '0714 V1 FAILED: the catalog row is not as written';
  END IF;
  RAISE NOTICE '0714 V1 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0714_the_lease_catalog_row_says_what_the_claim_does', false, false,
  'G429: brings agent_chain_inflight_timeout_s''s catalog row in step with the 130 s 0713 wrote into the claim (default '
  '130, max 180). Documentation and a write clamp only: FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-24 01:24:45 UTC (8:24 PM CT on 2026-10-23), no ledger row ══════════════════════════════════════════
--
--   Chase ran this file in the Supabase dashboard's SQL editor, one of five files in one paste that
--   scripts/editor_paste.py made from the files as they stand at 8403fbc, in this order: 0603, 0714, 0738, 0749, then
--   0755 with its switch after it (the paste's md5 c77bba758ad00d7c9e3bf4f33fc292b3, 54,662 bytes, from the step page
--   "Five Ready Fixes"). The paste checked this file's text, less its BEGIN; and COMMIT; lines, at md5
--   9e38ccc4d0e62889424fda07f45756c7 before it ran it (the file then, header PENDING: md5
--   d64d0ce5b5a14221716698becb142e05); the header's version and note and this footer are the only text added since.
--   Each file was its own transaction. All five lineage rows carry 01:24:45.340543 UTC, because a transaction begun
--   inside one query message takes that message's arrival as now(). Read back between 01:27 and 01:30 UTC (8:27 and
--   8:30 PM CT; the last query's own now() 01:30:12 UTC). P1 and V1 passed ("0714 V1 PASSED"). Read back:
--   agent_chain_inflight_timeout_s catalogued default 130, max 180, with this file's description.
