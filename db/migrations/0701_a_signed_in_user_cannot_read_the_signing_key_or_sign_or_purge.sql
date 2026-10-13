-- migration-version: PENDING
-- migration-name:    a_signed_in_user_cannot_read_the_signing_key_or_sign_or_purge
--
-- 0701  **Anyone who signs up could read the key that signs every event, SDR and audit bundle, sign anything with it,
--        and purge or start runs. Those doors are closed to the browser roles, the key is no longer cached for a
--        whole pooled session, and a new function in public is no longer callable by them until a migration says so.**
--        (FINDINGS draft G421; closes the grant half of G417. db/checks/0438.) Measured read-only on 2026-10-13 on the
--        live catalog and the API logs, ending 15:19 UTC (10:19 AM CT, read from the clock after the last query); the
--        P0/P1 dry-run read now() = 15:10:32 UTC and passed.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) THE KEY. public.ottoq_resolve_signing_secret(text) is SECURITY DEFINER and returns the decrypted Vault secret
--       of a signing key. There is one key, 'system:v1', active and Vault-backed: it is the HMAC key ottoq_sign_event
--       (through ottoq_record_event) puts on every event, ottoq_sign_sdr (through ottoq_emit_sdr) on every SDR (136,222
--       of 136,222 signed, read in the window above) and ottoq_sign_bundle on every audit bundle. Its ACL is
--       {postgres=X,service_role=X,authenticated=X}: any caller holding a signed-in JWT reads it with one POST to
--       /rest/v1/rpc/ottoq_resolve_signing_secret. Sign-up is open (the lead read the Auth setting, disable_signup =
--       false; no SQL path reads it, so it is not re-measured here); auth.users holds 7 accounts, all confirmed.
--       How it got there: ottoq_grant_snapshot_0198 records that 0198 (2026-09-06 03:21:56 UTC) found the resolver,
--       ottoq_sign_event, ottoq_record_event and ottoq_purge_prior_runs at {postgres=X,service_role=X} and GRANTED
--       them to authenticated: 0198 re-granted authenticated on every public SECURITY DEFINER function that was not on
--       its control-plane list, and none of these was. ottoq_record_event's own COMMENT still reads "NOT
--       client-callable: EXECUTE revoked from PUBLIC/anon/authenticated on 2026-07-30".
--
--   (b) THE ORACLES. ottoq_sign_event, ottoq_sign_sdr and ottoq_sign_bundle return the HMAC of fields the caller
--       chooses, under the system key: a signature on anything. ottoq_oem_deliver_live is wider: it reads ANY Vault
--       secret by a caller-supplied name (p_secret_ref; Vault holds 6), signs a caller-chosen payload with it, POSTs it
--       to a caller-chosen URL through pg_net and logs the delivery. ottoq_record_event writes a signed event whose
--       actor, type, entity and payload the caller chooses; ottoq_emit_sdr a signed SDR; ottoq_generate_audit_bundle
--       and ottoq_complete_audit_report signed audit artefacts.
--
--   (c) THE DESTRUCTIVE DOORS. To authenticated: ottoq_purge_prior_runs (deletes every non-production run's rows in
--       every engine table, G417), ottoq_start_busy_run and ottoq_start_busy_run_once (start runs), the three
--       ottoq_energy_mpc_replan overloads (POST to the optimizer and write plans). To anon, authenticated and PUBLIC,
--       because they were created after 0198 and kept Supabase's defaults: ottoq_release_unusable_reservations
--       (releases stall reservations), ottoq_fit_charge_fault_model (writes a fault-model fit; it is the one row
--       ottoq_assert_anon_rpc_surface() returns today) and ottoq_probe_task_completion (writes rule evaluations).
--
--   (d) THE SESSION CACHE. Before Vault, the resolver believes two settings, 'ottoq.signing_secret_<key>' and, for
--       system:v1, 'ottoq.signing_secret_default', and it caches the decrypted secret in the first with
--       set_config(name, secret, false): SESSION scope, so on a pooled connection the key outlives the request.
--       Nothing sets either: pg_db_role_setting holds no ottoq.* entry, no function but the resolver names them, and no
--       code or config file in the local OTTOYARD clones does. Whatever sets them for a session signs as the system.
--       The residue in pooled sessions is not readable through the API (placeholder settings are not in pg_settings,
--       measured on PG16, and the only function in public, twin or ottoq that reads a setting by a computed name is
--       the resolver itself), but it has no reason to exist.
--
--   (e) THE DEFAULT. postgres's per-schema default in public grants EXECUTE on every new function to anon,
--       authenticated and service_role, and PostgreSQL's built-in default grants it to PUBLIC. That is how (c)'s last
--       three reached anon, and 0406 named it a standing tax. A per-schema REVOKE cannot remove the PUBLIC grant:
--       "Default privileges that are specified per-schema are added to whatever the global default privileges are for
--       the particular object type. This means you cannot revoke privileges per-schema if they are granted globally
--       (either by default, or according to a previous ALTER DEFAULT PRIVILEGES command that did not specify a
--       schema)", and the page's own example, ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS
--       FROM PUBLIC, "has no effect, unless it is undoing a matching GRANT" (PostgreSQL 17, ALTER DEFAULT PRIVILEGES,
--       https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html, read 2026-10-13; the engine runs 17.6).
--       Supabase's guides recommend exactly that per-schema line (https://supabase.com/docs/guides/database/functions,
--       "Function privileges", and https://supabase.com/docs/guides/api/securing-your-api, both read 2026-10-13).
--       Reproduced on PostgreSQL 16.15: after IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon,
--       authenticated, a new function's ACL is {=X/postgres,postgres=X/postgres,service_role=X/postgres} and anon may
--       execute it. Only the global form removes PUBLIC.
--
--   WHO CALLS THESE, MEASURED.
--     - In the database: every caller of the resolver and the three signers is SECURITY DEFINER and owned by postgres
--       (sign_event: record_event, complete_audit_report, verify_event_signature; sign_sdr: emit_sdr; sign_bundle:
--       generate_audit_bundle, verify_audit_bundle; the resolver: the three signers), so it runs as the owner and a
--       revoke from the browser roles cannot reach it. Of the other targets, every caller is SECURITY DEFINER except
--       thirteen SECURITY INVOKER ones (twelve of ottoq_record_event, one of ottoq_emit_sdr): four are row triggers
--       (vehicles, stalls, schedule_tasks, ottoq_itinerary_legs) on tables neither browser role may INSERT or UPDATE;
--       two are not executable by them (ottoq.ottoq_v2_apply, twin.ottoq_sim_advance_service_flow) and one sits in
--       twin, where they have no USAGE (twin.ottoq_sim_departure_recheck); the remaining six (ottoq_cil_tick,
--       ottoq_mpc_lookahead, ottoq_mpc_energy_lookahead, ottoq_predict_arrivals, ottoq_production_start,
--       ottoq_production_stop) already fail at ottoq_record_event when anon calls them, and now fail the same way for
--       authenticated, which is the point: a signed-in browser should not start production or tick the engine.
--     - pg_cron: 22 jobs, every one as postgres; job 790 runs ottoq_fit_charge_fault_model.
--     - Apps and edge functions: otto-twin-control calls ottoq_record_event with the service-role key; the Python
--       calibration ingest emits SQL an operator runs. No browser code in the local clones of ottoyarddepot-sim,
--       ottoyard-field-ops, OTTOYARD, ottoyard-OTTO-Q or OTTOYARD-SITE names any of the sixteen.
--     - The API logs, 2026-10-10 15:06 UTC to 2026-10-13 14:50 UTC (all the logs hold): no request for any of the
--       sixteen from any role; the only signed-in (authenticated) RPC requests were 10, to 0700's sign-in doors.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) On the eighteen signatures (sixteen names; ottoq_energy_mpc_replan has three overloads): REVOKE EXECUTE FROM
--       PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role (explicitly, so an ACL that reached service_role
--       only through PUBLIC keeps it). postgres keeps its owner's right.
--   (b) The resolver: the two setting overrides go. The cache is set with set_config(..., true), so it lives for one
--       transaction, under a name no earlier version wrote ('ottoq.sigcache_' || md5(key)), beside a stamp of the
--       transaction's start, and it is believed only when the stamp matches this transaction: a value left in an old
--       pooled session is never read again, and a session that pre-sets the name is ignored. The Vault lookup is
--       unchanged, so it returns the same secret and every signature is byte-identical (V4). A tick is one
--       transaction, so the new cache decrypts at most once per tick; the old one saved that one decrypt only when a
--       session outlived its tick. A pair runs both arms in one transaction, so it decrypts once, as before.
--   (c) Default privileges for functions postgres creates later:
--         IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated   (undoes Supabase's per-schema grant)
--         REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC   (global: the only form that removes PostgreSQL's built-in grant)
--         IN SCHEMA twin, ottoq GRANT EXECUTE ON FUNCTIONS TO service_role
--         IN SCHEMA extensions GRANT EXECUTE ON FUNCTIONS TO PUBLIC
--       The last two put back what the global line would otherwise take outside public: in twin and ottoq only postgres
--       and service_role hold USAGE, so PUBLIC there meant service_role; extensions keeps PUBLIC. A new function in
--       public is then {postgres, service_role}; a function a browser calls is granted in the file that creates it,
--       naming its reader (0658's rule for tables, now for functions; 0700 already does this). In a schema postgres
--       creates later, a new function is the owner's alone. An extension postgres installs INTO public would need
--       grants too.
--   NOT CHANGED: the 124 other VOLATILE SECURITY DEFINER functions in public a browser role may still execute (for 112
--   of them no migration names a signed-in reader; db/checks/0438 (4) lists every one with its basis). Among them are
--   ottoq_promote_dials, ottoq_decide_tick, ottoq_archive_run, ottoq_benchmark_reset, ottoq_sim_run_scenario and
--   ottoq_cuopt_refresh, which sends a Vault-keyed NVIDIA call. That is the next file, after the signed-in UIs that use
--   any of them are named. No secret is rotated and no Auth setting is changed here: both are Chase's (FINDINGS G421).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   No atom reads a signature or a grant: h_evt digests event_type|entity|sim_clock_at, h_sdr is
--   ottoq_hash_sdrs (no "signature" or signing call in its source), and the decision frame's payload names none
--   (measured on the live sources 2026-10-13). The resolver returns the same Vault secret, so every signature is byte
--   for byte what it was (V4 asserts it on synthetic inputs, before against after). The engine runs as postgres (cron,
--   and every in-database caller is SECURITY DEFINER) or service_role (kept). Default privileges touch only functions
--   created later.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0701_pre', in snapshot_id order: the resolver as
--   it was, one GRANT per (function, browser role or PUBLIC) this file took, and the default privileges as they stood.
--   Rolling back re-opens the key to every signed-in caller; rotate the key first if it may have been read.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0701 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── the eighteen signatures this file closes (qual: schema-qualified with argument names, whatever the search_path) ──
CREATE TEMP TABLE p0701_targets (sig regprocedure PRIMARY KEY, qual text) ON COMMIT DROP;
INSERT INTO p0701_targets (sig, qual)
SELECT to_regprocedure(s),
       (SELECT format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE p.oid = to_regprocedure(s))
  FROM unnest(ARRAY[
  'public.ottoq_resolve_signing_secret(text)',
  'public.ottoq_sign_event(uuid,timestamptz,text,text,text,uuid,text,text)',
  'public.ottoq_sign_sdr(uuid,timestamptz,uuid,text,text,text)',
  'public.ottoq_sign_bundle(uuid,timestamptz,timestamptz,text,text)',
  'public.ottoq_oem_deliver_live(uuid,uuid,uuid,uuid,text,text,jsonb,text,timestamptz)',
  'public.ottoq_energy_mpc_replan(uuid,uuid,integer,numeric,numeric[],integer,text,text)',
  'public.ottoq_energy_mpc_replan(uuid,uuid,integer,numeric,numeric[],integer,text,text,timestamptz)',
  'public.ottoq_energy_mpc_replan(uuid,uuid,integer,numeric,numeric[],integer,text,text,timestamptz,uuid)',
  'public.ottoq_purge_prior_runs(uuid)',
  'public.ottoq_start_busy_run(numeric,integer,bigint)',
  'public.ottoq_start_busy_run_once(text,numeric,integer,bigint)',
  'public.ottoq_release_unusable_reservations(uuid,timestamptz,uuid)',
  'public.ottoq_fit_charge_fault_model(uuid,timestamptz,interval,text)',
  'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,integer,text,text,text,uuid)',
  'public.ottoq_emit_sdr(text,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,text)',
  'public.ottoq_generate_audit_bundle(uuid,uuid[],text,timestamptz,timestamptz,text,text,bigint,text,text,text,text,timestamptz)',
  'public.ottoq_complete_audit_report(uuid,jsonb,bigint,bigint,bigint,bigint,bigint,bigint,bigint,boolean,numeric,text)',
  'public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamptz,timestamptz)']) s
WHERE to_regprocedure(s) IS NOT NULL;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE
  v_names text[] := ARRAY['ottoq_resolve_signing_secret', 'ottoq_sign_event', 'ottoq_sign_sdr', 'ottoq_sign_bundle',
                          'ottoq_oem_deliver_live', 'ottoq_energy_mpc_replan', 'ottoq_purge_prior_runs',
                          'ottoq_start_busy_run', 'ottoq_start_busy_run_once', 'ottoq_release_unusable_reservations',
                          'ottoq_fit_charge_fault_model', 'ottoq_record_event', 'ottoq_emit_sdr',
                          'ottoq_generate_audit_bundle', 'ottoq_complete_audit_report', 'ottoq_probe_task_completion'];
  -- the six SECURITY INVOKER callers of ottoq_record_event a browser role may execute, read in §1; any other is new
  v_reviewed text[] := ARRAY['public.ottoq_cil_tick', 'public.ottoq_mpc_lookahead', 'public.ottoq_mpc_energy_lookahead',
                             'public.ottoq_predict_arrivals', 'public.ottoq_production_start', 'public.ottoq_production_stop'];
  v_n int; v_bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0700_an_owner_signs_in_and_connects_their_own_agent') THEN
    RAISE EXCEPTION '0701 P1: 0700 is not classified; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0701\_%')
     OR EXISTS (SELECT 1 FROM public.ottoq_schema_snapshots WHERE label = '0701_pre') THEN
    RAISE EXCEPTION '0701 P1: 0701 has run already';
  END IF;
  -- every target exists, and no overload of the sixteen names is missing from the list
  SELECT count(*) INTO v_n FROM p0701_targets;
  IF v_n <> 18 THEN
    RAISE EXCEPTION '0701 P1: % of the 18 signatures exist', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = ANY (v_names);
  IF v_n <> 18 THEN
    RAISE EXCEPTION '0701 P1: the sixteen names have % overloads in public, not 18; one is not on the list', v_n;
  END IF;
  SELECT string_agg(t.sig::text, ', ') INTO v_bad
    FROM p0701_targets t JOIN pg_proc p ON p.oid = t.sig
   WHERE NOT p.prosecdef OR p.proowner <> 'postgres'::regrole OR p.prokind <> 'f';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0701 P1: not a SECURITY DEFINER function owned by postgres: %', v_bad;
  END IF;
  -- the defect: a signed-in caller may execute every one of them
  SELECT string_agg(t.sig::text, ', ') INTO v_bad FROM p0701_targets t
   WHERE NOT has_function_privilege('authenticated', t.sig, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0701 P1: authenticated may no longer execute %; the premise moved, re-read', v_bad;
  END IF;
  -- the resolver is the definition this file replaces
  IF md5(pg_get_functiondef('public.ottoq_resolve_signing_secret(text)'::regprocedure)) <> 'b92997a8bcbc41b3c825ad11407c1f66' THEN
    RAISE EXCEPTION '0701 P1: the resolver is not the definition this file replaces (md5 %)',
      md5(pg_get_functiondef('public.ottoq_resolve_signing_secret(text)'::regprocedure));
  END IF;
  -- the key the engine signs with is Vault-backed, so dropping the setting overrides leaves the engine its secret
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_signing_keys k WHERE k.key_id = 'system:v1' AND k.is_active
                    AND k.secret_ref LIKE 'vault:%') THEN
    RAISE EXCEPTION '0701 P1: system:v1 is not an active Vault-backed key';
  END IF;
  -- nothing sets the overrides for a role or a database
  IF EXISTS (SELECT 1 FROM pg_db_role_setting s, unnest(s.setconfig) c WHERE c ILIKE 'ottoq.signing%') THEN
    RAISE EXCEPTION '0701 P1: a role or database setting sets an ottoq.signing_* override; find what reads it first';
  END IF;
  -- every caller of the resolver and the three signers runs as its owner
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND NOT p.prosecdef
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~ '\m(ottoq_resolve_signing_secret|ottoq_sign_event|ottoq_sign_sdr|ottoq_sign_bundle)\s*\(';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0701 P1: SECURITY INVOKER callers of the resolver or a signer: %', v_bad;
  END IF;
  -- a SECURITY INVOKER caller of any target that a browser role can reach is a trigger on a table it cannot write, or
  -- one of the six read in §1
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND NOT p.prosecdef
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~ ('\m(' || array_to_string(v_names, '|') || ')\s*\(')
     AND CASE WHEN p.prorettype = 'trigger'::regtype THEN
                EXISTS (SELECT 1 FROM pg_trigger tg, unnest(ARRAY['anon', 'authenticated']) r(rname)
                         WHERE tg.tgfoid = p.oid AND NOT tg.tgisinternal
                           AND (has_any_column_privilege(r.rname, tg.tgrelid, 'INSERT')
                                OR has_any_column_privilege(r.rname, tg.tgrelid, 'UPDATE')))
              ELSE EXISTS (SELECT 1 FROM unnest(ARRAY['anon', 'authenticated']) r(rname)
                            WHERE has_function_privilege(r.rname, p.oid, 'EXECUTE')
                              AND has_schema_privilege(r.rname, p.pronamespace, 'USAGE'))
                   AND (n.nspname || '.' || p.proname) <> ALL (v_reviewed)
         END;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0701 P1: a browser role reaches a target through a SECURITY INVOKER caller not read in §1: %', v_bad;
  END IF;
  -- cron runs as postgres
  IF to_regclass('cron.job') IS NOT NULL THEN
    EXECUTE 'SELECT string_agg(DISTINCT username, '', '') FROM cron.job WHERE username <> ''postgres''' INTO v_bad;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION '0701 P1: cron jobs run as %, not only postgres', v_bad;
    END IF;
  END IF;
  -- the default privileges as written against: Supabase's per-schema grant in public, nothing global, nothing in
  -- twin, ottoq or extensions
  IF NOT EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
                  WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
                    AND d.defaclobjtype = 'f' AND a.grantee = 'anon'::regrole AND a.privilege_type = 'EXECUTE')
     OR NOT EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
                     WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
                       AND d.defaclobjtype = 'f' AND a.grantee = 'authenticated'::regrole AND a.privilege_type = 'EXECUTE') THEN
    RAISE EXCEPTION '0701 P1: postgres''s default privileges in public do not grant new functions to anon and authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_default_acl d
              WHERE d.defaclrole = 'postgres'::regrole AND d.defaclobjtype = 'f'
                AND (d.defaclnamespace = 0
                     OR d.defaclnamespace IN ('twin'::regnamespace, 'ottoq'::regnamespace, 'extensions'::regnamespace))) THEN
    RAISE EXCEPTION '0701 P1: postgres already has a global, twin, ottoq or extensions default for functions';
  END IF;
  IF to_regprocedure('public.ottoq_assert_anon_rpc_surface()') IS NULL THEN
    RAISE EXCEPTION '0701 P1: ottoq_assert_anon_rpc_surface() is missing';
  END IF;
END $premises$;

-- ── probes, each in a block that rolls itself back ──
-- as a browser role: may it read the key and sign? (never prints the key; 'read' means a non-empty value came back)
CREATE FUNCTION pg_temp.p0701_as(p_role text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('role', p_role, true);
    DECLARE
      v_s text; v_key text; v_ev text; v_sdr text; v_bun text;
    BEGIN
      BEGIN
        v_s := public.ottoq_resolve_signing_secret('system:v1');
        v_key := CASE WHEN v_s IS NOT NULL AND length(v_s) > 0 THEN 'read' ELSE 'null' END;
      EXCEPTION WHEN insufficient_privilege THEN v_key := 'refused';
      END;
      v_s := NULL;
      BEGIN
        v_ev := CASE WHEN public.ottoq_sign_event('00000000-0000-4000-8000-000000000701', timestamptz '2026-10-13 00:00:00+00',
                                                  'system', 'probe.0701', 'probe', NULL, md5('0701'), 'system:v1') ~ '^[0-9a-f]{64}$'
                     THEN 'signed' ELSE 'null' END;
      EXCEPTION WHEN insufficient_privilege THEN v_ev := 'refused';
      END;
      BEGIN
        v_sdr := CASE WHEN public.ottoq_sign_sdr('00000000-0000-4000-8000-000000000701', timestamptz '2026-10-13 00:00:00+00',
                                                 NULL, 'probe_0701', md5('0701'), 'system:v1') ~ '^[0-9a-f]{64}$'
                      THEN 'signed' ELSE 'null' END;
      EXCEPTION WHEN insufficient_privilege THEN v_sdr := 'refused';
      END;
      BEGIN
        v_bun := CASE WHEN public.ottoq_sign_bundle('00000000-0000-4000-8000-000000000701', timestamptz '2026-10-13 00:00:00+00',
                                                    timestamptz '2026-10-13 01:00:00+00', md5('0701'), 'system:v1') ~ '^[0-9a-f]{64}$'
                      THEN 'signed' ELSE 'null' END;
      EXCEPTION WHEN insufficient_privilege THEN v_bun := 'refused';
      END;
      RAISE EXCEPTION 'AS %|key %|event %|sdr %|bundle %', p_role, v_key, v_ev, v_sdr, v_bun;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

-- as this file's own role (the engine's): the three signatures on synthetic inputs, carried out as md5s of the
-- signatures only. p_forge plants settings first: 'old' the two overrides the resolver used to believe, 'new' the new
-- cache name with no stamp, 'stale' the new cache name with a stamp from another transaction.
CREATE FUNCTION pg_temp.p0701_sigs(p_forge text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE
  v_msg text;
  v_cache text := 'ottoq.sigcache_' || md5('system:v1');
BEGIN
  BEGIN
    IF p_forge = 'old' THEN
      PERFORM set_config('ottoq.signing_secret_system_v1', 'p0701-forged', true);
      PERFORM set_config('ottoq.signing_secret_default', 'p0701-forged', true);
    ELSIF p_forge = 'new' THEN
      PERFORM set_config(v_cache, 'p0701-forged', true);
    ELSIF p_forge = 'stale' THEN
      PERFORM set_config(v_cache, 'p0701-forged', true);
      PERFORM set_config(v_cache || '_tx', '0', true);
    END IF;
    DECLARE
      v_ev text; v_sdr text; v_bun text;
    BEGIN
      v_ev := public.ottoq_sign_event('00000000-0000-4000-8000-000000000701', timestamptz '2026-10-13 00:00:00+00',
                                      'system', 'probe.0701', 'probe', NULL, md5('0701'), 'system:v1');
      v_sdr := public.ottoq_sign_sdr('00000000-0000-4000-8000-000000000701', timestamptz '2026-10-13 00:00:00+00',
                                     NULL, 'probe_0701', md5('0701'), 'system:v1');
      v_bun := public.ottoq_sign_bundle('00000000-0000-4000-8000-000000000701', timestamptz '2026-10-13 00:00:00+00',
                                        timestamptz '2026-10-13 01:00:00+00', md5('0701'), 'system:v1');
      RAISE EXCEPTION 'SIGS|%|%|%|hex %|stamp %',
        COALESCE(md5(v_ev), 'null'), COALESCE(md5(v_sdr), 'null'), COALESCE(md5(v_bun), 'null'),
        COALESCE((v_ev ~ '^[0-9a-f]{64}$')::int, 0) + COALESCE((v_sdr ~ '^[0-9a-f]{64}$')::int, 0)
          + COALESCE((v_bun ~ '^[0-9a-f]{64}$')::int, 0),
        CASE WHEN current_setting(v_cache || '_tx', true) = extract(epoch FROM transaction_timestamp())::text
             THEN 'this_tx' ELSE 'none' END;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RETURN v_msg;
END $fn$;

-- what a browser role may execute: VOLATILE SECURITY DEFINER non-trigger functions in public
CREATE FUNCTION pg_temp.p0701_census() RETURNS SETOF oid LANGUAGE sql AS $fn$
  SELECT p.oid FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef AND p.provolatile = 'v' AND p.prokind = 'f'
     AND p.prorettype <> 'trigger'::regtype
     AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
$fn$;

CREATE TEMP TABLE p0701 (phase text PRIMARY KEY, r text) ON COMMIT DROP;
CREATE TEMP TABLE p0701_census_before ON COMMIT DROP AS SELECT c AS oid FROM pg_temp.p0701_census() c;

-- ── P2: the defect, measured: a signed-in caller reads the key and signs; the resolver believes a planted setting ──
DO $p2$
DECLARE v_auth text := pg_temp.p0701_as('authenticated'); v_base text; v_old text;
BEGIN
  IF v_auth IS DISTINCT FROM 'AS authenticated|key read|event signed|sdr signed|bundle signed' THEN
    RAISE EXCEPTION '0701 P2: as a signed-in caller, before: % (expected the key read and all three signed)', v_auth;
  END IF;
  v_base := pg_temp.p0701_sigs('none');
  v_old := pg_temp.p0701_sigs('old');
  IF v_base !~ '^SIGS\|[0-9a-f]{32}\|[0-9a-f]{32}\|[0-9a-f]{32}\|hex 3\|' THEN
    RAISE EXCEPTION '0701 P2: the engine does not sign before this file: %', v_base;
  END IF;
  IF split_part(v_old, '|', 2) = split_part(v_base, '|', 2) THEN
    RAISE EXCEPTION '0701 P2: a planted ottoq.signing_secret_* setting did not change the signature; the premise moved';
  END IF;
  INSERT INTO p0701 VALUES ('as_authenticated_before', v_auth), ('sigs_before', v_base);
  RAISE NOTICE '0701 P2: before: %; a planted override setting changes the signature', v_auth;
END $p2$;

-- ── snapshot: the resolver, one GRANT per (target, browser role or PUBLIC) taken, the default privileges ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0701_pre', 'function', 'public', 'ottoq_resolve_signing_secret(text)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('public.ottoq_resolve_signing_secret(text)'::regprocedure) AS def) d;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0701_pre', 'grant', 'public', g.sig || '::' || g.grantee, g.stmt, md5(g.stmt)
  FROM (SELECT t.sig::text AS sig, CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS grantee,
               format('GRANT EXECUTE ON FUNCTION %s TO %s;', t.qual,
                      CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END) AS stmt
          FROM p0701_targets t JOIN pg_proc p ON p.oid = t.sig
          CROSS JOIN LATERAL aclexplode(p.proacl) a
         WHERE a.privilege_type = 'EXECUTE' AND a.grantor = 'postgres'::regrole
           AND (a.grantee = 0 OR a.grantee IN ('anon'::regrole, 'authenticated'::regrole))
         ORDER BY t.qual, a.grantee) g;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0701_pre', 'default_privileges', s.sch, s.obj, s.stmt, md5(s.stmt)
  FROM (VALUES
    (1, 'public', 'postgres::functions::anon',
        'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon;'),
    (2, 'public', 'postgres::functions::authenticated',
        'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;'),
    (3, '(global)', 'postgres::functions::PUBLIC',
        'ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO PUBLIC;'),
    (4, 'twin', 'postgres::functions::service_role',
        'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA twin REVOKE EXECUTE ON FUNCTIONS FROM service_role;'),
    (5, 'ottoq', 'postgres::functions::service_role',
        'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ottoq REVOKE EXECUTE ON FUNCTIONS FROM service_role;'),
    (6, 'extensions', 'postgres::functions::PUBLIC',
        'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA extensions REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;'))
    AS s(ord, sch, obj, stmt)
 ORDER BY s.ord;

-- ── (a) the eighteen: closed to PUBLIC and the browser roles, kept for service_role ──
DO $revoke$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT t.qual FROM p0701_targets t ORDER BY 1 LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.qual);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.qual);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0701 (a): % signatures closed to PUBLIC, anon and authenticated; service_role kept', v_n;
END $revoke$;

-- ── (b) the resolver: no setting overrides; a cache that lives for one transaction and is believed only in it ──
CREATE OR REPLACE FUNCTION public.ottoq_resolve_signing_secret(p_key_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_secret TEXT;
  v_ref    TEXT;
  -- 0701: the cache is one transaction's (set_config(..., true)), under a name no earlier version wrote, and it is
  -- believed only beside a stamp of this transaction's start, which nothing outside the transaction knows in advance.
  -- So a value an earlier version left in a pooled session is never read, and a session that pre-sets the name is
  -- ignored. Nothing else is read before the registry: the two setting overrides that came first are gone.
  v_cache  TEXT := 'ottoq.sigcache_' || md5(COALESCE(p_key_id, ''));
  v_stamp  TEXT := extract(epoch FROM transaction_timestamp())::text;
BEGIN
  IF p_key_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- 1. This transaction's cache, filled by this function earlier in the same transaction.
  IF current_setting(v_cache || '_tx', TRUE) IS NOT DISTINCT FROM v_stamp THEN
    v_secret := current_setting(v_cache, TRUE);
    IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
      RETURN v_secret;
    END IF;
  END IF;

  -- 2. Resolve through the key registry. Only 'vault:<name>' is resolvable from
  --    inside the database; 'env:<NAME>' is by definition not visible here.
  SELECT k.secret_ref INTO v_ref
    FROM ottoq_signing_keys k
   WHERE k.key_id = p_key_id
     AND k.is_active
   LIMIT 1;

  IF v_ref IS NOT NULL AND v_ref LIKE 'vault:%' THEN
    BEGIN
      SELECT s.decrypted_secret INTO v_secret
        FROM vault.decrypted_secrets s
       WHERE s.name = substring(v_ref FROM 7)
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      -- Vault unreadable for this role: fall through to NULL rather than break
      -- event recording. Recording must never fail because signing failed.
      v_secret := NULL;
    END;

    IF v_secret IS NOT NULL AND length(v_secret) > 0 THEN
      -- Cache for the rest of THIS TRANSACTION only, so a tick that signs many
      -- events decrypts once, and nothing outlives the transaction.
      PERFORM set_config(v_cache, v_secret, true);
      PERFORM set_config(v_cache || '_tx', v_stamp, true);
      RETURN v_secret;
    END IF;
  END IF;

  -- 3. No secret available: signing is skipped, the event is still recorded.
  RETURN NULL;
END;
$function$;

-- ── (c) a new function is not the browser roles' until the file that creates it grants it ──
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA twin, ottoq GRANT EXECUTE ON FUNCTIONS TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA extensions GRANT EXECUTE ON FUNCTIONS TO PUBLIC;

-- ── V1: the eighteen, as written: no browser role and no PUBLIC; service_role and the owner keep them ──
DO $v1$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(t.sig::text, ', ') INTO v_bad
    FROM p0701_targets t JOIN pg_proc p ON p.oid = t.sig
   WHERE has_function_privilege('anon', t.sig, 'EXECUTE')
      OR has_function_privilege('authenticated', t.sig, 'EXECUTE')
      OR NOT has_function_privilege('service_role', t.sig, 'EXECUTE')
      OR NOT has_function_privilege('postgres', t.sig, 'EXECUTE')
      OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0701 V1 FAILED: grants not as written on %', v_bad;
  END IF;
END $v1$;

-- ── V2: the resolver as written ──
DO $v2$
DECLARE
  p pg_proc;
  v_src text;
BEGIN
  SELECT * INTO p FROM pg_proc WHERE oid = 'public.ottoq_resolve_signing_secret(text)'::regprocedure;
  v_src := regexp_replace(p.prosrc, '--[^\n]*', '', 'g');
  IF md5(p.prosrc) <> 'ae44bc24121d3b33e6dcfc94b54b8c28'
     OR NOT p.prosecdef OR p.provolatile <> 'v' OR p.proowner <> 'postgres'::regrole
     OR p.proconfig IS DISTINCT FROM ARRAY['search_path=twin, ottoq, public, extensions']
     OR v_src ~* 'signing_secret_default' OR v_src ~* 'ottoq\.signing_secret_'
     OR v_src ~* 'set_config\([^)]*,\s*false\s*\)'
     OR v_src !~ 'set_config\(v_cache, v_secret, true\)' THEN
    RAISE EXCEPTION '0701 V2 FAILED: the resolver is not as written (prosrc md5 %, config %)', md5(p.prosrc), p.proconfig;
  END IF;
END $v2$;

-- ── V3: as the browser roles: the key and the three signers refuse ──
DO $v3$
DECLARE
  v_auth text := pg_temp.p0701_as('authenticated');
  v_anon text := pg_temp.p0701_as('anon');
BEGIN
  IF v_auth IS DISTINCT FROM 'AS authenticated|key refused|event refused|sdr refused|bundle refused'
     OR v_anon IS DISTINCT FROM 'AS anon|key refused|event refused|sdr refused|bundle refused' THEN
    RAISE EXCEPTION '0701 V3 FAILED: % / %', v_auth, v_anon;
  END IF;
  RAISE NOTICE '0701 V3 PASSED: before: %; after: % and %; rolled back',
    (SELECT r FROM p0701 WHERE phase = 'as_authenticated_before'), v_auth, v_anon;
END $v3$;

-- ── V4: the engine still signs, byte for byte as before, and believes no planted setting ──
DO $v4$
DECLARE
  v_before text := (SELECT r FROM p0701 WHERE phase = 'sigs_before');
  v_after text := pg_temp.p0701_sigs('none');
  v_old text := pg_temp.p0701_sigs('old');
  v_new text := pg_temp.p0701_sigs('new');
  v_stale text := pg_temp.p0701_sigs('stale');
  v_key3 text := split_part(v_before, '|', 2) || '|' || split_part(v_before, '|', 3) || '|' || split_part(v_before, '|', 4);
  v_cache text := 'ottoq.sigcache_' || md5('system:v1');
BEGIN
  IF v_after !~ '^SIGS\|[0-9a-f]{32}\|[0-9a-f]{32}\|[0-9a-f]{32}\|hex 3\|stamp this_tx$'
     OR split_part(v_after, '|', 2) || '|' || split_part(v_after, '|', 3) || '|' || split_part(v_after, '|', 4) <> v_key3 THEN
    RAISE EXCEPTION '0701 V4 FAILED: the engine''s signatures moved or the cache was not stamped: before %, after %', v_before, v_after;
  END IF;
  IF split_part(v_old, '|', 2) || '|' || split_part(v_old, '|', 3) || '|' || split_part(v_old, '|', 4) <> v_key3
     OR split_part(v_new, '|', 2) || '|' || split_part(v_new, '|', 3) || '|' || split_part(v_new, '|', 4) <> v_key3
     OR split_part(v_stale, '|', 2) || '|' || split_part(v_stale, '|', 3) || '|' || split_part(v_stale, '|', 4) <> v_key3 THEN
    RAISE EXCEPTION '0701 V4 FAILED: a planted setting changed a signature: old %, new %, stale %', v_old, v_new, v_stale;
  END IF;
  -- the probes rolled back, and with them the cache: nothing of the key is left in this transaction
  IF COALESCE(current_setting(v_cache, true), '') <> '' OR COALESCE(current_setting(v_cache || '_tx', true), '') <> '' THEN
    RAISE EXCEPTION '0701 V4 FAILED: the signing cache outlived the block that set it';
  END IF;
  RAISE NOTICE '0701 V4 PASSED: three signatures identical before and after (md5s only compared); planted settings ignored';
END $v4$;

-- ── V5: the default privileges, in the catalog and on functions created now (rolled back) ──
DO $v5$
DECLARE v_msg text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
              WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND d.defaclobjtype = 'f'
                AND a.grantee IN ('anon'::regrole, 'authenticated'::regrole))
     OR NOT EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
                     WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
                       AND d.defaclobjtype = 'f' AND a.grantee = 'service_role'::regrole)
     OR NOT EXISTS (SELECT 1 FROM pg_default_acl d
                     WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 0 AND d.defaclobjtype = 'f'
                       AND NOT EXISTS (SELECT 1 FROM aclexplode(d.defaclacl) a WHERE a.grantee = 0)) THEN
    RAISE EXCEPTION '0701 V5 FAILED: postgres''s default privileges for functions are not as written';
  END IF;
  BEGIN
    CREATE FUNCTION public.p0701_default_probe() RETURNS int LANGUAGE sql AS 'SELECT 1';
    CREATE FUNCTION twin.p0701_default_probe() RETURNS int LANGUAGE sql AS 'SELECT 1';
    CREATE FUNCTION ottoq.p0701_default_probe() RETURNS int LANGUAGE sql AS 'SELECT 1';
    CREATE FUNCTION extensions.p0701_default_probe() RETURNS int LANGUAGE sql AS 'SELECT 1';
    -- (a NULL proacl means PostgreSQL's built-in default, which includes PUBLIC)
    RAISE EXCEPTION 'PROBE|public anon %, authenticated %, service_role %|twin service_role %, PUBLIC %|ottoq service_role %, PUBLIC %|extensions PUBLIC %',
      has_function_privilege('anon', 'public.p0701_default_probe()', 'EXECUTE')::text,
      has_function_privilege('authenticated', 'public.p0701_default_probe()', 'EXECUTE')::text,
      has_function_privilege('service_role', 'public.p0701_default_probe()', 'EXECUTE')::text,
      has_function_privilege('service_role', 'twin.p0701_default_probe()', 'EXECUTE')::text,
      (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
         FROM pg_proc p WHERE p.oid = 'twin.p0701_default_probe()'::regprocedure)::text,
      has_function_privilege('service_role', 'ottoq.p0701_default_probe()', 'EXECUTE')::text,
      (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
         FROM pg_proc p WHERE p.oid = 'ottoq.p0701_default_probe()'::regprocedure)::text,
      (SELECT p.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
         FROM pg_proc p WHERE p.oid = 'extensions.p0701_default_probe()'::regprocedure)::text;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'PROBE|public anon false, authenticated false, service_role true|twin service_role true, PUBLIC false|ottoq service_role true, PUBLIC false|extensions PUBLIC true' THEN
    RAISE EXCEPTION '0701 V5 FAILED: a function created now: %', v_msg;
  END IF;
  RAISE NOTICE '0701 V5 PASSED: %; rolled back', v_msg;
END $v5$;

-- ── V6: the standing anon gate is empty, and the browser roles' census lost exactly the eighteen ──
DO $v6$
DECLARE v_gate text; v_gone text; v_new text; v_n int;
BEGIN
  SELECT string_agg(g.proname || ' (' || g.problem || ')', ', ') INTO v_gate FROM public.ottoq_assert_anon_rpc_surface() g;
  IF v_gate IS NOT NULL THEN
    RAISE EXCEPTION '0701 V6 FAILED: ottoq_assert_anon_rpc_surface() still reports %', v_gate;
  END IF;
  SELECT string_agg(b.oid::regprocedure::text, ', ') INTO v_gone
    FROM p0701_census_before b
   WHERE b.oid NOT IN (SELECT c FROM pg_temp.p0701_census() c) AND b.oid NOT IN (SELECT t.sig FROM p0701_targets t);
  SELECT string_agg(c::regprocedure::text, ', ') INTO v_new
    FROM pg_temp.p0701_census() c
   WHERE c NOT IN (SELECT b.oid FROM p0701_census_before b) OR c IN (SELECT t.sig FROM p0701_targets t);
  IF v_gone IS NOT NULL OR v_new IS NOT NULL THEN
    RAISE EXCEPTION '0701 V6 FAILED: the census lost % and gained or kept %', v_gone, v_new;
  END IF;
  SELECT count(*) INTO v_n FROM pg_temp.p0701_census();
  RAISE NOTICE '0701 V6 PASSED: the anon gate is empty; % VOLATILE SECURITY DEFINER functions in public remain executable by a browser role (db/checks/0438 (4))', v_n;
END $v6$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0701_a_signed_in_user_cannot_read_the_signing_key_or_sign_or_purge', false, false,
  'G421 (db/checks/0438): REVOKE EXECUTE from PUBLIC, anon and authenticated (service_role kept) on the signing-key '
  'resolver, the three signers, ottoq_oem_deliver_live, the three energy_mpc_replan overloads, purge_prior_runs, '
  'start_busy_run(_once), release_unusable_reservations, fit_charge_fault_model, record_event, emit_sdr, '
  'generate_audit_bundle, complete_audit_report and probe_task_completion; the resolver drops its two setting overrides '
  'and caches for one transaction under a new, stamped name; new public functions no longer grant anon, authenticated '
  'or PUBLIC (twin and ottoq keep service_role, extensions keeps PUBLIC). No atom reads a signature or a grant and the '
  'secret is unchanged, so signatures are byte-identical (V4): FALSE/FALSE.',
  now());

COMMIT;
