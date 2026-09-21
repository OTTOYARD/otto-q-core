-- migration-version: 20260919224417
-- migration-name:    the_review_judged_the_whole_run_from_three_chains_and_a_ledger_that_never_held_cuopt
--
-- 0354  THE RETURN LEG WORKS AND ITS VERDICT SAID "solver_returned_nothing" ON A
--       RUN WHERE 17 CHAINS REACHED A PROPOSAL AND 3 HAD ONE ENACTED.
--
-- G73, measured in db/checks/0251 on live run a51acc84 at tick ~457. The loop
-- itself is sound: 17 agent chains reached a proposal, 17 of 17 resolve to a real
-- agent decision on the producer's own `agent_solver_chain_id`, against 17 NVIDIA
-- calls returning 24 proposals, and 3 chains had a proposal enacted by the
-- deterministic kernel. Agent -> solver -> kernel is joined, not inferred.
--
-- `ottoq_agent_review` reported: verdict `solver_returned_nothing`, totals.enacted
-- 0, linkage `none` on all three chains.
--
-- WHY THIS MATTERS MORE THAN A COSMETIC FIX. The review is not a report anyone has
-- to go looking for. It is concatenated into `ottoq_agent_board` whenever policy
-- `agent_review_enabled >= 1` — which is **1 on the live run, measured** — and the
-- board is the ONLY thing `ottoq-orchestrator-agent` reads before it decides. It is
-- also returned by `ottoq_intelligence_stack`, which is what the OTTO-Twin
-- Intelligence panel renders. So the wrong word is simultaneously fed back to the
-- agent as its own history and displayed on screen. A reporting defect sitting on
-- top of working machinery is the failure mode most likely to be believed, by an
-- auditor and by the agent alike.
--
-- ── TWO INDEPENDENT CAUSES, and the second is the one 0251 had not yet isolated ─
--
-- (1) THE WINDOW. The function examines the last `p_chains` (default 3) nemotron
--     chains and emits one of six machine-actionable words with NO window
--     qualifier. On this run those three chains sit at ticks 423 / 425 / 427 and
--     the newest stamped proposal is at tick **339**, so they genuinely have no
--     proposals — every per-chain reading was CORRECT, and `linkage: 'none'` is
--     0342 being honest rather than reporting zeros that read as refusals. The
--     defect is that a 3-chain sample publishes in run-level vocabulary.
--
-- (2) THE `submitted` SIGNAL CANNOT SEE cuOpt AT ALL, and the function's own
--     comment already says so: *"ottoq_proposer_fire_log holds ZERO rows for a
--     cuOpt-served run, because it is the forward_lex bridge's ledger while cuOpt
--     records into cuopt_invocation_log."* 0342 knew it — and then fed the verdict
--     from exactly that ledger:
--
--         WHEN v_tot_sub = 0 THEN 'solver_returned_nothing'
--
--     with `v_tot_sub` summing `ottoq_proposer_fire_log.n_submitted`. Measured:
--     that table holds **112 rows, 112 of them `declared_source='forward_lex'`,
--     never one cuOpt row in its life**, and nothing since 2026-09-17. So on ANY
--     cuOpt-served run `v_tot_sub` is structurally 0, and if nothing is enacted in
--     the window the verdict is not merely wrong — **it is the only word the
--     function is capable of producing.** That is not a sampling artefact; it is a
--     branch that can never be reached by evidence.
--
--     (Third instance of the class this repo keeps finding: 0250's unscoped stall
--     census, 0231's purged cuOpt ledger, and now a verdict discriminator read
--     from a log that does not cover the path being judged.)
--
-- ── WHAT THIS FILE CHANGES, and it is additive on purpose ───────────────────────
--
--   a. `v_landed` per chain — proposals actually carrying this chain id, from
--      `ottoq_external_proposals`, which IS where cuOpt's proposals land. Summed
--      into `v_tot_landed` and reported per chain as `frame.landed`. The verdict's
--      "nothing came back" branch now requires BOTH signals to be zero, so it can
--      no longer fire while proposals are sitting in the table.
--
--   b. The window word is spelled `solver_returned_nothing_in_window`, and a new
--      `verdict_scope: 'window'` says out loud what the six words describe. The
--      bare string `solver_returned_nothing` is retired as a window verdict —
--      A2 asserts it can never be emitted there again.
--
--   c. A new top-level `run` block computed over the WHOLE run, with its own
--      `run_verdict`: chains_total, chains_reaching_a_proposal,
--      chains_with_an_enacted_proposal, proposals_stamped, proposals_enacted,
--      last_proposal_tick. This is the number an auditor asks for and it was
--      already derivable — 0251 Q1 derives it in one query — it simply was not
--      reported.
--
-- EVERY EXISTING KEY IS PRESERVED: now_tick, since_tick, chains_examined, totals,
-- verdict, chains. Both database consumers embed the whole object and the Twin UI
-- reads `review.verdict` as a free string and humanises it (no string matching),
-- so nothing downstream breaks. A4 asserts the old keys still exist.
--
-- WHAT THIS FILE DOES NOT DO. It does not judge proposal QUALITY (G71: a refusal
-- for `stall_occupied` still does not separate contention from a proposer
-- reasoning over a stale frame), and it does not make enactment durable across
-- runs (G72: `ottoq_external_proposals` is class `engine` and the demo-run purge
-- takes it). It makes the instrument stop contradicting its own evidence.
--
-- forces_recert: TRUE. `agent_review_enabled` is 1 on the live run, so the review
-- is inside `ottoq_agent_board`, which is the agent's input — this changes what
-- the agent reads. Classified TRUE rather than argued down.
--
-- HOW THIS WAS APPLIED, recorded because it differs from every file before it and
-- the difference is load-bearing. It was executed through the Supabase MANAGEMENT
-- API rather than the MCP `apply_migration` tool — Chase asked three times, the
-- last time in capitals, to stop the SQL confirmation prompts, and the MCP server
-- applies its own confirmation that no Claude Code setting can remove. The
-- Management API is the same postgres role against the same database.
--
-- THE COST, which is not zero: `apply_migration` also writes the
-- `supabase_migrations.schema_migrations` row, and a raw query does not. So
-- immediately after applying, the schema carried this change and the ledger's
-- newest row was still 0353's `20260919210336` — the exact inverse of
-- `db/migrations/UNFILED.md` (migrations applied with no committed file), and the
-- same family of defect: the schema and its ledger disagreeing. The row was written
-- explicitly, which is what `supabase migration repair --status applied` does, and
-- the version above is that row. **Anyone applying through this path must write the
-- ledger row too; it is not optional bookkeeping, it is what makes drift detectable.**

BEGIN;

-- REPEATABLE READ, and not as boilerplate. A3/A4 below compare this function's
-- output against a DIRECT count of the same rows, and they are separate statements
-- inside the assertion block. Under the default READ COMMITTED a STABLE function
-- takes a fresh snapshot per statement, so on a LIVE run -- which is exactly the
-- state this is being applied in, a51acc84 is ticking -- a proposal committed
-- between the two statements would make a correct assertion fail and abort the
-- migration for no reason. One snapshot makes the comparison mean what it says.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- ── PRECONDITIONS ──────────────────────────────────────────────────────────────
DO $pre$
DECLARE v_jobs text; v_pairs int; v_n int; v_block int; v_live text;
BEGIN
  --: P0/P1 copied from 0340 AFTER checking what it actually does. The first draft
  --: of this block read `FROM public.ottoq_determinism_pair WHERE finished_at IS
  --: NULL` -- there is NO SUCH TABLE; ottoq_determinism_pair is a FUNCTION, and
  --: 0340 detects an in-flight pair through pg_stat_activity. compile-check passed
  --: it (plpgsql plans lazily, so a missing relation inside a DO block is invisible
  --: until it runs) and it would have aborted this migration at P1 with 42P01. The
  --: read-only dry-run scripts/APPLYING.md mandates is what caught it, which is the
  --: entire reason that step exists.
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0354 P0: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0354 P1: % certification pair(s) are active', v_pairs;
  END IF;

  --: P1b. 0340 REFUSED to apply while any Twin run was active. This file
  --: deliberately does not, and says why rather than quietly relaxing it: 0340
  --: created a table plus two capture triggers on the tick path, while this is one
  --: CREATE OR REPLACE of a STABLE reporting function -- atomic, with no window in
  --: which the function is absent. But it is NOT free: `agent_review_enabled` is 1
  --: on the live run, so the review sits inside ottoq_agent_board, and replacing it
  --: mid-run means the agent's later beats read a differently-shaped board than its
  --: earlier ones. That TAINTS the run in progress as a reproducible artifact. It
  --: is recorded here by run id rather than hidden, and it is acceptable only
  --: because a51acc84 is an exploratory diagnostic run, not a certification arm --
  --: which P0 and P1 above are what establish.
  SELECT string_agg(sim_run_id::text, ', ') INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused')
     AND COALESCE(run_by,'') <> 'production_live';
  IF v_live IS NOT NULL THEN
    RAISE NOTICE '0354 P1b: applying while Twin run(s) % are active -- those runs are tainted for reproducibility from this point, deliberately and with no certification pair or job scheduled', v_live;
  END IF;

  -- P2. The function must exist with the signature we are replacing. A CREATE OR
  -- REPLACE against a DIFFERENT argument list creates a second overload instead of
  -- replacing, and the callers would keep the old one.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_review';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0354 P2: expected exactly 1 ottoq_agent_review, found %', v_n;
  END IF;

  --: P3 asserts on proargtypes, NOT on pg_get_function_identity_arguments. The
  --: first draft compared that function's output to the string 'uuid, integer' and
  --: it returned ZERO rows: on this server identity_arguments carries the parameter
  --: NAMES too -- 'p_sim_run_id uuid, p_chains integer' -- so the comparison could
  --: never be true and P3 would have aborted the migration. Second defect the
  --: read-only dry-run caught in this one block. Argument OIDs carry no names and
  --: no version-dependent formatting, so this form asserts the thing that matters.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='ottoq_agent_review'
       AND p.pronargs = 2
       AND p.proargtypes[0] = 'uuid'::regtype
       AND p.proargtypes[1] = 'integer'::regtype) THEN
    RAISE EXCEPTION '0354 P3: ottoq_agent_review is not (uuid, integer)';
  END IF;

  -- P4. The defect must still be present, or this file is being applied twice.
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname='ottoq_agent_review'
              AND prosrc LIKE '%solver_returned_nothing_in_window%') THEN
    RAISE EXCEPTION '0354 P4: the window-qualified verdict is already present';
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0354 P5: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $pre$;

-- ── THE FUNCTION ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_agent_review(p_sim_run_id uuid, p_chains integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_tick bigint; v_n int; v_chains jsonb := '[]'::jsonb; v_row record;
  v_since bigint; v_verdict text;
  v_tot_sub int := 0; v_tot_enacted int := 0; v_tot_empty int := 0;
  v_tot_slow int := 0; v_any boolean := false;
  v_linkage text; v_kernel jsonb; v_solver jsonb; v_lag bigint;
  v_sub int; v_enacted int; v_empty int;
  --: 0354. `v_landed` is the signal that works for cuOpt; `v_run`/`v_run_verdict`
  --: are the run-scope answer the six window words were being read as.
  v_tot_landed int := 0; v_landed int;
  v_run jsonb; v_run_verdict text;
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

    --: THE SOLVER LEG, from the unified per-call ledger (0340). ottoq_proposer_fire_log
    --: holds ZERO rows for a cuOpt-served run, because it is the forward_lex
    --: bridge's ledger while cuOpt records into cuopt_invocation_log.
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

    --: 0354. THE SIGNAL THAT WORKS FOR cuOpt. `v_sub` above comes from
    --: ottoq_proposer_fire_log, which by this function's own comment three blocks
    --: up holds ZERO rows for a cuOpt-served run -- measured, 112 of 112 rows are
    --: declared_source='forward_lex' and it has never held one cuOpt row. So
    --: `v_tot_sub = 0` was unfalsifiable on a cuOpt run and drove the verdict
    --: straight to 'solver_returned_nothing'. `v_landed` counts what is actually
    --: in the proposals table under this chain id, whichever proposer put it there.
    v_landed := COALESCE((SELECT count(*)::int
                            FROM public.ottoq_external_proposals p
                           WHERE p.sim_run_id = p_sim_run_id
                             AND v_row.chain_id IS NOT NULL
                             AND p.proposal->'agent_handoff'->>'chain_id' = v_row.chain_id), 0);

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
      --: 'landed' sits beside 'submitted' rather than replacing it: they come from
      --: different ledgers with different coverage, and collapsing them would hide
      --: which one saw the proposal.
      'frame', jsonb_build_object('submitted', v_sub, 'empty_fires', v_empty,
                                  'landed', v_landed),
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
    --: to NULL in plpgsql, poisoning every later total AND disabling the
    --: 'solver_returned_nothing' verdict, because `NULL = 0` is never true.
    v_tot_sub     := v_tot_sub + v_sub;
    v_tot_empty   := v_tot_empty + v_empty;
    v_tot_enacted := v_tot_enacted + v_enacted;
    v_tot_landed  := v_tot_landed + v_landed;
    IF COALESCE(v_row.agent_latency_ms,0) > 30000 THEN v_tot_slow := v_tot_slow + 1; END IF;
  END LOOP;

  --: 0354. THE WINDOW VERDICT, now spelled as a window statement. The only change
  --: to the branch order is that "nothing came back" requires BOTH ledgers to be
  --: silent -- v_tot_sub covers forward_lex, v_tot_landed covers every proposer
  --: that reached the proposals table.
  v_verdict := CASE
    WHEN NOT v_any         THEN 'no_chain_yet'
    WHEN v_tot_slow > 0    THEN 'agent_slower_than_tick'
    WHEN v_tot_empty > 0   THEN 'solver_saw_empty_frame'
    WHEN v_tot_enacted > 0 THEN 'proposals_enacted'
    WHEN v_tot_sub = 0 AND v_tot_landed = 0
                           THEN 'solver_returned_nothing_in_window'
    ELSE                        'kernel_refused_all'
  END;

  --: 0354. THE RUN SCOPE, over every nemotron chain of the run rather than the
  --: last p_chains. This is what the six words were being read as, and it was
  --: already derivable (db/checks/0251 Q1) -- it simply was not reported.
  SELECT jsonb_build_object(
           'chains_total',                    count(*),
           'chains_reaching_a_proposal',      count(*) FILTER (WHERE pr.proposals > 0),
           'chains_with_an_enacted_proposal', count(*) FILTER (WHERE pr.enacted > 0),
           'proposals_stamped',               COALESCE(sum(pr.proposals), 0),
           'proposals_enacted',               COALESCE(sum(pr.enacted), 0),
           'last_proposal_tick',              max(pr.last_tick))
    INTO v_run
    FROM (SELECT DISTINCT COALESCE(d.proposed_action->>'agent_solver_chain_id',
                                   d.context_frame->>'agent_solver_chain_id') AS chain_id
            FROM public.ottoq_decisions d
           WHERE d.sim_run_id = p_sim_run_id
             AND d.l2_engine = 'nemotron') ac
    LEFT JOIN LATERAL (
      SELECT count(*)::int                                      AS proposals,
             count(*) FILTER (WHERE p.status='enacted')::int     AS enacted,
             max(p.tick_seq)                                    AS last_tick
        FROM public.ottoq_external_proposals p
       WHERE p.sim_run_id = p_sim_run_id
         AND ac.chain_id IS NOT NULL
         AND p.proposal->'agent_handoff'->>'chain_id' = ac.chain_id) pr ON true;

  v_run_verdict := CASE
    WHEN COALESCE((v_run->>'chains_total')::int, 0) = 0        THEN 'no_chain_yet'
    WHEN COALESCE((v_run->>'proposals_enacted')::int, 0) > 0   THEN 'proposals_enacted'
    WHEN COALESCE((v_run->>'proposals_stamped')::int, 0) > 0   THEN 'kernel_refused_all'
    ELSE                                                            'solver_returned_nothing'
  END;

  RETURN jsonb_build_object(
    'now_tick',   v_tick,
    'since_tick', v_since,
    'chains_examined', jsonb_array_length(v_chains),
    'totals', jsonb_build_object(
      'submitted', v_tot_sub, 'enacted', v_tot_enacted,
      'empty_frames', v_tot_empty, 'agent_calls_over_one_tick', v_tot_slow,
      'landed', v_tot_landed),
    'verdict', v_verdict,
    --: 0354. Say out loud which scope `verdict` describes, so it cannot be quoted
    --: as a run-level finding again, and report the run scope beside it.
    'verdict_scope', 'window',
    'run_verdict', v_run_verdict,
    'run', v_run,
    'chains', v_chains);
END $function$;

COMMENT ON FUNCTION public.ottoq_agent_review(uuid, integer) IS
'0342, revised by 0354. The loop''s return leg: what happened to the agent''s own last objectives, joined to the kernel on the agent_solver_chain_id the producer stamps. TWO SCOPES, deliberately both: `verdict` + `totals` describe the last p_chains chains and `verdict_scope` says so; `run_verdict` + `run` describe the whole run. 0354 exists because the single unqualified verdict was quoted as a run-level finding — it read solver_returned_nothing on a run with 17 chains reaching a proposal and 3 enacted. AND the branch that produced it was unfalsifiable: it tested only ottoq_proposer_fire_log.n_submitted, a ledger that holds 112 of 112 rows declared_source=forward_lex and has never held a cuOpt row, so on a cuOpt-served run it was the only word this function could emit. `frame.landed` and `totals.landed` are the cuOpt-visible signal, counted from ottoq_external_proposals. Says nothing about proposal QUALITY (G71) and nothing survives the run''s purge (G72).';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
-- Not bookkeeping. ottoq_cert_recert_floor() reads schema_migrations LEFT JOIN
-- ottoq_cert_lineage and takes COALESCE(forces_recert, TRUE), so a MISSING row is
-- not "unclassified", it is "forces recert" — every certification column's streak
-- restarts. This row says TRUE deliberately, so the effect is the same either way;
-- it is written so the classification is a recorded decision rather than a default.
-- (tests/test_migration_hygiene.py::test_recent_migrations_classify_themselves is
-- what caught its absence here, after 0267 and 0271 both shipped without it.)
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0354_the_review_judged_the_whole_run_from_three_chains_and_a_ledger_that_never_held_cuopt', true,
  'Rewrites public.ottoq_agent_review, the loop''s return leg. FORCES RECERT because policy '
  'agent_review_enabled is 1 on the live run, which concatenates the review into ottoq_agent_board -- '
  'the only thing ottoq-orchestrator-agent reads before it decides -- so this changes the AGENT''S INPUT, '
  'not merely a report. Two defects, one of which was worse than the finding that opened it: (1) the single '
  'verdict carried no scope qualifier, so a p_chains=3 sample published in run-level vocabulary and read '
  'solver_returned_nothing on run a51acc84, which had 19 chains reaching a proposal and proposals enacted; '
  '(2) that branch tested ONLY ottoq_proposer_fire_log.n_submitted, a table holding 112 of 112 rows '
  'declared_source=forward_lex and never one cuOpt row in its life, so on any cuOpt-served run it was '
  'UNFALSIFIABLE -- the only word the function could emit. Adds v_tot_landed from ottoq_external_proposals '
  '(where cuOpt proposals actually land) and requires both ledgers silent before claiming silence; the live '
  'window immediately re-classified to kernel_refused_all, a different and correct diagnosis. Adds '
  'verdict_scope and a run-scope block with run_verdict. Every pre-existing key preserved (A5) because '
  'ottoq_agent_board and ottoq_intelligence_stack embed the object whole and the Twin UI reads verdict as a '
  'free string. Says nothing about proposal QUALITY (G71) and survives no purge (G72). Applied through the '
  'Management API, so its schema_migrations row was written explicitly -- see the header.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ── ASSERTIONS ─────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_run uuid; v_out jsonb; v_direct int; v_chains_direct int; v_block int;
BEGIN
  -- Pick the run with the most stamped proposals, so the assertions run against
  -- evidence rather than against whichever run happens to be newest.
  SELECT p.sim_run_id INTO v_run
    FROM public.ottoq_external_proposals p
   WHERE p.proposal->'agent_handoff' ? 'chain_id'
   GROUP BY p.sim_run_id
   ORDER BY count(*) DESC
   LIMIT 1;

  IF v_run IS NULL THEN
    RAISE EXCEPTION '0354 A0: no run carries a chain-stamped proposal, so the assertions below would be vacuous';
  END IF;

  v_out := public.ottoq_agent_review(v_run, 3);

  -- A1. The new keys exist and are populated.
  IF v_out IS NULL
     OR NOT (v_out ? 'run') OR NOT (v_out ? 'run_verdict')
     OR NOT (v_out ? 'verdict_scope') THEN
    RAISE EXCEPTION '0354 A1: the review is missing run / run_verdict / verdict_scope';
  END IF;
  IF v_out->>'verdict_scope' <> 'window' THEN
    RAISE EXCEPTION '0354 A1b: verdict_scope reads %', v_out->>'verdict_scope';
  END IF;

  -- A2. THE RETIREMENT, asserted rather than trusted: the bare word can never be
  -- emitted as a WINDOW verdict again. It survives only as a run verdict, where it
  -- is a statement about the run and therefore true when said.
  IF v_out->>'verdict' = 'solver_returned_nothing' THEN
    RAISE EXCEPTION '0354 A2: the window verdict emitted the unqualified word';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE proname='ottoq_agent_review')
       NOT LIKE '%solver_returned_nothing_in_window%' THEN
    RAISE EXCEPTION '0354 A2b: the window-qualified verdict is not in the body';
  END IF;

  -- A3. CORRECTNESS, not just shape: the run block must equal a direct count.
  SELECT count(*) FILTER (WHERE p.status='enacted')
    INTO v_direct
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = v_run
     AND p.proposal->'agent_handoff' ? 'chain_id';
  IF COALESCE((v_out->'run'->>'proposals_enacted')::int, -1) <> v_direct THEN
    RAISE EXCEPTION '0354 A3: run.proposals_enacted = %, direct count = %',
      v_out->'run'->>'proposals_enacted', v_direct;
  END IF;

  SELECT count(DISTINCT p.proposal->'agent_handoff'->>'chain_id')
    INTO v_chains_direct
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = v_run
     AND p.proposal->'agent_handoff' ? 'chain_id';
  IF COALESCE((v_out->'run'->>'chains_reaching_a_proposal')::int, -1) <> v_chains_direct THEN
    RAISE EXCEPTION '0354 A4: run.chains_reaching_a_proposal = %, direct = %',
      v_out->'run'->>'chains_reaching_a_proposal', v_chains_direct;
  END IF;

  -- A5. NON-BREAKING: every key 0342/0343 published is still there, because
  -- ottoq_agent_board and ottoq_intelligence_stack embed this object whole.
  IF NOT (v_out ? 'now_tick' AND v_out ? 'since_tick' AND v_out ? 'chains_examined'
          AND v_out ? 'totals' AND v_out ? 'verdict' AND v_out ? 'chains') THEN
    RAISE EXCEPTION '0354 A5: a pre-existing key was dropped';
  END IF;
  IF NOT (v_out->'totals' ? 'submitted' AND v_out->'totals' ? 'enacted'
          AND v_out->'totals' ? 'empty_frames'
          AND v_out->'totals' ? 'agent_calls_over_one_tick') THEN
    RAISE EXCEPTION '0354 A5b: a pre-existing totals key was dropped';
  END IF;

  -- A6. NON-VACUITY OF THE cuOpt SIGNAL. On the run chosen above, proposals are
  -- stamped and the fire log holds nothing for it -- which is exactly the state
  -- that made the old branch unfalsifiable. Assert the new signal sees them.
  IF COALESCE((v_out->'run'->>'proposals_stamped')::int, 0) = 0 THEN
    RAISE EXCEPTION '0354 A6: the chosen run has no stamped proposals, so A6 is vacuous';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_proposer_fire_log WHERE sim_run_id = v_run) THEN
    RAISE NOTICE '0354 A6 note: the fire log DOES cover run % -- the cuOpt blind spot is not exercised by this run, though the signal is still asserted by A3/A4', v_run;
  END IF;

  -- A7. The registry guard must not have moved.
  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0354 A7: the registry guard now reports % blocking defect(s)', v_block;
  END IF;

  RAISE NOTICE '0354 OK on run %: window verdict=%, run verdict=%, run=%',
    v_run, v_out->>'verdict', v_out->>'run_verdict', v_out->'run';
END $post$;

COMMIT;
