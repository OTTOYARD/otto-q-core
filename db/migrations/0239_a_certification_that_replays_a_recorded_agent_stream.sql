-- migration-version: 20260909032226
-- migration-name:    a_certification_that_replays_a_recorded_agent_stream
--
-- AGENT LAYER, step 3 of the SOLVER_STATE.md 8.3 sequence. The door.
--
--   step 1  0236  a proposal knows which tick it was made in          APPLIED
--   step 2  0237  record and replay an agent proposal stream          APPLIED
--   step 2.5 0238 the selector that consumes it is total on content   APPLIED
--   step 3  THIS  a certification PAIR driven by a recorded stream
--
-- 0237 shipped a proven substrate and said so plainly in its own footer:
--
--     "what is NOT yet true is that a certification PAIR has been run with a
--      replayed stream in both arms. That needs a driver that interleaves
--      ottoq_proposal_replay_inject with the tick loop, which is step 3.
--      Until then this is a proven substrate, not a proven certification."
--
-- This is that driver.
--
-- ---------------------------------------------------------------------------
-- WHICH ARM. A CORRECTION TO 0237'S OWN PLAN, MADE BY MEASURING
-- ---------------------------------------------------------------------------
-- 0237's footer named ottoq_cert_arm as the loop to wrap. Measured: it is not.
-- ottoq_determinism_pair does NOT call ottoq_cert_arm at all -- it opens its own
-- runs with twin.ottoq_sim_start_run and drives its own loop (its lines 47-53).
-- ottoq_cert_arm is the A/B and benchmark driver; ottoq_determinism_pair is the
-- certification driver and the only thing that produces the fourteen-atom
-- verdict. Posture B is a claim about the CERTIFICATION, so the replay belongs
-- in ottoq_determinism_pair's loop. Wrapping cert_arm would have produced a
-- replay-driven benchmark and called it a certification.
--
-- ---------------------------------------------------------------------------
-- WHERE THE INJECTION GOES, AND WHY THAT TICK
-- ---------------------------------------------------------------------------
-- The arm loop already reads the run's tick_count into v_ticks at the top of
-- every iteration. Inside ottoq_sim_advance_tick the world advance runs FIRST
-- (twin.ottoq_sim_advance_clock, which does tick_count = tick_count + 1) and
-- ottoq_sim_decide_and_dispatch runs after it. So the decide phase about to
-- happen is tick v_ticks + 1.
--
-- Measured rather than assumed, on six real benchmark arms: a 12-tick arm ends
-- at tick_count 12 and its ottoq_decisions carry tick_seq 1..12, twelve distinct
-- values. The mapping is exact.
--
-- Injecting BEFORE the advance means a replayed proposal is present for the
-- whole of its own tick, including the decide phase that reads it at
-- ottoq_decide_tick lines 128 and 958. The original proposal appeared partway
-- through that same decide phase. Presenting it at the start of the tick instead
-- of the middle is deliberate: it is the only alignment that is deterministic
-- and independent of the loop's internal ordering, and Posture B's claim is that
-- the SAME recorded stream, presented IDENTICALLY to both arms, produces
-- identical dispositions -- not that a replay re-enacts the submitting agent's
-- intra-tick latency.
--
-- The tick -1 bucket is injected once before the loop. ottoq_proposal_replay_
-- capture stores COALESCE(p.tick_seq, -1), so a stream recorded before 0236 has
-- every row at -1; without this it would be captured, look complete, and inject
-- nothing at all.
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS A CERTIFICATION AND NOT A DEMO
-- ---------------------------------------------------------------------------
-- The quiesce that 0152 and 0105 installed suppresses the PRODUCERS inside a
-- cert run (cuopt_propose_enabled=0, the LLM branch gated on run_by). It does
-- not touch the CONSUMER: ottoq_l2_external_proposal has no run_by or policy
-- filter, and ottoq_decide_tick still reads it twice per tick. So an injected
-- stream reaches the certified disposer, while nothing live can.
--
-- And the verdict already sees the result. h_prop hashes action_context,
-- entity_type, entity_id, source, declared_source, STATUS and proposal over
-- ottoq_external_proposals for the run. Injected rows land status='pending' and
-- ottoq_decide_tick's end-of-tick lifecycle moves each to enacted, superseded or
-- expired. So h_prop equality across the two arms is not "the same rows went
-- in" -- it is "the disposer did the same thing with them". That is the Posture
-- B sentence, made checkable:
--
--     the disposer is certified deterministic against recorded agent proposals;
--     agents are measured, not trusted.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE
-- ---------------------------------------------------------------------------
-- Nothing existing is edited. ottoq_determinism_pair keeps its md5 (A6 asserts
-- it), ottoq_decide_tick keeps its md5 (A7), and the new function is a sibling
-- that no scheduled round calls. A canon cannot move because nothing a canon
-- was measured over has changed.
--
-- The recert floor is nevertheless standing at 2026-09-09 03:15:07 because 0238
-- moved it forty minutes ago. That round is owed regardless of this file.
--
-- ---------------------------------------------------------------------------
-- replay_injected IS MEASURED, NOT ENFORCED
-- ---------------------------------------------------------------------------
-- Each arm object gains 'replay_injected'. It is deliberately NOT added to the
-- fourteen-atom equality list, per the blind-spot promotion doctrine in
-- CLAUDE.md 2.9a: an atom is added MEASURED first and ENFORCED only after a
-- flagship round shows the arms agree on it (0139 / 0206 / 0217 / 0225).
--
-- Stating the promotion gate now so it cannot be quietly skipped: promote it to
-- the equality list once one replay-driven pair at flagship scale reports the
-- same replay_injected on both arms. Its independent value is small -- a
-- divergence in injection count almost implies a divergence in 'ticks', which is
-- already enforced -- so it earns its place as a diagnostic that says the replay
-- actually happened, not as a fifteenth guarantee.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

DO $inflight$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active'
     AND (query LIKE '%ottoq_determinism_pair%' OR query LIKE '%ottoq_cert_arm%');
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s)/arm(s) in flight', n; END IF;
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0239_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

DO $p1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure));
  IF h <> 'e323bf87d0fbd9d3778bbda7c8f94ba7' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_determinism_pair md5 is %, pinned e323bf87d0fbd9d3778bbda7c8f94ba7', h;
  END IF;
  IF to_regprocedure('public.ottoq_proposal_replay_inject(uuid,uuid,integer)') IS NULL THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_proposal_replay_inject is absent; 0237 has not been applied';
  END IF;
  IF to_regprocedure('public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_determinism_pair_replay already exists; this migration creates it';
  END IF;
END $p1$;

-- ---------------------------------------------------------------------------
-- THE ARM. Six anchored substitutions over the live certification driver, each
-- asserted unique before the rewrite is built. Derived from the catalog rather
-- than retyped, so the new arm is the certified arm plus exactly these edits
-- and nothing else -- which is the property that makes it a certification.
-- ---------------------------------------------------------------------------
DO $chg$
DECLARE d text; a text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure);

  -- 1. the name
  a := 'CREATE OR REPLACE FUNCTION public.ottoq_determinism_pair(p_seed bigint';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: name anchor occurs % times', n; END IF;
  d := replace(d, a, 'CREATE OR REPLACE FUNCTION public.ottoq_determinism_pair_replay(p_seed bigint');

  -- 2. the parameter
  a := 'p_arm_budget_s integer DEFAULT 240)';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: signature anchor occurs % times', n; END IF;
  d := replace(d, a, 'p_arm_budget_s integer DEFAULT 240, p_replay_id uuid DEFAULT NULL::uuid)');

  -- 3. the counter. Its own line -- never appended to an existing declaration
  --    line, which is how 0235 commented out three variables at once.
  a := '  v_scen_depot uuid;';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: declare anchor occurs % times', n; END IF;
  d := replace(d, a, '  v_scen_depot uuid;'
                  || E'\n  v_inj int := 0;   -- 0239: replayed proposals injected into THIS arm');

  -- 4. the depot guard, and the per-arm counter reset
  a := '  FOR v_arm IN 1..2 LOOP';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: arm-loop anchor occurs % times', n; END IF;
  d := replace(d, a,
       E'  /* 0239: A REPLAY BELONGS TO A DEPOT. ottoq_proposal_replay rows name\n'
    || E'     entity_ids from the run they were captured on; injected into another\n'
    || E'     depot they would match no vehicle, the selector would find nothing,\n'
    || E'     and the pair would pass while proving nothing. Refused BEFORE either\n'
    || E'     arm is created, so a mismatch costs nothing and cannot alter a canon\n'
    || E'     -- the same posture as 0175''s scenario/depot guard above. */\n'
    || E'  IF p_replay_id IS NOT NULL THEN\n'
    || E'    IF NOT EXISTS (SELECT 1 FROM public.ottoq_proposal_replay WHERE replay_id = p_replay_id) THEN\n'
    || E'      RAISE EXCEPTION ''determinism_pair_replay: replay % holds no rows'', p_replay_id\n'
    || E'        USING ERRCODE = ''P0001'';\n'
    || E'    END IF;\n'
    || E'    IF EXISTS (SELECT 1 FROM public.ottoq_proposal_replay r\n'
    || E'                 JOIN public.ottoq_sim_runs sr ON sr.sim_run_id = r.captured_from\n'
    || E'                WHERE r.replay_id = p_replay_id AND sr.depot_id IS DISTINCT FROM p_depot) THEN\n'
    || E'      RAISE EXCEPTION ''determinism_pair_replay: replay % was captured on a different depot than %''\n'
    || E'        , p_replay_id, p_depot USING ERRCODE = ''P0001'';\n'
    || E'    END IF;\n'
    || E'  END IF;\n'
    || E'\n'
    || E'  FOR v_arm IN 1..2 LOOP\n'
    || E'    v_inj := 0;   -- 0239: per arm, not per pair');

  -- 5. the tick -1 bucket, once, before the loop
  a := E'    v_t0 := clock_timestamp();\n    LOOP';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: pre-loop anchor occurs % times', n; END IF;
  d := replace(d, a,
       E'    /* 0239: the -1 bucket. ottoq_proposal_replay_capture stores\n'
    || E'       COALESCE(p.tick_seq, -1), so a stream recorded before 0236 has every\n'
    || E'       row at -1 and no tick of the loop below would ever reach it. Injected\n'
    || E'       once, at run start, so a legacy stream is presented rather than\n'
    || E'       silently dropped. */\n'
    || E'    IF p_replay_id IS NOT NULL THEN\n'
    || E'      v_inj := v_inj + public.ottoq_proposal_replay_inject(v_run, p_replay_id, -1);\n'
    || E'    END IF;\n'
    || E'    v_t0 := clock_timestamp();\n    LOOP');

  -- 6. the per-tick injection, immediately before the advance
  a := '      PERFORM public.ottoq_sim_advance_tick(v_run);';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: advance anchor occurs % times', n; END IF;
  d := replace(d, a,
       E'      /* 0239: the recorded stream goes back in at the tick it was made in,\n'
    || E'         BEFORE the advance whose decide phase will read it. v_ticks is the\n'
    || E'         run''s tick_count as of the top of this iteration; the world advance\n'
    || E'         inside ottoq_sim_advance_tick increments it before\n'
    || E'         ottoq_sim_decide_and_dispatch runs, so the decide phase about to\n'
    || E'         happen is tick v_ticks + 1. Measured on six benchmark arms: a\n'
    || E'         12-tick arm ends at tick_count 12 with decisions carrying tick_seq\n'
    || E'         1..12, twelve distinct values. */\n'
    || E'      IF p_replay_id IS NOT NULL THEN\n'
    || E'        v_inj := v_inj + public.ottoq_proposal_replay_inject(v_run, p_replay_id, v_ticks + 1);\n'
    || E'      END IF;\n'
    || E'      PERFORM public.ottoq_sim_advance_tick(v_run);');

  -- 7. the arm object records what it injected (MEASURED, not enforced)
  a := '      ''run'', v_run, ''ticks'', r.tick_count, ''clock'', r.sim_clock_current,';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: arm-object anchor occurs % times', n; END IF;
  d := replace(d, a,
       E'      ''run'', v_run, ''ticks'', r.tick_count, ''clock'', r.sim_clock_current,\n'
    || E'      -- 0239: MEASURED, not enforced. Deliberately absent from the equality\n'
    || E'      -- list below, per the blind-spot promotion doctrine (CLAUDE.md 2.9a).\n'
    || E'      ''replay_injected'', v_inj,');

  -- 8. the verdict names the stream it was run against
  a := '    ''seed'', p_seed, ''ticks'', p_ticks, ''scenario'', p_scenario,';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: verdict anchor occurs % times', n; END IF;
  d := replace(d, a,
       E'    ''seed'', p_seed, ''ticks'', p_ticks, ''scenario'', p_scenario,\n'
    || E'    -- 0239: a verdict that does not name its stream is not reproducible.\n'
    || E'    ''replay'', p_replay_id,');

  EXECUTE d;
END $chg$;

COMMENT ON FUNCTION public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid) IS
  '0239: ottoq_determinism_pair with a recorded external-proposal stream replayed '
  'into BOTH arms, tick for tick (SOLVER_STATE.md 8.2, Posture B). Derived from the '
  'certified pair by anchored substitution, so it is that function plus injection '
  'and nothing else. p_replay_id NULL makes it behave as the pair it came from. '
  'h_prop hashes proposal STATUS, so equality across the arms says the disposer '
  'treated the replayed stream identically -- not merely that the same rows went in.';

-- ===========================================================================
-- THE ASSERTIONS.
--
-- A replay-driven PAIR cannot be run inside a migration: it opens runs, resets
-- a depot's fleet, and takes minutes, and "never run a certification while a
-- migration is applying" is the rule this file's own P- block enforces. So the
-- pair proof is a separate step, recorded in db/checks. What IS asserted here
-- is everything that can be checked without ticking a world -- and two of the
-- five do it by CALLING the new function and catching what it refuses, because
-- a guard nobody has ever tripped is a guard nobody has tested.
-- ===========================================================================

-- A1  THE NEW ARM EXISTS; THE CERTIFIED ONE IS UNTOUCHED.
DO $a1$
DECLARE h text;
BEGIN
  IF to_regprocedure('public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid)') IS NULL THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_determinism_pair_replay was not created';
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure));
  IF h <> 'e323bf87d0fbd9d3778bbda7c8f94ba7' THEN
    RAISE EXCEPTION 'A1 FAILED: the certified pair moved to % -- this migration must not edit it', h;
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_decide_tick md5 moved to %', h;
  END IF;
END $a1$;

-- A2  IT IS THE CERTIFIED ARM PLUS INJECTION, AND NOTHING ELSE.
--     The verdict's equality list is counted, not read: the number of
--     v_arms[1] comparisons in the new body must equal the number in the
--     pre-image. That is the assertion that catches an atom silently added or
--     silently dropped, which is the G25 defect class, and it is why
--     replay_injected can be introduced MEASURED without anyone taking it on
--     trust that it stayed out of the verdict.
DO $a2$
DECLARE v_pre text; v_new text; n_pre int; n_new int; n int;
BEGIN
  SELECT definition INTO v_pre FROM public.ottoq_schema_snapshots
   WHERE label='0239_pre' AND object_name='ottoq_determinism_pair'
   ORDER BY taken_at DESC LIMIT 1;
  IF v_pre IS NULL THEN RAISE EXCEPTION 'A2 FAILED: the pre-image snapshot is missing'; END IF;
  v_new := pg_get_functiondef('public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid)'::regprocedure);

  n_pre := (length(v_pre) - length(replace(v_pre, 'v_arms[1]', ''))) / length('v_arms[1]');
  n_new := (length(v_new) - length(replace(v_new, 'v_arms[1]', ''))) / length('v_arms[1]');
  IF n_pre <> n_new THEN
    RAISE EXCEPTION 'A2 FAILED: the verdict compares % arm keys, the certified pair compares %', n_new, n_pre;
  END IF;

  IF position('replay_injected' in split_part(v_new, 'v_equal :=', 2)) > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: replay_injected reached the equality list; it is MEASURED, not enforced';
  END IF;

  n := (length(v_new) - length(replace(v_new, 'ottoq_proposal_replay_inject', ''))) / length('ottoq_proposal_replay_inject');
  IF n <> 2 THEN RAISE EXCEPTION 'A2 FAILED: % injection call(s), expected exactly 2 (the -1 bucket and the per-tick one)', n; END IF;

  n := (length(v_new) - length(replace(v_new, 'p_replay_id IS NOT NULL', ''))) / length('p_replay_id IS NOT NULL');
  IF n <> 3 THEN RAISE EXCEPTION 'A2 FAILED: % guard(s) on p_replay_id, expected 3 (depot guard, -1 bucket, per-tick)', n; END IF;
END $a2$;

-- A3  BEHAVIOURAL: AN EMPTY REPLAY IS REFUSED, AND IT IS REFUSED BEFORE ANY
--     ARM EXISTS. Calls the function for real. If the guard were missing this
--     would tick a world inside a migration, which is exactly why it is here.
DO $a3$
DECLARE v_msg text; v_runs_before bigint; v_runs_after bigint;
BEGIN
  SELECT count(*) INTO v_runs_before FROM public.ottoq_sim_runs;
  BEGIN
    PERFORM public.ottoq_determinism_pair_replay(
      p_seed => 909239, p_ticks => 1, p_scenario => 'busy_day',
      p_depot => '11111111-1111-1111-1111-111111111111'::uuid,
      p_sim_start => '2026-09-01 02:00:00+00'::timestamptz, p_arm_budget_s => 5,
      p_replay_id => '00000000-0000-0000-0000-0000000239aa'::uuid);
    RAISE EXCEPTION 'A3 FAILED: an empty replay was accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE '%holds no rows%' THEN
      RAISE EXCEPTION 'A3 FAILED: refused for the wrong reason: %', v_msg;
    END IF;
  END;
  SELECT count(*) INTO v_runs_after FROM public.ottoq_sim_runs;
  IF v_runs_after <> v_runs_before THEN
    RAISE EXCEPTION 'A3 FAILED: % run(s) were created before the guard fired', v_runs_after - v_runs_before;
  END IF;
END $a3$;

-- A4  BEHAVIOURAL: A REPLAY BELONGS TO ITS DEPOT. Captures a real stream off a
--     run on one depot, offers it to a pair on another, and requires a refusal.
--     Without this guard the injected entity_ids match no vehicle, the selector
--     finds nothing, and the pair passes while proving nothing -- a green
--     verdict over an empty experiment, which is the worst failure this
--     harness can have. Cleans up after itself; A5 verifies.
DO $a4$
DECLARE v_src uuid; v_replay uuid := '00000000-0000-0000-0000-0000000239bb'::uuid;
        v_n int; v_msg text; v_other uuid;
BEGIN
  SELECT r.sim_run_id, r.depot_id INTO v_src, v_other
    FROM public.ottoq_sim_runs r
    JOIN public.ottoq_external_proposals p ON p.sim_run_id = r.sim_run_id
   WHERE r.depot_id IS DISTINCT FROM '11111111-1111-1111-1111-111111111111'::uuid
   GROUP BY r.sim_run_id, r.depot_id
   ORDER BY count(*) DESC LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'A4 FAILED: no proposal-carrying run outside the flagship depot to capture from';
  END IF;

  v_n := public.ottoq_proposal_replay_capture(v_src, v_replay);
  IF v_n = 0 THEN RAISE EXCEPTION 'A4 FAILED: captured nothing from run %', v_src; END IF;

  BEGIN
    PERFORM public.ottoq_determinism_pair_replay(
      p_seed => 909239, p_ticks => 1, p_scenario => 'busy_day',
      p_depot => '11111111-1111-1111-1111-111111111111'::uuid,
      p_sim_start => '2026-09-01 02:00:00+00'::timestamptz, p_arm_budget_s => 5,
      p_replay_id => v_replay);
    RAISE EXCEPTION 'A4 FAILED: a replay captured on depot % was accepted for the flagship depot', v_other;
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE '%different depot%' THEN
      RAISE EXCEPTION 'A4 FAILED: refused for the wrong reason: %', v_msg;
    END IF;
  END;

  DELETE FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;
END $a4$;

-- A5  NO RESIDUE. The probe replay is gone and nothing was injected anywhere.
DO $a5$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.ottoq_proposal_replay
   WHERE replay_id IN ('00000000-0000-0000-0000-0000000239aa'::uuid,
                       '00000000-0000-0000-0000-0000000239bb'::uuid);
  IF n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % probe replay row(s) left behind', n; END IF;

  SELECT count(*) INTO n FROM public.ottoq_external_proposals
   WHERE declared_source IN ('replay:00000000-0000-0000-0000-0000000239aa',
                             'replay:00000000-0000-0000-0000-0000000239bb');
  IF n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % proposal(s) were injected by a refused call', n; END IF;
END $a5$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_certification_that_replays_a_recorded_agent_stream',
  now(),
  false,
  'SOLVER_STATE.md 8.3 step 3, the Posture-B driver 0237 said it did not have. '
  'Creates public.ottoq_determinism_pair_replay by eight anchored substitutions '
  'over the certified pair, so it is that function plus injection and nothing '
  'else. Corrects 0237''s own plan: it named ottoq_cert_arm as the loop to wrap, '
  'but ottoq_determinism_pair does not call cert_arm at all -- it drives its own '
  'loop, and it is the only thing that produces the fourteen-atom verdict, so a '
  'replay in cert_arm would have been a replay-driven benchmark called a '
  'certification. Injection goes before the advance at tick v_ticks + 1, measured '
  'on six benchmark arms (a 12-tick arm ends at tick_count 12 with decisions '
  'carrying tick_seq 1..12); the -1 bucket is injected once at run start because '
  'capture stores COALESCE(tick_seq,-1) for pre-0236 streams. h_prop hashes '
  'proposal STATUS, and 0152/0105 quiesce the proposal PRODUCERS but not the '
  'CONSUMER, so an injected stream reaches the certified disposer and arm '
  'equality on h_prop is a statement about disposal, not about insertion. '
  'replay_injected is MEASURED only -- A2 asserts it did not reach the equality '
  'list and that the arm-key comparison count is unchanged from the pre-image. '
  'forces_recert FALSE: nothing existing is edited (A1 pins both the certified '
  'pair and decide_tick), and no scheduled round calls the new function.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 22:22 CT (2026-09-09 03:22 UTC), version 20260909032226,
-- first attempt, all five assertions green -- including the two that CALL the
-- new function and require a refusal:
--
--   A3  an empty replay          refused, 0 runs created before the guard fired
--   A4  a wrong-depot replay     refused, and refused for the right reason
--   A5  no residue               0 probe replay rows, 0 injected proposals
--   ottoq_determinism_pair md5   e323bf87d0fbd9d3778bbda7c8f94ba7   UNCHANGED
--   ottoq_decide_tick md5        ae98f71b879a0a11bdf366d21ff5b4eb   UNCHANGED
--   recert floor                 2026-09-09 03:15:07  (0238's, unmoved)
--
-- ---------------------------------------------------------------------------
-- AND THEN IT WAS USED. THE PROOF IS db/checks/0157
-- ---------------------------------------------------------------------------
-- Five pairs on the grid fixture (seed 239001, 6 ticks, grid_smoke, depot
-- aacd0bb0-..., sim_start 2026-09-01 02:00:00+00), differing ONLY in
-- p_replay_id:
--
--   P0  no replay              passed   h_prop d41d8cd9 (md5 of '')  h_dec c16074c6
--   P1  replay R               passed   h_prop c270c2c5             h_dec 4fe7b305
--   P2  replay R again         passed   identical to P1, separate pair
--   P3  replay R'              passed   h_prop MOVED, h_dec did not
--   P4  replay R''             passed   h_prop MOVED, h_dec MOVED
--
-- P1 is the Posture-B sentence. P0 is the control that it was not a no-op: a
-- certification today sees NO proposals at all, so its h_prop is literally the
-- md5 of the empty string, and P1's h_dec differs from P0's with every other
-- input held. P2 is between-pair reproducibility. P3 perturbed a proposal the
-- disposer never read and moved h_prop only; P4 perturbed one it ENACTED and
-- moved both. h_prop is what the agent said; h_dec is what the agent changed.
--
-- The disposer's own ledger for P1 arm A (run ac0f7263-5208-47d4-ade0-1630ed2d73d3):
-- of 24 replayed proposals, 4 ENACTED, 5 SUPERSEDED (honest pre-emption), 15
-- still PENDING at run end. Not one dropped silently.
--
-- ---------------------------------------------------------------------------
-- STILL OWED
-- ---------------------------------------------------------------------------
--   * a REAL captured stream. The proof used a synthetic one, because no run in
--     this database has ever carried a tick-stamped proposal -- 0236 shipped
--     hours before and every run since has been a certification, which quiesces
--     the producers. The capture half is proven by 0237's assertions; the first
--     production run with a live proposer closes it for real.
--   * replay_injected promoted from MEASURED to ENFORCED, on the gate stated
--     above: one flagship-scale replay pair reporting the same count on both
--     arms. Every pair so far reports 24 and 24.
--   * the same proof at flagship scale. The grid is a real depot to the engine
--     (0153) but it is four vehicles.
--   * 0238's recert round. Until it completes no column is green, this one
--     included -- what is proven here is that the rig behaves, not that the
--     standing canon holds.
