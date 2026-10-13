-- migration-version: PENDING
-- migration-name:    every_agent_pass_keeps_what_it_saw_and_what_it_changed
--
-- 0703  **Every agent pass keeps what it saw and what it changed.** An append-only evidence record per pass of the
--        orchestrator agent (OTTO-Q PRIME): the exact board text the model read, its hash computed by the database,
--        the prompt's hash, the models asked and the model that answered, sampling, token use, every attempt, the
--        parsed answer, and what each lever actually did, with one honest outcome class. (Study 2026-10-13, blind
--        spots AG-4 / TF-10 / AG-3 / AV-3 / AG-12; db/checks/0440.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase asked on 2026-10-13 whether OTTO-Q should run one agent on top or swarms of agents per run. That question
--   cannot be answered from the evidence the engine keeps, and this file is the reason it now can be. Measured
--   2026-10-13 (read-only, twin depot 11111111-…):
--
--   (a) NO AGENT DECISION CAN BE REPLAYED. public.ottoq_agent_board is VOLATILE and persists nothing; the decision
--       row (ottoq_decisions, class=engine, purged with its run) keeps board_tick, which blocks were present, the
--       attempts and the version -- not the board. ottoq_model_call_ledger (0340, evidence) keeps no input hash, no
--       prompt version, no sampling and no tokens. ai_decision_log, designed for exactly this, holds 0 rows. Without
--       the board no prompt, model or topology change (one agent against several) can be scored offline against the
--       same inputs.
--   (b) THE AGENT'S OUTCOME IS OVERSTATED. Since 2026-10-08, 766 of 766 agent ledger rows read 'enacted' against 14
--       passes that changed engine state: the edge function counts a directive as "applied" and a solver handoff that
--       returned zero proposals as success (index.ts v28 :414, :555, :590). A lever that never moves the depot reads
--       the same as one that does.
--   (c) THE LAYER'S COST IS INVISIBLE. _shared/agent_model_call.ts discards the response's usage block, so not one
--       token of the agent's spend has ever been recorded.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   1. public.ottoq_agent_prompts -- one row per distinct system prompt (sha256 -> text). The prompt varies with the
--      board (the charge-order section is appended only when a charge line is on it), so it is stored by hash once,
--      not per pass.
--   2. public.ottoq_agent_pass_evidence -- one row per pass of an agent seat. board_text is the board EXACTLY as the
--      model received it (JSON.stringify(board, null, 1)); board_sha256 is a STORED generated column the database
--      computes from that text, and board_sha256_client (what the edge function hashed before sending) must equal
--      it or the insert fails -- so a reader can prove the stored text is the text that was hashed at send time.
--      outcome_class is one of:
--        changed_state  a lever moved the depot: a charge order taken (accepted/partial), a dial or ops action applied
--        echo           the agent's charge order was the kernel's own (refused same_as_kernel) and nothing else moved
--        advisory       directives or approval requests only
--        no_effect      the model answered and nothing it asked for took effect
--        solver_only    the model was not consulted (no wake event; 0705) -- the solver ran on the standing objective
--        fallback       the model was consulted and did not answer
--        failed         the pass broke before its decision was written
--      No chain-of-thought is stored (the 0335 boundary): reasoning is disabled on every call, and `answer` is the
--      parsed JSON the agent returned -- the same rationale ottoq_decisions already keeps.
--   3. Registered in ottoq_run_scope_registry as class 'evidence' with NO foreign key (0340/0364's reason: an
--      enforcing FK on evidence can only block ottoq_purge_prior_runs or, as CASCADE, erase what check (c) forbids).
--   4. public.ottoq_agent_pass_scorecard -- per day, seat, run kind and model: passes, outcome classes (asserted to
--      sum to passes), tokens, latency. Grouped by day first because CLAUDE.md rule 6's standing test requires it.
--
--   NOT changed: ottoq_decisions.outcome_status. The twin app renders 'noop_no_candidate' as "nothing free"
--   (ottoyarddepot-sim src/lib/plainWords.ts:50), so relabelling agent passes there would mislabel them on screen.
--   The honest class lives here, and edge v29 also copies it onto the decision's enacted_action.outcome_class.
--
--   Size: one board is ~20-60 KB of JSON before TOAST compression; at today's ~1,600 passes a week that is tens of MB
--   a week before compression, and 0705's wake gate cuts the consulted passes. Not in the nightly retention allowlist
--   (0645/0646) on purpose: this is the record every future agent comparison is graded on.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   Two new tables, a view and a registry row. Nothing on the tick path reads or writes them; no certification atom
--   hashes them (P2 asserts it); the edge function that writes them is quiesced in certification arms (run_by
--   'cert_harness' / orchestrator_agent_enabled=0).
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The tables are append-only evidence; rolling back means the writer stops (redeploy edge v28). Dropping them is a
--   separate, deliberate migration.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0703 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_agent_pass_evidence') IS NOT NULL OR to_regclass('public.ottoq_agent_prompts') IS NOT NULL THEN
    RAISE EXCEPTION '0703 P1: the evidence tables already exist';
  END IF;
  IF to_regclass('public.ottoq_model_call_ledger') IS NULL OR to_regclass('public.ottoq_run_scope_registry') IS NULL THEN
    RAISE EXCEPTION '0703 P1: 0340''s ledger or the run-scope registry is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0699_the_twin_apps_determinism_canon_card_reads_again') THEN
    RAISE EXCEPTION '0703 P1: 0699 is not classified; apply in order';
  END IF;
END $premises$;

-- ── P2: no certification atom or hashing function can see the new tables (they do not exist yet; this asserts that
--        no function names them, so a future reader cannot be surprised by an atom that started hashing them) ──
DO $atoms$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND ((p.prosrc ~ 'ottoq_agent_pass_evidence' OR p.prosrc ~ 'ottoq_agent_prompts'));
  IF v_n > 0 THEN
    RAISE EXCEPTION '0703 P2: % function(s) already name the new tables', v_n;
  END IF;
END $atoms$;

-- ── P3: the database encoding is UTF8, which is what makes ottoq_sha256_utf8 honest as IMMUTABLE ──
DO $enc$
BEGIN
  IF pg_encoding_to_char((SELECT encoding FROM pg_database WHERE datname = current_database())) <> 'UTF8' THEN
    RAISE EXCEPTION '0703 P3: the database encoding is not UTF8';
  END IF;
END $enc$;

-- ══ 0. one hash function, IMMUTABLE so generated columns may use it ═══════════════════════════════════════════
--: convert_to() is STABLE (it depends on the encoding), so PostgreSQL refuses it in a generated column. The database
--: encoding is UTF8 and cannot change under a live database (P3 asserts it), so wrapping it IMMUTABLE is honest.
CREATE OR REPLACE FUNCTION public.ottoq_sha256_utf8(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE STRICT PARALLEL SAFE
SET search_path TO 'pg_catalog'
AS $fn$ SELECT encode(sha256(convert_to(p_text, 'UTF8')), 'hex') $fn$;

COMMENT ON FUNCTION public.ottoq_sha256_utf8(text) IS
'0703. Hex sha256 of a text''s UTF-8 bytes. IMMUTABLE so generated columns may use it; honest because the database encoding is UTF8 (asserted by 0703 P3).';

-- ══ 1. the prompts, by hash ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_agent_prompts (
  prompt_sha256  text PRIMARY KEY CHECK (prompt_sha256 ~ '^[0-9a-f]{64}$'),
  agent_version  text NOT NULL,
  prompt_text    text NOT NULL,
  --: the database's own hash of the text, so the key cannot name a different prompt than the one stored
  text_sha256    text GENERATED ALWAYS AS (public.ottoq_sha256_utf8(prompt_text)) STORED,
  first_seen_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_agent_prompts_key_is_text_hash CHECK (prompt_sha256 = text_sha256)
);

COMMENT ON TABLE public.ottoq_agent_prompts IS
'0703. Every distinct system prompt an agent seat has sent, keyed by the sha256 of its text (the key must equal the database''s own hash of the stored text). Append-only. ottoq_agent_pass_evidence.prompt_sha256 names a row here by value (no FK: evidence carries no enforcing foreign keys).';

-- ══ 2. the pass record ═══════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_agent_pass_evidence (
  pass_id              bigserial PRIMARY KEY,
  chain_id             text NOT NULL UNIQUE,
  seat                 text NOT NULL DEFAULT 'ottoq_prime',
  agent_version        text NOT NULL,
  --: durable keys, NO foreign keys (see §2.3)
  sim_run_id           uuid,
  depot_id             uuid,
  run_by               text,
  board_tick           bigint,
  trigger_tick         bigint,
  recorded_tick        bigint,
  sim_clock            timestamptz,
  --: 0705: why this pass consulted the model (or did not)
  wake                 jsonb,
  consulted            boolean NOT NULL,
  --: the board exactly as sent, and the database's own hash of it
  board_text           text,
  board_bytes          integer GENERATED ALWAYS AS (octet_length(board_text)) STORED,
  board_sha256         text GENERATED ALWAYS AS (public.ottoq_sha256_utf8(board_text)) STORED,
  board_sha256_client  text,
  prompt_sha256        text CHECK (prompt_sha256 IS NULL OR prompt_sha256 ~ '^[0-9a-f]{64}$'),
  models_requested     text[],
  model_answered       text,
  response_model       text,
  response_id          text,
  sampling             jsonb,
  usage                jsonb,
  attempts             jsonb,
  answer               jsonb,
  levers               jsonb NOT NULL DEFAULT '{}'::jsonb,
  outcome_class        text NOT NULL,
  decision_written     boolean NOT NULL DEFAULT true,
  propose_ms           integer,
  total_ms             integer,
  recorded_at          timestamptz NOT NULL DEFAULT now(),
  source_kind          text NOT NULL DEFAULT 'live',
  CONSTRAINT ottoq_agent_pass_board_hash_matches
    CHECK (board_sha256_client IS NULL OR board_sha256_client = board_sha256),
  CONSTRAINT ottoq_agent_pass_outcome_class_known
    CHECK (outcome_class IN ('changed_state','echo','advisory','no_effect','solver_only','fallback','failed')),
  --: a pass that consulted the model and got an answer cannot be filed as not consulted, and vice versa
  CONSTRAINT ottoq_agent_pass_consulted_coherent
    CHECK ((outcome_class = 'solver_only') = (NOT consulted))
);

COMMENT ON TABLE public.ottoq_agent_pass_evidence IS
'0703. One row per pass of an agent seat (today: OTTO-Q PRIME, ottoq-orchestrator-agent v29+). board_text is the board exactly as the model received it; board_sha256 is computed by the database from it and board_sha256_client (the edge function''s hash at send time) must equal it, so the stored text is provably the text that was sent. answer is the parsed JSON the agent returned -- never chain-of-thought (reasoning is disabled; 0335). outcome_class says honestly what the pass did: changed_state (a charge order taken, a dial or ops action applied), echo (its order was the kernel''s own), advisory (directives or approval requests only), no_effect, solver_only (0705: no wake event, the model was not consulted), fallback (consulted, no answer), failed. Class evidence, append-only, NO foreign key (0340/0364). Written by the edge function with the service role; nobody else reads or writes it. This is the record any comparison of agent prompts, models or topologies (one agent against several) is graded on.';

CREATE INDEX ottoq_agent_pass_evidence_run_idx ON public.ottoq_agent_pass_evidence (sim_run_id, pass_id DESC);
CREATE INDEX ottoq_agent_pass_evidence_day_idx ON public.ottoq_agent_pass_evidence (recorded_at DESC);

-- ══ 3. append-only, both tables ═══════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_agent_evidence_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.agent_evidence_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION '% is append-only: % refused. Set ottoq.agent_evidence_unlock=on in the session to override, '
                  'and say why in a migration.', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_agent_pass_evidence_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_pass_evidence
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_evidence_append_only();
CREATE TRIGGER ottoq_agent_prompts_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_agent_prompts
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_agent_evidence_append_only();

-- ══ 4. who may touch them: the service role writes and reads; nobody else ════════════════════════════════════
ALTER TABLE public.ottoq_agent_pass_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_agent_prompts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_agent_pass_evidence, public.ottoq_agent_prompts FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.ottoq_agent_pass_evidence_pass_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.ottoq_agent_pass_evidence, public.ottoq_agent_prompts TO service_role;
GRANT USAGE ON SEQUENCE public.ottoq_agent_pass_evidence_pass_id_seq TO service_role;
REVOKE ALL ON FUNCTION public.ottoq_agent_evidence_append_only() FROM PUBLIC, anon, authenticated;
--: the hash is harmless and pure; the cockpits may verify a board hash with it
GRANT EXECUTE ON FUNCTION public.ottoq_sha256_utf8(text) TO anon, authenticated, service_role;

-- ══ 5. registry ═══════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_agent_pass_evidence', 'sim_run_id', 'evidence',
        '0703: one row per agent pass -- the board as sent, its hash, the prompt hash, models, sampling, tokens, '
        'attempts, the parsed answer and an honest outcome class. Evidence, not engine: it is what every comparison '
        'of agent prompts, models or topologies is graded on, so it must outlive its run. NO foreign key, for '
        '0340/0364''s reason: an enforcing FK on evidence can only block the purge or, as CASCADE, erase what check '
        '(c) forbids erasing.');

-- ══ 6. the reader ═════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW public.ottoq_agent_pass_scorecard AS
SELECT date_trunc('day', e.recorded_at)                                       AS day,
       e.seat,
       CASE WHEN e.run_by = 'production_live' THEN 'production' ELSE 'twin' END AS run_kind,
       COALESCE(e.model_answered, 'none')                                      AS model_answered,
       count(*)                                                                AS passes,
       count(*) FILTER (WHERE e.consulted)                                     AS consulted,
       count(*) FILTER (WHERE e.outcome_class = 'changed_state')               AS changed_state,
       count(*) FILTER (WHERE e.outcome_class = 'echo')                        AS echo,
       count(*) FILTER (WHERE e.outcome_class = 'advisory')                    AS advisory,
       count(*) FILTER (WHERE e.outcome_class = 'no_effect')                   AS no_effect,
       count(*) FILTER (WHERE e.outcome_class = 'solver_only')                 AS solver_only,
       count(*) FILTER (WHERE e.outcome_class = 'fallback')                    AS fallback,
       count(*) FILTER (WHERE e.outcome_class = 'failed')                      AS failed,
       --: asserted by the check file to equal passes: every pass in exactly one class
       count(*) FILTER (WHERE e.outcome_class IN ('changed_state','echo','advisory','no_effect',
                                                  'solver_only','fallback','failed')) AS classified,
       sum(NULLIF(e.usage->>'prompt_tokens','')::bigint)                       AS prompt_tokens,
       sum(NULLIF(e.usage->>'completion_tokens','')::bigint)                   AS completion_tokens,
       round(avg(e.propose_ms) FILTER (WHERE e.consulted))                     AS mean_propose_ms,
       percentile_disc(0.95) WITHIN GROUP (ORDER BY e.total_ms)                AS p95_total_ms,
       round(avg(e.board_bytes))                                               AS mean_board_bytes,
       count(DISTINCT e.sim_run_id)                                            AS runs
  FROM public.ottoq_agent_pass_evidence e
 GROUP BY 1, 2, 3, 4;

COMMENT ON VIEW public.ottoq_agent_pass_scorecard IS
'0703. The agent layer by day, seat, run kind and answering model -- grouped by day first, as CLAUDE.md rule 6''s standing test requires, and by model because the fallback model answers at a different temperature. classified must equal passes. Quote an agent rate beside its day, its model and its run kind, never pooled.';

REVOKE ALL ON TABLE public.ottoq_agent_pass_scorecard FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ottoq_agent_pass_scorecard TO service_role;

-- ══ V: every structural promise, asserted, and every probe rolled back ═════════════════════════════════════════
DO $v$
DECLARE v_fk int; v_msg text; v_sha text; v_n int;
BEGIN
  --: V1 no foreign keys on either table
  SELECT count(*) INTO v_fk FROM pg_constraint con
   WHERE con.conrelid IN ('public.ottoq_agent_pass_evidence'::regclass, 'public.ottoq_agent_prompts'::regclass)
     AND con.contype = 'f';
  IF v_fk <> 0 THEN RAISE EXCEPTION '0703 V1 FAILED: % foreign key(s)', v_fk; END IF;

  --: V2 registered as evidence, exactly once
  IF (SELECT count(*) FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_agent_pass_evidence') <> 1
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                     WHERE table_name = 'ottoq_agent_pass_evidence' AND class = 'evidence') THEN
    RAISE EXCEPTION '0703 V2 FAILED: the registry row is missing or not class=evidence';
  END IF;

  --: V3 the database hashes the board; a matching client hash is accepted, a wrong one refused, an unknown class
  --:    refused, a solver_only pass that claims a consult refused, and an UPDATE refused -- all rolled back
  BEGIN
    INSERT INTO public.ottoq_agent_pass_evidence (chain_id, agent_version, consulted, board_text, board_sha256_client,
                                                  outcome_class)
    VALUES ('0703-v3-a', 'v-test', true, '{"tick": 1}',
            encode(sha256(convert_to('{"tick": 1}', 'UTF8')), 'hex'), 'no_effect')
    RETURNING board_sha256 INTO v_sha;
    IF v_sha IS DISTINCT FROM encode(sha256(convert_to('{"tick": 1}', 'UTF8')), 'hex') THEN
      RAISE EXCEPTION '0703 V3 FAILED: the stored hash is not the hash of the stored text';
    END IF;
    BEGIN
      INSERT INTO public.ottoq_agent_pass_evidence (chain_id, agent_version, consulted, board_text, board_sha256_client,
                                                    outcome_class)
      VALUES ('0703-v3-b', 'v-test', true, '{"tick": 1}', repeat('0', 64), 'no_effect');
      RAISE EXCEPTION '0703 V3 FAILED: a wrong client hash was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO public.ottoq_agent_pass_evidence (chain_id, agent_version, consulted, outcome_class)
      VALUES ('0703-v3-c', 'v-test', true, 'enacted');
      RAISE EXCEPTION '0703 V3 FAILED: an unknown outcome class was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      INSERT INTO public.ottoq_agent_pass_evidence (chain_id, agent_version, consulted, outcome_class)
      VALUES ('0703-v3-d', 'v-test', true, 'solver_only');
      RAISE EXCEPTION '0703 V3 FAILED: a solver_only pass that consulted the model was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
      UPDATE public.ottoq_agent_pass_evidence SET outcome_class = 'changed_state' WHERE chain_id = '0703-v3-a';
      RAISE EXCEPTION '0703 V3 FAILED: an UPDATE was accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE EXCEPTION 'V3 ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'V3 ROLLBACK' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_pass_evidence) THEN
    RAISE EXCEPTION '0703 V3 FAILED: a probe row survived its rollback';
  END IF;

  --: V4 the public key and a signed-in caller can neither read nor write the evidence
  BEGIN
    PERFORM set_config('role', 'authenticated', true);
    BEGIN
      PERFORM 1 FROM public.ottoq_agent_pass_evidence LIMIT 1;
      v_msg := 'authenticated read';
    EXCEPTION WHEN insufficient_privilege THEN v_msg := 'refused';
    END;
    RAISE EXCEPTION 'AS AUTH|%', v_msg;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'AS AUTH|refused' THEN
    RAISE EXCEPTION '0703 V4 FAILED: a signed-in caller was not refused: %', v_msg;
  END IF;
  IF has_table_privilege('anon', 'public.ottoq_agent_pass_evidence', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_agent_prompts', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.ottoq_agent_pass_evidence', 'INSERT') THEN
    RAISE EXCEPTION '0703 V4 FAILED: grants are not as written';
  END IF;

  --: V5 the scorecard reads (empty) and its classes cover every outcome class the table admits
  SELECT count(*) INTO v_n FROM public.ottoq_agent_pass_scorecard;
  RAISE NOTICE '0703 V1-V5 PASSED (scorecard rows: %)', v_n;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0703_every_agent_pass_keeps_what_it_saw_and_what_it_changed', false, false,
  'Study 2026-10-13 (AG-4/AG-3/AG-12; db/checks/0440): two append-only evidence tables (agent prompts by hash; one row '
  'per agent pass with the board as sent, its database-computed hash, models, sampling, tokens, attempts, the parsed '
  'answer and an honest outcome class), a scorecard view and a registry row. Nothing on the tick path reads or writes '
  'them; no atom hashes them; the writer is quiesced in certification arms: FALSE/FALSE.',
  now());

COMMIT;
