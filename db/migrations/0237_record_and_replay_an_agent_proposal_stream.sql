-- migration-version: PENDING
-- migration-name:    record_and_replay_an_agent_proposal_stream
--
-- AGENT LAYER, step 2 -- Posture B from SOLVER_STATE.md §8.2, which §8.3 calls
-- "the door to the agentic layer". 0236 gave proposals a tick; this makes a
-- proposal stream recordable and replayable, so the sentence
--
--     the disposer is certified deterministic against recorded agent proposals;
--     agents are measured, not trusted
--
-- becomes something the harness can check instead of something a doc asserts.
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS THE SHAPE IT IS
-- ---------------------------------------------------------------------------
-- §8.2 rejected posture C (live external calls during certification) because an
-- external proposer is not reproducible from this side of the wire, so it
-- manufactures red pairs that are not engine faults. It chose B: production
-- records what the agent proposed; certification replays that recording into
-- BOTH arms. Then h_prop proves both arms received the same proposals, and
-- h_dec/h_cmd prove the disposer turned them into the same decisions. The
-- proposer is not certified -- it is not supposed to be. The DISPOSER is.
--
-- Three functions, and the third is the one that makes the other two credible:
--
--   ottoq_proposal_replay_capture(run, replay_id, sources)  record a stream
--   ottoq_proposal_replay_inject(run, replay_id, tick)      play it back
--   ottoq_proposal_replay_content_hash(run, marker)         read back what
--                                                           actually landed
--
-- ---------------------------------------------------------------------------
-- FOUR DECISIONS, EACH WITH ITS REASON
-- ---------------------------------------------------------------------------
-- 1. INJECT DIRECTLY, NOT THROUGH ottoq_submit_external_proposal. That function
--    derives source from caller identity and stamps tick_seq from the TARGET
--    run's current tick (0236). Both are correct for a live agent and wrong for
--    a replay, which must preserve what was recorded. A replay is not a new
--    claim by an agent; it is a recording being played.
--
-- 2. BUT THE LEDGER MUST NOT LIE ABOUT IT. Every injected row carries
--    declared_source = 'replay:<replay_id>' and submitted_by_role =
--    'system:replay'. `source` is preserved as recorded, because the disposer
--    must treat a replayed proposal exactly as it treated the original -- that
--    is the whole experiment. So the row is indistinguishable to the DISPOSER
--    and fully distinguishable to an AUDITOR, which is the correct asymmetry.
--
-- 3. INJECT AS 'pending', NOT AS RECORDED. ottoq_external_proposals.status holds
--    the FINAL status -- enacted, superseded, expired. Replaying 'enacted' would
--    be replaying the answer along with the question. The recorded final status
--    is kept in the replay table as orig_status for analysis and is never
--    injected.
--
-- 4. LEAVE expires_at NULL. Every consumer already reads
--      GREATEST(COALESCE(expires_at, created_at + interval '35 minutes'),
--               created_at + interval '35 minutes') < now()
--    so NULL resolves to the same 35-minute floor a real proposal gets, and this
--    migration does not have to invent a wall-clock instant for a recording.
--
-- forces_recert: FALSE. One new table, three new functions, nothing existing
-- modified. Nothing in the decide path calls any of them -- they are a harness,
-- driven from outside a run. A2 pins ottoq_decide_tick's md5 and A3 asserts no
-- verdict atom reads the new table.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n; END IF;
END $P$;

DO $P1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_external_proposals'
                    AND column_name='tick_seq') THEN
    RAISE EXCEPTION 'P1 REFUSED: 0236 (tick_seq) must be applied first -- a replay without a tick is not a replay';
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- THE RECORDING
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_proposal_replay (
  replay_id       uuid        NOT NULL,
  seq             integer     NOT NULL,
  tick_seq        integer     NOT NULL,
  action_context  text        NOT NULL,
  entity_type     text        NOT NULL,
  entity_id       uuid,
  proposal        jsonb       NOT NULL,
  source          text        NOT NULL,
  orig_status     text,
  captured_from   uuid        NOT NULL,
  captured_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (replay_id, seq)
);

COMMENT ON TABLE public.ottoq_proposal_replay IS
  '0237 / SOLVER_STATE.md 8.2 Posture B. A recorded agent proposal stream, ordered '
  'by content so the same run always records the same seq. Replayed into both arms '
  'of a certification pair so the disposer can be certified deterministic GIVEN the '
  'proposals, without certifying the proposer -- which is not reproducible and is '
  'not supposed to be. orig_status is the recorded FINAL status and is never '
  'injected; injection is always pending.';

CREATE INDEX IF NOT EXISTS ottoq_proposal_replay_tick_idx
  ON public.ottoq_proposal_replay (replay_id, tick_seq);

-- ---------------------------------------------------------------------------
-- CAPTURE. Ordering is by CONTENT, never by created_at (a wall clock) and never
-- by proposal_id (a fresh uuid) -- so capturing the same run twice produces the
-- same seq numbering. That is what makes a replay reproducible rather than
-- merely repeatable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_proposal_replay_capture(
  p_sim_run_id uuid,
  p_replay_id  uuid,
  p_sources    text[] DEFAULT NULL      -- NULL = every source on the run
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_n integer;
BEGIN
  IF p_sim_run_id IS NULL OR p_replay_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_proposal_replay_capture: run and replay_id are both required';
  END IF;

  DELETE FROM public.ottoq_proposal_replay WHERE replay_id = p_replay_id;

  INSERT INTO public.ottoq_proposal_replay
    (replay_id, seq, tick_seq, action_context, entity_type, entity_id,
     proposal, source, orig_status, captured_from)
  SELECT p_replay_id,
         row_number() OVER (ORDER BY COALESCE(p.tick_seq, -1),
                                     p.action_context, p.entity_type,
                                     COALESCE(p.entity_id::text, '-'),
                                     p.source, p.proposal::text),
         COALESCE(p.tick_seq, -1),
         p.action_context, p.entity_type, p.entity_id,
         p.proposal, p.source, p.status, p_sim_run_id
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = p_sim_run_id
     AND (p_sources IS NULL OR p.source = ANY (p_sources));

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$fn$;

-- ---------------------------------------------------------------------------
-- INJECT. One tick's worth, so a driver can interleave injection with ticks.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_proposal_replay_inject(
  p_sim_run_id uuid,
  p_replay_id  uuid,
  p_tick       integer
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_n integer; v_depot uuid;
BEGIN
  SELECT depot_id INTO v_depot FROM public.ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN
    RAISE EXCEPTION 'ottoq_proposal_replay_inject: run % does not exist', p_sim_run_id;
  END IF;

  INSERT INTO public.ottoq_external_proposals
    (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
     source, status, expires_at, declared_source, submitted_by_role, submitted_by,
     tick_seq)
  SELECT p_sim_run_id, v_depot, r.action_context, r.entity_type, r.entity_id,
         r.proposal, r.source,
         'pending',                              -- never replay the answer
         NULL,                                   -- the 35-min floor applies
         'replay:' || p_replay_id::text,         -- auditable as a replay
         'system:replay',
         NULL,
         r.tick_seq
    FROM public.ottoq_proposal_replay r
   WHERE r.replay_id = p_replay_id AND r.tick_seq = p_tick
   ORDER BY r.seq;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$fn$;

-- ---------------------------------------------------------------------------
-- READ BACK. Content hash of what a replay actually LANDED on a run, over the
-- same fields ottoq_hash_proposals uses minus the ones a replay deliberately
-- rewrites (status, declared_source). This is the instrument the assertions
-- below use, and it is separate from the verdict's own h_prop on purpose --
-- a test that shares an implementation with the thing it tests proves nothing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_proposal_replay_content_hash(
  p_sim_run_id uuid,
  p_replay_id  uuid
) RETURNS text
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $fn$
  SELECT md5(COALESCE(string_agg(
           COALESCE(p.tick_seq::text,'-') || '|' || p.action_context || '|' ||
           p.entity_type || '|' || COALESCE(p.entity_id::text,'-') || '|' ||
           p.source || '|' || p.proposal::text,
           E'\n' ORDER BY COALESCE(p.tick_seq,-1), p.action_context, p.entity_type,
                          COALESCE(p.entity_id::text,'-'), p.source, p.proposal::text), ''))
    FROM public.ottoq_external_proposals p
   WHERE p.sim_run_id = p_sim_run_id
     AND p.declared_source = 'replay:' || p_replay_id::text;
$fn$;

-- ===========================================================================
-- THE TESTS. Behavioural, and the fourth one is the reason to trust the first
-- three: an instrument that only ever agrees has not been shown to discriminate.
-- ===========================================================================
DO $TESTS$
DECLARE
  v_src_run  uuid; v_tgt_run uuid; v_replay uuid := gen_random_uuid();
  v_captured int;  v_injected int;
  v_h1 text; v_h2 text; v_h3 text; v_row record;
BEGIN
  -- a run that actually has proposals, and a target run to inject into
  SELECT p.sim_run_id INTO v_src_run
    FROM public.ottoq_external_proposals p
   GROUP BY p.sim_run_id ORDER BY count(*) DESC LIMIT 1;
  IF v_src_run IS NULL THEN RAISE EXCEPTION 'TEST SETUP FAILED: no run carries proposals'; END IF;

  SELECT sim_run_id INTO v_tgt_run FROM public.ottoq_sim_runs
   WHERE sim_run_id <> v_src_run AND depot_id IS NOT NULL
   ORDER BY started_at DESC LIMIT 1;
  IF v_tgt_run IS NULL THEN RAISE EXCEPTION 'TEST SETUP FAILED: no target run'; END IF;

  ---------------------------------------------------------------------------
  -- A1  CAPTURE IS COMPLETE. Every proposal on the run is recorded, once.
  ---------------------------------------------------------------------------
  v_captured := public.ottoq_proposal_replay_capture(v_src_run, v_replay);
  IF v_captured <> (SELECT count(*) FROM public.ottoq_external_proposals WHERE sim_run_id = v_src_run) THEN
    RAISE EXCEPTION 'A1 FAILED: captured % of % proposals',
      v_captured, (SELECT count(*) FROM public.ottoq_external_proposals WHERE sim_run_id = v_src_run);
  END IF;

  ---------------------------------------------------------------------------
  -- A2  CAPTURE IS IDEMPOTENT AND CONTENT-ORDERED. Capturing the same run
  --     twice must produce byte-identical seq assignment, or a replay is not
  --     reproducible.
  ---------------------------------------------------------------------------
  SELECT md5(string_agg(seq||'|'||tick_seq||'|'||action_context||'|'||proposal::text, E'\n' ORDER BY seq))
    INTO v_h1 FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;
  PERFORM public.ottoq_proposal_replay_capture(v_src_run, v_replay);
  SELECT md5(string_agg(seq||'|'||tick_seq||'|'||action_context||'|'||proposal::text, E'\n' ORDER BY seq))
    INTO v_h2 FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;
  IF v_h1 IS DISTINCT FROM v_h2 THEN
    RAISE EXCEPTION 'A2 FAILED: re-capturing the same run produced a different stream (% vs %)', v_h1, v_h2;
  END IF;

  ---------------------------------------------------------------------------
  -- A3  INJECTION IS FAITHFUL, TICK BY TICK, FIELD BY FIELD.
  ---------------------------------------------------------------------------
  v_injected := 0;
  FOR v_row IN SELECT DISTINCT tick_seq FROM public.ottoq_proposal_replay
                WHERE replay_id = v_replay ORDER BY tick_seq LOOP
    v_injected := v_injected + public.ottoq_proposal_replay_inject(v_tgt_run, v_replay, v_row.tick_seq);
  END LOOP;
  IF v_injected <> v_captured THEN
    RAISE EXCEPTION 'A3 FAILED: injected % of % recorded proposals', v_injected, v_captured;
  END IF;

  -- Compared as two content hashes over the SAME field list and ordering, not
  -- as a FULL OUTER JOIN. The join version of this check was written first and
  -- was wrong: with `r.replay_id = v_replay` in the WHERE, any row where the
  -- recorded side is NULL evaluates NULL and drops out, so it could only ever
  -- catch recorded-without-injected and never injected-without-recorded. A
  -- one-directional test for a two-directional claim.
  SELECT md5(COALESCE(string_agg(
           COALESCE(r.tick_seq::text,'-') || '|' || r.action_context || '|' ||
           r.entity_type || '|' || COALESCE(r.entity_id::text,'-') || '|' ||
           r.source || '|' || r.proposal::text,
           E'\n' ORDER BY COALESCE(r.tick_seq,-1), r.action_context, r.entity_type,
                          COALESCE(r.entity_id::text,'-'), r.source, r.proposal::text), ''))
    INTO v_h1
    FROM public.ottoq_proposal_replay r WHERE r.replay_id = v_replay;

  v_h2 := public.ottoq_proposal_replay_content_hash(v_tgt_run, v_replay);

  IF v_h1 IS DISTINCT FROM v_h2 THEN
    RAISE EXCEPTION 'A3 FAILED: injected content hash % does not match recorded %', v_h2, v_h1;
  END IF;

  ---------------------------------------------------------------------------
  -- A4  PROVENANCE IS HONEST. Every injected row is auditable as a replay and
  --     none claims to be a live agent submission.
  ---------------------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM public.ottoq_external_proposals
              WHERE sim_run_id = v_tgt_run AND declared_source = 'replay:'||v_replay::text
                AND (submitted_by_role <> 'system:replay' OR status <> 'pending')) THEN
    RAISE EXCEPTION 'A4 FAILED: an injected row is mislabelled or was injected non-pending';
  END IF;

  ---------------------------------------------------------------------------
  -- A5  THE NEGATIVE CONTROL. Everything above shows the instrument AGREEING.
  --     None of it shows the instrument can DISAGREE. Perturb exactly one
  --     recorded proposal, re-inject, and require the content hash to move.
  --     Without this, A1-A4 are compatible with a hash that returns a constant.
  ---------------------------------------------------------------------------
  v_h1 := public.ottoq_proposal_replay_content_hash(v_tgt_run, v_replay);
  IF v_h1 IS NULL OR v_h1 = md5('') THEN
    RAISE EXCEPTION 'A5 FAILED: the content hash is empty; there is nothing to discriminate';
  END IF;

  UPDATE public.ottoq_external_proposals
     SET proposal = proposal || '{"_0237_perturbation":true}'::jsonb
   WHERE proposal_id = (SELECT proposal_id FROM public.ottoq_external_proposals
                         WHERE sim_run_id = v_tgt_run
                           AND declared_source = 'replay:'||v_replay::text
                         ORDER BY proposal_id LIMIT 1);

  v_h3 := public.ottoq_proposal_replay_content_hash(v_tgt_run, v_replay);
  IF v_h3 = v_h1 THEN
    RAISE EXCEPTION 'A5 FAILED: one proposal was altered and the content hash did not move. '
                    'The instrument cannot detect a differing proposal stream, so A1-A4 prove nothing.';
  END IF;

  ---------------------------------------------------------------------------
  -- A6  CLEAN UP, AND PROVE IT. The migration must leave no injected rows on a
  --     real run and no recording behind.
  ---------------------------------------------------------------------------
  DELETE FROM public.ottoq_external_proposals
   WHERE sim_run_id = v_tgt_run AND declared_source = 'replay:'||v_replay::text;
  DELETE FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;

  IF EXISTS (SELECT 1 FROM public.ottoq_external_proposals WHERE declared_source = 'replay:'||v_replay::text)
     OR EXISTS (SELECT 1 FROM public.ottoq_proposal_replay WHERE replay_id = v_replay) THEN
    RAISE EXCEPTION 'A6 FAILED: self-test residue survived cleanup';
  END IF;

  RAISE NOTICE '0237 self-test: captured %, injected %, perturbation detected, cleaned up',
               v_captured, v_injected;
END $TESTS$;

-- ---------------------------------------------------------------------------
-- A7  Nothing certified was touched.
-- ---------------------------------------------------------------------------
DO $A7$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure))
     <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A7 FAILED: ottoq_decide_tick md5 moved';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE proname='ottoq_determinism_pair') ~* 'ottoq_proposal_replay' THEN
    RAISE EXCEPTION 'A7 FAILED: the verdict now reads the replay table; forces_recert FALSE is wrong';
  END IF;
END $A7$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'record_and_replay_an_agent_proposal_stream',
  now(),
  false,
  'Agent layer step 2 -- SOLVER_STATE.md 8.2 Posture B, which 8.3 calls the door to '
  'the agentic layer. Adds ottoq_proposal_replay plus capture/inject/content_hash so '
  'a recorded agent proposal stream can be replayed into both arms of a pair, making '
  '"the disposer is deterministic GIVEN the proposals" checkable without certifying '
  'the proposer, which is not reproducible and is not meant to be. Capture orders by '
  'CONTENT, never created_at or proposal_id, so re-capturing a run yields identical '
  'seq. Injection preserves source (the disposer must not be able to tell) but marks '
  'declared_source=replay:<id> and submitted_by_role=system:replay (an auditor must), '
  'injects status=pending rather than the recorded final status, and leaves '
  'expires_at NULL so the existing 35-minute floor applies. Self-test is behavioural '
  'and includes a NEGATIVE CONTROL: it alters one injected proposal and requires the '
  'content hash to move, because A1-A4 passing is otherwise compatible with a hash '
  'that returns a constant. All self-test rows are deleted and the deletion is '
  'asserted. forces_recert FALSE: one new table, three new functions, nothing '
  'existing modified, nothing in the decide path calls them; A7 pins decide_tick md5 '
  'and asserts the verdict does not read the new table.'
);
