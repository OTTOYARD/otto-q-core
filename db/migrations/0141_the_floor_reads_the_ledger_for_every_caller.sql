-- 0141: the floor reads the ledger for every caller
--
-- 0140 gave ottoq_cert_matrix() a dependency it did not have before: the recert floor,
-- which reads supabase_migrations.schema_migrations. ottoq_cert_recert_floor() is SECURITY
-- INVOKER, and anon has no USAGE on that schema. So a call that worked before 0140 now
-- raises:
--
--   ERROR: 42501: permission denied for schema supabase_migrations
--   CONTEXT: SQL function "ottoq_cert_recert_floor" during startup
--
-- anon holds EXECUTE on ottoq_cert_matrix(timestamptz), so that is a live break, introduced
-- by me, in the same change that fixed the staleness gate. Caught by auditing the new
-- object's grants rather than by anything failing loudly.
--
-- A note on how it was nearly missed: the first probe wrapped SET LOCAL ROLE anon in a DO
-- block with an EXCEPTION handler and reported success. It was a false negative -- the role
-- change did not take effect the way the block assumed, so the query ran as postgres. The
-- second probe issued SET LOCAL ROLE anon as a plain statement and produced the error above
-- with its full context. Third time this round that the design of a probe mattered more
-- than its result (0057, 0060). A probe that reports success needs the same scrutiny as one
-- that reports a defect: ask what it would have done if the thing were broken.
--
-- Fix: the floor is an aggregate over the migration ledger -- one timestamp, no row data --
-- so it is safe to read with the owner's rights. SECURITY DEFINER with a pinned search_path
-- makes the answer the same for every caller, which is what a certification floor has to be.
--
-- While here: ottoq_cert_lineage was created without RLS, so anon could read the register.
-- Nothing sensitive is in it and anon was never granted INSERT/UPDATE/DELETE (checked:
-- anon and authenticated hold SELECT, REFERENCES, TRIGGER and nothing else, so the register
-- was never forgeable). But a new table should not add to the RLS debt 0056 recorded.
-- RLS on with no policy denies anon and authenticated; postgres and service_role bypass RLS,
-- and the floor function now reads it as owner, so the matrix keeps working for everyone.

BEGIN;

ALTER FUNCTION public.ottoq_cert_recert_floor() SECURITY DEFINER;

COMMENT ON FUNCTION public.ottoq_cert_recert_floor() IS
  'Timestamp of the most recent migration that forces determinism re-certification. '
  'A pair that ran before this cannot count toward a green column. SECURITY DEFINER: it '
  'aggregates the migration ledger to a single timestamp and must return the same answer '
  'to every caller, including roles with no rights on supabase_migrations.';

ALTER TABLE public.ottoq_cert_lineage ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.ottoq_cert_lineage IS
  'Which migrations force the determinism matrix to be re-certified. A migration absent '
  'from this table forces re-certification by default -- exemption must be claimed '
  'explicitly and justified in note. Keyed by migration name, matching '
  'supabase_migrations.schema_migrations.name. RLS on with no policy: readable only by '
  'roles that bypass RLS, and through ottoq_cert_recert_floor() which reads it as owner.';

DO $chk$
DECLARE v_secdef boolean; v_cfg text[]; v_rls boolean; v_pol int; v_floor timestamptz;
        v_writes int;
BEGIN
  SELECT p.prosecdef, p.proconfig INTO v_secdef, v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cert_recert_floor';

  IF NOT v_secdef THEN
    RAISE EXCEPTION '0141: ottoq_cert_recert_floor is not SECURITY DEFINER';
  END IF;
  -- A SECURITY DEFINER function without a pinned search_path is a privilege-escalation
  -- hazard, not a style question. Refuse to ship one.
  IF v_cfg IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(v_cfg) c WHERE c LIKE 'search\_path=%') THEN
    RAISE EXCEPTION '0141: ottoq_cert_recert_floor is SECURITY DEFINER with no pinned search_path';
  END IF;

  SELECT c.relrowsecurity INTO v_rls
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='ottoq_cert_lineage';
  IF NOT v_rls THEN
    RAISE EXCEPTION '0141: RLS is not enabled on ottoq_cert_lineage';
  END IF;

  SELECT count(*) INTO v_pol FROM pg_policies
   WHERE schemaname='public' AND tablename='ottoq_cert_lineage';
  IF v_pol <> 0 THEN
    RAISE EXCEPTION '0141: ottoq_cert_lineage gained % policy/policies; deny-all was intended', v_pol;
  END IF;

  -- The register must stay unforgeable by the public roles. If a future grant hands anon or
  -- authenticated a write, this fails rather than letting the staleness gate be edited away.
  SELECT count(*) INTO v_writes FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='ottoq_cert_lineage'
     AND grantee IN ('anon','authenticated')
     AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE');
  IF v_writes <> 0 THEN
    RAISE EXCEPTION '0141: anon/authenticated hold % write grant(s) on ottoq_cert_lineage', v_writes;
  END IF;

  v_floor := public.ottoq_cert_recert_floor();
  IF v_floor IS NULL THEN
    RAISE EXCEPTION '0141: floor went null after the change';
  END IF;
  RAISE NOTICE '0141: floor % still readable after SECURITY DEFINER + RLS.', v_floor;
END
$chk$;

COMMIT;
