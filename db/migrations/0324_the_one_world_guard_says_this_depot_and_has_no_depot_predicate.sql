-- migration-version: 20260914192738
-- migration-name:    0324_the_one_world_guard_says_this_depot_and_has_no_depot_predicate
--
-- 0324  THE RUN GUARD REFUSES CORRECTLY AND EXPLAINS ITSELF WRONGLY
--
-- twin.ottoq_sim_start_run refuses a second concurrent run with
--
--   OTTOQ_RUN_ALREADY_ACTIVE: run % (started by %) is still moving THIS DEPOT.
--   The world is shared, so a second run would fight it for every vehicle.
--   Watch the live run instead, or stop it first.
--
-- The REFUSAL is right and the reason it gives is right -- its own comment two
-- lines above states the design exactly:
--
--   -- ONE WORLD, ONE MOVER. vehicles/stalls are global and unscoped, so a
--   -- second ticking run would advance the same rows from a different clock.
--
-- But the SENTENCE says "this depot", and the query it guards has no depot
-- predicate at all:
--
--   SELECT sim_run_id, run_by INTO v_active_id, v_active_by
--     FROM ottoq_sim_runs
--    WHERE status = 'running'
--      AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
--    ORDER BY started_at DESC LIMIT 1;
--
-- Any running non-certification run anywhere blocks any new start anywhere.
-- That is deliberate and correct. The message describes a narrower rule than
-- the one being enforced, and a reader who believes it concludes that a run on
-- a DIFFERENT depot is safe to start.
--
-- ---------------------------------------------------------------------------
-- WHAT IT COST, recorded because the cost is the justification
--
-- 2026-09-14, mid round 43: a twin run was started on the Benchmark depot
-- (22222222) to demonstrate end-to-end orchestration, on the reasoning that the
-- certification round was on the flagship depot (11111111) and therefore
-- unaffected. The scenario-to-depot mapping was checked and was correct. The
-- GUARD was not read.
--
-- Two certification pairs were then refused -- r43_c2 (normal_day/171717/12t)
-- and r43_d2 (busy_day/424242/12t) -- leaving two columns at one pass instead
-- of two and costing the round a re-run. Nothing was corrupted: the guard
-- checks before anything is written, exactly as its comment promises, so a
-- refused start leaves no partial run behind.
--
-- The rule broken is the one this repo keeps restating: BEFORE RELYING ON A
-- PROPERTY, READ ITS ASSIGNMENT. "Different depot" was verified against the
-- scenario table and assumed to imply run isolation. The isolation is
-- world-wide by design, and the message is what made that easy to get wrong.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS CHANGES AND WHAT IT DOES NOT
--
-- CHANGES:      the wording of one RAISE, and it now names the dial that lifts
--               the restriction so the next reader has somewhere to go.
-- DOES NOT:     touch the predicate, the ordering, the excluded run_by values,
--               or when the guard fires. The behaviour is correct and stays
--               byte-for-byte.
--
-- Nobody should read this as making concurrent runs safe. allow_concurrent_runs
-- exists and defaults to 0, and the comment gives the reason it should stay
-- there: vehicles and stalls are global, so two movers corrupt each other's
-- world. The two-lane certification cadence sketched in the backlog is NOT
-- viable while that is true, and that is a design question, not a wording one.
--
-- forces_recert: TRUE, and this one genuinely should be FALSE -- a RAISE message
-- on a refusal path that no certification arm can reach (cert_harness runs are
-- excluded from being blockers, and a cert arm that hits the guard fails rather
-- than producing a canon). It is classified TRUE anyway because it rides the
-- same apply window as 0320-0323, which force one regardless, so the honest
-- classification costs nothing and a wrong FALSE is what 0308/0309 did.
-- ===========================================================================

-- SNAPSHOT BEFORE REPLACE (scripts/APPLYING.md §2) ----------------------------
-- Every function this file rewrites, recorded verbatim with its md5 BEFORE it is
-- touched. This file substitutes into live bodies rather than issuing CREATE OR
-- REPLACE from source, so without this row there is no recorded "before" to
-- restore from if a substitution lands wrong.
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0324_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run');

DO $pre$
DECLARE v_src text; v_anchor CONSTANT text := 'is still moving this depot.';
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0324 P1: twin.ottoq_sim_start_run not found';
  END IF;

  -- P1. THE MISLEADING PHRASE OCCURS EXACTLY ONCE, counted the way replace()
  --     counts it -- substrings, not lines (0317).
  IF (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor) <> 1 THEN
    RAISE EXCEPTION '0324 P1: the phrase % does not occur exactly once', v_anchor;
  END IF;

  -- P2. AND THE PREDICATE REALLY HAS NO DEPOT CLAUSE -- i.e. the message really
  --     is wrong. If someone has since scoped the guard to a depot, the message
  --     is CORRECT and this migration must not "fix" it into a lie.
  IF v_src ~ 'FROM ottoq_sim_runs\s+WHERE status = ''running''\s+AND[^;]*depot_id' THEN
    RAISE EXCEPTION '0324 P2: the guard now has a depot predicate; the existing message is '
                    'accurate and this migration would make it wrong';
  END IF;
END $pre$;

DO $apply$
DECLARE
  v_def text; v_new text;
  a CONSTANT text := 'is still moving this depot. The world is shared, so a second run would fight it for every vehicle.';
  r CONSTANT text := 'is still moving THIS WORLD -- not just this depot. vehicles and stalls are global and unscoped, so ANY running non-certification run blocks a new start on ANY depot, and a second mover would advance the same rows from a different clock. Lift it deliberately with the allow_concurrent_runs dial if that is really what you want.';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run';
  v_new := replace(v_def, a, r);
  IF v_new = v_def THEN
    RAISE EXCEPTION '0324: substitution changed nothing -- the message text has drifted';
  END IF;
  EXECUTE v_new;
END $apply$;

DO $post$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run';

  -- A1. THE MISLEADING PHRASE IS GONE and the accurate one is present.
  IF v_src ~ 'is still moving this depot\.' THEN
    RAISE EXCEPTION '0324 A1: the old message survived'; END IF;
  IF v_src !~ 'THIS WORLD' OR v_src !~ 'allow_concurrent_runs' THEN
    RAISE EXCEPTION '0324 A1: the new message is missing its scope or its dial'; END IF;

  -- A2. THE GUARD STILL FIRES ON THE SAME CONDITION. This file changes a
  --     sentence; if it changed behaviour it would be a different migration and
  --     a far more dangerous one.
  IF v_src !~ 'OTTOQ_RUN_ALREADY_ACTIVE' THEN
    RAISE EXCEPTION '0324 A2: the guard lost its error code'; END IF;
  IF v_src !~ 'allow_concurrent_runs'' , 0\) < 1' AND v_src !~ 'allow_concurrent_runs''\s*,\s*0\)\s*<\s*1' THEN
    RAISE EXCEPTION '0324 A2: the allow_concurrent_runs gate is no longer the condition'; END IF;
  IF v_src !~ 'NOT IN \(''production_live'', ''cert_harness''\)' THEN
    RAISE EXCEPTION '0324 A2: the excluded run_by set changed'; END IF;

  RAISE NOTICE '0324: the refusal is unchanged; it now names the scope it actually enforces';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0324_the_one_world_guard_says_this_depot_and_has_no_depot_predicate', true,
   'One RAISE message in twin.ottoq_sim_start_run. The guard refuses correctly -- vehicles and '
   'stalls are global, so one world means one mover -- but said "this depot" while its query '
   'carries no depot predicate, and a reader who believed it concluded a run on another depot '
   'was safe to start. That reading cost round 43 two refused pairs (r43_c2, r43_d2) on '
   '2026-09-14. Behaviour is untouched: A2 asserts the error code, the allow_concurrent_runs '
   'gate and the excluded run_by set are all unchanged. Classified TRUE only because it rides '
   'the 0320-0323 window which forces a recert anyway.',
   now())
ON CONFLICT (name) DO NOTHING;
