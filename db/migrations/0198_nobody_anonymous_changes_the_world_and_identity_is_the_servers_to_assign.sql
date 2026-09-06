-- =====================================================================
-- 0198  Nobody anonymous changes the world, and identity is the
--       server's to assign
-- =====================================================================
-- forces_recert = FALSE. This migration changes GRANTS and rewrites two
-- functions that are not on the decide path (the external-proposal
-- submitter and the L1 override authorizer). The pin table taken at the
-- top and compared at the bottom PROVES that no other function body in
-- public, ottoq or twin changed; cron runs as postgres and the edge
-- functions as service_role, and both keep every privilege they had.
--
-- THE FINDING (external audit F1, confirmed here against the catalog)
-- ---------------------------------------------------------------------
-- The core has 332 SECURITY DEFINER functions across public, ottoq and
-- twin. 320 of them are executable by the anon role -- the role the
-- public anon key resolves to, i.e. anyone on the internet who has read
-- the cockpit's JavaScript. 184 of those write by their own body; more
-- write through callees (public.ottoq_sim_stop_and_reset has no INSERT
-- or UPDATE of its own and stops a run). Table grants are already clean:
-- anon and authenticated hold SELECT only on every operational table
-- inspected (ottoq_external_proposals, ottoq_rule_overrides,
-- ottoq_sim_runs, stalls, vehicles, ottoq_stall_bookings,
-- ottoq_policy_params). So SECURITY DEFINER RPC is THE anonymous
-- mutation path, and it is wide open.
--
-- Three of those functions also trust what the caller says about
-- itself:
--   public.ottoq_submit_external_proposal  stores p_source verbatim,
--                                          so anyone can propose as 'cuopt'
--   public.ottoq_l1_override_authorized    compares p_actor_type against
--                                          the rule's minimum role and
--                                          inserts p_actor_id as approved_by,
--                                          so anyone can approve as anyone
--   public.ottoq_sim_stop_and_reset        stops any run, no questions
--
-- "Agents propose, solver disposes" means nothing if the solver cannot
-- tell which agent proposed. That is why this is on the pre-part-B list.
--
-- WHAT THE COCKPIT NEEDS FROM THE CORE (measured, not assumed)
-- ---------------------------------------------------------------------
-- grep over ottoyard-OTTO-Q/src: the cockpit calls exactly one RPC by
-- name, ottoq_sim_set_state, and that function DOES NOT EXIST in the core
-- (it is an MVP-project object); its one .from() against a core-shaped
-- client is ottoq_ps_depot_stalls, an MVP retail table. Every twin
-- control and every chat action goes through an edge function, which
-- authenticates as service_role. Revoking anon EXECUTE on core functions
-- therefore cannot break the cockpit. The staff role vocabulary
-- (charging_tech, cleaning_tech, maintenance_tech, yard_supervisor,
-- ops_manager, retail_concierge) does not match the override function's
-- (depot_tech, depot_supervisor, command_center_operator); a mapping is
-- built here so a real staff identity can be ranked.
--
-- THE THREE MOVES
-- ---------------------------------------------------------------------
-- 1. anon and PUBLIC lose EXECUTE on EVERY SECURITY DEFINER function in
--    public, ottoq and twin. Read-only ones included: a SECURITY DEFINER
--    read runs as postgres and bypasses row security, which is the
--    fleet-isolation half of the same finding. service_role and
--    authenticated are granted explicitly first so the 30 functions that
--    relied on default (PUBLIC) privileges keep working for real callers.
--    The three PostGIS st_estimatedextent overloads are owned by
--    supabase_admin, which postgres cannot act for; they are read-only
--    and A1 lists them rather than pretending.
-- 2. authenticated loses EXECUTE on the engine internals: every function
--    in schemas ottoq and twin, plus an explicit, reviewable list of
--    public control-plane functions (start/stop/advance/reset/deal/
--    tick/governor/emergency). An authenticated cockpit user is an
--    operator of the depot, not of the simulation engine. Read-only
--    ottoq_twin_* views in public keep authenticated so dashboards
--    that authenticate can still read twin state.
-- 3. The two identity-bearing functions derive identity server-side.
--    public.ottoq_caller_identity() classifies the caller as 'system'
--    (no JWT: cron, migrations, psql; or service_role), 'operator'
--    (authenticated with auth.uid()), or 'anonymous'. A system caller's
--    declared source/actor is trusted and RECORDED as system-declared.
--    An operator's source is assigned from auth.uid(), and an
--    operator's override role is looked up in staff_users and mapped --
--    the declared role is stored for the record and ignored for the
--    decision. Anonymous is refused with 42501 even before the grant
--    says so.
--
-- Every grant this migration touches is snapshotted first into
-- public.ottoq_grant_snapshot_0198 (function, acl before, actions), so
-- rollback of any single function is one GRANT and the whole thing is
-- one statement over that table.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Pin every function body BEFORE touching anything.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE pin_0198 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

-- ---------------------------------------------------------------------
-- 1. Snapshot table (permanent; the rollback map).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_grant_snapshot_0198 (
  schema_name    text NOT NULL,
  function_name  text NOT NULL,
  identity_args  text NOT NULL,
  owner_name     text NOT NULL,
  acl_before     text,           -- proacl::text as it stood; NULL = default privileges
  actions        text[] NOT NULL DEFAULT '{}',
  taken_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (schema_name, function_name, identity_args)
);
COMMENT ON TABLE public.ottoq_grant_snapshot_0198 IS
  '0198: EXECUTE grants on every SECURITY DEFINER function in public/ottoq/twin as they stood before 0198, with the actions taken. Rollback of one function: re-grant per acl_before. Not run-scoped.';

REVOKE ALL ON public.ottoq_grant_snapshot_0198 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_grant_snapshot_0198 TO service_role;

-- ---------------------------------------------------------------------
-- 2. Identity helpers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_caller_identity()
 RETURNS TABLE(trust text, jwt_role text, auth_uid uuid, db_session_user text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0198. Who is calling, decided by the SERVER from what PostgREST or the
  -- session actually established -- never from an argument.
  --   system    : no JWT at all (pg_cron, a migration, psql as postgres) or
  --               the service_role key (edge functions). Trusted to name
  --               itself, and recorded as having done so.
  --   operator  : the authenticated role with a real auth.uid().
  --   anonymous : the anon key, or an authenticated JWT with no subject.
  SELECT CASE
           WHEN auth.role() IS NULL                                   THEN 'system'
           WHEN auth.role() = 'service_role'                          THEN 'system'
           WHEN auth.role() = 'authenticated' AND auth.uid() IS NOT NULL THEN 'operator'
           ELSE 'anonymous'
         END,
         auth.role(),
         auth.uid(),
         session_user::text;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_staff_rule_role(p_auth_uid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0198. The staff table speaks one vocabulary (charging_tech, cleaning_tech,
  -- maintenance_tech, yard_supervisor, ops_manager, retail_concierge); the
  -- rule-override authorizer speaks another (depot_tech 1, depot_supervisor 2,
  -- command_center_operator 3). This is the ONLY place they meet. NULL means
  -- "no rank": not staff, not active, or a role with no override authority.
  SELECT CASE s.role::text
           WHEN 'ops_manager'      THEN 'command_center_operator'
           WHEN 'yard_supervisor'  THEN 'depot_supervisor'
           WHEN 'charging_tech'    THEN 'depot_tech'
           WHEN 'cleaning_tech'    THEN 'depot_tech'
           WHEN 'maintenance_tech' THEN 'depot_tech'
           ELSE NULL
         END
    FROM public.staff_users s
   WHERE s.auth_user_id = p_auth_uid
     AND s.is_active
   ORDER BY s.id
   LIMIT 1;
$function$;

-- ---------------------------------------------------------------------
-- 3. The proposal submitter: source is assigned, not declared.
-- ---------------------------------------------------------------------
ALTER TABLE public.ottoq_external_proposals
  ADD COLUMN IF NOT EXISTS declared_source    text,
  ADD COLUMN IF NOT EXISTS submitted_by_role  text,
  ADD COLUMN IF NOT EXISTS submitted_by       uuid;
COMMENT ON COLUMN public.ottoq_external_proposals.declared_source   IS '0198: what the caller SAID its source was. For system callers equals source; for operators it is recorded and ignored.';
COMMENT ON COLUMN public.ottoq_external_proposals.submitted_by_role IS '0198: ottoq_caller_identity().trust at submission (system|operator), plus the JWT role or db session user.';
COMMENT ON COLUMN public.ottoq_external_proposals.submitted_by      IS '0198: auth.uid() of an operator submitter; NULL for system callers.';

CREATE OR REPLACE FUNCTION public.ottoq_submit_external_proposal(p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text DEFAULT 'external'::text, p_ttl_seconds integer DEFAULT 120)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_id uuid;
  v_who RECORD;
  v_source text;
  v_role text;
BEGIN
  SELECT * INTO v_who FROM public.ottoq_caller_identity();

  -- 0198. Identity is the server's to assign.
  IF v_who.trust = 'anonymous' THEN
    RAISE EXCEPTION 'OTTOQ_PROPOSAL_UNAUTHENTICATED: an anonymous caller cannot propose'
      USING ERRCODE = '42501';
  ELSIF v_who.trust = 'system' THEN
    -- cron (postgres), a migration, or an edge function (service_role): the
    -- declared source names the proposer (cuopt, ottoq_service_priority, ...).
    v_source := COALESCE(NULLIF(p_source, ''), 'external');
    v_role   := 'system:' || COALESCE(v_who.jwt_role, 'db:' || v_who.db_session_user);
  ELSE
    -- an operator: the source IS the operator, whatever the client typed.
    v_source := 'operator:' || v_who.auth_uid::text;
    v_role   := 'operator:authenticated';
  END IF;

  UPDATE public.ottoq_external_proposals SET status='superseded'
   WHERE sim_run_id=p_sim_run_id AND action_context=p_action_context
     AND entity_type=p_entity_type AND entity_id=p_entity_id AND status='pending';
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id,depot_id,action_context,entity_type,entity_id,proposal,source,status,expires_at,
     declared_source, submitted_by_role, submitted_by)
  VALUES (p_sim_run_id,p_depot_id,p_action_context,p_entity_type,p_entity_id,p_proposal,v_source,'pending',
          now() + (p_ttl_seconds || ' seconds')::interval,
          p_source, v_role, v_who.auth_uid)
  RETURNING proposal_id INTO v_id;
  RETURN v_id;
END; $function$;

-- ---------------------------------------------------------------------
-- 4. The override authorizer: the actor's rank comes from who they ARE.
-- ---------------------------------------------------------------------
ALTER TABLE public.ottoq_rule_overrides
  ADD COLUMN IF NOT EXISTS declared_actor_type text,
  ADD COLUMN IF NOT EXISTS actor_auth_uid      uuid,
  ADD COLUMN IF NOT EXISTS identity_source     text;
COMMENT ON COLUMN public.ottoq_rule_overrides.declared_actor_type IS '0198: the role the caller CLAIMED. For operators it is recorded and ignored; the ranked role comes from staff_users.';
COMMENT ON COLUMN public.ottoq_rule_overrides.actor_auth_uid      IS '0198: auth.uid() of an operator actor; NULL for system callers.';
COMMENT ON COLUMN public.ottoq_rule_overrides.identity_source     IS '0198: staff_users (operator, looked up) or system:<role> (declared by a trusted caller).';

CREATE OR REPLACE FUNCTION public.ottoq_l1_override_authorized(p_rule_code text, p_actor_type text, p_actor_id text, p_justification text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid, p_fleet_operator_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rule ottoq_rules%ROWTYPE;
  v_id   uuid;
  v_who  RECORD;
  v_actor_type text;
  v_actor_id   text;
  v_identity   text;
BEGIN
  SELECT * INTO v_who FROM public.ottoq_caller_identity();

  -- 0198. Who is asking, decided by the server.
  IF v_who.trust = 'anonymous' THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_UNAUTHENTICATED: an anonymous caller cannot authorize an override'
      USING ERRCODE = '42501';
  ELSIF v_who.trust = 'system' THEN
    -- A trusted system caller (cron, migration, edge function) names the
    -- human it is acting for. That is recorded as system-declared.
    v_actor_type := p_actor_type;
    v_actor_id   := p_actor_id;
    v_identity   := 'system:' || COALESCE(v_who.jwt_role, 'db:' || v_who.db_session_user);
  ELSE
    -- An operator's rank is looked up, never declared.
    v_actor_type := public.ottoq_staff_rule_role(v_who.auth_uid);
    IF v_actor_type IS NULL THEN
      RAISE EXCEPTION 'OTTOQ_OVERRIDE_NO_STAFF_IDENTITY: authenticated user % is not active staff with override authority', v_who.auth_uid
        USING ERRCODE = 'P0001';
    END IF;
    v_actor_id := v_who.auth_uid::text;
    v_identity := 'staff_users';
  END IF;

  SELECT * INTO v_rule FROM ottoq_rules
   WHERE rule_code = p_rule_code AND status IN ('active','shadow')
   ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_UNKNOWN_RULE: %', p_rule_code USING ERRCODE = 'P0001';
  END IF;

  -- 1. the rule must be overridable at all
  IF NOT COALESCE(v_rule.override_allowed, FALSE) THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_FORBIDDEN: rule % is not overridable', p_rule_code USING ERRCODE = 'P0001';
  END IF;

  -- 2. the actor's role must meet/exceed the rule's required min role
  IF ottoq_role_rank(v_actor_type) < ottoq_role_rank(COALESCE(v_rule.override_min_role,'command_center_operator')) THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_ROLE_INSUFFICIENT: % requires %, got %',
      p_rule_code, COALESCE(v_rule.override_min_role,'command_center_operator'), v_actor_type USING ERRCODE = 'P0001';
  END IF;

  -- 3. justification floor (kept; SM.005 audit-note policy, OD-33)
  IF p_justification IS NULL OR length(trim(p_justification)) < 10 THEN
    RAISE EXCEPTION 'OTTOQ_OVERRIDE_JUSTIFICATION_REQUIRED: >=10 chars' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO ottoq_rule_overrides
    (rule_code, rule_version, entity_type, entity_id, override_actor_type, override_actor_id,
     approved_by, justification, effective_from, depot_id, fleet_operator_id, payload,
     declared_actor_type, actor_auth_uid, identity_source)
  VALUES
    (p_rule_code, v_rule.version, p_entity_type, p_entity_id, v_actor_type, v_actor_id,
     v_actor_id, p_justification, NOW(), p_depot_id, p_fleet_operator_id,
     jsonb_build_object('authorized_by','ottoq_l1_override_authorized','min_role',v_rule.override_min_role,
                        'identity_source', v_identity),
     p_actor_type, v_who.auth_uid, v_identity)
  RETURNING override_id INTO v_id;
  RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- 5. The grants. Snapshot, preserve real callers, revoke the anonymous
--    world, then revoke the authenticated role from the engine internals.
-- ---------------------------------------------------------------------
DO $grants$
DECLARE
  r RECORD;
  v_sig text;
  v_actions text[];
  v_ctrl text[] := ARRAY[
    -- public control plane: starts, stops, advances, resets, deals, ticks,
    -- governors, emergency paths. Cron/service only. Read-only ottoq_twin_*
    -- views are deliberately NOT here.
    'busy_day_probe_tick','ottoq_baseline_fifo','ottoq_cert_battery_step','ottoq_cert_recert_floor',
    'ottoq_complete_training_run','ottoq_crn_init_run','ottoq_cron_tick','ottoq_emergency_clear',
    'ottoq_fifo_tick','ottoq_manual_tick','ottoq_ops_set_feed_mode','ottoq_purge_orphan_rows',
    'ottoq_run_governor_auto_stop','ottoq_scenario_apply_fleet_overrides','ottoq_set_demo_speed',
    'ottoq_set_playback','ottoq_sim_advance_and_snapshot','ottoq_sim_advance_due_runs',
    'ottoq_sim_advance_tick','ottoq_sim_advance_tick_world','ottoq_sim_decide_and_dispatch',
    'ottoq_sim_jump_forward','ottoq_sim_mark_stopped','ottoq_sim_release_depot','ottoq_sim_run_scenario',
    'ottoq_sim_stop_and_reset','ottoq_start_demo_run','ottoq_start_training_run',
    'ottoq_tick_invariance_arm','ottoq_tick_invariance_reset_fleet','ottoq_trigger_emergency_cascade',
    'ottoq_twin_deal','ottoq_twin_deal_eta_card','ottoq_twin_deal_fault_card','ottoq_twin_refit_distribution',
    'ottoq_twin_ingest_refresh','ottoq_variability_instantiate','ottoq_determinism_pair',
    'ottoq_reserve_stall','ottoq_retention_purge_worker'];
  v_n int := 0; v_skipped int := 0;
BEGIN
  FOR r IN
    SELECT n.nspname AS sch, p.proname AS fn, p.oid,
           pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_userbyid(p.proowner) AS owner_name,
           p.proacl::text AS acl_before,
           (n.nspname IN ('ottoq','twin') OR (n.nspname = 'public' AND p.proname = ANY (v_ctrl))) AS is_internal
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p') AND p.prosecdef
     ORDER BY n.nspname, p.proname, p.oid
  LOOP
    v_sig := format('%I.%I(%s)', r.sch, r.fn, r.args);
    v_actions := '{}';
    BEGIN
      -- preserve the callers that matter BEFORE touching PUBLIC (30 functions
      -- have default privileges; revoking PUBLIC on those would strand them)
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_sig);
      v_actions := array_append(v_actions, 'grant:service_role');
      IF NOT r.is_internal THEN
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
        v_actions := array_append(v_actions, 'grant:authenticated');
      END IF;
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_sig);
      v_actions := array_append(v_actions, 'revoke:PUBLIC');
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', v_sig);
      v_actions := array_append(v_actions, 'revoke:anon');
      IF r.is_internal THEN
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', v_sig);
        v_actions := array_append(v_actions, 'revoke:authenticated');
      END IF;
      v_n := v_n + 1;
    EXCEPTION WHEN insufficient_privilege THEN
      -- owned by a role postgres cannot act for (supabase_admin). Recorded,
      -- and A1 decides whether that is acceptable.
      v_actions := ARRAY['skipped:not_owner:' || r.owner_name];
      v_skipped := v_skipped + 1;
    END;
    INSERT INTO public.ottoq_grant_snapshot_0198 (schema_name, function_name, identity_args, owner_name, acl_before, actions)
    VALUES (r.sch, r.fn, r.args, r.owner_name, r.acl_before, v_actions)
    ON CONFLICT (schema_name, function_name, identity_args) DO UPDATE
      SET acl_before = EXCLUDED.acl_before, actions = EXCLUDED.actions, taken_at = now();
  END LOOP;
  RAISE NOTICE '0198 grants: % functions re-granted, % skipped (not owner)', v_n, v_skipped;
END $grants$;

-- The two helpers are for real callers only.
REVOKE EXECUTE ON FUNCTION public.ottoq_caller_identity() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ottoq_caller_identity() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.ottoq_staff_rule_role(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ottoq_staff_rule_role(uuid) TO authenticated, service_role;

-- =====================================================================
-- ASSERTIONS
-- =====================================================================
DO $assert$
DECLARE
  v_n int; v_names text; v_msg text;
  v_changed text[]; v_new text[];
  v_rule text; v_uid_mgr uuid; v_uid_sup uuid; v_uid_none uuid := '0198dead-0000-4000-8000-000000000198';
  v_res uuid; v_got text; v_run uuid;
BEGIN
  -- ── A0. THE PIN. Exactly two bodies changed and exactly two are new.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0198 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_l1_override_authorized(p_rule_code text, p_actor_type text, p_actor_id text, p_justification text, p_entity_type text, p_entity_id uuid, p_depot_id uuid, p_fleet_operator_id uuid)',
       'public.ottoq_submit_external_proposal(p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text, p_ttl_seconds integer)'] THEN
    RAISE EXCEPTION '0198 A0 FAILED: function bodies changed = % -- the decide path must not be among them', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0198 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY['public.ottoq_caller_identity()','public.ottoq_staff_rule_role(p_auth_uid uuid)'] THEN
    RAISE EXCEPTION '0198 A0 FAILED: new functions = %, expected only the two identity helpers', v_new;
  END IF;
  RAISE NOTICE '0198 A0: two bodies changed (submit, override), two helpers new, nothing else moved';

  -- ── A1. NO anonymous execute remains on any postgres-owned SECURITY DEFINER
  --     function in the three schemas. Functions postgres could not touch are
  --     listed; if any of them writes, the class is not closed and we stop.
  SELECT count(*), string_agg(n.nspname||'.'||p.proname, ', ') INTO v_n, v_names
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p') AND p.prosecdef
     AND pg_get_userbyid(p.proowner) = 'postgres'
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR p.proacl IS NULL
          OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) e WHERE e.grantee = 0 AND e.privilege_type = 'EXECUTE'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0198 A1 FAILED: % postgres-owned SECURITY DEFINER functions still executable by anon/PUBLIC: %', v_n, v_names;
  END IF;
  SELECT count(*), string_agg(schema_name||'.'||function_name, ', ') INTO v_n, v_names
    FROM public.ottoq_grant_snapshot_0198 WHERE actions[1] LIKE 'skipped:%';
  IF v_n > 0 THEN
    -- any skipped function that writes by body is a failure, not a footnote
    SELECT count(*) INTO v_n
      FROM public.ottoq_grant_snapshot_0198 g
      JOIN pg_namespace n ON n.nspname = g.schema_name
      JOIN pg_proc p ON p.pronamespace = n.oid AND p.proname = g.function_name
                    AND pg_get_function_identity_arguments(p.oid) = g.identity_args
     WHERE g.actions[1] LIKE 'skipped:%'
       AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g') ~* '\m(insert|update|delete|truncate)\M';
    IF v_n > 0 THEN
      RAISE EXCEPTION '0198 A1 FAILED: % function(s) postgres cannot revoke on WRITE and stay anon-executable: %', v_n, v_names;
    END IF;
    RAISE NOTICE '0198 A1: anon/PUBLIC execute is gone from every postgres-owned SECURITY DEFINER function; read-only functions postgres could not touch: %', v_names;
  ELSE
    RAISE NOTICE '0198 A1: anon/PUBLIC execute is gone from every SECURITY DEFINER function in public, ottoq, twin';
  END IF;

  -- ── A2. service_role kept EXECUTE on every function processed.
  SELECT count(*), string_agg(g.schema_name||'.'||g.function_name, ', ') INTO v_n, v_names
    FROM public.ottoq_grant_snapshot_0198 g
    JOIN pg_namespace n ON n.nspname = g.schema_name
    JOIN pg_proc p ON p.pronamespace = n.oid AND p.proname = g.function_name
                  AND pg_get_function_identity_arguments(p.oid) = g.identity_args
   WHERE g.actions[1] NOT LIKE 'skipped:%'
     AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0198 A2 FAILED: service_role lost EXECUTE on % function(s): %', v_n, v_names;
  END IF;
  RAISE NOTICE '0198 A2: service_role holds EXECUTE on every processed function (cron is postgres and owns them)';

  -- ── A3. authenticated: none in ottoq/twin, none on the public control plane,
  --     still present on the two identity-bearing operator RPCs.
  SELECT count(*), string_agg(n.nspname||'.'||p.proname, ', ') INTO v_n, v_names
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('ottoq','twin') AND p.prokind IN ('f','p') AND p.prosecdef
     AND pg_get_userbyid(p.proowner) = 'postgres'
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0198 A3 FAILED: authenticated still executes % engine-internal function(s): %', v_n, v_names;
  END IF;
  IF has_function_privilege('authenticated', 'public.ottoq_sim_stop_and_reset(uuid, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_cron_tick()', 'EXECUTE') THEN
    RAISE EXCEPTION '0198 A3 FAILED: authenticated can still stop runs or run the tick';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.ottoq_submit_external_proposal(uuid, uuid, text, text, uuid, jsonb, text, integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_l1_override_authorized(text, text, text, text, text, uuid, uuid, uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0198 A3 FAILED: authenticated lost the two operator RPCs that now derive identity';
  END IF;
  RAISE NOTICE '0198 A3: authenticated is out of ottoq/twin and the control plane, and keeps the operator RPCs';

  -- ── A4. LIVE, ROLLED BACK: as anon, the world cannot be changed.
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.ottoq_sim_stop_and_reset('01980000-0000-4000-8000-000000000198'::uuid, 'probe');
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = 'stop_and_reset:ALLOWED';
  EXCEPTION
    WHEN insufficient_privilege THEN v_msg := 'stop_and_reset:42501';
    WHEN SQLSTATE 'P0198' THEN v_msg := SQLERRM;
  END;
  RESET ROLE;
  IF v_msg <> 'stop_and_reset:42501' THEN RAISE EXCEPTION '0198 A4 FAILED: anon %', v_msg; END IF;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM public.ottoq_submit_external_proposal('01980000-0000-4000-8000-000000000198'::uuid,
              '11111111-1111-1111-1111-111111111111'::uuid, 'probe', 'vehicle',
              '01980000-0000-4000-8000-000000000001'::uuid, '{}'::jsonb, 'cuopt', 5);
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = 'submit:ALLOWED';
  EXCEPTION
    WHEN insufficient_privilege THEN v_msg := 'submit:42501';
    WHEN SQLSTATE 'P0198' THEN v_msg := SQLERRM;
  END;
  RESET ROLE;
  IF v_msg <> 'submit:42501' THEN RAISE EXCEPTION '0198 A4 FAILED: anon %', v_msg; END IF;
  RAISE NOTICE '0198 A4: anon is refused by the grant on stop_and_reset and submit_external_proposal';

  -- ── A5. LIVE, ROLLED BACK: an operator's rank is who they are, not what they say.
  SELECT rule_code INTO v_rule FROM public.ottoq_rules
   WHERE override_allowed AND status IN ('active','shadow') AND override_min_role = 'command_center_operator'
   ORDER BY rule_code LIMIT 1;
  SELECT auth_user_id INTO v_uid_mgr FROM public.staff_users WHERE role::text = 'ops_manager'     AND is_active AND auth_user_id IS NOT NULL ORDER BY id LIMIT 1;
  SELECT auth_user_id INTO v_uid_sup FROM public.staff_users WHERE role::text = 'yard_supervisor' AND is_active AND auth_user_id IS NOT NULL ORDER BY id LIMIT 1;
  IF v_rule IS NULL OR v_uid_mgr IS NULL OR v_uid_sup IS NULL THEN
    RAISE EXCEPTION '0198 A5 FAILED: fixture missing (rule %, manager %, supervisor %)', v_rule, v_uid_mgr, v_uid_sup;
  END IF;
  -- (a) manager, DECLARING a low role: succeeds, recorded at the looked-up role
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','sub',v_uid_mgr)::text, true);
    v_res := public.ottoq_l1_override_authorized(v_rule, 'depot_tech', 'spoofed-actor-id', 'probe 0198: identity beats declaration');
    SELECT override_actor_type||'|'||approved_by||'|'||identity_source||'|'||declared_actor_type INTO v_got
      FROM public.ottoq_rule_overrides WHERE override_id = v_res;
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = v_got;
  EXCEPTION WHEN SQLSTATE 'P0198' THEN v_got := SQLERRM;
  END;
  IF v_got IS DISTINCT FROM 'command_center_operator|'||v_uid_mgr::text||'|staff_users|depot_tech' THEN
    RAISE EXCEPTION '0198 A5(a) FAILED: manager override recorded as %, expected command_center_operator from staff_users with approved_by = auth.uid()', v_got;
  END IF;
  -- (b) supervisor, DECLARING command_center_operator: refused for rank, declaration ignored
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','sub',v_uid_sup)::text, true);
    v_res := public.ottoq_l1_override_authorized(v_rule, 'command_center_operator', 'spoofed-actor-id', 'probe 0198: declaration cannot escalate');
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = 'ALLOWED';
  EXCEPTION
    WHEN SQLSTATE 'P0198' THEN v_got := SQLERRM;
    WHEN OTHERS THEN v_got := SQLERRM;
  END;
  IF v_got !~ 'OTTOQ_OVERRIDE_ROLE_INSUFFICIENT.*got depot_supervisor' THEN
    RAISE EXCEPTION '0198 A5(b) FAILED: supervisor declaring command_center_operator got: %', v_got;
  END IF;
  -- (c) authenticated but not staff: refused
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','sub',v_uid_none)::text, true);
    v_res := public.ottoq_l1_override_authorized(v_rule, 'command_center_operator', 'x', 'probe 0198: not staff at all');
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = 'ALLOWED';
  EXCEPTION
    WHEN SQLSTATE 'P0198' THEN v_got := SQLERRM;
    WHEN OTHERS THEN v_got := SQLERRM;
  END;
  IF v_got !~ 'OTTOQ_OVERRIDE_NO_STAFF_IDENTITY' THEN
    RAISE EXCEPTION '0198 A5(c) FAILED: non-staff authenticated user got: %', v_got;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE '0198 A5: manager ranked from staff_users despite declaring depot_tech; supervisor refused despite declaring command_center_operator; non-staff refused';

  -- ── A6. LIVE, ROLLED BACK: an operator's proposal source is assigned; a system's is trusted and recorded.
  -- The proposals table carries fk_ottoq_external_proposals_sim_run, so the probe rides a real, completed
  -- flagship run (the rows never persist: each probe raises inside a handled block and rolls itself back).
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'completed'
   ORDER BY started_at DESC, sim_run_id DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0198 A6 FIXTURE: no completed flagship run to ride'; END IF;
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role','authenticated','sub',v_uid_mgr)::text, true);
    v_res := public.ottoq_submit_external_proposal(v_run,
              '11111111-1111-1111-1111-111111111111'::uuid, 'probe', 'vehicle',
              '01980000-0000-4000-8000-000000000001'::uuid, '{}'::jsonb, 'cuopt', 5);
    SELECT source||'|'||declared_source||'|'||submitted_by_role||'|'||coalesce(submitted_by::text,'NULL') INTO v_got
      FROM public.ottoq_external_proposals WHERE proposal_id = v_res;
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = v_got;
  EXCEPTION WHEN SQLSTATE 'P0198' THEN v_got := SQLERRM;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_got IS DISTINCT FROM 'operator:'||v_uid_mgr::text||'|cuopt|operator:authenticated|'||v_uid_mgr::text THEN
    RAISE EXCEPTION '0198 A6(a) FAILED: operator proposal stored as %, expected source operator:<uid> with declared cuopt', v_got;
  END IF;
  BEGIN
    -- no JWT: this very session (a migration) is a system caller
    v_res := public.ottoq_submit_external_proposal(v_run,
              '11111111-1111-1111-1111-111111111111'::uuid, 'probe', 'vehicle',
              '01980000-0000-4000-8000-000000000002'::uuid, '{}'::jsonb, 'cuopt', 5);
    SELECT source||'|'||declared_source||'|'||submitted_by_role INTO v_got
      FROM public.ottoq_external_proposals WHERE proposal_id = v_res;
    RAISE EXCEPTION USING ERRCODE = 'P0198', MESSAGE = v_got;
  EXCEPTION WHEN SQLSTATE 'P0198' THEN v_got := SQLERRM;
  END;
  IF v_got !~ '^cuopt\|cuopt\|system:db:' THEN
    RAISE EXCEPTION '0198 A6(b) FAILED: system proposal stored as %, expected source cuopt recorded as system:db:<session_user>', v_got;
  END IF;
  RAISE NOTICE '0198 A6: operator source assigned from auth.uid(); system source trusted and recorded as system-declared';

  -- ── A7. The rollback map covers every SECURITY DEFINER function in the three schemas.
  SELECT count(*) INTO v_n FROM public.ottoq_grant_snapshot_0198;
  IF v_n < 300 THEN RAISE EXCEPTION '0198 A7 FAILED: snapshot holds % rows, expected the full census (>= 300)', v_n; END IF;
  RAISE NOTICE '0198 A7: % functions snapshotted with their prior acl and the actions taken', v_n;

  RAISE NOTICE '0198: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0198_nobody_anonymous_changes_the_world_and_identity_is_the_servers_to_assign', FALSE,
  'External audit F1, confirmed against the catalog: 320 of 332 SECURITY DEFINER functions in public/ottoq/twin were executable by anon, '
  '184 write by body and more through callees (ottoq_sim_stop_and_reset); table grants were already SELECT-only for anon/authenticated, '
  'so SECURITY DEFINER RPC was the anonymous mutation path. Three functions trusted caller-declared identity: submit_external_proposal '
  'stored p_source verbatim, l1_override_authorized ranked p_actor_type and inserted p_actor_id as approved_by, sim_stop_and_reset '
  'stopped any run. Measured before changing: the cockpit calls one RPC by name and it does not exist in the core; all twin control goes '
  'through service_role edge functions. Moves: (1) anon and PUBLIC lose EXECUTE on every SECURITY DEFINER function in the three schemas, '
  'service_role and authenticated granted explicitly first so the 30 default-privilege functions keep their real callers; (2) authenticated '
  'loses EXECUTE on schemas ottoq and twin and on an explicit public control-plane list; (3) ottoq_caller_identity() classifies the caller '
  'as system (no JWT or service_role), operator (authenticated + auth.uid()) or anonymous; the submitter assigns source operator:<uid> to '
  'operators and trusts/records a system caller''s declared source; the authorizer ranks an operator from staff_users via '
  'ottoq_staff_rule_role() (ops_manager->command_center_operator, yard_supervisor->depot_supervisor, *_tech->depot_tech) and ignores the '
  'declared role. A0 pins md5 of every function body before and after: exactly two changed, two helpers new, decide path untouched. '
  'A4-A6 are live probes rolled back: anon refused with 42501; a manager declaring depot_tech is recorded as command_center_operator with '
  'approved_by = auth.uid(); a supervisor declaring command_center_operator is refused for rank; a non-staff user is refused; an operator '
  'proposal is stored as operator:<uid> with declared_source recorded. Every prior acl is in ottoq_grant_snapshot_0198 for rollback. '
  'forces_recert=FALSE: no engine function changed (A0), cron runs as postgres, edge functions as service_role, both unaffected.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-06 03:21:56 UTC (10:21:56 PM CT, Sep 5) -- one
-- transaction as postgres, third attempt. Attempts 1 and 2 rolled back
-- whole: 22P02 (text[] || 'literal' is array concatenation in plpgsql;
-- array_append now) and 23503 (A6 rode a synthetic sim_run_id into
-- fk_ottoq_external_proposals_sim_run; it now selects the newest
-- completed flagship run, 347773ec at apply time). Before each retry
-- the rollback was measured clean: snapshot table absent, both helpers
-- absent, all six new columns absent, anon still holding EXECUTE on the
-- submitter. No determinism pair was scheduled or in flight.
--
-- The SQL endpoint returns no NOTICEs, so the post-state was measured
-- by independent queries after COMMIT rather than read off A0-A7:
--
--   snapshot rows                        334  = 332 SECURITY DEFINER that
--                                               existed + the 2 helpers
--     by schema                          ottoq 50, public 233, twin 51
--     postgres-owned, actioned           331
--       keep authenticated               192  (public, not control plane)
--       lose authenticated               139  (ottoq 50 + twin 51 + 38
--                                               public control-plane)
--     supabase_admin-owned, untouched      3  (see CORRECTION)
--     had default privileges before       30
--   anon EXECUTE remaining
--     on postgres-owned SECURITY DEFINER   0
--     in total                             3  st_estimatedextent x3, PostGIS
--                                               C estimators, read-only
--   authenticated EXECUTE in ottoq/twin    0
--   probe rows persisted                   0 proposals, 0 overrides
--   lineage                                forces_recert = false
--   first cron tick after apply            03:22:00 UTC, ottoq-depot-tick
--                                          and ottoq-demo-metronome both
--                                          succeeded (cron is postgres;
--                                          the grant sweep cannot see it)
--   function bodies changed (A0)           2, the submitter and the
--                                          authorizer; decide path pinned
--                                          and unchanged
--
-- CORRECTION (appended 03:24 UTC, applied; nothing above is rewritten)
-- ---------------------------------------------------------------------
-- The header says postgres "cannot act for" supabase_admin and that A1
-- lists the three st_estimatedextent overloads. The outcome was right
-- and the mechanism was wrong: a GRANT or REVOKE by a non-owner without
-- grant option is a WARNING in Postgres, not insufficient_privilege, so
-- the loop's handler never fired, skipped = 0, A1 had nothing to list,
-- and the snapshot recorded four actions on each of the three rows
-- while their acl did not move (acl_before = proacl after, verified).
-- A1 still passed honestly because it filters to postgres-owned
-- functions. The right guard is r.owner_name <> current_user before
-- issuing anything, not a handler after. The three rows now say what
-- happened. Statement run:
--
--   UPDATE public.ottoq_grant_snapshot_0198 g
--      SET actions = ARRAY['noop:not_owner:' || g.owner_name || ':acl_unchanged']
--     FROM pg_namespace n, pg_proc p
--    WHERE n.nspname = g.schema_name AND p.pronamespace = n.oid
--      AND p.proname = g.function_name
--      AND pg_get_function_identity_arguments(p.oid) = g.identity_args
--      AND g.owner_name <> 'postgres'
--      AND p.proacl::text = g.acl_before;
--   -- 3 rows: st_estimatedextent(text,text) / (text,text,text) /
--   --         (text,text,text,boolean), owner supabase_admin
--
-- Those three remain anon-executable. They read table statistics for a
-- geometry column and write nothing; closing them needs supabase_admin,
-- which no agent here holds. Recorded, not hidden.
--
-- What this closes: external audit F1 (anonymous mutation through
-- SECURITY DEFINER RPC; caller-declared identity in proposals and
-- overrides). What it does not touch: any decide-path function (A0),
-- cron (postgres), edge functions (service_role). No recert is owed and
-- none was scheduled.
-- =====================================================================
