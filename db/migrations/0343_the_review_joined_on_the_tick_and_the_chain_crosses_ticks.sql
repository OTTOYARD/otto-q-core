-- migration-version: PENDING
-- migration-name:    the_review_joined_on_the_tick_and_the_chain_crosses_ticks
--
-- 0343  0342's REVIEW REPORTED "kernel: enacted 0, solver: null" FOR A CHAIN
--       WHOSE SEVENTEEN PROPOSALS WERE ALL ENACTED.
--
-- 0342 shipped the loop's return leg and its first live read was wrong, in the
-- direction that makes a working system look broken. On run ac402e07 it returned:
--
--   kernel : {enacted: 0, superseded: 0, refused: 0, expired: 0}
--   solver : null
--   verdict: agent_slower_than_tick
--
-- while the run's seventeen proposals were, in fact, all enacted.
--
-- THE CAUSE IS A JOIN, and the measurement is unambiguous:
--
--   agent decisions on that run   : ticks 1, 2, 17, 31
--   proposals on that run         : ticks 2, 3
--   all 17 carry agent_handoff.chain_id = 39dea39e-6c83-4eef-a90a-7223d2f22672
--   that chain_id joins to an agent decision row : TRUE
--   the chain's own agent_tick                   : 1
--
-- The agent analysed at tick 1 and its proposals landed at ticks 2 and 3, because
-- `net.http_post` only QUEUES -- the request is delivered after the transaction
-- commits, so the solver answers on a LATER beat by construction. 0342 joined the
-- kernel and solver legs on `tick_seq = <agent tick>`, an equality that is
-- therefore wrong for every chain that ever worked. It found nothing precisely
-- when the loop had worked perfectly.
--
-- AND THE JOIN IT SHOULD HAVE USED WAS ALREADY THERE. Measured across the whole
-- table: **2,490 of 18,826 proposals carry a chain id, across 477 distinct
-- chains**, last written 2026-09-17 12:42:11 UTC. 0331 does stamp it, and
-- `ottoq-cuopt-propose` writes it at `proposal.agent_handoff.chain_id`.
--
-- A NOTE ON HOW I FIRST MIS-READ THAT, because the method matters. A query for
-- `proposal ? 'agent_solver_chain_id'` returned 0 of 18,826 and I briefly had a
-- much louder finding: that the chain id 0331's header claims to stamp is stamped
-- nowhere, and the "one traceable process" is unverifiable. It was my key path
-- that was wrong -- the stamp is NESTED under `agent_handoff`, and the top-level
-- name only ever existed on the agent's own ottoq_decisions row. A `?` returning
-- zero is evidence about a key, not about a capability, and the difference here
-- was the difference between "the loop is not traceable" and "the loop is
-- traceable and my query wasn't".
--
-- WHAT THIS FILE CHANGES, one function, no schema:
--
--   1. THE KERNEL LEG JOINS ON chain_id, not on tick. True linkage, recorded by
--      the producer, crossing tick boundaries as the transport requires.
--   2. THE SOLVER LEG READS ottoq_model_call_ledger (0340) rather than
--      ottoq_proposer_fire_log alone. That was the second half of the null:
--      ottoq_proposer_fire_log holds **0 rows for this run** because it is
--      written by the forward_lex bridge, while cuOpt records into
--      cuopt_invocation_log. Two proposers, two ledgers, and 0340 exists to
--      unify them -- so the review reads the union and stops depending on which
--      solver happened to answer. The fire log is still consulted, for the
--      frame-shape facts only it carries (serviceable/held, the G60 signature).
--   3. EVERY CHAIN CARRIES A `linkage` FIELD -- 'chain_id', 'tick' or 'none' --
--      so a reader can never mistake an inferred association for a recorded one.
--      An unlinked chain reports `none` and zero counts, which is the honest
--      answer, rather than zeros that look like refusals.
--   4. `lag_ticks`: how many beats after the agent's analysis the first proposal
--      of its chain landed. On ac402e07 that is 1. It compounds G62 -- an agent
--      already a tick late advises a world that has moved another beat -- and it
--      was invisible before because the wrong join hid it.
--   5. NULL-SAFE ACCUMULATION. 0342's totals read `submitted: null,
--      empty_frames: null` and that is a defect of its own: `SELECT expr INTO v`
--      over ZERO ROWS sets v to NULL in plpgsql, so one tick without a fire row
--      poisoned the running total permanently. Worse, it disabled a verdict:
--      `v_tot_sub = 0` is NULL once poisoned, never true, so
--      'solver_returned_nothing' could not fire. Accumulators are now scalar
--      subqueries wrapped in COALESCE and can only be integers.
--
-- forces_recert: FALSE. One STABLE read-only function is replaced, reached only
-- through ottoq_agent_board's gated `review` key, which an unarmed run does not
-- publish (0342 A4). A1 re-asserts the unarmed board is still twelve keys.

DO $preflight$
DECLARE v_jobs text; v_runs int; v_chained int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0343 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0343 P-: % Twin run(s) are active', v_runs; END IF;

  IF to_regprocedure('public.ottoq_agent_review(uuid,integer)') IS NULL THEN
    RAISE EXCEPTION '0343 P1: 0342 has not been applied';
  END IF;
  IF to_regclass('public.ottoq_model_call_ledger') IS NULL THEN
    RAISE EXCEPTION '0343 P2: 0340 has not been applied; the solver leg has nothing to read';
  END IF;

  -- P3. THE JOIN KEY THIS FILE SWITCHES TO MUST ACTUALLY BE POPULATED, or the new
  -- version trades a wrong join for an empty one. This is the number the header
  -- quotes, asserted rather than remembered.
  SELECT count(*) INTO v_chained FROM public.ottoq_external_proposals
   WHERE proposal->'agent_handoff'->>'chain_id' IS NOT NULL;
  IF v_chained = 0 THEN
    RAISE EXCEPTION '0343 P3: no proposal carries agent_handoff.chain_id; the chain join would be empty';
  END IF;
  RAISE NOTICE '0343: % proposals carry a chain id across % chains', v_chained,
    (SELECT count(DISTINCT proposal->'agent_handoff'->>'chain_id')
       FROM public.ottoq_external_proposals
      WHERE proposal->'agent_handoff'->>'chain_id' IS NOT NULL);
END $preflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0343-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p WHERE p.oid='public.ottoq_agent_review(uuid,integer)'::regprocedure;

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
  v_since bigint; v_verdict text;
  v_tot_sub int := 0; v_tot_enacted int := 0; v_tot_empty int := 0;
  v_tot_slow int := 0; v_any boolean := false;
  v_linkage text; v_kernel jsonb; v_solver jsonb; v_lag bigint;
  v_sub int; v_enacted int; v_empty int;
BEGIN
  v_n := LEAST(GREATEST(COALESCE(p_chains, 3), 1), 10);

  SELECT COALESCE(tick_count, 0) INTO v_tick
    FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_tick IS NULL THEN RETURN NULL; END IF;

  FOR v_row IN
    SELECT d.tick_seq,
           COALESCE(d.proposed_action->>'agent_solver_chain_id',
                    d.context_frame->>'agent_solver_chain_id') AS chain_id,
           d.proposed_action->>'model'  AS model,
           d.proposed_action->>'solver' AS solver_objective,
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
    v_since := LEAST(COALESCE(v_since, v_row.tick_seq), v_row.tick_seq);

    --: THE LINKAGE, DECLARED. 'chain_id' is the producer's own key and the only
    --: honest linkage; 'none' means this analysis cannot be tied to a proposal at
    --: all, and says so instead of reporting zeros that read as refusals.
    v_linkage := CASE
      WHEN v_row.chain_id IS NULL THEN 'none'
      WHEN EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
                    WHERE p.sim_run_id = p_sim_run_id
                      AND p.proposal->'agent_handoff'->>'chain_id' = v_row.chain_id)
        THEN 'chain_id'
      ELSE 'none' END;

    --: THE KERNEL LEG, joined on chain_id. 0342 joined on tick equality, which is
    --: wrong for every chain that worked: net.http_post only QUEUES, so the
    --: solver answers on a LATER beat. Measured on ac402e07: agent at tick 1,
    --: proposals at ticks 2 and 3, all 17 enacted, all carrying that chain id.
    IF v_linkage = 'chain_id' THEN
      SELECT jsonb_build_object(
               'enacted',    count(*) FILTER (WHERE p.status='enacted'),
               'superseded', count(*) FILTER (WHERE p.status='superseded'),
               'refused',    count(*) FILTER (WHERE p.status='refused'),
               'expired',    count(*) FILTER (WHERE p.status='expired'),
               'pending',    count(*) FILTER (WHERE p.status='pending'),
               'landed_at_ticks', COALESCE(jsonb_agg(DISTINCT p.tick_seq), '[]'::jsonb),
               'top_reason', (SELECT p2.disposition_reason
                                FROM public.ottoq_external_proposals p2
                               WHERE p2.sim_run_id = p_sim_run_id
                                 AND p2.proposal->'agent_handoff'->>'chain_id' = v_row.chain_id
                                 AND p2.disposition_reason IS NOT NULL
                               GROUP BY p2.disposition_reason
                               ORDER BY count(*) DESC, p2.disposition_reason
                               LIMIT 1)),
             min(p.tick_seq) - v_row.tick_seq
        INTO v_kernel, v_lag
        FROM public.ottoq_external_proposals p
       WHERE p.sim_run_id = p_sim_run_id
         AND p.proposal->'agent_handoff'->>'chain_id' = v_row.chain_id;
    ELSE
      v_kernel := 'null'::jsonb; v_lag := NULL;
    END IF;

    --: THE SOLVER LEG, from the unified per-call ledger (0340). This was the other
    --: half of 0342's null: ottoq_proposer_fire_log holds ZERO rows for this run,
    --: because it is the forward_lex bridge's ledger while cuOpt records into
    --: cuopt_invocation_log. Reading the union means the review no longer depends
    --: on which solver happened to answer.
    SELECT jsonb_build_object(
             'calls', count(*),
             'providers', COALESCE(jsonb_agg(DISTINCT m.provider), '[]'::jsonb),
             'proposals_returned', COALESCE(sum(m.proposals_out), 0),
             'max_latency_ms', max(m.latency_ms),
             'outcomes', COALESCE(jsonb_object_agg(m.outcome, m.n), '{}'::jsonb))
      INTO v_solver
      FROM (SELECT provider, outcome, proposals_out, latency_ms,
                   count(*) OVER (PARTITION BY outcome) AS n
              FROM public.ottoq_model_call_ledger
             WHERE sim_run_id = p_sim_run_id
               AND (chain_id = v_row.chain_id
                    --: a cuOpt call carries no chain_id of its own, so fall back to
                    --: the beat window the chain actually spans, bounded to 3.
                    OR (chain_id IS NULL AND tick_seq BETWEEN v_row.tick_seq AND v_row.tick_seq + 3))
           ) m;

    --: THE FRAME SHAPE, which only the fire log carries: serviceable vs held is
    --: the G60 starvation signature and no other ledger records it.
    v_sub   := COALESCE((SELECT sum(COALESCE(f.n_submitted,0))
                           FROM public.ottoq_proposer_fire_log f
                          WHERE f.sim_run_id = p_sim_run_id
                            AND f.tick_seq BETWEEN v_row.tick_seq AND v_row.tick_seq + 3), 0);
    v_empty := COALESCE((SELECT count(*)::int
                           FROM public.ottoq_proposer_fire_log f
                          WHERE f.sim_run_id = p_sim_run_id
                            AND f.status = 'empty'
                            AND f.tick_seq BETWEEN v_row.tick_seq AND v_row.tick_seq + 3), 0);
    v_enacted := COALESCE((v_kernel->>'enacted')::int, 0);

    v_chains := v_chains || jsonb_build_array(jsonb_build_object(
      'chain_id',         v_row.chain_id,
      'issued_at_tick',   v_row.tick_seq,
      'linkage',          v_linkage,
      'lag_ticks',        v_lag,
      'solver_objective', v_row.solver_objective,
      'agent', jsonb_build_object(
        'model', v_row.model,
        'latency_ms', v_row.agent_latency_ms,
        'over_one_tick', COALESCE(v_row.agent_latency_ms, 0) > 30000,
        'l1_rules_evaluated', v_row.l1_rules),
      'policy_writes', jsonb_build_object(
        'applied',  COALESCE(v_row.applied,  'null'::jsonb),
        'queued',   COALESCE(v_row.queued,   'null'::jsonb),
        'rejected', COALESCE(v_row.rejected, 'null'::jsonb)),
      'solver', v_solver,
      'kernel', v_kernel,
      'frame', jsonb_build_object('submitted', v_sub, 'empty_fires', v_empty),
      'shield', COALESCE((
        SELECT jsonb_build_object(
                 'decisions', count(*),
                 'overridden', count(*) FILTER (WHERE d2.overridden),
                 'rule_codes', COALESCE(jsonb_agg(DISTINCT c.code)
                                 FILTER (WHERE c.code IS NOT NULL), '[]'::jsonb))
          FROM public.ottoq_decisions d2
          LEFT JOIN LATERAL unnest(COALESCE(d2.override_rule_codes, ARRAY[]::text[])) c(code) ON true
         WHERE d2.sim_run_id = p_sim_run_id
           AND d2.l2_engine <> 'nemotron'
           AND d2.tick_seq BETWEEN v_row.tick_seq AND v_row.tick_seq + 3),
        'null'::jsonb)
    ));

    --: NULL-SAFE, which 0342 was not. `SELECT expr INTO v` over zero rows sets v
    --: to NULL in plpgsql, so one tick without a fire row poisoned every later
    --: total AND disabled the 'solver_returned_nothing' verdict, because
    --: `NULL = 0` is never true. These can only be integers.
    v_tot_sub     := v_tot_sub + v_sub;
    v_tot_empty   := v_tot_empty + v_empty;
    v_tot_enacted := v_tot_enacted + v_enacted;
    IF COALESCE(v_row.agent_latency_ms,0) > 30000 THEN v_tot_slow := v_tot_slow + 1; END IF;
  END LOOP;

  --: Precedence order: the agent is told the FIRST thing that went wrong. 'enacted'
  --: is now checked against the chain-joined count, so a working loop reports
  --: proposals_enacted instead of kernel_refused_all.
  v_verdict := CASE
    WHEN NOT v_any         THEN 'no_chain_yet'
    WHEN v_tot_slow > 0    THEN 'agent_slower_than_tick'
    WHEN v_tot_empty > 0   THEN 'solver_saw_empty_frame'
    WHEN v_tot_enacted > 0 THEN 'proposals_enacted'
    WHEN v_tot_sub = 0     THEN 'solver_returned_nothing'
    ELSE                        'kernel_refused_all'
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
'0343 (replacing 0342''s). The return leg of the agent/solver/kernel loop. THE KERNEL LEG JOINS ON agent_handoff.chain_id, NOT ON TICK: net.http_post only queues, so a solver answers on a later beat, and 0342''s tick-equality join reported "enacted 0" for a chain whose seventeen proposals were all enacted (run ac402e07: agent at tick 1, proposals at ticks 2 and 3). 2,490 of 18,826 proposals carry that key across 477 chains. THE SOLVER LEG reads ottoq_model_call_ledger (0340) rather than ottoq_proposer_fire_log alone, because the fire log is the forward_lex bridge''s ledger and holds zero rows for a cuOpt-served run -- two proposers, two ledgers, and 0340 unifies them. The fire log is still read for the frame shape only it carries (submitted, empty fires -- the G60 signature). EVERY CHAIN DECLARES ITS `linkage` (chain_id or none) so an inferred association can never be mistaken for a recorded one, and `lag_ticks` reports how many beats after the analysis its first proposal landed -- 1 on ac402e07, which compounds G62. Accumulators are COALESCEd scalar subqueries: 0342 used SELECT INTO, which yields NULL over zero rows, poisoning every later total and silently disabling the solver_returned_nothing verdict.';

DO $assertions$
DECLARE v_run uuid; v_rev jsonb; v_c jsonb; v_keys int;
BEGIN
  -- A1. The unarmed board is untouched: still exactly twelve keys, review absent.
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1;
  IF public.ottoq_agent_board(v_run) ? 'review' THEN
    RAISE EXCEPTION '0343 A1a: an unarmed run publishes the review key';
  END IF;
  SELECT count(*) INTO v_keys FROM jsonb_object_keys(public.ottoq_agent_board(v_run));
  IF v_keys <> 12 THEN
    RAISE EXCEPTION '0343 A1b: an unarmed board has % keys, expected 12', v_keys;
  END IF;

  -- A2. THE REGRESSION THIS FILE EXISTS FOR, pinned to the exact run and numbers
  -- that exposed it. A chain whose proposals were all enacted must report them.
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE sim_run_id='ac402e07-81cc-4c95-bc2e-3b636b392920') THEN
    v_rev := public.ottoq_agent_review('ac402e07-81cc-4c95-bc2e-3b636b392920', 10);
    SELECT c INTO v_c FROM jsonb_array_elements(v_rev->'chains') c
     WHERE c->>'linkage' = 'chain_id' LIMIT 1;
    IF v_c IS NULL THEN
      RAISE EXCEPTION '0343 A2a: no chain on ac402e07 linked by chain_id';
    END IF;
    IF COALESCE((v_c->'kernel'->>'enacted')::int, 0) <> 17 THEN
      RAISE EXCEPTION '0343 A2b: the linked chain reports % enacted, expected 17',
        COALESCE(v_c->'kernel'->>'enacted', 'null');
    END IF;
    IF (v_c->>'lag_ticks')::int <> 1 THEN
      RAISE EXCEPTION '0343 A2c: lag_ticks is %, expected 1', v_c->>'lag_ticks';
    END IF;
    IF (v_rev->>'verdict') <> 'agent_slower_than_tick' THEN
      RAISE EXCEPTION '0343 A2d: verdict is %, expected agent_slower_than_tick (both calls exceeded the beat)',
        v_rev->>'verdict';
    END IF;
  END IF;

  -- A3. NULL-SAFE TOTALS, which is the second defect. Every total must be a
  -- number on every run that has an agent chain -- never NULL.
  FOR v_run IN SELECT DISTINCT d.sim_run_id FROM public.ottoq_decisions d
                WHERE d.l2_engine='nemotron' ORDER BY 1 LIMIT 25
  LOOP
    v_rev := public.ottoq_agent_review(v_run, 3);
    IF v_rev->'totals'->>'submitted' IS NULL
       OR v_rev->'totals'->>'enacted' IS NULL
       OR v_rev->'totals'->>'empty_frames' IS NULL
       OR v_rev->'totals'->>'agent_calls_over_one_tick' IS NULL THEN
      RAISE EXCEPTION '0343 A3: a total is NULL on run % -- the accumulator is poisoned again', v_run;
    END IF;
    IF v_rev->>'verdict' NOT IN ('no_chain_yet','agent_slower_than_tick',
          'solver_saw_empty_frame','solver_returned_nothing','kernel_refused_all',
          'proposals_enacted') THEN
      RAISE EXCEPTION '0343 A3b: unknown verdict % on run %', v_rev->>'verdict', v_run;
    END IF;
  END LOOP;

  -- A4. Every chain declares a linkage from the closed vocabulary. A missing or
  -- novel value would reach the agent as an unwritten instruction.
  FOR v_run IN SELECT DISTINCT d.sim_run_id FROM public.ottoq_decisions d
                WHERE d.l2_engine='nemotron' ORDER BY 1 LIMIT 25
  LOOP
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(
                 public.ottoq_agent_review(v_run, 3)->'chains') c
                WHERE COALESCE(c->>'linkage','') NOT IN ('chain_id','tick','none')) THEN
      RAISE EXCEPTION '0343 A4: a chain on run % declares an unknown linkage', v_run;
    END IF;
  END LOOP;

  -- A5. Still bounded.
  SELECT sim_run_id INTO v_run FROM public.ottoq_decisions
   WHERE l2_engine='nemotron' ORDER BY created_at DESC LIMIT 1;
  IF (public.ottoq_agent_review(v_run, 9999)->>'chains_examined')::int > 10 THEN
    RAISE EXCEPTION '0343 A5: p_chains did not clamp to 10';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0343_the_review_joined_on_the_tick_and_the_chain_crosses_ticks', false,
  'Replaces ottoq_agent_review. The kernel leg now joins on agent_handoff.chain_id rather than tick equality -- net.http_post queues, so a solver answers on a later beat, and the tick join reported "enacted 0" for a chain whose 17 proposals were all enacted. The solver leg reads the unified ottoq_model_call_ledger instead of the forward_lex-only fire log. Adds a declared linkage per chain and lag_ticks, and replaces SELECT INTO accumulators that yielded NULL over zero rows and silently disabled a verdict. One STABLE read-only function, reached only through a gated board key. Recertification not required.',
  now())
ON CONFLICT(name) DO NOTHING;
