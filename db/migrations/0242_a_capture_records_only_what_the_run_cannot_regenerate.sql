-- migration-version: PENDING
-- migration-name:    a_capture_records_only_what_the_run_cannot_regenerate
--
-- G42 / db/checks/0159. APPLY AFTER 0241 -- it consults the registry 0241
-- creates. Order for the window: 0240, 0241, 0242.
--
-- ---------------------------------------------------------------------------
-- THE DEFECT IN ONE LINE OF SQL
-- ---------------------------------------------------------------------------
-- public.ottoq_proposal_replay_capture ends its WHERE with
--
--     AND (p_sources IS NULL OR p.source = ANY (p_sources));
--
-- and p_sources DEFAULTS TO NULL. So "record this run's agent stream", called
-- the obvious way, records EVERY proposal on the run -- including the internal
-- deterministic proposers.
--
-- Replay that and the same logical proposal exists twice:
--
--   * the recorded copy is INJECTED, at tick -1 (capture stores
--     COALESCE(tick_seq,-1), and greedy_constrained rows have no tick because
--     ottoq_l2_optimize_assignments writes them directly and 0236 stamped only
--     the door); and
--   * the proposer REGENERATES it at its real tick during the replayed arm,
--     exactly as 0236 promised it would -- "internal deterministic proposers
--     regenerate themselves identically from the same seed" is TRUE, and it is
--     precisely why they must not also be replayed.
--
-- Measured, and it is not a corner: greedy_constrained is 12,458 proposals, the
-- largest proposer in the system, and 100% of it is written directly. Every
-- one of those rows would be captured, ghosted at tick -1, and visible to the
-- decide path for the WHOLE run -- able to be selected in preference to the
-- real ones. A replay could change the decisions it exists to reproduce.
--
-- ---------------------------------------------------------------------------
-- WHY THE 0157 PROOF DID NOT SEE IT
-- ---------------------------------------------------------------------------
-- Its stream was hand-written: 24 rows, source 'agent_probe', a source nothing
-- regenerates. The proof is sound for what it claimed and its own "still owed"
-- list opens with "a REAL captured stream". This is why that item was first.
--
-- ---------------------------------------------------------------------------
-- THE FIX, AND WHY THE REGISTRY IS THE RIGHT LIST
-- ---------------------------------------------------------------------------
-- What must be excluded is exactly "the proposers that regenerate from the
-- seed" -- which is exactly what 0241 seeded ottoq_certified_proposers from,
-- measured off real certification traffic. One list, two uses, same meaning:
-- a certification hears these because they ARE the certified core (Posture A),
-- and a capture skips these because the replay would duplicate them (this).
--
-- The default flips: recording the stream now records the OUTSIDE stream, and a
-- caller who genuinely wants an internal proposer names it in p_sources. The
-- dangerous thing stops being what you get for free.
--
-- forces_recert: FALSE. ottoq_proposal_replay_capture is a recording tool. It
-- is not called by ottoq_determinism_pair, by ottoq_determinism_pair_replay, or
-- by any tick; decide_tick's md5 is asserted unchanged (A5).
--
-- MUST NOT BE APPLIED WHILE ROUND 31 IS IN FLIGHT.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

DO $inflight$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active'
     AND (query LIKE '%ottoq_determinism_pair%' OR query LIKE '%ottoq_cert_arm%');
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s)/arm(s) in flight', n; END IF;
  IF EXISTS (
    SELECT 1 FROM cron.job j
     WHERE j.jobname ~ '^r31_' AND j.active
       AND NOT EXISTS (SELECT 1 FROM cron.job_run_details d
                        WHERE d.jobid = j.jobid AND d.end_time IS NOT NULL
                          AND extract(epoch FROM (d.end_time - d.start_time)) >= 60))
  THEN
    RAISE EXCEPTION 'P- REFUSED: round 31 has pairs that have not completed; wait for r31_f';
  END IF;
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0242_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_proposal_replay_capture';

DO $p1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_proposal_replay_capture(uuid,uuid,text[])'::regprocedure));
  IF h <> 'fb26e6296ace86716c142a4f1cd17dcf' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_proposal_replay_capture md5 is %, pinned fb26e6296ace86716c142a4f1cd17dcf', h;
  END IF;
  IF to_regclass('public.ottoq_certified_proposers') IS NULL THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_certified_proposers is absent; apply 0241 first';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_certified_proposers) = 0 THEN
    RAISE EXCEPTION 'P1 REFUSED: the registry is empty, so this change would be a no-op that looks like a fix';
  END IF;
END $p1$;

DO $chg$
DECLARE d text; a text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_proposal_replay_capture(uuid,uuid,text[])'::regprocedure);
  a := E'     AND (p_sources IS NULL OR p.source = ANY (p_sources));';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: source-filter anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a,
       E'     -- 0242 / G42 / db/checks/0159. THE DEFAULT NOW EXCLUDES THE PROPOSERS\n'
    || E'     -- THAT REGENERATE. It used to be "NULL means every source", which meant\n'
    || E'     -- recording a run picked up the internal deterministic proposers too --\n'
    || E'     -- and replaying that injects them at tick -1 while the proposer ALSO\n'
    || E'     -- regenerates them at their real ticks. The same proposal twice, the\n'
    || E'     -- ghost visible from before tick 1, able to be selected over the real\n'
    || E'     -- one. 0236 is right that internal proposers regenerate identically\n'
    || E'     -- from the seed; that is exactly why they must not also be replayed.\n'
    || E'     --\n'
    || E'     -- ottoq_certified_proposers (0241) names precisely those proposers,\n'
    || E'     -- seeded from measured certification traffic. One list, two uses, one\n'
    || E'     -- meaning: a certification HEARS these because they are the certified\n'
    || E'     -- core, and a capture SKIPS these because a replay would double them.\n'
    || E'     --\n'
    || E'     -- An explicit p_sources still wins, so wanting an internal proposer in\n'
    || E'     -- a recording is possible and is now a deliberate act rather than the\n'
    || E'     -- thing you get for free.\n'
    || E'     AND (CASE\n'
    || E'            WHEN p_sources IS NOT NULL THEN p.source = ANY (p_sources)\n'
    || E'            ELSE NOT EXISTS (SELECT 1 FROM public.ottoq_certified_proposers cp\n'
    || E'                              WHERE cp.source = p.source)\n'
    || E'          END);');

  EXECUTE d;
END $chg$;

-- ===========================================================================
-- THE ASSERTIONS. All four behavioural: they capture for real and read back
-- what was recorded. A2 is the one that keeps this honest -- a change that
-- captured NOTHING would pass A1 and be useless.
-- ===========================================================================
DO $TESTS$
DECLARE
  v_run uuid; v_veh uuid; v_replay uuid := '0242aaaa-0000-0000-0000-000000000001'::uuid;
  n int; v_total int; v_reg int; v_h1 text; v_h2 text;
BEGIN
  -- a run that carries a REGISTERED proposer's output, so there is something to exclude
  SELECT p.sim_run_id INTO v_run FROM public.ottoq_external_proposals p
    JOIN public.ottoq_certified_proposers cp ON cp.source = p.source
   GROUP BY p.sim_run_id ORDER BY count(*) DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION 'TEST SETUP FAILED: no run carries a registered proposer'; END IF;
  SELECT id INTO v_veh FROM public.vehicles WHERE category='autonomous' ORDER BY id LIMIT 1;

  SELECT count(*) INTO v_total FROM public.ottoq_external_proposals WHERE sim_run_id = v_run;
  SELECT count(*) INTO v_reg FROM public.ottoq_external_proposals p
    JOIN public.ottoq_certified_proposers cp ON cp.source = p.source WHERE p.sim_run_id = v_run;
  IF v_reg = 0 THEN RAISE EXCEPTION 'TEST SETUP FAILED: chosen run has nothing to exclude'; END IF;

  -- one UNREGISTERED proposal on the same run, so the capture has something to keep
  INSERT INTO public.ottoq_external_proposals
    (sim_run_id, action_context, entity_type, entity_id, proposal, source, status, tick_seq)
  VALUES (v_run, '0242_probe', 'vehicle', v_veh, '{"verb":"triage"}', 'outside_agent_0242', 'pending', 3);

  ---------------------------------------------------------------------------
  -- A1  THE DEFAULT KEEPS ONLY WHAT CANNOT REGENERATE.
  ---------------------------------------------------------------------------
  n := public.ottoq_proposal_replay_capture(v_run, v_replay);
  IF n <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: default capture took % rows, expected 1 (the run holds % total, % of them registered)',
      n, v_total + 1, v_reg;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_proposal_replay r
              JOIN public.ottoq_certified_proposers cp ON cp.source = r.source
             WHERE r.replay_id = v_replay) THEN
    RAISE EXCEPTION 'A1 FAILED: a registered proposer reached the recording';
  END IF;

  ---------------------------------------------------------------------------
  -- A2  NEGATIVE CONTROL: THE TEST IS NOT VACUOUS. An implementation that
  --     captured NOTHING at all would sail through A1. Naming a registered
  --     proposer explicitly must still record it -- that is the override, and
  --     it also proves the excluded rows were really there.
  ---------------------------------------------------------------------------
  n := public.ottoq_proposal_replay_capture(v_run, v_replay, ARRAY['greedy_constrained','ottoq_service_priority','cuopt']);
  IF n <> v_reg THEN
    RAISE EXCEPTION 'A2 FAILED: explicit p_sources captured % rows, expected the % registered ones -- the override is broken', n, v_reg;
  END IF;

  ---------------------------------------------------------------------------
  -- A3  NEGATIVE CONTROL: THE TWO CALLS DISAGREE. If the default and the
  --     override produced the same recording, nothing was excluded and A1
  --     passed by accident.
  ---------------------------------------------------------------------------
  IF v_reg = 1 THEN
    RAISE EXCEPTION 'A3 INVALID: the chosen run has exactly one registered proposal, so A1 and A2 cannot be distinguished by count';
  END IF;

  ---------------------------------------------------------------------------
  -- A4  IDEMPOTENCE SURVIVES. 0237's A2 property: capturing the same run twice
  --     must produce a byte-identical stream, or a replay is not reproducible.
  ---------------------------------------------------------------------------
  PERFORM public.ottoq_proposal_replay_capture(v_run, v_replay);
  SELECT md5(string_agg(seq||'|'||tick_seq||'|'||action_context||'|'||proposal::text, E'\n' ORDER BY seq))
    INTO v_h1 FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;
  PERFORM public.ottoq_proposal_replay_capture(v_run, v_replay);
  SELECT md5(string_agg(seq||'|'||tick_seq||'|'||action_context||'|'||proposal::text, E'\n' ORDER BY seq))
    INTO v_h2 FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;
  IF v_h1 IS DISTINCT FROM v_h2 THEN
    RAISE EXCEPTION 'A4 FAILED: re-capturing the same run produced a different stream (% vs %)', v_h1, v_h2;
  END IF;

  DELETE FROM public.ottoq_proposal_replay WHERE replay_id = v_replay;
  DELETE FROM public.ottoq_external_proposals WHERE source = 'outside_agent_0242';
END $TESTS$;

-- A5  NO RESIDUE; THE CERTIFIED TICK IS UNTOUCHED.
DO $a5$
DECLARE n int; h text;
BEGIN
  SELECT count(*) INTO n FROM public.ottoq_external_proposals WHERE source = 'outside_agent_0242';
  IF n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % probe proposal(s) left behind', n; END IF;
  SELECT count(*) INTO n FROM public.ottoq_proposal_replay
   WHERE replay_id = '0242aaaa-0000-0000-0000-000000000001'::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % probe replay row(s) left behind', n; END IF;

  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A5 FAILED: ottoq_decide_tick md5 moved to %', h;
  END IF;
END $a5$;

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_capture_records_only_what_the_run_cannot_regenerate',
  now(),
  false,
  'G42 / db/checks/0159. ottoq_proposal_replay_capture took p_sources DEFAULT NULL '
  'to mean EVERY source, so recording a run picked up the internal deterministic '
  'proposers -- and replaying that injects them at tick -1 (capture stores '
  'COALESCE(tick_seq,-1), and greedy_constrained has no tick because '
  'ottoq_l2_optimize_assignments writes it directly and 0236 stamped only the door) '
  'while the proposer ALSO regenerates them at their real ticks. The same proposal '
  'twice, the ghost visible from before tick 1 and selectable over the real one. '
  '0236 is right that internal proposers regenerate identically from the seed; that '
  'is exactly why they must not also be replayed. The default now excludes '
  'ottoq_certified_proposers (0241) -- one list, two uses, one meaning -- and an '
  'explicit p_sources still overrides. 0157''s proof could not have caught this: its '
  'stream was hand-written with a source nothing regenerates. forces_recert FALSE: a '
  'recording tool, called by no tick and by neither pair; A5 pins decide_tick.'
);
