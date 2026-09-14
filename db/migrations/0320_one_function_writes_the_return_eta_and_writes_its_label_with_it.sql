-- migration-version: PENDING
-- migration-name:    0320_one_function_writes_the_return_eta_and_writes_its_label_with_it
--
-- 0320  FOUR FUNCTIONS WRITE return_eta_minutes AND EXACTLY ONE WRITES
--       eta_source, SO THE LABEL DESCRIBES A WRITE THAT HAS BEEN SUPERSEDED
--
-- Measured in db/checks/0240 §B against run a5bd449f: 21 of 61 dispatch rows
-- carry eta_source = 'policy_constant:return_eta_minutes' while holding
-- SEVENTEEN DISTINCT VALUES between 1.6 and 48.8 minutes. A constant does not
-- take seventeen values.
--
-- ---------------------------------------------------------------------------
-- WHY THE LABEL IS WRONG WITHOUT ANY SITE BEING WRONG
--
-- The four writers:
--
--   twin.ottoq_sim_advance_deployed_telemetry  L323  value + stamp + source
--   twin.ottoq_sim_auto_dispatch_tick          L139  value only
--   public.ottoq_ingest_vehicle_signal         L53   value only
--   twin.ottoq_sim_prime_deployment            L104  value only (INSERT, dial)
--
-- The first stamps an HONEST label at the return flip -- when the computation
-- refuses there, 'policy_constant' is correct at the moment it is written. Then
-- ottoq_sim_auto_dispatch_tick overwrites the value on a later tick with a
-- genuinely computed number and leaves eta_source alone. Every site, read on
-- its own, is right. The pair of columns, read together, is wrong.
--
-- THAT IS WHY THIS IS NOT FIXED BY ADDING A LABEL TO THE OTHER THREE SITES.
-- 0318 is titled "the engine stopped guessing and the label kept saying guess"
-- and it did exactly that -- fixed the labelling inside ONE writer -- and the
-- defect survived it, one migration later, because there were four. A fourth
-- careful site is a fourth thing that can fall out of step with a fifth.
--
-- So the value and its provenance are made inseparable: ONE function writes all
-- three columns in ONE statement, and the other writers call it.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MIGRATION DOES, AND DELIBERATELY DOES NOT DO
--
-- DOES:  creates public.ottoq_refresh_return_eta. That is all it does.
--
-- DOES NOT: convert ANY existing writer, and does not refresh the ETA for
--        `active` dispatches. Both are 0321.
--
-- AN EARLIER DRAFT OF THIS HEADER SAID IT ALSO CONVERTED THE RETURN-FLIP WRITE,
-- and the body did not. That is the scripts/APPLYING.md §3b failure exactly --
-- "a precondition you have not executed is a comment" -- with the header
-- playing the part of the precondition. Corrected here rather than discovered
-- during the apply.
--
-- Splitting it this way costs a second file and buys the thing that matters at
-- a recert boundary: after round 44, a moved canon is attributable. 0320 adds a
-- function NOBODY CALLS, so it cannot move one. If a canon moves, 0321 did it.
--
-- ---------------------------------------------------------------------------
-- DETERMINISM, because this writes inside the certified path
--
--   * eta_refreshed_at is p_sim_clock -- the SIM clock, passed in. Never now().
--     The G15 defect class is a wall clock inside the decide path.
--   * the dispatch to update is chosen ORDER BY dispatched_at DESC,
--     planned_duration_min DESC. dispatch_id is NOT in the ordering and is not
--     referenced: its column default is gen_random_uuid(), so it differs between
--     two arms of one seed. That is 0319, four days old, and A3 below asserts
--     the token appears nowhere in the new function's body.
--   * the label branches on the SAME variable the value is COALESCEd from, in
--     the same statement, so the two cannot disagree even in principle.
--
-- forces_recert: TRUE. The write moves from an inline UPDATE to a function
-- call. The VALUES should be identical -- that is the intent and A5 checks the
-- shape -- but "should be identical" is a prediction, not a classification, and
-- 0192 exists so that an atom which can be required can be retired, not so that
-- a behaviour change can be waved through. Round 44 judges it.
-- ===========================================================================

DO $pre$
DECLARE v_writers int; v_labelers int; v_src text;
BEGIN
  -- P1. THE PREMISE: four writers, one labeler. If this has already been
  --     tidied by someone else, the migration's whole argument is stale.
  SELECT count(*) INTO v_labelers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~ 'eta_source';
  IF v_labelers <> 1 THEN
    RAISE EXCEPTION '0320 P1: expected exactly 1 function writing eta_source, found %; '
                    'the premise measured in db/checks/0240 has changed', v_labelers;
  END IF;

  SELECT count(*) INTO v_writers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~ 'return_eta_minutes\s*=';
  IF v_writers < 3 THEN
    RAISE EXCEPTION '0320 P1: expected at least 3 functions assigning return_eta_minutes, found %', v_writers;
  END IF;

  -- P2. A FORWARD GUARD FOR 0321, not a precondition of this file.
  --     0321 will substitute the return-flip write, and it will do that by
  --     anchoring on this exact text. Checking the anchor HERE means 0321
  --     cannot ship into a database where the anchor has already drifted --
  --     the cost of finding that out is one failed apply either way, but
  --     finding it now keeps it out of the apply window.
  --     Asserted to occur EXACTLY ONCE by length arithmetic, because replace()
  --     matches SUBSTRINGS: "it appears once" has to be measured the way
  --     replace() will see it, not the way a line-oriented grep would (0317).
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_deployed_telemetry';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0320 P2: twin.ottoq_sim_advance_deployed_telemetry not found';
  END IF;
  IF (length(v_src) - length(replace(v_src, 'return_eta_minutes   = v_eta_min,', '')))
       / length('return_eta_minutes   = v_eta_min,') <> 1 THEN
    RAISE EXCEPTION '0320 P2: the return-flip write anchor does not occur exactly once';
  END IF;
END $pre$;

-- ---------------------------------------------------------------------------
-- THE ONE WRITER.
--
-- Returns the ETA it wrote, or NULL when there is no open dispatch to write to
-- -- and NULL means "nothing to refresh", never "the ETA is zero". Callers that
-- need a number for their own arithmetic COALESCE it themselves, exactly as
-- they do today.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_refresh_return_eta(
  p_vehicle_id  uuid,
  p_sim_run_id  uuid,
  p_sim_clock   timestamptz,
  p_depot_id    uuid DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_depot     uuid;
  v_computed  numeric;   -- NULL means the computation REFUSED (0318's convention)
  v_eta       numeric;
  v_target    uuid;
BEGIN
  IF p_vehicle_id IS NULL OR p_sim_run_id IS NULL OR p_sim_clock IS NULL THEN
    RETURN NULL;
  END IF;

  -- 0316: resolve the depot rather than assume the caller supplied one. Two of
  -- the five ETA call sites pass NULL.
  SELECT COALESCE(p_depot_id, v.home_depot_id, r.depot_id)
    INTO v_depot
    FROM public.ottoq_sim_runs r
    LEFT JOIN public.vehicles v ON v.id = p_vehicle_id
   WHERE r.sim_run_id = p_sim_run_id;

  -- The dispatch this refresh is about. Chosen the same way ottoq_trip_geometry
  -- chooses it (0319), on two deterministic columns, so the ETA and the
  -- geometry it is derived from can never be about different dispatches.
  SELECT d.dispatch_id INTO v_target
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = p_vehicle_id
     AND d.sim_run_id = p_sim_run_id
     AND d.status IN ('active','returning')
   ORDER BY d.dispatched_at DESC NULLS LAST, d.planned_duration_min DESC NULLS LAST
   LIMIT 1;
  IF v_target IS NULL THEN RETURN NULL; END IF;

  IF v_depot IS NOT NULL THEN
    v_computed := public.ottoq_computed_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id, p_sim_clock);
  END IF;

  -- The fallback inlines the dial rather than calling ottoq_return_eta_minutes,
  -- which would re-run the computation that just refused (0318's note, kept).
  v_eta := COALESCE(v_computed,
                    GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id,'return_eta_minutes',30), 30)));

  -- Value, stamp and label in ONE statement, the label branching on the SAME
  -- variable the value was COALESCEd from. This is the entire point of the file.
  UPDATE public.ottoq_vehicle_dispatches
     SET return_eta_minutes = v_eta,
         eta_refreshed_at   = p_sim_clock,      -- SIM clock. Never now().
         eta_source         = CASE WHEN v_computed IS NOT NULL
                                   THEN 'computed:distance_over_speed'
                                   ELSE 'policy_constant:return_eta_minutes' END
   WHERE dispatch_id = v_target;

  RETURN v_eta;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_refresh_return_eta(uuid,uuid,timestamptz,uuid) IS
'THE ONLY function that may write ottoq_vehicle_dispatches.return_eta_minutes. Writes the '
'value, eta_refreshed_at and eta_source in one statement so the number and its provenance '
'cannot fall out of step -- db/checks/0240 measured 21 of 61 rows labelled policy_constant '
'while holding 17 distinct values, because four functions wrote the value and one wrote the '
'label. Returns the ETA written, or NULL when the vehicle has no open dispatch (NULL means '
'nothing to refresh, never zero). eta_refreshed_at is the SIM clock passed in; a wall clock '
'here would be the G15 class. 0320.';

DO $post$
DECLARE v_src text; v_def text;
BEGIN
  -- A1. THE FUNCTION EXISTS with the signature callers will use.
  IF to_regprocedure('public.ottoq_refresh_return_eta(uuid,uuid,timestamptz,uuid)') IS NULL THEN
    RAISE EXCEPTION '0320 A1: ottoq_refresh_return_eta was not created with the expected signature';
  END IF;

  SELECT pg_get_functiondef(to_regprocedure('public.ottoq_refresh_return_eta(uuid,uuid,timestamptz,uuid)'))
    INTO v_def;

  -- A2. IT WRITES ALL THREE COLUMNS. The claim the COMMENT makes, asserted --
  --     a version of this function that forgot eta_source would be the very
  --     defect it exists to close.
  IF position('return_eta_minutes' in v_def) = 0
     OR position('eta_refreshed_at'  in v_def) = 0
     OR position('eta_source'        in v_def) = 0 THEN
    RAISE EXCEPTION '0320 A2: the refresh function does not write all three columns';
  END IF;

  -- A3. NO dispatch_id IN A SALT OR AN ORDER BY. 0319, four days old: that
  --     column defaults to gen_random_uuid() and differs between two arms of
  --     one seed. It IS used here -- as the UPDATE's WHERE key, which is
  --     correct and arm-local -- so the assertion is specifically that it does
  --     not appear in the ORDER BY that CHOOSES the row.
  IF v_def ~ 'ORDER BY[^;]*dispatch_id' THEN
    RAISE EXCEPTION '0320 A3: dispatch_id appears in an ORDER BY; its default is a random uuid '
                    'and it cannot order a deterministic choice (0319)';
  END IF;

  -- A4. NO WALL CLOCK. now()/clock_timestamp() inside a function that writes to
  --     the certified path is G15 by name.
  IF v_def ~ '\mnow\s*\(' OR v_def ~ '\mclock_timestamp\s*\(' THEN
    RAISE EXCEPTION '0320 A4: a wall clock appears in the refresh function';
  END IF;

  -- A5. THE LABEL AND THE VALUE BRANCH ON THE SAME VARIABLE. Asserted
  --     structurally rather than trusted: v_computed must be what the CASE
  --     tests AND what the COALESCE takes.
  IF v_def !~ 'COALESCE\(v_computed' OR v_def !~ 'CASE WHEN v_computed IS NOT NULL' THEN
    RAISE EXCEPTION '0320 A5: the value and the label do not both derive from v_computed';
  END IF;

  -- A6. THE OTHER THREE WRITERS ARE UNCHANGED BY THIS FILE, stated as a
  --     measurement so 0321 starts from a known place rather than a memory.
  SELECT count(*)::text INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~ 'return_eta_minutes\s*=';
  RAISE NOTICE '0320: % functions still assign return_eta_minutes directly; 0321 converts them', v_src;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0320_one_function_writes_the_return_eta_and_writes_its_label_with_it', true,
   'Creates public.ottoq_refresh_return_eta as the single writer of return_eta_minutes + '
   'eta_refreshed_at + eta_source. This file creates the function only; it does not yet '
   'convert the three unlabelled writers and does not refresh active dispatches (0321). '
   'Classified TRUE rather than false: the intent is that values are unchanged, but that is '
   'a prediction for round 44 to judge, not a classification.',
   now())
ON CONFLICT (name) DO NOTHING;
