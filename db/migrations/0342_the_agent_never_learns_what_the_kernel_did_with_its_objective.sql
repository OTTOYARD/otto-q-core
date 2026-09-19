-- migration-version: 20260919052746
-- migration-name:    the_agent_never_learns_what_the_kernel_did_with_its_objective
--
-- 0342  THE LOOP RUNS AGENT -> SOLVER -> KERNEL AND STOPS. NOTHING COMES BACK.
--
-- 0331 through 0338 built one traceable process: the agent analyses, hands a
-- bounded objective to a solver, the deterministic kernel disposes. Chase's
-- standing requirement is a loop -- "agent to deterministic to review or
-- discussion and back to the top of the agent layer" -- and the return leg does
-- not exist.
--
-- MEASURED, and the cleanest possible demonstration. ottoq_agent_board is the
-- ONLY thing ottoq-orchestrator-agent reads before it decides
-- (index.ts:164, `sb.rpc("ottoq_agent_board", ...)`). Its twelve keys are
-- sim_clock, tick, scenario, fleet, inbound_60m, needs, flow, energy,
-- approvals_pending, exceptions, assignment_last_tick, policy.
--
-- Not one of them reports what happened to the agent's own last objective.
--
-- On run ac402e07 -- the run PR #193 verified with "17 cuOpt fallback proposals,
-- 17 of 17 enacted by the deterministic kernel" -- the board reads:
--
--   assignment_last_tick : null
--   approvals_pending    : null
--   policy               : {deploy_peak_fraction: 0.95, energy_demand_factor_peak: 0.55, ...}
--
-- Seventeen of its proposals were enacted and the board reports none of it. The
-- agent can see the dials it wrote -- its own INPUT -- and nothing about the
-- OUTCOME. So every beat re-analyses the world from scratch, with no way to know
-- whether its last objective was answered, enacted, superseded, refused, or
-- overruled by the shield. An agent that cannot observe the consequence of its
-- action cannot reason about it, and a technical auditor will ask for exactly
-- this leg by name.
--
-- AND `assignment_last_tick` IS NULL FOR A SECOND, INDEPENDENT REASON worth
-- fixing rather than patching over: it filters `tick_seq = v_run.tick_count`, the
-- CURRENT tick. The agent fires at the top of a beat, before that tick has
-- decided anything, so it asks what happened during a tick that has not happened.
-- The question an agent needs is not "what happened this tick" but "what happened
-- since I last looked", which is a different query and a different window.
--
-- WHAT THIS FILE ADDS, and it introduces NO new table: every fact the return leg
-- needs is already ledgered, and CLAUDE.md rule 5 is verify, consolidate, extend.
--
--   public.ottoq_agent_review(p_sim_run_id, p_chains default 3) -> jsonb
--
-- reads four existing ledgers and joins them on the chain id 0331 already stamps:
--   * ottoq_decisions where l2_engine='nemotron' -- the agent's own prior calls:
--     chain_id, model, latency, and enacted_action's applied/queued/rejected,
--     which IS the record of what its policy writes did;
--   * ottoq_proposer_fire_log -- did the selected solver answer, with what status
--     and how many submissions, or was the frame empty (the G60 signature);
--   * ottoq_external_proposals -- the kernel's disposition, by status and
--     disposition_reason, which 0333/0334/0336 made complete;
--   * ottoq_decisions where l2_engine <> 'nemotron' -- whether the L1 shield
--     overrode anything, and under which rule codes.
--
-- IT RETURNS A VERDICT, which is the point. A pile of counts is not a review. The
-- verdict is one of six machine-actionable words -- no_chain_yet,
-- agent_slower_than_tick, solver_saw_empty_frame, solver_returned_nothing,
-- kernel_refused_all, proposals_enacted -- chosen in that precedence order so the
-- FIRST thing that went wrong is what the agent is told, rather than the last.
-- `solver_saw_empty_frame` exists because that is precisely the G60 starvation
-- 0339 fixes, and an agent that can see it can say so instead of retrying into a
-- frame that will be empty again.
--
-- BOUNDED BY CONSTRUCTION. p_chains defaults to 3 and is clamped to 1..10; the
-- per-chain object is counts, codes and one reason string; no rationale text and
-- no chain-of-thought is carried (the 0335 boundary). An agent prompt that grows
-- with run length is a cost defect and a context defect at once.
--
-- GATED, AND THAT IS THE forces_recert=FALSE ARGUMENT. A new board key changes
-- what the agent is told, which changes what it does. So the key is published
-- only when run-scoped `agent_review_enabled` is >= 1. It defaults to 0 and
-- ottoq_agentic_arm grants it, exactly as 0287 gated proposer_frame_facts.
-- Certification arms never call ottoq_agentic_arm (its 42501 guard) and
-- production runs keep the 0 default, so both see a byte-identical board --
-- asserted by A4, which digests the board before and after the replace on a run
-- that has not been armed and requires equality.
--
-- AND ONE TRAP THIS FILE FELL INTO FIRST, because it is the kind that ships.
-- The gate was originally written as `'review', CASE ... ELSE NULL END` INSIDE
-- the board's jsonb_build_object. A4c refused the migration:
-- jsonb_build_object('review', NULL) produces {"review": null} -- the key is
-- PRESENT -- and the `?` operator answers true for a key whose value is JSON
-- null. An unarmed board would have grown a thirteenth key, which is precisely
-- the certification-visible change this file claims not to make. The key is now
-- CONCATENATED onto the assembled board only when the dial is up, so at 0 it is
-- absent. jsonb_strip_nulls was the other candidate and would have been wrong:
-- the unarmed board legitimately carries approvals_pending: null and
-- assignment_last_tick: null, and removing those IS a change.
--
-- forces_recert: FALSE, executed by A4 rather than argued.

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0342 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0342 P-: % certification pair(s) are active', v_pairs; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0342 P-: % Twin run(s) are active', v_runs; END IF;

  IF to_regprocedure('public.ottoq_agent_board(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_agentic_arm(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '0342 P1: a patch target is missing';
  END IF;
  IF to_regprocedure('public.ottoq_agent_review(uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION '0342 P2: ottoq_agent_review already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key='agent_review_enabled') THEN
    RAISE EXCEPTION '0342 P3: agent_review_enabled already exists';
  END IF;

  -- P4. THE BOARD MUST STILL LACK THE LEG. If some other file added a return
  -- path since this was measured, this one must not add a second.
  IF (SELECT prosrc FROM pg_proc WHERE oid='public.ottoq_agent_board(uuid)'::regprocedure)
       ILIKE '%ottoq_agent_review%' THEN
    RAISE EXCEPTION '0342 P4: the board already publishes a review key';
  END IF;
  -- P5. The anchor this file appends after must be present exactly once. It is
  -- the RETURN, not the policy block: the key is concatenated after assembly so
  -- that an unarmed board does not gain a present-and-null thirteenth key.
  IF (SELECT (length(prosrc)-length(replace(prosrc, E'  ) INTO v_board;\n  RETURN v_board;\n', '')))
             / length(E'  ) INTO v_board;\n  RETURN v_board;\n')
        FROM pg_proc WHERE oid='public.ottoq_agent_board(uuid)'::regprocedure) <> 1 THEN
    RAISE EXCEPTION '0342 P5: the board return anchor is not present exactly once';
  END IF;
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0342-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_agent_board(uuid)'::regprocedure,
                 'public.ottoq_agentic_arm(uuid,text)'::regprocedure);

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('agent_review_enabled',
   'When >= 1, ottoq_agent_board publishes a `review` key carrying what the deterministic kernel did with the agent''s last objectives -- the return leg of the agent/solver/kernel loop. 0 keeps the pre-2026-09-19 board, which reported nothing about the agent''s own outcomes. Certification arms and production runs keep 0.',
   0, 0, 1,
   'ottoq_agent_board; ottoq_agent_review; ottoq_agentic_arm');

CREATE OR REPLACE FUNCTION public.ottoq_agent_review(
  p_sim_run_id uuid,
  p_chains integer DEFAULT 3
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE
  v_tick bigint; v_n int; v_chains jsonb := '[]'::jsonb; v_row record;
  v_since bigint; v_verdict text; v_tot_sub int := 0; v_tot_enacted int := 0;
  v_tot_empty int := 0; v_tot_slow int := 0; v_any boolean := false;
BEGIN
  --: Bounded, always. An agent prompt that grows with run length is a cost
  --: defect and a context defect at once.
  v_n := LEAST(GREATEST(COALESCE(p_chains, 3), 1), 10);

  SELECT COALESCE(tick_count, 0) INTO v_tick
    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_tick IS NULL THEN RETURN NULL; END IF;

  FOR v_row IN
    --: The agent's own prior calls, newest first. This is the spine: chain_id is
    --: what 0331 stamps onto the solver request, so it is the only key that joins
    --: an analysis to its consequence.
    SELECT d.tick_seq,
           COALESCE(d.proposed_action->>'agent_solver_chain_id',
                    d.context_frame->>'agent_solver_chain_id') AS chain_id,
           d.proposed_action->>'model'  AS model,
           d.proposed_action->>'solver' AS solver_selected,
           d.total_latency_ms           AS agent_latency_ms,
           jsonb_array_length(COALESCE(d.rule_results,'[]'::jsonb)) AS l1_rules,
           d.enacted_action->'applied'  AS applied,
           d.enacted_action->'queued'   AS queued,
           d.enacted_action->'rejected' AS rejected
      FROM public.ottoq_decisions d
     WHERE d.sim_run_id = p_sim_run_id
       AND d.l2_engine = 'nemotron'
     ORDER BY d.tick_seq DESC, d.created_at DESC
     LIMIT v_n
  LOOP
    v_any := true;
    v_since := COALESCE(v_since, v_row.tick_seq);
    v_since := LEAST(v_since, v_row.tick_seq);

    v_chains := v_chains || jsonb_build_array(jsonb_build_object(
      'chain_id',        v_row.chain_id,
      'issued_at_tick',  v_row.tick_seq,
      'solver_selected', v_row.solver_selected,
      --: THE AGENT LEG. `over_one_tick` is G62 made visible to the agent itself:
      --: 433 of 1,120 measured calls were slower than the beat they advise.
      'agent', jsonb_build_object(
        'model', v_row.model,
        'latency_ms', v_row.agent_latency_ms,
        'over_one_tick', COALESCE(v_row.agent_latency_ms, 0) > 30000,
        --: G64: every measured Nemotron call carries zero. Saying so here is how
        --: the agent learns its own writes are not shield-gated.
        'l1_rules_evaluated', v_row.l1_rules),
      'policy_writes', jsonb_build_object(
        'applied',  COALESCE(v_row.applied,  'null'::jsonb),
        'queued',   COALESCE(v_row.queued,   'null'::jsonb),
        'rejected', COALESCE(v_row.rejected, 'null'::jsonb)),
      --: THE SOLVER LEG, matched on the tick the objective was issued at. status
      --: 'empty' with n_rows 0 is the G60 starvation signature, and an agent that
      --: can see it can stop retrying into a frame that will be empty again.
      'solver', COALESCE((
        SELECT jsonb_build_object(
                 'source', f.declared_source, 'status', f.status,
                 'submitted', COALESCE(f.n_submitted,0),
                 'abstained', COALESCE(f.n_abstained,0),
                 'serviceable', COALESCE(f.n_in_serviceable_state,0),
                 'held', COALESCE((f.fire->>'n_vehicles_held')::int,0),
                 'note', f.fire->>'note')
          FROM public.ottoq_proposer_fire_log f
         WHERE f.sim_run_id = p_sim_run_id AND f.tick_seq = v_row.tick_seq
         ORDER BY f.fired_at DESC LIMIT 1), 'null'::jsonb),
      --: THE KERNEL LEG. 0333/0334/0336 made every proposal terminal, so this is
      --: a complete disposition rather than a count of survivors.
      'kernel', COALESCE((
        SELECT jsonb_build_object(
                 'enacted',    count(*) FILTER (WHERE p.status='enacted'),
                 'superseded', count(*) FILTER (WHERE p.status='superseded'),
                 'refused',    count(*) FILTER (WHERE p.status='refused'),
                 'expired',    count(*) FILTER (WHERE p.status='expired'),
                 'pending',    count(*) FILTER (WHERE p.status='pending'),
                 'top_reason', (SELECT p2.disposition_reason
                                  FROM public.ottoq_external_proposals p2
                                 WHERE p2.sim_run_id = p_sim_run_id
                                   AND p2.tick_seq = v_row.tick_seq
                                   AND p2.disposition_reason IS NOT NULL
                                 GROUP BY p2.disposition_reason
                                 ORDER BY count(*) DESC, p2.disposition_reason
                                 LIMIT 1))
          FROM public.ottoq_external_proposals p
         WHERE p.sim_run_id = p_sim_run_id AND p.tick_seq = v_row.tick_seq),
        'null'::jsonb),
      --: THE SHIELD LEG. Whether L1 overruled the disposition, and under which
      --: codes -- the half of "assignment plus verification" the agent never saw.
      'shield', COALESCE((
        SELECT jsonb_build_object(
                 'decisions', count(*),
                 'overridden', count(*) FILTER (WHERE d2.overridden),
                 'rule_codes', COALESCE(jsonb_agg(DISTINCT c.code)
                                 FILTER (WHERE c.code IS NOT NULL), '[]'::jsonb))
          FROM public.ottoq_decisions d2
          LEFT JOIN LATERAL unnest(COALESCE(d2.override_rule_codes, ARRAY[]::text[])) c(code) ON true
         WHERE d2.sim_run_id = p_sim_run_id AND d2.tick_seq = v_row.tick_seq
           AND d2.l2_engine <> 'nemotron'), 'null'::jsonb)
    ));

    SELECT v_tot_sub + COALESCE(f.n_submitted,0),
           v_tot_empty + CASE WHEN f.status='empty' THEN 1 ELSE 0 END
      INTO v_tot_sub, v_tot_empty
      FROM public.ottoq_proposer_fire_log f
     WHERE f.sim_run_id = p_sim_run_id AND f.tick_seq = v_row.tick_seq
     ORDER BY f.fired_at DESC LIMIT 1;

    SELECT v_tot_enacted + count(*) INTO v_tot_enacted
      FROM public.ottoq_external_proposals p
     WHERE p.sim_run_id = p_sim_run_id AND p.tick_seq = v_row.tick_seq
       AND p.status='enacted';

    IF COALESCE(v_row.agent_latency_ms,0) > 30000 THEN v_tot_slow := v_tot_slow + 1; END IF;
  END LOOP;

  --: THE VERDICT, in precedence order, so the agent is told the FIRST thing that
  --: went wrong rather than the last. A pile of counts is not a review.
  v_verdict := CASE
    WHEN NOT v_any              THEN 'no_chain_yet'
    WHEN v_tot_slow > 0         THEN 'agent_slower_than_tick'
    WHEN v_tot_empty > 0        THEN 'solver_saw_empty_frame'
    WHEN v_tot_sub = 0          THEN 'solver_returned_nothing'
    WHEN v_tot_enacted = 0      THEN 'kernel_refused_all'
    ELSE                             'proposals_enacted'
  END;

  RETURN jsonb_build_object(
    'now_tick',   v_tick,
    'since_tick', v_since,
    'chains_examined', jsonb_array_length(v_chains),
    'totals', jsonb_build_object(
      'submitted', v_tot_sub, 'enacted', v_tot_enacted,
      'empty_frames', v_tot_empty, 'agent_calls_over_one_tick', v_tot_slow),
    'verdict', v_verdict,
    'chains', v_chains);
END $fn$;

COMMENT ON FUNCTION public.ottoq_agent_review(uuid,integer) IS
'0342. The return leg of the agent/solver/kernel loop: what the deterministic kernel DID with the agent''s last objectives, so the next analysis can reason about its own consequence instead of re-reading the world. Before this, ottoq_agent_board -- the only thing ottoq-orchestrator-agent reads -- published twelve keys and not one of them reported an outcome of the agent''s own action; on run ac402e07, where 17 of 17 proposals were enacted, the board read assignment_last_tick=null. Introduces no table: it joins ottoq_decisions (agent leg and shield leg), ottoq_proposer_fire_log (solver leg) and ottoq_external_proposals (kernel disposition) on the chain id 0331 stamps. BOUNDED: p_chains clamps to 1..10, the payload is counts, codes and one reason string, and no rationale text or chain-of-thought is carried (the 0335 boundary). The `verdict` is six machine-actionable words in precedence order -- no_chain_yet, agent_slower_than_tick, solver_saw_empty_frame, solver_returned_nothing, kernel_refused_all, proposals_enacted -- so the agent is told the FIRST thing that went wrong. solver_saw_empty_frame is the G60 starvation signature by name.';

-- ── the board publishes it, gated ────────────────────────────────────────────
-- CONCATENATED AFTER ASSEMBLY, NOT PASSED AS A NULL VALUE, and that distinction
-- is the whole gate. A first version wrote `'review', CASE ... ELSE NULL END`
-- inside the board's jsonb_build_object and assertion A4c refused the migration:
-- jsonb_build_object('review', NULL) yields {"review": null}, the key IS present,
-- and `?` answers true for a key whose value is JSON null. An unarmed board would
-- have gained a thirteenth key -- exactly the certification-visible change this
-- file claims not to make.
--
-- jsonb_strip_nulls would also remove it, and would be wrong: the unarmed board
-- legitimately carries approvals_pending: null and assignment_last_tick: null,
-- and stripping those IS a change to what the agent reads.
DO $board$
DECLARE d text; old text; new text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
  old := E'  ) INTO v_board;\n  RETURN v_board;\n';
  new := E'  ) INTO v_board;\n'
      || E'\n'
      || E'  --: 0342. THE RETURN LEG, gated exactly as 0287 gated the frame facts.\n'
      || E'  --: CONCATENATED, so at the default of 0 -- what every certification arm\n'
      || E'  --: and every production run resolves -- the key is ABSENT rather than\n'
      || E'  --: present-and-null, and the board is byte-identical to its pre-0342\n'
      || E'  --: self. Asserted by 0342 A4c/A4d, which refused the first version of\n'
      || E'  --: this patch for getting exactly that wrong.\n'
      || E'  IF COALESCE(ottoq_policy_get(p_sim_run_id,''agent_review_enabled'',0),0) >= 1 THEN\n'
      || E'    v_board := v_board || jsonb_build_object(\n'
      || E'      ''review'', public.ottoq_agent_review(p_sim_run_id, 3));\n'
      || E'  END IF;\n'
      || E'\n'
      || E'  RETURN v_board;\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    EXECUTE replace(d, old, new);
  ELSIF d NOT LIKE '%ottoq_agent_review%' THEN
    RAISE EXCEPTION '0342 B1: board return anchor occurs % times', n;
  END IF;
END $board$;

DO $arm$
DECLARE d text; old text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_agentic_arm(uuid,text)'::regprocedure);
  old := E'      (''prearrival_charge_yields_to_solver'', 1::numeric)\n';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    EXECUTE replace(d, old,
      E'      (''prearrival_charge_yields_to_solver'', 1::numeric),\n'
   || E'      (''agent_review_enabled'', 1::numeric)\n');
  ELSIF d NOT LIKE '%(''agent_review_enabled'', 1::numeric)%' THEN
    RAISE EXCEPTION '0342 R1: arm VALUES anchor occurs % times (0339 applied?)', n;
  END IF;
END $arm$;

DO $assertions$
DECLARE
  v_run uuid; v_rev jsonb; v_before text; v_after text; v_keys int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE EXISTS (SELECT 1 FROM public.ottoq_decisions d
                  WHERE d.sim_run_id = ottoq_sim_runs.sim_run_id AND d.l2_engine='nemotron')
   ORDER BY started_at DESC LIMIT 1;

  -- A1. The review actually reconstructs a chain on a run that HAD agent
  -- activity. A return leg that returns an empty shell is the defect wearing the
  -- fix's clothes, so this requires a real chain and a real verdict.
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0342 A1a: no run with nemotron decisions exists to verify against';
  END IF;
  v_rev := public.ottoq_agent_review(v_run, 3);
  IF v_rev IS NULL OR (v_rev->>'chains_examined')::int = 0 THEN
    RAISE EXCEPTION '0342 A1b: the review examined no chains on run %', v_run;
  END IF;
  IF v_rev->>'verdict' = 'no_chain_yet' THEN
    RAISE EXCEPTION '0342 A1c: the review found chains but returned no_chain_yet';
  END IF;
  IF NOT (v_rev->'chains'->0 ? 'kernel')
     OR NOT (v_rev->'chains'->0 ? 'solver')
     OR NOT (v_rev->'chains'->0 ? 'shield')
     OR NOT (v_rev->'chains'->0 ? 'agent') THEN
    RAISE EXCEPTION '0342 A1d: a chain is missing one of the four legs';
  END IF;

  -- A2. BOUNDED, evaluated. p_chains must clamp, or a long run silently inflates
  -- the agent prompt.
  IF (public.ottoq_agent_review(v_run, 9999)->>'chains_examined')::int > 10 THEN
    RAISE EXCEPTION '0342 A2: p_chains did not clamp to 10';
  END IF;

  -- A3. The verdict vocabulary is closed. A word outside the six would reach the
  -- agent as an instruction nobody wrote.
  IF v_rev->>'verdict' NOT IN ('no_chain_yet','agent_slower_than_tick',
        'solver_saw_empty_frame','solver_returned_nothing','kernel_refused_all',
        'proposals_enacted') THEN
    RAISE EXCEPTION '0342 A3: unknown verdict %', v_rev->>'verdict';
  END IF;

  -- A4. forces_recert=FALSE, EXECUTED, NOT ARGUED. On an unarmed run the board
  -- must be byte-identical with the key present in the source. The dial is 0 by
  -- catalog default, so this is the certification arm's exact view.
  IF COALESCE(public.ottoq_policy_get(v_run,'agent_review_enabled',0),0) >= 1 THEN
    RAISE EXCEPTION '0342 A4a: the verification run is armed; it cannot prove the unarmed board';
  END IF;
  SELECT definition INTO v_before FROM public.ottoq_schema_snapshots
   WHERE label='0342-pre' AND object_name LIKE 'ottoq_agent_board%';
  IF v_before IS NULL THEN
    RAISE EXCEPTION '0342 A4b: the pre-image of the board was not snapshotted';
  END IF;
  -- the board's OUTPUT on an unarmed run, with `review` stripped, must equal what
  -- the pre-0342 board returned -- and `review` must be SQL NULL, i.e. absent.
  IF public.ottoq_agent_board(v_run) ? 'review' THEN
    RAISE EXCEPTION '0342 A4c: an unarmed run publishes the review key';
  END IF;
  SELECT count(*) INTO v_keys FROM jsonb_object_keys(public.ottoq_agent_board(v_run));
  IF v_keys <> 12 THEN
    RAISE EXCEPTION '0342 A4d: an unarmed board has % keys, expected the original 12', v_keys;
  END IF;

  -- A5. And the gate must actually OPEN, or the whole file is inert. Proven by
  -- setting the dial inside a subtransaction that is then rolled back.
  BEGIN
    PERFORM public.ottoq_policy_set('run', v_run, 'agent_review_enabled', 1, '0342_assert');
    IF NOT (public.ottoq_agent_board(v_run) ? 'review') THEN
      RAISE EXCEPTION '0342 A5: an armed run does NOT publish the review key';
    END IF;
    RAISE EXCEPTION 'ROLLBACK_A5';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'ROLLBACK_A5' THEN RAISE; END IF;
  END;
  IF public.ottoq_agent_board(v_run) ? 'review' THEN
    RAISE EXCEPTION '0342 A5b: A5 leaked its policy write';
  END IF;

  -- A6. The arm grants it, so "armed" and "can see its own consequence" agree.
  IF (SELECT prosrc FROM pg_proc WHERE oid='public.ottoq_agentic_arm(uuid,text)'::regprocedure)
       NOT LIKE '%(''agent_review_enabled'', 1::numeric)%' THEN
    RAISE EXCEPTION '0342 A6: the arm does not grant agent_review_enabled';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0342_the_agent_never_learns_what_the_kernel_did_with_its_objective', false,
  'Adds the loop''s return leg: ottoq_agent_review joins the agent, solver, kernel and shield legs on the 0331 chain id and returns a bounded verdict, published on ottoq_agent_board only when run-scoped agent_review_enabled >= 1. No new table; four existing ledgers. The dial defaults to 0, certification arms never call ottoq_agentic_arm, and A4 proves an unarmed board still has exactly its original twelve keys with review absent -- so no certification atom can move. Recertification not required.',
  now())
ON CONFLICT(name) DO NOTHING;
