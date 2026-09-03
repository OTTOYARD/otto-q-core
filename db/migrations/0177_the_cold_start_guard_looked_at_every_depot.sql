-- =====================================================================
-- 0177  The cold-start guard looked at every depot
-- =====================================================================
-- forces_recert = TRUE. NOT APPLIED when written - the 0169 round was
-- in flight. This gets its own round.
--
-- FOUND: while deciding whether it was safe to run a grid-fixture smoke
-- concurrently with a flagship certification pair. It is not, and this
-- is why.
--
-- twin.ottoq_sim_start_run decides whether a new run needs a cold start:
--
--   SELECT count(*) INTO v_deployed
--     FROM vehicles WHERE current_state = 'deployed'::vehicle_state;
--   IF v_deployed = 0 THEN
--     v_primed := twin.ottoq_sim_prime_deployment(...);
--   END IF;
--
-- There is NO DEPOT FILTER on that count. The guard's own comment says
-- exactly what it is for:
--
--   "A torn-down world is all-offline, and nothing in the demo tick
--    path deploys an offline vehicle, so without this the run can never
--    move. Guarded on the whole fleet being parked: if anything is
--    already deployed, this run is joining a world in motion and must
--    not disturb it."
--
-- "The whole fleet" is read literally - every vehicle in the table,
-- across every depot. So while a flagship run has assets deployed, a
-- run starting at ANY OTHER depot concludes it is "joining a world in
-- motion", skips its cold start, and begins from an all-parked world
-- that the tick path cannot move. Depot A's traffic silently decides
-- whether depot B's run can run at all.
--
-- Same class as 0145 (validator read every run's calendar), 0053 (the
-- sweep for that class) and 0054 (energy orchestrator summed every
-- run's and every depot's sessions): an unscoped read of state that is
-- conceptually scoped.
--
-- WHAT THIS DOES NOT MEAN - the limit of the claim
-- ---------------------------------------------------------------------
-- The CERTIFICATION PATH DOES NOT DEPEND ON THIS BRANCH.
-- ottoq_determinism_pair primes every arm explicitly and unconditionally
-- right after starting it:
--
--   BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
--   EXCEPTION WHEN OTHERS THEN RAISE WARNING ...; END;
--
-- so a cert arm is primed whether or not start_run's guard fires. No
-- canon recorded to date is in question because of this, and this is
-- not a retro-active invalidation of anything. Stated plainly so the
-- finding is not read as bigger than it is.
--
-- What it DOES block is the two-lane cadence (flagship + a second depot
-- concurrently), which is the whole reason the Benchmark depot and the
-- grid fixture exist: any non-cert run, or any future harness that
-- relies on cold start, is coupled to whatever another depot happens to
-- be doing. It is also why a grid smoke must not be fired while a
-- flagship pair is running.
--
-- THE FIX: count only the depot this run is about to move.
-- =====================================================================

DO $do$
DECLARE
  v_src text;
  v_anchor CONSTANT text :=
    '  SELECT count(*) INTO v_deployed FROM vehicles WHERE current_state = ''deployed''::vehicle_state;';
  v_fixed  CONSTANT text :=
    '  /* 0177: only THIS depot. Counting every vehicle in the table let one'||E'\n'||
    '     depot''s traffic decide whether another depot''s run cold-starts, and'||E'\n'||
    '     a run that skips its cold start begins all-parked in a world the'||E'\n'||
    '     tick path cannot move. Same class as 0145/0053/0054. */'||E'\n'||
    '  SELECT count(*) INTO v_deployed FROM vehicles'||E'\n'||
    '   WHERE current_state = ''deployed''::vehicle_state'||E'\n'||
    '     AND home_depot_id = v_scenario.depot_id;';
  v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_run';
  IF v_src IS NULL THEN RAISE EXCEPTION '0177: twin.ottoq_sim_start_run not found'; END IF;

  IF position('0177: only THIS depot' in v_src) > 0 THEN
    RAISE NOTICE '0177: already applied; nothing to do';
    RETURN;
  END IF;

  -- count, not presence
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0177: cold-start anchor occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_anchor, v_fixed);
  EXECUTE v_src;
  RAISE NOTICE '0177: cold-start guard scoped to the run''s own depot';
END
$do$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_cold_start_guard_looked_at_every_depot', true,
        'twin.ottoq_sim_start_run counted deployed vehicles across EVERY depot when deciding whether a new run needs a cold start, so one depot''s traffic decided whether another depot''s run primed - and an unprimed run begins all-parked in a world the tick path cannot move. Now scoped to the run''s own scenario depot. Same class as 0145/0053/0054. forces_recert because it sits on the run-start path and changes which runs prime. Limit of the claim, stated rather than buried: the certification path does not depend on this branch - ottoq_determinism_pair primes every arm explicitly at 0.70 right after starting it - so no recorded canon is in question. What it blocked was the two-lane cadence (flagship + a second depot concurrently), the reason the Benchmark depot and grid fixture exist.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
