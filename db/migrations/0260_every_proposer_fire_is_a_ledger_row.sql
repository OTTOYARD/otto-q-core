-- migration-version: PENDING
-- migration-name: 0260_every_proposer_fire_is_a_ledger_row
-- ===========================================================================
-- 0260  EVERY PROPOSER FIRE IS A LEDGER ROW
-- ===========================================================================
-- probe:          BUILD_QUEUE #4; bridge/proposer_bridge.py; CLAUDE.md rule 6
--                 ("cuOpt claims must be ledger-backed" -- the same rule, for the
--                 next proposer, BEFORE its first claim is made)
-- forces_recert:  FALSE -- new objects only: one table, one function, two registry
--                 rows. Nothing on the tick path is touched; A6 pins the pair.
--
-- APPLY AFTER 0259 (the batch function submits through the same door 0259's
-- precedence table now seats; either order works mechanically, but the fire log
-- exists to ledger fires that 0259 makes hearable).
--
-- NOT TO BE APPLIED WHILE A ROUND IS IN FLIGHT OR SCHEDULED.
--
-- ---------------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------------
--
-- cuopt_invocation_log exists so that "never invoked" is distinguishable from
-- "invoked N times, abstained M" -- CLAUDE.md rule 6 makes that ledger the ONLY
-- admissible source for any cuOpt sentence. The CP-SAT proposer is about to be
-- invoked for the first time (bridge/), and it would be the same mistake in the
-- other direction to let its first hundred fires happen with no ledger and then
-- reconstruct them from cron durations, which is what db/checks/0158 had to do for
-- cuOpt nine days after the fact.
--
-- So the ledger lands FIRST. One row per fire, whatever happened:
--
--   submitted  -- N rows went through ottoq_submit_external_proposal
--   empty      -- the proposer was invoked and had nothing to say (no plannable
--                 vehicle, no charge-capable stall); 0 rows, and that is a fact
--   refused    -- the door refused (Posture A: not a certified proposer into a
--                 certification arm; or unauthenticated). ALL rows of the batch
--                 roll back, the refusal is the ledger row, and the caller sees it
--                 in the return value rather than as an exception
--   error      -- anything else the door raised; same all-or-nothing
--
-- and the fire record itself (the bridge's own accounting: frame hash, solver
-- statuses, optima, reproducible flag, counts) travels in `fire` jsonb so an
-- auditor can walk a proposal row back to the exact world the solver saw.
--
-- THE FUNCTION IS A WRAPPER AROUND THE DOOR, NOT A SECOND DOOR. Every row still
-- goes through ottoq_submit_external_proposal: server-derived identity (0198),
-- Posture A (0241), the supersede of the entity's prior pending row, the tick
-- stamp (0236). This function adds atomicity and the ledger row, nothing else.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity only.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%');
  IF v_n > 0 THEN
    RAISE EXCEPTION 'P FAILED: % certification pair(s) or tick(s) in flight', v_n;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 1. The ledger.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_proposer_fire_log (
  fire_id                bigserial PRIMARY KEY,
  sim_run_id             uuid        NOT NULL,
  depot_id               uuid        NOT NULL,
  declared_source        text        NOT NULL,
  effective_source       text,
  tick_seq               integer,
  fired_at               timestamptz NOT NULL DEFAULT now(),
  status                 text        NOT NULL CHECK (status IN ('submitted','empty','refused','error')),
  frame_hash             text,
  n_vehicles             integer,
  n_in_serviceable_state integer,
  n_rows                 integer     NOT NULL DEFAULT 0,
  n_planned              integer,
  n_abstained            integer,
  n_deferred             integer,
  n_submitted            integer     NOT NULL DEFAULT 0,
  proposal_ids           uuid[]      NOT NULL DEFAULT '{}',
  solver                 jsonb,
  fire                   jsonb       NOT NULL,
  error                  text
);
CREATE INDEX IF NOT EXISTS ottoq_proposer_fire_log_run_idx
  ON public.ottoq_proposer_fire_log (sim_run_id, fired_at);
COMMENT ON TABLE public.ottoq_proposer_fire_log IS
  '0260. One row per proposer invocation through ottoq_proposer_submit_batch, whatever happened (submitted / empty / refused / error). The cuopt_invocation_log discipline for every other proposer: never invoked, invoked-and-empty, invoked-and-refused and invoked-and-submitted-N are four different ledger facts. `fire` is the caller''s own record (frame hash, solver accounting); `proposal_ids` are the door''s receipts.';

-- Run-scope registry, or the purge check will rightly refuse (CLAUDE.md C3.4).
-- evidence: the fire log is a claim substrate (rule 6), not working data.
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note) VALUES
('public', 'ottoq_proposer_fire_log', 'sim_run_id', 'evidence',
 '0260: the proposer invocation ledger. Evidence, not engine: every proposer sentence is quantified from it (CLAUDE.md rule 6), so it must survive its run.'),
('public', 'ottoq_proposer_fire_log', 'tick_seq', 'stamp',
 '0260: run tick at fire time, from ottoq_sim_runs.tick_count. Provenance, not a scoping key; sim_run_id is.')
ON CONFLICT (table_schema, table_name, column_name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. The one-call submit: every row through the door, one ledger row, all or nothing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_proposer_submit_batch(
  p_sim_run_id  uuid,
  p_depot_id    uuid,
  p_source      text,
  p_rows        jsonb,
  p_fire        jsonb,
  p_ttl_seconds integer DEFAULT 60)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_row     jsonb;
  v_id      uuid;
  v_ids     uuid[] := ARRAY[]::uuid[];
  v_n       integer := 0;
  v_status  text;
  v_err     text;
  v_tick    integer;
  v_fire_id bigint;
  v_eff     text;
  v_fire    jsonb := COALESCE(p_fire, '{}'::jsonb);
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR NULLIF(p_source, '') IS NULL THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: sim_run_id, depot_id and source are all required'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(COALESCE(p_rows, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: p_rows must be a jsonb array, got %',
                    jsonb_typeof(p_rows) USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_ttl_seconds, 0) < 1 THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: p_ttl_seconds must be >= 1' USING ERRCODE = '22023';
  END IF;

  SELECT r.tick_count INTO v_tick FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_proposer_submit_batch: run % does not exist', p_sim_run_id
      USING ERRCODE = '22023';
  END IF;

  -- THE BATCH IS ONE SUB-TRANSACTION. A refusal on row k rolls back rows 1..k-1
  -- too: a half-submitted plan is not a plan, and the ledger row says exactly
  -- what happened instead of raising past the caller.
  BEGIN
    FOR v_row IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
      v_id := public.ottoq_submit_external_proposal(
                p_sim_run_id, p_depot_id,
                v_row->>'action_context', v_row->>'entity_type',
                (v_row->>'entity_id')::uuid, v_row->'proposal',
                p_source, p_ttl_seconds);
      v_ids := v_ids || v_id;
      v_n := v_n + 1;
    END LOOP;
    v_status := CASE WHEN v_n = 0 THEN 'empty' ELSE 'submitted' END;
  EXCEPTION WHEN OTHERS THEN
    v_ids := ARRAY[]::uuid[];
    v_n := 0;
    v_err := SQLSTATE || ': ' || SQLERRM;
    v_status := CASE WHEN SQLERRM LIKE 'OTTOQ_PROPOSAL_REFUSED_CERT%'
                       OR SQLERRM LIKE 'OTTOQ_PROPOSAL_UNAUTHENTICATED%'
                     THEN 'refused' ELSE 'error' END;
  END;

  -- The SERVER-derived source (0198), read back from the first receipt: an
  -- operator's declared 'forward_lex' lands as 'operator:<uuid>' and the ledger
  -- must say so.
  IF v_n > 0 THEN
    SELECT p.source INTO v_eff FROM public.ottoq_external_proposals p WHERE p.proposal_id = v_ids[1];
  END IF;

  INSERT INTO public.ottoq_proposer_fire_log
    (sim_run_id, depot_id, declared_source, effective_source, tick_seq, status,
     frame_hash, n_vehicles, n_in_serviceable_state, n_rows, n_planned, n_abstained,
     n_deferred, n_submitted, proposal_ids, solver, fire, error)
  VALUES
    (p_sim_run_id, p_depot_id, p_source, v_eff, v_tick, v_status,
     v_fire->>'frame_hash',
     (v_fire->>'n_vehicles')::int, (v_fire->>'n_in_serviceable_state')::int,
     jsonb_array_length(COALESCE(p_rows, '[]'::jsonb)),
     (v_fire->>'n_planned')::int, (v_fire->>'n_abstained')::int, (v_fire->>'n_deferred')::int,
     v_n, v_ids, v_fire->'solver', v_fire, v_err)
  RETURNING fire_id INTO v_fire_id;

  RETURN jsonb_build_object(
    'fire_id', v_fire_id, 'status', v_status, 'submitted', v_n,
    'proposal_ids', to_jsonb(v_ids), 'tick_seq', v_tick,
    'effective_source', v_eff, 'error', v_err);
END
$fn$;

COMMENT ON FUNCTION public.ottoq_proposer_submit_batch(uuid, uuid, text, jsonb, jsonb, integer) IS
  '0260. Submits every row of p_rows through ottoq_submit_external_proposal inside one sub-transaction (all or nothing) and writes exactly one ottoq_proposer_fire_log row whatever happened. A door refusal (Posture A, unauthenticated) is returned as status=refused, never raised. p_fire is the caller''s own fire record (bridge/proposer_bridge.py fire()).';

REVOKE ALL ON FUNCTION public.ottoq_proposer_submit_batch(uuid, uuid, text, jsonb, jsonb, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_proposer_submit_batch(uuid, uuid, text, jsonb, jsonb, integer) FROM anon;
REVOKE ALL ON FUNCTION public.ottoq_proposer_submit_batch(uuid, uuid, text, jsonb, jsonb, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_proposer_submit_batch(uuid, uuid, text, jsonb, jsonb, integer) TO service_role;
REVOKE ALL ON TABLE public.ottoq_proposer_fire_log FROM anon;
GRANT SELECT ON TABLE public.ottoq_proposer_fire_log TO service_role, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Classify.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
('0260_every_proposer_fire_is_a_ledger_row', false,
 'New objects only: ottoq_proposer_fire_log (registered evidence + stamp) and ottoq_proposer_submit_batch, a '
 'wrapper that submits every row through ottoq_submit_external_proposal in one sub-transaction and ledgers the '
 'outcome. Nothing on the tick path changes; A6 pins ottoq_determinism_pair.')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- A. Assertions -- including two LIVE probes against the most recent certification
--    run, which is exactly the run the door must refuse (Posture A). Both probe
--    rows are deleted at the end; A5 asserts none remain.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_run uuid; v_depot uuid; v_r jsonb; v_n int; v_md5 text; v_before int;
BEGIN
  -- A1: table, CHECK, index.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid = c.conrelid
                  WHERE t.relname = 'ottoq_proposer_fire_log' AND c.contype = 'c'
                    AND pg_get_constraintdef(c.oid) LIKE '%submitted%refused%') THEN
    RAISE EXCEPTION 'A1 FAILED: status CHECK missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='ottoq_proposer_fire_log_run_idx') THEN
    RAISE EXCEPTION 'A1 FAILED: run index missing'; END IF;

  -- A2: registry rows.
  SELECT count(*) INTO v_n FROM public.ottoq_run_scope_registry
   WHERE table_name = 'ottoq_proposer_fire_log' AND column_name IN ('sim_run_id','tick_seq');
  IF v_n <> 2 THEN RAISE EXCEPTION 'A2 FAILED: % registry rows, expected 2', v_n; END IF;

  -- A3: an EMPTY fire is a ledger row. Probe against the latest cert run: no row
  --     goes through the door, so Posture A is not even consulted.
  SELECT r.sim_run_id, r.depot_id INTO v_run, v_depot
    FROM public.ottoq_sim_runs r WHERE r.run_by = 'cert_harness' ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'A3 FAILED: no cert run to probe against'; END IF;
  SELECT count(*) INTO v_before FROM public.ottoq_external_proposals WHERE sim_run_id = v_run;
  v_r := public.ottoq_proposer_submit_batch(v_run, v_depot, 'forward_lex', '[]'::jsonb,
           '{"probe":"0260","status":"empty","n_vehicles":0,"n_in_serviceable_state":0,"frame_hash":"sha256:probe"}'::jsonb, 60);
  IF v_r->>'status' <> 'empty' OR (v_r->>'submitted')::int <> 0 THEN
    RAISE EXCEPTION 'A3 FAILED: empty batch returned %', v_r; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposer_fire_log WHERE fire_id = (v_r->>'fire_id')::bigint AND status = 'empty'
                    AND frame_hash = 'sha256:probe' AND n_rows = 0) THEN
    RAISE EXCEPTION 'A3 FAILED: no empty fire row'; END IF;

  -- A4: a REFUSED fire is a ledger row and inserts nothing. forward_lex is not a
  --     certified proposer and v_run is a certification arm, so the door must
  --     raise OTTOQ_PROPOSAL_REFUSED_CERT (0241) and this function must swallow
  --     it into status=refused with ZERO proposal rows added.
  v_r := public.ottoq_proposer_submit_batch(v_run, v_depot, 'forward_lex',
           jsonb_build_array(jsonb_build_object(
             'action_context', 'stall_assignment', 'entity_type', 'vehicle',
             'entity_id', gen_random_uuid(),
             'proposal', jsonb_build_object('verb','assign_stall','abstain',true,
                                            'rationale', jsonb_build_object('reason','0260 A4 probe')))),
           '{"probe":"0260","status":"proposed","n_vehicles":1,"frame_hash":"sha256:probe"}'::jsonb, 60);
  IF v_r->>'status' <> 'refused' OR (v_r->>'submitted')::int <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: expected refused/0, got %', v_r; END IF;
  IF (v_r->>'error') NOT LIKE '%OTTOQ_PROPOSAL_REFUSED_CERT%' THEN
    RAISE EXCEPTION 'A4 FAILED: refusal reason not recorded: %', v_r->>'error'; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_external_proposals WHERE sim_run_id = v_run;
  IF v_n <> v_before THEN RAISE EXCEPTION 'A4 FAILED: proposal rows for the cert run moved % -> %', v_before, v_n; END IF;

  -- A5: the probe rows are removed and nothing else was touched.
  DELETE FROM public.ottoq_proposer_fire_log WHERE fire->>'probe' = '0260';
  SELECT count(*) INTO v_n FROM public.ottoq_proposer_fire_log WHERE fire->>'probe' = '0260';
  IF v_n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % probe rows remain', v_n; END IF;

  -- A6: the pair is untouched; anon cannot execute the batch.
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_md5 <> '8a35b8c874fed154cc216140faec0274' THEN RAISE EXCEPTION 'A6 FAILED: ottoq_determinism_pair moved to %', v_md5; END IF;
  IF has_function_privilege('anon', 'public.ottoq_proposer_submit_batch(uuid,uuid,text,jsonb,jsonb,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'A6 FAILED: anon can execute the batch'; END IF;
  IF NOT has_function_privilege('service_role', 'public.ottoq_proposer_submit_batch(uuid,uuid,text,jsonb,jsonb,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'A6 FAILED: service_role cannot execute the batch'; END IF;

  RAISE NOTICE '0260 OK: fire log live; empty and refused probes ledgered and removed against cert run %', v_run;
END
$a$;

SELECT count(*) AS fire_log_rows_post FROM public.ottoq_proposer_fire_log;
