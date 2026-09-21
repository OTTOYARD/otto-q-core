-- 0252  THE VERDICT THAT COULD ONLY EVER SAY ONE WORD NOW SAYS THREE TRUE THINGS,
--       AND THE AGENT'S OWN BOARD IS ONE OF THEM.
--
-- G73, closed by migration 0354 (applied 20260919224417). This file is the
-- after-measurement, run against the live run rather than asserted.
--
-- ══ 1. WHAT THE THREE READINGS NOW SAY, ALL AT ONCE, ALL TRUE ══════════════
--
-- On live run a51acc84 immediately after 0354:
--
--   verdict         kernel_refused_all           <- the window
--   verdict_scope   window                       <- says which scope it means
--   run_verdict     proposals_enacted            <- the whole run
--   run             chains_total 196
--                   chains_reaching_a_proposal 19
--                   chains_with_an_enacted_proposal 3
--                   proposals_stamped 27
--                   proposals_enacted 3
--                   last_proposal_tick 640
--
-- EVERY COUNT ABOVE IS A READING OF A MOMENT. The run is ticking: `proposals_
-- enacted` read 3 when this section was written and 4 four minutes later, and
-- `last_proposal_tick` moved from 339 to 640 during the investigation — cuOpt
-- resumed calling once charge stalls freed, which is 0250/0251's capacity finding
-- behaving as predicted. Q5 asserts the reported figure against a DIRECT count in
-- the same statement, so it stays true as the numbers move; do not quote the
-- literals here without re-running it.
--
-- Before 0354 the same run reported `solver_returned_nothing`, totals.enacted 0,
-- and nothing else. Two separate things changed it, and the second is the one
-- worth reading twice:
--
--   (a) THE SCOPE IS NAMED. `verdict` is explicitly a window statement and
--       `run_verdict` reports the run. The two DISAGREE here — window says the
--       kernel refused everything it saw, run says proposals were enacted — and
--       both are correct. That disagreement is the whole point: it is what a
--       single unqualified word made impossible to express.
--
--   (b) THE WINDOW WORD MOVED FROM "nothing came back" TO "the kernel refused
--       them", WHICH IS A DIFFERENT DIAGNOSIS. Not cosmetic. The old branch was
--         WHEN v_tot_sub = 0 THEN 'solver_returned_nothing'
--       with `v_tot_sub` summing `ottoq_proposer_fire_log.n_submitted` — a table
--       holding **112 rows, 112 of them declared_source='forward_lex', never one
--       cuOpt row in its life**, and 0 rows for this run. So on a cuOpt-served run
--       that test was unfalsifiable and `solver_returned_nothing` was the only
--       word the function could emit. 0354 adds `v_tot_landed`, counted from
--       `ottoq_external_proposals` where cuOpt's proposals actually land, and
--       requires BOTH ledgers to be silent before claiming silence. The window
--       immediately re-classified to `kernel_refused_all` — proposals DID arrive
--       and the kernel refused them, which is a real finding and was previously
--       reported as the solver having produced nothing.
--
-- ══ 2. AND IT REACHES THE AGENT, WHICH IS WHY forces_recert IS TRUE ════════
--
-- The review is not a report someone has to go looking for. Measured:
--
--   ottoq_agent_board(<run>)->'review'->>'run_verdict'       proposals_enacted
--   ottoq_agent_board(<run>)->'review'->>'verdict_scope'     window
--   ottoq_intelligence_stack(<run>, true)->'review'          both scopes present
--
-- `agent_review_enabled` is **1** on this run, so the review is concatenated into
-- `ottoq_agent_board` — the ONLY thing `ottoq-orchestrator-agent` reads before it
-- decides. Before 0354 the agent's own history told it the solver returned
-- nothing; it now tells it three of its chains were enacted. That is the return
-- leg of Chase's loop carrying a true signal instead of a false one, and it is
-- also exactly why this migration is classified `forces_recert: TRUE` rather than
-- argued down: it changes the agent's input.
--
-- `ottoq_intelligence_stack` carries it too, so the OTTO-Twin Intelligence panel
-- renders both scopes. The UI reads `review.verdict` as a free string and
-- humanises it — no string matching — so renaming the word broke nothing, and
-- every key 0342/0343 published is still present (0354 A5).
--
-- ══ 3. THREE DEFECTS OF MY OWN IN 0354, ALL CAUGHT BEFORE APPLYING ═════════
--
-- All three were invisible to `scripts/compile-check.py`, and all three would have
-- aborted the migration. Recorded because the pattern is now four sessions old:
-- **plpgsql plans lazily, so a DO block compiles clean and fails when it runs.**
--
--   1. `FROM public.ottoq_determinism_pair WHERE finished_at IS NULL` — THERE IS
--      NO SUCH TABLE. `ottoq_determinism_pair` is a FUNCTION; 0340 detects an
--      in-flight pair through `pg_stat_activity`. I copied 0340's intent without
--      reading its mechanism. Would have raised 42P01 at P1.
--   2. `pg_get_function_identity_arguments(p.oid) = 'uuid, integer'` returned
--      ZERO rows: on this server that function includes parameter NAMES —
--      `'p_sim_run_id uuid, p_chains integer'` — so the comparison could never be
--      true and P3 would have aborted on a function that was perfectly correct.
--      Now asserted on `proargtypes`, which carries no names and no formatting.
--   3. READ COMMITTED would have made A3/A4 flaky. They compare the function's
--      output against a direct count of the same rows in SEPARATE statements, and
--      a STABLE function re-snapshots per statement — on a live, ticking run a
--      proposal committing between them fails a correct assertion. 0354 sets
--      REPEATABLE READ so the comparison means what it says.
--
-- What caught 1 and 2 was the read-only precondition dry-run that
-- `scripts/APPLYING.md` mandates. That step is not ceremony.
--
-- ══ 4. AND ONE BOOKKEEPING DEFECT THE NEW SQL PATH INTRODUCES ══════════════
--
-- 0354 was applied through the Supabase **Management API** rather than the MCP
-- `apply_migration` tool, because the MCP server adds its own confirmation prompt
-- that no Claude Code setting removes and Chase asked three times for those to
-- stop. Same role, same database — but `apply_migration` ALSO writes the
-- `supabase_migrations.schema_migrations` row and a raw query does not. Measured
-- immediately after applying: the schema carried the change while the ledger's
-- newest row was still 0353's `20260919210336`.
--
-- That is the exact inverse of `db/migrations/UNFILED.md` (67 migrations applied
-- with no committed file) and the same family: **the schema and its ledger
-- disagreeing.** The row was written explicitly, which is what
-- `supabase migration repair --status applied` does. Anyone using this path must
-- write the ledger row too — it is what makes drift detectable at all. Recorded
-- in 0354's header as a standing instruction rather than as a one-off note.
--
-- `scripts/check-drift.sql` re-run after: **zero rows mention 0354.** The 71
-- in-database-not-in-repo, 42 name-mismatch and 3 routine-count findings are all
-- pre-existing (the repo's verdict was already DRIFT before this session), and
-- B2's one PENDING file is 0288, not this one.
--
-- ── WHAT IS STILL OPEN, so this is not read as more than it is ──────────────
--
-- G71 — a refusal for `stall_occupied` still does not separate contention from a
-- proposer reasoning over a stale frame. `kernel_refused_all` in section 1 is
-- therefore a statement about disposition, NOT about proposal quality.
-- G72 — nothing here survives the run: `ottoq_external_proposals` is class
-- `engine` and the demo-run purge takes it, so `run` is a live-run instrument.
-- G44 — `ottoq_rules` still declares thirty action_contexts with five ever called.
--
-- Nothing in this file changes engine state.
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  the three readings together. The DISAGREEMENT between verdict and
--     run_verdict is the deliverable, not a discrepancy.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
),
rev AS (SELECT public.ottoq_agent_review(r.sim_run_id, 3) AS j FROM r)
SELECT j->>'verdict'       AS window_verdict,
       j->>'verdict_scope' AS verdict_scope,
       j->>'run_verdict'   AS run_verdict,
       j->'run'            AS run_block,
       j->'totals'->>'landed' AS window_landed
  FROM rev;

-- Q2  the retirement, asserted: the bare word can never be a WINDOW verdict
--     again, and the window-qualified spelling is in the body.
SELECT (SELECT prosrc LIKE '%solver_returned_nothing_in_window%'
          FROM pg_proc WHERE proname = 'ottoq_agent_review')      AS window_word_present,
       (SELECT prosrc LIKE '%v_tot_landed%'
          FROM pg_proc WHERE proname = 'ottoq_agent_review')      AS landed_signal_present,
       (SELECT (public.ottoq_agent_review(sim_run_id, 3))->>'verdict'
          FROM public.ottoq_sim_runs
         WHERE status='running' ORDER BY started_at DESC LIMIT 1)
         <> 'solver_returned_nothing'                             AS bare_word_not_emitted;

-- Q3  the reason the old branch was unfalsifiable, kept as a measurement: the
--     fire log has never held a cuOpt row, and holds nothing for the live run.
SELECT count(*)                                                    AS fire_log_rows,
       count(*) FILTER (WHERE declared_source = 'forward_lex')      AS forward_lex_rows,
       count(*) FILTER (WHERE declared_source <> 'forward_lex')     AS non_forward_lex_rows,
       max(fired_at)                                               AS latest_fire,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
          JOIN public.ottoq_sim_runs s ON s.sim_run_id = f.sim_run_id
         WHERE s.status = 'running')                               AS rows_for_live_run
  FROM public.ottoq_proposer_fire_log;

-- Q4  section 2: it reaches the agent. This is the forces_recert justification
--     as a query rather than a paragraph.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
)
SELECT public.ottoq_policy_get(r.sim_run_id, 'agent_review_enabled', 0)   AS review_gate,
       (public.ottoq_agent_board(r.sim_run_id)) ? 'review'                AS board_carries_review,
       (public.ottoq_agent_board(r.sim_run_id))->'review'->>'run_verdict' AS board_run_verdict,
       (public.ottoq_intelligence_stack(r.sim_run_id, true))
         ->'review'->>'run_verdict'                                       AS ui_run_verdict
  FROM r;

-- Q5  section 1(a) as an assertion: run-level enactment must equal a direct
--     count, so the new block is checked against the rows rather than trusted.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
)
SELECT ((public.ottoq_agent_review(r.sim_run_id, 3))->'run'->>'proposals_enacted')::int
         AS reported_enacted,
       (SELECT count(*) FROM public.ottoq_external_proposals p
         WHERE p.sim_run_id = r.sim_run_id
           AND p.proposal->'agent_handoff' ? 'chain_id'
           AND p.status = 'enacted')::int AS direct_enacted,
       ((public.ottoq_agent_review(r.sim_run_id, 3))->'run'->>'proposals_enacted')::int
         = (SELECT count(*) FROM public.ottoq_external_proposals p
             WHERE p.sim_run_id = r.sim_run_id
               AND p.proposal->'agent_handoff' ? 'chain_id'
               AND p.status = 'enacted')::int AS agrees
  FROM r;

-- Q6  section 4: the ledger row exists, so the schema and its ledger agree.
SELECT version, name
  FROM supabase_migrations.schema_migrations
 WHERE name = 'the_review_judged_the_whole_run_from_three_chains_and_a_ledger_that_never_held_cuopt';
