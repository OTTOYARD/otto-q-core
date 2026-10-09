-- migration-version: PENDING
-- migration-name:    the_command_dock_answers_only_the_platform
--
-- 0648  **The command dock answers only the platform: no public key or signed-in account can peek at, lease or
--        acknowledge a production command.** (G393; security item 2 of the twin data contract review, 2026-10-08.
--        Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The dock is five SECURITY DEFINER functions, owned by postgres, that check no caller. Measured 2026-10-09 ~23:30
--   UTC, EXECUTE held by:
--
--     function                                         anon   authenticated   what it does
--     ottoq_fleet_claim_commands(uuid,uuid,int,text)    yes        yes        leases production vehicle commands;
--                                                                              first delivery wins
--     ottoq_energy_claim_commands(uuid,int,text)        yes        yes        the same for energy commands (also PUBLIC)
--     ottoq_energy_ack_command(uuid,text,text,text)     yes        yes        acknowledges a delivered energy command
--                                                                              (also PUBLIC)
--     ottoq_fleet_pending_commands(uuid,uuid,int)        -         yes        peeks at pending production commands
--     ottoq_ack_vehicle_command(uuid,text,text,text)     -         yes        acknowledges a vehicle command
--
--   The operator is an optional argument, so with the public key anyone could lease every operator's production
--   commands and the real operator would never receive them; any signed-in account (the field-ops demo logins share one
--   password in a public repo) could read them or acknowledge them. Latent today: 1 production vehicle command exists
--   and 0 commands of either kind have ever been delivered.
--
--   Callers, measured (every repo, every database function, every cron job): only the robovac bridge
--   (otto-q-workspace/bridge), which calls ottoq_fleet_pending_commands and ottoq_ack_vehicle_command with the
--   service key. No database function and no cron job calls any of the five.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   REVOKE EXECUTE on the five FROM PUBLIC, anon, authenticated. service_role and postgres keep it. The bodies are
--   untouched. Binding the operator to the caller's credential belongs to the door that will call the dock for an
--   operator (the v2 contract door, review step 3), which passes p_fleet_operator_id from the credential, never from
--   the request.
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No body, no tick path, no row. The twin issues and confirms its own commands inside the tick and never calls the
--   dock (twin commands are refused by it), so every run, pair and dial arm behaves byte for byte as before.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0648_pre' (the GRANT statements that restore the
--   privileges as they stood, generated from the ACLs at apply time).

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0648 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: the dock this file was written against ──
DO $premises$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0647_the_public_key_reads_no_vehicle_and_no_command') THEN
    RAISE EXCEPTION '0648 P1: 0647 is not classified; apply in order';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_fleet_claim_commands(uuid,uuid,integer,text)',  '2b46474c77ab2b6791c3174220763435'),
      ('public.ottoq_energy_claim_commands(uuid,integer,text)',      '936a3bb9cb1aa589ea585f0461767932'),
      ('public.ottoq_energy_ack_command(uuid,text,text,text)',       '2923976992bc2440c3c49f98e5fe251a'),
      ('public.ottoq_fleet_pending_commands(uuid,uuid,integer)',     'b7842a6352ea70aa6cef51e4fc52c6b0'),
      ('public.ottoq_ack_vehicle_command(uuid,text,text,text)',      '66d4db2561f6247314d195bbf522b881')) AS t(sig, md5)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE EXCEPTION '0648 P1: % is missing', r.sig;
    END IF;
    IF md5(pg_get_functiondef(r.sig::regprocedure)) <> r.md5 THEN
      RAISE EXCEPTION '0648 P1: % is not the definition this file was written against', r.sig;
    END IF;
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = r.sig::regprocedure) THEN
      RAISE EXCEPTION '0648 P1: % is not SECURITY DEFINER', r.sig;
    END IF;
  END LOOP;
END $premises$;

-- ── the GRANTs that restore what this file revokes, generated from the live ACLs ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0648_pre', 'grant', 'public', 'command dock EXECUTE (5 functions)', g.def, md5(g.def)
  FROM (SELECT string_agg(format('GRANT EXECUTE ON FUNCTION %s TO %s;', p.oid::regprocedure,
                                 CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(a.grantee)) END),
                          ' ' ORDER BY p.oid::regprocedure::text, a.grantee) AS def
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          CROSS JOIN LATERAL aclexplode(p.proacl) a
         WHERE n.nspname = 'public'
           AND p.proname IN ('ottoq_fleet_claim_commands', 'ottoq_energy_claim_commands', 'ottoq_energy_ack_command',
                             'ottoq_fleet_pending_commands', 'ottoq_ack_vehicle_command')
           AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR pg_get_userbyid(a.grantee) IN ('anon', 'authenticated'))) g;

-- ── the platform alone ──
REVOKE EXECUTE ON FUNCTION public.ottoq_fleet_claim_commands(uuid,uuid,integer,text)  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ottoq_energy_claim_commands(uuid,integer,text)      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ottoq_energy_ack_command(uuid,text,text,text)       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ottoq_fleet_pending_commands(uuid,uuid,integer)     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ottoq_ack_vehicle_command(uuid,text,text,text)      FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.ottoq_fleet_claim_commands(uuid,uuid,integer,text) IS
  '0273: the outbound LEASE. Returns the same production commands as ottoq_fleet_pending_commands and stamps delivered_at/delivered_to as it does. Poll with the peek; take with the claim. First delivery wins, so a retry does not overwrite when the command actually went out. 0648: service_role only; the door that calls it for an operator passes p_fleet_operator_id from that operator''s credential, never from the request.';

-- ── V1: privileges as written ──
DO $v1$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS f FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN ('ottoq_fleet_claim_commands', 'ottoq_energy_claim_commands', 'ottoq_energy_ack_command',
                                'ottoq_fleet_pending_commands', 'ottoq_ack_vehicle_command')
  LOOP
    IF has_function_privilege('anon', r.f, 'EXECUTE') OR has_function_privilege('authenticated', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0648 V1 FAILED: % is still executable by anon or authenticated', r.f;
    END IF;
    IF NOT has_function_privilege('service_role', r.f, 'EXECUTE') THEN
      RAISE EXCEPTION '0648 V1 FAILED: service_role lost %', r.f;
    END IF;
  END LOOP;
END $v1$;

-- ── V2: as the public key, the lease is refused; nothing is delivered (the sub-block rolls back either way) ──
DO $v2$
DECLARE v_msg text; v_refused boolean := false; v_delivered_before bigint; v_delivered_after bigint;
BEGIN
  SELECT count(*) INTO v_delivered_before FROM public.ottoq_vehicle_commands WHERE delivered_at IS NOT NULL;
  BEGIN
    PERFORM set_config('role', 'anon', true);
    BEGIN
      PERFORM * FROM public.ottoq_fleet_claim_commands(NULL, NULL, 1, 'probe_0648');
    EXCEPTION WHEN insufficient_privilege THEN v_refused := true;
    END;
    RAISE EXCEPTION '0648 V2 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0648 V2 PROBED' THEN RAISE EXCEPTION '0648 V2: the probe itself failed: %', v_msg; END IF;
  SELECT count(*) INTO v_delivered_after FROM public.ottoq_vehicle_commands WHERE delivered_at IS NOT NULL;
  IF NOT v_refused THEN RAISE EXCEPTION '0648 V2 FAILED: the public key can still lease commands'; END IF;
  IF v_delivered_after <> v_delivered_before THEN
    RAISE EXCEPTION '0648 V2 FAILED: delivered commands moved % -> %', v_delivered_before, v_delivered_after;
  END IF;
  RAISE NOTICE '0648 V2 PASSED: the public key is refused the lease; delivered commands % before and after', v_delivered_after;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0648_the_command_dock_answers_only_the_platform', false, false,
  'G393 (security item 2): REVOKE EXECUTE FROM PUBLIC, anon, authenticated on the five command-dock functions '
  '(fleet/energy claim, energy ack, fleet peek, vehicle-command ack); service_role keeps them. Privileges only; no body, '
  'no tick path. FALSE/FALSE.',
  now());

COMMIT;
