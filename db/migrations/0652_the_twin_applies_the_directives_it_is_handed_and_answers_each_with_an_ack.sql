-- migration-version: PENDING
-- migration-name:    the_twin_applies_the_directives_it_is_handed_and_answers_each_with_an_ack
--
-- 0652  **The twin's apply door grows a payload: it applies exactly the directives it is handed and answers each with
--        a contract ack.** (Step 3 of the twin data contract review, 2026-10-08: "ottoq_api_twin_apply_commands grows a
--        payload". Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_api_twin_apply_commands(run, clock) takes no payload: it runs twin.ottoq_sim_confirm_commands, which
--   executes every issued command of the run straight from the engine's table. OTTOQ-TWIN-BOUNDARY.md: "misleadingly
--   named -- its body only calls ottoq_sim_confirm_commands and takes no command payload." The world should receive a
--   directive document and answer it, the way an operator will. Step 4 makes the twin call this through the v2 door;
--   this file gives it the door to call.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) twin.ottoq_sim_confirm_commands gains one filter, at its three reads of issued commands: a command runs only
--       if it is in the transaction-local setting ottoq.apply_only, WHEN THAT SETTING IS SET. Nothing in a tick sets
--       it, so there v_only is NULL, each filter reads TRUE, and the walk is byte-for-byte the walk it was. The body is
--       patched in place at four anchors, each asserted to occur exactly once, between an md5 of the live definition
--       before (071644ef4db2b539301060f4512e78a3) and the md5 it must have after (fba6dd47836c81eead40a63846e7f282),
--       both computed read-only on 2026-10-10 against the live catalog. The pattern 0505 used on the same function.
--   (b) public.ottoq_api_twin_apply_directives(run, clock, directives): the payload door. For each directive event:
--       one of this run's commands, version 1, in force on the run's clock, still issued. The ones that are run
--       through the walk, and only those; the rest are answered without being run. Every directive gets the contract's
--       ack data back (directive.ack: accepted, rejected or unable, with a reason from the closed list), keyed by its
--       directive_id, for the caller to send through the v2 door as its own event. A directive not yet valid gets no
--       ack: it is handed in again later.
--   The old ottoq_api_twin_apply_commands is untouched and still runs the whole walk; nothing calls it today.
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   The tick's walk is the same walk when ottoq.apply_only is unset, which it is in every tick (no function sets it
--   but (b), transaction-locally). V1 proves both halves on the live walk inside a sub-block that rolls back: with the
--   setting, only the command handed in runs; without it, every issued command runs. No run, pair or dial arm changes.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0652_pre' (the walk's definition as it stood).
--   Dropping ottoq_api_twin_apply_directives needs a person at the connector's prompt.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0652 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: the walk this file patches, and the order ──
DO $premises$
DECLARE v_def text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0651_a_directive_leaves_with_an_id_a_version_an_expiry_and_the_depots_signing_key') THEN
    RAISE EXCEPTION '0652 P1: 0651 is not classified; apply in order';
  END IF;
  IF to_regprocedure('public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0652 P1: ottoq_api_twin_apply_directives exists already';
  END IF;
  v_def := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure);
  IF md5(v_def) <> '071644ef4db2b539301060f4512e78a3' THEN
    RAISE EXCEPTION '0652 P1: twin.ottoq_sim_confirm_commands is not the body this file patches (md5 %)', md5(v_def);
  END IF;
END $premises$;

-- ── snapshot: the walk as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0652_pre', 'function', 'twin', 'ottoq_sim_confirm_commands(uuid,timestamptz)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure) AS def) d;

-- ── (a) the walk runs only what it was handed, when it was handed something ──
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[
$a1$  v_bay_end   timestamptz;  -- 0458 (G191): when this bay seat's contract says it ends
BEGIN
$a1$,
$a2$WHERE c.sim_run_id = p_sim_run_id AND c.status = 'issued' AND c.payload ? 'stall_id'$a2$,
$a3$AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.id = c.vehicle_id);$a3$,
$a4$       AND c.status = 'issued'
     /* ═════════ 0060$a4$];
  b text[] := ARRAY[
$b1$  v_bay_end   timestamptz;  -- 0458 (G191): when this bay seat's contract says it ends
  -- 0652: the commands a directive payload handed in (public.ottoq_api_twin_apply_directives). Unset, as it is in
  -- every tick, this is NULL and each filter below reads TRUE, so the walk is the walk it was.
  v_only      uuid[] := CASE WHEN current_setting('ottoq.apply_only', true) ~ '^\{[0-9a-f,-]*\}$'
                             THEN current_setting('ottoq.apply_only', true)::uuid[] END;
BEGIN
$b1$,
$b2$WHERE c.sim_run_id = p_sim_run_id AND c.status = 'issued' AND c.payload ? 'stall_id' AND (v_only IS NULL OR c.command_id = ANY (v_only))  /* 0652 */$b2$,
$b3$AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.id = c.vehicle_id)
     AND (v_only IS NULL OR c.command_id = ANY (v_only));   -- 0652$b3$,
$b4$       AND c.status = 'issued'
       AND (v_only IS NULL OR c.command_id = ANY (v_only))   -- 0652
     /* ═════════ 0060$b4$];
  i int; v_n int;
BEGIN
  FOR i IN 1 .. 4 LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0652 (a): anchor % occurs % times in the walk, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'fba6dd47836c81eead40a63846e7f282' THEN
    RAISE EXCEPTION '0652 (a): the patched walk is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure)) <> 'fba6dd47836c81eead40a63846e7f282' THEN
    RAISE EXCEPTION '0652 (a): the walk did not read back as written';
  END IF;
END $patch$;

-- ── (b) the payload door ──
CREATE OR REPLACE FUNCTION public.ottoq_api_twin_apply_directives(p_sim_run_id uuid, p_clock timestamptz, p_directives jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_clock timestamptz; v_run_found boolean;
  e jsonb; d jsonb; v_id uuid; c public.ottoq_vehicle_commands%ROWTYPE;
  v_run uuid[] := ARRAY[]::uuid[]; v_out jsonb := '[]'::jsonb; v_ack jsonb; v_state text; v_obs text; r record;
  c_uuid constant text := '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
BEGIN
  /* 0652: the world receives directive documents and answers each one (contract/README.md rules 3 and 9). The
     caller wraps each ack in its own CloudEvent (its own source and sequence) and sends it through the v2 door. A
     signature is checked by whoever received the directive over the wire; this door trusts the database it is in. */
  SELECT true, COALESCE(p_clock, r0.sim_clock_current) INTO v_run_found, v_clock
    FROM public.ottoq_sim_runs r0 WHERE r0.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_run_found, false) OR v_clock IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_run_or_no_clock');
  END IF;
  IF jsonb_typeof(p_directives) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'directives_must_be_an_array');
  END IF;
  v_obs := ottoq.ottoq_v2_rfc3339(v_clock);

  -- 1. which of these the walk may run: this run's, version 1, in force now, still issued. The rest are answered here.
  FOR e IN SELECT value FROM jsonb_array_elements(p_directives) LOOP
    d := e -> 'data';
    v_id := CASE WHEN d ->> 'directive_id' ~ c_uuid THEN (d ->> 'directive_id')::uuid END;
    c := NULL;
    SELECT * INTO c FROM public.ottoq_vehicle_commands WHERE command_id = v_id AND sim_run_id = p_sim_run_id;
    v_ack := NULL;
    IF c.command_id IS NULL THEN
      v_ack := jsonb_build_object('disposition', 'rejected', 'reason', 'other', 'detail', 'not a directive of this run');
    ELSIF (d ->> 'version') IS DISTINCT FROM '1' THEN
      v_ack := jsonb_build_object('disposition', 'rejected', 'reason', 'other', 'detail', 'a version this depot never issued');
    ELSIF c.status <> 'issued' THEN
      NULL;   -- answered already: reported below from what happened, nothing runs again
    ELSIF ottoq.ottoq_v2_tstz(d ->> 'expires_at') IS NULL OR ottoq.ottoq_v2_tstz(d ->> 'expires_at') <= v_clock THEN
      v_ack := jsonb_build_object('disposition', 'unable', 'reason', 'expired');
    ELSIF ottoq.ottoq_v2_tstz(d ->> 'valid_from') > v_clock THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', c.command_id, 'deferred', 'not_yet_valid'));
      CONTINUE;
    ELSE
      v_run := v_run || c.command_id;
      CONTINUE;
    END IF;
    IF v_ack IS NOT NULL THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', d ->> 'directive_id', 'ack',
        jsonb_build_object('directive_id', d ->> 'directive_id', 'directive_version', 1, 'observed_at', v_obs) || v_ack));
    ELSE
      v_run := v_run || c.command_id;   -- already terminal: its outcome is read below, nothing runs again
    END IF;
  END LOOP;

  -- 2. the walk, over exactly those still issued (an empty set runs nothing)
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands WHERE command_id = ANY (v_run) AND status = 'issued') THEN
    PERFORM set_config('ottoq.apply_only',
      (SELECT COALESCE(array_agg(command_id), ARRAY[]::uuid[]) FROM public.ottoq_vehicle_commands
        WHERE command_id = ANY (v_run) AND status = 'issued')::text, true);
    PERFORM twin.ottoq_sim_confirm_commands(p_sim_run_id, v_clock);
    PERFORM set_config('ottoq.apply_only', '', true);
  END IF;

  -- 3. what happened to each, as the contract's ack
  FOR r IN SELECT cmd.command_id, cmd.status, cmd.reason_code, cmd.payload ->> 'refusal_reason' AS refusal, v.current_state::text AS state
             FROM public.ottoq_vehicle_commands cmd JOIN public.vehicles v ON v.id = cmd.vehicle_id
            WHERE cmd.command_id = ANY (v_run)
            ORDER BY cmd.command_seq
  LOOP
    v_ack := CASE
      WHEN r.status IN ('executed', 'confirmed') THEN jsonb_build_object('disposition', 'accepted')
      WHEN r.status = 'expired' THEN jsonb_build_object('disposition', 'unable', 'reason', 'expired')
      WHEN r.status = 'issued' THEN NULL
      WHEN r.reason_code = 'target_occupied'      THEN jsonb_build_object('disposition', 'unable', 'reason', 'occupied')
      WHEN r.reason_code = 'resource_faulted'     THEN jsonb_build_object('disposition', 'unable', 'reason', 'charger_fault')
      WHEN r.reason_code = 'vehicle_unresponsive' THEN jsonb_build_object('disposition', 'unable', 'reason', 'vehicle_unresponsive')
      WHEN r.reason_code = 'superseded'           THEN jsonb_build_object('disposition', 'rejected', 'reason', 'superseded')
      WHEN r.reason_code = 'vehicle_state_incompatible'
           AND r.state IN ('deployed', 'en_route_to_depot', 'en_route_to_deployment', 'offline')
                                                  THEN jsonb_build_object('disposition', 'unable', 'reason', 'vehicle_not_at_depot')
      ELSE jsonb_build_object('disposition', 'unable', 'reason', 'other',
                              'detail', left(COALESCE(r.reason_code, 'refused') || COALESCE(': ' || r.refusal, ''), 500))
    END;
    IF v_ack IS NULL THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', r.command_id, 'deferred', 'not_run'));
    ELSE
      v_out := v_out || jsonb_build_array(jsonb_build_object('directive_id', r.command_id, 'ack',
        jsonb_build_object('directive_id', r.command_id, 'directive_version', 1, 'observed_at', v_obs) || v_ack));
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'contract_version', '0.1', 'endpoint', 'twin.apply_directives',
                            'sim_run_id', p_sim_run_id, 'clock', v_clock, 'results', v_out);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb) TO service_role;

-- ── V1: on the live walk, inside a sub-block that rolls back ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_car uuid; v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid;
  c1 uuid; c2 uuid; c3 uuid; c4 uuid; st1 text; st2 text; st2b text; st3 text; st4 text;
  r_apply jsonb; r_unknown jsonb; v_cmds_before bigint; v_cmds_after bigint;
BEGIN
  -- the twin depot's newest run, a car with no stall, and four free staging stalls
  SELECT sim_run_id, COALESCE(sim_clock_current, started_at) INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = v_twin AND COALESCE(run_by, '') <> 'production_live' ORDER BY started_at DESC LIMIT 1;
  SELECT id INTO v_car FROM public.vehicles
   WHERE home_depot_id = v_twin AND current_stall_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id)
   ORDER BY display_name LIMIT 1;
  SELECT (array_agg(id ORDER BY stall_code))[1], (array_agg(id ORDER BY stall_code))[2],
         (array_agg(id ORDER BY stall_code))[3], (array_agg(id ORDER BY stall_code))[4]
    INTO v_s1, v_s2, v_s3, v_s4
    FROM (SELECT id, stall_code FROM public.stalls
           WHERE depot_id = v_twin AND stall_type = 'staging' AND current_vehicle_id IS NULL
             AND (reserved_by IS NULL OR reservation_expires_at <= COALESCE(v_clock, now()))
           ORDER BY stall_code DESC LIMIT 4) s;
  IF v_run IS NULL OR v_car IS NULL OR v_s4 IS NULL THEN
    RAISE EXCEPTION '0652 V1: no run, free car or four free staging stalls at the twin depot to probe with';
  END IF;
  SELECT count(*) INTO v_cmds_before FROM public.ottoq_vehicle_commands WHERE sim_run_id = v_run;
  BEGIN
    -- (i) two issued holds; the payload door hands the walk only the second
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_car, 'hold', jsonb_build_object('stall_id', v_s1), v_clock, '0652_v1_probe') RETURNING command_id INTO c1;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_car, 'hold', jsonb_build_object('stall_id', v_s2), v_clock, '0652_v1_probe') RETURNING command_id INTO c2;
    r_apply := public.ottoq_api_twin_apply_directives(v_run, v_clock,
                 jsonb_build_array(ottoq.ottoq_v2_directive_event(c2)));
    SELECT status INTO st1 FROM public.ottoq_vehicle_commands WHERE command_id = c1;
    SELECT status INTO st2 FROM public.ottoq_vehicle_commands WHERE command_id = c2;
    -- a directive no run of this depot issued
    r_unknown := public.ottoq_api_twin_apply_directives(v_run, v_clock, jsonb_build_array(jsonb_build_object(
                   'data', jsonb_build_object('directive_id', gen_random_uuid(), 'version', 1))));
    -- (ii) with nothing handed in, the walk is the whole walk: two more issued holds, both run
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_car, 'hold', jsonb_build_object('stall_id', v_s3), v_clock, '0652_v1_probe') RETURNING command_id INTO c3;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_car, 'hold', jsonb_build_object('stall_id', v_s4), v_clock, '0652_v1_probe') RETURNING command_id INTO c4;
    PERFORM twin.ottoq_sim_confirm_commands(v_run, v_clock);
    SELECT status INTO st2b FROM public.ottoq_vehicle_commands WHERE command_id = c1;
    SELECT status INTO st3 FROM public.ottoq_vehicle_commands WHERE command_id = c3;
    SELECT status INTO st4 FROM public.ottoq_vehicle_commands WHERE command_id = c4;
    RAISE EXCEPTION '0652 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0652 V1 PROBED' THEN RAISE EXCEPTION '0652 V1: the probe itself failed: %', v_msg; END IF;
  SELECT count(*) INTO v_cmds_after FROM public.ottoq_vehicle_commands WHERE sim_run_id = v_run;

  IF st1 <> 'issued' THEN RAISE EXCEPTION '0652 V1 FAILED: a command not handed in was run (%)', st1; END IF;
  IF st2 = 'issued' THEN RAISE EXCEPTION '0652 V1 FAILED: the command handed in was not run'; END IF;
  IF jsonb_array_length(r_apply -> 'results') <> 1 OR r_apply -> 'results' -> 0 ->> 'directive_id' <> c2::text
     OR NOT (r_apply -> 'results' -> 0 ? 'ack') THEN
    RAISE EXCEPTION '0652 V1 FAILED: the payload door answered %', r_apply;
  END IF;
  IF (st2 = 'executed') <> (r_apply -> 'results' -> 0 -> 'ack' ->> 'disposition' = 'accepted') THEN
    RAISE EXCEPTION '0652 V1 FAILED: the ack (%) does not say what happened (%)', r_apply -> 'results' -> 0 -> 'ack', st2;
  END IF;
  IF r_unknown -> 'results' -> 0 -> 'ack' ->> 'disposition' <> 'rejected' OR r_unknown -> 'results' -> 0 -> 'ack' ->> 'reason' <> 'other' THEN
    RAISE EXCEPTION '0652 V1 FAILED: a directive of no run was answered %', r_unknown;
  END IF;
  IF st2b = 'issued' OR st3 = 'issued' OR st4 = 'issued' THEN
    RAISE EXCEPTION '0652 V1 FAILED: with nothing handed in, the walk left an issued command unrun (% % %)', st2b, st3, st4;
  END IF;
  IF current_setting('ottoq.apply_only', true) NOT IN ('') AND current_setting('ottoq.apply_only', true) IS NOT NULL THEN
    RAISE EXCEPTION '0652 V1 FAILED: ottoq.apply_only is still set after the payload door: %', current_setting('ottoq.apply_only', true);
  END IF;
  IF v_cmds_after <> v_cmds_before THEN RAISE EXCEPTION '0652 V1 FAILED: the probe commands did not roll back'; END IF;
  RAISE NOTICE '0652 V1 PASSED on run %: handed one of two issued holds, the walk ran that one (%) and left the other issued; the ack says what happened (%); a directive of no run is rejected; with nothing handed in the walk ran every issued command (% % %); the setting is cleared; all rolled back',
    v_run, st2, r_apply -> 'results' -> 0 -> 'ack' ->> 'disposition', st2b, st3, st4;
END $v1$;

-- ── V2: who may call it ──
DO $v2$
BEGIN
  IF has_function_privilege('anon', 'public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0652 V2 FAILED: the payload door is executable by anon or authenticated';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '0652 V2 FAILED: service_role cannot execute the payload door';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0652_the_twin_applies_the_directives_it_is_handed_and_answers_each_with_an_ack', false, false,
  'Step 3 of the twin data contract review: twin.ottoq_sim_confirm_commands gains a filter on the transaction-local '
  'ottoq.apply_only, NULL in every tick (each filter reads TRUE: the walk is unchanged), patched at four anchors between '
  'md5 071644ef... and fba6dd47...; public.ottoq_api_twin_apply_directives runs exactly the directives handed in and '
  'answers each with a contract ack. V1 proves both halves on the live walk, rolled back. FALSE/FALSE.',
  now());

COMMIT;
