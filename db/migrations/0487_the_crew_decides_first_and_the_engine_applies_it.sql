-- migration-version: 20260926152610
-- migration-name:    the_crew_decides_first_and_the_engine_applies_it
--
-- 0487  **The crew decides first, and the engine applies it.** PULSE's approvals queue had an Approve and a
--       Decline button that could never work, and would not have done the right thing if they had.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-26) ════════════════════════════════════════════════════════════════════
--
--   (a) THE BUTTONS COULD NOT WRITE. PULSE wrote `UPDATE ottoq_ops_approvals SET status = ...` straight to the
--       table. anon and authenticated hold SELECT on it and no UPDATE (has_table_privilege, both false), and no
--       function offered a crew decision: the only deciders are `twin.ottoq_opportunistic_scan` (the simulated
--       technician) and `public.ottoq_decide_indepot_approvals` (OTTO-Q's gate), neither callable by a client.
--       Every click returned "permission denied".
--   (b) AND A WRITE WOULD NOT HAVE ENACTED ANYTHING. An approved opportunistic top-off is enacted INSIDE the
--       scan, in the same loop iteration that draws the verdict (state to staged_awaiting_service, then
--       ottoq_enact_opportunistic_charge, then the arm check, then the stall claim). The scan's cursor reads
--       status = 'pending' only. So a row a client set to 'approved' would leave the queue approved and never
--       charge: a recorded decision with no effect, which is worse than a refusal.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `public.ottoq_ops_approval_decide(p_approval_id, p_decision, p_note)`, for the crew's two questions only
--       (opportunistic_charge, tech_greenlight). It records the verdict on the row as payload.operator_verdict
--       and brings decide_after to the run's sim clock, leaving the row PENDING. It refuses, with a reason, a
--       decision on OTTO-Q's in-depot gate (that gate is doctrine, decided by the kernel), a card already decided,
--       a second verdict, a card past its expiry, and a run that is not live. It emits `ops.approval_decided`
--       with actor_type depot_tech, a human actor in `ottoq_kpi_touch_actor_types`, so KPI 4 (human touches per
--       turn) counts the decision as the touch it is. authenticated and service_role only.
--   (2) The scan reads the verdict. Its draw becomes COALESCE(operator verdict = 'approved', seeded draw < p):
--       with a verdict the draw is not consulted, without one the draw is the only term. So the crew's decision
--       takes EXACTLY the path the simulated technician's does, including the enactment of an approved top-off,
--       and decided_by names the crew instead of twin_tech_sim.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The scan is in the tick. No certified run can carry an operator verdict (a pair runs inside one transaction,
--   and the verdict can only come from the new function), so the draw is the only term in every certified arm
--   and behaviour is unchanged by construction. The canon re-certifies anyway: the body changed.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0487 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured, and nothing it creates exists yet ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure))
     <> '31a2f4a1d21e01433735381c6b68507e' THEN
    RAISE EXCEPTION '0487 P2: twin.ottoq_opportunistic_scan is not the body this file patches';
  END IF;
  IF to_regprocedure('public.ottoq_ops_approval_decide(uuid,text,text)') IS NOT NULL THEN
    RAISE EXCEPTION '0487 P2: public.ottoq_ops_approval_decide already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog WHERE event_type = 'ops.approval_decided') THEN
    RAISE EXCEPTION '0487 P2: the event type ops.approval_decided already exists';
  END IF;
  -- the crew's actor type counts as a human touch in KPI 4
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_kpi_touch_actor_types WHERE actor_type = 'depot_tech' AND human_actor) THEN
    RAISE EXCEPTION '0487 P2: depot_tech is not a human actor in ottoq_kpi_touch_actor_types';
  END IF;
  -- clients still cannot write the table, which is the reason for the door
  IF has_table_privilege('authenticated', 'public.ottoq_ops_approvals', 'UPDATE')
     OR has_table_privilege('anon', 'public.ottoq_ops_approvals', 'UPDATE') THEN
    RAISE EXCEPTION '0487 P2: a client role can already UPDATE ottoq_ops_approvals';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0487_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure;

-- ── (1) the crew's door ──
CREATE FUNCTION public.ottoq_ops_approval_decide(p_approval_id uuid, p_decision text, p_note text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
/* 0487. A crew member's verdict on one of the twin technician's questions (an opportunistic top-off, a
   technician green-light). Recorded on the row and applied by twin.ottoq_opportunistic_scan on the next tick,
   on the same path as the simulated technician's draw, so an approved top-off is enacted exactly as a drawn
   one is. The row stays pending until then. OTTO-Q's in-depot gate is not the crew's to decide. */
DECLARE
  v_ap    public.ottoq_ops_approvals%ROWTYPE;
  v_run   record;
  v_uid   uuid := auth.uid();
  v_actor text;
  v_fleet uuid;
BEGIN
  IF p_decision IS NULL OR p_decision NOT IN ('approved', 'declined') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'the decision is approved or declined');
  END IF;
  SELECT * INTO v_ap FROM public.ottoq_ops_approvals WHERE approval_id = p_approval_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no such approval');
  END IF;
  IF v_ap.approval_type NOT IN ('opportunistic_charge', 'tech_greenlight') THEN
    RETURN jsonb_build_object('ok', false, 'approval_type', v_ap.approval_type,
                              'error', 'this approval is decided by OTTO-Q, not the crew');
  END IF;
  IF v_ap.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already ' || v_ap.status, 'decided_by', v_ap.decided_by);
  END IF;
  IF COALESCE(v_ap.payload, '{}'::jsonb) ? 'operator_verdict' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'the crew already decided this and it applies on the next tick',
                              'operator_verdict', v_ap.payload -> 'operator_verdict');
  END IF;
  SELECT r.status, r.sim_clock_current INTO v_run FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_ap.sim_run_id;
  IF v_run.status IS NULL OR v_run.status NOT IN ('running', 'paused') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'the run this card belongs to is not live');
  END IF;
  -- the twin technician's questions are stamped on the sim clock, so the comparison is sim against sim
  IF v_ap.expires_at IS NOT NULL AND v_ap.expires_at <= v_run.sim_clock_current THEN
    RETURN jsonb_build_object('ok', false, 'error', 'the card has expired');
  END IF;

  v_actor := COALESCE(v_uid::text, 'pulse');
  UPDATE public.ottoq_ops_approvals
     SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('operator_verdict', jsonb_build_object(
                     'verdict', p_decision, 'by', 'pulse', 'by_uid', v_uid, 'note', p_note,
                     'at_real', now(), 'at_sim', v_run.sim_clock_current)),
         decide_after = LEAST(COALESCE(decide_after, v_run.sim_clock_current), v_run.sim_clock_current)
   WHERE approval_id = p_approval_id;

  SELECT v.fleet_operator_id INTO v_fleet FROM public.vehicles v WHERE v.id = v_ap.vehicle_id;
  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'depot_tech', p_actor_id := v_actor,
      p_event_type := 'ops.approval_decided', p_entity_type := 'vehicle', p_entity_id := v_ap.vehicle_id,
      p_fleet_operator_id := v_fleet, p_depot_id := v_ap.depot_id,
      p_payload := jsonb_build_object('approval_id', p_approval_id, 'approval_type', v_ap.approval_type,
                                      'verdict', p_decision, 'note', p_note, 'applies', 'next_tick'),
      p_severity := 'info', p_ingest_source := 'app', p_data_source := 'twin', p_sim_run_id := v_ap.sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    -- the verdict stands without its event, and says so
    RETURN jsonb_build_object('ok', true, 'approval_id', p_approval_id, 'verdict', p_decision,
                              'applies', 'next_tick', 'event_error', SQLERRM);
  END;
  RETURN jsonb_build_object('ok', true, 'approval_id', p_approval_id, 'verdict', p_decision, 'applies', 'next_tick');
END;
$function$;

REVOKE ALL ON FUNCTION public.ottoq_ops_approval_decide(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_ops_approval_decide(uuid, text, text) TO authenticated, service_role;

INSERT INTO public.ottoq_event_types_catalog (event_type, category, default_severity, description, introduced_in, emitter)
VALUES ('ops.approval_decided', 'action', 'info',
        'A crew member decided one of the twin technician''s questions (an opportunistic top-off or a technician '
        'green-light) through ottoq_ops_approval_decide. The engine applies it on the next tick. A human touch for '
        'KPI 4. Payload: approval_id, approval_type, verdict, note, applies.',
        '0487', 'app');

-- ── (2) the scan reads the verdict ──
DO $patch_scan$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure);
  v_old_sel text := $o$COALESCE(v.target_soc, public.ottoq_default_target_soc()) AS veh_target
$o$;
  v_new_sel text := $n$COALESCE(v.target_soc, public.ottoq_default_target_soc()) AS veh_target,
           ap.payload #>> '{operator_verdict,verdict}' AS op_verdict,   -- 0487: the crew's verdict, if any
           ap.payload #>> '{operator_verdict,by}' AS op_by
$n$;
  v_old_draw text := $o$    IF ottoq_sim_seeded_random(v_seed, 'techdecide:' || v_rec.vehicle_id::text || ':' || v_rec.approval_type || ':' || extract(epoch from v_rec.requested_at)::bigint::text) < v_p THEN
$o$;
  v_new_draw text := $n$    -- 0487: THE CREW DECIDES FIRST. A verdict recorded by ottoq_ops_approval_decide replaces the simulated
    -- technician's draw and takes this same path, so an approved top-off is enacted exactly as a drawn one.
    -- With no verdict the draw is the only term, which is every certified run.
    IF COALESCE(v_rec.op_verdict = 'approved',
                ottoq_sim_seeded_random(v_seed, 'techdecide:' || v_rec.vehicle_id::text || ':' || v_rec.approval_type || ':' || extract(epoch from v_rec.requested_at)::bigint::text) < v_p) THEN
$n$;
  v_old_by text := $o$decided_by='twin_tech_sim'$o$;
  v_new_by text := $n$decided_by=COALESCE('operator:' || v_rec.op_by, 'twin_tech_sim')$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old_sel, ''))) / length(v_old_sel);
  IF n <> 1 THEN RAISE EXCEPTION '0487: the cursor select matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old_draw, ''))) / length(v_old_draw);
  IF n <> 1 THEN RAISE EXCEPTION '0487: the technician draw matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old_by, ''))) / length(v_old_by);
  IF n <> 2 THEN RAISE EXCEPTION '0487: the decider stamp matched % times, not twice', n; END IF;
  v_def := replace(v_def, v_old_sel, v_new_sel);
  v_def := replace(v_def, v_old_draw, v_new_draw);
  v_def := replace(v_def, v_old_by, v_new_by);
  EXECUTE v_def;
END $patch_scan$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure);
  v_f   regprocedure := 'public.ottoq_ops_approval_decide(uuid,text,text)'::regprocedure;
  v_scan regprocedure := 'twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure;
BEGIN
  -- V1: the scan reads the verdict, draws only without one, and names the crew when the crew decided.
  IF position('AS op_verdict' IN v_def) = 0
     OR position('IF COALESCE(v_rec.op_verdict = ''approved'',' IN v_def) = 0
     OR (length(v_def) - length(replace(v_def, 'decided_by=COALESCE(''operator:'' || v_rec.op_by, ''twin_tech_sim'')', '')))
        / length('decided_by=COALESCE(''operator:'' || v_rec.op_by, ''twin_tech_sim'')') <> 2
     OR position('decided_by=''twin_tech_sim''' IN v_def) > 0 THEN
    RAISE EXCEPTION '0487 V1: the scan is not the body this file leaves';
  END IF;
  -- V2: the scan kept its privileges (CREATE OR REPLACE keeps the ACL) and its security definer.
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_scan)
     OR has_function_privilege('anon', v_scan, 'EXECUTE') OR has_function_privilege('authenticated', v_scan, 'EXECUTE') THEN
    RAISE EXCEPTION '0487 V2: the scan''s privileges changed';
  END IF;
  -- V3: the door is the crew's and the engine's, not anon's.
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR has_function_privilege('anon', v_f, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_f, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_f, 'EXECUTE') THEN
    RAISE EXCEPTION '0487 V3: ottoq_ops_approval_decide has the wrong privileges';
  END IF;
  -- V4: clients still cannot write the table directly.
  IF has_table_privilege('authenticated', 'public.ottoq_ops_approvals', 'UPDATE')
     OR has_table_privilege('anon', 'public.ottoq_ops_approvals', 'UPDATE') THEN
    RAISE EXCEPTION '0487 V4: a client role can UPDATE ottoq_ops_approvals';
  END IF;
  -- V5: a refusal is a refusal, with no row touched (a card that does not exist).
  IF (public.ottoq_ops_approval_decide('00000000-0000-0000-0000-000000000000'::uuid, 'approved') ->> 'ok')::boolean THEN
    RAISE EXCEPTION '0487 V5: the door accepted a card that does not exist';
  END IF;
  IF (public.ottoq_ops_approval_decide('00000000-0000-0000-0000-000000000000'::uuid, 'maybe') ->> 'ok')::boolean THEN
    RAISE EXCEPTION '0487 V5: the door accepted a decision that is not approved or declined';
  END IF;
END $verify$;

-- Rollback: restore twin.ottoq_opportunistic_scan from ottoq_schema_snapshots label '0487_pre' (CREATE OR REPLACE,
-- ACL kept), then DROP FUNCTION public.ottoq_ops_approval_decide(uuid, text, text) and
-- DELETE FROM public.ottoq_event_types_catalog WHERE event_type = 'ops.approval_decided'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0487_the_crew_decides_first_and_the_engine_applies_it', true,
  'twin.ottoq_opportunistic_scan (tick path) reads an operator verdict before its seeded draw. No certified arm can '
  'carry one, so behaviour is unchanged by construction, but the body changed and the canon re-certifies.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
