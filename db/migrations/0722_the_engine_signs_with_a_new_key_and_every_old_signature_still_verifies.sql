-- migration-version: PENDING
-- migration-name:    the_engine_signs_with_a_new_key_and_every_old_signature_still_verifies
--
-- 0722  **The key that signs every event, SDR and audit bundle is rotated, and every row the old key signed still verifies.
--        'system:v2', a new 32-byte Vault secret made inside the database and never selected by this file, signs from
--        now on. No browser role can read it; service_role and postgres can, as they can 'system:v1'. 'system:v1' stays
--        active, which is what keeps its rows verifying.** (FINDINGS G428, its rotation half; follows 0701, which closed
--        the old key to the browser roles, and refuses to run before it.) Written against the live catalog read-only on
--        2026-10-14 from 15:08:34 UTC (10:08 AM CT, the first query's own now()) to 15:21:19 UTC (10:21 AM CT, read from
--        the clock after the last query). No query in that window called the resolver, a signer or a verifier, or read a
--        secret: before 0701 the resolver caches the key for the whole pooled session, and db/checks/0438 forbids it. So
--        P2's premise (the newest v1 rows verify) is first measured inside this file's own transaction, after 0701.
--        ottoq_certification_in_flight(true) read 1 at 15:16:35 UTC; P0 refuses until it reads 0. Re-read read-only for
--        the review's fixes from 16:46:29 UTC (11:46 AM CT) to 16:47:57 UTC (11:47 AM CT), each the query's own now(),
--        again calling no resolver, signer or verifier and reading no secret: the object_kind values in
--        ottoq_schema_snapshots, the one audit bundle's signature shape (§1(c)), and who may read Vault (§2(a)).
--
-- ══ §0 CHASE'S GO-AHEAD: NOT YET GIVEN. THIS FILE REFUSES TO APPLY UNTIL IT IS. ══════════════════════════════════════
--
--   FINDINGS G428's status reads "OPEN — founder actions: rotate the signing secret; close or gate sign-up", and 0701 §0
--   keeps it so: "Rotating the key and closing sign-up stay his as well, and are not in this file." Nothing in the build
--   that drafted this file is his voice. So P0a declares v_said as the word PENDING between two chase-tagged dollar
--   quotes and refuses while it reads PENDING. When Chase says go, replace PENDING with his words, the date and the CT
--   time he said them (e.g. 2026-10-14, 2:15 PM CT: "..."), quote them here, and they go into this file's
--   ottoq_cert_lineage note. The same message may carry the go-ahead for 0701 and for this file; 0701 must be applied
--   first either way (P1).
--
--   Chase's go-ahead, as given: (PENDING)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) THE OLD KEY MAY HAVE BEEN READ. From 0198 (2026-09-06 03:21:56 UTC) until 0701, any signed-in caller could POST
--       to /rest/v1/rpc/ottoq_resolve_signing_secret and read 'system:v1''s secret (G428; role emulation returned its 64
--       characters, only the length printed). The API logs reach back about four days and show no such request, which
--       does not establish that nobody made one. 0701 closes the door; it cannot make the key unread. A key that may be
--       known outside the engine signs nothing new.
--
--   (b) HOW THE ENGINE CHOOSES A KEY, MEASURED. public.ottoq_signing_keys holds one row: system:v1, scope 'system',
--       scope_id NULL, active, secret_ref 'vault:ottoq_signing_key_system_v1', rotated_at NULL. The Vault secret's own
--       description says how to rotate: "Rotate by creating a new key_id row in ottoq_signing_keys + a new vault secret;
--       do NOT overwrite this one or previously-signed events become unverifiable." The resolver reads only key_id and
--       is_active; nothing else in the database reads the registry or rotated_at (every function and view searched). The
--       key is chosen ONLY by five literals, each in exactly one function (pinned in P1; how the rest was searched is
--       below the list):
--         ottoq_record_event            p_signing_key_id text DEFAULT 'system:v1'   every event
--         ottoq_emit_sdr                p_key_id text DEFAULT 'system:v1'           every SDR and its sdr_issued event
--         ottoq_generate_audit_bundle   p_signing_key_id text DEFAULT 'system:v1'   every audit bundle
--         ottoq_complete_audit_report   p_signing_key_id text DEFAULT 'system:v1'   every completed audit report
--         ottoq_trg_attribution_attach  p_signing_key_id => 'system:v1'             the sdr_costs_attached event
--       (pg_get_functiondef md5s 6d3eafdb, 8158e4bf, 23c0bda2, b0ec150f, 9a89bcd6; each literal occurs once in its
--       definition. 0701 changes these five's grants, not their definitions, and pg_get_functiondef carries no grant,
--       so the pins hold across it.) Searched live: no other function and no view names 'system:v1' except the resolver,
--       whose 0701 body drops it. Searched in the repo: no edge function (otto-twin-control, ottoq-ottocommand,
--       ottoq-agent-gateway, ottoq-depot-v2, ottoq-ingest among them) and no app code names a key or passes one. The
--       only caller that passes a key as a LITERAL is that trigger. ottoq_emit_sdr also passes a key to
--       ottoq_record_event (p_signing_key_id => p_key_id), but it is its own parameter, not a literal: the sdr_issued
--       event signs with whatever key the SDR did, which is emit_sdr's default unless its own caller names one.
--
--   (c) HOW A ROW IS VERIFIED. ottoq_verify_event_signature and ottoq_verify_audit_bundle re-sign the stored fields
--       with the row's own signature_key_id, through the resolver, which returns a secret only for an ACTIVE key. So v1
--       stays active: deactivate it and every one of its events and SDRs (2,613,582 and 145,888 at the count in
--       db/checks/0438's window) verifies as NULL. There is no "retired, verify-only" state, and this file does not
--       invent one. The registry's UNIQUE (scope, scope_id, is_active) is DEFERRABLE and scope_id is NULL for system
--       keys, so a second active system key is allowed (NULLs are distinct).
--       THE ONE AUDIT BUNDLE DOES NOT VERIFY TODAY, AND NOTHING HERE SAYS IT DOES. Live holds a single bundle, generated
--       2026-05-14 20:02:11 UTC with signature_key_id 'system:v1', and its signature is 36 characters, not the 64-hex
--       HMAC-SHA-256 that ottoq_sign_bundle returns (read 16:46:29 UTC, its length and shape only). ottoq_verify_audit_
--       bundle (live md5 40afdf34) sets out_valid to `v_recomputed IS NOT NULL AND v_recomputed = v_bundle.signature`,
--       and a 64-character recomputation never equals 36 characters: out_valid is false today and stays false after
--       this file. That is read from the verifier's source; the verifier was not called. So P2 and V4 ask only about a
--       v1 bundle whose signature is 64 hex. On live there is none, so both report the bundle as 'none' and say how many
--       v1 bundles they did not ask about and why (1 on live; 0 on the stub, whose bundle is signed by the live writer).
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) A NEW VAULT SECRET, 'ottoq_signing_key_system_v2': vault.create_secret(encode(extensions.gen_random_bytes(32),
--       'hex'), ...). The value is made inside the database and handed straight to Vault: it is in no statement's text,
--       no log line, no NOTICE and no result. This file never selects a secret, never calls the resolver, and never reads
--       vault.decrypted_secrets; the only reads of the new secret are the signers' own, inside blocks that roll back
--       (and 0701's resolver caches for one transaction only). It reads vault.secrets by name, never its secret column.
--       WHO CAN READ IT. No browser role: anon and authenticated hold no SELECT on vault.decrypted_secrets (live, read
--       16:47:12 UTC), and after 0701 neither may execute the resolver, a signer or ottoq_oem_deliver_live (which reads
--       any Vault secret by a name its caller passes); P1 asserts all of it. service_role and postgres CAN, exactly as
--       they can read v1: both hold SELECT on vault.decrypted_secrets, and 0701 keeps service_role's EXECUTE on the
--       resolver, so anything holding the service key (an edge function, a POST to /rest/v1/rpc/ottoq_resolve_signing_
--       secret) can fetch v2 in plaintext the moment this commits. "Never selected" is a claim about this file, not about
--       the database. G428's exposure was the browser roles; this file rotates away from that, and does not narrow the
--       service roles.
--   (b) A NEW REGISTRY ROW: ('system:v2', 'system', NULL, 'HMAC-SHA-256', 'vault:ottoq_signing_key_system_v2', active,
--       created_by 'migration:0722_...').
--   (c) v1 IS MARKED, NOT RETIRED: rotated_at = now() and a rotation_reason naming G428. is_active stays TRUE, so v1
--       still resolves, and every v1 signature still verifies. The Vault secret of v1 is not touched.
--   (d) THE FIVE LITERALS become 'system:v2', each by an anchored substitution asserted to occur exactly once in the
--       pinned definition (0715's pattern). CREATE OR REPLACE may change a parameter's default; pg_proc.c refuses only
--       removing one or changing its type (https://raw.githubusercontent.com/postgres/postgres/REL_17_STABLE/src/backend/
--       catalog/pg_proc.c, read 2026-10-14), and it keeps the owner and the grants ("the ownership and permissions of the
--       function do not change", https://www.postgresql.org/docs/17/sql-createfunction.html, read 2026-10-14). V1
--       asserts both: each definition md5 is the one this file computes, and each ACL is what it was.
--   A caller already planned under the old default signs with v1 until it re-plans; that row verifies, because v1 is
--   still active. Nothing is re-signed and ottoq_events is not touched: V4's probe event is written and rolled back in
--   one block (one ottoq_events_event_seq_seq value is spent, which nothing reads as contiguous). The two probe functions
--   (pg_temp.p0722_sigs and pg_temp.p0722_old_rows) are dropped before COMMIT and the temp tables are ON COMMIT DROP, so
--   nothing this file made is left in the session that applied it.
--   NOT CHANGED: the verifiers, the signers, the resolver, any grant, and Auth's sign-up setting (G428's other founder
--   action, a dashboard switch). A forger who read v1 before 0701 can still make a v1 signature that verifies; §5 is the
--   follow-up that closes it, and it is not in this file.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   No atom reads a signature or a key id: h_evt digests event_type|entity|sim_clock_at; h_sdr is ottoq_hash_sdrs, which
--   names neither column (its source read 2026-10-14: an explicit column list, payload_hash left out by 0218); the
--   decision frame's payload names neither (ottoq_capture_decision_snapshot and ottoq_frame_hash_payload searched). The
--   only functions that read signature_key_id are the five writers and the two verifiers. Signatures change from now on,
--   which is the point; nothing certified reads them. No dial is touched.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) THIS FILE. EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0722_pre' AND object_kind =
--       'function', in snapshot_id order: the five functions with their v1 defaults. Then put v1's rotated_at and
--       rotation_reason back from the 'table_row' snapshot, a jsonb array of {key_id, rotated_at, rotation_reason} (the
--       convention 0573 and 0574 use for a row's fields):
--         UPDATE public.ottoq_signing_keys k
--            SET rotated_at = (r->>'rotated_at')::timestamptz, rotation_reason = r->>'rotation_reason'
--           FROM public.ottoq_schema_snapshots s CROSS JOIN LATERAL jsonb_array_elements(s.definition::jsonb) r
--          WHERE s.label = '0722_pre' AND s.object_kind = 'table_row' AND s.object_name = 'ottoq_signing_keys'
--            AND k.key_id = r->>'key_id';
--       Leave 'system:v2' (its row and its Vault secret) active: rows signed with it between the apply and the rollback
--       verify only while it resolves. Never overwrite or delete either Vault secret. Rolling back puts new rows back on
--       a key that may have been read. This file cannot then be applied again (P1 refuses on the v2 row it leaves); a
--       second rotation is a new file with a new key id.
--   (b) ROLLING BACK 0701 AFTER THIS FILE EXPOSES 'system:v2' TO EVERY SIGNED-IN USER. 0701 §4 restores the resolver as
--       it was and gives back every grant 0701 took from the browser roles and PUBLIC, authenticated's EXECUTE on the
--       resolver among them. The resolver returns the secret of any ACTIVE key, and v2 is active; it stays active even
--       if (a) runs first, so rolling this file back does not protect it. A 0701 rollback therefore hands v2 to every
--       signed-in caller, exactly as v1 was handed out from 0198 until 0701. Before any such rollback, rotate again (a
--       new key id and a new Vault secret, in a new file), and if 0701 is ever rolled back regardless, treat v2 as read
--       from the moment that rollback commits.
--
-- ══ §5 FOLLOW-UP, NOT IN THIS FILE AND NOT EXECUTED BY IT: refuse a v1 signature on a row recorded after the rotation ══
--
--   Rotation does not stop someone who read v1 before 0701: v1 stays active so its rows verify, and a forged v1 row
--   verifies with them. The mitigation (recommended by the security lane's review, 2026-10-14): ottoq_verify_event_signature and
--   ottoq_verify_audit_bundle return valid = false for a signature whose key has a rotated_at and whose row was recorded
--   after it (there is no SDR verifier to change). Sketch, after the recompute in ottoq_verify_event_signature:
--       valid := v_recomputed = v_event.signature
--                AND NOT EXISTS (SELECT 1 FROM ottoq_signing_keys k
--                                 WHERE k.key_id = v_event.signature_key_id AND k.rotated_at IS NOT NULL
--                                   AND v_event.recorded_at > k.rotated_at + <grace>);
--   Two things to settle before it is built, which is why it is a separate file:
--     1. The boundary. rotated_at is this file's transaction start (now()), and a transaction that began before this
--        file committed can still record a v1 row after it, its plan made under the old default, with a recorded_at
--        later than rotated_at (a determinism pair runs both arms in one transaction). A strict boundary would call
--        genuine rows forged. It needs a grace at least as long as the longest transaction that can straddle the commit,
--        or a boundary taken after the commit (the highest event_seq signed with v1 once no v1 writer remains).
--     2. The readers. Both verifiers are SECURITY DEFINER and authenticated may execute them (0701 left them, db/checks/
--        0438 (E)); changing what `valid` means changes it for every reader, so the readers are named first.
--   Also there: re-signing the 2.6M v1 rows under v2 is NOT the mitigation. It would mutate append-only evidence and
--   would launder any forged row into a v2 signature.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0722 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P0a: Chase's go-ahead (§0). Replace PENDING with his words, the date and the CT time he said them. ──
CREATE TEMP TABLE p0722_go_ahead (said text NOT NULL) ON COMMIT DROP;
DO $go_ahead$
DECLARE
  v_said text := $chase$PENDING$chase$;
BEGIN
  IF v_said ~* '^\s*PENDING\s*$'
     OR v_said !~ '2026-\d\d-\d\d'
     OR v_said !~* '\m\d{1,2}:\d\d\s*(AM|PM)\s+CT\M' THEN
    RAISE EXCEPTION '0722 P0a: Chase''s go-ahead is not in this file. FINDINGS G428 leaves rotating the signing key to him; '
                    'paste his words, the date and the CT time he said them (e.g. 2026-10-14, 2:15 PM CT: "...") where P0a '
                    'reads PENDING, and quote them in §0';
  END IF;
  INSERT INTO p0722_go_ahead VALUES (v_said);
END $go_ahead$;

-- ── the five functions whose default key changes: the live definition each was written against, the definition this
--    file makes, and the one substitution between them ──
CREATE TEMP TABLE p0722_fns (
  ord int PRIMARY KEY, sig text NOT NULL, pre_md5 text NOT NULL, post_md5 text NOT NULL,
  old_anchor text NOT NULL, new_anchor text NOT NULL, acl_before text, shape_before text) ON COMMIT DROP;
INSERT INTO p0722_fns (ord, sig, pre_md5, post_md5, old_anchor, new_anchor) VALUES
  (1, 'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,integer,text,text,text,uuid)',
      '6d3eafdb8d582a05c6d0af2b90bbb8ff', '593dd0b01cba27b98bd217f5896df4d0',
      'p_signing_key_id text DEFAULT ''system:v1''::text', 'p_signing_key_id text DEFAULT ''system:v2''::text'),
  (2, 'public.ottoq_emit_sdr(text,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,text)',
      '8158e4bf2fdac5a8e0495d65c43b891a', '40d49d125de6aad894729aa20cc84856',
      'p_key_id text DEFAULT ''system:v1''::text', 'p_key_id text DEFAULT ''system:v2''::text'),
  (3, 'public.ottoq_generate_audit_bundle(uuid,uuid[],text,timestamptz,timestamptz,text,text,bigint,text,text,text,text,timestamptz)',
      '23c0bda2f0c9ce64b02c9c25699cf412', 'b60b9e865167da6b77b2a592f9cfa95f',
      'p_signing_key_id text DEFAULT ''system:v1''::text', 'p_signing_key_id text DEFAULT ''system:v2''::text'),
  (4, 'public.ottoq_complete_audit_report(uuid,jsonb,bigint,bigint,bigint,bigint,bigint,bigint,bigint,boolean,numeric,text)',
      'b0ec150fae0619d75af4e32bafe37bc0', '3d5140303b22240f1e988c8b36a516c4',
      'p_signing_key_id text DEFAULT ''system:v1''::text', 'p_signing_key_id text DEFAULT ''system:v2''::text'),
  (5, 'public.ottoq_trg_attribution_attach()',
      '9a89bcd66a2319d734828bb601b539a0', '3898824f6f54bdd10268c655182f19be',
      'p_signing_key_id => ''system:v1'',', 'p_signing_key_id => ''system:v2'',');

-- ── P1: what this file was written against ──
DO $premises$
DECLARE
  r record; v_bad text; v_n int;
BEGIN
  -- 0701 first: until it is applied, any signed-in caller reads whatever key is active, the new one included
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0701_a_signed_in_user_cannot_read_the_signing_key_or_call_the_signers_or_purge') THEN
    RAISE EXCEPTION '0722 P1: 0701 is not applied (no ottoq_cert_lineage row); a signed-in caller would read the new key '
                    'the moment it exists. Apply 0701 first';
  END IF;
  IF to_regprocedure('public.ottoq_resolve_signing_secret(text)') IS NULL
     OR (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_resolve_signing_secret(text)'))
        IS DISTINCT FROM 'ae44bc24121d3b33e6dcfc94b54b8c28' THEN
    RAISE EXCEPTION '0722 P1: the resolver is not 0701''s (no setting override, a cache that lives for one transaction)';
  END IF;
  SELECT string_agg(s, ', ') INTO v_bad
    FROM unnest(ARRAY['public.ottoq_resolve_signing_secret(text)',
                      'public.ottoq_sign_event(uuid,timestamptz,text,text,text,uuid,text,text)',
                      'public.ottoq_sign_sdr(uuid,timestamptz,uuid,text,text,text)',
                      'public.ottoq_sign_bundle(uuid,timestamptz,timestamptz,text,text)',
                      -- reads any Vault secret by a name its caller passes, and signs with it (0701 §1(b))
                      'public.ottoq_oem_deliver_live(uuid,uuid,uuid,uuid,text,text,jsonb,text,timestamptz)']) s
   WHERE to_regprocedure(s) IS NULL
      OR has_function_privilege('anon', to_regprocedure(s), 'EXECUTE')
      OR has_function_privilege('authenticated', to_regprocedure(s), 'EXECUTE')
      OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = to_regprocedure(s) AND a.grantee = 0);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0722 P1: a browser role or PUBLIC may still execute %; 0701''s revoke is not in force', v_bad;
  END IF;
  -- and no browser role reads Vault directly (a privilege check on the view; nothing is selected from it)
  IF has_table_privilege('anon', 'vault.decrypted_secrets', 'SELECT')
     OR has_table_privilege('authenticated', 'vault.decrypted_secrets', 'SELECT') THEN
    RAISE EXCEPTION '0722 P1: a browser role may SELECT vault.decrypted_secrets; it would read the new key directly';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0722\_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_schema_snapshots WHERE label = '0722_pre') THEN
    RAISE EXCEPTION '0722 P1: 0722 has run already';
  END IF;
  -- the registry as measured: v1 the only active system key, Vault-backed, never rotated; no v2 yet
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_signing_keys k
                  WHERE k.key_id = 'system:v1' AND k.scope = 'system' AND k.scope_id IS NULL AND k.is_active
                    AND k.secret_ref = 'vault:ottoq_signing_key_system_v1' AND k.rotated_at IS NULL) THEN
    RAISE EXCEPTION '0722 P1: system:v1 is not the active, Vault-backed, unrotated system key this file was written against';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_signing_keys k WHERE k.scope = 'system' AND k.is_active;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0722 P1: % active system keys, not 1; re-read the registry', v_n;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_signing_keys k WHERE k.key_id = 'system:v2') THEN
    RAISE EXCEPTION '0722 P1: a system:v2 registry row exists already';
  END IF;
  -- Vault, by name only: v1's secret is there, v2's is not
  IF (SELECT count(*) FROM vault.secrets s WHERE s.name = 'ottoq_signing_key_system_v1') <> 1 THEN
    RAISE EXCEPTION '0722 P1: the Vault secret ottoq_signing_key_system_v1 is missing; v1''s rows could not verify';
  END IF;
  IF EXISTS (SELECT 1 FROM vault.secrets s WHERE s.name = 'ottoq_signing_key_system_v2') THEN
    RAISE EXCEPTION '0722 P1: a Vault secret named ottoq_signing_key_system_v2 exists already; never overwrite a signing secret';
  END IF;
  IF to_regprocedure('vault.create_secret(text,text,text,uuid)') IS NULL
     OR NOT has_function_privilege(current_user, to_regprocedure('vault.create_secret(text,text,text,uuid)'), 'EXECUTE')
     OR to_regprocedure('extensions.gen_random_bytes(integer)') IS NULL
     OR NOT has_function_privilege(current_user, to_regprocedure('extensions.gen_random_bytes(integer)'), 'EXECUTE') THEN
    RAISE EXCEPTION '0722 P1: vault.create_secret or extensions.gen_random_bytes is missing or not executable by %', current_user;
  END IF;
  -- the five, as written against: each exists, is SECURITY DEFINER, and its definition is the one pinned
  FOR r IN SELECT f.* FROM p0722_fns f ORDER BY f.ord LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE EXCEPTION '0722 P1: % does not exist', r.sig;
    END IF;
    IF md5(pg_get_functiondef(to_regprocedure(r.sig))) IS DISTINCT FROM r.pre_md5 THEN
      RAISE EXCEPTION '0722 P1: % is not the definition this file was written against (md5 %)',
        r.sig, md5(pg_get_functiondef(to_regprocedure(r.sig)));
    END IF;
  END LOOP;
  -- the five are the only places the v1 key is named: no other function would keep signing with it
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_(temp|toast)'
     AND (p.prosrc ~ 'system:v1' OR pg_get_function_arguments(p.oid) ~ 'system:v1')
     AND p.oid NOT IN (SELECT to_regprocedure(f.sig) FROM p0722_fns f);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0722 P1: functions other than the five name system:v1: %; read them before rotating', v_bad;
  END IF;
  UPDATE p0722_fns f
     SET acl_before = (SELECT p.proacl::text FROM pg_proc p WHERE p.oid = to_regprocedure(f.sig)),
         shape_before = (SELECT concat_ws('|', p.prosecdef::text, pg_get_userbyid(p.proowner), p.provolatile::text,
                                          COALESCE(p.proconfig::text, '-'), pg_get_function_result(p.oid))
                           FROM pg_proc p WHERE p.oid = to_regprocedure(f.sig));
END $premises$;

-- ── probes, each in a block that rolls itself back and carries out booleans and md5s only ──
-- the three signatures on one synthetic input, under the key given (md5s of the signatures, and how many are 64 hex)
CREATE FUNCTION pg_temp.p0722_sigs(p_key text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    DECLARE
      v_ev text; v_sdr text; v_bun text;
    BEGIN
      v_ev := public.ottoq_sign_event('00000000-0000-4000-8000-000000000722', timestamptz '2026-10-14 00:00:00+00',
                                      'system', 'probe.0722', 'probe', NULL, md5('0722'), p_key);
      v_sdr := public.ottoq_sign_sdr('00000000-0000-4000-8000-000000000722', timestamptz '2026-10-14 00:00:00+00',
                                     NULL, 'probe_0722', md5('0722'), p_key);
      v_bun := public.ottoq_sign_bundle('00000000-0000-4000-8000-000000000722', timestamptz '2026-10-14 00:00:00+00',
                                        timestamptz '2026-10-14 01:00:00+00', md5('0722'), p_key);
      RAISE EXCEPTION 'SIGS|%|%|%|hex %',
        COALESCE(md5(v_ev), 'null'), COALESCE(md5(v_sdr), 'null'), COALESCE(md5(v_bun), 'null'),
        COALESCE((v_ev ~ '^[0-9a-f]{64}$')::int, 0) + COALESCE((v_sdr ~ '^[0-9a-f]{64}$')::int, 0)
          + COALESCE((v_bun ~ '^[0-9a-f]{64}$')::int, 0);
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

-- the stored rows a verifier is asked about: does each still verify (booleans only). 'none' means none was asked about:
-- there is no such row, or, for a bundle, no v1 bundle whose signature is a 64-hex HMAC (live's one bundle is not, §1(c);
-- P2 counts the bundles it does not ask about and both P2 and V4 say so)
CREATE FUNCTION pg_temp.p0722_old_rows(p_event uuid, p_sdr uuid, p_bundle uuid) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    DECLARE
      v_ev text := 'none'; v_sdr text := 'none'; v_bun text := 'none';
    BEGIN
      IF p_event IS NOT NULL THEN
        SELECT COALESCE(v.valid::text, 'null') INTO v_ev FROM public.ottoq_verify_event_signature(p_event) v;
      END IF;
      IF p_sdr IS NOT NULL THEN
        SELECT COALESCE((public.ottoq_sign_sdr(d.sdr_id, d.ended_at, d.vehicle_id, d.operation_code, d.payload_hash,
                                               d.signature_key_id) = d.signature)::text, 'null')
          INTO v_sdr FROM public.ottoq_service_detail_records d WHERE d.sdr_id = p_sdr;
      END IF;
      IF p_bundle IS NOT NULL THEN
        SELECT COALESCE(v.out_valid::text, 'null') INTO v_bun FROM public.ottoq_verify_audit_bundle(p_bundle) v;
      END IF;
      RAISE EXCEPTION 'OLD|event %|sdr %|bundle %', v_ev, v_sdr, v_bun;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

CREATE TEMP TABLE p0722 (phase text PRIMARY KEY, r text, event_id uuid, sdr_id uuid, bundle_id uuid) ON COMMIT DROP;

-- ── P2: before anything changes, the newest row v1 signed of each kind verifies, and v1's synthetic signatures ──
DO $before$
DECLARE
  v_event uuid; v_sdr uuid; v_bundle uuid; v_old text; v_sigs text; v_not_asked int;
BEGIN
  SELECT e.event_id INTO v_event FROM public.ottoq_events e
   WHERE e.signature_key_id = 'system:v1' AND e.signature IS NOT NULL
   ORDER BY e.event_seq DESC LIMIT 1;
  IF v_event IS NULL THEN
    RAISE EXCEPTION '0722 P2: no event signed with system:v1 exists; there is nothing to prove still verifies';
  END IF;
  SELECT d.sdr_id INTO v_sdr FROM public.ottoq_service_detail_records d
   WHERE d.signature_key_id = 'system:v1' AND d.signature IS NOT NULL
   ORDER BY d.issued_at DESC, d.sdr_id LIMIT 1;
  SELECT b.bundle_id INTO v_bundle FROM public.ottoq_audit_bundles b
   WHERE b.signature_key_id = 'system:v1' AND b.signature ~ '^[0-9a-f]{64}$'
   ORDER BY b.generated_at DESC, b.bundle_id LIMIT 1;
  -- the v1 bundles not asked about: no 64-hex HMAC signature, so no key verifies them (live: 1, 36 characters, §1(c))
  SELECT count(*) INTO v_not_asked FROM public.ottoq_audit_bundles b
   WHERE b.signature_key_id = 'system:v1' AND (b.signature IS NULL OR b.signature !~ '^[0-9a-f]{64}$');
  v_old := pg_temp.p0722_old_rows(v_event, v_sdr, v_bundle);
  IF v_old !~ '^OLD\|event true\|sdr (true|none)\|bundle (true|none)$' THEN
    RAISE EXCEPTION '0722 P2: the newest v1 rows do not verify before this file changes anything: %', v_old;
  END IF;
  v_sigs := pg_temp.p0722_sigs('system:v1');
  IF v_sigs !~ '^SIGS\|[0-9a-f]{32}\|[0-9a-f]{32}\|[0-9a-f]{32}\|hex 3$' THEN
    RAISE EXCEPTION '0722 P2: the engine does not sign with system:v1 before this file: %', v_sigs;
  END IF;
  IF pg_temp.p0722_sigs('system:v2') <> 'SIGS|null|null|null|hex 0' THEN
    RAISE EXCEPTION '0722 P2: system:v2 already resolves to a secret';
  END IF;
  INSERT INTO p0722 (phase, r, event_id, sdr_id, bundle_id) VALUES ('old_before', v_old, v_event, v_sdr, v_bundle),
                                                                   ('v1_sigs_before', v_sigs, NULL, NULL, NULL),
                                                                   ('bundles_not_asked', v_not_asked::text, NULL, NULL, NULL);
  RAISE NOTICE '0722 P2: before: newest v1 rows %; v1 signs (md5s only kept); % v1 audit bundle(s) not asked about: their '
               'signature is not a 64-hex HMAC, so they verify under no key, before this file or after it', v_old, v_not_asked;
END $before$;

-- ── snapshot: the five definitions, and v1's registry fields this file sets ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0722_pre', 'function', n.nspname, p.oid::regprocedure::text, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM p0722_fns f JOIN pg_proc p ON p.oid = to_regprocedure(f.sig) JOIN pg_namespace n ON n.oid = p.pronamespace
 ORDER BY f.ord;

-- v1's two fields this file sets, as 'table_row' data (0573's and 0574's convention: a jsonb array, not a statement);
-- §4(a) has the UPDATE that puts them back
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0722_pre', 'table_row', 'public', 'ottoq_signing_keys', d::text, md5(d::text)
  FROM (SELECT jsonb_agg(jsonb_build_object('key_id', k.key_id, 'rotated_at', k.rotated_at,
                                            'rotation_reason', k.rotation_reason) ORDER BY k.key_id) AS d
          FROM public.ottoq_signing_keys k WHERE k.key_id = 'system:v1') x;

-- ── (a) the new secret, made inside the database and handed straight to Vault; nothing reads it back here ──
DO $secret$
DECLARE v_id uuid;
BEGIN
  v_id := vault.create_secret(
    encode(extensions.gen_random_bytes(32), 'hex'),
    'ottoq_signing_key_system_v2',
    'HMAC-SHA-256 signing key for ottoq_events, ottoq_service_detail_records and ottoq_audit_bundles, key_id=system:v2. '
    'Created by migration 0722 (FINDINGS G428): system:v1 may have been read through ottoq_resolve_signing_secret '
    'between 2026-09-06 and 0701, so it signs nothing new; it stays active so its rows still verify. Rotate by creating '
    'a new key_id row in ottoq_signing_keys + a new vault secret; do NOT overwrite this one or previously-signed rows '
    'become unverifiable.');
  IF v_id IS NULL THEN
    RAISE EXCEPTION '0722 (a): vault.create_secret returned no id';
  END IF;
END $secret$;

-- ── (b) the registry row ──
INSERT INTO public.ottoq_signing_keys (key_id, scope, scope_id, algorithm, secret_ref, is_active, created_by)
VALUES ('system:v2', 'system', NULL, 'HMAC-SHA-256', 'vault:ottoq_signing_key_system_v2', true,
        'migration:0722_the_engine_signs_with_a_new_key_and_every_old_signature_still_verifies');

-- ── (c) v1 marked rotated, and kept active so every v1 signature still verifies ──
DO $rotate$
DECLARE v_n int;
BEGIN
  UPDATE public.ottoq_signing_keys k
     SET rotated_at = now(),
         rotation_reason = 'FINDINGS G428: any signed-in caller could read this key through ottoq_resolve_signing_secret '
                           'from 0198 (2026-09-06 03:21:56 UTC) until 0701. Rotated by 0722 to system:v2. Kept ACTIVE so '
                           'the rows it signed still verify; it signs nothing new.'
   WHERE k.key_id = 'system:v1' AND k.is_active AND k.rotated_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0722 (c): marked % v1 rows, expected 1', v_n;
  END IF;
END $rotate$;

-- ── (d) the five defaults: one anchored substitution each, asserted to occur exactly once ──
DO $defaults$
DECLARE r record; v_def text; v_n int;
BEGIN
  FOR r IN SELECT f.* FROM p0722_fns f ORDER BY f.ord LOOP
    v_def := pg_get_functiondef(to_regprocedure(r.sig));
    v_n := (length(v_def) - length(replace(v_def, r.old_anchor, ''))) / length(r.old_anchor);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0722 (d): the anchor occurs % times in %, expected exactly 1', v_n, r.sig;
    END IF;
    EXECUTE replace(v_def, r.old_anchor, r.new_anchor);
  END LOOP;
END $defaults$;

-- ── V1: the five as written: each definition the one computed, its grants, owner, security, volatility, settings and
--    result unchanged; v1 named nowhere any more, v2 in exactly the five ──
DO $verify_defaults$
DECLARE r record; v_bad text;
BEGIN
  FOR r IN SELECT f.*, p.oid AS foid, p.proacl::text AS acl_after,
                  concat_ws('|', p.prosecdef::text, pg_get_userbyid(p.proowner), p.provolatile::text,
                            COALESCE(p.proconfig::text, '-'), pg_get_function_result(p.oid)) AS shape_after
             FROM p0722_fns f JOIN pg_proc p ON p.oid = to_regprocedure(f.sig) ORDER BY f.ord LOOP
    IF md5(pg_get_functiondef(r.foid)) IS DISTINCT FROM r.post_md5 THEN
      RAISE EXCEPTION '0722 V1 FAILED: % is not as written (md5 %)', r.sig, md5(pg_get_functiondef(r.foid));
    END IF;
    IF r.acl_after IS DISTINCT FROM r.acl_before OR r.shape_after IS DISTINCT FROM r.shape_before THEN
      RAISE EXCEPTION '0722 V1 FAILED: % changed its grants or shape: % / %', r.sig, r.acl_after, r.shape_after;
    END IF;
  END LOOP;
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_(temp|toast)'
     AND (p.prosrc ~ 'system:v1' OR pg_get_function_arguments(p.oid) ~ 'system:v1');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0722 V1 FAILED: system:v1 is still named by %', v_bad;
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND n.nspname !~ '^pg_(temp|toast)'
         AND (p.prosrc ~ 'system:v2' OR pg_get_function_arguments(p.oid) ~ 'system:v2')
         AND p.oid IN (SELECT to_regprocedure(f.sig) FROM p0722_fns f)) <> 5 THEN
    RAISE EXCEPTION '0722 V1 FAILED: system:v2 is not the default of all five';
  END IF;
  RAISE NOTICE '0722 V1 PASSED: five defaults now system:v2, each definition as computed, grants and shape unchanged';
END $verify_defaults$;

-- ── V2: the registry and Vault, by name: two active system keys, v1 marked and kept, both secrets present once ──
DO $verify_registry$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_signing_keys k
                  WHERE k.key_id = 'system:v2' AND k.scope = 'system' AND k.scope_id IS NULL AND k.is_active
                    AND k.algorithm = 'HMAC-SHA-256' AND k.secret_ref = 'vault:ottoq_signing_key_system_v2')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_signing_keys k
                     WHERE k.key_id = 'system:v1' AND k.is_active AND k.rotated_at = now()
                       AND k.rotation_reason ~ 'G428' AND k.secret_ref = 'vault:ottoq_signing_key_system_v1')
     OR (SELECT count(*) FROM public.ottoq_signing_keys k WHERE k.scope = 'system' AND k.is_active) <> 2
     OR (SELECT count(*) FROM vault.secrets s WHERE s.name = 'ottoq_signing_key_system_v1') <> 1
     OR (SELECT count(*) FROM vault.secrets s WHERE s.name = 'ottoq_signing_key_system_v2') <> 1 THEN
    RAISE EXCEPTION '0722 V2 FAILED: the registry or Vault is not as written';
  END IF;
  RAISE NOTICE '0722 V2 PASSED: system:v2 active and Vault-backed; system:v1 marked rotated and still active';
END $verify_registry$;

-- ── V3: the new key signs, 64 hex, differently from v1 on the same input; v1 still signs byte for byte as before ──
DO $verify_signatures$
DECLARE
  v_before text := (SELECT r FROM p0722 WHERE phase = 'v1_sigs_before');
  v_v1 text := pg_temp.p0722_sigs('system:v1');
  v_v2 text := pg_temp.p0722_sigs('system:v2');
BEGIN
  IF v_v2 !~ '^SIGS\|[0-9a-f]{32}\|[0-9a-f]{32}\|[0-9a-f]{32}\|hex 3$' THEN
    RAISE EXCEPTION '0722 V3 FAILED: system:v2 does not sign 64 hex on all three signers: %', v_v2;
  END IF;
  IF v_v1 IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION '0722 V3 FAILED: system:v1''s signatures moved: before %, after %', v_before, v_v1;
  END IF;
  IF split_part(v_v2, '|', 2) = split_part(v_v1, '|', 2) OR split_part(v_v2, '|', 3) = split_part(v_v1, '|', 3)
     OR split_part(v_v2, '|', 4) = split_part(v_v1, '|', 4) THEN
    RAISE EXCEPTION '0722 V3 FAILED: a system:v2 signature equals system:v1''s on the same input';
  END IF;
  RAISE NOTICE '0722 V3 PASSED: v2 signs 64 hex on all three signers and differs from v1; v1 unchanged (md5s only compared)';
END $verify_signatures$;

-- ── V4: the newest v1 rows P2 read still verify; a new event (written and rolled back) carries v2 and verifies ──
DO $verify_rows$
DECLARE
  b record; v_old text; v_msg text;
BEGIN
  SELECT * INTO b FROM p0722 WHERE phase = 'old_before';
  v_old := pg_temp.p0722_old_rows(b.event_id, b.sdr_id, b.bundle_id);
  IF v_old IS DISTINCT FROM b.r THEN
    RAISE EXCEPTION '0722 V4 FAILED: the newest v1 rows verified % before and % after', b.r, v_old;
  END IF;
  BEGIN
    DECLARE
      v_id uuid; v_key text; v_hex boolean; v_valid boolean;
    BEGIN
      v_id := public.ottoq_record_event(p_actor_type => 'migration_script', p_event_type => 'migration.0722_probe',
                                        p_entity_type => 'migration', p_payload => jsonb_build_object('probe', '0722'),
                                        p_severity => 'info', p_ingest_source => 'migration');
      SELECT e.signature_key_id, e.signature ~ '^[0-9a-f]{64}$' INTO v_key, v_hex
        FROM public.ottoq_events e WHERE e.event_id = v_id;
      SELECT v.valid INTO v_valid FROM public.ottoq_verify_event_signature(v_id) v;
      RAISE EXCEPTION 'PROBE|%|%|%', COALESCE(v_key, 'null'), COALESCE(v_hex::text, 'null'), COALESCE(v_valid::text, 'null');
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'PROBE|system:v2|true|true' THEN
    RAISE EXCEPTION '0722 V4 FAILED: a new event: %', v_msg;
  END IF;
  RAISE NOTICE '0722 V4 PASSED: the newest v1 rows still verify (%; % v1 audit bundle(s) not asked about, not HMAC-signed); '
               'a new event signs with system:v2 and verifies; rolled back',
               v_old, (SELECT r FROM p0722 WHERE phase = 'bundles_not_asked');
END $verify_rows$;

-- ── V5: the probes rolled back, and with them the resolver's cache: nothing of either key is left in this transaction ──
DO $verify_cache$
BEGIN
  IF COALESCE(current_setting('ottoq.sigcache_' || md5('system:v1'), true), '') <> ''
     OR COALESCE(current_setting('ottoq.sigcache_' || md5('system:v2'), true), '') <> ''
     OR COALESCE(current_setting('ottoq.sigcache_' || md5('system:v1') || '_tx', true), '') <> ''
     OR COALESCE(current_setting('ottoq.sigcache_' || md5('system:v2') || '_tx', true), '') <> '' THEN
    RAISE EXCEPTION '0722 V5 FAILED: the signing cache outlived the blocks that set it';
  END IF;
  RAISE NOTICE '0722 V5 PASSED: no signing cache left in this transaction';
END $verify_cache$;

-- the two probe functions go with the transaction, as the temp tables do ON COMMIT DROP: nothing of this file is left
-- in the applying session after it
DROP FUNCTION pg_temp.p0722_sigs(text);
DROP FUNCTION pg_temp.p0722_old_rows(uuid, uuid, uuid);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0722_the_engine_signs_with_a_new_key_and_every_old_signature_still_verifies', false, false,
  'G428, the rotation half (after 0701): a new Vault secret ottoq_signing_key_system_v2 (32 random bytes, made in the '
  'database and never selected by this file; no browser role can read it, service_role and postgres can, as for v1) '
  'and an active system:v2 registry row; system:v1 marked rotated_at/rotation_reason and kept '
  'ACTIVE so every v1 row still verifies (V4); the five defaults (record_event, emit_sdr, generate_audit_bundle, '
  'complete_audit_report, trg_attribution_attach) now system:v2, grants unchanged (V1). No atom reads a signature or a '
  'key id (h_evt, ottoq_hash_sdrs and the decision frame name neither), and no dial moves: FALSE/FALSE. Still open: a '
  'verifier that refuses v1 on a row recorded after the rotation (0722 §5), and closing or gating sign-up. '
  'Chase''s go-ahead (FINDINGS G428): ' || (SELECT g.said FROM p0722_go_ahead g),
  now());

COMMIT;
