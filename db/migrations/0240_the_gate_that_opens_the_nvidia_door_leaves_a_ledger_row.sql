-- migration-version: 20260909051529
-- migration-name:    the_gate_that_opens_the_nvidia_door_leaves_a_ledger_row
--
-- G40 / db/checks/0158, half (a). Half (b) shipped 2026-09-08 22:42 CT as edge
-- versions ottoq-orchestrate-tick v9 and ottoq-assign-optimize v5, and is
-- verified: both now write cuopt_invocation_log on every pass, abstentions
-- included.
--
-- This is the database's half, and it exists because half (b) is not enough.
--
-- ---------------------------------------------------------------------------
-- WHY AN EDGE-SIDE ROW LEAVES A HOLE
-- ---------------------------------------------------------------------------
-- The edge row only exists IF THE FUNCTION RAN. ottoq_cron_tick dispatches with
-- net.http_post, which is fire-and-forget: it returns a request id and never
-- learns the outcome. So every way the request can die between the database and
-- the function -- the function 500s before its first statement, the platform
-- rate-limits it, the JWT is rejected, pg_net drops it, the 25 s timeout expires
-- -- produces exactly the same evidence as "the gate never opened": nothing.
--
-- That is the same failure this whole finding is about. A ledger that cannot
-- distinguish "did not happen" from "happened invisibly" is not a ledger, and
-- CLAUDE.md rule 6 asks it to distinguish precisely those.
--
-- So the DISPATCH becomes a fact on the database side, where it cannot be lost:
-- a row saying the gate opened and a request was queued, carrying the pg_net
-- request id so it can be joined to net._http_response while that row survives.
--
-- ---------------------------------------------------------------------------
-- AND THE CLOSED GATE IS A FACT TOO
-- ---------------------------------------------------------------------------
-- A row is also written when the gate is CLOSED. That is not symmetry for its
-- own sake: `ottoq_policy_get(<run>, 'cuopt_propose_enabled', 1)` DEFAULTS TO 1,
-- so a run has to opt out, and the difference between "a run was live and chose
-- not to call cuOpt" and "no run was live at all" is exactly what a claim of the
-- form "the endpoint has not been called since X" turns on. db/checks/0158 had
-- to reconstruct that difference from cron durations and a policy_params row,
-- nine days after the fact. It should not have had to.
--
-- Volume is bounded by production activity, not by the cron: line 5 of
-- ottoq_cron_tick returns before any of this unless a non-cert run is RUNNING.
-- Measured over the last ten days that was true for 10 of 5,996 fires.
--
-- ---------------------------------------------------------------------------
-- stage = 'sql_gate', NOT A NEW VALUE
-- ---------------------------------------------------------------------------
-- cuopt_invocation_log has CHECK (stage = ANY (ARRAY['sql_gate','edge'])). A
-- new stage would mean altering that constraint, and it would be wrong anyway:
-- SOLVER_STATE.md 9.1 defines sql_gate as "the in-database gate", and this is
-- exactly that gate for exactly this door. source_note tells the two gates
-- apart. No schema change, and 9.1's two-stage table keeps its meaning.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE
-- ---------------------------------------------------------------------------
-- ottoq_cron_tick is not on the certified tick path -- a certification arm
-- drives ottoq_sim_advance_tick directly, and line 5 of this function refuses to
-- act for run_by='cert_harness' at all (0106). ottoq_decide_tick's md5 is
-- asserted unchanged (A4), and nothing a canon is measured over is touched.
--
-- The recert floor is standing at 2026-09-09 03:15:07 because 0238 moved it;
-- round 31 is running against that. THIS FILE MUST NOT BE APPLIED UNTIL ROUND 31
-- COMPLETES (last pair r31_f fires 04:58 UTC, expected done ~05:20 UTC /
-- 12:20 AM CT). The P- block refuses on its own, but the schedule is written
-- here so nobody has to rediscover it.
--
-- ---------------------------------------------------------------------------
-- A FAILING LEDGER MUST NEVER FAIL A TICK
-- ---------------------------------------------------------------------------
-- Both inserts sit in their own BEGIN/EXCEPTION block and warn rather than
-- raise. APPLYING.md's rule is stated for decide_tick and the reasoning carries:
-- a rolled-back tick reads as "succeeded" in cron and does nothing. An audit row
-- is never worth losing an orchestration tick over.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

DO $inflight$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active'
     AND (query LIKE '%ottoq_determinism_pair%' OR query LIKE '%ottoq_cert_arm%');
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s)/arm(s) in flight', n; END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r31_' AND active) THEN
    -- Round 31 was scheduled by 0238's recert. A pair that has not fired yet is
    -- as blocking as one in flight: it would run against a function this file
    -- changed halfway through the round.
    IF EXISTS (
      SELECT 1 FROM cron.job j
       WHERE j.jobname ~ '^r31_' AND j.active
         AND NOT EXISTS (SELECT 1 FROM cron.job_run_details d
                          WHERE d.jobid = j.jobid AND d.end_time IS NOT NULL
                            AND extract(epoch FROM (d.end_time - d.start_time)) >= 60))
    THEN
      RAISE EXCEPTION 'P- REFUSED: round 31 has pairs that have not completed; wait for r31_f';
    END IF;
  END IF;
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0240_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_cron_tick';

DO $p1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure));
  IF h <> '0562fbd6579524bf71f6c733b9295268' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_cron_tick md5 is %, pinned 0562fbd6579524bf71f6c733b9295268', h;
  END IF;
  -- the stage value this file writes must already be legal, or the first
  -- production dispatch fails its ledger write silently in a WARNING.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='public.cuopt_invocation_log'::regclass
       AND conname='cuopt_invocation_log_stage_check'
       AND pg_get_constraintdef(oid) LIKE '%sql_gate%') THEN
    RAISE EXCEPTION 'P1 REFUSED: cuopt_invocation_log does not accept stage=''sql_gate''';
  END IF;
END $p1$;

DO $chg$
DECLARE d text; a text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure);

  -- 1. two locals. Replacing the WHOLE declaration line rather than appending to
  --    it: ottoq_cert_arm's DECLARE is one line of six declarations and 0235
  --    commented three of them out by appending a trailing comment. Never again.
  a := 'DECLARE k text; base text := ''https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1'';';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: declare anchor occurs % times', n; END IF;
  d := replace(d, a, a
    || E'\n        v_prun uuid;   -- 0240: the run the cuOpt gate is read off'
    || E'\n        v_req  bigint; -- 0240: pg_net request id, so the row names its dispatch');

  -- 2. the gate itself. Anchored on the entire IF..END IF so the rewrite cannot
  --    land on a lookalike, and so the subquery is evaluated ONCE into v_prun
  --    instead of three times.
  a := E'  IF ottoq_policy_get((SELECT r.sim_run_id FROM ottoq_sim_runs r\n'
    || E'                        WHERE r.status=''running'' AND COALESCE(r.run_by,'''') <> ''cert_harness''\n'
    || E'                        ORDER BY r.started_at DESC LIMIT 1),\n'
    || E'                      ''cuopt_propose_enabled'', 1) > 0 THEN\n'
    || E'  PERFORM net.http_post(\n'
    || E'    url := base || ''/ottoq-orchestrate-tick'',\n'
    || E'    headers := jsonb_build_object(''Content-Type'',''application/json'',''Authorization'',''Bearer ''||k,''apikey'',k),\n'
    || E'    body := jsonb_build_object(''depot_id'',''11111111-1111-1111-1111-111111111111'',''submit'',true,''shadow'',false),\n'
    || E'    timeout_milliseconds := 25000);\n'
    || E'  END IF;';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: gate anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a,
       E'  -- 0240 / G40 / db/checks/0158: resolved ONCE, so the gate, the ledger row\n'
    || E'  -- and any future reader all name the same run.\n'
    || E'  SELECT r.sim_run_id INTO v_prun FROM ottoq_sim_runs r\n'
    || E'   WHERE r.status=''running'' AND COALESCE(r.run_by,'''') <> ''cert_harness''\n'
    || E'   ORDER BY r.started_at DESC LIMIT 1;\n'
    || E'  IF ottoq_policy_get(v_prun, ''cuopt_propose_enabled'', 1) > 0 THEN\n'
    || E'  SELECT net.http_post(\n'
    || E'    url := base || ''/ottoq-orchestrate-tick'',\n'
    || E'    headers := jsonb_build_object(''Content-Type'',''application/json'',''Authorization'',''Bearer ''||k,''apikey'',k),\n'
    || E'    body := jsonb_build_object(''depot_id'',''11111111-1111-1111-1111-111111111111'',''submit'',true,''shadow'',false),\n'
    || E'    timeout_milliseconds := 25000) INTO v_req;\n'
    || E'  -- 0240: the DISPATCH is the database''s to record. net.http_post is\n'
    || E'  -- fire-and-forget, so every way the request can die before the function\n'
    || E'  -- runs looks exactly like the gate never opening. This row is the\n'
    || E'  -- difference. Whether NVIDIA was actually called is the EDGE row''s to\n'
    || E'  -- say (orchestrate-tick v9+); the two together are the full record.\n'
    || E'  BEGIN\n'
    || E'    INSERT INTO public.cuopt_invocation_log\n'
    || E'      (sim_run_id, stage, tick_seq, called_at, source_note, detail)\n'
    || E'    SELECT v_prun, ''sql_gate'', r.tick_count, now(), ''cron_tick:orchestrate_dispatch'',\n'
    || E'           jsonb_build_object(''request_id'', v_req, ''fn'', ''ottoq-orchestrate-tick'',\n'
    || E'                              ''gate'', ''open'', ''ledgered_by'', ''G40/0158'')\n'
    || E'      FROM ottoq_sim_runs r WHERE r.sim_run_id = v_prun;\n'
    || E'  EXCEPTION WHEN OTHERS THEN\n'
    || E'    RAISE WARNING ''0240 dispatch ledger failed (non-fatal): % %'', SQLSTATE, SQLERRM;\n'
    || E'  END;\n'
    || E'  ELSIF v_prun IS NOT NULL THEN\n'
    || E'  -- 0240: a CLOSED gate is a fact too. cuopt_propose_enabled defaults to 1,\n'
    || E'  -- so a run has to opt out, and "a run was live and chose not to call cuOpt"\n'
    || E'  -- is a different sentence from "no run was live". 0158 had to reconstruct\n'
    || E'  -- that difference from cron durations nine days after the fact.\n'
    || E'  BEGIN\n'
    || E'    INSERT INTO public.cuopt_invocation_log\n'
    || E'      (sim_run_id, stage, tick_seq, called_at, abstained_reason, source_note, detail)\n'
    || E'    SELECT v_prun, ''sql_gate'', r.tick_count, now(), ''policy_disabled'',\n'
    || E'           ''cron_tick:orchestrate_dispatch'',\n'
    || E'           jsonb_build_object(''fn'', ''ottoq-orchestrate-tick'', ''gate'', ''closed'',\n'
    || E'                              ''ledgered_by'', ''G40/0158'')\n'
    || E'      FROM ottoq_sim_runs r WHERE r.sim_run_id = v_prun;\n'
    || E'  EXCEPTION WHEN OTHERS THEN\n'
    || E'    RAISE WARNING ''0240 gate-closed ledger failed (non-fatal): % %'', SQLSTATE, SQLERRM;\n'
    || E'  END;\n'
    || E'  END IF;');

  EXECUTE d;
END $chg$;

-- ===========================================================================
-- THE ASSERTIONS.
--
-- The honest way to test this end to end would be to call ottoq_cron_tick()
-- and watch a row appear. That is not available: line 5 returns unless a
-- non-cert run is RUNNING, and manufacturing one inside a migration would make
-- ottoq_world_advance() tick a fake world. So A2 and A3 do the next best thing
-- and the thing 0239 A5 established -- they LIFT the ledger blocks out of the
-- live catalog definition and EXECUTE them, rather than testing a retyped copy.
-- If CHG wrote something different from what is asserted here, this runs the
-- difference.
--
-- Note what that buys: the lifted block carries its own
-- EXCEPTION WHEN OTHERS THEN RAISE WARNING, so a broken INSERT would be
-- swallowed exactly as it would be in production -- and the assertion still
-- fires, because it checks for the ROW, not for an absent exception. A test
-- that only checked "it did not raise" would pass on a ledger that never wrote.
-- ===========================================================================
DO $TESTS$
DECLARE
  v_def text; v_open text; v_closed text; v_run uuid; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_cron_tick()'::regprocedure);

  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'TEST SETUP FAILED: no run to bind v_prun to'; END IF;

  ---------------------------------------------------------------------------
  -- A1  THE SHAPE. Cheap, and it names what A2/A3 then execute.
  ---------------------------------------------------------------------------
  n := (length(v_def) - length(replace(v_def, 'cuopt_invocation_log', ''))) / length('cuopt_invocation_log');
  IF n <> 2 THEN RAISE EXCEPTION 'A1 FAILED: % ledger reference(s), expected exactly 2 (open + closed)', n; END IF;
  IF position('SELECT net.http_post(' in v_def) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the dispatch still uses PERFORM, so no request id reaches the ledger';
  END IF;
  IF position('ottoq_policy_get(v_prun,' in v_def) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the gate does not read the run resolved into v_prun';
  END IF;

  ---------------------------------------------------------------------------
  -- A2  THE OPEN-GATE ROW, EXECUTED. Lifted verbatim from the live definition.
  ---------------------------------------------------------------------------
  v_open := split_part(v_def,
    E'  BEGIN\n    INSERT INTO public.cuopt_invocation_log\n      (sim_run_id, stage, tick_seq, called_at, source_note, detail)', 2);
  v_open := split_part(v_open, E'  ELSIF v_prun IS NOT NULL THEN', 1);
  IF v_open = '' THEN RAISE EXCEPTION 'A2 FAILED: could not lift the open-gate ledger block'; END IF;
  v_open := 'BEGIN INSERT INTO public.cuopt_invocation_log (sim_run_id, stage, tick_seq, called_at, source_note, detail)'
         || v_open;

  EXECUTE 'DO $probe$ DECLARE v_prun uuid := ' || quote_literal(v_run) || '::uuid; v_req bigint := -240; '
       || v_open || ' $probe$;';

  SELECT count(*) INTO n FROM public.cuopt_invocation_log
   WHERE source_note = 'cron_tick:orchestrate_dispatch'
     AND detail->>'gate' = 'open' AND detail->>'request_id' = '-240';
  IF n <> 1 THEN
    RAISE EXCEPTION 'A2 FAILED: the open-gate block wrote % row(s), expected 1 (a swallowed INSERT looks like this)', n;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cuopt_invocation_log
                  WHERE detail->>'request_id' = '-240' AND stage = 'sql_gate'
                    AND sim_run_id = v_run AND abstained_reason IS NULL) THEN
    RAISE EXCEPTION 'A2 FAILED: the open-gate row is not stage=sql_gate on the resolved run with no abstention';
  END IF;

  ---------------------------------------------------------------------------
  -- A3  THE CLOSED-GATE ROW, EXECUTED. Its abstained_reason is what makes
  --     "a run chose not to" distinguishable from "no run existed".
  ---------------------------------------------------------------------------
  v_closed := split_part(v_def,
    E'  BEGIN\n    INSERT INTO public.cuopt_invocation_log\n      (sim_run_id, stage, tick_seq, called_at, abstained_reason, source_note, detail)', 2);
  v_closed := split_part(v_closed, E'  END IF;', 1);
  IF v_closed = '' THEN RAISE EXCEPTION 'A3 FAILED: could not lift the closed-gate ledger block'; END IF;
  v_closed := 'BEGIN INSERT INTO public.cuopt_invocation_log (sim_run_id, stage, tick_seq, called_at, abstained_reason, source_note, detail)'
           || v_closed || ' END;';

  EXECUTE 'DO $probe$ DECLARE v_prun uuid := ' || quote_literal(v_run) || '::uuid; v_req bigint := -240; '
       || v_closed || ' $probe$;';

  SELECT count(*) INTO n FROM public.cuopt_invocation_log
   WHERE source_note = 'cron_tick:orchestrate_dispatch'
     AND detail->>'gate' = 'closed' AND abstained_reason = 'policy_disabled'
     AND sim_run_id = v_run;
  IF n <> 1 THEN RAISE EXCEPTION 'A3 FAILED: the closed-gate block wrote % row(s), expected 1', n; END IF;

  ---------------------------------------------------------------------------
  -- A4  NEGATIVE CONTROL: THE TWO ROWS ARE TELLING DIFFERENT STORIES.
  --     An implementation that wrote the same row on both branches would pass
  --     A2 and A3 and be useless -- the whole point is the distinction.
  ---------------------------------------------------------------------------
  IF (SELECT count(DISTINCT COALESCE(abstained_reason,'(none)')) FROM public.cuopt_invocation_log
       WHERE source_note = 'cron_tick:orchestrate_dispatch') <> 2 THEN
    RAISE EXCEPTION 'A4 FAILED: the open and closed rows are indistinguishable on abstained_reason';
  END IF;

  ---------------------------------------------------------------------------
  -- CLEAN UP. A5 verifies.
  ---------------------------------------------------------------------------
  DELETE FROM public.cuopt_invocation_log WHERE source_note = 'cron_tick:orchestrate_dispatch';
END $TESTS$;

-- A5  NO RESIDUE, AND THE CERTIFIED TICK IS UNTOUCHED.
DO $a5$
DECLARE n int; h text;
BEGIN
  SELECT count(*) INTO n FROM public.cuopt_invocation_log
   WHERE source_note = 'cron_tick:orchestrate_dispatch';
  IF n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % probe ledger row(s) left behind', n; END IF;

  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A5 FAILED: ottoq_decide_tick md5 moved to %', h;
  END IF;
END $a5$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'the_gate_that_opens_the_nvidia_door_leaves_a_ledger_row',
  now(),
  false,
  'G40 / db/checks/0158, half (a). ottoq_cron_tick now writes cuopt_invocation_log '
  'when it dispatches to ottoq-orchestrate-tick, and again -- with '
  'abstained_reason=''policy_disabled'' -- when the gate is shut. Half (b), the edge '
  'rows, shipped as orchestrate-tick v9 and assign-optimize v5 and is verified; this '
  'half exists because net.http_post is fire-and-forget, so a request that dies '
  'between the database and the function is indistinguishable from a gate that never '
  'opened, which is the same failure the finding is about. stage=''sql_gate'' rather '
  'than a new value: the CHECK allows only sql_gate and edge, and SOLVER_STATE.md 9.1 '
  'already defines sql_gate as the in-database gate. Both inserts warn rather than '
  'raise -- an audit row is never worth losing an orchestration tick over. '
  'forces_recert FALSE: ottoq_cron_tick refuses to act for run_by=''cert_harness'' at '
  'line 5 (0106) and is not on the certified tick path; A5 pins decide_tick md5. A2 '
  'and A3 LIFT the two ledger blocks out of the live catalog and EXECUTE them, and '
  'check for the ROW rather than for an absent exception -- the blocks swallow their '
  'own errors, so a test that only checked "it did not raise" would pass on a ledger '
  'that never wrote.'
);
