-- migration-version: 20261004111501
-- migration-name:    the_fleet_owner_cockpit_reads_its_own_agent_requests
--
-- 0560  **The fleet owner's cockpit can read its own agent requests.** One GRANT, in its own file, because it is an
--       exposure decision and not a mechanism.
--
-- ══ §1 WHY THIS IS NOT PART OF 0559 ═════════════════════════════════════════════════════════════════════════════════
--
--   OrchestrAV reaches this database with the anon key and nothing else: its sign-in lives on the legacy project
--   (ycsisvozzgmisboumfqc) and its user -> fleet-operator binding is a picker on the device. So the only way its
--   "Agent requests" panel can show anything is an anon-executable read. 0559 builds that read,
--   ottoq_agent_requests_for_operator(fleet_operator_id, depot_id, limit), and grants it to authenticated only. This
--   file adds anon. Apply it if the exposure below is acceptable for the demo; skip it and the panel says, honestly,
--   that agent access is built but not enabled for OrchestrAV.
--
-- ══ §2 WHAT anon CAN THEN SEE, AND WHAT IT CANNOT ═══════════════════════════════════════════════════════════════════
--
--   CAN: anyone holding the public anon key who knows a fleet operator's id (the ids are already readable through
--   ottoq_depot_cards, which anon has held since before 0198) can read that operator's agent requests at a depot:
--   title, body and payload as the agent wrote them, the principal's name, the target vehicle's live state and SoC,
--   the status, whether the crew or the operator decided, the decision note, and the engine's reply. That is the same
--   exposure class as ottoq_depot_cards' operator filter, which CLAUDE.md-adjacent docs already name as spoofable.
--   CANNOT: read another operator's requests without naming it; read depot-wide requests (a note or ops action with
--   no fleet operator is never returned); see who on the crew decided (only "crew" or "operator"); see a token, a
--   token hash, a principal id or the call ledger; decide anything (ottoq_agent_request_decide stays authenticated
--   only and refuses anyone not bound in fleet_operators.auth_user_id); reach the gateway's dispatcher.
--
-- ══ §3 THE SAFETY GATE, AS 0405 DID IT ══════════════════════════════════════════════════════════════════════════════
--
--   anon executes a SECURITY DEFINER function as its owner, which is where a careless grant becomes a hole. So the
--   function is asserted READ-ONLY on its comment-stripped source before the grant (0405's statement-shaped pattern),
--   and the file refuses if it ever acquires a write. forces_recert FALSE and forces_dial_restart FALSE (stated, not
--   left NULL, which 0523 reads as a restart): a privilege bit is invisible to every certification atom and dial arm.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0560 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: 0559 is applied, the read is the one it built, anon does not have it yet, and it writes nothing ──
DO $premises$
DECLARE
  v_fn  regprocedure := to_regprocedure('public.ottoq_agent_requests_for_operator(uuid,uuid,integer)');
  v_src text;
BEGIN
  IF v_fn IS NULL THEN
    RAISE EXCEPTION '0560 P1: ottoq_agent_requests_for_operator does not exist; apply 0559 first';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_fn)
     OR (SELECT provolatile FROM pg_proc WHERE oid = v_fn) <> 's' THEN
    RAISE EXCEPTION '0560 P1: ottoq_agent_requests_for_operator is not the STABLE SECURITY DEFINER read 0559 built';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION '0560 P1: anon can already execute ottoq_agent_requests_for_operator; something else granted it';
  END IF;
  -- 0405's safety gate, on the comment-stripped body and the two helpers it calls
  FOR v_src IN
    SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
      FROM pg_proc p
     WHERE p.oid IN (v_fn, 'public.ottoq_agent_request_json(public.ottoq_agent_requests,text)'::regprocedure)
  LOOP
    IF v_src ~* '(INSERT[[:space:]]+INTO[[:space:]]|UPDATE[[:space:]]+[a-z_."]+[[:space:]]+SET[[:space:]]|DELETE[[:space:]]+FROM[[:space:]]|TRUNCATE[[:space:]]|nextval[[:space:]]*\()' THEN
      RAISE EXCEPTION '0560 P1: the operator read (or a helper it calls) contains a write statement; it must not be granted to anon';
    END IF;
  END LOOP;
  -- it never returns every operator at once
  IF (public.ottoq_agent_requests_for_operator(NULL) ->> 'error') IS DISTINCT FROM 'fleet_operator_required' THEN
    RAISE EXCEPTION '0560 P1: ottoq_agent_requests_for_operator answers without naming an operator';
  END IF;
END $premises$;

GRANT EXECUTE ON FUNCTION public.ottoq_agent_requests_for_operator(uuid, uuid, integer) TO anon;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_fn regprocedure;
BEGIN
  -- V1: anon has exactly this one read
  IF NOT has_function_privilege('anon', 'public.ottoq_agent_requests_for_operator(uuid,uuid,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0560 V1: the grant did not take';
  END IF;
  -- V2: and still nothing else of the agent surface: not the inbox, not the decide door, not the dispatcher, not admin
  FOREACH v_fn IN ARRAY ARRAY[
      'public.ottoq_agent_inbox(uuid,boolean,integer)',
      'public.ottoq_agent_request_decide(uuid,text,text)',
      'public.ottoq_agent_call(text,text,jsonb,text,jsonb)',
      'public.ottoq_agent_issue_token(text,text,text[],uuid,uuid,text,integer,integer)',
      'public.ottoq_agent_revoke(text,text,boolean)',
      'public.ottoq_agent_request_json(public.ottoq_agent_requests,text)']::regprocedure[] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION '0560 V2: anon can execute %', v_fn;
    END IF;
  END LOOP;
  -- V3: and no agent table directly
  IF has_table_privilege('anon', 'public.ottoq_agent_requests', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_agent_principals', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_agent_call_ledger', 'SELECT') THEN
    RAISE EXCEPTION '0560 V3: anon can read an agent table directly';
  END IF;
END $verify$;

-- Rollback: REVOKE EXECUTE ON FUNCTION public.ottoq_agent_requests_for_operator(uuid, uuid, integer) FROM anon;
-- and DELETE FROM public.ottoq_cert_lineage WHERE name = '0560_the_fleet_owner_cockpit_reads_its_own_agent_requests'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0560_the_fleet_owner_cockpit_reads_its_own_agent_requests', false, false,
  'One GRANT EXECUTE to anon on a read-only, operator-scoped function built by 0559. No body changes; a privilege bit is invisible to every certification atom and to every dial arm.',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
