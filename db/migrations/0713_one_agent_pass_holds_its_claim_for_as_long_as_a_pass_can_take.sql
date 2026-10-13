-- migration-version: PENDING
-- migration-name:    one_agent_pass_holds_its_claim_for_as_long_as_a_pass_can_take
--
-- 0713  **One agent pass holds its claim for as long as a pass can take.** ottoq_agent_chain_claim lets a new agent
--        pass in once the previous one has written its decision, or once its claim is older than
--        agent_chain_inflight_timeout_s. That lease was sized at 45 s by 0338, when a Nemotron call took about 29 s. Edge
--        v23 since gave the model a 90-second retry budget and the solver a 30-second window, so a pass can run about
--        125 s, and on run 176b2912 58 of 79 passes started while another was still running (G423; the study's DC-6).
--        The default is now 130 s and the ceiling 180. A finished pass still releases the claim at once.
--
--        AND THE DEFAULT IS THE CLAIM'S, NOT THE CATALOG'S. public.ottoq_policy_get reads the run, then the depot, then
--        the global scope, then the caller's own literal; it never reads ottoq_policy_param_catalog.default_value
--        (measured: a run with no row reads whatever the caller passes, 7 when asked with 7). So the engine's default
--        for this lease is the 45 written inside ottoq_agent_chain_claim, and changing the catalog row alone would have
--        changed nothing. This file changes the literal, and keeps the catalog row in step with it (G429).
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0338 (2026-09-17): "Live run 911a5d0d measured Nemotron at about 29 seconds ... A crashed call expires after 45
--   seconds." The edge function now has (edge-functions/ottoq-orchestrator-agent/index.ts): MODEL_TIMEOUT_MS 75,000 per
--   attempt, MODEL_BUDGET_MS 90,000 across the primary and fallback models, SOLVER_TIMEOUT_MS 30,000. Two settings that
--   must agree drifted apart, one in an edge function and one in the catalog.
--
--   Measured (db/checks/0440 §6, §10):
--     run 176b2912, lease 45 s, gate in shadow:  consulted pass p50 59.5 s, p90 98.4 s, max 107.9 s;
--                                                58 of 79 passes started while another was still running.
--     run 57188f55, lease 120 s (run-scoped), gate on:  0 of the first 46 passes overlapped.
--   An overlapping pass computes on a board a minute older than the one before it, and whichever finishes later
--   stands, so the order in force was chosen by network timing (DC-6).
--
--   What a longer lease costs: only a pass that crashes without writing a decision holds the claim longer. A pass that
--   finishes releases it at once (the claim reads the decision row), so the healthy path is unchanged.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   a. public.ottoq_agent_chain_claim (md5 aad09c12), by SUBSTITUTION, one anchor asserted to occur exactly once:
--      ottoq_policy_get(p_sim_run_id,'agent_chain_inflight_timeout_s',45) → ...,130). Every other byte is the live one.
--   b. The catalog row agent_chain_inflight_timeout_s: default 45 → 130, max 120 → 180 (the write clamp a person's run-
--      scoped value is held to), description says why.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   Read only by ottoq_agent_chain_claim, which only the agent's edge function calls; the agent is quiesced in
--   certification arms and off in the A/B, dial and sweep harnesses.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the ottoq_agent_chain_claim definition snapshotted under label '0713_pre', then
--   UPDATE public.ottoq_policy_param_catalog SET default_value = 45, max_value = 120
--    WHERE param_key = 'agent_chain_inflight_timeout_s';

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0713 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE v_row record; v_readers text;
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_agent_chain_claim(uuid,text)'::regprocedure))
     IS DISTINCT FROM 'aad09c12e9c8cd61d9ae4b527219439d' THEN
    RAISE EXCEPTION '0713 P1: ottoq_agent_chain_claim is not the definition this file was written against';
  END IF;
  SELECT default_value, min_value, max_value, agent_writable INTO v_row
    FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_chain_inflight_timeout_s';
  IF v_row.default_value IS DISTINCT FROM 45 OR v_row.max_value IS DISTINCT FROM 120
     OR v_row.min_value IS DISTINCT FROM 10 OR COALESCE(v_row.agent_writable, false) THEN
    RAISE EXCEPTION '0713 P1: the lease row is not as 0338 wrote it: %', to_jsonb(v_row);
  END IF;
  --: one reader, the claim
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prokind = 'f'
     AND pg_get_functiondef(p.oid) LIKE '%agent_chain_inflight_timeout_s%';
  IF v_readers IS DISTINCT FROM 'ottoq_agent_chain_claim(uuid,text)' THEN
    RAISE EXCEPTION '0713 P1: the lease is read by more than the claim: %', v_readers;
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0713_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_chain_claim';

DO $claim$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_agent_chain_claim(uuid,text)'::regprocedure);
  v_old constant text := E'public.ottoq_policy_get(p_sim_run_id,''agent_chain_inflight_timeout_s'',45)::integer);';
  v_new constant text := E'public.ottoq_policy_get(p_sim_run_id,''agent_chain_inflight_timeout_s'',130)::integer);  --: 0713';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0713: the lease default occurs % times in ottoq_agent_chain_claim, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $claim$;

UPDATE public.ottoq_policy_param_catalog
   SET default_value = 130,
       max_value     = 180,
       description   = 'Real-second lease for one in-flight agent pass per run. A later FIRE beat starts a new pass only '
                       'after the prior pass''s decision is recorded or this lease expires. 0713: 130 s, because a pass '
                       'can run about 125 s (a 90 s model budget across two models, a 30 s solver window, the board); '
                       'at 0338''s 45 s, 58 of 79 passes on run 176b2912 started while another was still running.'
 WHERE param_key = 'agent_chain_inflight_timeout_s';

DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_chain_claim(uuid,text)'::regprocedure);
        v_old text := (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0713_pre' AND s.object_name = 'ottoq_agent_chain_claim' LIMIT 1);
BEGIN
  --: V1 the claim's default is 130, and undoing that one literal gives the old definition back
  IF strpos(v_def, '''agent_chain_inflight_timeout_s'',130)') = 0
     OR replace(v_def, ',130)::integer);  --: 0713', ',45)::integer);') <> v_old THEN
    RAISE EXCEPTION '0713 V1 FAILED: the claim changed by more than its lease default';
  END IF;
  --: V2 the catalog row agrees with the literal its one reader passes
  IF (SELECT default_value FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_chain_inflight_timeout_s') <> 130 THEN
    RAISE EXCEPTION '0713 V2 FAILED: the catalog and the claim disagree';
  END IF;
  RAISE NOTICE '0713 V1-V2 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0713_one_agent_pass_holds_its_claim_for_as_long_as_a_pass_can_take', false, false,
  'G423 (db/checks/0440 §6, §10): the agent claim lease, 45 s since 0338, was shorter than a pass (p50 59.5 s, up to '
  '~125 s under edge v23''s budgets); 58 of 79 passes overlapped on run 176b2912, 0 at 120 s on 57188f55. The claim''s '
  'literal default 130 (ottoq_policy_get never reads the catalog default, G429), catalog in step, max 180. Read only by '
  'the agent''s claim, quiesced in certification arms: FALSE/FALSE.',
  now());

COMMIT;
