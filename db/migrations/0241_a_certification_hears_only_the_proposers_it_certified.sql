-- migration-version: 20260909051812
-- migration-name:    a_certification_hears_only_the_proposers_it_certified
--
-- POSTURE A. SOLVER_STATE.md 8.3 step 2, and the last open item in that
-- sequence -- step 1 shipped as 0199, step 3 shipped tonight (0236/0237/0238/
-- 0239, proof in db/checks/0157).
--
-- 8.2's words are "pin cert runs to deterministic proposers". This file takes
-- them literally, and it is NOT the file I first wrote.
--
-- ===========================================================================
-- THE DRAFT THIS REPLACES WAS WRONG, AND MEASURING IS WHAT CAUGHT IT
-- ===========================================================================
-- The obvious Posture A is "a certification refuses the agent door". I wrote
-- it, named it 0241, and then measured what actually comes through that door.
--
--   372 proposals, across 148 CERTIFICATION runs, 2026-09-06 -> 2026-09-09,
--   the most recent forty minutes before this was written.
--
-- The caller is public.ottoq_service_priority_propose, and it is called from
-- public.ottoq_sim_decide_and_dispatch -- INSIDE THE CERTIFIED TICK. It is an
-- internal deterministic proposer that happens to submit through the same door
-- an external agent would use, which is why its rows carry
-- submitted_by_role='system:db:postgres'.
--
-- So the obvious version would have silently deleted a proposer the
-- certification currently exercises, narrowed what the harness tests without
-- saying so, and shipped under a "forces_recert FALSE" header that was simply
-- false. It would have passed a textual review.
--
-- Two candidate discriminators were tried and both are wrong, recorded here so
-- nobody re-derives them:
--
--   declared_source IS NOT 'replay:%'   -- wrong: the internal proposers leave
--                                          declared_source NULL (cuopt,
--                                          greedy_constrained and
--                                          ottoq_service_priority all appear as
--                                          "(null) <- <source>"), because only
--                                          the door stamps it. Counts the
--                                          certified core as a foreign agent.
--   submitted_by_role IS NOT NULL       -- wrong for the same reason in
--                                          reverse: ottoq_service_priority DOES
--                                          come through the door, 372 times.
--
-- "Internal" and "external" are not visible in any column. What is visible, and
-- what actually matters, is WHICH PROPOSER IT IS.
--
-- ===========================================================================
-- SO: A REGISTRY, SEEDED FROM WHAT CERTIFICATIONS HAVE ACTUALLY HEARD
-- ===========================================================================
-- Measured over every proposal ever written against a run_by='cert_harness'
-- run:
--
--   source                   rows     runs  how it arrives
--   ----------------------  ------  ------  ----------------------------------
--   greedy_constrained      12,403     542  direct insert
--   ottoq_service_priority   1,904     821  direct insert AND through the door
--   cuopt                        1       1  direct insert (2026-08-30)
--   agent_probe                192       8  system:replay (0239's Posture-B proof)
--
-- The first three are the deterministic core the certification is FOR. They are
-- the seed. agent_probe is deliberately NOT seeded -- a replay is admitted by
-- being a replay, not by being on a list, which keeps the two mechanisms
-- independent.
--
-- (Worth recording rather than fixing here: ottoq_service_priority reaches the
-- table by BOTH paths. One proposer, two write paths, one of which stamps
-- provenance and one of which does not. That is a real inconsistency and it is
-- not this file's concern.)
--
-- ===========================================================================
-- WHAT THIS IS AND IS NOT
-- ===========================================================================
-- It is CERTIFICATION HYGIENE, not a security boundary. For a system caller,
-- ottoq_submit_external_proposal takes p_source from the caller, so a proposer
-- determined to be heard could name itself 'cuopt'. That is fine and it is not
-- the threat model: G2 already settled authorization, and what Posture A
-- protects against is an agent we built proposing into a certification BY
-- ACCIDENT and turning a clean determinism failure into a three-hour hunt for
-- nondeterminism that was never there.
--
-- An operator is refused outright: for a non-system caller the server sets
-- v_source := 'operator:<uuid>', which can never be a registry row.
--
-- ===========================================================================
-- forces_recert: FALSE, AND NOW THAT IS TRUE RATHER THAN HOPED
-- ===========================================================================
-- A5 asserts it against history rather than arguing it: with the seed above,
-- every proposal ever written to a certification run is either registered or a
-- replay. Zero exceptions across 14,500 rows. So no certification behaviour
-- changes -- the refusal path is unreachable for everything that has ever
-- actually proposed into one. A2 proves the same thing forwards, by submitting
-- as a registered proposer and requiring success.
--
-- ottoq_decide_tick and ottoq_determinism_pair both keep their md5 (A6).
--
-- MUST NOT BE APPLIED WHILE ROUND 31 IS IN FLIGHT. Apply after 0240.

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
SELECT '0241_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public'
   AND p.proname IN ('ottoq_submit_external_proposal','ottoq_determinism_pair_replay');

DO $p1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)'::regprocedure));
  IF h <> '036f5128c357477fa9f329edd79cf2f6' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_submit_external_proposal md5 is %, pinned 036f5128c357477fa9f329edd79cf2f6', h;
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid)'::regprocedure));
  IF h <> 'f0d530c018494bfc550e010a266a4140' THEN
    RAISE EXCEPTION 'P1 REFUSED: ottoq_determinism_pair_replay md5 is %, pinned f0d530c018494bfc550e010a266a4140', h;
  END IF;
END $p1$;

-- ---------------------------------------------------------------------------
-- 1. THE REGISTRY.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_certified_proposers (
  source     text PRIMARY KEY,
  note       text NOT NULL,
  added_at   timestamptz NOT NULL DEFAULT now(),
  added_by   text NOT NULL DEFAULT current_user
);

COMMENT ON TABLE public.ottoq_certified_proposers IS
  '0241 / Posture A (SOLVER_STATE.md 8.2). The proposers a certification arm is '
  'allowed to hear. ottoq_submit_external_proposal refuses any other source when '
  'the target run is run_by=''cert_harness''. Seeded from measurement -- every '
  'source that has ever proposed into a certification -- not from intent. A replay '
  'is admitted by BEING a replay (submitted_by_role=''system:replay'', 0237) rather '
  'than by appearing here, so the two admission mechanisms stay independent. '
  'Certification hygiene, not a security boundary: p_source is caller-supplied for '
  'a system caller, and authorization is G2''s job.';

INSERT INTO public.ottoq_certified_proposers (source, note) VALUES
  ('greedy_constrained',
   '0241 seed. 12,403 proposals across 542 certification runs since 2026-08-29. '
   'The local deterministic stall proposer; inserts directly.'),
  ('ottoq_service_priority',
   '0241 seed. 1,904 proposals across 821 certification runs since 2026-08-29. '
   'ottoq_service_priority_propose, called from ottoq_sim_decide_and_dispatch -- '
   'INSIDE the certified tick. Reaches the table by BOTH paths (direct insert and '
   'through ottoq_submit_external_proposal, 372 of them), which is why a door ban '
   'would have removed a certified proposer.'),
  ('cuopt',
   '0241 seed. 1 proposal, 1 certification run, 2026-08-30. The cuOpt proposer is '
   'quiesced inside a cert by 0152 (cuopt_propose_enabled=0, run-scoped) and by '
   '0056 before it; registered so that quiesce stays the single mechanism that '
   'silences it, rather than this registry silently becoming a second one.')
ON CONFLICT (source) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. THE DOOR CONSULTS THE REGISTRY.
-- ---------------------------------------------------------------------------
DO $chg1$
DECLARE d text; a text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)'::regprocedure);
  a := E'  END IF;\n\n  UPDATE public.ottoq_external_proposals SET status=''superseded''';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG1 REFUSED: door anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a,
       E'  END IF;\n\n'
    || E'  -- 0241 / POSTURE A (SOLVER_STATE.md 8.2; step 2 of the 8.3 sequence).\n'
    || E'  -- A certification arm hears only the proposers it was certified with.\n'
    || E'  -- 0105 and 0152 quiesce the proposers this repository owns; nothing\n'
    || E'  -- stopped an agent proposing into a cert run through this door, and if\n'
    || E'  -- one did the pair would report "failed" over fourteen hashes with no\n'
    || E'  -- hint that a stranger was in the room.\n'
    || E'  --\n'
    || E'  -- Checked on v_source, the SERVER-derived source, not on p_source: an\n'
    || E'  -- operator is ''operator:<uuid>'' and can never be registered.\n'
    || E'  --\n'
    || E'  -- Refused BEFORE the supersede below, so a refused proposal cannot even\n'
    || E'  -- displace a pending one on its way out.\n'
    || E'  --\n'
    || E'  -- A REPLAY is unaffected and deliberately not on the registry:\n'
    || E'  -- ottoq_proposal_replay_inject (0237) writes the table directly and never\n'
    || E'  -- comes through here. Being a replay is its own admission, which keeps\n'
    || E'  -- Posture A and Posture B independent of each other.\n'
    || E'  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs r\n'
    || E'              WHERE r.sim_run_id = p_sim_run_id AND r.run_by = ''cert_harness'')\n'
    || E'     AND NOT EXISTS (SELECT 1 FROM public.ottoq_certified_proposers cp\n'
    || E'                      WHERE cp.source = v_source) THEN\n'
    || E'    RAISE EXCEPTION ''OTTOQ_PROPOSAL_REFUSED_CERT: proposer % is not a certified proposer and run % is a certification arm (Posture A). Register it in ottoq_certified_proposers, or record the stream and replay it -- ottoq_proposal_replay_capture then ottoq_determinism_pair_replay.'', v_source, p_sim_run_id\n'
    || E'      USING ERRCODE = ''42501'';\n'
    || E'  END IF;\n\n'
    || E'  UPDATE public.ottoq_external_proposals SET status=''superseded''');

  EXECUTE d;
END $chg1$;

-- ---------------------------------------------------------------------------
-- 3. THE VERDICT COUNTS WHAT GOT IN ANYWAY. MEASURED, NOT ENFORCED.
--    A door is not a proof: direct SQL, a future edge function or a psql
--    session can all insert around it.
-- ---------------------------------------------------------------------------
DO $chg2$
DECLARE d text; a text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid)'::regprocedure);
  a := E'      ''replay_injected'', v_inj,';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG2 REFUSED: arm-object anchor occurs % times, expected 1', n; END IF;

  d := replace(d, a, a
    || E'\n      -- 0241 POSTURE A, MEASURED (CLAUDE.md 2.9a), not enforced. Proposals on\n'
    || E'      -- this run from a proposer the certification was not certified with.\n'
    || E'      -- Keyed on SOURCE, because neither declared_source nor\n'
    || E'      -- submitted_by_role separates internal from external -- both were\n'
    || E'      -- tried and both counted ottoq_service_priority, which runs inside the\n'
    || E'      -- certified tick, as a foreign agent.\n'
    || E'      ''foreign_proposals'', (SELECT count(*) FROM ottoq_external_proposals fp\n'
    || E'                              WHERE fp.sim_run_id = v_run\n'
    || E'                                AND COALESCE(fp.submitted_by_role,'''') <> ''system:replay''\n'
    || E'                                AND NOT EXISTS (SELECT 1 FROM ottoq_certified_proposers cp\n'
    || E'                                                 WHERE cp.source = fp.source)),');

  EXECUTE d;
END $chg2$;

-- ===========================================================================
-- THE ASSERTIONS.
--
-- Three of the six call the door FOR REAL and check what it does, and two of
-- those require it to SUCCEED. That asymmetry is the point: a gate is easy to
-- assert closed and easy to ship closed on everything. A5 is the one that
-- matters most -- it validates the seed against three days of real
-- certification traffic instead of against my reasoning about it.
-- ===========================================================================
DO $TESTS$
DECLARE
  v_cert uuid; v_noncert uuid; v_veh uuid; v_id uuid; v_msg text; n int;
BEGIN
  SELECT sim_run_id INTO v_cert FROM public.ottoq_sim_runs
   WHERE run_by = 'cert_harness' ORDER BY started_at DESC LIMIT 1;
  SELECT sim_run_id INTO v_noncert FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness' ORDER BY started_at DESC LIMIT 1;
  SELECT id INTO v_veh FROM public.vehicles WHERE category='autonomous' ORDER BY id LIMIT 1;
  IF v_cert IS NULL OR v_noncert IS NULL OR v_veh IS NULL THEN
    RAISE EXCEPTION 'TEST SETUP FAILED: need a cert run, a non-cert run and a vehicle';
  END IF;

  ---------------------------------------------------------------------------
  -- A1  AN UNREGISTERED PROPOSER IS REFUSED FROM A CERTIFICATION.
  ---------------------------------------------------------------------------
  BEGIN
    v_id := public.ottoq_submit_external_proposal(
      v_cert, NULL, '0241_probe', 'vehicle', v_veh,
      '{"verb":"triage","abstain":false}'::jsonb, 'some_new_agent_0241', 300);
    RAISE EXCEPTION 'A1 FAILED: an unregistered proposer was admitted to a certification run';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg NOT LIKE 'OTTOQ_PROPOSAL_REFUSED_CERT%' THEN
      RAISE EXCEPTION 'A1 FAILED: refused, but for the wrong reason: %', v_msg;
    END IF;
  END;

  ---------------------------------------------------------------------------
  -- A2  NEGATIVE CONTROL, AND THE IMPORTANT ONE: A REGISTERED PROPOSER IS
  --     STILL ADMITTED. ottoq_service_priority proposes into certification runs
  --     372 times through this exact door, from inside the certified tick. If
  --     this fails, the migration has quietly narrowed what the harness tests
  --     and forces_recert FALSE is a lie.
  ---------------------------------------------------------------------------
  v_id := public.ottoq_submit_external_proposal(
    v_cert, NULL, '0241_probe_ok', 'vehicle', v_veh,
    '{"verb":"triage","abstain":false}'::jsonb, 'ottoq_service_priority', 300);
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'A2 FAILED: a REGISTERED proposer was not admitted to a certification run';
  END IF;

  ---------------------------------------------------------------------------
  -- A3  NEGATIVE CONTROL: THE GATE IS SCOPED TO CERTIFICATIONS. The same
  --     unregistered proposer that A1 refused must be admitted to a normal run,
  --     or this is not Posture A, it is a ban on external proposals.
  ---------------------------------------------------------------------------
  v_id := public.ottoq_submit_external_proposal(
    v_noncert, NULL, '0241_probe_ok', 'vehicle', v_veh,
    '{"verb":"triage","abstain":false}'::jsonb, 'some_new_agent_0241', 300);
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'A3 FAILED: an unregistered proposer was refused from a NON-certification run';
  END IF;

  DELETE FROM public.ottoq_external_proposals
   WHERE action_context IN ('0241_probe','0241_probe_ok');

  ---------------------------------------------------------------------------
  -- A4  THE VERDICT CARRIES foreign_proposals, AND IT DID NOT REACH THE
  --     EQUALITY LIST. Arm-key comparison count unchanged from the pre-image,
  --     which is the G25 check: an atom added or dropped in silence.
  ---------------------------------------------------------------------------
  DECLARE v_pre text; v_new text; n_pre int; n_new int;
  BEGIN
    SELECT definition INTO v_pre FROM public.ottoq_schema_snapshots
     WHERE label='0241_pre' AND object_name='ottoq_determinism_pair_replay'
     ORDER BY taken_at DESC LIMIT 1;
    v_new := pg_get_functiondef('public.ottoq_determinism_pair_replay(bigint,integer,text,uuid,timestamptz,integer,uuid)'::regprocedure);
    IF v_pre IS NULL THEN RAISE EXCEPTION 'A4 FAILED: the pre-image snapshot is missing'; END IF;
    IF position('foreign_proposals' in v_new) = 0 THEN
      RAISE EXCEPTION 'A4 FAILED: foreign_proposals is not in the arm object';
    END IF;
    IF position('foreign_proposals' in split_part(v_new, 'v_equal :=', 2)) > 0 THEN
      RAISE EXCEPTION 'A4 FAILED: foreign_proposals reached the equality list; it is MEASURED, not enforced';
    END IF;
    n_pre := (length(v_pre) - length(replace(v_pre, 'v_arms[1]', ''))) / length('v_arms[1]');
    n_new := (length(v_new) - length(replace(v_new, 'v_arms[1]', ''))) / length('v_arms[1]');
    IF n_pre <> n_new THEN
      RAISE EXCEPTION 'A4 FAILED: the verdict compares % arm keys, the pre-image compared %', n_new, n_pre;
    END IF;
  END;

  ---------------------------------------------------------------------------
  -- A5  THE SEED IS COMPLETE AGAINST HISTORY, NOT AGAINST MY REASONING.
  --     Every proposal ever written to a certification run must be either a
  --     registered proposer or a replay. If this fails, the registry is short a
  --     row and applying this file WOULD have changed certification behaviour --
  --     which is exactly what the forces_recert FALSE header claims it cannot.
  ---------------------------------------------------------------------------
  SELECT count(*) INTO n
    FROM public.ottoq_external_proposals p
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.sim_run_id
   WHERE r.run_by = 'cert_harness'
     AND COALESCE(p.submitted_by_role,'') <> 'system:replay'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_certified_proposers cp WHERE cp.source = p.source);
  IF n <> 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % historical certification proposal(s) come from a source the registry does not hold -- the seed is incomplete and this file WOULD change certification behaviour', n;
  END IF;
END $TESTS$;

-- A6  NO RESIDUE; THE CERTIFIED TICK AND THE CERTIFIED PAIR ARE UNTOUCHED.
DO $a6$
DECLARE n int; h text;
BEGIN
  SELECT count(*) INTO n FROM public.ottoq_external_proposals
   WHERE action_context IN ('0241_probe','0241_probe_ok') OR source = 'some_new_agent_0241';
  IF n <> 0 THEN RAISE EXCEPTION 'A6 FAILED: % probe proposal(s) left behind', n; END IF;

  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A6 FAILED: ottoq_decide_tick md5 moved to %', h;
  END IF;
  h := md5(pg_get_functiondef('public.ottoq_determinism_pair(bigint,integer,text,uuid,timestamptz,integer)'::regprocedure));
  IF h <> 'e323bf87d0fbd9d3778bbda7c8f94ba7' THEN
    RAISE EXCEPTION 'A6 FAILED: the certified pair md5 moved to %', h;
  END IF;
END $a6$;

-- NO ottoq_run_scope_registry ROW, DELIBERATELY. The first draft registered the
-- new table with class 'config', which the registry's CHECK does not allow
-- (engine | stamp | evidence | run_ledger) -- and the fix is not to pick the
-- least-wrong class. ottoq_check_run_scope_registry flags UNREGISTERED
-- RUN-SCOPED COLUMNS; ottoq_certified_proposers has no run-scoped column at all,
-- so it is not in that check's universe and a row would only teach a future
-- reader that configuration tables belong in a run-scope registry. They do not.

INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'a_certification_hears_only_the_proposers_it_certified',
  now(),
  false,
  'POSTURE A, SOLVER_STATE.md 8.3 step 2 -- the last open item in that sequence. '
  'ottoq_submit_external_proposal refuses a proposer that is not in the new '
  'ottoq_certified_proposers registry when the target run is run_by=''cert_harness''. '
  'THE OBVIOUS VERSION -- refuse the door outright -- was written first and was '
  'WRONG: measured, 372 proposals reach 148 CERTIFICATION runs through that door '
  'from ottoq_service_priority_propose, which ottoq_sim_decide_and_dispatch calls '
  'INSIDE the certified tick. It would have deleted a certified proposer under a '
  'forces_recert FALSE header. Two column-based discriminators (declared_source, '
  'submitted_by_role) were also tried and both counted the certified core as '
  'foreign. The registry is seeded from measurement -- greedy_constrained (12,403 '
  'proposals / 542 cert runs), ottoq_service_priority (1,904 / 821), cuopt (1 / 1) '
  '-- and A5 asserts completeness against every proposal ever written to a cert '
  'run, so forces_recert FALSE is checked rather than argued. A replay is admitted '
  'by being a replay, not by registration, keeping Postures A and B independent. '
  'foreign_proposals added to ottoq_determinism_pair_replay MEASURED only (A4). '
  'This is certification hygiene, not a security boundary: p_source is '
  'caller-supplied for a system caller and authorization is G2''s.'
);

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-09 00:19 CT (05:19 UTC), version 20260909051812, first
-- attempt, all six assertions green. The two that matter most both had to
-- SUCCEED rather than refuse:
--
--   A1  an unregistered proposer IS refused from a certification run, with
--       OTTOQ_PROPOSAL_REFUSED_CERT and SQLSTATE 42501
--   A2  ottoq_service_priority -- which proposes into cert runs 372 times through
--       this exact door, from inside the certified tick -- is STILL ADMITTED.
--       This is the assertion that proves the migration did not quietly narrow
--       what the harness tests, and it is why forces_recert FALSE is honest.
--   A3  the same unregistered proposer A1 refused IS admitted to a NON-cert run:
--       the gate is scoped to certifications, not a ban on external proposals
--   A4  foreign_proposals present in the arm object, ABSENT from the equality
--       list, arm-key comparison count unchanged from the pre-image
--   A5  the seed is complete against HISTORY: zero proposals, across every
--       certification run ever recorded, come from a source the registry does
--       not hold
--   A6  no probe residue; decide_tick AND the certified pair both md5-unchanged
--
--   registry              cuopt, greedy_constrained, ottoq_service_priority
--   recert floor          2026-09-09 03:15:07, UNMOVED
--
-- A5 is the one that converts the header's claim into a measurement. "Nothing
-- certified changes" is not argued here; it is checked against every proposal
-- this database has ever written to a cert run.
