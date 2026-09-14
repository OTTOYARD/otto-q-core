-- migration-version: PENDING
-- migration-name:    0323_nothing_that_starts_a_run_ever_armed_the_agentic_layer
--
-- 0323  ACROSS 1,147 SIM RUNS, NOTHING THAT STARTS A RUN HAS EVER ARMED THE
--       AGENTIC LAYER. THE ONLY CALLER OF ottoq_agentic_arm IS A PYTHON SCRIPT
--       A HUMAN DISPATCHES BY HAND.
--
-- Found 2026-09-14 answering a founder question: the twin is live in the UI, so
-- why does it not show the engine's intelligence layer doing anything?
--
-- MEASURED:
--   public.ottoq_sim_run_scenario arms?                     false
--     ^ the start path otto-twin-control (the UI's control surface) calls at
--       edge-functions/otto-twin-control/index.ts:99
--   database functions calling ottoq_agentic_arm            (NONE)
--   edge functions calling ottoq_agentic_arm                (NONE, all 27)
--   anything at all calling it                              bridge/proposer_bridge.py:87
--   total sim runs ever                                     1,147
--
-- So every run ever started from the UI, from the metronome, from the API or
-- from a scheduler has booted with the proposer door SHUT. Not broken -- never
-- opened. The deterministic core orchestrates end to end in those runs (world
-- -> needs -> recall -> shield -> bookings -> commands -> SDRs, all verifiable
-- with scripts/watch-run.sql), and the agentic half is simply absent, because
-- opening it requires an explicit call nothing in the served surface makes.
--
-- ---------------------------------------------------------------------------
-- WHY THE FIX GOES IN THE DATABASE AND NOT IN THE EDGE FUNCTION
--
-- The obvious fix is to make otto-twin-control call ottoq_agentic_arm after it
-- starts a run. That closes ONE door. There are at least two, and adding a
-- careful call site to one of them is precisely the defect this repo has
-- convicted three times TODAY:
--
--   db/checks/0240   four functions write return_eta_minutes, one writes the label
--   db/checks/0241   eight functions write ottoq_decisions, four set no source
--   0318             fixed labelling inside one writer; there were four
--
-- So arming becomes part of STARTING, at every door, in the layer both doors go
-- through. A run is armed because it was started, not because somebody
-- remembered.
--
-- ---------------------------------------------------------------------------
-- THE ONE EXCLUSION, AND WHY IT IS STRUCTURAL RATHER THAN CAREFUL
--
-- A certification arm must NEVER be armed. Arming sets proposer_frame_facts=1,
-- which by 0265 changes what the decision frame carries -- the frame every
-- canon was measured against. ottoq_agentic_arm already refuses a
-- run_by='cert_harness' run and RAISES to do it, so calling it unguarded here
-- would abort the creation of every certification arm.
--
-- Both substitutions therefore test run_by BEFORE calling, and the call is
-- additionally wrapped so that an arming failure records a receipt on the run
-- instead of destroying a start. Two independent protections, because the cost
-- of getting this wrong is every canon in the matrix.
--
-- forces_recert: TRUE. Cert arms are excluded by construction, so the honest
-- expectation is that NO canon moves -- but "no canon should move" is a
-- prediction for round 44 to judge, not a classification. 0308/0309 argued
-- forces_recert=false correctly, omitted the lineage row, and the floor
-- swallowed every column until 0310 repaired it. Classified TRUE, and the
-- lineage row is in this file.
-- ===========================================================================

-- SNAPSHOT BEFORE REPLACE (scripts/APPLYING.md §2) ----------------------------
-- Every function this file rewrites, recorded verbatim with its md5 BEFORE it is
-- touched. This file substitutes into live bodies rather than issuing CREATE OR
-- REPLACE from source, so without this row there is no recorded "before" to
-- restore from if a substitution lands wrong.
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0323_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'public' AND p.proname = 'ottoq_sim_run_scenario') OR (n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run');

DO $pre$
DECLARE v_callers text; v_scn text; v_str text;
BEGIN
  -- P1. THE PREMISE: nothing arms today. If someone has already wired this,
  --     the substitutions below would double-arm.
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~ 'ottoq_agentic_arm'
     AND p.proname <> 'ottoq_agentic_arm';
  IF v_callers IS NOT NULL THEN
    RAISE EXCEPTION '0323 P1: % already call(s) ottoq_agentic_arm; the premise has changed', v_callers;
  END IF;

  -- P2. THE ARMING FUNCTION EXISTS, and still refuses a certification arm.
  --     This migration's safety rests on that refusal being real.
  IF to_regprocedure('public.ottoq_agentic_arm(uuid,text)') IS NULL THEN
    RAISE EXCEPTION '0323 P2: public.ottoq_agentic_arm(uuid,text) not found';
  END IF;
  IF (SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_agentic_arm(uuid,text)'))
       !~ 'cert_harness' THEN
    RAISE EXCEPTION '0323 P2: ottoq_agentic_arm no longer guards cert_harness; refusing to call it from a start path';
  END IF;

  -- P3/P4. Both anchors occur EXACTLY ONCE, counted the way replace() counts --
  --        it matches SUBSTRINGS, which is the 0317 lesson.
  SELECT p.prosrc INTO v_scn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_run_scenario';
  SELECT p.prosrc INTO v_str FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_run';
  IF v_scn IS NULL THEN RAISE EXCEPTION '0323 P3: public.ottoq_sim_run_scenario not found'; END IF;
  IF v_str IS NULL THEN RAISE EXCEPTION '0323 P4: twin.ottoq_sim_start_run not found'; END IF;

  IF (length(v_scn) - length(replace(v_scn,
        E'  PERFORM ottoq_record_event(\n    p_actor_type := ''system_scheduler'', p_actor_id := ''twin_scenario_runner'',','')))
     / length(E'  PERFORM ottoq_record_event(\n    p_actor_type := ''system_scheduler'', p_actor_id := ''twin_scenario_runner'',') <> 1 THEN
    RAISE EXCEPTION '0323 P3: the ottoq_sim_run_scenario anchor does not occur exactly once';
  END IF;
  IF (length(v_str) - length(replace(v_str, E'  RETURN v_run_id;','')))
     / length(E'  RETURN v_run_id;') <> 1 THEN
    RAISE EXCEPTION '0323 P4: the ottoq_sim_start_run anchor does not occur exactly once';
  END IF;
END $pre$;

DO $apply$
DECLARE
  v_def text; v_new text;
  a_scn CONSTANT text := E'  PERFORM ottoq_record_event(\n    p_actor_type := ''system_scheduler'', p_actor_id := ''twin_scenario_runner'',';
  a_str CONSTANT text := E'  RETURN v_run_id;';
  -- The arming block, written once and substituted into both doors. p_run_by is
  -- the parameter name in BOTH functions, and v_target differs per door, so the
  -- run-id variable is injected by format().
  tpl   CONSTANT text :=
      E'  -- 0323: ARM THE AGENTIC LAYER ON THE WAY IN. Across 1,147 runs nothing\n'
   || E'  -- that started a run had ever done this, so every run booted with the\n'
   || E'  -- proposer door shut and the UI could never show the agentic half\n'
   || E'  -- working. Arming is part of STARTING now, at every door, so a run is\n'
   || E'  -- armed because it was started and not because somebody remembered.\n'
   || E'  --\n'
   || E'  -- THE cert_harness TEST IS NOT OPTIONAL. Arming sets\n'
   || E'  -- proposer_frame_facts=1, which changes what the decision frame carries\n'
   || E'  -- (0265) -- the frame every canon was measured against.\n'
   || E'  -- ottoq_agentic_arm refuses such a run by RAISING, so an unguarded call\n'
   || E'  -- would abort the creation of every certification arm.\n'
   || E'  IF COALESCE(p_run_by, '''') <> ''cert_harness'' THEN\n'
   || E'    BEGIN\n'
   || E'      PERFORM public.ottoq_agentic_arm(%1$s, ''auto:'' || COALESCE(p_run_by, ''unknown''));\n'
   || E'      UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, ''{}''::jsonb)\n'
   || E'             || jsonb_build_object(''agentic_arm'', jsonb_build_object(''ok'', true))\n'
   || E'       WHERE sim_run_id = %1$s;\n'
   || E'    EXCEPTION WHEN OTHERS THEN\n'
   || E'      -- Receipt, never silence, and never a failed start: a run that could\n'
   || E'      -- not be armed is still a valid run, and the reason is on the row.\n'
   || E'      UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, ''{}''::jsonb)\n'
   || E'             || jsonb_build_object(''agentic_arm'',\n'
   || E'                  jsonb_build_object(''ok'', false, ''error'', SQLERRM))\n'
   || E'       WHERE sim_run_id = %1$s;\n'
   || E'    END;\n'
   || E'  END IF;\n\n';
BEGIN
  -- S1  public.ottoq_sim_run_scenario  (the door otto-twin-control calls)
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_run_scenario';
  v_new := replace(v_def, a_scn, format(tpl, 'v_sim_run_id') || a_scn);
  IF v_new = v_def THEN RAISE EXCEPTION '0323 S1: substitution changed nothing'; END IF;
  EXECUTE v_new;

  -- S2  twin.ottoq_sim_start_run  (the door a script or the harness calls)
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_run';
  v_new := replace(v_def, a_str, format(tpl, 'v_run_id') || a_str);
  IF v_new = v_def THEN RAISE EXCEPTION '0323 S2: substitution changed nothing'; END IF;
  EXECUTE v_new;
END $apply$;

DO $post$
DECLARE v_scn text; v_str text;
BEGIN
  SELECT p.prosrc INTO v_scn FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_run_scenario';
  SELECT p.prosrc INTO v_str FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_run';

  -- A1. BOTH doors arm, and each exactly once. Twice would double-write dials.
  IF (length(v_scn)-length(replace(v_scn,'ottoq_agentic_arm','')))/length('ottoq_agentic_arm') <> 1 THEN
    RAISE EXCEPTION '0323 A1: ottoq_sim_run_scenario does not arm exactly once'; END IF;
  IF (length(v_str)-length(replace(v_str,'ottoq_agentic_arm','')))/length('ottoq_agentic_arm') <> 1 THEN
    RAISE EXCEPTION '0323 A1: ottoq_sim_start_run does not arm exactly once'; END IF;

  -- A2. BOTH guard on cert_harness BEFORE calling. This is the assertion that
  --     protects every canon in the matrix, so it is checked structurally and
  --     not trusted to the diff.
  IF v_scn !~ 'cert_harness' THEN
    RAISE EXCEPTION '0323 A2: ottoq_sim_run_scenario arms without a cert_harness guard'; END IF;
  IF v_str !~ 'cert_harness' THEN
    RAISE EXCEPTION '0323 A2: ottoq_sim_start_run arms without a cert_harness guard'; END IF;
  IF position('cert_harness' in v_scn) > position('ottoq_agentic_arm' in v_scn) THEN
    RAISE EXCEPTION '0323 A2: in ottoq_sim_run_scenario the guard does not precede the call'; END IF;
  IF position('cert_harness' in v_str) > position('ottoq_agentic_arm' in v_str) THEN
    RAISE EXCEPTION '0323 A2: in ottoq_sim_start_run the guard does not precede the call'; END IF;

  -- A3. THE REFUSAL THIS FILE LEANS ON IS STILL THERE. If a later edit removed
  --     ottoq_agentic_arm's own cert_harness guard, these call sites become the
  --     only thing standing between a certification and a changed frame.
  IF (SELECT p.prosrc FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_agentic_arm(uuid,text)'))
       !~ 'cert_harness' THEN
    RAISE EXCEPTION '0323 A3: ottoq_agentic_arm lost its own cert_harness refusal';
  END IF;

  -- A4. NO WALL CLOCK was introduced into either start path (G15).
  IF v_scn ~ '0323' AND v_scn ~ '\mclock_timestamp\s*\(' THEN
    RAISE EXCEPTION '0323 A4: a wall clock appears in the arming block'; END IF;

  RAISE NOTICE '0323: both start doors now arm non-certification runs';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0323_nothing_that_starts_a_run_ever_armed_the_agentic_layer', true,
   'Arming becomes part of starting, at BOTH doors -- public.ottoq_sim_run_scenario (which '
   'otto-twin-control calls, so the UI path) and twin.ottoq_sim_start_run. Measured premise: '
   'across 1,147 sim runs, NO database function and NO edge function called ottoq_agentic_arm; '
   'the only caller was bridge/proposer_bridge.py, dispatched by hand. Every run from the UI '
   'therefore booted with the proposer door shut. Certification arms are excluded by a '
   'run_by <> cert_harness test placed BEFORE the call (A2 asserts the ordering), because '
   'arming sets proposer_frame_facts=1 and would change the frame every canon was measured '
   'against. forces_recert TRUE even though cert arms are excluded by construction: "no canon '
   'should move" is a prediction for round 44, not a classification.',
   now())
ON CONFLICT (name) DO NOTHING;
