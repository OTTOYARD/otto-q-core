-- migration-version: 20260916144203
-- migration-name:    every_solver_proposal_gets_a_deterministic_disposition
--
-- The first live 0331/0332 Sim Start proved one product process:
-- agent analysis -> solver handoff -> deterministic kernel -> dispatch. It also
-- exposed one lifecycle hole. A cuOpt stall proposal can arrive after the world
-- has moved; the selector correctly refuses to use its now-unavailable stall,
-- but no row says why. The proposal can remain `pending` after the run ends.
--
-- 0333 makes every terminal path explicit:
--   * enacted by the kernel;
--   * superseded by another enacted proposal;
--   * expired in the selector's real-time TTL domain;
--   * refused because its stall is no longer eligible; or
--   * expired when the run is finalized.
--
-- `proposal` remains the immutable proposer packet. Disposition has its own
-- columns so the solver's request is never rewritten to explain the kernel.
-- forces_recert: TRUE. This changes the proposal ledger written by a tick.

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0333 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0333 P-: % certification pair(s) are in flight', v_pairs;
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running', 'paused') AND COALESCE(run_by, '') <> 'production_live';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0333 P-: % Twin run(s) are active', v_runs;
  END IF;

  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_decide_tick'
         AND pg_get_function_identity_arguments(p.oid)='p_sim_run_id uuid')
       <> 'fd0bf428abeda40801467fd428a090f1' THEN
    RAISE EXCEPTION '0333 P-: ottoq_decide_tick moved from the measured 0327/0332 body';
  END IF;

  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_sim_stop_and_reset'
         AND pg_get_function_identity_arguments(p.oid)='p_sim_run_id uuid, p_reason text')
       <> '8f0a2d6e6b8098d680d594ea959d7621' THEN
    RAISE EXCEPTION '0333 P-: ottoq_sim_stop_and_reset moved from the measured two-phase wrapper';
  END IF;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0333-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
   AND p.proname IN ('ottoq_decide_tick', 'ottoq_sim_stop_and_reset');

ALTER TABLE public.ottoq_external_proposals
  ADD COLUMN IF NOT EXISTS disposition_reason text,
  ADD COLUMN IF NOT EXISTS disposed_at timestamptz,
  ADD COLUMN IF NOT EXISTS disposed_tick integer;

COMMENT ON COLUMN public.ottoq_external_proposals.disposition_reason IS
  '0333: deterministic terminal reason assigned by the kernel or run finalizer. Historical rows before 0333 are NULL.';
COMMENT ON COLUMN public.ottoq_external_proposals.disposed_at IS
  '0333: wall-clock audit stamp for the terminal disposition. Not part of the proposer packet.';
COMMENT ON COLUMN public.ottoq_external_proposals.disposed_tick IS
  '0333: run tick at which the kernel disposed the proposal; NULL for stop/finalize disposal.';

CREATE OR REPLACE FUNCTION public.ottoq_dispose_external_proposals(
  p_sim_run_id uuid,
  p_tick_seq integer DEFAULT NULL,
  p_sim_clock timestamptz DEFAULT NULL,
  p_finalize boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_clock timestamptz;
  v_wall  timestamptz := clock_timestamp();
  v_n     integer := 0;
BEGIN
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, v_wall)
    INTO v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;
  v_clock := COALESCE(v_clock, p_sim_clock, v_wall);

  UPDATE public.ottoq_external_proposals p
     SET status = CASE
                    WHEN p_finalize THEN 'expired'
                    WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                                  p.created_at + interval '35 minutes') < v_wall THEN 'expired'
                    ELSE 'refused'
                  END,
         disposition_reason = CASE
           WHEN p_finalize THEN 'run_finalized'
           WHEN GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                         p.created_at + interval '35 minutes') < v_wall THEN 'ttl_elapsed'
           WHEN COALESCE(p.proposal->>'stall_id', '') !~
                '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
             THEN 'invalid_stall_id'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid)
             THEN 'stall_missing'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.current_vehicle_id IS NOT NULL)
             THEN 'stall_occupied'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              WHERE s.id = (p.proposal->>'stall_id')::uuid
                AND s.reserved_by IS NOT NULL
                AND s.reserved_by <> p.entity_id
                AND (s.reservation_expires_at IS NULL OR s.reservation_expires_at > v_clock))
             THEN 'stall_reserved'
           WHEN NOT EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.station_state = 'Available')
             THEN 'charger_unavailable'
           WHEN EXISTS (
             SELECT 1 FROM public.stalls s
              JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
                WHERE s.id = (p.proposal->>'stall_id')::uuid
                  AND c.last_heartbeat_at < v_clock - interval '90 seconds')
             THEN 'charger_heartbeat_stale'
           ELSE 'target_no_longer_eligible'
         END,
         disposed_at = v_wall,
         disposed_tick = p_tick_seq
   WHERE p.sim_run_id = p_sim_run_id
     AND p.status = 'pending'
     AND (
       p_finalize
       OR GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
                   p.created_at + interval '35 minutes') < v_wall
       OR (
         p.action_context = 'stall_assignment'
         AND (
           COALESCE(p.proposal->>'stall_id', '') !~
             '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
           OR NOT EXISTS (
             SELECT 1
               FROM public.stalls s
               JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
              WHERE s.id = CASE
                WHEN COALESCE(p.proposal->>'stall_id', '') ~
                     '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
                THEN (p.proposal->>'stall_id')::uuid
                ELSE NULL
              END
                AND s.current_vehicle_id IS NULL
                AND (s.reserved_by IS NULL OR s.reserved_by = p.entity_id
                     OR s.reservation_expires_at <= v_clock)
                AND c.station_state = 'Available'
                AND c.last_heartbeat_at >= v_clock - interval '90 seconds'
           )
         )
       )
     );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean) IS
  '0333: closes pending external proposals with a deterministic reason. Tick mode refuses unavailable stall targets and expires real-time TTLs; finalize mode expires every remaining proposal before archive.';

REVOKE ALL ON FUNCTION public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean)
  TO service_role;

DO $patch_decide$
DECLARE d text; old text; new text; n integer;
BEGIN
  d := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  old := E'  UPDATE ottoq_external_proposals p SET status=''enacted''\n'
      || E'   WHERE p.sim_run_id=p_sim_run_id AND p.status=''pending''\n'
      || E'     AND EXISTS (SELECT 1 FROM ottoq_decisions d\n'
      || E'                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick\n'
      || E'                    AND d.entity_id=p.entity_id AND d.outcome_status=''enacted''\n'
      || E'                    AND d.enacted_action->>''source'' = p.source);\n'
      || E'  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal\n'
      || E'  UPDATE ottoq_external_proposals p SET status=''superseded''\n'
      || E'   WHERE p.sim_run_id=p_sim_run_id AND p.status=''pending''\n'
      || E'     AND EXISTS (SELECT 1 FROM ottoq_decisions d\n'
      || E'                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick\n'
      || E'                    AND d.entity_id=p.entity_id AND d.outcome_status=''enacted'');\n'
      || E'  UPDATE ottoq_external_proposals p SET status=''expired''\n'
      || E'   WHERE p.sim_run_id=p_sim_run_id AND p.status=''pending''\n'
      || E'     AND GREATEST(COALESCE(p.expires_at, p.created_at+interval ''35 minutes''), p.created_at+interval ''35 minutes'') < now();  -- 0122: the stamp is wall-domain (deliberate); the sweep must read the same clock';
  n := (length(d) - length(replace(d, old, ''))) / length(old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0333 patch_decide: lifecycle anchor occurs % times, expected 1', n;
  END IF;

  new := E'  UPDATE ottoq_external_proposals p\n'
      || E'     SET status=''enacted'', disposition_reason=''enacted_by_kernel'',\n'
      || E'         disposed_at=clock_timestamp(), disposed_tick=v_tick\n'
      || E'   WHERE p.sim_run_id=p_sim_run_id AND p.status=''pending''\n'
      || E'     AND EXISTS (SELECT 1 FROM ottoq_decisions d\n'
      || E'                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick\n'
      || E'                    AND d.entity_id=p.entity_id AND d.outcome_status=''enacted''\n'
      || E'                    AND d.enacted_action->>''source'' = p.source);\n'
      || E'  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal\n'
      || E'  UPDATE ottoq_external_proposals p\n'
      || E'     SET status=''superseded'', disposition_reason=''entity_decided_by_other_proposal'',\n'
      || E'         disposed_at=clock_timestamp(), disposed_tick=v_tick\n'
      || E'   WHERE p.sim_run_id=p_sim_run_id AND p.status=''pending''\n'
      || E'     AND EXISTS (SELECT 1 FROM ottoq_decisions d\n'
      || E'                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick\n'
      || E'                    AND d.entity_id=p.entity_id AND d.outcome_status=''enacted'');\n'
      || E'  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, v_tick, v_clock, false);';
  EXECUTE replace(d, old, new);
END $patch_decide$;

DO $patch_stop$
DECLARE d text; a text; n integer;
BEGIN
  d := pg_get_functiondef('public.ottoq_sim_stop_and_reset(uuid,text)'::regprocedure);
  a := E'  v_marked := ottoq_sim_mark_stopped(p_sim_run_id, p_reason);';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN
    RAISE EXCEPTION '0333 patch_stop: finalizer anchor occurs % times, expected 1', n;
  END IF;
  d := replace(d, a,
       E'  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);\n'
    || E'  v_marked := ottoq_sim_mark_stopped(p_sim_run_id, p_reason);');
  EXECUTE d;
END $patch_stop$;

-- Close historical leftovers only for runs that are already terminal. Active
-- runs were refused by preflight, so this cannot race a kernel tick.
UPDATE public.ottoq_external_proposals p
   SET status='expired', disposition_reason='run_finalized_backfill',
       disposed_at=clock_timestamp(), disposed_tick=NULL
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id=p.sim_run_id AND p.status='pending'
   AND r.status NOT IN ('running','paused');

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0333_every_solver_proposal_gets_a_deterministic_disposition',true,
  'The kernel now records enacted, superseded, expired and invalid-target proposal dispositions, and run stop expires every remaining pending proposal before archive. Proposal-ledger output changes, so recertification is required.',now())
ON CONFLICT(name) DO NOTHING;

DO $assertions$
DECLARE v text; n integer;
BEGIN
  SELECT p.prosrc INTO v FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname='ottoq_decide_tick'
     AND pg_get_function_identity_arguments(p.oid)='p_sim_run_id uuid';
  IF v NOT LIKE '%PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, v_tick, v_clock, false);%' THEN
    RAISE EXCEPTION '0333 A1: tick finalizer is absent';
  END IF;
  IF v LIKE '%UPDATE ottoq_external_proposals p SET status=''expired''%' THEN
    RAISE EXCEPTION '0333 A2: old reasonless expiry remains in decide_tick';
  END IF;

  SELECT p.prosrc INTO v FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname='ottoq_sim_stop_and_reset'
     AND pg_get_function_identity_arguments(p.oid)='p_sim_run_id uuid, p_reason text';
  IF v NOT LIKE '%ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true)%' THEN
    RAISE EXCEPTION '0333 A3: stop finalizer is absent';
  END IF;

  IF has_function_privilege('anon','public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean)','EXECUTE')
     OR has_function_privilege('authenticated','public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.ottoq_dispose_external_proposals(uuid,integer,timestamptz,boolean)','EXECUTE') THEN
    RAISE EXCEPTION '0333 A4: finalizer privileges are not service-role-only';
  END IF;

  SELECT count(*) INTO n FROM public.ottoq_external_proposals p
    JOIN public.ottoq_sim_runs r ON r.sim_run_id=p.sim_run_id
   WHERE p.status='pending' AND r.status NOT IN ('running','paused');
  IF n <> 0 THEN
    RAISE EXCEPTION '0333 A5: % terminal-run proposal(s) remain pending', n;
  END IF;
END $assertions$;
