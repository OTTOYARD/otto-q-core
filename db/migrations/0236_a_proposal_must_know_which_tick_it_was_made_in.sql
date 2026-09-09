-- migration-version: PENDING
-- migration-name:    a_proposal_must_know_which_tick_it_was_made_in
--
-- AGENT LAYER, step 1 of the Posture-B sequence in SOLVER_STATE.md §8.3.
--
-- §8.2 chose Posture B as "the agentic layer's first deliverable": production
-- runs ledger every external proposal, and a cert mode replays that recorded
-- stream into both arms, so the provable sentence becomes
--
--     the disposer is certified deterministic against recorded agent proposals;
--     agents are measured, not trusted.
--
-- A replay is only faithful if each proposal goes back in AT THE TICK IT WAS
-- MADE. Measured today: public.ottoq_external_proposals carries
-- proposal_id, sim_run_id, depot_id, action_context, entity_type, entity_id,
-- proposal, source, status, created_at, expires_at, declared_source,
-- submitted_by_role, submitted_by -- and NO TICK. created_at is a wall-clock
-- stamp, and reconstructing a tick from it means dividing by a tick interval
-- and hoping, which is the guessing this codebase keeps having to undo.
--
-- So: give the proposal its tick, from the only authority for it --
-- ottoq_sim_runs.tick_count on its own run, read at insert.
--
-- ---------------------------------------------------------------------------
-- SCOPE: THE EXTERNAL DOOR ONLY, AND THAT IS DELIBERATE
-- ---------------------------------------------------------------------------
-- Two functions insert into ottoq_external_proposals:
--
--   public.ottoq_submit_external_proposal   <- THIS MIGRATION. The agent door.
--                                              Called by edge functions and
--                                              operators. NOT in the decide path.
--   public.ottoq_l2_optimize_assignments    <- NOT TOUCHED. It runs INSIDE the
--                                              policy gate of
--                                              ottoq_sim_decide_and_dispatch,
--                                              i.e. inside the certified tick.
--
-- Posture B replays the EXTERNAL stream. Internal deterministic proposers do not
-- need replaying -- they regenerate themselves identically from the same seed,
-- which is what "deterministic internal proposer" means and what §8.1 says
-- h_prop already proves. Leaving l2_optimize_assignments alone keeps this
-- migration completely out of the certified path, which is why it can be
-- forces_recert FALSE rather than needing a round behind it.
--
-- If internal proposals ever need tick provenance too, that is a separate
-- migration with a recert round, and it is not needed for the agent layer.
--
-- ---------------------------------------------------------------------------
-- WHAT IS NOT CHANGED, HAVING LOOKED AT IT
-- ---------------------------------------------------------------------------
-- p_ttl_seconds is accepted by this function and then effectively overridden
-- downstream: every consumer reads
--     GREATEST(COALESCE(p.expires_at, p.created_at + interval '35 minutes'),
--              p.created_at + interval '35 minutes') < now()
-- so no proposal is ever treated as expired sooner than 35 wall-minutes after
-- creation, whatever TTL the caller asked for. The minimum TTL any caller has
-- ever requested is 90 seconds. That is an API telling a small lie -- it takes a
-- parameter it cannot honour -- but migration 0122 made the wall domain
-- deliberate and annotated it ("the stamp is wall-domain (deliberate); the sweep
-- must read the same clock"), the stamp and the sweep agree, and changing an
-- expiry floor is a behaviour change to the disposer, not a provenance fix.
-- Recorded here, deliberately not bundled in.
--
-- forces_recert: FALSE. The column is nullable and additive; no verdict atom
-- hashes it (asserted in A3 against the live ottoq_determinism_pair body); the
-- only function changed is outside the decide path; and ottoq_decide_tick's md5
-- is asserted unchanged.

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
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)'::regprocedure));
  IF h IS NULL THEN RAISE EXCEPTION 'P1 REFUSED: the agent door does not resolve'; END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- 1. THE COLUMN
-- ---------------------------------------------------------------------------
ALTER TABLE public.ottoq_external_proposals
  ADD COLUMN IF NOT EXISTS tick_seq integer;

COMMENT ON COLUMN public.ottoq_external_proposals.tick_seq IS
  '0236: the run tick this proposal was made in, read from ottoq_sim_runs.tick_count '
  'at insert. NULL for every row written before 0236 and for any insert whose run '
  'row is missing. Exists so a recorded external proposal stream can be replayed '
  'at the tick it happened (SOLVER_STATE.md 8.2 Posture B), rather than having its '
  'tick reconstructed by dividing created_at by a tick interval.';

-- ---------------------------------------------------------------------------
-- 2. REGISTER IT. The purge check refuses unregistered run-scoped columns, and
--    it is right to. Class 'stamp': it records WHEN, it is not a scoping key
--    (sim_run_id already carries the scope and is registered 'engine').
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_external_proposals', 'tick_seq', 'stamp',
        '0236: run tick at insert, from ottoq_sim_runs.tick_count. Provenance for '
        'Posture-B proposal replay. Not a scoping key; sim_run_id is.')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. STAMP IT AT THE DOOR. Anchored substitution, uniqueness asserted.
-- ---------------------------------------------------------------------------
DO $CHG$
DECLARE d text; a1 text; a2 text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)'::regprocedure);

  a1 := '     declared_source, submitted_by_role, submitted_by)';
  a2 := '          p_source, v_role, v_who.auth_uid)';

  n := (length(d) - length(replace(d, a1, ''))) / length(a1);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: column-list anchor occurs % times, expected 1', n; END IF;
  n := (length(d) - length(replace(d, a2, ''))) / length(a2);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: values anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a1, '     declared_source, submitted_by_role, submitted_by, tick_seq)');
  d := replace(d, a2, '          p_source, v_role, v_who.auth_uid,'
                   || E'\n          -- 0236: the tick is the run''s to state, not the caller''s.'
                   || E'\n          (SELECT r.tick_count FROM public.ottoq_sim_runs r'
                   || E'\n            WHERE r.sim_run_id = p_sim_run_id))');

  EXECUTE d;
END $CHG$;

-- ---------------------------------------------------------------------------
-- A1  BEHAVIOURAL, not textual. Actually submit a proposal against a real run,
--     read back what landed, and prove tick_seq matches that run's tick_count.
--     Then delete the probe row so the migration leaves no residue.
--
--     This is the assertion style the rest of this file's siblings should have
--     been using: a grep for 'tick_seq' in the body would pass on a function
--     that stamps NULL.
-- ---------------------------------------------------------------------------
DO $A1$
DECLARE v_run uuid; v_depot uuid; v_expected int; v_id uuid; v_got int; v_veh uuid;
BEGIN
  SELECT sim_run_id, depot_id, COALESCE(tick_count, 0)
    INTO v_run, v_depot, v_expected
    FROM public.ottoq_sim_runs
   WHERE depot_id IS NOT NULL
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'A1 FAILED: no run to probe against'; END IF;

  SELECT id INTO v_veh FROM public.vehicles WHERE home_depot_id = v_depot LIMIT 1;

  v_id := public.ottoq_submit_external_proposal(
            v_run, v_depot, '0236_probe', 'vehicle', v_veh,
            '{"probe":true}'::jsonb, '0236_selftest', 300);

  SELECT tick_seq INTO v_got FROM public.ottoq_external_proposals WHERE proposal_id = v_id;

  IF v_got IS DISTINCT FROM v_expected THEN
    DELETE FROM public.ottoq_external_proposals WHERE proposal_id = v_id;
    RAISE EXCEPTION 'A1 FAILED: tick_seq came back %, expected % (run %)', v_got, v_expected, v_run;
  END IF;

  DELETE FROM public.ottoq_external_proposals WHERE proposal_id = v_id;
  IF EXISTS (SELECT 1 FROM public.ottoq_external_proposals WHERE proposal_id = v_id) THEN
    RAISE EXCEPTION 'A1 FAILED: the probe row survived cleanup';
  END IF;
END $A1$;

-- ---------------------------------------------------------------------------
-- A2  The other writer is untouched, so the certified path is untouched.
-- ---------------------------------------------------------------------------
DO $A2$
DECLARE d text; h text;
BEGIN
  d := pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure);
  IF d ~* 'tick_seq' THEN
    RAISE EXCEPTION 'A2 FAILED: the internal proposer was modified; this migration is scoped to the external door';
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A2 FAILED: ottoq_decide_tick md5 moved: %', h;
  END IF;
END $A2$;

-- ---------------------------------------------------------------------------
-- A3  NO VERDICT ATOM HASHES THE NEW COLUMN. This is the actual justification
--     for forces_recert FALSE, so it is asserted rather than asserted-in-prose.
-- ---------------------------------------------------------------------------
DO $A3$
BEGIN
  IF (SELECT prosrc FROM pg_proc WHERE proname='ottoq_determinism_pair') ~* 'tick_seq' THEN
    RAISE EXCEPTION 'A3 FAILED: ottoq_determinism_pair references tick_seq; a canon could move '
                    'and forces_recert FALSE is wrong';
  END IF;
END $A3$;

-- ---------------------------------------------------------------------------
-- A4  Registered, or the purge check would rightly refuse the column later.
-- ---------------------------------------------------------------------------
DO $A4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name='ottoq_external_proposals' AND column_name='tick_seq') THEN
    RAISE EXCEPTION 'A4 FAILED: tick_seq is not in the run-scope registry';
  END IF;
END $A4$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_proposal_must_know_which_tick_it_was_made_in',
  now(),
  false,
  'Agent layer, step 1 of SOLVER_STATE.md 8.3 Posture B. ottoq_external_proposals '
  'carried no tick, so a recorded external proposal stream could only be replayed by '
  'reconstructing its tick from created_at and a tick interval. Adds a nullable '
  'tick_seq stamped from ottoq_sim_runs.tick_count at insert, in '
  'ottoq_submit_external_proposal ONLY -- the agent door, outside the decide path. '
  'ottoq_l2_optimize_assignments runs inside the certified tick and is deliberately '
  'untouched (A2 asserts it); internal deterministic proposers regenerate identically '
  'and do not need replay. Registered in the run-scope registry as class stamp. '
  'forces_recert FALSE, asserted rather than argued: A3 checks ottoq_determinism_pair '
  'does not reference tick_seq, so no canon can move, and A2 pins decide_tick md5. A1 '
  'is behavioural -- it submits a real proposal, reads tick_seq back, compares it to '
  'the run tick_count, and deletes the probe -- because a textual check for tick_seq '
  'would pass on a function that stamps NULL.'
);
