-- =====================================================================
-- 0150 — The arm interlock asks which run is running, and gets the wrong
--        answer. It is why no second policy has ever run.
--
-- Finding id: G34
-- Opened:     2026-09-08 22:4x UTC (5:4x PM CT)
-- Found by:   trying to run the first fifo arm in this database's history
--             and being refused by a trigger.
-- Status:     OPEN — root cause is a missing column, fix is not trivial
--
-- ---------------------------------------------------------------------
-- 1. HOW IT SURFACED
-- ---------------------------------------------------------------------
-- 0149 said the next work was to create a baseline arm so 0231's outcome
-- block could be falsified. The harness for that already exists:
--
--   CALL public.ottoq_cert_arm(p_seed, p_policy, p_ab_group, p_ticks,
--                              p_start, p_fault_chargers)
--
-- It takes a policy, runs on the isolated benchmark-crn depot
-- (22222222), resets that depot first, seeds the world from
-- hash(p_seed || p_ab_group || 'wave'), ticks, scores, aborts. Same seed
-- plus same ab_group gives two arms an identical starting world. That is
-- a CRN-paired A/B and it has been sitting there the whole time.
--
-- Arm A (otto_q, seed 909090, 12 ticks) ran: sim_run_id
-- 7cb0f46e-9306-4df2-af98-e566792167ff. Arm B (fifo, same seed, same
-- ab_group) was refused before it started:
--
--   ERROR: arm interlock: vehicle 4992b1fa is held by the arm at stall
--          fc5d1dab until 2026-09-09 04:39:07.598566+00
--          (sim 2026-09-08 22:37:37.149564+00, charging/charging)
--          -- refusing to move it to nowhere.
--   CONTEXT: ottoq_arm_interlock_guard() -> ottoq_benchmark_reset ->
--            ottoq_cert_arm
--
-- Arm A left seven vehicles tethered to the OTTO-CHARGE ARM. Arm B's
-- depot reset is not allowed to move them. The benchmark lane is wedged.
--
-- ---------------------------------------------------------------------
-- 2. THE ROOT CAUSE, WHICH IS NOT THE TRIGGER
-- ---------------------------------------------------------------------
-- public.ottoq_arm_interlock_guard() decides whether a tether is live by:
--
--   v_clock := COALESCE(
--     (SELECT sim_clock_current FROM public.ottoq_sim_runs
--       WHERE status = 'running' ORDER BY started_at DESC NULLS LAST
--       LIMIT 1),
--     now());
--   IF NEW.robotic_tether_until <= v_clock THEN RETURN NEW; END IF;
--
-- It asks "which run is running" and takes whichever answers first. It
-- never asks which run set THIS tether -- because it cannot:
SELECT 'a_tether_columns' AS check, column_name, data_type
FROM information_schema.columns
WHERE table_schema='public' AND table_name='vehicles'
  AND column_name ~ 'tether|robotic'
ORDER BY column_name;
-- Observed: robotic_tether_until, robotic_tether_stall_id,
--           robotic_tether_direction, robotic_tether_phase.
--           NO run id. A run-scoped fact stored without its run.
--
-- That is the whole finding. The trigger is not wrong so much as it is
-- asked a question the schema cannot answer, and it guesses.
--
-- ---------------------------------------------------------------------
-- 3. THE THREE REGIMES, ONLY ONE OF WHICH IS CORRECT
-- ---------------------------------------------------------------------
--   exactly one run running   -> right answer, by luck of there being
--                                only one candidate
--   no run running            -> falls back to now(), i.e. WALL CLOCK,
--                                compared against a deadline stamped in
--                                SIM time. This is what wedged the lane:
--                                the deadline is 2026-09-09 04:39 sim,
--                                wall clock is 2026-09-08 22:39, so
--                                every tether reads live for six more
--                                hours of real time.
--   two runs running          -> takes the most recently STARTED one,
--                                which in a two-lane world is the OTHER
--                                LANE'S clock.
--
-- The guard's own comment names this hazard exactly:
--   "comparing against now() would treat every live tether in a
--    sim-dated world as either eternal or expired."
-- and then the COALESCE fallback does precisely that. So does
-- twin.ottoq_arm_emergency_release, whose comment goes further and calls
-- the wall-clock comparison "the mistake that made an earlier
-- migration's own assertion fail."
--
-- This is the 0145 defect class -- an unscoped read of run-scoped state --
-- but sited in a TRIGGER, where it does not merely slow a query down: it
-- refuses a write.

-- 3a. Reproduce the wedge.
SELECT 'b_wedge' AS check,
       count(*)                              AS tethered_vehicles,
       max(robotic_tether_until)             AS max_deadline_sim,
       now()                                 AS wall_clock,
       (SELECT count(*) FROM public.ottoq_sim_runs WHERE status='running') AS running_runs
FROM public.vehicles WHERE robotic_tether_until IS NOT NULL;

-- ---------------------------------------------------------------------
-- 4. BLAST RADIUS, MEASURED RATHER THAN ASSUMED
-- ---------------------------------------------------------------------
SELECT 'c_arm_use_by_depot' AS check, coalesce(d.slug,'?') AS depot,
       count(*) AS cycles, count(DISTINCT c.sim_run_id) AS runs
FROM twin.arm_cycles c LEFT JOIN public.depots d ON d.id=c.depot_id
GROUP BY d.slug ORDER BY 3 DESC;
-- Observed 2026-09-08:
--   nashville-flagship  27,130 cycles / 765 runs   (26,350 on cert runs)
--   benchmark-crn          842 cycles /  46 runs
--   grid-0169-smoke         90 cycles /  30 runs
--
-- So the arm is heavily exercised inside the certified flagship path.
--
-- WHAT THIS DOES **NOT** SAY, and the distinction matters. It does not
-- say the thirty certification rounds are contaminated. A determinism
-- pair runs its two arms sequentially, so at any instant exactly one run
-- has status='running' -- regime one above, the regime that happens to
-- be correct. The guard has been getting the right clock for the wrong
-- reason.
--
-- It does say two things that are live risks:
--   i.  The two-lane plan (flagship + benchmark concurrently) walks
--       straight into regime three. Every tether comparison in the
--       quieter lane would read the busier lane's clock.
--   ii. Any harness that runs arms back to back with a gap -- which is
--       exactly what an A/B needs -- walks into regime two the moment
--       the first arm sets status to something other than 'running'.
--       ottoq_cert_arm ends with UPDATE ... SET status='aborted'.
--
-- 4a. Neither the pair, the reset, nor the cert arm touches the tether.
SELECT 'd_who_clears_tethers' AS check, p.proname,
       (p.prosrc ~* 'arm_emergency_release|robotic_tether') AS clears_tether
FROM pg_proc p
WHERE p.proname IN ('ottoq_determinism_pair','ottoq_benchmark_reset','ottoq_cert_arm')
ORDER BY 2;
-- Observed: false, false, false. Nothing in the harness releases an arm.
-- The only release path is twin.ottoq_arm_emergency_release, which is
-- documented as an emergency, requires a stated reason, and refuses an
-- unexplained call -- correctly, since "an unexplained release is not a
-- safety record".

-- ---------------------------------------------------------------------
-- 5. WHY THIS HAS NEVER FIRED BEFORE
-- ---------------------------------------------------------------------
-- Because until today nothing ever ran a second arm on the benchmark
-- lane after a first one finished. 0147 measured why: policy='otto_q'
-- for 845 of 845 runs. The A/B harness existed, took a policy parameter,
-- and was never called with a second value. The first time it was, it
-- failed on its second call.
--
-- A capability that has never been exercised is not a capability. It is
-- an untested assertion, and this one was false.
--
-- ---------------------------------------------------------------------
-- 6. THE FIX, AND WHY IT IS NOT BEING RUSHED
-- ---------------------------------------------------------------------
-- The honest fix is a column: vehicles.robotic_tether_run_id, written by
-- whatever sets the tether, read by the guard, so the guard compares the
-- deadline against ITS OWN run's sim clock and treats a tether whose run
-- is no longer running as released. That is:
--
--   - a schema change to public.vehicles, which is in the world
--     fingerprint's blast radius (0137 territory: a column that ends up
--     hashed changes every canon);
--   - a change to a TRIGGER on public.vehicles, in the certified path;
--   - a change to the tether SETTER, wherever it is, which must now
--     supply the run;
--   - and a decision about the 7 rows currently tethered by a run that
--     ended, which have no run id to migrate.
--
-- That is a forces_recert=TRUE migration and it is not being written at
-- the end of a long session to unblock one experiment. It is filed, with
-- its shape stated, and the experiment proceeds through the sanctioned
-- emergency release with a stated reason -- which is what that function
-- exists for and what the error message itself recommends.
--
-- INTERIM, and recorded so it is not mistaken for the fix: releasing the
-- tethers by hand before each arm makes the A/B runnable today and
-- leaves G34 exactly as open as it was.
-- =====================================================================
