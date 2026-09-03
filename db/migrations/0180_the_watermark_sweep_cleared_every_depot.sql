-- =====================================================================
-- 0180  The watermark sweep cleared every depot
-- =====================================================================
-- forces_recert = TRUE. Found by the two-lane probe that 0177 unblocked.
--
-- THE PROBE, AND WHAT IT CAUGHT
-- ---------------------------------------------------------------------
-- A flagship certification pair was fired, and while it was demonstrably
-- mid-flight a grid-fixture smoke was run against a DIFFERENT depot.
-- Solo the smoke takes ~10 s. Concurrently it ran past 60 s and was
-- killed. That is not slowness - pg_stat_activity named it exactly:
--
--   pid 2932935  144 s  IO/DataFileRead   <- the flagship pair
--   pid 2932980   75 s  Lock/transactionid  blocked_by [2932935]  <- the fixture lane
--   pid 2933042    9 s  Lock/transactionid  blocked_by [2932935]  <- ottoq_start_demo_run
--
-- and pg_locks named the row:
--
--   pid 2932980  tuple ExclusiveLock  vehicle_need_profile  page 32 tuple 2
--   pid 2932980  transactionid ShareLock  xid 9596158  NOT GRANTED
--
-- The fixture lane held a tuple lock on vehicle_need_profile and was
-- waiting for the flagship pair's transaction to commit. Note the third
-- row: a demo run, nobody's certification, was blocked by the same
-- transaction. A cert pair currently stalls the demo backend for its
-- entire ~11-minute duration.
--
-- THE CAUSE
-- ---------------------------------------------------------------------
-- public.ottoq_run_boot_draw section 1c, the 0109 watermark sweep:
--
--   UPDATE public.vehicle_need_profile p
--      SET wear_km_applied = NULL, wear_km_applied_run = NULL
--    WHERE p.wear_km_applied_run IS DISTINCT FROM p_sim_run_id
--      AND (p.wear_km_applied IS NOT NULL OR p.wear_km_applied_run IS NOT NULL);
--
-- NO DEPOT FILTER AND NO VEHICLE FILTER. Every other write in that
-- function is scoped - section 1's fleet CTE, 1d's fleet CTE, 1e and 1f
-- all carry `WHERE v.home_depot_id = v_run.depot_id`. This one sweeps
-- the whole table.
--
-- The intent is right and worth keeping: "a watermark the anchor could
-- not reach is the PREVIOUS run's - clear it so the start state is a
-- function of the seed alone, not of run history." Per-run purity is
-- correct. Reaching into OTHER DEPOTS' rows to get it is not: those rows
-- are not this run's history, and touching them takes a row lock that
-- every other depot's run must then queue behind.
--
-- Fifth instance of one defect class, and the first that is a WRITE:
--   0145  the pre-flight validator read every run's calendar
--   0053  the sweep for that class
--   0054  the energy orchestrator summed every run's and depot's sessions
--   0177  the cold-start guard counted every depot's vehicles
--   0180  the watermark sweep CLEARED every depot's rows
--
-- The first four were unscoped READS - wrong answers. This one is an
-- unscoped WRITE, so it does not merely mis-read the world, it serialises
-- every concurrent run in the database behind one transaction. That is
-- why the two-lane cadence has never worked, and 0177 was necessary but
-- not sufficient.
--
-- THE FIX: sweep only the depot this run owns.
--
-- PREDICTION, published before the recertification round fires. The
-- flagship pair currently clears the fixture's and Benchmark's rows as a
-- side effect; after this it will not. Nothing it does to its OWN
-- depot's rows changes. So:
--
--   ALL SIX COLUMNS MUST REPRODUCE ROUND 11 EXACTLY. Any moved hash is
--   0180's and is a defect to REVERT, not a canon to re-baseline.
--
-- The two-lane probe is then re-run: success is both lanes completing,
-- each reproducing its own canon, and NEITHER blocking the other -
-- checked by pg_blocking_pids being empty, not by wall time alone.
-- =====================================================================

DO $do$
DECLARE
  v_src text; v_n int;
  v_anchor CONSTANT text :=
'    UPDATE public.vehicle_need_profile p
       SET wear_km_applied = NULL, wear_km_applied_run = NULL
     WHERE p.wear_km_applied_run IS DISTINCT FROM p_sim_run_id
       AND (p.wear_km_applied IS NOT NULL OR p.wear_km_applied_run IS NOT NULL);';
  v_fixed CONSTANT text :=
'    /* 0180: ONLY THIS DEPOT. Unscoped, this swept vehicle_need_profile
       across every depot, so any two concurrent runs collided on these
       rows and serialised behind one another - the actual reason the
       two-lane cadence never worked, and why a cert pair also stalled
       ottoq_start_demo_run. Other depots the rows belong to are not this
       run''s history. Fifth of the 0145/0053/0054/0177 class and the
       first that is a WRITE. */
    UPDATE public.vehicle_need_profile p
       SET wear_km_applied = NULL, wear_km_applied_run = NULL
      FROM public.vehicles v
     WHERE v.id = p.vehicle_id
       AND v.home_depot_id = v_run.depot_id
       AND p.wear_km_applied_run IS DISTINCT FROM p_sim_run_id
       AND (p.wear_km_applied IS NOT NULL OR p.wear_km_applied_run IS NOT NULL);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_run_boot_draw';
  IF v_src IS NULL THEN RAISE EXCEPTION '0180: ottoq_run_boot_draw not found'; END IF;

  IF position('0180: ONLY THIS DEPOT' in v_src) > 0 THEN
    RAISE NOTICE '0180: already applied; nothing to do'; RETURN;
  END IF;

  -- count, not presence
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0180: watermark-sweep anchor occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_anchor, v_fixed);
  EXECUTE v_src;
  RAISE NOTICE '0180: watermark sweep scoped to the run''s own depot';
END
$do$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_watermark_sweep_cleared_every_depot', true,
        'ottoq_run_boot_draw section 1c cleared wear_km_applied/wear_km_applied_run on vehicle_need_profile with NO depot or vehicle filter, sweeping every depot. Found by the two-lane probe 0177 unblocked: a grid-fixture smoke on a different depot ran past 60 s against a ~10 s solo baseline, and pg_locks showed it holding a tuple lock on vehicle_need_profile while waiting on the flagship pair transaction id - as was an unrelated ottoq_start_demo_run. An unscoped WRITE does not merely mis-read the world, it serialises every concurrent run behind one transaction, which is the real reason the two-lane cadence never worked; 0177 was necessary but not sufficient. Fifth instance of the 0145/0053/0054/0177 class and the first that is a write. Now scoped to the run depot via a join on vehicles. forces_recert because it sits on the run-boot path; prediction published before the round - all six columns must reproduce round 11 exactly, since nothing it does to its own depot changes.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
