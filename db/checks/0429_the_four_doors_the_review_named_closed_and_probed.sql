-- 0429  **The four doors the twin data contract review named are closed, each probed as the role it was open to.**
--        Security items 1-4 of the review of 2026-10-08 (G393), built 2026-10-09 between 5:00 and 6:40 PM CT by
--        0647, 0648, 0649 and ottoq-ingest v16. Twin depot 11111111-…. Every probe below is read-only or rolls back.
--
-- ══ §1 WHAT WAS OPEN, WHAT CLOSED IT, AND THE PROOF ══
--
--     item                                   open to          closed by                      proof (reproduce)
--     1 vehicles + commands readable          the public key   0647 (20261009232411)          (1) (2)
--       by anyone (226 cars, 129,015 commands)
--     2 command dock: lease, peek, ack         the public key,  0648 (20261009232737)          (3)
--       (five SECURITY DEFINER functions)      any login
--     3 otto-q-api mints a trusted source      anyone (no JWT)  0649 (20261009233223)          (4), and the HTTP probe in
--       key for any depot                                                                       0649's APPLIED note
--     4 ottoq-ingest takes depot + data        the public key   0649 + ottoq-ingest v16         _MANIFEST.md footnote 10
--       source from the body                                                                    (seven live probes)
--
--   As each role after the change (2): the public key is refused vehicles and ottoq_vehicle_commands, and the cockpit's
--   SECURITY DEFINER RPCs still answer it; twin-depot staff read 120 vehicles and 128,855 commands, all at their depot;
--   a signed-in account with no staff or operator row reads 0 and 0.
--
-- ══ §2 FOUR THINGS THE REVIEW DID NOT SAY, FOUND WHILE CLOSING IT ══
--
--   (a) The dock was five functions, not two. Besides the two claims, the public key could acknowledge energy
--       commands (ottoq_energy_ack_command, also PUBLIC), and any login could peek at pending production commands and
--       acknowledge vehicle commands. 0648 closed all five. The robovac bridge, the one caller, uses the service key.
--   (b) Supabase's connector holds any DROP for an approval prompt that, in a cloud session, expires unseen after
--       60 s, and the SQL never reaches Postgres (nothing in pg_stat_statements; ledger unchanged). ALTER, REVOKE,
--       CREATE and comments containing the word run at once. So 0647 retires the two open policies (service_role
--       only, renamed "retired 0647: …") instead of dropping them; dropping them waits for someone at the prompt.
--   (c) The functions gateway now refuses legacy JWT keys (UNAUTHORIZED_LEGACY_JWT). Every app still ships the
--       legacy anon key in its code, so it reaches PostgREST but not a verify_jwt function. That is why ottoq-ingest
--       v16 runs with verify_jwt off and checks every credential itself.
--   (d) The public key still reads 284 public tables: 242 with row security off and 42 with an open policy, 81 of
--       them carrying vehicle or operator ids, among them ottoq_events (~2.76M rows), ottoq_comms_messages (~903K),
--       itinerary legs, stall bookings, visit needs, the deploy log and ops approvals (5). Items 1-4 shut the four
--       doors the review named; this is the room behind them. Not closed here: the cockpits read about a dozen of
--       these tables directly with the public key, and a default deny changes how every session builds a cockpit
--       feature, so it is a decision for Chase (G394).
--
-- ══ §3 WHAT IS STILL OPEN BY DESIGN OF THIS STEP (G394) ══
--
--   otto-q-api's other write routes (tasks, vehicles, stalls, scheduler, ai, ottow missions) still need no credential.
--   No app calls them (24 h of logs: the OTTOYARD app's four GETs only), and the function is one 399 KB file that this
--   session cannot redeploy without retyping it; its key-revoke route now answers {revoked: true} while changing
--   nothing. otto-twin-control's mutation gate is still commented out (review item 5; the twin app sends no key yet).
--   The field-ops demo logins share one password in a public repo. Webhook signing (item 6) and CORS (item 7) are
--   unchanged.
--
-- ══ REPRODUCE ══

-- (1) the policies and grants as they stand
SELECT tablename, policyname, roles, cmd, qual
  FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('vehicles', 'ottoq_vehicle_commands')
 ORDER BY tablename, policyname;
SELECT t, has_table_privilege('anon', t, 'SELECT') AS anon_select, has_table_privilege('anon', t, 'TRUNCATE') AS anon_truncate,
       has_table_privilege('authenticated', t, 'SELECT') AS auth_select, has_table_privilege('authenticated', t, 'TRUNCATE') AS auth_truncate
  FROM unnest(ARRAY['public.vehicles', 'public.ottoq_vehicle_commands']) AS t;

-- (2) as each role, in a block that rolls itself back
DO $as_each_role$
DECLARE r text := ''; n bigint; m bigint; v_staff uuid;
BEGIN
  SELECT auth_user_id INTO v_staff FROM public.staff_users
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND auth_user_id IS NOT NULL ORDER BY created_at LIMIT 1;
  BEGIN
    PERFORM set_config('role', 'anon', true);
    BEGIN SELECT count(*) INTO n FROM public.vehicles; r := r || 'anon vehicles=' || n;
    EXCEPTION WHEN insufficient_privilege THEN r := r || 'anon vehicles=REFUSED'; END;
    BEGIN SELECT count(*) INTO n FROM public.ottoq_vehicle_commands; r := r || ', anon commands=' || n;
    EXCEPTION WHEN insufficient_privilege THEN r := r || ', anon commands=REFUSED'; END;
    r := r || ', anon cockpit rpc answers=' || (public.ottoq_depot_cards(NULL, NULL) IS NOT NULL);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    SELECT count(*) INTO n FROM public.vehicles; SELECT count(*) INTO m FROM public.ottoq_vehicle_commands;
    r := r || ' | staff vehicles=' || n || ', commands=' || m;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000429', 'role', 'authenticated')::text, true);
    SELECT count(*) INTO n FROM public.vehicles; SELECT count(*) INTO m FROM public.ottoq_vehicle_commands;
    r := r || ' | stranger vehicles=' || n || ', commands=' || m;
    RAISE EXCEPTION 'AS EACH ROLE: %', r;   -- rolls the role and claims back; the message is the reading
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE '%', SQLERRM;
  END;
END $as_each_role$;

-- (3) the dock
SELECT p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_fleet_claim_commands', 'ottoq_energy_claim_commands', 'ottoq_energy_ack_command',
                     'ottoq_fleet_pending_commands', 'ottoq_ack_vehicle_command')
 ORDER BY 1;
SELECT count(*) FILTER (WHERE delivered_at IS NOT NULL) AS delivered_ever FROM public.ottoq_vehicle_commands;

-- (4) the source-key registry: every key's binding, and that only the issuer can write one
SELECT key_prefix, source, source_name, data_source, streams, is_active, revoked_at, revoke_reason, last_used_at
  FROM public.ottow_api_keys ORDER BY created_at;
SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid = 'public.ottow_api_keys'::regclass AND NOT tgisinternal;

-- (5) the room behind the doors (G394): tables the public key can read with no row security or an open policy
WITH t AS (
  SELECT c.relname, c.relrowsecurity AS rls, c.reltuples::bigint AS est_rows,
         EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname IN ('vehicle_id', 'fleet_operator_id')
                    AND NOT a.attisdropped) AS tenant_cols,
         EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname
                    AND p.cmd IN ('SELECT', 'ALL') AND p.roles && ARRAY['anon', 'public']::name[] AND p.qual = 'true') AS open_policy
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND has_table_privilege('anon', c.oid, 'SELECT'))
SELECT count(*) FILTER (WHERE NOT rls) AS no_rls, count(*) FILTER (WHERE rls AND open_policy) AS open_policy,
       count(*) FILTER (WHERE (NOT rls OR open_policy) AND tenant_cols) AS with_vehicle_or_operator_ids
  FROM t;
