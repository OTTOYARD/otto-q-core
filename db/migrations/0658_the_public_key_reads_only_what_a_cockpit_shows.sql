-- migration-version: PENDING
-- migration-name:    the_public_key_reads_only_what_a_cockpit_shows
--
-- 0658  **The public key reads only the fifteen relations a cockpit shows it, and a new table is closed to it until a
--        migration opens it.** (G394; db/checks/0429 §2 (d). Chase, 2026-10-09 CT, on blocking the public key by
--        default: "all of your answers look great ... just build as you indicated.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Measured 2026-10-10 ~05:00 UTC, before this file. The public key (anon) could SELECT 383 of 432 public tables, 242
--   of them with row security off, 80 of 89 views and 70 of 72 sequences; it held INSERT, UPDATE, DELETE or TRUNCATE
--   on 18 tables and 45 views. postgres's default privileges in public handed it SELECT on every new table (anon=rxtm).
--   The anon key sits in client code in public repos, so anon is everyone.
--
--   Who uses it, measured:
--     - PostgREST logs, the 24 h before this file: anon read 10 tables and called 17 RPCs, all from browsers. Every
--       other request came on the secret key (the service role), which this file does not touch.
--     - The twin app (ottoyarddepot-sim) reads 14 relations in the browser with the public key: the 10 in the logs and
--       four on pages nobody opened that day (useSelfReview: ottoq_arbiter_assessments, ottoq_charge_clock_fits;
--       useDecisionTrail: ottoq_decisions, ottoq_external_proposals).
--     - field-ops' open demo (no login) reads ottoq_comms_messages every 5 s on its comms page.
--     - Every core edge function uses the service role. No browser code writes a table on the public key.
--     - Of the 29 cockpit RPCs that exist, 28 are SECURITY DEFINER and the 29th, ottoq_shield_probe_posture, reads only
--       the system catalog, so no RPC loses a table it reads.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) REVOKE ALL FROM anon on every table, view and sequence in public and twin that holds an anon grant made by
--       postgres: 535 relations (387 tables, 78 views, 70 sequences) when written.
--   (b) GRANT SELECT TO anon on the allowlist, the 15 relations the cockpits read:
--         the twin app: ottoq_arbiter_assessments, ottoq_calibration_datasets, ottoq_calibration_distributions,
--           ottoq_charge_clock_fits, ottoq_decisions, ottoq_depot_tariffs, ottoq_determinism_canon (view),
--           ottoq_external_proposals, ottoq_feed_plans, ottoq_intelligence_ledger (view),
--           ottoq_proposal_disposition_ledger, ottoq_rules, ottoq_variability_catalog, ottoq_vehicle_classes;
--         field-ops' open demo: ottoq_comms_messages.
--       SELECT only, since nothing in a browser writes them. Their row security and policies are unchanged.
--   (c) ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES, and ON SEQUENCES, FROM anon.
--       A table a later migration creates is closed to the public key until that migration opens it. A cockpit reads a
--       new table through a SECURITY DEFINER RPC, as most already do, or through a GRANT SELECT ... TO anon in the file
--       that adds it, naming the reader.
--
--   After: anon reads the 15 and nothing else that postgres owns, writes nothing in public or twin, uses no sequence.
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No function, row, policy or tick path. The engine reads and writes as postgres or service_role, which grants to
--   anon do not touch, so every run, pair and dial arm behaves byte for byte as before. Still open after it (G394):
--     - functions: the public key may still EXECUTE about a thousand public functions, 67 of them SECURITY DEFINER.
--       A default deny on functions is the next step, not this one: SECURITY INVOKER chains make its reach harder to
--       prove, and the twin app calls run controls with the public key;
--     - PostGIS's spatial_ref_sys, geometry_columns and geography_columns belong to supabase_admin, which granted anon
--       and PUBLIC on them. postgres cannot revoke another grantor's grant, so they keep those privileges;
--     - signed-in users (authenticated) keep theirs, and field-ops' demo logins still share one password in a public
--       repo (G393);
--     - ottoq_comms_messages (~903K rows, row security off), ottoq_decisions, ottoq_external_proposals and
--       ottoq_proposal_disposition_ledger stay readable whole. Each belongs behind a run-scoped RPC next.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0658_pre', in snapshot_id order: one GRANT per
--   relation that held an anon grant, and one ALTER DEFAULT PRIVILEGES per object type.

BEGIN;

-- GRANT and REVOKE change catalog rows; measured on PostgreSQL 16, a REVOKE holds no lock on the relation it names.
-- The live engine is 17, so the timeout bounds any wait on a tick if that differs.
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0658 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE
  v_allow text[] := ARRAY['ottoq_arbiter_assessments', 'ottoq_calibration_datasets', 'ottoq_calibration_distributions',
                          'ottoq_charge_clock_fits', 'ottoq_comms_messages', 'ottoq_decisions', 'ottoq_depot_tariffs',
                          'ottoq_determinism_canon', 'ottoq_external_proposals', 'ottoq_feed_plans',
                          'ottoq_intelligence_ledger', 'ottoq_proposal_disposition_ledger', 'ottoq_rules',
                          'ottoq_variability_catalog', 'ottoq_vehicle_classes'];
  v_missing text;
BEGIN
  -- 0656, not 0657: 0657 forces a recertification, so it is applied after 0658, 0659 and 0690 (its sweep would hold
  -- their in-flight check closed for most of an hour); nothing here depends on it
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0656_the_research_wing_measures_the_operator_door_in_the_twin') THEN
    RAISE EXCEPTION '0658 P1: 0656 is not classified; apply in order';
  END IF;
  SELECT string_agg(t, ', ') INTO v_missing FROM unnest(v_allow) t
   WHERE NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relname = t
                        AND c.relkind IN ('r', 'p', 'v', 'm'));
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0658 P1: allowlisted relations missing: %', v_missing;
  END IF;
  -- a SECURITY INVOKER view would need its base tables granted too; the two allowlisted views run as their owner
  IF EXISTS (SELECT 1 FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relname = ANY (v_allow)
                AND c.relkind = 'v' AND COALESCE(array_to_string(c.reloptions, ','), '') ~ 'security_invoker=(true|on|1)') THEN
    RAISE EXCEPTION '0658 P1: an allowlisted view runs as its invoker; grant its base tables or drop it from the list';
  END IF;
  -- the default privileges hand the public key SELECT on new tables and USAGE on new sequences (live: rxtm and rwU)
  IF NOT EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
                  WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
                    AND d.defaclobjtype = 'r' AND a.grantee = 'anon'::regrole AND a.privilege_type = 'SELECT') THEN
    RAISE EXCEPTION '0658 P1: postgres''s default privileges do not give the public key new public tables';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
                  WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
                    AND d.defaclobjtype = 'S' AND a.grantee = 'anon'::regrole AND a.privilege_type = 'USAGE') THEN
    RAISE EXCEPTION '0658 P1: postgres''s default privileges do not give the public key new public sequences';
  END IF;
  -- the restore statements below carry no WITH GRANT OPTION, so there must be none to restore
  IF EXISTS (SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
              WHERE c.relnamespace IN ('public'::regnamespace, 'twin'::regnamespace)
                AND a.grantee = 'anon'::regrole AND a.is_grantable) THEN
    RAISE EXCEPTION '0658 P1: an anon grant carries a grant option';
  END IF;
  -- PUBLIC reaches anon too; the only PUBLIC grants are PostGIS's three, which postgres does not own
  IF EXISTS (SELECT 1 FROM pg_class c, aclexplode(c.relacl) a
              WHERE c.relnamespace IN ('public'::regnamespace, 'twin'::regnamespace)
                AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S') AND a.grantee = 0
                AND c.relname NOT IN ('spatial_ref_sys', 'geometry_columns', 'geography_columns')) THEN
    RAISE EXCEPTION '0658 P1: a relation other than PostGIS''s three is granted to PUBLIC';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_schema_snapshots WHERE label = '0658_pre') THEN
    RAISE EXCEPTION '0658 P1: 0658_pre snapshots exist already';
  END IF;
END $premises$;

-- ── restore statements: one GRANT per relation, then the default privileges ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0658_pre', 'grant', g.nspname, g.relname || '::anon', g.stmt, md5(g.stmt)
  FROM (SELECT n.nspname, c.relname,
               format('GRANT %s ON %s %I.%I TO anon;',
                      (SELECT string_agg(a.privilege_type, ', ' ORDER BY a.privilege_type)
                         FROM aclexplode(c.relacl) a WHERE a.grantee = 'anon'::regrole AND a.grantor = 'postgres'::regrole),
                      CASE WHEN c.relkind = 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, n.nspname, c.relname) AS stmt
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname IN ('public', 'twin') AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
           AND EXISTS (SELECT 1 FROM aclexplode(c.relacl) a
                        WHERE a.grantee = 'anon'::regrole AND a.grantor = 'postgres'::regrole)
         ORDER BY n.nspname, c.relname) g;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0658_pre', 'default_privileges', 'public', 'postgres::' || k.kind || '::anon', k.stmt, md5(k.stmt)
  FROM (SELECT lower(o.kind) AS kind,
               format('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT %s ON %s TO anon;',
                      string_agg(a.privilege_type, ', ' ORDER BY a.privilege_type), o.kind) AS stmt
          FROM pg_default_acl d
          CROSS JOIN LATERAL aclexplode(d.defaclacl) a
          CROSS JOIN LATERAL (SELECT CASE d.defaclobjtype WHEN 'r' THEN 'TABLES' ELSE 'SEQUENCES' END AS kind) o
         WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
           AND d.defaclobjtype IN ('r', 'S') AND a.grantee = 'anon'::regrole
         GROUP BY o.kind) k;

-- ── (a) the public key loses every relation postgres granted it ──
DO $revoke$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN
    SELECT c.relkind, n.nspname, c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'twin') AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
       AND EXISTS (SELECT 1 FROM aclexplode(c.relacl) a
                    WHERE a.grantee = 'anon'::regrole AND a.grantor = 'postgres'::regrole)
     ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE format('REVOKE ALL ON %s %I.%I FROM anon',
                   CASE WHEN r.relkind = 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, r.nspname, r.relname);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0658 (a): revoked the public key on % relations', v_n;
END $revoke$;

-- ── (b) the allowlist: what the cockpits read, read-only ──
GRANT SELECT ON public.ottoq_arbiter_assessments, public.ottoq_calibration_datasets,
                public.ottoq_calibration_distributions, public.ottoq_charge_clock_fits, public.ottoq_comms_messages,
                public.ottoq_decisions, public.ottoq_depot_tariffs, public.ottoq_determinism_canon,
                public.ottoq_external_proposals, public.ottoq_feed_plans, public.ottoq_intelligence_ledger,
                public.ottoq_proposal_disposition_ledger, public.ottoq_rules, public.ottoq_variability_catalog,
                public.ottoq_vehicle_classes
   TO anon;

-- ── (c) a new table or sequence is closed to the public key until a migration opens it ──
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon;

-- ── V1: as the public key, in a block that rolls itself back ──
DO $v1$
DECLARE
  v_msg text;
BEGIN
  BEGIN
    PERFORM set_config('role', 'anon', true);
    DECLARE
      v_read int := 0; v_refused int := 0; v_wrongly text := ''; v_t text; v_n bigint;
    BEGIN
      -- tables on the list answer a real read (the two views are checked by privilege in V2: they aggregate)
      FOREACH v_t IN ARRAY ARRAY['ottoq_arbiter_assessments', 'ottoq_calibration_datasets',
                                 'ottoq_calibration_distributions', 'ottoq_charge_clock_fits', 'ottoq_comms_messages',
                                 'ottoq_decisions', 'ottoq_depot_tariffs', 'ottoq_external_proposals', 'ottoq_feed_plans',
                                 'ottoq_proposal_disposition_ledger', 'ottoq_rules', 'ottoq_variability_catalog',
                                 'ottoq_vehicle_classes'] LOOP
        EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM public.%I LIMIT 1) s', v_t) INTO v_n;
        v_read := v_read + 1;
      END LOOP;
      -- tables off the list are refused, among them the ones 0429 named
      FOREACH v_t IN ARRAY ARRAY['ottoq_events', 'ottoq_stall_bookings', 'ottoq_visit_needs', 'ottoq_sim_runs',
                                 'staff_users', 'stalls', 'depots', 'ottoq_model_call_ledger'] LOOP
        BEGIN
          EXECUTE format('SELECT 1 FROM public.%I LIMIT 1', v_t);
          v_wrongly := v_wrongly || v_t || ' ';
        EXCEPTION WHEN insufficient_privilege THEN
          v_refused := v_refused + 1;
        END;
      END LOOP;
      -- the cockpit RPCs still answer: a SECURITY DEFINER one, and the one that runs as its caller
      PERFORM public.ottoq_depot_cards(NULL, NULL);
      PERFORM count(*) FROM public.ottoq_shield_probe_posture();
      RAISE EXCEPTION 'AS ANON|%|%|%', v_read, v_refused, v_wrongly;
    END;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'AS ANON|13|8|' THEN
    RAISE EXCEPTION '0658 V1 FAILED: as the public key: %', v_msg;
  END IF;
  RAISE NOTICE '0658 V1 PASSED: as the public key, 13 listed tables read, 8 unlisted refused, two cockpit RPCs answer; rolled back';
END $v1$;

-- ── V2: the privileges as written ──
DO $v2$
DECLARE
  v_allow text[] := ARRAY['ottoq_arbiter_assessments', 'ottoq_calibration_datasets', 'ottoq_calibration_distributions',
                          'ottoq_charge_clock_fits', 'ottoq_comms_messages', 'ottoq_decisions', 'ottoq_depot_tariffs',
                          'ottoq_determinism_canon', 'ottoq_external_proposals', 'ottoq_feed_plans',
                          'ottoq_intelligence_ledger', 'ottoq_proposal_disposition_ledger', 'ottoq_rules',
                          'ottoq_variability_catalog', 'ottoq_vehicle_classes'];
  v_postgis text[] := ARRAY['spatial_ref_sys', 'geometry_columns', 'geography_columns'];
  v_readable text[];
  v_writable int;
  v_seqs int;
  v_snap int;
BEGIN
  SELECT array_agg(c.relname::text ORDER BY c.relname) INTO v_readable
    FROM pg_class c
   WHERE c.relnamespace IN ('public'::regnamespace, 'twin'::regnamespace) AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
     AND c.relname <> ALL (v_postgis) AND has_table_privilege('anon', c.oid, 'SELECT');
  IF v_readable IS DISTINCT FROM (SELECT array_agg(t ORDER BY t) FROM unnest(v_allow) t) THEN
    RAISE EXCEPTION '0658 V2 FAILED: the public key reads %', v_readable;
  END IF;
  SELECT count(*) INTO v_writable
    FROM pg_class c
   WHERE c.relnamespace IN ('public'::regnamespace, 'twin'::regnamespace) AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
     AND c.relname <> ALL (v_postgis)
     AND (has_table_privilege('anon', c.oid, 'INSERT') OR has_table_privilege('anon', c.oid, 'UPDATE')
          OR has_table_privilege('anon', c.oid, 'DELETE') OR has_table_privilege('anon', c.oid, 'TRUNCATE')
          OR has_table_privilege('anon', c.oid, 'REFERENCES') OR has_table_privilege('anon', c.oid, 'TRIGGER')
          OR EXISTS (SELECT 1 FROM aclexplode(c.relacl) a                -- and MAINTAIN, on 17
                      WHERE a.grantee = 'anon'::regrole AND a.privilege_type <> 'SELECT'));
  SELECT count(*) INTO v_seqs
    FROM pg_class c
   WHERE c.relnamespace IN ('public'::regnamespace, 'twin'::regnamespace) AND c.relkind = 'S'
     AND (has_sequence_privilege('anon', c.oid, 'USAGE') OR has_sequence_privilege('anon', c.oid, 'SELECT')
          OR has_sequence_privilege('anon', c.oid, 'UPDATE'));
  IF v_writable <> 0 OR v_seqs <> 0 THEN
    RAISE EXCEPTION '0658 V2 FAILED: the public key still writes % relations and uses % sequences', v_writable, v_seqs;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_default_acl d, aclexplode(d.defaclacl) a
              WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace
                AND d.defaclobjtype IN ('r', 'S') AND a.grantee = 'anon'::regrole) THEN
    RAISE EXCEPTION '0658 V2 FAILED: postgres''s default privileges in public still name the public key';
  END IF;
  SELECT count(*) INTO v_snap FROM public.ottoq_schema_snapshots WHERE label = '0658_pre';
  RAISE NOTICE '0658 V2 PASSED: the public key reads the 15 and writes nothing; % restore statements kept', v_snap;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0658_the_public_key_reads_only_what_a_cockpit_shows', false, false,
  'G394: the public key (anon) loses every table, view and sequence postgres granted it in public and twin, keeps SELECT '
  'on the 15 relations the cockpits read, and new public tables and sequences no longer grant it. Grants only: no '
  'function, row, policy or tick path; the engine runs as postgres and service_role. FALSE/FALSE.',
  now());

COMMIT;
