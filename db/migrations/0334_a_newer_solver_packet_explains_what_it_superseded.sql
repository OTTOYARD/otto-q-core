-- migration-version: 20260916180920
-- migration-name:    a_newer_solver_packet_explains_what_it_superseded
--
-- Live 0333 proof, run a2b246ed-80d1-4fe3-8dc0-362514eeb58e:
--   832 agent decisions -> 716 chained cuOpt proposals -> 33 commands.
--   Zero proposals remained pending after finalization.
--   28 finalization expiries carried `run_finalized`, but 688 superseded rows
--   had no reason. They were superseded at submission, before decide_tick's
--   reasoned lifecycle block could see them.
--
-- 0334 closes that one remaining door. The older packet is terminal because a
-- newer packet for the same run, context and entity replaced it.
-- forces_recert: TRUE. Proposal-ledger output changes.

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int; v_md5 text;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0334 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0334 P-: % certification pair(s) are active', v_pairs; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0334 P-: % Twin run(s) are active', v_runs; END IF;

  SELECT md5(p.prosrc) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_submit_external_proposal'
     AND pg_get_function_identity_arguments(p.oid)=
       'p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text, p_ttl_seconds integer';
  IF v_md5 <> '40427794304a728c9a66ffa8f5b60f36' THEN
    RAISE EXCEPTION '0334 P-: proposal submit door moved (md5 %)', v_md5;
  END IF;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0334-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_submit_external_proposal'
   AND pg_get_function_identity_arguments(p.oid)=
     'p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text, p_ttl_seconds integer';

DO $patch$
DECLARE d text; old text; new text; n integer;
BEGIN
  d := pg_get_functiondef('public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)'::regprocedure);
  old := E'  UPDATE public.ottoq_external_proposals SET status=''superseded''\n'
      || E'   WHERE sim_run_id=p_sim_run_id AND action_context=p_action_context\n'
      || E'     AND entity_type=p_entity_type AND entity_id=p_entity_id AND status=''pending'';';
  n := (length(d)-length(replace(d,old,''))) / length(old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0334 patch: submit supersede anchor occurs % times, expected 1', n;
  END IF;
  new := E'  UPDATE public.ottoq_external_proposals\n'
      || E'     SET status=''superseded'',\n'
      || E'         disposition_reason=''newer_proposal_same_entity'',\n'
      || E'         disposed_at=clock_timestamp(),\n'
      || E'         disposed_tick=(SELECT r.tick_count FROM public.ottoq_sim_runs r\n'
      || E'                         WHERE r.sim_run_id=p_sim_run_id)\n'
      || E'   WHERE sim_run_id=p_sim_run_id AND action_context=p_action_context\n'
      || E'     AND entity_type=p_entity_type AND entity_id=p_entity_id AND status=''pending'';';
  EXECUTE replace(d,old,new);
END $patch$;

-- Before 0334 there was no separate reason column at the submission door. The
-- cause is nevertheless knowable from that door's exact predicate: a newer
-- packet for the same entity superseded the older pending packet.
UPDATE public.ottoq_external_proposals
   SET disposition_reason='newer_proposal_same_entity',
       disposed_at=COALESCE(disposed_at, created_at),
       disposed_tick=COALESCE(disposed_tick, tick_seq)
 WHERE status='superseded' AND disposition_reason IS NULL;

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0334_a_newer_solver_packet_explains_what_it_superseded',true,
  'The proposal submission door now records why and when it supersedes an older pending packet for the same run, context and entity. Proposal-ledger output changes, so recertification is required.',now())
ON CONFLICT(name) DO NOTHING;

DO $assert$
DECLARE v text; n integer;
BEGIN
  SELECT p.prosrc INTO v
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname='ottoq_submit_external_proposal'
     AND pg_get_function_identity_arguments(p.oid)=
       'p_sim_run_id uuid, p_depot_id uuid, p_action_context text, p_entity_type text, p_entity_id uuid, p_proposal jsonb, p_source text, p_ttl_seconds integer';
  IF v NOT LIKE '%disposition_reason=''newer_proposal_same_entity''%' THEN
    RAISE EXCEPTION '0334 A1: submit door still supersedes without a reason';
  END IF;
  SELECT count(*) INTO n FROM public.ottoq_external_proposals
   WHERE status='superseded' AND disposition_reason IS NULL;
  IF n <> 0 THEN RAISE EXCEPTION '0334 A2: % superseded proposal(s) remain reasonless', n; END IF;
END $assert$;
