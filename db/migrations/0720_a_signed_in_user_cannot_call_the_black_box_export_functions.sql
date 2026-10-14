-- migration-version: PENDING
-- migration-name:    a_signed_in_user_cannot_call_the_black_box_export_functions
--
-- 0720  **A signed-in user can no longer call the two Black Box export functions through /rest/v1/rpc; the same user
--        still reads most of a run, table by table, through /rest/v1/<relation> (§2 NOT CHANGED, FINDINGS G438).**
--        public.ottoq_run_blackbox(uuid) and public.ottoq_run_blackbox_meta(uuid) are SECURITY DEFINER and executable by
--        `authenticated`, and public sign-up is open (FINDINGS G428), so anyone who signs up can pull a whole run in one
--        call, with the engine's source, through PostgREST without going near the edge function that PR #243 locks.
--        This file takes EXECUTE on both from PUBLIC, anon and authenticated. service_role keeps both, and service_role
--        is how the edge function calls the meta read. (FINDINGS G435 (b); db/checks/0446 §5 (a).)
--        Measured read-only on the live catalog on 2026-10-14, from 14:49:46 UTC (9:49 AM CT, the first query's own
--        now()) to 14:59:52 UTC (9:59 AM CT, the last query's own now()); §2's table door from 16:34:47 UTC (11:34 AM
--        CT) to 16:37:57 UTC (11:37 AM CT), the same way, and re-read unchanged at 17:34 UTC (12:34 PM CT). The P0/P1
--        dry run is in §5.
--
-- ══ §0 STATUS: WRITTEN AND EXECUTED ON A STUB; NOT APPLIED ══════════════════════════════════════════════════════════
--
--   tests/test_blackbox_rpc_grants_sql.py runs this file on a stub that carries both live bodies (md5-pinned), both
--   live ACLs, and the live grants and row-security policies of the five relations the stub holds. Before the file, a
--   signed-in caller gets the whole bundle. After it, both functions refuse authenticated and anon with 42501, and
--   service_role still gets the bundle. The suite also records what the file does not close: after it, the same
--   signed-in caller still reads ottoq_decisions, ottoq_sim_runs and stalls as tables, exactly as before it.
--   WHAT THIS FILE CLOSES, and nothing wider: the RPC door. Through it a signed-in caller got, in one call, (i) the
--   current source of the 49 engine functions in `executed_code`, (ii) the depot's vehicles and charge sessions, which
--   row security withholds as tables from a caller with no staff, fleet or retail row (§2), (iii) the 17 run-scoped
--   relations it cannot read as tables at all (§2), and (iv) the rest of the run in a single request that first sets a
--   150 s statement timeout.
--   WHAT IT DOES NOT CLOSE: the table door. 76 of the 93 run-scoped relations the export reads stay open to a
--   signed-in caller through /rest/v1/<relation>, ottoq_sim_runs and ottoq_telemetry_packets among them, and
--   ottoq_schema_snapshots holds earlier versions of 45 of the 49 function sources (§2). Do not quote this file as
--   closing signed-in read access to run data. That is G438, OPEN.
--   Applying it is a step of G435's deploy, which FINDINGS leaves to Chase. Its order against the deploy does not matter:
--   the deployed v7 (index.ts:32,42 before #243) and #243's handler (_shared/run_blackbox.ts:150,160) both call
--   ottoq_run_blackbox_meta with a client built from SUPABASE_SERVICE_ROLE_KEY, which is the service_role this file
--   keeps. Neither calls ottoq_run_blackbox.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) WHAT THE TWO RETURN (db/checks/0446 §1 (d), §5 (a); both definitions read in the window above).
--       ottoq_run_blackbox(uuid), md5 4f96d37ef15bcf3fac9a79023f99c729, STABLE SECURITY DEFINER, owner postgres:
--         the monolithic v1 bundle. It returns the run's row; every public relation named ottoq% that has a sim_run_id
--         column, up to 200,000 rows each; the depot's vehicles, stalls and charge sessions; and `executed_code`, the
--         full source of the 49 engine functions its pattern matches. It sets a 150 s transaction-local
--         statement_timeout first ("export can take a moment to assemble; give it room"), so it is a load lever as well
--         as a read.
--       ottoq_run_blackbox_meta(uuid), md5 06ec6069b1f08a5ce51a18e2e2764123, STABLE SECURITY DEFINER, owner postgres:
--         the run's row, its depot, the same 49 function sources, and the list of relations the export reads.
--   (b) WHO MAY CALL THEM, AS READ. Both carry ACL {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}.
--       anon: no (no grant and no PUBLIC entry). authenticated: yes. ottoq_sim_runs holds production_live runs beside
--       the twin's (9, 8 of them at the twin depot, read in the window), so once telemetry flows this door would hand a
--       signed-in caller a production run whole, in one call, with the engine's current source. It is not the only
--       door to that data: most of the same rows stay readable to the same caller through /rest/v1/<relation> (§2 NOT
--       CHANGED, G438), so what this file removes is the one-call export and the parts §0 (i)-(iii) name, not
--       signed-in read access to run data. Sign-up is open per G428 (the study read the Auth setting on 2026-10-13; no
--       SQL path reads it, so it is not re-measured here), and the field-ops demo logins share one password in a public
--       repo (G393/G394).
--   (c) WHO CALLS THEM, MEASURED.
--       - In the database: no function in any schema except pg_catalog and information_schema names either one,
--         comment-stripped, other than the two themselves (P1 asserts it). No view, policy, column default or other
--         object depends on either in pg_depend. No trigger runs either. No cron job's command names "blackbox", and every
--         cron job runs as postgres, which keeps its owner's EXECUTE in any case. The one other function that
--         mentions "blackbox" is ottoq_sim_release_depot, and it only returns a JSON key, 'blackbox_ready'.
--       - Edge functions: ottoq-run-blackbox, as §0 says, calls the meta read only, as service_role.
--       - Apps: no code in any repository under /home/user calls either RPC. The twin app reaches the export only
--         through the edge function (ottoyarddepot-sim src/lib/blackbox.ts downloadBlackbox). The only other mention is
--         an example in ottoyard-agent-context docs/08_DEVELOPMENT.md:101, which runs in the SQL editor as postgres.
--       - Logs: one request is unexplained. edge_logs records POST rpc/ottoq_run_blackbox_meta, status 400, from the
--         edge runtime at 2026-10-13 13:58:18 UTC, with no matching function_edge_logs row (the study's black-box lane).
--         A 400 returned no data. If that caller holds the service-role key it keeps working; if it sent a user's token,
--         it is refused after this file.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   On the two signatures: REVOKE EXECUTE FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role. The GRANT is
--   explicit, as in 0648 and 0701, so service_role keeps the right however it held it. postgres keeps its owner's
--   right. NEITHER DEFINITION IS TOUCHED: there is no CREATE OR REPLACE, so no anchored patch is needed, and V3 asserts
--   that both md5s are unchanged.
--   NOT CHANGED:
--     - public.ottoq_blackbox_latest_run(). anon, authenticated and service_role may execute it. It returns only the
--       latest operator_demo run's id, scenario, status, tick count and demo speed, and no run data.
--     - The edge function's own credential: #243, merged, not yet deployed.
--     - The 124 VOLATILE SECURITY DEFINER functions a browser role may still execute (db/checks/0438 (4)). These two
--       are STABLE, so they are not in that census. 0701 (pending) neither touches them nor counts them, and in either
--       apply order neither file's verification sees the other's change.
--     - THE TABLE DOOR (FINDINGS G438, OPEN). Measured read-only on live, 2026-10-14 16:34:47-16:37:57 UTC (11:34-11:37
--       AM CT), each query's own now(). The export reads 93 relations: those in public named ottoq% with a sim_run_id
--       column (72 tables, 21 views). authenticated holds SELECT on 78 of them; on 2 of those row security has no
--       policy for it, so 76 are open to a signed-in caller:
--         * 67 return every row to anyone signed in: 31 tables with row security off (ottoq_stall_bookings,
--           ottoq_visit_needs, ottoq_vehicle_itineraries, ottoq_recall_decisions, ottoq_comms_messages,
--           ottoq_model_call_ledger and 25 more; about 4.30 million rows by reltuples), 13 views owned by postgres
--           without security_invoker (postgres has BYPASSRLS), 18 tables under a SELECT policy USING (true)
--           (ottoq_decisions, ottoq_decision_snapshots, ottoq_events, ottoq_agent_charge_orders, ...), and 5 under a
--           policy every signed-in caller passes, auth.role() IN ('authenticated', 'service_role'): ottoq_sim_runs,
--           ottoq_telemetry_packets, ottoq_ocpp_messages, ottoq_vehicle_dispatches, ottoq_vehicle_incidents;
--         * 9 depend on the caller or on the tables beneath them: 7 security_invoker views read through their
--           tables' row security; ottoq_rule_evaluations returns the rows with no fleet operator plus the caller's own;
--           ottoq_vehicle_commands returns the caller's depot only (none to a caller with no staff_users row).
--       The other 17 return nothing to a signed-in caller, which is what this file's REVOKE takes from the RPC: 15 with
--       no grant (among them ottoq_owner_commands, ottoq_owner_settings, ottoq_agent_requests, ottoq_v2_inbox,
--       ottoq_run_archives and ottoq_vehicle_wear) and 2 with row security on and no policy for authenticated
--       (ottoq_service_detail_records, ottoq_rider_cleaning_flags). Of the depot's three, stalls is readable whole
--       (policy "client keys read only" TO anon, authenticated USING (true)); vehicles returns only the caller's
--       fleet's, retail membership's or depot's (none to someone who just signed up); ocpp_sessions has no policy for
--       authenticated, so none.
--       The engine's source: ottoq_schema_snapshots (row security off, SELECT to authenticated, none to anon) holds
--       7,654 rows, 1,404 of them function definitions as they stood before a migration changed them, 625 function
--       names in all and 45 of the 49 the export's executed_code returns. Those are earlier versions, not necessarily the
--       current ones; the RPC handed over the current 49 in one call. This file's own 0720_pre rows (both export
--       definitions and its GRANT statements) will be readable there too.
--       How the door is used: PostgREST serves public (the twin app reads its tables through /rest/v1, 0658 §1), and
--       the authenticator role carries statement_timeout 8s, so the table door reads a run one bounded request per
--       relation at a time rather than in one call.
--       The remedy is the authenticated-role census 0701 §2 defers ("the next file, after the signed-in UIs that use
--       any of them are named"), carried to relations as 0658 did for anon: name every signed-in reader, then REVOKE
--       the rest and default-deny new tables to authenticated.
--       RE-READ 2026-10-14 17:34:00-17:34:36 UTC (12:34 PM CT), each query's own now(), the same way: every count above
--       unchanged (93 = 72 + 21; 78 granted; 31 + 13 + 18 + 5 every row, 7 + 2 caller-dependent, 2 with no policy, 15
--       with no grant; 7,654 snapshot rows, 1,404 function definitions, 625 schema-qualified names, 45 of 49 sources;
--       stalls, vehicles and ocpp_sessions policies as stated), except reltuples on the 31 tables, now about 4.31
--       million. Both md5s and both ACLs still read as P1 pins them.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   No atom reads a grant. No function body changes (V3). No tick path, certification path or cron job calls either
--   function (§1 (c)), and the engine runs as postgres or service_role, both of which keep EXECUTE.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0720_pre' AND object_kind = 'grant', in
--   snapshot_id order: one GRANT per (function, PUBLIC, anon or authenticated) entry this file took. Today that is
--   authenticated on both. The function rows under the same label are the definitions as they stood, which this file
--   does not change, kept for the record. Rolling back re-opens the export to everyone who signs up.
--
-- ══ §5 THE DRY RUN, READ-ONLY, AGAINST LIVE ══════════════════════════════════════════════════════════════════════
--
--   P0 and P1 were run by hand as plain SELECTs at 14:59:44 UTC (9:59 AM CT); this session runs nothing but SELECT
--   against live.
--   - P0 read 1. The recertification runner (pg_cron, in its transaction since 14:58:13 UTC) was certifying, so an
--     apply in that minute would have refused at P0. That is P0 doing its job: apply when it reads 0.
--   - P1 held on every premise as written. There is no 0720 lineage row and no 0720_pre snapshot. The md5s are
--     4f96d37e... and 06ec6069.... Both functions are postgres-owned SECURITY DEFINER with ACL
--     {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}. The comment-stripped census over the
--     2,071 functions outside pg_catalog and information_schema found no caller. pg_depend holds no dependent. The
--     probe's run id is no run's.
--   - P2 and the V blocks switch role and call the functions, which a SELECT cannot do. They run on the stub
--     (tests/test_blackbox_rpc_grants_sql.py, which applies this file) and in the file itself at apply.
--   Mutation-checked on the stub, each on a copy, each refused: without the REVOKE, V1 FAILED; revoking from PUBLIC
--   and anon only, V1 FAILED; revoking service_role too, V1 FAILED; the probe calling the functions as PL/pgSQL
--   expressions instead of through EXECUTE, P2 refused (anon read as answered).

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0720 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE
  v_bad text;
  v_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0720\_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_schema_snapshots WHERE label = '0720_pre') THEN
    RAISE EXCEPTION '0720 P1: 0720 has run already';
  END IF;
  IF to_regprocedure('public.ottoq_run_blackbox(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_run_blackbox_meta(uuid)') IS NULL THEN
    RAISE EXCEPTION '0720 P1: one of the two export functions does not exist';
  END IF;
  -- the definitions, byte for byte as read
  IF md5(pg_get_functiondef('public.ottoq_run_blackbox(uuid)'::regprocedure)) <> '4f96d37ef15bcf3fac9a79023f99c729' THEN
    RAISE EXCEPTION '0720 P1: ottoq_run_blackbox is not the definition this file was written against (md5 %)',
      md5(pg_get_functiondef('public.ottoq_run_blackbox(uuid)'::regprocedure));
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_run_blackbox_meta(uuid)'::regprocedure)) <> '06ec6069b1f08a5ce51a18e2e2764123' THEN
    RAISE EXCEPTION '0720 P1: ottoq_run_blackbox_meta is not the definition this file was written against (md5 %)',
      md5(pg_get_functiondef('public.ottoq_run_blackbox_meta(uuid)'::regprocedure));
  END IF;
  -- SECURITY DEFINER, owned by postgres, and the ACL as read (the defect: authenticated may execute)
  SELECT string_agg(p.oid::regprocedure::text || ' ' || COALESCE(p.proacl::text, 'NULL'), '; ') INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('public.ottoq_run_blackbox(uuid)'::regprocedure, 'public.ottoq_run_blackbox_meta(uuid)'::regprocedure)
     AND (NOT p.prosecdef OR p.proowner <> 'postgres'::regrole OR p.proacl IS NULL OR p.proacl::text <> v_acl);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0720 P1: not a postgres-owned SECURITY DEFINER function with ACL %: %', v_acl, v_bad;
  END IF;
  -- no other function names either one (comment-stripped: a mention in a comment is not a call; a name in a string,
  -- as dynamic SQL would carry it, is)
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
     AND p.oid NOT IN ('public.ottoq_run_blackbox(uuid)'::regprocedure, 'public.ottoq_run_blackbox_meta(uuid)'::regprocedure)
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~* 'ottoq_run_blackbox';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0720 P1: a function now calls the export functions; read it before revoking: %', v_bad;
  END IF;
  -- nor does a view, a policy, a column default or anything else that records a dependency (a browser role querying a
  -- view needs EXECUTE on the functions it calls)
  SELECT string_agg(DISTINCT pg_describe_object(d.classid, d.objid, d.objsubid), ', ') INTO v_bad
    FROM pg_depend d
   WHERE d.refclassid = 'pg_proc'::regclass
     AND d.refobjid IN ('public.ottoq_run_blackbox(uuid)'::regprocedure, 'public.ottoq_run_blackbox_meta(uuid)'::regprocedure)
     AND d.classid <> 'pg_proc'::regclass;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0720 P1: an object depends on the export functions: %', v_bad;
  END IF;
  -- the probes below ask for a run that does not exist, so they read no run's data
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = '00000000-0000-4000-8000-000000000720') THEN
    RAISE EXCEPTION '0720 P1: the probe run id belongs to a run';
  END IF;
END $premises$;

-- ── the probe: as one role, call both functions for a run that does not exist; rolled back either way ──
-- 'answered' means the function ran and returned (for an unknown run the bundle answers {"error":"run not found"} after
-- one indexed read, and the meta read answers the run as null); 'refused' means EXECUTE was denied (42501).
-- The calls go through EXECUTE, never as a PL/pgSQL expression. PL/pgSQL keeps a simple expression's executor state
-- for the rest of the transaction once it has run, and EXECUTE permission on a function is checked when that state
-- is built, so a second call as another role would reuse the first role's check. Measured on the stub while writing
-- this file: called that way, P2 read anon as 'answered' right after authenticated. EXECUTE plans each call afresh,
-- so every role is checked as itself.
CREATE FUNCTION pg_temp.p0720_as(p_role text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('role', p_role, true);
    DECLARE
      v_bundle text; v_meta text;
    BEGIN
      BEGIN
        EXECUTE 'SELECT CASE WHEN public.ottoq_run_blackbox($1) IS NOT NULL THEN ''answered'' ELSE ''null'' END'
          INTO v_bundle USING '00000000-0000-4000-8000-000000000720'::uuid;
      EXCEPTION WHEN insufficient_privilege THEN v_bundle := 'refused';
      END;
      BEGIN
        EXECUTE 'SELECT CASE WHEN public.ottoq_run_blackbox_meta($1) IS NOT NULL THEN ''answered'' ELSE ''null'' END'
          INTO v_meta USING '00000000-0000-4000-8000-000000000720'::uuid;
      EXCEPTION WHEN insufficient_privilege THEN v_meta := 'refused';
      END;
      -- current_user is the control: it proves the role switch happened
      RAISE EXCEPTION 'AS %|user %|bundle %|meta %', p_role, current_user, v_bundle, v_meta;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

CREATE TEMP TABLE p0720 (phase text PRIMARY KEY, r text) ON COMMIT DROP;

-- ── P2: the defect, as each role: a signed-in caller gets both answers; the public key does not; the platform does ──
DO $before$
DECLARE
  v_auth text := pg_temp.p0720_as('authenticated');
  v_anon text := pg_temp.p0720_as('anon');
  v_svc text := pg_temp.p0720_as('service_role');
BEGIN
  IF v_auth IS DISTINCT FROM 'AS authenticated|user authenticated|bundle answered|meta answered'
     OR v_anon IS DISTINCT FROM 'AS anon|user anon|bundle refused|meta refused'
     OR v_svc IS DISTINCT FROM 'AS service_role|user service_role|bundle answered|meta answered' THEN
    RAISE EXCEPTION '0720 P2: before this file, as each role: % / % / % (expected authenticated and service_role answered, anon refused)',
      v_auth, v_anon, v_svc;
  END IF;
  INSERT INTO p0720 VALUES ('as_authenticated_before', v_auth);
  RAISE NOTICE '0720 P2: before: %; %; %', v_auth, v_anon, v_svc;
END $before$;

-- ── snapshot: both definitions as they stand, and one GRANT per (function, PUBLIC, anon or authenticated) taken ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0720_pre', 'function', 'public', f.sig, d.def, md5(d.def)
  FROM (VALUES ('ottoq_run_blackbox(uuid)'), ('ottoq_run_blackbox_meta(uuid)')) AS f(sig)
  CROSS JOIN LATERAL (SELECT pg_get_functiondef(('public.' || f.sig)::regprocedure) AS def) d
 ORDER BY f.sig;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0720_pre', 'grant', 'public', g.sig || '::' || g.grantee, g.stmt, md5(g.stmt)
  FROM (SELECT p.oid::regprocedure::text AS sig,
               CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
               format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO %s;', p.proname, pg_get_function_identity_arguments(p.oid),
                      CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END) AS stmt
          FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
         WHERE p.oid IN ('public.ottoq_run_blackbox(uuid)'::regprocedure, 'public.ottoq_run_blackbox_meta(uuid)'::regprocedure)
           AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR a.grantee IN ('anon'::regrole, 'authenticated'::regrole))
         ORDER BY 1, 2) g;

-- ── the change: closed to PUBLIC and the browser roles, kept for the platform ──
REVOKE EXECUTE ON FUNCTION public.ottoq_run_blackbox(uuid), public.ottoq_run_blackbox_meta(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_run_blackbox(uuid), public.ottoq_run_blackbox_meta(uuid) TO service_role;

-- ── V1: the catalog: no PUBLIC, no browser role; service_role and the owner keep both ──
DO $vone$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text || ' ' || COALESCE(p.proacl::text, 'NULL'), '; ') INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('public.ottoq_run_blackbox(uuid)'::regprocedure, 'public.ottoq_run_blackbox_meta(uuid)'::regprocedure)
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
          OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
          OR NOT has_function_privilege('postgres', p.oid, 'EXECUTE')
          OR p.proacl IS NULL
          OR p.proacl::text <> '{postgres=X/postgres,service_role=X/postgres}');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0720 V1 FAILED: grants not as written: %', v_bad;
  END IF;
  RAISE NOTICE '0720 V1 PASSED: both ACLs read {postgres=X/postgres,service_role=X/postgres}';
END $vone$;

-- ── V2: as each role: authenticated and anon are refused (42501); service_role still gets both answers ──
DO $vtwo$
DECLARE
  v_auth text := pg_temp.p0720_as('authenticated');
  v_anon text := pg_temp.p0720_as('anon');
  v_svc text := pg_temp.p0720_as('service_role');
BEGIN
  IF v_auth IS DISTINCT FROM 'AS authenticated|user authenticated|bundle refused|meta refused'
     OR v_anon IS DISTINCT FROM 'AS anon|user anon|bundle refused|meta refused'
     OR v_svc IS DISTINCT FROM 'AS service_role|user service_role|bundle answered|meta answered' THEN
    RAISE EXCEPTION '0720 V2 FAILED: % / % / %', v_auth, v_anon, v_svc;
  END IF;
  RAISE NOTICE '0720 V2 PASSED: before: %; after: %; %; %; rolled back',
    (SELECT r FROM p0720 WHERE phase = 'as_authenticated_before'), v_auth, v_anon, v_svc;
END $vtwo$;

-- ── V3: neither definition moved: the same md5s, and the same as the snapshot just taken ──
DO $vthree$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_run_blackbox(uuid)'::regprocedure)) <> '4f96d37ef15bcf3fac9a79023f99c729'
     OR md5(pg_get_functiondef('public.ottoq_run_blackbox_meta(uuid)'::regprocedure)) <> '06ec6069b1f08a5ce51a18e2e2764123'
     OR (SELECT count(*) FROM public.ottoq_schema_snapshots s
          WHERE s.label = '0720_pre' AND s.object_kind = 'function'
            AND s.def_md5 = md5(pg_get_functiondef(('public.' || s.object_name)::regprocedure))) <> 2 THEN
    RAISE EXCEPTION '0720 V3 FAILED: a definition changed';
  END IF;
  RAISE NOTICE '0720 V3 PASSED: both definitions unchanged (4f96d37e, 06ec6069)';
END $vthree$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0720_a_signed_in_user_cannot_call_the_black_box_export_functions', false, false,
  'G435 (b), db/checks/0446 §5 (a): REVOKE EXECUTE FROM PUBLIC, anon and authenticated on ottoq_run_blackbox(uuid) and '
  'ottoq_run_blackbox_meta(uuid), both SECURITY DEFINER, which gave anyone who signs up a whole run and the engine''s '
  'current source in one call through /rest/v1/rpc. Closes the RPC door only: 76 of the 93 run-scoped relations the '
  'export reads stay open to a signed-in caller through /rest/v1/<relation> (§2, G438, OPEN). service_role keeps both '
  '(the ottoq-run-blackbox edge function calls the meta read as service_role). Privileges only; neither definition '
  'changes (V3); no tick, certification or cron path calls either: FALSE/FALSE.',
  now());

COMMIT;
