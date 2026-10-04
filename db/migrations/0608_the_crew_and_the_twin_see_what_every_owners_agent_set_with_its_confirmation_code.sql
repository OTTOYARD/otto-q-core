-- migration-version: PENDING
-- migration-name:    the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code
--
-- 0608  **The crew and the twin see what every owner's agent set, with its confirmation code.** One new read-only
--       function for OTTO-PULSE and OTTO-TWIN -- everything owners' agents have set at the depot, per car and as a
--       list, the agents connected, and each command's receipt with its confirmation code -- and 0606's OrchestrAV read
--       extended with the same code and the agent's own name. Both granted to anon, as 0606 was: the cockpits and the
--       twin open with no sign-in (OrchestrAV #32, PULSE #27).
--
--       Chase, 2026-10-03, 10:50 PM CT: "...a confirmation and validation code with link to the orchestra app and
--       updated information"; and earlier the same day: "validate that an agent could check in and control those and
--       then it's visible in the UI, both orchestra and pulse as well as the twin simulator."
--
-- ══ §1 WHAT IT IS FOR ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   0606 gave OrchestrAV one owner's view. OTTO-PULSE is the depot crew's cockpit and shows every owner, and OTTO-TWIN
--   draws the whole depot; neither could see that an agent had set a car to stop at 90%, ordered it a wash, or held it,
--   though the engine acts on all three at its next tick. And 0607's confirmation code was on the agent's receipt
--   only.
--
-- ══ §2 WHAT anon CAN THEN SEE, AND WHAT IT CANNOT ═══════════════════════════════════════════════════════════════════
--
--   public.ottoq_depot_owner_board(p_depot_id DEFAULT the twin, p_limit DEFAULT 30), read-only (asserted before the
--   grant, as 0606):
--     * in_force    every owner setting active on the depot's live run: car, owner, the limit / hold / order, who set
--                   it, its command's confirmation code, and whether the engine has applied it yet;
--     * by_vehicle  the same keyed by vehicle id, for a car's card and the 3D marker;
--     * commands    the last p_limit (1-100) non-preview owner commands at the depot: tool, outcome, the receipt's
--                   first line and full text, confirmation code, agent and how it got in (passcode or key), owner,
--                   cars, link, and whether it is still in force, undone or lifted with its run;
--     * agents      the agents connected now (a passcode session not ended or expired; a key used in the last hour)
--                   and passcode sessions that ended in the last two hours, by display name only.
--   It never returns a key, a key prefix, a principal id, a passcode or a call. 0606's ottoq_owner_board gains
--   `confirmation_code`, `agent` (the display name a passcode agent gave) and `agent_via` on each command; nothing is
--   removed from it.
--
-- ══ §3 forces_recert FALSE, forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   Two read-only functions and a grant. Nothing on the tick path calls either (V3); a privilege bit and a read are
--   invisible to every certification atom and dial arm.

BEGIN;

-- ── P1: 0607 applied; 0606's board is the body this file extends ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code') THEN
    RAISE EXCEPTION '0608 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends') THEN
    RAISE EXCEPTION '0608 P1: 0607 (the passcode door and the confirmation code) is not applied; apply it first';
  END IF;
  IF to_regprocedure('public.ottoq_owner_board(uuid,uuid,uuid)') IS NULL
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure)
        IS DISTINCT FROM 'e8597b11063f82e9c9ff8f5d45b658ee' THEN
    RAISE EXCEPTION '0608 P1: ottoq_owner_board is not 0606''s body (re-measure before applying)';
  END IF;
  IF to_regprocedure('public.ottoq_depot_owner_board(uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION '0608 P1: ottoq_depot_owner_board already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0608_pre', 'function', 'public', 'ottoq_owner_board',
       pg_get_functiondef('public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure));

-- ══ 1. OrchestrAV's read, with the confirmation code and the agent's own name ═════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_owner_board(
    p_fleet_operator_id uuid,
    p_depot_id          uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_command_id        uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0606. OrchestrAV's view of what ONE owner's agent set: the settings in force on the live run, per car and as lists,
   the owner's recent commands with their plain-English receipts, and the command a receipt link names. Never every
   operator at once; never previews; never a token, principal id or call. Read-only (asserted before the grant).
   0608: each command also carries its confirmation code (0607), the agent's own name and how it got in. */
DECLARE
  v_name    text;
  v_run     jsonb;
  v_run_id  uuid;
  v_force   jsonb;
  v_by_car  jsonb;
  v_cmds    jsonb;
  v_hl      jsonb;
  v_ceiling numeric;
BEGIN
  IF p_fleet_operator_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fleet_operator_required', 'message', 'Name the fleet operator whose settings to read.');
  END IF;
  SELECT f.name INTO v_name FROM public.fleet_operators f WHERE f.id = p_fleet_operator_id;
  IF v_name IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_fleet_operator', 'message', 'No such fleet operator.');
  END IF;
  v_run := public.ottoq_agent_live_run(p_depot_id);
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  v_ceiling := COALESCE((public.ottoq_owner_contract(p_fleet_operator_id, COALESCE((v_run ->> 'sim_clock')::timestamptz, now())) ->> 'max_charge_pct')::numeric,
                        public.ottoq_default_target_soc());

  SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'setting_id', o.setting_id, 'kind', o.kind, 'vehicle_id', o.vehicle_id, 'vehicle', v.display_name,
           'charge_limit_pct', o.charge_limit_pct,
           'hold_until_sim', o.hold_until_sim, 'hold_until_local', public.ottoq_owner_clock(o.hold_until_sim, true, true),
           'service', o.service, 'service_name', c.display_name, 'when', o.service_when,
           'set_at', o.set_at, 'set_at_local', public.ottoq_owner_clock(o.set_at, false),
           'command_id', o.command_id, 'waiting_for_tick', o.pending_reconcile))
           ORDER BY o.kind, v.display_name, o.service), '[]'::jsonb)
    INTO v_force
    FROM public.ottoq_owner_settings o
    JOIN public.vehicles v ON v.id = o.vehicle_id
    LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
   WHERE o.sim_run_id = v_run_id AND o.fleet_operator_id = p_fleet_operator_id AND o.depot_id = p_depot_id
     AND o.status = 'active';

  SELECT COALESCE(jsonb_object_agg(x.vehicle_id, x.card), '{}'::jsonb) INTO v_by_car
    FROM (SELECT s ->> 'vehicle_id' AS vehicle_id,
                 jsonb_strip_nulls(jsonb_build_object(
                   'charge_limit_pct', max((s ->> 'charge_limit_pct')::numeric),
                   'full_pct', v_ceiling,
                   'hold_until_sim', max(s ->> 'hold_until_sim'),
                   'hold_until_local', max(s ->> 'hold_until_local'),
                   'orders', jsonb_agg(jsonb_build_object('service', s ->> 'service', 'name', s ->> 'service_name',
                                                          'when', s ->> 'when'))
                             FILTER (WHERE s ->> 'kind' = 'service'))) AS card
            FROM jsonb_array_elements(v_force) s GROUP BY 1) x;

  SELECT COALESCE(jsonb_agg(q.j ORDER BY q.created_at DESC), '[]'::jsonb) INTO v_cmds
    FROM (SELECT c.created_at, jsonb_strip_nulls(jsonb_build_object(
                   'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome, 'summary', c.summary,
                   'confirmation_code', CASE WHEN c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(c.command_id) END,
                   'agent', COALESCE(a.display_name, c.principal_name),
                   'agent_via', CASE WHEN a.origin = 'passcode' THEN 'passcode' ELSE 'key' END,
                   'cars', jsonb_array_length(c.vehicles),
                   'vehicle_ids', (SELECT jsonb_agg(x -> 'id') FROM jsonb_array_elements(c.vehicles) x),
                   'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
                   'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
                   'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
                   'link', c.link, 'refusal', c.refusal,
                   'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason)) AS j
            FROM public.ottoq_owner_commands c
            LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = c.principal_id
           WHERE c.fleet_operator_id = p_fleet_operator_id AND c.depot_id = p_depot_id AND c.outcome <> 'previewed'
           ORDER BY c.created_at DESC
           LIMIT 20) q;

  IF p_command_id IS NOT NULL THEN
    SELECT jsonb_strip_nulls(jsonb_build_object(
             'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome, 'summary', c.summary,
             'confirmation_code', CASE WHEN c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(c.command_id) END,
             'agent', COALESCE(a.display_name, c.principal_name),
             'agent_via', CASE WHEN a.origin = 'passcode' THEN 'passcode' ELSE 'key' END,
             'vehicles', c.vehicles, 'effects', c.effects, 'args', c.args - 'idempotency_key',
             'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
             'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
             'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
             'link', c.link, 'refusal', c.refusal,
             'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason))
      INTO v_hl
      FROM public.ottoq_owner_commands c
      LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = c.principal_id
     WHERE c.command_id = p_command_id AND c.fleet_operator_id = p_fleet_operator_id AND c.outcome <> 'previewed';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'fleet_operator', jsonb_build_object('id', p_fleet_operator_id, 'name', v_name),
    'depot_id', p_depot_id,
    'run', CASE WHEN v_run IS NULL THEN NULL ELSE jsonb_build_object(
             'sim_run_id', v_run_id, 'status', v_run ->> 'status', 'demo', v_run ->> 'run_by' = 'operator_demo',
             'sim_clock', v_run -> 'sim_clock', 'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)) END,
    'full_pct', v_ceiling,
    'in_force', v_force,
    'by_vehicle', v_by_car,
    'counts', jsonb_build_object(
      'charge_limits', (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'charge_limit'),
      'holds',         (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'hold'),
      'orders',        (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'service')),
    'commands', v_cmds,
    'highlight', v_hl,
    'resets', 'Everything an agent sets lasts until the demo run ends or the agent undoes it; a stop or reset of the twin puts every car back to baseline.',
    'clocks', '"sim time" is SIMULATION time in Nashville local time; CT is real time.');
END $fn$;

-- ══ 2. the crew's and the twin's read: every owner at the depot ═══════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ottoq_depot_owner_board(
    p_depot_id uuid    DEFAULT '11111111-1111-1111-1111-111111111111'::uuid,
    p_limit    integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0608. What every owner's agent set at one depot, for OTTO-PULSE (the crew) and OTTO-TWIN (the 3D depot): settings in
   force on the live run per car and as a list, the agents connected, and the last owner commands with their receipts
   and confirmation codes. Never a key, a key prefix, a principal id, a passcode or a call. Read-only (asserted before
   the grant). */
DECLARE
  v_depot  text;
  v_run    jsonb;
  v_run_id uuid;
  v_clock  timestamptz;
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_force  jsonb;
  v_by_car jsonb;
  v_cmds   jsonb;
  v_agents jsonb;
BEGIN
  SELECT d.name INTO v_depot FROM public.depots d WHERE d.id = p_depot_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_depot', 'message', 'No such depot.');
  END IF;
  v_run := public.ottoq_agent_live_run(p_depot_id);
  v_run_id := (v_run ->> 'sim_run_id')::uuid;
  v_clock := COALESCE((v_run ->> 'sim_clock')::timestamptz, now());

  SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'setting_id', o.setting_id, 'kind', o.kind, 'vehicle_id', o.vehicle_id, 'vehicle', v.display_name,
           'fleet_operator_id', o.fleet_operator_id, 'fleet_operator', f.name,
           'charge_limit_pct', o.charge_limit_pct,
           'full_pct', COALESCE((public.ottoq_owner_contract(o.fleet_operator_id, v_clock) ->> 'max_charge_pct')::numeric,
                                public.ottoq_default_target_soc()),
           'hold_until_sim', o.hold_until_sim, 'hold_until_local', public.ottoq_owner_clock(o.hold_until_sim, true, true),
           'service', o.service, 'service_name', c.display_name, 'when', o.service_when,
           'set_at', o.set_at, 'set_at_local', public.ottoq_owner_clock(o.set_at, false),
           'command_id', o.command_id,
           'confirmation_code', public.ottoq_owner_confirmation_code(o.command_id),
           'agent', COALESCE(a.display_name, cmd.principal_name),
           'agent_via', CASE WHEN a.origin = 'passcode' THEN 'passcode' ELSE 'key' END,
           'waiting_for_tick', o.pending_reconcile))
           ORDER BY f.name, o.kind, v.display_name, o.service), '[]'::jsonb)
    INTO v_force
    FROM public.ottoq_owner_settings o
    JOIN public.vehicles v ON v.id = o.vehicle_id
    LEFT JOIN public.fleet_operators f ON f.id = o.fleet_operator_id
    LEFT JOIN public.service_cadence_policy c ON c.svc = o.service
    LEFT JOIN public.ottoq_owner_commands cmd ON cmd.command_id = o.command_id
    LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = cmd.principal_id
   WHERE o.sim_run_id = v_run_id AND o.depot_id = p_depot_id AND o.status = 'active';

  SELECT COALESCE(jsonb_object_agg(x.vehicle_id, x.card), '{}'::jsonb) INTO v_by_car
    FROM (SELECT s ->> 'vehicle_id' AS vehicle_id,
                 jsonb_strip_nulls(jsonb_build_object(
                   'vehicle', min(s ->> 'vehicle'),
                   'fleet_operator', min(s ->> 'fleet_operator'),
                   'charge_limit_pct', max((s ->> 'charge_limit_pct')::numeric),
                   'full_pct', max((s ->> 'full_pct')::numeric),
                   'hold_until_sim', max(s ->> 'hold_until_sim'),
                   'hold_until_local', max(s ->> 'hold_until_local'),
                   'orders', jsonb_agg(jsonb_build_object('service', s ->> 'service', 'name', s ->> 'service_name',
                                                          'when', s ->> 'when'))
                             FILTER (WHERE s ->> 'kind' = 'service'),
                   'agents', jsonb_agg(DISTINCT s ->> 'agent'),
                   'confirmation_codes', jsonb_agg(DISTINCT s ->> 'confirmation_code'),
                   'waiting_for_tick', bool_or((s ->> 'waiting_for_tick')::boolean))) AS card
            FROM jsonb_array_elements(v_force) s GROUP BY 1) x;

  SELECT COALESCE(jsonb_agg(q.j ORDER BY q.created_at DESC), '[]'::jsonb) INTO v_cmds
    FROM (SELECT c.created_at, jsonb_strip_nulls(jsonb_build_object(
                   'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome,
                   'head', split_part(c.summary, E'\n', 1), 'summary', c.summary,
                   'confirmation_code', CASE WHEN c.outcome = 'applied' THEN public.ottoq_owner_confirmation_code(c.command_id) END,
                   'agent', COALESCE(a.display_name, c.principal_name),
                   'agent_via', CASE WHEN a.origin = 'passcode' THEN 'passcode' ELSE 'key' END,
                   'fleet_operator_id', c.fleet_operator_id, 'fleet_operator', f.name,
                   'cars', jsonb_array_length(c.vehicles),
                   'vehicles', (SELECT jsonb_agg(x -> 'name') FROM jsonb_array_elements(c.vehicles) x),
                   'vehicle_ids', (SELECT jsonb_agg(x -> 'id') FROM jsonb_array_elements(c.vehicles) x),
                   'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
                   'sim_clock', c.sim_clock, 'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
                   'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
                   'link', c.link, 'refusal', c.refusal ->> 'message',
                   'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason)) AS j
            FROM public.ottoq_owner_commands c
            LEFT JOIN public.ottoq_agent_principals a ON a.principal_id = c.principal_id
            LEFT JOIN public.fleet_operators f ON f.id = c.fleet_operator_id
           WHERE c.depot_id = p_depot_id AND c.outcome <> 'previewed'
           ORDER BY c.created_at DESC
           LIMIT v_limit) q;

  SELECT COALESCE(jsonb_agg(z.j ORDER BY z.ord, z.at DESC), '[]'::jsonb) INTO v_agents
    FROM (SELECT CASE WHEN st.state = 'connected' THEN 0 ELSE 1 END AS ord, COALESCE(a.last_used_at, a.created_at) AS at,
                 jsonb_strip_nulls(jsonb_build_object(
                   'agent', COALESCE(a.display_name, a.name),
                   'via', CASE WHEN a.origin = 'passcode' THEN 'passcode' ELSE 'key' END,
                   'fleet_operator', f.name,
                   'state', st.state,
                   'connected_at_local', public.ottoq_owner_clock(a.created_at, false),
                   'last_seen_local', public.ottoq_owner_clock(a.last_used_at, false),
                   'expires_local', public.ottoq_owner_clock(a.expires_at, false),
                   'ended_local', public.ottoq_owner_clock(COALESCE(a.revoked_at, CASE WHEN st.state = 'expired' THEN a.expires_at END), false))) AS j
            FROM public.ottoq_agent_principals a
            LEFT JOIN public.fleet_operators f ON f.id = a.fleet_operator_id
            CROSS JOIN LATERAL (SELECT CASE
                WHEN a.status = 'active' AND a.origin = 'passcode' AND a.expires_at > now() THEN 'connected'
                WHEN a.status = 'active' AND a.origin = 'issued' THEN 'connected'
                WHEN a.origin = 'passcode' AND a.status = 'revoked' AND a.revoked_reason LIKE 'run\_ended%' THEN 'ended_with_run'
                WHEN a.origin = 'passcode' AND a.status = 'revoked' THEN 'closed'
                WHEN a.origin = 'passcode' THEN 'expired' END AS state) st
           WHERE a.depot_id = p_depot_id
             AND ((a.origin = 'passcode' AND a.status = 'active' AND a.expires_at > now())
                  OR (a.origin = 'issued' AND a.status = 'active' AND a.last_used_at > now() - interval '1 hour')
                  OR (a.origin = 'passcode' AND COALESCE(a.revoked_at, a.expires_at) BETWEEN now() - interval '2 hours' AND now()))
           ORDER BY 1, 2 DESC
           LIMIT 20) z;

  RETURN jsonb_build_object(
    'ok', true,
    'depot', jsonb_build_object('id', p_depot_id, 'name', v_depot),
    'run', CASE WHEN v_run IS NULL THEN NULL ELSE jsonb_build_object(
             'sim_run_id', v_run_id, 'status', v_run ->> 'status', 'demo', v_run ->> 'run_by' = 'operator_demo',
             'sim_clock', v_run -> 'sim_clock', 'sim_clock_local', public.ottoq_owner_clock((v_run ->> 'sim_clock')::timestamptz, true)) END,
    'in_force', v_force,
    'by_vehicle', v_by_car,
    'commands', v_cmds,
    'agents', v_agents,
    'counts', jsonb_build_object(
      'charge_limits', (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'charge_limit'),
      'holds',         (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'hold'),
      'orders',        (SELECT count(*) FROM jsonb_array_elements(v_force) s WHERE s ->> 'kind' = 'service'),
      'cars',          (SELECT count(*) FROM jsonb_object_keys(v_by_car)),
      'agents_connected', (SELECT count(*) FROM jsonb_array_elements(v_agents) g WHERE g ->> 'state' = 'connected')),
    'resets', 'Everything an owner''s agent sets lasts until the demo run ends or the agent undoes it; a stop or reset of the twin puts every car back to baseline and ends every passcode session.',
    'clocks', '"sim time" is SIMULATION time in Nashville local time; CT is real time.');
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_depot_owner_board(uuid, integer) FROM PUBLIC, anon, authenticated, service_role;

-- ── the safety gate (0405, 0560, 0606): read-only on its comment-stripped source, and on the helpers both call ──
DO $gate$
DECLARE v_src text;
BEGIN
  FOR v_src IN
    SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
      FROM pg_proc p
     WHERE p.oid IN ('public.ottoq_depot_owner_board(uuid,integer)'::regprocedure,
                     'public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure,
                     'public.ottoq_owner_confirmation_code(uuid)'::regprocedure,
                     'public.ottoq_owner_clock(timestamptz,boolean,boolean)'::regprocedure,
                     'public.ottoq_owner_contract(uuid,timestamptz)'::regprocedure,
                     'public.ottoq_agent_live_run(uuid)'::regprocedure)
  LOOP
    IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\(|set_config[[:space:]]*\()' THEN
      RAISE EXCEPTION '0608: a board (or a helper it calls) contains a write; it must not be granted to anon';
    END IF;
  END LOOP;
  IF (public.ottoq_depot_owner_board('00000000-0000-0000-0000-000000000000') ->> 'error') IS DISTINCT FROM 'unknown_depot' THEN
    RAISE EXCEPTION '0608: the depot board answers for a depot that does not exist';
  END IF;
  IF NOT (public.ottoq_depot_owner_board() ->> 'ok')::boolean THEN
    RAISE EXCEPTION '0608: the depot board does not answer for the twin depot';
  END IF;
END $gate$;

GRANT EXECUTE ON FUNCTION public.ottoq_depot_owner_board(uuid, integer) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_depot_owner_board(uuid, integer) IS
'0608. OTTO-PULSE''s and OTTO-TWIN''s read of what every owner''s agent set at a depot (anon-executable, read-only): settings in force on the live run per car and as a list, each with its command''s confirmation code and agent; the agents connected (display names only); the last owner commands with receipts, codes and links. Never a key, key prefix, principal id, passcode or call.';
COMMENT ON FUNCTION public.ottoq_owner_board(uuid, uuid, uuid) IS
'0606. OrchestrAV''s read of what ONE owner''s agent set (anon-executable, read-only): settings in force on the live run per car and as lists, the owner''s last 20 non-preview commands with plain-English receipts and links, and the command a receipt link names (p_command_id). 0608: each command carries its confirmation code, the agent''s own name and how it got in. Never all operators; never a token, principal id or call.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v jsonb;
BEGIN
  -- V1: anon has both reads, and still no owner or agent table
  IF NOT has_function_privilege('anon', 'public.ottoq_depot_owner_board(uuid,integer)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.ottoq_owner_board(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0608 V1: a grant did not take';
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_owner_commands', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_owner_settings', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_agent_principals', 'SELECT') THEN
    RAISE EXCEPTION '0608 V1: anon can read an owner or agent table directly';
  END IF;
  -- V2: the board names no key, key prefix or principal id
  v := public.ottoq_depot_owner_board();
  IF v::text ~ '(oq[as]_[0-9a-f]|"principal_id"|"token)' THEN
    RAISE EXCEPTION '0608 V2: the depot board exposes a key or a principal';
  END IF;
  -- V3: nothing on the tick path, and no existing routine, calls the depot board
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname <> 'ottoq_depot_owner_board'
                AND p.prosrc ~* 'ottoq_depot_owner_board') THEN
    RAISE EXCEPTION '0608 V3: an existing routine calls the depot board';
  END IF;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_depot_owner_board(uuid, integer); re-create ottoq_owner_board from its '0608_pre'
-- snapshot (its grant to anon survives CREATE OR REPLACE); DELETE this file's ottoq_cert_lineage row.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code', false, false,
  'Two read-only functions for the cockpits and the twin (what every owner''s agent set at a depot; 0606''s owner board with confirmation codes and agent names) and a GRANT to anon. Nothing on the tick path calls either (V3); a privilege bit and a read are invisible to every certification atom and dial arm.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
