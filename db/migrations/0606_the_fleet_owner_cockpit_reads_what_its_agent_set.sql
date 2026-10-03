-- migration-version: PENDING
-- migration-name:    the_fleet_owner_cockpit_reads_what_its_agent_set
--
-- 0606  **The fleet owner's cockpit reads what its agent set.** One read-only function and its grant, in their own
--       file, because opening it to anon is an exposure decision and not a mechanism (0560's reasoning, unchanged).
--
-- ══ §1 WHAT IT IS FOR ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-02: an owner's agent command should come back "saying in plain English essentially this has been
--   accepted and is visible now within your orchestra app with a link. You can then click the link and go to your fleet
--   and see all Tesla vehicles now have a maximum charge capacity at any given time of 90% instead of 100%."
--   0605's receipts carry that link (…/?source=agent&run=…&owner=…&tab=fleet&command=…). OrchestrAV reaches this
--   database with the anon key alone, so the page behind the link can show what the agent set only through an
--   anon-executable read: public.ottoq_owner_board(fleet_operator_id, depot_id, command_id).
--
-- ══ §2 WHAT anon CAN THEN SEE, AND WHAT IT CANNOT ═══════════════════════════════════════════════════════════════════
--
--   CAN: anyone holding the public anon key who names a fleet operator (ids already readable through
--   ottoq_depot_cards) can read, for that operator at one depot: the owner settings in force on the live run (each
--   car's charge limit, hold and service orders), and the operator's last 20 owner commands that changed or refused
--   something -- tool, outcome, the plain-English summary, the cars, the effects, the OrchestrAV link, when it was
--   undone or lifted, and the agent's NAME. A command named by p_command_id is returned in full when it is that
--   operator's. The same exposure class as 0560's agent requests.
--   CANNOT: read another operator without naming it; read previews (not shown: they changed nothing); see a token, a
--   token hash, a principal id, the call ledger or the idempotency keys; change anything (the function is asserted
--   read-only below, on its comment-stripped source, before the grant); reach the gateway's dispatcher.
--
-- ══ §3 forces_recert FALSE, forces_dial_restart FALSE ══════════════════════════════════════════════════════════════
--
--   A new read nothing on the tick path calls (V3), and a privilege bit. Invisible to every certification atom and every
--   dial arm.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0606 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0605 applied; this file not ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_owner_commands') IS NULL OR to_regclass('public.ottoq_owner_settings') IS NULL THEN
    RAISE EXCEPTION '0606 P1: 0605 (owner settings) is not applied; apply it first';
  END IF;
  IF to_regprocedure('public.ottoq_owner_board(uuid,uuid,uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0606_the_fleet_owner_cockpit_reads_what_its_agent_set') THEN
    RAISE EXCEPTION '0606 P1: already applied';
  END IF;
END $premises$;

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
   operator at once; never previews; never a token, principal id or call. Read-only (asserted before the grant). */
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
                   'agent', c.principal_name, 'cars', jsonb_array_length(c.vehicles),
                   'vehicle_ids', (SELECT jsonb_agg(x -> 'id') FROM jsonb_array_elements(c.vehicles) x),
                   'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
                   'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
                   'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
                   'link', c.link, 'refusal', c.refusal,
                   'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason)) AS j
            FROM public.ottoq_owner_commands c
           WHERE c.fleet_operator_id = p_fleet_operator_id AND c.depot_id = p_depot_id AND c.outcome <> 'previewed'
           ORDER BY c.created_at DESC
           LIMIT 20) q;

  IF p_command_id IS NOT NULL THEN
    SELECT jsonb_strip_nulls(jsonb_build_object(
             'command_id', c.command_id, 'tool', c.tool, 'outcome', c.outcome, 'summary', c.summary,
             'agent', c.principal_name, 'vehicles', c.vehicles, 'effects', c.effects, 'args', c.args - 'idempotency_key',
             'created_at', c.created_at, 'created_at_local', public.ottoq_owner_clock(c.created_at, false),
             'sim_clock_local', public.ottoq_owner_clock(c.sim_clock, true),
             'sim_run_id', c.sim_run_id, 'live_run', c.sim_run_id IS NOT DISTINCT FROM v_run_id,
             'link', c.link, 'refusal', c.refusal,
             'undone_at', c.undone_at, 'lifted_at', c.lifted_at, 'lifted_reason', c.lifted_reason))
      INTO v_hl
      FROM public.ottoq_owner_commands c
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

REVOKE ALL ON FUNCTION public.ottoq_owner_board(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ── the safety gate (0405, 0560): read-only on its comment-stripped source, and the helpers it calls ──
DO $gate$
DECLARE v_src text;
BEGIN
  FOR v_src IN
    SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
      FROM pg_proc p
     WHERE p.oid IN ('public.ottoq_owner_board(uuid,uuid,uuid)'::regprocedure,
                     'public.ottoq_owner_clock(timestamptz,boolean,boolean)'::regprocedure,
                     'public.ottoq_owner_contract(uuid,timestamptz)'::regprocedure,
                     'public.ottoq_agent_live_run(uuid)'::regprocedure)
  LOOP
    IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\(|set_config[[:space:]]*\()' THEN
      RAISE EXCEPTION '0606: the owner board (or a helper it calls) contains a write; it must not be granted to anon';
    END IF;
  END LOOP;
  IF (public.ottoq_owner_board(NULL) ->> 'error') IS DISTINCT FROM 'fleet_operator_required' THEN
    RAISE EXCEPTION '0606: the owner board answers without naming an operator';
  END IF;
END $gate$;

GRANT EXECUTE ON FUNCTION public.ottoq_owner_board(uuid, uuid, uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ottoq_owner_board(uuid, uuid, uuid) IS
'0606. OrchestrAV''s read of what ONE owner''s agent set (anon-executable, read-only): settings in force on the live run per car and as lists, the owner''s last 20 non-preview commands with plain-English receipts and links, and the command a receipt link names (p_command_id). Never all operators; never a token, principal id or call.';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_fn regprocedure;
BEGIN
  -- V1: anon has this one read
  IF NOT has_function_privilege('anon', 'public.ottoq_owner_board(uuid,uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0606 V1: the grant did not take';
  END IF;
  -- V2: and nothing else of the owner surface, and no owner table
  FOR v_fn IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname IN ('public', 'ottoq') AND p.proname LIKE 'ottoq\_owner\_%'
                 AND p.proname NOT IN ('ottoq_owner_board') LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '0606 V2: anon can execute %', v_fn;
    END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.ottoq_owner_commands', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_owner_settings', 'SELECT') THEN
    RAISE EXCEPTION '0606 V2: anon can read an owner table directly';
  END IF;
  -- V3: nothing on the tick path, and no existing routine, calls it
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname <> 'ottoq_owner_board'
                AND p.prosrc ~* 'ottoq_owner_board') THEN
    RAISE EXCEPTION '0606 V3: an existing routine calls the owner board';
  END IF;
END $verify$;

-- Rollback: DROP FUNCTION public.ottoq_owner_board(uuid, uuid, uuid); DELETE FROM public.ottoq_cert_lineage WHERE
-- name = '0606_the_fleet_owner_cockpit_reads_what_its_agent_set'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0606_the_fleet_owner_cockpit_reads_what_its_agent_set', false, false,
  'A read-only, operator-scoped function for OrchestrAV (what an owner''s agent set, and its receipts) and its GRANT to anon. Nothing on the tick path calls it (V3); a privilege bit is invisible to every certification atom and dial arm.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
