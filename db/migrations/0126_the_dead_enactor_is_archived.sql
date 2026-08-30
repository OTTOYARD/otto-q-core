-- migration-version: 20260830234000
-- migration-name:    the_dead_enactor_is_archived
-- 0126 -- disposal of ottoq_enact_cuopt_batch, per the founder's decision rule
-- (2026-08-30): "if we will rebuild better/differently later, then just clear it."
-- The batch enactor's job WAS rebuilt better -- the live cuOpt path is propose/dispose
-- through the deferral pattern (ottoq_cuopt_deferrals one-tick right-of-first-refusal,
-- disposed by decide_tick), which superseded direct batch enactment. The function has
-- been call-dead since the V-campaign cleanup (task record + fresh verification today:
-- zero callers across public/ottoq/twin; repo references are historical migrations and
-- docs only).
--
-- Disposal follows the repo's own convention: RENAME into the ottoq_fn_backup_* corpse
-- namespace rather than DROP -- cleared from the live call namespace, source preserved
-- in pg_proc and in db/fn_current/ for recovery. The live cuOpt machinery
-- (ottoq-cuopt-propose edge function, cuopt_invocation_log, deferrals, l2 proposers)
-- is untouched.

DO $archive$
BEGIN
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_enact_cuopt_batch';
  IF NOT FOUND THEN
    RAISE EXCEPTION '0126 abort: ottoq_enact_cuopt_batch not found (already disposed?)';
  END IF;

  -- Fresh no-caller assert at apply time: any function whose body names it aborts this.
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prokind = 'f' AND n.nspname IN ('public','ottoq','twin')
     AND p.proname <> 'ottoq_enact_cuopt_batch'
     AND position('ottoq_enact_cuopt_batch' in pg_get_functiondef(p.oid)) > 0;
  IF FOUND THEN
    RAISE EXCEPTION '0126 abort: a live function still references ottoq_enact_cuopt_batch';
  END IF;

  ALTER FUNCTION public.ottoq_enact_cuopt_batch(uuid, uuid, timestamp with time zone, bigint, uuid)
    RENAME TO ottoq_fn_backup_enact_cuopt_batch;

  RAISE NOTICE '0126 applied: the dead enactor is archived as ottoq_fn_backup_enact_cuopt_batch.';
END
$archive$;
