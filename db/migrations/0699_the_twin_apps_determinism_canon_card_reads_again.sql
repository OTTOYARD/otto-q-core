-- migration-version: 20261010110724
-- migration-name:    the_twin_apps_determinism_canon_card_reads_again
--
-- 0699  **The twin app's determinism canon card reads again: the public key may call the one-timestamp function the
--        canon view is built on.** (G394; db/checks/0436, found 2026-10-10 reading 0658's allowlist through the public
--        API before applying it.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The twin app's useBackgroundFacts hook reads public.ottoq_determinism_canon in the browser with the public key.
--   Every such read in the 24 hours to 08:48 UTC on 2026-10-10 was refused with 401, code 42501 (4 requests from the
--   cockpit in the edge logs; the probe's own two since). The view's tables are readable through it (a view reads them
--   with its owner's rights), but "Functions called in the view are treated the same as if they had been called
--   directly from the query using the view. Therefore, the user of a view must have permissions to call all functions
--   used by the view" (PostgreSQL 17, CREATE VIEW, Notes: https://www.postgresql.org/docs/17/sql-createview.html, read
--   2026-10-10; the engine runs 17.6). The view calls public.ottoq_cert_recert_floor(), which only postgres and
--   service_role may execute.
--
--   0141 made that function SECURITY DEFINER so the public key could read the floor ("one timestamp, no row data -- so
--   it is safe to read with the owner's rights"). 0198 then took EXECUTE on every SECURITY DEFINER function in public
--   from anon and PUBLIC, and this one went with them. 0658 puts the view on the cockpit allowlist but checks the two
--   views by privilege only, which this does not touch, so it would not have seen it either.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   GRANT EXECUTE ON FUNCTION public.ottoq_cert_recert_floor() TO anon. Nothing else. The function is STABLE, writes
--   nothing and returns one timestamp, an aggregate over the migration ledger. 0198's rule, that nobody anonymous
--   changes the world, stands: this function changes nothing.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   A grant to the public key. No engine path runs as it.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   REVOKE EXECUTE ON FUNCTION public.ottoq_cert_recert_floor() FROM anon;

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0699 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE v_fn regprocedure := to_regprocedure('public.ottoq_cert_recert_floor()');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0658_the_public_key_reads_only_what_a_cockpit_shows') THEN
    RAISE EXCEPTION '0699 P1: 0658 is not classified; apply in order';
  END IF;
  IF v_fn IS NULL OR to_regclass('public.ottoq_determinism_canon') IS NULL THEN
    RAISE EXCEPTION '0699 P1: the floor function or the canon view does not exist';
  END IF;
  IF NOT (SELECT p.prosecdef AND p.provolatile = 's' FROM pg_proc p WHERE p.oid = v_fn) THEN
    RAISE EXCEPTION '0699 P1: the floor function is not a STABLE SECURITY DEFINER function; this file''s premise is wrong';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION '0699 P1: the public key may already call the floor function';
  END IF;
  IF NOT has_table_privilege('anon', 'public.ottoq_determinism_canon', 'SELECT') THEN
    RAISE EXCEPTION '0699 P1: the public key may not select the canon view (0658 lists it)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_rewrite rw ON rw.oid = d.objid
                  WHERE rw.ev_class = 'public.ottoq_determinism_canon'::regclass
                    AND d.classid = 'pg_rewrite'::regclass AND d.refclassid = 'pg_proc'::regclass AND d.refobjid = v_fn) THEN
    RAISE EXCEPTION '0699 P1: the canon view does not call the floor function';
  END IF;
END $premises$;

-- ── as the public key, in a block that rolls itself back: the canon view, the floor, and a table off the list ──
CREATE FUNCTION pg_temp.p0699_as_anon() RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('role', 'anon', true);
    DECLARE
      v_canon text; v_floor text; v_events text; v_n bigint;
    BEGIN
      BEGIN
        -- whole rows, as the cockpit asks for them (select=*): count(*) alone never calls the function a column is
        -- built on, so it would read even while the cockpit is refused
        SELECT count(to_jsonb(c)) INTO v_n FROM public.ottoq_determinism_canon c;
        v_canon := 'read ' || v_n;
      EXCEPTION WHEN insufficient_privilege THEN v_canon := 'refused';
      END;
      BEGIN
        v_floor := CASE WHEN public.ottoq_cert_recert_floor() IS NOT NULL THEN 'read' ELSE 'null' END;
      EXCEPTION WHEN insufficient_privilege THEN v_floor := 'refused';
      END;
      -- the control: a table 0658 took from the public key must still refuse, or the role switch did not happen
      BEGIN
        PERFORM 1 FROM public.ottoq_events LIMIT 1;
        v_events := 'read';
      EXCEPTION WHEN insufficient_privilege THEN v_events := 'refused';
      END;
      RAISE EXCEPTION 'AS ANON|canon %|floor %|events %', v_canon, v_floor, v_events;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

-- ── P2: the defect, as the public key: the canon view and the floor are refused, and so is the control ──
DO $p2$
DECLARE v text := pg_temp.p0699_as_anon();
BEGIN
  IF v IS DISTINCT FROM 'AS ANON|canon refused|floor refused|events refused' THEN
    RAISE EXCEPTION '0699 P2: as the public key the canon was not refused as this file expects: %', v;
  END IF;
END $p2$;

GRANT EXECUTE ON FUNCTION public.ottoq_cert_recert_floor() TO anon;

-- ── V1: as the public key: the canon view reads, the floor answers, the control still refuses ──
DO $v1$
DECLARE v text := pg_temp.p0699_as_anon();
BEGIN
  IF v !~ '^AS ANON\|canon read [0-9]+\|floor read\|events refused$' THEN
    RAISE EXCEPTION '0699 V1 FAILED: as the public key: %', v;
  END IF;
  RAISE NOTICE '0699 V1 PASSED: as the public key: %; rolled back', v;
END $v1$;

-- ── V2: the grant as written: the public key alone, not PUBLIC ──
DO $v2$
DECLARE v_acl text := (SELECT proacl::text FROM pg_proc WHERE oid = 'public.ottoq_cert_recert_floor()'::regprocedure);
BEGIN
  IF NOT has_function_privilege('anon', 'public.ottoq_cert_recert_floor()', 'EXECUTE')
     OR v_acl ~ '(^|[{,])=X/' THEN
    RAISE EXCEPTION '0699 V2 FAILED: the floor function''s grants are not as written: %', v_acl;
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0699_the_twin_apps_determinism_canon_card_reads_again', false, false,
  'G394 (db/checks/0436): GRANT EXECUTE on public.ottoq_cert_recert_floor() to anon, so the twin app''s determinism '
  'canon card can read public.ottoq_determinism_canon with the public key (a view''s functions run with the reader''s '
  'right to call them). One STABLE function returning one timestamp; no engine path runs as anon: FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 11:07:24 UTC (6:07 AM CT), version 20261010110724 ═════════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 9eeaa49; the ledger's stored statement is that file byte for
--   byte (md5 44463f58461caee2ba226e10c3b06dc2, 7,695 characters, 8,471 bytes). P1, V1, V2 passed in the apply's
--   transaction. Read after: the floor function's ACL is {postgres=X/postgres,service_role=X/postgres,anon=X/postgres}
--   (no PUBLIC); lineage FALSE/FALSE (read 11:07:28 UTC). From outside at 11:07:31 UTC, with the legacy anon key and
--   with the publishable key: the 15 listed relations answer 200, ottoq_determinism_canon among them; the six unlisted
--   probed answer 401, code 42501.
