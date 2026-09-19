-- migration-version: PENDING
-- migration-name:    every_external_model_call_gets_a_ledger_that_outlives_its_run
--
-- 0340  THE THREE INTELLIGENCE PATHS KEEP NO DURABLE PER-CALL RECORD, AND THE
--       ONE LEDGER THAT EXISTS IS REGISTERED TO BE DELETED.
--
-- Three measurements, taken 2026-09-19 against this engine:
--
--   1. cuOpt IS NOT DARK ANY MORE, and CLAUDE.md still says it is.
--      cuopt_invocation_log now holds 27,340 rows of which 515 carry an
--      http_status -- a real status from optimize.api.nvidia.com, since
--      ottoq-cuopt-propose sets that column only from `nvidiaStatuses`. 505 of
--      them answered with source='cuopt' for 2,714 proposals, 8 answered
--      `solved_but_zero_proposals`. The most recent call is 2026-09-17
--      12:42:07 UTC. CLAUDE.md rule 6's quotable sentence -- "sixteen calls ...
--      the last on 2026-08-30" -- is off by 499 calls and 18 days, in the
--      direction that understates us. It was true when written.
--
--   2. THAT EVIDENCE IS REGISTERED TO DIE. cuopt_invocation_log.sim_run_id is
--      class='engine' in ottoq_run_scope_registry ("must not outlive its run"),
--      and ottoq_purge_prior_runs deletes every engine table by registry lookup.
--      ottoq_start_demo_run calls that purge. So the next Twin Start deletes the
--      515-call record this file exists to preserve. 0327 corrected the table's
--      COMMENT to admit this; nothing changed the fact. Meanwhile
--      ottoq_proposer_fire_log was reclassified `evidence` by 0260 for exactly
--      this reason -- the precedent is set and the cuOpt ledger never got it.
--
--   3. NEMOTRON HAS NO PER-CALL LEDGER AT ALL. It is the only intelligence
--      source that has ever changed what this engine did, 729 decision rows in
--      the last four days, and its only trace is a row in ottoq_decisions --
--      which is itself class='engine' and purged. Measured on the way past: its
--      last call took 40,776 ms against a 30-second tick, and 721
--      `deterministic_fallback` rows sit beside those 729, so roughly half of
--      all agent calls are not answered in time.
--
-- WHAT THIS FILE BUILDS. One append-only ledger, public.ottoq_model_call_ledger,
-- carrying one row per call to an external model or solver service, whoever made
-- it: NVIDIA cuOpt, NVIDIA Nemotron, the CP-SAT service, the Anthropic advisor.
-- It is registered class='evidence' and it deliberately has NO foreign key to
-- ottoq_sim_runs.
--
-- THE MISSING FK IS THE DESIGN, NOT AN OMISSION, and the registry's own guard
-- says so: ottoq_check_run_scope_registry check (b) requires an FK for
-- class='engine' and class='stamp' ONLY. An evidence row must outlive the run
-- row it names, so an enforcing FK would either block the purge or, as CASCADE,
-- silently erase the history -- which check (c) already forbids. The uuid is
-- kept as a durable historical key so "no number ships without a run ID"
-- survives the run's deletion. This is the ordinary shape of an audit ledger.
--
-- It is filled two ways, and never by asking the edge functions to remember:
--   * AFTER INSERT triggers on cuopt_invocation_log (http_status NOT NULL only,
--     so gate refusals stay out) and on ottoq_decisions (nemotron, forward_lex,
--     llm_advisor -- NOT cuopt, whose call the first trigger already has; a
--     decision row is the ENACTMENT of a proposal, and counting both would make
--     one call two rows, which is the exact confusion this file exists to end).
--     Both trigger functions swallow every error and return
--     NEW, because ottoq_decisions is written from the tick path and APPLYING.md
--     is unambiguous: a failure must never abort decide_tick.
--   * a one-time backfill of the 515 surviving NVIDIA calls and every surviving
--     Nemotron decision, marked source_kind='backfill' so a reader can always
--     tell a reconstructed row from one written as it happened.
--
-- NO CHAIN-OF-THOUGHT IS STORED. 0335 drew that line and this file keeps it:
-- `rationale_present` is a boolean, and no rationale text is copied.
--
-- NO CHECK CONSTRAINT ON provider/role/outcome, on purpose. An evidence table
-- records what happened, not what was predicted; a CHECK that rejected a
-- provider nobody had thought of would lose exactly the call most worth having.
-- The vocabulary lives in the COMMENT, where being wrong is cheap.
--
-- AND ONE THING THIS FILE DELIBERATELY DOES NOT DO, because trying it failed an
-- assertion and the failure was instructive. A first draft also dropped
-- ottoq_proposer_fire_log's ON DELETE NO ACTION FK to ottoq_sim_runs, on the
-- reasoning that the table is class='evidence' and check (b) asks engine/stamp
-- only. A3b refused the whole migration: the guard reported a blocking defect
-- the moment the FK went.
--
-- The reason is a real seam in the guard, filed as G61 and left for its own file.
-- THE REGISTRY IS PER-COLUMN; CHECK (b) IS PER-TABLE. ottoq_proposer_fire_log
-- has TWO registry rows -- sim_run_id class='evidence' and tick_seq
-- class='stamp' -- and check (b) reads "this table has some FK to
-- ottoq_sim_runs", not "this column does". So the stamp row demands the very FK
-- the evidence row's purpose requires it not to have, and 0267 added it to
-- satisfy exactly that demand. A mixed-class table is therefore required to
-- block the purge it is registered to survive. Measured: 112 fire-log rows name
-- runs in the purge's doomed set.
--
-- That is not this file's concern to settle, and guessing at it is how a guard
-- gets weakened. THE NEW LEDGER SIDESTEPS IT BY CONSTRUCTION: it registers
-- exactly one column, sim_run_id, as evidence. Its tick_seq is NOT registered
-- and does not need to be -- check (a) watches only sim_run_id, run_id,
-- owning_sim_run_id and source_run_id -- so no stamp row exists to demand an FK.
--
-- forces_recert: FALSE, and this is executed rather than argued (A6). Nothing
-- on the decide path reads the new table, no existing function body changes, and
-- the triggers only write. The fourteen certification atoms digest the frames,
-- commands, decisions, events, bookings, energy, proposals, deferrals,
-- calibration, rules, recalls, SDRs, tick count and end state -- none of which
-- this table appears in.

DO $preflight$
DECLARE v_jobs text; v_pairs int; v_runs int; v_block int; v_http int; v_nem int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0340 P-: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN RAISE EXCEPTION '0340 P-: % certification pair(s) are active', v_pairs; END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_runs > 0 THEN RAISE EXCEPTION '0340 P-: % Twin run(s) are active', v_runs; END IF;

  -- P1. The table must not already exist under any shape.
  IF to_regclass('public.ottoq_model_call_ledger') IS NOT NULL THEN
    RAISE EXCEPTION '0340 P1: ottoq_model_call_ledger already exists';
  END IF;

  -- P2. THE REGISTRY MUST BE CLEAN BEFORE THIS FILE TOUCHES IT. If the guard is
  -- already reporting a blocking defect, a failure after this migration could
  -- not be attributed to it.
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry()
   WHERE severity='block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0340 P2: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;

  -- P4. The backfill sources must be non-empty, or the assertions below would
  -- pass trivially on a ledger that copied nothing.
  SELECT count(*) INTO v_http FROM public.cuopt_invocation_log WHERE http_status IS NOT NULL;
  SELECT count(*) INTO v_nem  FROM public.ottoq_decisions WHERE l2_engine='nemotron';
  IF v_http = 0 OR v_nem = 0 THEN
    RAISE EXCEPTION '0340 P4: backfill sources are empty (http=%, nemotron=%)', v_http, v_nem;
  END IF;
  RAISE NOTICE '0340: backfilling % NVIDIA cuOpt calls and % Nemotron decisions', v_http, v_nem;
END $preflight$;

-- ── 1. the ledger ────────────────────────────────────────────────────────────
CREATE TABLE public.ottoq_model_call_ledger (
  call_id           bigserial PRIMARY KEY,
  --: Durable historical key. NO FOREIGN KEY, deliberately -- see the header and
  --: ottoq_check_run_scope_registry check (b). The run row this names may be
  --: purged; this row must not be.
  sim_run_id        uuid,
  depot_id          uuid,
  tick_seq          bigint,
  sim_clock         timestamptz,
  --: agent_solver_chain_id: joins one analysis -> solve -> disposal chain (0331).
  chain_id          text,
  provider          text NOT NULL,
  role              text NOT NULL,
  model             text,
  endpoint          text,
  --: The PROVIDER's status. NULL means the provider was never reached.
  http_status       integer,
  latency_ms        integer,
  outcome           text NOT NULL,
  proposals_out     integer,
  --: Whether the provider returned a rationale. The TEXT IS NEVER COPIED (0335).
  rationale_present boolean,
  detail            jsonb NOT NULL DEFAULT '{}'::jsonb,
  called_at         timestamptz NOT NULL DEFAULT now(),
  --: 'live' = written by the trigger as it happened; 'backfill' = reconstructed
  --: by 0340 from a run-scoped table. A reader must be able to tell.
  source_kind       text NOT NULL DEFAULT 'live'
);

COMMENT ON TABLE public.ottoq_model_call_ledger IS
'0340. One row per CALL to an external model or solver service, and the only such record that outlives its run. Grain: one attempted call, not one row of working data -- the distinction cuopt_invocation_log did not make, where 27,340 rows carried 515 actual NVIDIA calls. Registered class=evidence with NO foreign key to ottoq_sim_runs: an evidence row must survive ottoq_purge_prior_runs deleting the run it names, and ottoq_check_run_scope_registry check (b) requires an FK for class engine/stamp only. sim_run_id is kept as a durable historical key so a call stays attributable after its run row is gone. VOCABULARY, in the comment rather than a CHECK constraint so an unforeseen provider is recorded rather than rejected: provider in (nvidia_cuopt, nvidia_nemotron, cpsat_service, anthropic_advisor, local_fallback); role in (agent, proposer); outcome in (answered, abstained, fallback, error, refused). http_status is the PROVIDER status and NULL means the provider was never reached. No chain-of-thought is stored -- rationale_present is a boolean and no rationale text is ever copied (the 0335 boundary).';

CREATE INDEX ottoq_model_call_ledger_provider_at_idx
  ON public.ottoq_model_call_ledger (provider, called_at DESC);
CREATE INDEX ottoq_model_call_ledger_run_idx
  ON public.ottoq_model_call_ledger (sim_run_id) WHERE sim_run_id IS NOT NULL;
CREATE INDEX ottoq_model_call_ledger_chain_idx
  ON public.ottoq_model_call_ledger (chain_id) WHERE chain_id IS NOT NULL;

-- ── 2. append-only, because a ledger that can be edited proves nothing ───────
CREATE OR REPLACE FUNCTION public.ottoq_model_call_ledger_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.model_ledger_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_model_call_ledger is append-only: % refused. Set ottoq.model_ledger_unlock=on in the session to override, and say why in a migration.',
    TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_model_call_ledger_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_model_call_ledger
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_model_call_ledger_append_only();

-- ── 3. the writer ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_log_model_call(
  p_provider   text,
  p_role       text,
  p_outcome    text,
  p_sim_run_id uuid    DEFAULT NULL,
  p_depot_id   uuid    DEFAULT NULL,
  p_tick_seq   bigint  DEFAULT NULL,
  p_sim_clock  timestamptz DEFAULT NULL,
  p_chain_id   text    DEFAULT NULL,
  p_model      text    DEFAULT NULL,
  p_endpoint   text    DEFAULT NULL,
  p_http_status integer DEFAULT NULL,
  p_latency_ms integer DEFAULT NULL,
  p_proposals_out integer DEFAULT NULL,
  p_rationale_present boolean DEFAULT NULL,
  p_detail     jsonb   DEFAULT '{}'::jsonb,
  p_source_kind text   DEFAULT 'live'
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.ottoq_model_call_ledger
    (sim_run_id, depot_id, tick_seq, sim_clock, chain_id, provider, role, model,
     endpoint, http_status, latency_ms, outcome, proposals_out, rationale_present,
     detail, source_kind)
  VALUES
    (p_sim_run_id, p_depot_id, p_tick_seq, p_sim_clock, p_chain_id,
     p_provider, p_role, p_model, p_endpoint, p_http_status, p_latency_ms,
     p_outcome, p_proposals_out, p_rationale_present,
     COALESCE(p_detail,'{}'::jsonb), COALESCE(p_source_kind,'live'))
  RETURNING call_id INTO v_id;
  RETURN v_id;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_log_model_call(text,text,text,uuid,uuid,bigint,timestamptz,text,text,text,integer,integer,integer,boolean,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_log_model_call(text,text,text,uuid,uuid,bigint,timestamptz,text,text,text,integer,integer,integer,boolean,jsonb,text) TO service_role;

-- ── 4. capture at the source, so no edge function has to remember ────────────
-- BOTH trigger functions swallow EVERYTHING. ottoq_decisions is written from the
-- tick path; APPLYING.md: a failure must never abort decide_tick. A lost ledger
-- row is a bad day. A rolled-back tick is a silent zero-assignment run.
CREATE OR REPLACE FUNCTION public.ottoq_capture_cuopt_model_call()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
BEGIN
  BEGIN
    PERFORM public.ottoq_log_model_call(
      p_provider   => 'nvidia_cuopt',
      p_role       => 'proposer',
      p_outcome    => CASE
                        WHEN NEW.detail->>'source' = 'cuopt'
                             AND COALESCE(NEW.proposals_out,0) > 0 THEN 'answered'
                        WHEN NEW.detail->>'source' = 'cuopt' THEN 'abstained'
                        WHEN NEW.abstained_reason IS NOT NULL THEN 'fallback'
                        ELSE 'answered' END,
      p_sim_run_id => NEW.sim_run_id,
      p_tick_seq   => NEW.tick_seq::bigint,
      p_sim_clock  => NEW.sim_clock,
      p_model      => NEW.detail->>'source',
      p_endpoint   => 'optimize.api.nvidia.com/v1/nvidia/cuopt',
      p_http_status => NEW.http_status,
      p_latency_ms => NEW.latency_ms,
      p_proposals_out => NEW.proposals_out,
      p_detail     => jsonb_build_object(
                        'stage', NEW.stage,
                        'source_note', NEW.source_note,
                        'abstained_reason', NEW.abstained_reason,
                        'candidates_in', NEW.candidates_in,
                        'free_stalls_in', NEW.free_stalls_in,
                        'enroute_source', NEW.detail->>'enroute_source',
                        'nvidia_statuses', NEW.detail->'nvidia_statuses'),
      p_source_kind => 'live');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_capture_cuopt_model_call: % (invocation=%)', SQLERRM, NEW.invocation_id;
  END;
  RETURN NEW;
END $fn$;

CREATE TRIGGER ottoq_capture_cuopt_model_call_trg
  AFTER INSERT ON public.cuopt_invocation_log
  FOR EACH ROW WHEN (NEW.http_status IS NOT NULL)
  EXECUTE FUNCTION public.ottoq_capture_cuopt_model_call();

CREATE OR REPLACE FUNCTION public.ottoq_capture_decision_model_call()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
BEGIN
  BEGIN
    PERFORM public.ottoq_log_model_call(
      p_provider   => CASE NEW.l2_engine
                        WHEN 'nemotron'    THEN 'nvidia_nemotron'
                        WHEN 'forward_lex' THEN 'cpsat_service'
                        WHEN 'llm_advisor' THEN 'anthropic_advisor'
                        ELSE NEW.l2_engine END,
      p_role       => CASE WHEN NEW.l2_engine = 'nemotron' THEN 'agent' ELSE 'proposer' END,
      p_outcome    => CASE
                        WHEN NEW.outcome_status IS NOT NULL THEN NEW.outcome_status
                        WHEN NEW.overridden THEN 'refused'
                        ELSE 'answered' END,
      p_sim_run_id => NEW.sim_run_id,
      p_depot_id   => NEW.depot_id,
      p_tick_seq   => NEW.tick_seq,
      p_sim_clock  => NEW.sim_clock,
      p_chain_id   => COALESCE(NEW.proposed_action->>'agent_solver_chain_id',
                               NEW.context_frame->>'agent_solver_chain_id'),
      p_model      => NEW.proposed_action->>'model',
      p_latency_ms => NEW.total_latency_ms,
      --: rationale_present, NOT the rationale. The 0335 boundary.
      p_rationale_present => (NEW.enacted_action ? 'rationale'),
      p_detail     => jsonb_build_object(
                        'l2_engine', NEW.l2_engine,
                        'action_context', NEW.action_context,
                        'decision_id', NEW.decision_id,
                        'overridden', NEW.overridden,
                        'override_rule_codes', NEW.override_rule_codes,
                        'solver', NEW.proposed_action->>'solver',
                        'solver_handoff', NEW.enacted_action->'solver_handoff',
                        --: THE SHIELD GAP, MADE COUNTABLE. Measured 2026-09-19:
                        --: 729 of 729 nemotron rows carried an empty
                        --: rule_results. A reader can now quantify that without
                        --: ottoq_decisions, which the purge deletes.
                        'l1_rules_evaluated',
                          jsonb_array_length(COALESCE(NEW.rule_results,'[]'::jsonb))),
      p_source_kind => 'live');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_capture_decision_model_call: % (decision=%)', SQLERRM, NEW.decision_id;
  END;
  RETURN NEW;
END $fn$;

CREATE TRIGGER ottoq_capture_decision_model_call_trg
  AFTER INSERT ON public.ottoq_decisions
  --: 'cuopt' IS DELIBERATELY ABSENT. The cuOpt CALL is captured at
  --: cuopt_invocation_log by the trigger above; an ottoq_decisions row with
  --: l2_engine='cuopt' is the ENACTMENT of a proposal that call already
  --: produced. Logging both would double-count every cuOpt call, and the
  --: ledger's whole purpose is that a row means one call.
  FOR EACH ROW WHEN (NEW.l2_engine IN ('nemotron','forward_lex','llm_advisor'))
  EXECUTE FUNCTION public.ottoq_capture_decision_model_call();

-- ── 5. register it, so the purge guard knows what it is ──────────────────────
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_model_call_ledger', 'sim_run_id', 'evidence',
        '0340: the per-call ledger for every external model and solver call. Evidence, not engine: CLAUDE.md rule 6 quantifies every cuOpt, Nemotron and CP-SAT sentence from it, so it must survive its run. Deliberately carries NO foreign key to ottoq_sim_runs -- check (b) asks for one from engine/stamp only, and an enforcing FK on an evidence table can only block ottoq_purge_prior_runs step (5) or, as CASCADE, erase the history check (c) forbids erasing.');

-- ── 7. backfill what is still alive ──────────────────────────────────────────
INSERT INTO public.ottoq_model_call_ledger
  (sim_run_id, tick_seq, sim_clock, provider, role, model, endpoint,
   http_status, latency_ms, outcome, proposals_out, detail, called_at, source_kind)
SELECT l.sim_run_id, l.tick_seq::bigint, l.sim_clock,
       'nvidia_cuopt', 'proposer', l.detail->>'source',
       'optimize.api.nvidia.com/v1/nvidia/cuopt',
       l.http_status, l.latency_ms,
       CASE WHEN l.detail->>'source' = 'cuopt' AND COALESCE(l.proposals_out,0) > 0 THEN 'answered'
            WHEN l.detail->>'source' = 'cuopt' THEN 'abstained'
            WHEN l.abstained_reason IS NOT NULL THEN 'fallback'
            ELSE 'answered' END,
       l.proposals_out,
       jsonb_build_object('stage', l.stage, 'source_note', l.source_note,
                          'abstained_reason', l.abstained_reason,
                          'candidates_in', l.candidates_in,
                          'free_stalls_in', l.free_stalls_in,
                          'backfilled_from', 'cuopt_invocation_log',
                          'invocation_id', l.invocation_id),
       l.called_at, 'backfill'
  FROM public.cuopt_invocation_log l
 WHERE l.http_status IS NOT NULL;

INSERT INTO public.ottoq_model_call_ledger
  (sim_run_id, depot_id, tick_seq, sim_clock, chain_id, provider, role, model,
   latency_ms, outcome, rationale_present, detail, called_at, source_kind)
SELECT d.sim_run_id, d.depot_id, d.tick_seq, d.sim_clock,
       COALESCE(d.proposed_action->>'agent_solver_chain_id',
                d.context_frame->>'agent_solver_chain_id'),
       CASE d.l2_engine WHEN 'nemotron' THEN 'nvidia_nemotron'
                        WHEN 'forward_lex' THEN 'cpsat_service'
                        ELSE 'anthropic_advisor' END,
       CASE WHEN d.l2_engine='nemotron' THEN 'agent' ELSE 'proposer' END,
       d.proposed_action->>'model', d.total_latency_ms,
       COALESCE(d.outcome_status, CASE WHEN d.overridden THEN 'refused' ELSE 'answered' END),
       (d.enacted_action ? 'rationale'),
       jsonb_build_object('l2_engine', d.l2_engine, 'action_context', d.action_context,
                          'decision_id', d.decision_id, 'overridden', d.overridden,
                          'solver', d.proposed_action->>'solver',
                          'l1_rules_evaluated',
                            jsonb_array_length(COALESCE(d.rule_results,'[]'::jsonb)),
                          'backfilled_from', 'ottoq_decisions'),
       d.created_at, 'backfill'
  FROM public.ottoq_decisions d
 WHERE d.l2_engine IN ('nemotron','forward_lex','llm_advisor');

-- ── 8. the reading view: the honest sentence, computed ───────────────────────
CREATE OR REPLACE VIEW public.ottoq_intelligence_ledger AS
SELECT provider, role,
       count(*)                                              AS calls,
       count(*) FILTER (WHERE http_status IS NOT NULL)        AS calls_with_provider_status,
       count(*) FILTER (WHERE outcome = 'answered')           AS answered,
       count(*) FILTER (WHERE outcome = 'abstained')          AS abstained,
       count(*) FILTER (WHERE outcome = 'fallback')           AS fell_back,
       count(*) FILTER (WHERE outcome = 'refused')            AS refused,
       COALESCE(sum(proposals_out), 0)                        AS proposals,
       count(*) FILTER (WHERE COALESCE((detail->>'l1_rules_evaluated')::int, 0) = 0
                          AND role = 'agent')                 AS agent_calls_with_no_l1_rules,
       round(avg(latency_ms))                                 AS avg_latency_ms,
       max(latency_ms)                                        AS max_latency_ms,
       min(called_at)                                         AS first_call,
       max(called_at)                                         AS last_call,
       count(*) FILTER (WHERE source_kind = 'backfill')        AS reconstructed
  FROM public.ottoq_model_call_ledger
 GROUP BY provider, role;

COMMENT ON VIEW public.ottoq_intelligence_ledger IS
'0340. The quantified answer CLAUDE.md rule 6 demands, per provider, computed rather than remembered -- so a cuOpt, Nemotron or CP-SAT sentence can be re-derived instead of quoted from a file that has gone stale three times. `calls_with_provider_status` is the count that means "the provider was actually reached"; `calls` includes attempts that fell back locally. `agent_calls_with_no_l1_rules` is the shield-coverage gap in one column.';

DO $assertions$
DECLARE v_http int; v_led int; v_nem_src int; v_nem_led int; v_block int; v_refused boolean;
BEGIN
  -- A1. Backfill is complete and attributed, both directions.
  SELECT count(*) INTO v_http FROM public.cuopt_invocation_log WHERE http_status IS NOT NULL;
  SELECT count(*) INTO v_led  FROM public.ottoq_model_call_ledger
   WHERE source_kind='backfill' AND detail->>'backfilled_from'='cuopt_invocation_log';
  IF v_led <> v_http THEN
    RAISE EXCEPTION '0340 A1a: backfilled % NVIDIA calls, source holds %', v_led, v_http;
  END IF;
  SELECT count(*) INTO v_nem_src FROM public.ottoq_decisions
   WHERE l2_engine IN ('nemotron','forward_lex','llm_advisor');
  SELECT count(*) INTO v_nem_led FROM public.ottoq_model_call_ledger
   WHERE source_kind='backfill' AND detail->>'backfilled_from'='ottoq_decisions';
  IF v_nem_led <> v_nem_src THEN
    RAISE EXCEPTION '0340 A1b: backfilled % decisions, source holds %', v_nem_led, v_nem_src;
  END IF;

  -- A2. THE WHOLE POINT: no FK to the run table, so the purge cannot be blocked
  -- by this table and cannot delete through it either.
  IF EXISTS (SELECT 1 FROM pg_constraint
              WHERE contype='f' AND conrelid='public.ottoq_model_call_ledger'::regclass
                AND confrelid='public.ottoq_sim_runs'::regclass) THEN
    RAISE EXCEPTION '0340 A2: the ledger acquired an FK to ottoq_sim_runs';
  END IF;

  -- A3. Registered as evidence, and the guard is still clean -- evaluated, not
  -- assumed, because a new sim_run_id column that nobody classified is exactly
  -- what check (a) exists to catch.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name='ottoq_model_call_ledger' AND column_name='sim_run_id'
                    AND class='evidence') THEN
    RAISE EXCEPTION '0340 A3a: the ledger is not registered as evidence';
  END IF;
  SELECT count(*) INTO v_block FROM public.ottoq_check_run_scope_registry() WHERE severity='block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0340 A3b: the registry guard now reports % blocking defect(s)', v_block;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry()
              WHERE table_name='ottoq_model_call_ledger') THEN
    RAISE EXCEPTION '0340 A3c: the guard reports the new ledger at all';
  END IF;

  -- A3d. THE SIDESTEP, PINNED. This ledger must stay single-class: exactly one
  -- registry row, class='evidence'. A stamp or engine row added later would make
  -- check (b) demand an FK to ottoq_sim_runs, and A2 forbids that FK -- so the
  -- two assertions would become unsatisfiable together. That is G61 arriving
  -- here, and it should fail loudly in a migration rather than quietly at a
  -- purge.
  IF (SELECT count(*) FROM public.ottoq_run_scope_registry
       WHERE table_name='ottoq_model_call_ledger') <> 1
     OR EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                 WHERE table_name='ottoq_model_call_ledger' AND class IN ('engine','stamp')) THEN
    RAISE EXCEPTION '0340 A3d: the ledger has a non-evidence registry row, which would demand the FK A2 forbids';
  END IF;

  -- A4. Append-only is REAL, not declared: attempt a delete and require refusal.
  BEGIN
    DELETE FROM public.ottoq_model_call_ledger WHERE call_id = (
      SELECT min(call_id) FROM public.ottoq_model_call_ledger);
    v_refused := false;
  EXCEPTION WHEN insufficient_privilege THEN
    v_refused := true;
  END;
  IF NOT v_refused THEN
    RAISE EXCEPTION '0340 A4: the append-only guard did not refuse a DELETE';
  END IF;

  -- A5. Both capture triggers swallow. A trigger on ottoq_decisions that can
  -- raise is a trigger that can abort a tick.
  IF (SELECT prosrc FROM pg_proc WHERE oid='public.ottoq_capture_decision_model_call()'::regprocedure)
       NOT LIKE '%EXCEPTION WHEN OTHERS%'
     OR (SELECT prosrc FROM pg_proc WHERE oid='public.ottoq_capture_cuopt_model_call()'::regprocedure)
       NOT LIKE '%EXCEPTION WHEN OTHERS%' THEN
    RAISE EXCEPTION '0340 A5: a capture trigger can raise into the tick path';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname='ottoq_capture_decision_model_call_trg' AND NOT tgisinternal
                    AND tgenabled <> 'D')
     OR NOT EXISTS (SELECT 1 FROM pg_trigger
                     WHERE tgname='ottoq_capture_cuopt_model_call_trg' AND NOT tgisinternal
                       AND tgenabled <> 'D') THEN
    RAISE EXCEPTION '0340 A5b: a capture trigger is missing or disabled';
  END IF;

  -- A5c. THE DOUBLE-COUNT GUARD, ASSERTED. A row in this ledger means exactly
  -- one call, so the decisions trigger must never fire for 'cuopt' -- that call
  -- is captured at cuopt_invocation_log and the decision row is its enactment.
  IF pg_get_triggerdef((SELECT oid FROM pg_trigger
                         WHERE tgname='ottoq_capture_decision_model_call_trg'
                           AND NOT tgisinternal)) LIKE '%''cuopt''%' THEN
    RAISE EXCEPTION '0340 A5c: the decisions trigger fires for cuopt and would double-count calls';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_model_call_ledger
              WHERE provider='nvidia_cuopt' AND detail->>'backfilled_from'='ottoq_decisions') THEN
    RAISE EXCEPTION '0340 A5d: cuOpt calls were backfilled from both sources';
  END IF;

  -- A6. forces_recert=FALSE, EXECUTED. No certified function body changed, so
  -- no certification atom can have moved. Asserted by absence: nothing in the
  -- catalog reads the new table except this file's own view.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname IN ('public','ottoq','twin')
                AND p.prosrc ILIKE '%ottoq_model_call_ledger%'
                AND p.proname NOT IN ('ottoq_log_model_call',
                                      'ottoq_model_call_ledger_append_only',
                                      'ottoq_capture_cuopt_model_call',
                                      'ottoq_capture_decision_model_call')) THEN
    RAISE EXCEPTION '0340 A6: an existing routine already reads the new ledger';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0340_every_external_model_call_gets_a_ledger_that_outlives_its_run', false,
  'Purely additive: an evidence ledger, two swallowing capture triggers, one view. No FK was removed -- see G61 in the header. No certified function body changes and no certification atom reads the new table; A6 asserts no pre-existing routine does either. Recertification not required.',
  now())
ON CONFLICT(name) DO NOTHING;
