-- migration-version: PENDING
-- migration-name:    the_public_key_reads_no_vehicle_and_no_command
--
-- 0645  **The public key reads no vehicle and no command; depot staff read their own depot's commands.** (G393;
--        security item 1 of the twin data contract review, 2026-10-08. Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Measured 2026-10-09 ~22:10 UTC, as each role, before this file:
--
--     who                                   vehicles   ottoq_vehicle_commands
--     anon (the public key in client code)       226                  129,015
--     authenticated, twin-depot staff            226                  129,015
--     authenticated, no staff/operator row       226                  129,015
--
--   Two permissive SELECT policies, "client keys read only" (vehicles) and "client keys read commands"
--   (ottoq_vehicle_commands), are TO anon, authenticated USING (true). Permissive policies are OR-ed, so they override
--   the per-operator, per-member and per-staff policies beside them. And "Fleet operators see own vehicles" is TO public
--   with an "OR fleet_operator_id IS NULL" branch, so even without the open policy the public key reads the 6 unowned
--   cars (4 at the twin depot). anon and authenticated also hold TRUNCATE, TRIGGER and REFERENCES on both tables; none
--   is used. The four engine repos are public and the anon key sits in client code, so "anon" is everyone.
--
--   Who reads these tables, measured (24 h of API logs, every app repo, every edge function):
--     - every edge function uses the service role (RLS does not apply);
--     - every browser RPC that reads vehicles is SECURITY DEFINER, owned by postgres (RLS does not apply);
--     - no app reads vehicles or ottoq_vehicle_commands over REST with the public key, and no realtime feed carries them;
--     - ONE direct reader: ottoyard-field-ops, PrimeOpsSubTab.tsx, reads ottoq_vehicle_commands as a signed-in staff
--       user (all 6 staff are at the twin depot). It keeps working through the staff policy below.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) DROP POLICY "client keys read only" ON vehicles and "client keys read commands" ON ottoq_vehicle_commands.
--   (b) "Fleet operators see own vehicles" becomes TO authenticated USING (fleet_operator_id = the caller's operator).
--       No operator has a login today (0 of 4), so no signed-in user loses a row; the public key loses the 6 unowned cars.
--   (c) New "Depot staff read own depot commands": TO authenticated USING (depot_id = the caller's staff depot), the
--       commands mirror of "Staff see own depot vehicles". The function call sits in a sub-select so it runs once per
--       query, not once per row.
--   (d) REVOKE SELECT, TRUNCATE, TRIGGER, REFERENCES on both tables FROM anon, and TRUNCATE, TRIGGER, REFERENCES
--       FROM authenticated. authenticated keeps SELECT, now bounded by the staff, operator and member policies.
--
--   After, as each role: anon is refused both tables; twin-depot staff read the twin depot's vehicles and commands
--   (120 and 128,855 at the time of writing); a signed-in user with no staff or operator row reads none.
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No function, no tick path, no row. The engine reads and writes these tables as postgres or service_role, and RLS
--   and grants do not apply to either, so every run, pair and dial arm behaves byte for byte as before.
--   Not here, and still open (G393): the demo staff logins in ottoyard-field-ops share one password in a public repo,
--   so "signed-in twin-depot staff" is still anyone who reads that repo. That closes before a second operator connects,
--   not in this file, because it would end Chase's demo logins.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE every definition in ottoq_schema_snapshots WHERE label = '0645_pre' (each is a restore statement), then
--   DROP POLICY "Depot staff read own depot commands" ON public.ottoq_vehicle_commands.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0645 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: the policies and helpers this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0644_the_research_safety_check_judges_cars_not_served_across_a_look') THEN
    RAISE EXCEPTION '0645 P1: 0644 is not classified; apply in order';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vehicles'
                    AND policyname = 'client keys read only' AND cmd = 'SELECT' AND qual = 'true'
                    AND roles = ARRAY['anon','authenticated']::name[]) THEN
    RAISE EXCEPTION '0645 P1: "client keys read only" on vehicles is not the policy this file was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ottoq_vehicle_commands'
                    AND policyname = 'client keys read commands' AND cmd = 'SELECT' AND qual = 'true'
                    AND roles = ARRAY['anon','authenticated']::name[]) THEN
    RAISE EXCEPTION '0645 P1: "client keys read commands" on ottoq_vehicle_commands is not the policy this file was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'vehicles'
                    AND policyname = 'Fleet operators see own vehicles' AND cmd = 'SELECT' AND roles = ARRAY['public']::name[]
                    AND qual = '((fleet_operator_id = get_fleet_operator_id()) OR (fleet_operator_id IS NULL))') THEN
    RAISE EXCEPTION '0645 P1: "Fleet operators see own vehicles" is not the policy this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ottoq_vehicle_commands'
                AND policyname = 'Depot staff read own depot commands') THEN
    RAISE EXCEPTION '0645 P1: "Depot staff read own depot commands" exists already';
  END IF;
  IF to_regprocedure('public.get_staff_depot_id()') IS NULL OR to_regprocedure('public.get_fleet_operator_id()') IS NULL THEN
    RAISE EXCEPTION '0645 P1: get_staff_depot_id() or get_fleet_operator_id() is missing';
  END IF;
END $premises$;

-- ── restore statements for everything this file removes or narrows ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0645_pre', s.kind, 'public', s.obj, s.def, md5(s.def)
  FROM (VALUES
    ('policy', 'vehicles::client keys read only',
     'CREATE POLICY "client keys read only" ON public.vehicles AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);'),
    ('policy', 'ottoq_vehicle_commands::client keys read commands',
     'CREATE POLICY "client keys read commands" ON public.ottoq_vehicle_commands AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);'),
    ('policy', 'vehicles::Fleet operators see own vehicles',
     'ALTER POLICY "Fleet operators see own vehicles" ON public.vehicles TO public USING (((fleet_operator_id = get_fleet_operator_id()) OR (fleet_operator_id IS NULL)));'),
    ('grant', 'vehicles::anon',
     'GRANT SELECT, TRUNCATE, TRIGGER, REFERENCES ON public.vehicles TO anon;'),
    ('grant', 'vehicles::authenticated',
     'GRANT TRUNCATE, TRIGGER, REFERENCES ON public.vehicles TO authenticated;'),
    ('grant', 'ottoq_vehicle_commands::anon',
     'GRANT SELECT, TRUNCATE, TRIGGER, REFERENCES ON public.ottoq_vehicle_commands TO anon;'),
    ('grant', 'ottoq_vehicle_commands::authenticated',
     'GRANT TRUNCATE, TRIGGER, REFERENCES ON public.ottoq_vehicle_commands TO authenticated;')
  ) AS s(kind, obj, def);

-- ── (a) the two open policies ──
DROP POLICY "client keys read only" ON public.vehicles;
DROP POLICY "client keys read commands" ON public.ottoq_vehicle_commands;

-- ── (b) an operator reads its own cars, and only a signed-in operator ──
ALTER POLICY "Fleet operators see own vehicles" ON public.vehicles
  TO authenticated
  USING (fleet_operator_id = (SELECT public.get_fleet_operator_id()));

-- ── (c) depot staff read their own depot's commands (field-ops Prime Ops) ──
CREATE POLICY "Depot staff read own depot commands" ON public.ottoq_vehicle_commands
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (depot_id = (SELECT public.get_staff_depot_id()));

-- ── (d) privileges nobody uses ──
REVOKE SELECT, TRUNCATE, TRIGGER, REFERENCES ON public.vehicles, public.ottoq_vehicle_commands FROM anon;
REVOKE TRUNCATE, TRIGGER, REFERENCES ON public.vehicles, public.ottoq_vehicle_commands FROM authenticated;

-- ── V1: privileges as written ──
DO $v1$
BEGIN
  IF has_table_privilege('anon', 'public.vehicles', 'SELECT') OR has_table_privilege('anon', 'public.ottoq_vehicle_commands', 'SELECT') THEN
    RAISE EXCEPTION '0645 V1 FAILED: anon still holds SELECT';
  END IF;
  IF has_table_privilege('anon', 'public.vehicles', 'TRUNCATE') OR has_table_privilege('authenticated', 'public.vehicles', 'TRUNCATE')
     OR has_table_privilege('anon', 'public.ottoq_vehicle_commands', 'TRUNCATE') OR has_table_privilege('authenticated', 'public.ottoq_vehicle_commands', 'TRUNCATE') THEN
    RAISE EXCEPTION '0645 V1 FAILED: TRUNCATE survives';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.ottoq_vehicle_commands', 'SELECT') THEN
    RAISE EXCEPTION '0645 V1 FAILED: authenticated lost SELECT, which field-ops Prime Ops needs';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.vehicles', 'UPDATE') OR NOT has_table_privilege('service_role', 'public.ottoq_vehicle_commands', 'INSERT') THEN
    RAISE EXCEPTION '0645 V1 FAILED: service_role lost a write it had';
  END IF;
END $v1$;

-- ── V2: each role sees what §2 says, measured as that role ──
-- The probes run in a sub-block that ends by raising, so the role and claims roll back with it; plpgsql variables do
-- not roll back, so the counts survive. The twin writes commands every tick and a demo start purges them, so a staff
-- count is judged against the twin depot's count measured just before AND just after it, never against one snapshot.
DO $v2$
DECLARE
  v_msg text; v_staff uuid; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_veh_before bigint; v_veh_after bigint; v_cmd_before bigint; v_cmd_after bigint;
  v_anon_refused boolean := false; v_anon_rpc boolean;
  v_staff_veh bigint; v_staff_veh_out bigint; v_staff_cmd bigint; v_staff_cmd_out bigint;
  v_other_veh bigint; v_other_cmd bigint;
BEGIN
  SELECT auth_user_id INTO v_staff FROM public.staff_users WHERE depot_id = v_twin AND auth_user_id IS NOT NULL ORDER BY created_at LIMIT 1;
  IF v_staff IS NULL THEN RAISE EXCEPTION '0645 V2: no twin-depot staff login to probe with'; END IF;
  SELECT count(*) INTO v_veh_before FROM public.vehicles WHERE current_depot_id = v_twin OR home_depot_id = v_twin;
  SELECT count(*) INTO v_cmd_before FROM public.ottoq_vehicle_commands WHERE depot_id = v_twin;

  BEGIN
    -- the public key
    PERFORM set_config('role', 'anon', true);
    BEGIN
      PERFORM count(*) FROM public.vehicles;
    EXCEPTION WHEN insufficient_privilege THEN v_anon_refused := true;
    END;
    v_anon_rpc := public.ottoq_twin_fleet_condition(NULL) IS NOT NULL;   -- SECURITY DEFINER, the cockpit's path

    -- a signed-in twin-depot staff user
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    SELECT count(*), count(*) FILTER (WHERE (current_depot_id = v_twin OR home_depot_id = v_twin) IS NOT TRUE)
      INTO v_staff_veh, v_staff_veh_out FROM public.vehicles;
    SELECT count(*), count(*) FILTER (WHERE depot_id IS DISTINCT FROM v_twin)
      INTO v_staff_cmd, v_staff_cmd_out FROM public.ottoq_vehicle_commands;

    -- a signed-in user with no staff, operator or member row
    PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000645', 'role', 'authenticated')::text, true);
    SELECT count(*) INTO v_other_veh FROM public.vehicles;
    SELECT count(*) INTO v_other_cmd FROM public.ottoq_vehicle_commands;

    RAISE EXCEPTION '0645 V2 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0645 V2 PROBED' THEN RAISE EXCEPTION '0645 V2: the probe itself failed: %', v_msg; END IF;
  IF current_user NOT IN ('postgres', session_user) THEN RAISE EXCEPTION '0645 V2: role did not revert (%)', current_user; END IF;

  SELECT count(*) INTO v_veh_after FROM public.vehicles WHERE current_depot_id = v_twin OR home_depot_id = v_twin;
  SELECT count(*) INTO v_cmd_after FROM public.ottoq_vehicle_commands WHERE depot_id = v_twin;

  IF NOT v_anon_refused THEN RAISE EXCEPTION '0645 V2 FAILED: anon can still SELECT vehicles'; END IF;
  IF NOT v_anon_rpc THEN RAISE EXCEPTION '0645 V2 FAILED: the cockpit RPC returned nothing as anon'; END IF;
  IF v_staff_veh_out <> 0 OR v_staff_cmd_out <> 0 THEN
    RAISE EXCEPTION '0645 V2 FAILED: staff read % vehicles and % commands outside their depot', v_staff_veh_out, v_staff_cmd_out;
  END IF;
  IF v_staff_veh NOT BETWEEN LEAST(v_veh_before, v_veh_after) AND GREATEST(v_veh_before, v_veh_after)
     OR v_staff_cmd NOT BETWEEN LEAST(v_cmd_before, v_cmd_after) AND GREATEST(v_cmd_before, v_cmd_after) THEN
    RAISE EXCEPTION '0645 V2 FAILED: staff read % vehicles / % commands; the depot held %..% / %..%',
      v_staff_veh, v_staff_cmd, v_veh_before, v_veh_after, v_cmd_before, v_cmd_after;
  END IF;
  IF v_other_veh <> 0 OR v_other_cmd <> 0 THEN
    RAISE EXCEPTION '0645 V2 FAILED: a stranger reads % vehicles / % commands', v_other_veh, v_other_cmd;
  END IF;
  RAISE NOTICE '0645 V2 PASSED: anon refused, cockpit RPC still answers; staff read % vehicles / % commands, all at their depot; a stranger reads 0 / 0',
    v_staff_veh, v_staff_cmd;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0645_the_public_key_reads_no_vehicle_and_no_command', false, false,
  'G393 (security item 1): drops the two USING(true) anon/authenticated SELECT policies on vehicles and '
  'ottoq_vehicle_commands, narrows the fleet-operator vehicles policy to signed-in operators, adds a staff-depot '
  'SELECT policy on commands, and revokes unused anon/authenticated table privileges. Policies and grants only; the '
  'engine runs as postgres/service_role. FALSE/FALSE.',
  now());

COMMIT;
