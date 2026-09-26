-- migration-version: 20260926170743
-- migration-name:    an_ops_action_outside_the_whitelist_is_refused_and_says_so
--
-- 0491  **An ops action outside the whitelist is refused, and says so (G222).** The setter promised a human approval
--       queue that the approvals table cannot hold and nothing would ever execute.
--
-- ══ §1 WHAT WAS WRONG ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_apply_ops_action` applies three whitelisted moves (raise_deploy_surge, extend_forecast_horizon,
--   enable_energy_reserve). Anything else fell to an ELSE branch that inserted an `ottoq_ops_approvals` row of type
--   `nemotron_ops_action` and returned `queued_for_approval`. `ottoq_ops_approvals_approval_type_check` allows only
--   `opportunistic_charge`, `tech_greenlight` and `indepot_reassign`, so the insert raised, and the agent filed the
--   action under `rejected` with the constraint's message. No row of that type has ever existed, and nothing would
--   execute one: the crew's door (0487) decides only opportunistic charges and technician green-lights.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The ELSE branch inserts nothing and returns `{status: 'refused', reason: 'not in the auto-exec whitelist',
--   whitelist: [...]}`. The agent already files a `refused` under `rejected` with the reply attached
--   (ottoq-orchestrator-agent, the ops-action loop), so its record now carries the reason instead of a constraint
--   violation. Its `queued` branch for ops actions can no longer fill, which was already true.
--
-- ══ §3 forces_recert FALSE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Only the agent calls this function, and certification arms do not run the agent.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0491 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)'::regprocedure))
     <> '92e144c6bad2045df88be42b9a83cf5f' THEN
    RAISE EXCEPTION '0491 P2: public.ottoq_apply_ops_action is not the body this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_ops_approvals WHERE approval_type = 'nemotron_ops_action') THEN
    RAISE EXCEPTION '0491 P2: a nemotron_ops_action approval exists, so the premise that none ever did is false';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0491_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)'::regprocedure);
  v_old text := $o$  ELSE
    -- OUT OF WHITELIST → human approval queue (Pulse), not a silent drop.
    INSERT INTO ottoq_ops_approvals (approval_type, sim_run_id, depot_id, status, priority, payload, requested_at, expires_at)
    VALUES ('nemotron_ops_action', p_sim_run_id, p_depot_id, 'pending',
            COALESCE(NULLIF(p_args->>'priority',''), 'normal'),
            jsonb_build_object('action', p_action, 'args', p_args, 'by', p_by, 'reason','not in auto-exec whitelist'),
            now(), now() + interval '30 minutes');
    RETURN jsonb_build_object('status','queued_for_approval','action',p_action);
  END IF;
$o$;
  v_new text := $n$  ELSE
    -- 0491 (G222): OUT OF WHITELIST IS REFUSED, AND SAYS SO. This used to queue a nemotron_ops_action approval,
    -- which the approvals table's check constraint rejects and which nothing would ever execute.
    RETURN jsonb_build_object('status','refused','action',p_action,'reason','not in the auto-exec whitelist',
                              'whitelist', jsonb_build_array('raise_deploy_surge','extend_forecast_horizon',
                                                             'enable_energy_reserve'));
  END IF;
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0491: the out-of-whitelist branch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)'::regprocedure;
  v_def text := pg_get_functiondef('public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)'::regprocedure);
  v_res jsonb;
BEGIN
  -- V1: the function no longer writes the approvals table and no longer promises a queue.
  IF position('ottoq_ops_approvals' IN v_def) > 0 OR position('queued_for_approval' IN v_def) > 0 THEN
    RAISE EXCEPTION '0491 V1: the out-of-whitelist branch still queues';
  END IF;
  -- V2: an action outside the whitelist is refused, writes nothing, and names the whitelist.
  v_res := public.ottoq_apply_ops_action(NULL, '11111111-1111-1111-1111-111111111111', 'probe_not_whitelisted', '{}'::jsonb, 'migration_0491');
  IF v_res->>'status' IS DISTINCT FROM 'refused' OR jsonb_array_length(v_res->'whitelist') <> 3 THEN
    RAISE EXCEPTION '0491 V2: the refusal reads %', v_res;
  END IF;
  -- V3: privileges and security definer kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f)
        <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0491 V3: ottoq_apply_ops_action''s privileges changed';
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_apply_ops_action from ottoq_schema_snapshots label '0491_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0491_an_ops_action_outside_the_whitelist_is_refused_and_says_so', false,
  'ottoq_apply_ops_action refuses an action outside its whitelist instead of inserting an approval its table rejects. '
  'Only the agent calls it, and certification arms do not run the agent.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
